-- NextUp.lua: the overview's Next up card. A short feed of things worth doing next, worked
-- out from saved data, heaviest first.

local _, ns = ...

local NextUp = {}
ns.NextUp = NextUp

local REACH = 20
local FIRST = 5
local HEADER_HEIGHT = 34
local ROW_GAP = 8

local TEXT = ns.UI.TEXT
local Soft = ns.UI.Soft

local ShortName = ns.UI.ShortName

-- Put the facts an item is made from in its id: a dismissed item must come back when they change.

local RULES = {}

function RULES.shopping(list, add)
    if #ns.db.tracked == 0 and #ns.db.plans == 0 then return end
    local plan = ns.ShoppingPlan(list)
    local open = { "Open Shopping", function() ns.ShowSection("shopping") end }
    for _, c in ipairs(plan.crafts) do
        if c.track and c.status == "ready" then
            add({ id = ("craft:%d:%s:%d"):format(c.track.recipe, c.track.key, c.track.count), weight = 90,
                  title = ("%s can craft %d × %s now"):format(c.crafter, c.track.count, c.name),
                  note = Soft("Tracked on Shopping. Every material is on hand."), action = open })
        end
    end
    for _, m in ipairs(plan.mail) do
        add({ id = "mail:" .. m.from .. ">" .. m.to .. ":" .. table.concat(m.lines, ","), weight = 75,
              title = "Mail from " .. m.from .. " to " .. m.to,
              note = Soft(table.concat(m.lines, ", ") .. "."), action = open })
    end
end

