-- GatherView.lua: the Gathering page. On the left the account's herbs and ore (what's short, what's
-- in stock) or a zone's; on the right the picked material, the zone, or the account's gatherers.

local _, ns = ...

local View = {}
ns.GatherView = View

local UI = ns.UI
local Gather = ns.Gathering
local PAGE, TEXT = UI.PAGE, UI.TEXT
local Color, Soft, Gold = UI.ColorText, UI.Soft, UI.Gold
local ROW_HEIGHT, NESTED_HEIGHT, MESSAGE_HEIGHT = 22, 26, 40
local CONTROL_ROW = 32
local PANE_WIDTH, PANE_GAP = PAGE.paneWidth, PAGE.paneGap
local SEARCH_WIDTH, SEARCH_MIN, MENU_WIDTH, CONTINENT_WIDTH, MENU_ROW = 200, 120, 300, 200, 24
local MAX_FOUND, MAX_USES, ZONES_SHOWN = 30, 6, 4
local NO_ICON = 134400
local KINDS = { "Herbalism", "Mining" }

local state = { mode = "keep", open = {}, search = "" }
local panel, current, last = nil, nil, {}

local WORDS = {
    Herbalism = { title = Gather.TITLE.Herbalism, count = "herbs", countOne = "herb", here = "Grows here", where = "Grows in", is = "grow", one = "grows",
                  nobody = "No one on your account gathers herbs.", who = "Who gathers it", can = "can gather herbs here",
                  bring = "For the herbs, bring %s.", also = "%s also gathers your herbs, so one trip covers both." },
    Mining = { title = Gather.TITLE.Mining, count = "ore and stone", countOne = "ore and stone", here = "Mined here", where = "Mined in", is = "are mined",
               one = "is mined", nobody = "No one on your account mines.", who = "Who mines it", can = "can mine here",
               bring = "For the ore, bring %s.", also = "%s also mines your ore, so one trip covers both." },
}
local OTHER = { Herbalism = "Mining", Mining = "Herbalism" }

local ItemName = UI.ItemLabel

local function ZoneNames(mapIDs, max)
    local names = {}
    for i, mapID in ipairs(mapIDs) do
        if max and i > max then break end
        names[i] = Gather.ZoneName(mapID)
    end
    return names
end

local function ItemNames(itemIDs)
    local names = {}
    for i, itemID in ipairs(itemIDs) do names[i] = ItemName(itemID) end
    return names
end

local function Name(g) return UI.ShortName(g.char, g.key) end

local function GatherersNote(s)
    local g = s.gatherers
    if #g == 0 then return WORDS[s.kind].nobody:lower():gsub("%.$", "") end
    if #g == 1 then return ("%s, %s %d"):format(Name(g[1]), g[1].prof.name or s.kind, g[1].prof.skill or 0) end
    local names = {}
    for i, one in ipairs(g) do names[i] = Name(one) end
    return UI.JoinNames(names)
end

