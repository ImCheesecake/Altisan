-- Builds the QuestieDBForever library from QuestieDB's GPLv3 Forever layers (the generated
-- delta-base and the player traces). SRC and COMMIT are filled in by the caller.

local modules = {}
local function Module(name)
    modules[name] = modules[name] or {}
    return modules[name]
end
QuestieLoader = { ImportModule = function(_, name) return Module(name) end }
QuestieLoader.CreateModule = QuestieLoader.ImportModule

-- QuestieDB's correction files index a row by key name (npcKeys.spawns_add): keep the names.
local keyNames = setmetatable({}, { __index = function(_, key) return key end })
Module("QuestieDB").npcKeys = keyNames
Module("QuestieDB").itemKeys = keyNames
Module("QuestieDB").npcRanks = keyNames

local function Run(key, ...)
    local chunk = assert(load(SRC[key], "=" .. key))
    return chunk(...)
end

local enum = {}
Run("zones", nil, { Enum = enum })
Module("ZoneDB").zoneIDs = enum.zoneIDs

local function Remove(list, value)
    for i = #list, 1, -1 do if list[i] == value then table.remove(list, i) end end
end

local function Merge(rows, moduleName)
    for id, fields in pairs(Module(moduleName):Load()) do
        local row = rows[id] or {}
        rows[id] = row
        for key, value in pairs(fields) do
            local field, op = key:match("^(.-)_(add)$")
            if not field then field, op = key:match("^(.-)_(remove)$") end
            if not op then
                row[key] = value
            elseif field == "spawns" then
                row.spawns = row.spawns or {}
                for area, points in pairs(value) do
                    if op == "add" then row.spawns[area] = points else row.spawns[area] = nil end
                end
            else
                row[field] = row[field] or {}
                for _, v in ipairs(value) do
                    if op == "add" then table.insert(row[field], v) else Remove(row[field], v) end
                end
            end
        end
    end
end

local npcs, items = {}, {}
Run("npcGen"); Merge(npcs, "ForeverBaseNpc")
Run("npcTrace"); Merge(npcs, "ForeverNpcTraces")
Run("itemGen"); Merge(items, "ForeverBaseItem")
Run("itemTrace"); Merge(items, "ForeverItemTraces")

local recipeItem, sourced, lqNamed, lqPlaced = {}, {}, {}, {}
for spell, item in SRC.recipeItems:gmatch("%[(%d+)%]=(%d+)") do recipeItem[tonumber(spell)] = tonumber(item) end
for spell in SRC.sources:gmatch("\n%[(%d+)%]=") do sourced[tonumber(spell)] = true end
for id in SRC.lqText:gmatch('\n%[(%d+)%]="') do lqNamed[tonumber(id)] = true end
for id in SRC.lqSpawns:gmatch('\n%[(%d+)%]="') do lqPlaced[tonumber(id)] = true end

local function Sorted(list)
    local out = {}
    local seen = {}
    for _, v in ipairs(list or {}) do
        if type(v) == "number" and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    table.sort(out)
    return out
end

local function Named(id) return lqNamed[id] or (npcs[id] and npcs[id].name) end

