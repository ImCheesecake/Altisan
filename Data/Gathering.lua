-- Gathering.lua: herbs and ore by zone (LibItemDB's nodes), materials kept in stock, and what the
-- account is short of, herbs and ore apart, for tracked crafts and for stock.

local _, ns = ...

local Gather = {}
ns.Gathering = Gather

Gather.KINDS = { Herbalism = 182, Mining = 186 }
Gather.TITLE = { Herbalism = "Herbs", Mining = "Ore and stone" }
local KIND_OF_LINE = { [182] = "Herbalism", [186] = "Mining" }
Gather.START = 20
local MIN_CHANCE, MIN_SPOTS = 10, 3

local index

local function ItemDB()
    return LibStub and LibStub("LibItemDB-1.0", true)
end

function Gather.Cover(rows)
    local covers, total = {}, 0
    for _, row in ipairs(rows) do
        local zones = Gather.Zones(row.itemID)
        if #zones > 0 then total = total + 1 end
        for _, mapID in ipairs(zones) do covers[mapID] = (covers[mapID] or 0) + 1 end
    end
    return covers, total
end

local function SortByCount(counts)
    local out = {}
    for id in pairs(counts) do out[#out + 1] = id end
    table.sort(out, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    return out
end

-- Nodes also give quest items (Root Sample from Barrens herbs), which only matter on the quest.
local QUEST_ITEM_CLASS = 12
local function IsQuestItem(itemID)
    return select(6, C_Item.GetItemInfoInstant(itemID)) == QUEST_ITEM_CLASS
end

-- The library can't list its items, so its placeOf table is walked once. Only "g" tokens (items an
-- object gives) can be gathered.
local function BuildZoneIndex()
    index = { kind = {}, zones = {}, inZone = {} }
    local db = ItemDB()
    local spotsIn = {}
    for itemID, blob in pairs(db and db.placeOf or {}) do
        if type(blob) == "string" and blob:find("g", 1, true) and not IsQuestItem(itemID) then
            local kind, spots = nil, {}
            for _, row in ipairs(db:GetItemPlaces(itemID) or {}) do
                if row.kind == "object" and Gather.KINDS[row.profession] and (row.chance or 0) >= MIN_CHANCE then
                    kind = kind or row.profession
                    for _, place in ipairs(row.places) do
                        -- A place the library learned in game has no spawn count, only the points seen.
                        local n = place.count or #place.points
                        if place.uiMapID then spots[place.uiMapID] = (spots[place.uiMapID] or 0) + n end
                    end
                end
            end
            for mapID, n in pairs(spots) do
                if n < MIN_SPOTS then spots[mapID] = nil end
            end
            if kind and next(spots) then
                index.kind[itemID] = kind
                index.zones[itemID] = SortByCount(spots)
                for mapID, n in pairs(spots) do
                    spotsIn[mapID] = spotsIn[mapID] or {}
                    spotsIn[mapID][itemID] = n
                end
            end
        end
    end
    for mapID, counts in pairs(spotsIn) do index.inZone[mapID] = SortByCount(counts) end
end

local function Index()
    if not index then BuildZoneIndex() end
    return index
end

function Gather.Kind(itemID)
    return Index().kind[itemID]
end

function Gather.Zones(itemID)
    return Index().zones[itemID] or {}
end

function Gather.InZone(mapID)
    return Index().inZone[mapID] or {}
end

function Gather.Materials()
    local out = {}
    for itemID in pairs(Index().kind) do out[#out + 1] = itemID end
    table.sort(out)
    return out
end

local zoneNames = {}
function Gather.ZoneName(mapID)
    if not zoneNames[mapID] then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        zoneNames[mapID] = info and info.name or ("Zone " .. mapID)
    end
    return zoneNames[mapID]
end

function Gather.PlayerZone()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 5 do
        local info = mapID and C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == nil or info.mapType == zone then return mapID end
        mapID = info.parentMapID
    end
end

function Gather.Continent(mapID)
    local continent = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    for _ = 1, 5 do
        local info = mapID and C_Map.GetMapInfo(mapID)
        if not info then return nil end
        if info.mapType == continent then return mapID end
        mapID = info.parentMapID
    end
end

function Gather.Continents()
    local byContinent, out = {}, {}
    for mapID in pairs(Index().inZone) do
        local continent = Gather.Continent(mapID)
        if continent then
            if not byContinent[continent] then
                byContinent[continent] = { mapID = continent, zones = {} }
                out[#out + 1] = byContinent[continent]
            end
            table.insert(byContinent[continent].zones, mapID)
        end
    end
    table.sort(out, function(a, b) return a.mapID < b.mapID end)
    for _, c in ipairs(out) do
        table.sort(c.zones, function(a, b) return Gather.ZoneName(a) < Gather.ZoneName(b) end)
    end
    return out
end

function Gather.KindOfLine(skillLine)
    return KIND_OF_LINE[skillLine]
end

function Gather.Gatherers(list)
    local out = {}
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local kind = KIND_OF_LINE[prof.skillLine]
            if kind then out[#out + 1] = { key = entry.key, char = entry.char, prof = prof, kind = kind } end
        end
    end
    return out
end

function Gather.Target(itemID)
    local s = ns.db.stock[itemID]
    return s and s.target
end

function Gather.Keep(itemID, target)
    if target and target > 0 then
        ns.db.stock[itemID] = ns.db.stock[itemID] or {}
        ns.db.stock[itemID].target = target
    else
        ns.db.stock[itemID] = nil
    end
    ns.RefreshWindow()
end

function Gather.Change(itemID, delta)
    local target = Gather.Target(itemID)
    if target then Gather.Keep(itemID, math.max(1, target + delta)) end
end

function Gather.Buys(itemID)
    local s = ns.db.stock[itemID]
    return s and s.buy or false
end

function Gather.SetBuy(itemID, on)
    local s = ns.db.stock[itemID]
    if not s then return end
    s.buy = on or nil
    ns.RefreshWindow()
end

function Gather.Crafts(itemID, list, crafts)
    local listed = {}
    for _, entry in ipairs(list) do listed[entry.key] = true end
    local out = {}
    for _, t in ipairs(crafts or (ns.SkillPlan.AllCrafts(list))) do
        if listed[t.key] then
            local recipe = ns.db.recipes[t.recipe]
            for _, reagent in ipairs(ns.Reagents(t.recipe, recipe and recipe.skillLine)) do
                if reagent[1] == itemID then
                    out[#out + 1] = { recipe = t.recipe, name = ns.RecipeName(t.recipe),
                                      count = t.count, need = reagent[2] * t.count, key = t.key }
                    break
                end
            end
        end
    end
    return out
end

function Gather.Stock(list, plan)
    local sections, byKind = {}, {}
    for _, kind in ipairs({ "Herbalism", "Mining" }) do
        byKind[kind] = { kind = kind, gatherers = {}, short = {}, inStock = {} }
        sections[#sections + 1] = byKind[kind]
    end
    for _, g in ipairs(Gather.Gatherers(list)) do table.insert(byKind[g.kind].gatherers, g) end
    local seen, stockShort = {}, {}
    for _, b in ipairs(plan.buy) do
        local short, s = b.count - (b.stock or 0), byKind[Gather.Kind(b.itemID)]
        if short > 0 and s then
            seen[b.itemID] = true
            -- Ore for a tracked craft's bars isn't one of its materials, so no crafts: use what's
            -- held.
            local crafts, need = Gather.Crafts(b.itemID, list, plan.allCrafts), 0
            for _, c in ipairs(crafts) do need = need + c.need end
            local have = #crafts > 0 and math.max(0, need - short) or ns.Bags.Holders(b.itemID, list)
            s.short[#s.short + 1] = { itemID = b.itemID, short = short, crafts = crafts, want = have + short, have = have }
        end
    end
    for itemID, st in pairs(ns.db.stock) do
        local s, left = byKind[Gather.Kind(itemID)], plan.stock[itemID]
        if s and left and not seen[itemID] then
            local row = { itemID = itemID, have = left.have, want = st.target, short = left.short }
            if row.short > 0 then
                stockShort[s.kind] = stockShort[s.kind] or {}
                table.insert(stockShort[s.kind], row)
            else
                table.insert(s.inStock, row)
            end
        end
    end
    for _, s in ipairs(sections) do
        local rows = stockShort[s.kind] or {}
        table.sort(rows, function(a, b)
            local fa, fb = a.have / a.want, b.have / b.want
            if fa ~= fb then return fa < fb end
            return a.itemID < b.itemID
        end)
        for _, row in ipairs(rows) do s.short[#s.short + 1] = row end
        table.sort(s.inStock, function(a, b) return a.itemID < b.itemID end)
        s.spread = Gather.Spread(s.short)
    end
    return sections
end

function Gather.InTracker()
    return ns.db.stockInTracker
end

function Gather.SetInTracker(on)
    ns.db.stockInTracker = on
    ns.RefreshWindow()
end

function Gather.TrackerRows(list)
    local groups = {}
    for _, s in ipairs(Gather.Stock(list, ns.ShoppingPlan(list))) do
        local rows = {}
        for _, row in ipairs(s.short) do
            if not row.crafts and not Gather.Buys(row.itemID) then rows[#rows + 1] = row end
        end
        if #rows > 0 then groups[#groups + 1] = { kind = s.kind, rows = rows } end
    end
    return groups
end

function Gather.Spread(short)
    if #short == 0 then return nil end
    local covers, total = Gather.Cover(short)
    local zones = SortByCount(covers)
    if #zones == 0 then return nil end
    local best = covers[zones[1]]
    local top = {}
    for i = 1, math.min(2, #zones) do
        if covers[zones[i]] == best then top[#top + 1] = zones[i] end
    end
    local lacking = {}
    for _, row in ipairs(short) do
        local grows = {}
        for _, mapID in ipairs(Gather.Zones(row.itemID)) do grows[mapID] = true end
        if not grows[top[1]] and next(grows) and #lacking < 2 then
            local three = {}
            for i, mapID in ipairs(Gather.Zones(row.itemID)) do if i <= 3 then three[i] = mapID end end
            lacking[#lacking + 1] = { itemID = row.itemID, zones = three }
        end
    end
    return { zones = top, covers = best, total = total, lacking = lacking }
end

function Gather.Zone(mapID, sections)
    local rowOf, z = {}, { mapID = mapID, here = {}, notHere = {} }
    for _, s in ipairs(sections) do
        z[s.kind], z.here[s.kind], z.notHere[s.kind] = {}, 0, {}
        for _, row in ipairs(s.short) do rowOf[row.itemID] = row end
        for _, row in ipairs(s.inStock) do rowOf[row.itemID] = row end
    end
    local inZone = {}
    for _, itemID in ipairs(Gather.InZone(mapID)) do
        inZone[itemID] = true
        local bucket = z[Gather.Kind(itemID)]
        bucket[#bucket + 1] = { itemID = itemID, row = rowOf[itemID] }
    end
    for _, s in ipairs(sections) do
        for _, row in ipairs(s.short) do
            if inZone[row.itemID] then
                z.here[s.kind] = z.here[s.kind] + 1
            else
                table.insert(z.notHere[s.kind], row.itemID)
            end
        end
    end
    return z
end

function Gather.CommonZones(itemIDs)
    if #itemIDs == 0 then return {} end
    local out = {}
    for _, mapID in ipairs(Gather.Zones(itemIDs[1])) do
        local all = true
        for i = 2, #itemIDs do
            local found = false
            for _, other in ipairs(Gather.Zones(itemIDs[i])) do if other == mapID then found = true break end end
            all = all and found
        end
        if all then out[#out + 1] = mapID end
    end
    return out
end

function Gather.Drops(itemID, max)
    local db = ItemDB()
    local drops = {}
    for _, row in ipairs(db and db:GetItemPlaces(itemID) or {}) do
        if row.kind == "drop" and not row.questOnly and not row.condition and row.chance then drops[#drops + 1] = row end
    end
    table.sort(drops, function(a, b) return a.chance > b.chance end)
    local names = {}
    for i = 1, math.min(max or 3, #drops) do names[i] = drops[i].name end
    return names, drops[1] and drops[1].chance
end
