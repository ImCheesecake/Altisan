-- CampData.lua: what each character can bring to a camp (objects per profession from the scans'
-- "Camping" categories), the account's campfire, and the Blueprints closest to use.

local _, ns = ...

local Data = {}
ns.CampData = Data

local TIER_SKILL = { 20, 140, 300 }
local COOKING = 185
-- How many objects a campfire holds is the one thing the game doesn't tell an addon, so it's kept
-- by hand.
local CAMPFIRES = {
    { recipe = 1229737, name = "Basic Campfire", holds = 3 },
    { recipe = 1283400, name = "Journeyman Campfire", holds = 5, learn = 90, place = 140 },
    { recipe = 1291341, name = "Expert Campfire", holds = 10, learn = 200, place = 220 },
}
local IS_CAMPFIRE = {}
for _, fire in ipairs(CAMPFIRES) do IS_CAMPFIRE[fire.recipe] = fire end

-- By ID: the category's name is translated ("Lager aufschlagen").
local CAMP_CATEGORIES = { [2454] = true, [2489] = true, [2514] = true, [2529] = true,
                          [2535] = true, [2574] = true, [2591] = true, [2714] = true,
                          [2715] = true, [2716] = true, [2717] = true, [2718] = true }

local function IsCamp(recipeID, skillLine)
    if ns.GATHERING[skillLine] then return true end
    local recipe = ns.db.recipes[recipeID]
    return recipe and CAMP_CATEGORIES[recipe.categoryID] or false
end
Data.IsCamp = IsCamp

function Data.Professions(list)
    local out = ns.ProfessionHolders(list)
    for _, p in ipairs(out) do
        p.objects, p.ids = {}, {}
        p.best = ns.BestHolder(p.holders, { scanned = true, played = true })
        for _, h in ipairs(p.holders) do
            if ns.HasFullList(h.scan) then
                p.scanned = true
                for _, set in ipairs({ h.scan.known or {}, h.scan.unknown or {} }) do
                    for id in pairs(set) do
                        if not IS_CAMPFIRE[id] and IsCamp(id, p.skillLine) then p.ids[id] = true end
                    end
                end
            end
        end
    end
    for _, p in ipairs(out) do
        -- One object for both faction versions (the Faction Banner).
        local byObject = {}
        for id in pairs(p.ids) do
            local recipe = ns.db.recipes[id]
            local name = ns.RecipeName(id, p.skillLine)
            local knowers = {}
            for _, h in ipairs(p.holders) do
                if h.scan and h.scan.known[id] then table.insert(knowers, h) end
            end
            local key = math.min(id, ns.FactionTwin(id) or id)
            local object = byObject[key]
            if not object or (#knowers > 0 and #object.knowers == 0) then
                object = { id = id, name = name, required = ns.RequiredSkill(id, p.skillLine),
                           trivial = recipe and recipe.trivial, knowers = knowers }
                byObject[key] = object
            end
        end
        for _, object in pairs(byObject) do table.insert(p.objects, object) end
        -- By required skill; Herbalism and Skinning have none in the library, so by grey level.
        local function Key(o) return (o.required and o.required > 1 and o.required) or o.trivial or 0 end
        table.sort(p.objects, function(a, b)
            if Key(a) ~= Key(b) then return Key(a) < Key(b) end
            return a.name < b.name
        end)
        p.slots = {}
        if p.skillLine == COOKING then p.slots[1] = { campfire = true, name = CAMPFIRES[1].name } end
        for _, o in ipairs(p.objects) do
            local r = o.required
            if r and r > 1 then
                local tier = r >= 300 and 3 or (r >= 140 and 2 or 1)
                if not p.slots[tier] then p.slots[tier], o.placed = o, true end
            end
        end
        -- Without a required skill in the library, take the tier's: camp objects come at 20, 140
        -- and 300.
        for _, o in ipairs(p.objects) do
            if not o.placed then
                for tier = 1, 3 do
                    if not p.slots[tier] then
                        p.slots[tier], o.placed = o, true
                        if not (o.required and o.required > 1) then o.required = TIER_SKILL[tier] end
                        break
                    end
                end
            end
        end
    end
    local shown = {}
    for _, p in ipairs(out) do
        if #p.objects > 0 or not p.scanned then shown[#shown + 1] = p end
    end
    table.sort(shown, function(a, b) return (a.name or "") < (b.name or "") end)
    return shown
end

function Data.Campfire(list)
    local result = {}
    local cooks = ns.ProfessionHolders(list, function(line) return line == COOKING end)[1]
    result.cook = cooks and ns.BestHolder(cooks.holders, { played = true })
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            if prof.skillLine == COOKING then
                local scan = ns.GetProfessionRecipes(entry.char, COOKING)
                for i, fire in ipairs(CAMPFIRES) do
                    -- Basic comes with Cooking itself, scanned or not.
                    local knows = (i == 1) or (scan and scan.known[fire.recipe])
                    if knows and (not result.current or fire.holds > result.current.holds) then
                        result.current, result.who = fire, { key = entry.key, char = entry.char }
                    end
                end
            end
        end
    end
    for _, fire in ipairs(CAMPFIRES) do
        if not result.current or fire.holds > result.current.holds then result.next = fire break end
    end
    return result
end

function Data.Blueprints(professions, campfire)
    local out = {}
    for _, p in ipairs(professions) do
        for _, o in ipairs(p.objects) do
            if #o.knowers == 0 and o.required and o.required > 20 and p.best then
                local gap = math.max(0, o.required - (p.best.prof.skill or 0))
                out[#out + 1] = { name = o.name, prof = p, who = p.best, gap = gap, required = o.required }
            end
        end
    end
    local fire, cook = campfire.next, campfire.cook
    if fire and cook and fire.learn then
        out[#out + 1] = { name = fire.name, prof = { name = cook.prof.name }, who = cook, required = fire.learn,
                          gap = math.max(0, fire.learn - (cook.prof.skill or 0)), fire = fire }
    end
    table.sort(out, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        return a.name < b.name
    end)
    return out
end