local sources, needed = {}, {}
local counts = { recipes = 0, vendor = 0, drop = 0, quest = 0 }
for spell, itemID in pairs(recipeItem) do
    local item = not sourced[spell] and items[itemID]
    if item then
        local row = {}
        local vendors = {}
        for _, id in ipairs(Sorted(item.vendors)) do if Named(id) then vendors[#vendors + 1] = id end end
        if #vendors > 0 then row.vendor = vendors end
        local drops = {}
        for _, id in ipairs(Sorted(item.npcDrops)) do if Named(id) then drops[#drops + 1] = id end end
        if #drops > 0 then row.drop = drops end
        local quests = Sorted(item.questRewards)
        if #quests > 0 then row.quest = quests end
        if row.vendor or row.drop or row.quest then
            sources[spell] = row
            counts.recipes = counts.recipes + 1
            for _, kind in ipairs({ "vendor", "drop", "quest" }) do
                if row[kind] then counts[kind] = counts[kind] + 1 end
            end
            for _, kind in ipairs({ "vendor", "drop" }) do
                for _, id in ipairs(row[kind] or {}) do needed[id] = true end
            end
        end
    end
end

local itemVendors, vendorItemCount = {}, 0
for itemID, item in pairs(items) do
    local vendors = {}
    for _, id in ipairs(Sorted(item.vendors)) do if Named(id) then vendors[#vendors + 1] = id end end
    if #vendors > 0 then
        itemVendors[itemID] = vendors
        vendorItemCount = vendorItemCount + 1
        for _, id in ipairs(vendors) do needed[id] = true end
    end
end

local function Spawns(npc)
    local out, any = {}, false
    for area, points in pairs(npc.spawns or {}) do
        local p = type(area) == "number" and points[1]
        if p and p[1] and p[1] >= 0 then
            out[area] = { math.floor(p[1] * 100 + 0.5) / 100, math.floor(p[2] * 100 + 0.5) / 100 }
            any = true
        end
    end
    return any and out or nil
end

local npcRows, npcCount = {}, 0
for id in pairs(needed) do
    local npc = npcs[id]
    local missing = not lqNamed[id] or not lqPlaced[id]
    if npc and npc.name and missing then
        npcRows[id] = { npc.name, npc.subName or false, npc.friendlyToFaction or false, Spawns(npc) }
        npcCount = npcCount + 1
    end
end

local function Keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end
local function List(ids) return "{" .. table.concat(ids, ",") .. "}" end
local function Num(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return (string.format("%.2f", n):gsub("0$", ""))
end

local out = {}
local function Add(line) out[#out + 1] = line end
Add("-- QuestieDBForever: where to get Forever's own recipes that LibProfessionDB has no source for, which")
Add("-- vendors sell an item, and the NPCs they name that LibQuestDB lacks. From QuestieDB's GPLv3 Forever layers (the generated")
Add("-- delta-base and the player traces), commit " .. COMMIT .. ". Written by Altisan's dev/questiedb.js.")
Add("")
Add("local _, ns = ...")
Add("")
Add("ns.QuestieForever = {")
Add("    commit = \"" .. COMMIT .. "\",")
Add("    -- [recipe spell ID] = { vendor = { NPC IDs }, drop = { every NPC ID }, quest = { quest IDs } }")
Add("    sources = {")
for _, spell in ipairs(Keys(sources)) do
    local row, parts = sources[spell], {}
    if row.vendor then parts[#parts + 1] = "vendor=" .. List(row.vendor) end
    if row.drop then parts[#parts + 1] = "drop=" .. List(row.drop) end
    if row.quest then parts[#parts + 1] = "quest=" .. List(row.quest) end
    Add(("[%d]={%s},"):format(spell, table.concat(parts, ",")))
end
Add("    },")
Add("    -- [item ID] = { vendor NPC IDs }")
Add("    itemVendors = {")
for _, itemID in ipairs(Keys(itemVendors)) do Add(("[%d]=%s,"):format(itemID, List(itemVendors[itemID]))) end
Add("    },")
Add("    -- [NPC ID] = { name, title or false, \"A\" / \"H\" / \"AH\" or false, { [area ID] = { { x, y } } } or nil }")
Add("    npcs = {")
for _, id in ipairs(Keys(npcRows)) do
    local r = npcRows[id]
    local spawns = "nil"
    if r[4] then
        local parts = {}
        for _, area in ipairs(Keys(r[4])) do
            parts[#parts + 1] = ("[%d]={{%s,%s}}"):format(area, Num(r[4][area][1]), Num(r[4][area][2]))
        end
        spawns = "{" .. table.concat(parts, ",") .. "}"
    end
    local function Str(v) return v and string.format("%q", v) or "false" end
    Add(("[%d]={%s,%s,%s,%s},"):format(id, Str(r[1]), Str(r[2]), Str(r[3]), spawns))
end
Add("    },")
Add("}")
OUTPUT = table.concat(out, "\n") .. "\n"
SUMMARY = ("%d recipes (vendor %d, drop %d, quest %d), %d items sold by vendors, %d NPCs"):format(counts.recipes,
    counts.vendor, counts.drop, counts.quest, vendorItemCount, npcCount)