local function PerKind(counts)
    local parts = {}
    for _, kind in ipairs(KINDS) do
        local n = counts[kind] or 0
        if n > 0 then parts[#parts + 1] = UI.Count(n, WORDS[kind].countOne, WORDS[kind].count) end
    end
    return table.concat(parts, ", ")
end

local function ZoneChoices(here, continent, sections)
    local out = {}
    if here and Gather.Continent(here) == continent.mapID then out[1] = here end
    for _, mapID in ipairs(continent.zones) do if mapID ~= here then out[#out + 1] = mapID end end
    local shortIn = {}
    for _, s in ipairs(sections) do
        for _, row in ipairs(s.short) do
            for _, mapID in ipairs(Gather.Zones(row.itemID)) do
                shortIn[mapID] = shortIn[mapID] or {}
                table.insert(shortIn[mapID], row.itemID)
            end
        end
    end
    return out, shortIn
end

local function Compute(list)
    local d = { list = list, plan = ns.ShoppingPlan(list) }
    d.sections = Gather.Stock(list, d.plan)
    d.byKind, d.rowOf, d.short, d.inStock = {}, {}, {}, {}
    for _, s in ipairs(d.sections) do
        d.byKind[s.kind] = s
        d.short[s.kind], d.inStock[s.kind] = #s.short, #s.inStock
        for _, row in ipairs(s.short) do d.rowOf[row.itemID] = row end
        for _, row in ipairs(s.inStock) do d.rowOf[row.itemID] = row end
    end
    d.totalShort, d.totalStock = d.short.Herbalism + d.short.Mining, d.inStock.Herbalism + d.inStock.Mining
    d.buy = {}
    for _, b in ipairs(d.plan.buy) do d.buy[b.itemID] = b end
    d.here = Gather.PlayerZone()
    d.continents = Gather.Continents()
    local mine = state.continent or Gather.Continent(d.here)
    d.continent = d.continents[1]
    for _, c in ipairs(d.continents) do if c.mapID == mine then d.continent = c end end
    d.zones, d.shortIn = {}, {}
    if d.continent then d.zones, d.shortIn = ZoneChoices(d.here, d.continent, d.sections) end
    d.zone = state.zone or d.here
    if d.zone then d.zoneData = Gather.Zone(d.zone, d.sections) end
    if d.here then d.hereData = d.here == d.zone and d.zoneData or Gather.Zone(d.here, d.sections) end
    d.held = {}
    if d.zoneData then
        for _, kind in ipairs(KINDS) do
            for _, r in ipairs(d.zoneData[kind]) do d.held[r.itemID] = ns.Bags.Holders(r.itemID, list) end
        end
    end
    return d
end

local function RowNote(row)
    local note = ("%d of %d"):format(row.have, row.want)
    if not row.crafts then return note end
    if #row.crafts == 1 then return note .. " for " .. row.crafts[1].name end
    return note .. " for tracked crafts"
end

local function Header(rows, key, title, note, count, defaultOpen, nested)
    local open = state.open[key]
    if open == nil then open = defaultOpen end
    rows[#rows + 1] = { header = title, note = note, count = count, fold = key, open = open, nested = nested, first = #rows == 0 }
    return open
end

local function Material(rows, itemID, note)
    rows[#rows + 1] = { itemID = itemID, note = note }
end

local function TextRow(rows, text)
    rows[#rows + 1] = { line = text }
end

local function Found(rows, search)
    local needle = search:lower()
    local found = {}
    for _, itemID in ipairs(Gather.Materials()) do
        local name = UI.ItemName(itemID, UI.RedrawWindow)
        if name and name:lower():find(needle, 1, true) then found[#found + 1] = { itemID = itemID, name = name } end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    Header(rows, "found", "Found", "looking one up doesn't add it to this page", tostring(#found), true)
    for i = 1, math.min(#found, MAX_FOUND) do
        local row = current.rowOf[found[i].itemID]
        Material(rows, found[i].itemID, row and RowNote(row) or "")
    end
    if #found == 0 then TextRow(rows, Soft("No herb or ore by that name.")) end
end

local function SpreadText(spread, kind)
    local w, zones = WORDS[kind], ZoneNames(spread.zones)
    if spread.covers == spread.total then
        if spread.total == 1 then return Soft(("It %s in %s."):format(w.one, UI.JoinNames(zones))) end
        return Soft(("All %d %s in %s."):format(spread.total, w.is, UI.JoinNames(zones)))
    end
    local text = ("%d of the %d %s in %s."):format(spread.covers, spread.total, w.is, zones[1])
    for _, lack in ipairs(spread.lacking) do
        text = text .. (" %s %s in %s."):format(ItemName(lack.itemID), w.one, UI.JoinNames(ZoneNames(lack.zones)))
    end
    return Soft(text)
end

local function KeepRows(rows, d)
    local any = false
    for _, s in ipairs(d.sections) do
        if #s.short + #s.inStock > 0 then
            any = true
            if Header(rows, "kind" .. s.kind, WORDS[s.kind].title, GatherersNote(s), #s.short .. " short", true) then
                local forCrafts = false
                for _, row in ipairs(s.short) do
                    Material(rows, row.itemID, RowNote(row))
                    forCrafts = forCrafts or row.crafts ~= nil
                end
                if s.spread then TextRow(rows, SpreadText(s.spread, s.kind)) end
                if #s.gatherers == 0 and forCrafts then
                    TextRow(rows, Soft("What tracked crafts need is on Shopping's To buy already."))
                end
                if #s.inStock > 0 and Header(rows, "stock" .. s.kind, #s.inStock .. " in stock", "at or above your target", "", false, true) then
                    for _, row in ipairs(s.inStock) do Material(rows, row.itemID, RowNote(row)) end
                end
            end
        end
    end
    if not any then
        TextRow(rows, Soft("Nothing to gather yet. Find a herb or ore to keep it in stock, or track a craft on Shopping."))
    end
end

local function ZoneRows(rows, d)
    local z = d.zoneData
    if not z then
        TextRow(rows, Soft("Altisan can't tell which zone you're in. Pick one above."))
        return
    end
    for _, kind in ipairs(KINDS) do
        local items = z[kind]
        if #items > 0 and Header(rows, "zone" .. kind, WORDS[kind].here, GatherersNote(d.byKind[kind]), tostring(#items), true) then
            for _, r in ipairs(items) do
                local held = d.held[r.itemID] or 0
                Material(rows, r.itemID, r.row and RowNote(r.row) or (held > 0 and ("you have %d"):format(held) or ""))
            end
        end
    end
    if #z.Herbalism + #z.Mining == 0 then
        TextRow(rows, Soft("No herbs or ore in this zone in the addon's data."))
    elseif d.totalShort > 0 then
        local here = z.here.Herbalism + z.here.Mining
        local text
        if d.totalShort == 1 then
            text = UI.Plural(here, "The one you're short of is here.", "The one you're short of isn't here.")
        elseif here == 0 then
            text = ("None of the %d you're short of are here."):format(d.totalShort)
        else
            text = ("%d of the %d you're short of %s here: %s."):format(here, d.totalShort, UI.Plural(here, "is", "are"), PerKind(z.here))
        end
        TextRow(rows, Soft(text))
    end
end

local function Rows(d)
    local rows = {}
    if state.search ~= "" then
        Found(rows, state.search)
    elseif state.mode == "zone" then
        ZoneRows(rows, d)
    else
        KeepRows(rows, d)
    end
    return rows
end

local function GatherFoldOptions(data)
    return { x = data.nested and 24 or 4, title = data.header, note = data.note, count = data.count,
             open = data.open, line = not data.nested, width = last.listWidth }
end

local function ItemLabel(itemID, size, gap)
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or NO_ICON
    return ("|T%s:%d:%d|t%s%s"):format(icon, size or 16, size or 16, gap or "  ", ItemName(itemID))
end

local function ItemNote(data) return Color(TEXT.light, data.note or "") end

local ITEM_PAD = 8
local function ItemTextHeight(data)
    return UI.PairHeight(ItemLabel(data.itemID), ItemNote(data), last.listWidth - 2 * ITEM_PAD, "GameFontHighlight", "GameFontHighlightSmall")
end

local function Extent(data)
    if data.header then
        local extra = UI.FoldNoteExtra(GatherFoldOptions(data), last.listWidth)
        return (data.nested and NESTED_HEIGHT or UI.HeadingExtent(data.first)) + extra
    end
    if data.line then return data.height or MESSAGE_HEIGHT end
    if not data.itemID then return ROW_HEIGHT end
    return math.max(ROW_HEIGHT, math.ceil(ItemTextHeight(data) + ITEM_PAD))
end

local function OnGatherRowClick(row)
    local data = row.data
    if not data then return end
    if data.fold then
        state.open[data.fold] = not data.open
        View.Redraw()
    elseif data.itemID then
        state.picked = state.picked ~= data.itemID and data.itemID or nil
        state.allPlaces, state.allZones = nil, nil
        View.Redraw()
    end
end

local function FillGatherRow(row, data)
    row.data = data
    row.fold:SetShown(data.header ~= nil)
    row.name:SetShown(data.itemID ~= nil)
    row.note:SetShown(data.itemID ~= nil)
    row.line:SetShown(data.line ~= nil)
    row.picked:SetShown(data.itemID ~= nil and data.itemID == state.picked)
    row:EnableMouse(data.line == nil)
    row:SetHeight(Extent(data))
    if data.header then
        row.fold:Set(GatherFoldOptions(data))
    elseif data.itemID then
        row.name:SetText(ItemLabel(data.itemID))
        row.note:SetText(ItemNote(data))
        local under = UI.FitPair(row.name, row.note, last.listWidth - 2 * ITEM_PAD)
        local top = math.floor((row:GetHeight() - ItemTextHeight(data)) / 2)
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", ITEM_PAD, -top)
        row.note:ClearAllPoints()
        if under then
            row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", UI.PAIR_GAP, -2)
        else
            row.note:SetPoint("TOPRIGHT", -ITEM_PAD, -top)
        end
    else
        row.line:SetWidth(last.listWidth - 24)
        row.line:SetText(data.line)
    end
end

local function InitGatherRow(row, data)
    if not row.made then
        row.made = true
        row.picked = UI.RoundedBox(row, 6)
        row.picked:SetFill(UI.C.selected)
        UI.RoundedHover(row, 6)
        row.note = UI.Text(row, "GameFontHighlightSmall", 0)
        row.name = UI.Text(row, "GameFontHighlight", 0)
        row.line = UI.Text(row)
        row.line:SetPoint("TOPLEFT", 8, -6)
        row.fold = UI.FoldHeader(row)
        row:SetScript("OnClick", OnGatherRowClick)
        UI.ItemHover(row, function(self) return self.data and self.data.itemID end)
    end
    FillGatherRow(row, data)
end

local function BackLabel(d)
    if state.mode == "zone" and state.search == "" and d.zoneData then return "Back to " .. Gather.ZoneName(d.zoneData.mapID) end
    return "Back to your gatherers"
end

local function HeldText(itemID, list, onPage)
    local total, places = ns.Bags.Holders(itemID, list)
    local text
    if total == 0 then
        text = "You have none."
    elseif #places == 1 then
        local p = places[1]
        text = p.word and ("%s has %d in %s."):format(p.name, total, p.word) or ("%s has %d."):format(p.name, total)
    else
        text = ("You have %d: %s."):format(total, (ns.Bags.HeldText(itemID, list, { sep = ", " })))
    end
    if not onPage then text = text .. " Looking it up doesn't add it to this page." end
    return Soft(text)
end

local function OnToBuyText()
    return Soft(Gather.InTracker() and "They're on Shopping's To buy, not in the quest tracker." or "They're on Shopping's To buy.")
end

local function CraftBlocks(blocks, d, itemID, crafts)
    if #crafts == 0 then return end
    local b = d.buy[itemID]
    local short = b and (b.count - (b.stock or 0)) or 0
    local need, lines = 0, {}
    for i, c in ipairs(crafts) do
        need = need + c.need
        local who = ns.db.characters[c.key]
        lines[i] = ("%s's %d %s %s %d"):format(who and UI.ShortName(who, c.key) or c.key, c.count, c.name,
            UI.Plural(c.count, "needs", "need"), c.need)
    end
    if short > 0 and short < need then lines[#lines] = lines[#lines] .. ", " .. Color(TEXT.amber, short .. " short") end
    lines[#lines] = lines[#lines] .. "."
    blocks:Heading("For tracked crafts")
    blocks:Text(table.concat(lines, "\n"), 4)
    if short > 0 then blocks:Text(OnToBuyText(), 4) end
end

local function WhoBlocks(blocks, d, itemID)
    local kind = Gather.Kind(itemID)
    if not kind then return end
    local s = d.byKind[kind]
    blocks:Heading(WORDS[kind].who)
    if #s.gatherers == 0 then
        blocks:Text(WORDS[kind].nobody, 4)
        return
    end
    local parts = {}
    for i, g in ipairs(s.gatherers) do parts[i] = ("%s, %s %d."):format(Name(g), g.prof.name or kind, g.prof.skill or 0) end
    local other = OTHER[kind]
    if #d.byKind[other].short > 0 then
        for _, g in ipairs(d.byKind[other].gatherers) do
            for _, mine in ipairs(s.gatherers) do
                if mine.key == g.key then parts[#parts + 1] = WORDS[other].also:format(Name(g)) end
            end
        end
    end
    blocks:Text(table.concat(parts, " "), 4)
end

local function UseBlocks(blocks, itemID, list, crafts)
    local users = ns.ItemUses.Analyze(itemID, list)
    local tracked = {}
    for _, c in ipairs(crafts) do tracked[c.recipe] = true end
    local byChar, order = {}, {}
    for _, u in ipairs(users or {}) do
        for _, recipeID in ipairs(u.known) do
            if not tracked[recipeID] then
                local key = u.entry.key
                if not byChar[key] then
                    byChar[key] = { entry = u.entry, names = {} }
                    order[#order + 1] = key
                end
                table.insert(byChar[key].names, ns.RecipeName(recipeID))
            end
        end
    end
    if #order == 0 then return end
    local lines = {}
    for i, key in ipairs(order) do
        local names = byChar[key].names
        table.sort(names)
        local shown = {}
        for j = 1, math.min(#names, MAX_USES) do shown[j] = names[j] end
        lines[i] = UI.ShortName(byChar[key].entry) .. ": " .. table.concat(shown, ", ")
            .. (#names > MAX_USES and Soft((" and %d more"):format(#names - MAX_USES)) or "")
    end
    blocks:Heading("Used for")
    blocks:Text(table.concat(lines, "\n"), 4)
end

local function KeepBlocks(blocks, d, itemID)
    blocks:Heading("Keep in stock")
    local target = Gather.Target(itemID)
    local left = d.plan.stock[itemID]
    if target and left then
        local note = left.short > 0 and Color(TEXT.amber, left.short .. " short") or Color(TEXT.green, "enough")
        blocks[#blocks + 1] = { stepper = target, min = 1, note = note, gap = 6,
                                onChange = function(delta) Gather.Change(itemID, delta) end }
        local buttons = { { label = "Stop keeping in stock", onClick = function() Gather.Keep(itemID, nil) end } }
        local on = Gather.Buys(itemID)
        if on or left.short > 0 then
            buttons[2] = { label = on and "Remove from shopping list" or "Add to shopping list", kind = on and "primary" or "quiet",
                           onClick = function() Gather.SetBuy(itemID, not on) end }
        end
        blocks:Buttons(buttons)
        if on and Gather.InTracker() then blocks:Text(OnToBuyText(), 4) end
    else
        blocks:Buttons({ { label = "Keep in stock", onClick = function() Gather.Keep(itemID, Gather.START) end } }, 4)
    end
end

local function AuctionBlocks(blocks, d, itemID)
    local price = ns.AH.Available() and ns.AH.GetPrice(itemID)
    if not price then return end
    local b = d.buy[itemID]
    local text = UI.Money(price) .. " each"
    if b and b.count > 0 then text = text .. (", %d for %s"):format(b.count, UI.Money(price * b.count)) end
    blocks:Heading("Auction house")
    blocks:Text(text, 4)
end

local RefreshPane

local function SourceBlocks(blocks, itemID)
    local zones = Gather.Zones(itemID)
    if #zones > 0 then
        blocks:Heading(WORDS[Gather.Kind(itemID)].where .. ", most nodes first")
        local here, all = Gather.PlayerZone(), #zones <= ZONES_SHOWN + 1 or state.allZones == itemID
        local lines = {}
        for i, mapID in ipairs(zones) do
            if all or i <= ZONES_SHOWN or mapID == here then
                lines[#lines + 1] = Gather.ZoneName(mapID) .. (mapID == here and Soft(" (you're here)") or "")
            end
        end
        blocks:Text(table.concat(lines, "\n"), 4)
        if #zones > ZONES_SHOWN + 1 then
            local open = state.allZones == itemID
            blocks:Buttons({ { label = UI.ShowMoreLabel(#zones - #lines, open), kind = "quiet", onClick = function()
                state.allZones = not open and itemID or nil
                RefreshPane(true)
            end } })
        end
    end
    local vendor = ns.Places.Vendors(itemID)
    if vendor then
        blocks:Heading("Sold by")
        if #vendor.places > 0 then
            blocks[#blocks + 1] = { places = vendor.places, total = #vendor.places, expanded = state.allPlaces == itemID, gap = 4 }
        else
            blocks:Text(Soft("Many vendors sell it."), 4)
        end
        if vendor.price then blocks:Text(Soft(UI.Money(vendor.price) .. " each"), 2) end
    end
    local names, chance = Gather.Drops(itemID)
    if #names > 0 then
        blocks:Heading("Drops from")
        local about = chance < 1 and "under 1%" or ("about %d%%"):format(math.floor(chance + 0.5))
        blocks:Text(table.concat(names, ", ") .. Soft(", " .. about), 4)
    end
end

local function MaterialBlocks(d, itemID)
    local blocks = UI.Blocks()
    blocks:Buttons({ { label = BackLabel(d), onClick = function()
        state.picked = nil
        View.Redraw(true)
    end } })
    blocks:Text(ItemLabel(itemID, 20, " "), 12, "GameFontHighlightLarge")
    local crafts = Gather.Crafts(itemID, d.list, d.plan.allCrafts)
    local kept = Gather.Target(itemID) ~= nil
    blocks:Text(HeldText(itemID, d.list, kept or d.rowOf[itemID] ~= nil), 4)
    CraftBlocks(blocks, d, itemID, crafts)
    WhoBlocks(blocks, d, itemID)
    UseBlocks(blocks, itemID, d.list, crafts)
    if kept then
        KeepBlocks(blocks, d, itemID)
        AuctionBlocks(blocks, d, itemID)
    else
        AuctionBlocks(blocks, d, itemID)
        KeepBlocks(blocks, d, itemID)
    end
    SourceBlocks(blocks, itemID)
    return blocks
end

local function NotHereLines(z)
    local lines = {}
    for _, kind in ipairs(KINDS) do
        local ids, w = z.notHere[kind], WORDS[kind]
        local common = #ids > 1 and Gather.CommonZones(ids) or {}
        if #common > 0 then
            lines[#lines + 1] = ("%s %s in %s."):format(UI.JoinNames(ItemNames(ids)), w.is, UI.JoinNames(ZoneNames(common, 5)))
        else
            for _, itemID in ipairs(ids) do
                local zones = Gather.Zones(itemID)
                if #zones > 0 then lines[#lines + 1] = ("%s %s in %s."):format(ItemName(itemID), w.one, UI.JoinNames(ZoneNames(zones, 3))) end
            end
        end
    end
    return lines
end

local function ZoneBlocks(d)
    local blocks = UI.Blocks()
    local z = d.zoneData
    blocks:Text(Gold(Gather.ZoneName(z.mapID)), 0, "GameFontNormalLarge")
    if d.totalShort > 0 then
        blocks:Heading("Not in this zone")
        local lines = NotHereLines(z)
        blocks:Text(#lines > 0 and table.concat(lines, "\n") or "Everything you're short of is here.", 4)
    end
    local me, who = ns.CharacterKey(), {}
    for _, kind in ipairs(KINDS) do
        if #z[kind] > 0 then
            local s, mine, other = d.byKind[kind], nil, nil
            for _, g in ipairs(s.gatherers) do
                if g.key == me then mine = g else other = other or g end
            end
            if mine then
                table.insert(who, 1, ("%s %s."):format(Name(mine), WORDS[kind].can))
            elseif other then
                who[#who + 1] = WORDS[kind].bring:format(Name(other))
            else
                who[#who + 1] = WORDS[kind].nobody
            end
        end
    end
    if #who > 0 then
        blocks:Heading("Who can gather here")
        blocks:Text(table.concat(who, " "), 4)
    end
    return blocks
end

local function HomeBlocks(d)
    local blocks = UI.Blocks()
    blocks:Text(Gold("Your gatherers"), 0, "GameFontNormalLarge")
    local has = {}
    for _, entry in ipairs(d.list) do
        local skills = {}
        for _, prof in ipairs(entry.char.professions or {}) do
            if ns.GATHERING[prof.skillLine] then
                local kind = Gather.KindOfLine(prof.skillLine)
                if kind then has[kind] = true end
                skills[#skills + 1] = ("%s %d of %d"):format(prof.name or "", prof.skill or 0, prof.maxSkill or 0)
            end
        end
        if #skills > 0 then blocks:Text((UI.CharacterName(entry.key, entry.char)) .. "\n" .. table.concat(skills, "\n"), 8) end
    end
    local nobody = {}
    for _, kind in ipairs(KINDS) do
        if not has[kind] then nobody[#nobody + 1] = WORDS[kind].nobody end
    end
    if #nobody > 0 then blocks:Text(Soft(table.concat(nobody, " ")), 8) end
    if d.hereData then
        local zone, z = Gather.ZoneName(d.here), d.hereData
        local text
        if d.totalShort > 0 then
            local parts = {}
            for _, kind in ipairs(KINDS) do
                local n, here = d.short[kind], z.here[kind]
                if here > 0 then
                    parts[#parts + 1] = n == 1 and ("the one %s"):format(WORDS[kind].countOne)
                        or ("%d of the %d %s"):format(here, n, WORDS[kind].count)
                end
            end
            text = #parts > 0 and ("%s has %s you're short of."):format(zone, UI.JoinNames(parts))
                or ("None of what you're short of is in %s."):format(zone)
        else
            local counts = { Herbalism = #z.Herbalism, Mining = #z.Mining }
            text = counts.Herbalism + counts.Mining > 0 and ("%s has %s."):format(zone, (PerKind(counts):gsub(", ", " and ")))
                or ("No herbs or ore in %s in the addon's data."):format(zone)
        end
        blocks:Heading("Where you are")
        blocks:Text(text, 4)
        blocks:Buttons({ { label = "Show this zone", onClick = function()
            state.mode, state.zone, state.picked = "zone", nil, nil
            ns.RefreshWindow()
        end } })
    end
    local crafts = {}
    for _, s in ipairs(d.sections) do
        for _, row in ipairs(s.short) do
            if row.crafts then
                local c, what, verb = row.crafts[1], "Tracked crafts", "need"
                if #row.crafts == 1 then
                    local who = ns.db.characters[c.key]
                    what = ("%s's %d %s"):format(who and UI.ShortName(who, c.key) or c.key, c.count, c.name)
                    if c.count == 1 then verb = "needs" end
                end
                crafts[#crafts + 1] = ("%s %s %s"):format(what, verb, Color(TEXT.amber, ("%d more %s"):format(row.short, ItemName(row.itemID))))
            end
        end
    end
    if #crafts > 0 then
        blocks:Heading("Tracked crafts")
        blocks:Text(table.concat(crafts, "\n"), 4)
    end
    return blocks
end

function RefreshPane(keepScroll)
    local d = current
    local blocks
    if state.picked then
        blocks = MaterialBlocks(d, state.picked)
    elseif state.mode == "zone" and d.zoneData and state.search == "" then
        blocks = ZoneBlocks(d)
    else
        blocks = HomeBlocks(d)
    end
    panel.pane:SetBlocks(blocks, keepScroll)
end

local menuRows = {}

local function ZoneLabel(d, mapID)
    return Gather.ZoneName(mapID) .. (mapID == d.here and " (you're here)" or "")
end

local function RefreshMenuButton()
    local d = current
    panel.menuButton:SetState(d.zone and ZoneLabel(d, d.zone) or "Pick a zone", false, panel.menu:IsShown())
end

local function FillMenu()
    local d = current
    local y = -8
    for i, mapID in ipairs(d.zones) do
        local row = menuRows[i] or ns.Dropdown.RadioRow(panel.menu, MENU_WIDTH - 20, MENU_ROW)
        menuRows[i] = row
        row:SetScript("OnClick", function()
            -- nil, not the mapID: the zone where you stand follows you as you move.
            if mapID == d.here then
                state.zone, state.continent = nil, nil
            else
                state.zone = mapID
            end
            state.picked = nil
            panel.menu:Hide()
            ns.RefreshWindow()
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, y)
        local short = d.shortIn[mapID]
        y = y - row:Set(ZoneLabel(d, mapID), short and (#short == 1 and ItemName(short[1]) or (#short .. " short")) or nil, mapID == d.zone)
        local hereLine = i == 1 and mapID == d.here and #d.zones > 1
        if i == 1 then
            panel.menuLine:SetShown(hereLine)
            if hereLine then
                panel.menuLine:SetPoint("TOPLEFT", 12, y - 4)
                panel.menuLine:SetPoint("TOPRIGHT", -12, y - 4)
                y = y - 9
            end
        end
    end
    for i = #d.zones + 1, #menuRows do menuRows[i]:Hide() end
    panel.menu:SetHeight(-y + 8)
end

local continentRows = {}

local function RefreshContinentButton()
    local d = current
    panel.continentButton:SetState(d.continent and Gather.ZoneName(d.continent.mapID) or "Pick a continent", false,
        panel.continentMenu:IsShown())
end

local function FillContinents()
    local d = current
    local y = -8
    for i, c in ipairs(d.continents) do
        local row = continentRows[i] or ns.Dropdown.RadioRow(panel.continentMenu, CONTINENT_WIDTH - 20, MENU_ROW)
        continentRows[i] = row
        row:SetScript("OnClick", function()
            state.continent = c.mapID
            panel.continentMenu:Hide()
            ns.RefreshWindow()
            FillMenu()
            panel.menu:Show()
            RefreshMenuButton()
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, y)
        y = y - row:Set(Gather.ZoneName(c.mapID), nil, c == d.continent)
    end
    panel.continentMenu:SetHeight(math.max(MENU_ROW, -y - 8) + 16)
end

local function SetMode(mode)
    if state.mode == mode then return end
    state.mode, state.picked = mode, nil
    panel.menu:Hide()
    panel.continentMenu:Hide()
    ns.RefreshWindow()
end

local function ArrangePage(width)
    local controlsY = UI.Below(PAGE.top, PAGE.titleHeight)
    panel.keepButton:SetKind(state.mode == "keep" and "primary" or "quiet")
    panel.zoneButton:SetKind(state.mode == "zone" and "primary" or "quiet")
    panel.keepButton:SetPoint("TOPLEFT", 0, controlsY)
    local zoneMode = state.mode == "zone"
    panel.continentButton:SetShown(zoneMode)
    panel.menuButton:SetShown(zoneMode)
    if zoneMode then
        RefreshContinentButton()
        RefreshMenuButton()
    end
    local before = zoneMode and panel.menuButton or panel.zoneButton
    local on = Gather.InTracker()
    panel.trackerButton:SetKind(on and "primary" or "quiet", on and "Hide from quest tracker" or "Show in quest tracker")
    panel.trackerButton:SetPoint("TOPRIGHT", 0, controlsY)
    local rowEnd = width - panel.trackerButton:GetWidth() - 16
    local x, rowsBelow = panel.keepButton:GetWidth() + 6 + panel.zoneButton:GetWidth(), 0
    panel.continentButton:ClearAllPoints()
    if zoneMode then
        local zones = panel.continentButton:GetWidth() + 8 + panel.menuButton:GetWidth()
        if x + 12 + zones <= rowEnd then
            panel.continentButton:SetPoint("LEFT", panel.zoneButton, "RIGHT", 12, 0)
            x = x + 12 + zones
        else
            rowsBelow = 1
            panel.continentButton:SetPoint("TOPLEFT", 0, controlsY - CONTROL_ROW)
            x, rowEnd = zones, width
        end
    end
    local room = rowEnd - x - 16
    panel.search:ClearAllPoints()
    if room >= SEARCH_MIN then
        panel.search:SetWidth(math.min(SEARCH_WIDTH, room))
        panel.search:SetPoint("LEFT", before, "RIGHT", 16, 0)
    else
        rowsBelow = rowsBelow + 1
        panel.search:SetWidth(SEARCH_WIDTH)
        panel.search:SetPoint("TOPLEFT", 6, controlsY - rowsBelow * CONTROL_ROW)
    end
    local listTop = controlsY - 26 - PAGE.gap - rowsBelow * CONTROL_ROW
    last.listWidth = width - PANE_WIDTH - PANE_GAP - 14
    UI.PlaceList(panel.list, listTop, 4, PANE_WIDTH + PANE_GAP)
    panel.pane:ClearAllPoints()
    panel.pane:SetPoint("TOPRIGHT", 0, listTop)
    panel.pane:SetPoint("BOTTOMRIGHT", 0, 4)
end

local function CountLine(d)
    local stock = d.totalStock > 0 and (" %d in stock."):format(d.totalStock) or ""
    if d.totalShort == 0 then return d.totalStock > 0 and ("Nothing short." .. stock) or "" end
    return ("%d short: %s.%s"):format(d.totalShort, PerKind(d.short), stock)
end

local function MeasureLines(rows)
    for _, data in ipairs(rows) do
        if data.line then data.height = math.ceil(UI.TextHeight(data.line, last.listWidth - 24, "GameFontHighlightSmall", 3)) + 14 end
    end
end

function View.Redraw(keepScroll)
    if not (panel and current) then return end
    local rows = Rows(current)
    MeasureLines(rows)
    panel.list.box:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    RefreshPane(keepScroll)
end

local function OpenAt(itemID)
    state.mode, state.zone, state.search = "keep", nil, ""
    if panel then panel.search:SetText("") end
    state.picked = itemID
end

function View.Open()
    OpenAt(nil)
    ns.ShowSection("gathering")
end

function View.Opened(itemID)
    if itemID then OpenAt(itemID) end
end

function View.Refresh(list, width, height, layoutOnly)
    last.list, last.width, last.height = list, width or last.width, height or last.height
    current = UI.Data("gathering", layoutOnly, function() return Compute(list) end)
    panel.subtitle:SetText(CountLine(current))
    ArrangePage(last.width)
    if layoutOnly and UI.RedrawRows(panel.list, FillGatherRow) then return end
    View.Redraw(true)
end

function View.Build(parent)
    panel = UI.Page(parent, "Gathering")
    panel.gathering = true
    menuRows, continentRows = {}, {}

    panel.keepButton = UI.Button(panel, "What you need", "primary")
    panel.keepButton:SetScript("OnClick", function() SetMode("keep") end)
    panel.zoneButton = UI.Button(panel, "By zone", "quiet")
    panel.zoneButton:SetPoint("LEFT", panel.keepButton, "RIGHT", 6, 0)
    panel.zoneButton:SetScript("OnClick", function() SetMode("zone") end)

    panel.trackerButton = UI.Button(panel, "Show in quest tracker", "quiet")
    panel.trackerButton:SetScript("OnClick", function() Gather.SetInTracker(not Gather.InTracker()) end)

    panel.continentButton, panel.continentMenu = ns.Dropdown.Menu(panel, CONTINENT_WIDTH, FillContinents, RefreshContinentButton)
    panel.menuButton, panel.menu = ns.Dropdown.Menu(panel, MENU_WIDTH, FillMenu, RefreshMenuButton)
    panel.menuLine = UI.Divider(panel.menu)
    panel.menuButton:SetPoint("LEFT", panel.continentButton, "RIGHT", 8, 0)

    panel.search = UI.SearchBox(panel, function(text)
        if text == state.search then return end
        state.search, state.picked = text, nil
        View.Redraw()
    end)
    if type(panel.search.Instructions) == "table" then panel.search.Instructions:SetText("Find a herb or ore") end

    panel.list = UI.ScrollList(panel, Extent, InitGatherRow)
    panel.pane = UI.BlockPane(panel, PANE_WIDTH, function()
        state.allPlaces = state.allPlaces ~= state.picked and state.picked or nil
        RefreshPane(true)
    end)
    return panel
end

ns.UI.AddPage("gathering", View)