function RULES.stock(list, add)
    if not next(ns.db.stock) then return end
    local G = ns.Gathering
    local byKind, best = {}, {}
    for _, g in ipairs(G.Gatherers(list)) do
        byKind[g.kind] = byKind[g.kind] or {}
        table.insert(byKind[g.kind], g)
    end
    for kind, gatherers in pairs(byKind) do best[kind] = ns.BestHolder(gatherers) end
    local left = ns.ShoppingPlan(list).stock
    for _, kind in ipairs({ "Herbalism", "Mining" }) do
        local g = best[kind]
        local items = {}
        for itemID, s in pairs(g and ns.db.stock or {}) do
            if G.Kind(itemID) == kind and left[itemID].short > 0 then
                items[#items + 1] = { itemID = itemID, have = left[itemID].have, target = s.target }
            end
        end
        table.sort(items, function(a, b) return a.itemID < b.itemID end)
        if #items > 0 then
            local parts, ids = {}, {}
            for i, it in ipairs(items) do
                local name = ns.UI.ItemLabel(it.itemID)
                parts[i] = ("%s %d of %d"):format(name, it.have, it.target)
                ids[i] = it.itemID .. ":" .. it.target
            end
            add({ id = "stock:" .. g.key .. ":" .. table.concat(ids, ","), weight = 40,
                  title = ("Stock up on %s for %s"):format(ns.UI.Count(#items, "material", "materials"), ShortName(g)),
                  note = Soft(table.concat(parts, ", ") .. "."),
                  action = { "Open Gathering", function() ns.GatherView.Open() end } })
        end
    end
end

function RULES.legacy(list, add)
    for line, best in pairs(ns.Legacy.BestPerProfession(list)) do
        local prof = best.prof
        local skill = prof.skill or 0
        local at, toGo = ns.Legacy.Next(line, skill)
        if at and toGo <= REACH then
            local note = ("%s %d of %d, %d to go."):format(prof.name, skill, prof.maxSkill or 0, toGo)
            local cap = prof.maxSkill or 0
            local rank = cap > 0 and ns.RANKS[cap + 75]
            if rank and cap < at then
                note = note .. (" Train %s %s first: the cap is %d."):format(rank, prof.name, cap)
            elseif rank and cap == at then
                note = note .. (" Train %s %s to keep going after %d."):format(rank, prof.name, cap)
            end
            add({ id = ("legacy:%d:%d"):format(line, at), weight = 100 - toGo,
                  title = "Legacy point for " .. ShortName({ key = best.key, char = best.char }), note = Soft(note),
                  action = { "Show recipes", function() ns.ShowCharacter(best.key, line) end } })
        end
    end
end

function RULES.onhand(list, add)
    for _, item in ipairs(ns.RecipesOnHand.Items(list)) do
        local now = item.gap == 0
        add({ id = "onhand:" .. item.itemID .. ":" .. (now and "now" or "later"), weight = now and 72 or 30,
              title = item.name, note = item.who .. Soft(". " .. item.where .. "."),
              action = item.key and { now and "Show recipe" or "Show recipes",
                                      function() ns.ShowCharacter(item.key, item.skillLine) end } })
    end
end

function RULES.trainer(list, add)
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local scan = ns.GetProfessionRecipes(entry.char, prof.skillLine)
            if scan then
                local ready = {}
                for recipeID in pairs(scan.unknown or {}) do
                    if select(2, ns.SkillGap(recipeID, prof.skillLine, prof.skill)) == 0 and ns.RecipeSourceKind(recipeID) == "Trainer"
                        and not ns.Ignore.Is(recipeID) then
                        ready[#ready + 1] = ns.RecipeName(recipeID)
                    end
                end
                if #ready > 0 then
                    table.sort(ready)
                    local shown = { unpack(ready, 1, math.min(3, #ready)) }
                    if #ready > 3 then shown[#shown + 1] = (#ready - 3) .. " more" end
                    add({ id = ("trainer:%s:%d:%d"):format(entry.key, prof.skillLine, #ready), weight = 65,
                          title = ("%s can learn %d %s %s at a trainer"):format(ShortName(entry), #ready, prof.name,
                                                                           ns.UI.Plural(#ready, "recipe", "recipes")),
                          note = Soft(ns.UI.JoinNames(shown) .. ". " .. prof.name .. " " .. (prof.skill or 0) .. "."),
                          action = { "Show recipes", function() ns.ShowCharacter(entry.key, prof.skillLine) end } })
                end
            end
        end
    end
end

function RULES.plan(list, add)
    if not ns.db.window.plan then return end
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local plan = ns.SkillPlan.Cached(list, entry.key, prof.skillLine)
            local step = plan and plan.steps[1]
            if step and step.learned and not next(step.buy) then
                local SP, needs = ns.SkillPlan, {}
                for _, g in ipairs(SP.StepNeeds(plan, step)) do needs[#needs + 1] = g.label .. ": " .. g.short .. "." end
                needs[#needs + 1] = SP.StepWhen(plan, 1)
                add({ id = ("plan:%s:%d:%d:%d"):format(entry.key, prof.skillLine, step.recipeID, step.to), weight = 60,
                      title = ("%s can make %s %s: %s %d to %d"):format(ShortName(entry), ns.RecipeName(step.recipeID, prof.skillLine) or "?",
                          SP.Times(step.make), prof.name, step.from, step.to),
                      note = Soft(table.concat(needs, " ")),
                      action = { "Show plan", function() ns.ShowPlan(entry.key, prof.skillLine) end } })
            end
        end
    end
end

function RULES.cap(list, add)
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local rank = (prof.maxSkill or 0) > 0 and ns.RANKS[prof.maxSkill + 75]
            if rank and (prof.skill or 0) >= prof.maxSkill then
                add({ id = ("cap:%s:%d:%d"):format(entry.key, prof.skillLine, prof.maxSkill), weight = 70,
                      title = ("%s is capped at %s %d"):format(ShortName(entry), prof.name, prof.maxSkill),
                      note = Soft(("Train %s %s to keep going."):format(rank, prof.name)) })
            end
        end
    end
end

function RULES.scan(list, add)
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            if ns.CRAFTING[prof.skillLine] or ns.SECONDARY[prof.skillLine] then
                local scan = ns.GetProfessionRecipes(entry.char, prof.skillLine)
                local title = ("Open %s's %s window once"):format(ShortName(entry), prof.name)
                if not ns.HasFullList(scan) then
                    local note = scan and "Only the recipes it knows were read at login."
                        or "Its recipes haven't been read yet."
                    add({ id = ("scan:%s:%d:never"):format(entry.key, prof.skillLine), weight = 45,
                          title = title, note = Soft(note) })
                elseif scan.skill and prof.skill and prof.skill > scan.skill then
                    add({ id = ("scan:%s:%d:%d"):format(entry.key, prof.skillLine, prof.skill), weight = 50,
                          title = title, note = Soft(("%s went from %d to %d since the last scan, so its recipe list may be out of date.")
                                                         :format(prof.name, scan.skill, prof.skill)) })
                end
            end
        end
    end
end

function RULES.gap(list, add)
    local have, missing, lines, free = {}, {}, {}, {}
    for _, entry in ipairs(list) do
        local primaries = 0
        for _, prof in ipairs(entry.char.professions or {}) do
            if ns.CRAFTING[prof.skillLine] then have[prof.skillLine] = true end
            if prof.kind == "primary" then primaries = primaries + 1 end
        end
        if primaries < 2 then free[#free + 1] = ShortName(entry) end
    end
    for line, name in pairs(ns.CRAFTING) do
        if not have[line] then
            missing[#missing + 1] = name
            lines[#lines + 1] = tostring(line)
        end
    end
    if #missing == 0 or #list == 0 then return end
    table.sort(missing)
    table.sort(lines)
    local note
    if #free == 0 then
        note = Soft("Every character's two profession slots are taken.")
    elseif #free == 1 then
        note = free[1] .. Soft(" has a free profession slot.")
    else
        note = ns.UI.JoinNames(free) .. Soft(" have free profession slots.")
    end
    add({ id = "gap:" .. table.concat(lines, ","), weight = 40, title = "Nobody has " .. ns.UI.JoinNames(missing, "or"), note = note })
end

function RULES.cooldowns(list, add)
    local C, now = ns.Cooldowns, time()
    for _, entry in ipairs(list) do
        for _, c in ipairs(C.Timers(entry.char)) do
            local t = c.timer
            if t.long and t.ends <= now then
                local more = C.MaterialsNote(entry, t, list)
                add({ id = ("cooldown:%s:%s:%d"):format(entry.key, c.key, t.ends), weight = 80,
                      title = ("%s can %s again"):format(ShortName(entry), C.What(t)),
                      note = Soft("Ready since " .. C.When(t.ends, now) .. "." .. (more and (" " .. more) or "")),
                      action = t.skillLine and { "Show recipe", function()
                          ns.ShowCharacter(entry.key, t.skillLine, t.recipes[1])
                      end } })
            end
        end
    end
end

function RULES.bank(list, add)
    for _, entry in ipairs(list) do
        if not entry.char.bank then
            add({ id = "bank:" .. entry.key, weight = 20, title = ("Open the bank on %s once"):format(ShortName(entry)),
                  note = Soft(("Shopping and the item tooltips don't count %s's bank until it has been read once.")
                              :format(ns.UI.CharName(entry.char, entry.key))) })
        end
    end
end

local ORDER = { "shopping", "cooldowns", "stock", "legacy", "onhand", "trainer", "plan", "cap", "scan", "gap", "bank" }

function NextUp.Items(list)
    local played = {}
    for _, entry in ipairs(list) do
        if ns.IsPlayed(entry.key) then played[#played + 1] = entry end
    end
    local all, made = {}, {}
    local function add(item)
        if made[item.id] then return end
        made[item.id] = true
        all[#all + 1] = item
    end
    for _, name in ipairs(ORDER) do
        local ok, err = pcall(RULES[name], played, add)
        if not ok then geterrorhandler()(("Altisan Next up (%s): %s"):format(name, tostring(err))) end
    end

    local dismissed = ns.db.dismissed.items
    for id in pairs(dismissed) do
        if not made[id] then dismissed[id] = nil end
    end
    local items, hidden = {}, 0
    for _, item in ipairs(all) do
        if dismissed[item.id] then hidden = hidden + 1 else items[#items + 1] = item end
    end
    table.sort(items, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.id < b.id
    end)
    return items, hidden
end

local card
local expanded = false
local last = { items = {}, hidden = 0, width = 0 }
local FOOTER_HEIGHT = 32
local BAR_ROOM = 14
local LIST_PAD = 4

local function Measure(item, inner)
    local m = card.measure
    local buttonWidth = 0
    if item.action then
        m.button:SetKind("primary", item.action[1])
        buttonWidth = m.button:GetWidth() + 10
    end
    item.textWidth = inner - 24 - 10 - buttonWidth
    local UI = ns.UI
    item.height = math.max(44, math.ceil(ROW_GAP + UI.TextHeight(item.title, item.textWidth, "GameFontHighlight", 2) + 4
        + UI.TextHeight(item.note, item.textWidth, "GameFontHighlightSmall", 2) + ROW_GAP))
end

local function InitRow(row, item)
    local UI = ns.UI
    if not row.made then
        row.made = true
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.title:SetPoint("TOPLEFT", 0, -ROW_GAP)
        row.title:SetJustifyH("LEFT")
        row.title:SetSpacing(2)
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.note:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
        row.note:SetJustifyH("LEFT")
        row.note:SetSpacing(2)
        row.line = UI.Divider(row)
        row.line:SetPoint("TOPLEFT")
        row.line:SetPoint("TOPRIGHT")
        row.dismiss = UI.SquareButton(row, "×", "Dismiss until this changes")
        row.dismiss:SetPoint("RIGHT", 0, 0)
        row.dismiss:SetScript("OnClick", function()
            if not row.item then return end
            ns.db.dismissed.items[row.item.id] = true
            ns.RefreshWindow()
        end)
        row.button = UI.Button(row, "")
        row.button:SetPoint("RIGHT", row.dismiss, "LEFT", -10, 0)
        row.button:SetScript("OnClick", function()
            local action = row.item and row.item.action
            if action then action[2]() end
        end)
    end
    row.item = item
    row:SetHeight(item.height)
    row.line:SetShown(not item.first)
    row.button:SetShown(item.action ~= nil)
    if item.action then row.button:SetKind("primary", item.action[1]) end
    row.title:SetWidth(item.textWidth)
    row.note:SetWidth(item.textWidth)
    row.title:SetText(item.title)
    row.note:SetText(item.note or "")
end

function NextUp.Refresh(list, width, layoutOnly, maxHeight)
    width = width or 600
    local inner = width - 32 - BAR_ROOM
    local remeasure = not layoutOnly
    last.items, last.hidden = ns.UI.Data("nextup", layoutOnly, function() return NextUp.Items(list) end)
    local items = last.items
    local count = expanded and #items or math.min(#items, FIRST)
    local shown = {}
    for i = 1, count do
        local item = items[i]
        if remeasure or not item.height then Measure(item, inner) end
        item.first = i == 1
        shown[i] = item
    end
    last.width = width

    local more = #items - FIRST
    local footer = (more > 0 or last.hidden > 0) and FOOTER_HEIGHT or 0
    ns.UI.SetShowMore(card.toggle, more, expanded)
    card.restore:SetShown(last.hidden > 0)
    if last.hidden > 0 then
        card.restore:SetKind("quiet", ("Show %d dismissed"):format(last.hidden))
        card.restore:ClearAllPoints()
        if more > 0 then
            card.restore:SetPoint("LEFT", card.toggle, "RIGHT", 10, 0)
        else
            card.restore:SetPoint("BOTTOMLEFT", 16, 10)
        end
    end

    local content = 0
    for _, item in ipairs(shown) do content = content + item.height end
    local room = (maxHeight or math.huge) - (HEADER_HEIGHT - 4) - LIST_PAD - footer - 10
    local listHeight = math.max(0, math.min(content, room))
    if #shown > 0 and listHeight < 44 then listHeight = math.min(content, 44) end
    -- UI.PlaceList keeps 4 px free under the list: add them back, or a tiny scroll bar shows.
    card.listFrame:SetHeight(math.max(1, listHeight + LIST_PAD))
    card.listFrame:SetShown(#shown > 0)
    if not (layoutOnly and card.list.box:HasDataProvider()) then
        card.list.box:SetDataProvider(CreateDataProvider(shown), ScrollBoxConstants.RetainScrollPosition)
    end

    card.count:SetText(#items > 0 and (count .. " of " .. #items) or "")
    card.empty:SetShown(#items == 0)
    local height = HEADER_HEIGHT - 4 + listHeight + LIST_PAD + footer + 10
    if #items == 0 then
        card.empty:SetWidth(inner)
        height = HEADER_HEIGHT + card.empty:GetStringHeight() + 18 + footer
    end
    card:SetHeight(height)
    card:SetShown(#list > 0)
    return #list > 0 and height or 0
end

function NextUp.Build(parent)
    local UI = ns.UI
    card = UI.TitledCard(parent, "Next up")
    card.count = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.count:SetPoint("BOTTOMLEFT", card.title, "BOTTOMRIGHT", 10, 0)
    card.empty = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.empty:SetPoint("TOPLEFT", 16, -HEADER_HEIGHT)
    card.empty:SetJustifyH("LEFT")
    card.empty:SetText("Nothing to do right now. Dismissed suggestions come back when what they're about changes.")

    card.listFrame = CreateFrame("Frame", nil, card)
    card.listFrame:SetPoint("TOPLEFT", 16, -(HEADER_HEIGHT - 4))
    card.listFrame:SetPoint("TOPRIGHT", -10, -(HEADER_HEIGHT - 4))
    card.list = UI.ScrollList(card.listFrame, function(item) return item.height end, InitRow)
    UI.PlaceList(card.list, 0)

    card.measure = { button = UI.Button(card, "") }
    card.measure.button:Hide()

    card.toggle = UI.Button(card, "", "quiet")
    card.toggle:SetPoint("BOTTOMLEFT", 16, 10)
    card.toggle:SetScript("OnClick", function()
        expanded = not expanded
        ns.RefreshWindow()
    end)
    card.restore = UI.Button(card, "", "quiet")
    card.restore:SetScript("OnClick", function()
        wipe(ns.db.dismissed.items)
        ns.RefreshWindow()
    end)
    NextUp.card = card
    return card
end
