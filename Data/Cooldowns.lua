-- Cooldowns.lua: profession cooldowns per character, saved as the time each timer ends. The window
-- scan finds them (recipes that share a timer end at the same second); the Salt Shaker is an item.

local _, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

local LONG = 3 * 3600
local SAME = 2
local SALT_SHAKER = 15846   -- Leatherworking's cooldown is on this item, not on a recipe

local function Overlaps(a, b)
    local set = {}
    for _, id in ipairs(a) do set[id] = true end
    for _, id in ipairs(b) do if set[id] then return true end end
    return false
end

function Cooldowns.FromScan(char, skillLine, known)
    if not C_TradeSkillUI.GetRecipeCooldown then return end
    local now, found = time(), {}
    for recipeID in pairs(known) do
        local left = C_TradeSkillUI.GetRecipeCooldown(recipeID)
        if left and left > 0 then
            local ends = now + math.floor(left + 0.5)
            local group
            for _, g in ipairs(found) do
                if math.abs(g.ends - ends) <= SAME then group = g break end
            end
            if not group then
                group = { ends = ends, left = 0, recipes = {} }
                found[#found + 1] = group
            end
            group.recipes[#group.recipes + 1] = recipeID
            group.left = math.max(group.left, left)
        end
    end
    char.cooldowns = char.cooldowns or {}
    for _, g in ipairs(found) do
        table.sort(g.recipes)
        -- GetRecipeCooldown gives what's left, not the length; a craft rescans right away, so it's
        -- nearly the whole timer.
        local long = g.left > LONG
        for key, t in pairs(char.cooldowns) do
            if t.recipes and Overlaps(t.recipes, g.recipes) then
                long = long or t.long
                char.cooldowns[key] = nil
            end
        end
        char.cooldowns["recipe:" .. g.recipes[1]] = { ends = g.ends, recipes = g.recipes, skillLine = skillLine,
                                                      long = long or nil }
    end
end

function Cooldowns.ReadItems(char)
    if not char then return end
    char.cooldowns = char.cooldowns or {}
    local key = "item:" .. SALT_SHAKER
    if (C_Item.GetItemCount(SALT_SHAKER, true) or 0) == 0 then
        char.cooldowns[key] = nil
        return
    end
    local start, duration = C_Container.GetItemCooldown(SALT_SHAKER)
    -- Under a minute is the global cooldown, not the item's own.
    if start and duration and start > 0 and duration > 60 then
        char.cooldowns[key] = { ends = time() + math.floor(start + duration - GetTime() + 0.5), item = SALT_SHAKER,
                                long = duration > LONG or nil }
    end
end

function Cooldowns.Timers(char)
    local has, out = {}, {}
    for _, prof in ipairs(char and char.professions or {}) do has[prof.skillLine] = true end
    for key, t in pairs(char and char.cooldowns or {}) do
        if t.item or has[t.skillLine] then out[#out + 1] = { key = key, timer = t } end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function Cooldowns.ForRecipe(char, recipeID)
    for _, c in ipairs(Cooldowns.Timers(char)) do
        for _, id in ipairs(c.timer.recipes or {}) do
            if id == recipeID then return c.timer end
        end
    end
end

local function SharedVerb(recipes)
    if #recipes < 2 then return end
    local verb
    for _, id in ipairs(recipes) do
        local word = (ns.RecipeName(id) or ""):match("^(.-):")
        if not word or (verb and word ~= verb) then return end
        verb = word
    end
    return verb:lower()
end

function Cooldowns.What(t)
    if t.item then return "use the " .. ns.UI.ItemLabel(t.item) end
    local verb = SharedVerb(t.recipes)
    if verb then return verb end
    local names = {}
    for i, id in ipairs(t.recipes) do names[i] = ns.RecipeName(id) end
    return "make " .. ns.UI.JoinNames(names, "or")
end

local function Midnight(t)
    local d = date("*t", t)
    ---@cast d osdateparam
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end

function Cooldowns.When(ends, now)
    now = now or time()
    local days = math.floor((Midnight(ends) - Midnight(now)) / 86400 + 0.5)
    local day
    if days == 0 then day = "today"
    elseif days == 1 then day = "tomorrow"
    elseif days == -1 then day = "yesterday"
    elseif days > 1 and days < 7 then day = date("%A", ends)
    else day = date("%d %B", ends):gsub("^0", "") end
    return day .. " at " .. date("%H:%M", ends)
end

function Cooldowns.MaterialsNote(entry, t, list)
    local verb = SharedVerb(t.recipes or {})
    local function ForRecipeName(id)
        if not verb then return "" end
        return " for " .. (ns.RecipeName(id) or ""):gsub("^.-:%s*", "")
    end
    local senders = ns.Bags.CanReach(list, entry.char, entry.key)
    local fallback
    for _, id in ipairs(t.recipes or {}) do
        local reagents = ns.Reagents(id, t.skillLine)
        local missing, holders, covered = {}, {}, #reagents > 0
        for _, r in ipairs(reagents) do
            local short = r[2] - ns.Bags.Held(entry.char, r[1])
            if short > 0 then
                missing[#missing + 1] = ns.UI.ItemLabel(r[1])
                local best
                for _, other in ipairs(senders) do
                    if ns.Bags.Held(other.char, r[1]) >= short then best = other break end
                end
                if best then holders[ns.UI.ShortName(best)] = true else covered = false end
            end
        end
        if covered and #missing == 0 then return "Has the materials" .. ForRecipeName(id) .. "." end
        if covered and not fallback then
            local who = {}
            for name in pairs(holders) do who[#who + 1] = name end
            table.sort(who)
            fallback = ("%s %s the %s%s."):format(ns.UI.JoinNames(who), ns.UI.Plural(#who, "holds", "hold"),
                                                  ns.UI.JoinNames(missing), ForRecipeName(id))
        end
    end
    return fallback
end
