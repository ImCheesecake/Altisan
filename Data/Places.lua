-- Places.lua: where a recipe's trainers, vendors and quest givers stand (LibQuestDB), which vendors
-- sell an item (LibItemDB), nearest to you first, and the game's own map pin for one of them.

local _, ns = ...

local Places = {}
ns.Places = Places

-- Not IsReady(): that waits for the quest rewards, which aren't embedded.
local function QuestDB()
    return LibStub and LibStub("LibQuestDB-1.0", true)
end

local FACTION = { Alliance = "A", Horde = "H" }

local function MyFaction() return FACTION[UnitFactionGroup("player") or ""] end
local function OnMySide(side, mine) return not mine or not side or side:find(mine, 1, true) ~= nil end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name
end

local function WorldPos(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and continent and pos then return continent, pos:GetXY() end
end

local function PlayerPos()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then return WorldPos(mapID, pos:GetXY()) end
end

local function Here()
    local here = {}
    here.continent, here.x, here.y = PlayerPos()
    return here
end

local function SortPlaces(list)
    table.sort(list, function(a, b)
        if (a.far ~= nil) ~= (b.far ~= nil) then return a.far ~= nil end
        if a.far and b.far and a.far ~= b.far then return a.far < b.far end
        if (a.zone or "") ~= (b.zone or "") then return (a.zone or "~") < (b.zone or "~") end
        return a.name < b.name
    end)
end

function Places.OnMySide(side) return OnMySide(side, MyFaction()) end

local fromQuestie = {}
function Places.NPC(npcID)
    local db = QuestDB()
    local npc = db and db:GetNPC(npcID)
    if npc then return npc end
    local row = ns.QuestieForever and ns.QuestieForever.npcs[npcID]
    if not row then return nil end
    if not fromQuestie[npcID] then
        fromQuestie[npcID] = { name = row[1], subName = row[2] or nil, friendlyToFaction = row[3] or nil,
                               zoneID = row[4] and next(row[4]) or nil }
    end
    return fromQuestie[npcID]
end

local function Spawns(db, npcID)
    local spawns = db and db:GetNPCSpawns(npcID)
    if spawns and next(spawns) then return spawns end
    local row = ns.QuestieForever and ns.QuestieForever.npcs[npcID]
    return row and row[4] or {}
end

-- Inside an instance the library gives -1,-1, which can't be pinned.
local function Spot(db, npcID, zoneID)
    local spawns = Spawns(db, npcID)
    local area = zoneID and spawns[zoneID] and zoneID or next(spawns)
    local point = area and spawns[area][1]
    if not point or point[1] < 0 or not db then return area end
    return area, db:GetUiMapId(area), point[1] / 100, point[2] / 100
end

local instancesOf = {}
function Places.DropInstances(recipeID)
    if instancesOf[recipeID] == nil then
        local drop = (ns.RecipeSources(recipeID) or {}).drop
        local areas, list = {}, false
        if drop and #drop > 0 and (drop.total or #drop) <= #drop then
            list = {}
            for _, entry in ipairs(drop) do
                for area, points in pairs(Spawns(QuestDB(), entry.id)) do
                    for _, point in ipairs(points) do
                        if point[1] >= 0 then list = false end
                    end
                    if list and not areas[area] then
                        areas[area] = true
                        list[#list + 1] = area
                    end
                end
                if not list then break end
            end
            if list and #list == 0 then list = false end
            if list then table.sort(list) end
        end
        instancesOf[recipeID] = list
    end
    return instancesOf[recipeID] or nil
end

-- LibProfessionDB's quest names are NPC names, so the game names quests (nil until it has loaded).
function Places.QuestTitle(questID)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if not title and C_QuestLog and C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(questID) end
    return title
end

local function Place(db, npcID, name, kind, mine, here)
    local p = { id = npcID, name = name, kind = kind }
    local npc = Places.NPC(npcID)
    if not npc then return p, false end
    p.name, p.title = p.name or npc.name, npc.subName
    local friendly = npc.friendlyToFaction
    local area, mapID, x, y = Spot(db, npcID, npc.zoneID)
    p.mapID, p.x, p.y = mapID, x, y
    p.zone = MapName(mapID) or (area and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area))
    if mapID and here.continent then
        local c, wx, wy = WorldPos(mapID, x, y)
        if c == here.continent then p.far = math.sqrt((wx - here.x) ^ 2 + (wy - here.y) ^ 2) end
    end
    return p, not OnMySide(friendly, mine)
end

local function QuestLabel(questID, quest)
    local title = Places.QuestTitle(questID)
    return (title and ("Quest: " .. title) or "Quest") .. (quest.hidden == "seasonal" and " (holiday)" or "")
end

function Places.ForRecipe(recipeID)
    local db = QuestDB()
    local sources = ns.RecipeSources(recipeID)
    if not sources then return {}, 0, nil, {} end
    local mine = MyFaction()
    local here = Here()
    local list, total, left, kinds = {}, 0, false, {}
    local function Add(p, theirs)
        if theirs then
            total, left = total - 1, true
        else
            kinds[p.kind] = true
            if p.name then list[#list + 1] = p end
        end
    end
    for _, kind in ipairs({ "trainer", "vendor" }) do
        local entries = sources[kind] or {}
        total = total + (entries.total or #entries)
        for _, entry in ipairs(entries) do Add(Place(db, entry.id, entry.name, kind, mine, here)) end
    end
    for _, entry in ipairs(sources.quest or {}) do
        local quest = db and db.GetQuest and db:GetQuest(entry.id)
        for _, npcID in ipairs(quest and quest.startedBy.npcs or {}) do
            total = total + 1
            local p, theirs = Place(db, npcID, nil, "quest", mine, here)
            p.quest, p.title = entry.id, QuestLabel(entry.id, quest)
            Add(p, theirs)
        end
    end
    SortPlaces(list)
    return list, total, left and (mine == "H" and FACTION_ALLIANCE or FACTION_HORDE) or nil, kinds
end

local skillQuests = {}
function Places.ForSkillQuests(skillLine, skill)
    local db = QuestDB()
    if not db then return {} end
    local id = skillLine .. ":" .. skill
    if not skillQuests[id] then
        local ids = {}
        for _, questID in ipairs(db:GetQuestIds()) do
            local quest = db:GetQuest(questID)
            local req = quest and quest.requiredSkill
            if req and req.skill == skillLine and req.value == skill and not quest.hidden then ids[#ids + 1] = questID end
        end
        skillQuests[id] = ids
    end
    local mine, here, list = MyFaction(), Here(), {}
    for _, questID in ipairs(skillQuests[id]) do
        local quest = db:GetQuest(questID)
        for _, npcID in ipairs(quest.startedBy.npcs or {}) do
            local p, theirs = Place(db, npcID, nil, "quest", mine, here)
            if p.name and not theirs then
                p.quest, p.title = questID, QuestLabel(questID, quest)
                list[#list + 1] = p
            end
        end
    end
    SortPlaces(list)
    return list
end

function Places.Kept(kept, recipeID)
    local k = kept[recipeID]
    if not k then
        k = { Places.ForRecipe(recipeID) }
        kept[recipeID] = k
    end
    return k[1], k[2], k[3]
end

-- LibItemDB keeps at most 8 vendors per item, lowest NPC IDs first: a full list may lack your
-- capital's vendor.
local MAX_VENDORS = 8
local vendorsOf = {}

function Places.Vendors(itemID)
    local sold = vendorsOf[itemID]
    if sold == nil then
        local items = LibStub and LibStub("LibItemDB-1.0", true)
        local rows = items and items.GetItemPlaces and items:GetItemPlaces(itemID)
        local mine = MyFaction()
        local count, ours, listed = 0, {}, {}
        for _, row in ipairs(rows or {}) do
            if row.kind == "vendor" then
                count, listed[row.id] = count + 1, true
                -- A vendor the library learned in game has no faction: the NPC's own says it.
                local side = row.side ~= "" and row.side or (Places.NPC(row.id) or {}).friendlyToFaction
                if not side or side == "" or OnMySide(side, mine) then ours[#ours + 1] = row end
            end
        end
        -- QuestieDB's lists are whole; the library's can be one vendor its author saw in game.
        local fromQuestie = count < MAX_VENDORS and ns.QuestieForever and ns.QuestieForever.itemVendors[itemID]
        for _, npcID in ipairs(fromQuestie or {}) do
            local npc = not listed[npcID] and Places.NPC(npcID)
            if npc and OnMySide(npc.friendlyToFaction, mine) then ours[#ours + 1] = { id = npcID } end
        end
        -- LibItemDB's price is for the merchant's whole stack (5 Empty Vials for 20c).
        local stackPrice = items and items.GetVendorBasePrice and items:GetVendorBasePrice(itemID)
        local stack = ns.VendorStacks[itemID] or 1
        sold = (count >= MAX_VENDORS or #ours > 0) and { count = count, ours = ours, stack = stack,
            price = stackPrice and stackPrice / stack } or false
        vendorsOf[itemID] = sold
    end
    if not sold then return nil end
    local info = { price = sold.price, stack = sold.stack, places = {} }
    if sold.count < MAX_VENDORS then
        local db, here, mine = QuestDB(), Here(), MyFaction()
        for _, row in ipairs(sold.ours) do
            local p = Place(db, row.id, row.name, "vendor", mine, here)
            local spot = not p.mapID and row.places and row.places[1]
            if spot and spot.uiMapID and spot.points[1] then
                p.mapID, p.x, p.y = spot.uiMapID, spot.points[1].x / 100, spot.points[1].y / 100
                p.zone = MapName(p.mapID)
            end
            info.places[#info.places + 1] = p
        end
        SortPlaces(info.places)
    end
    return info
end

function Places.WholeStacks(vendor, count)
    local n = math.ceil(count / vendor.stack) * vendor.stack
    return n, vendor.price and vendor.price * n
end

function Places.OnlyText(recipeID, faction)
    local sources = ns.RecipeSources(recipeID) or {}
    local has = function(kind) return sources[kind] and #sources[kind] > 0 end
    local text
    if has("vendor") then
        text = ("Sold by %s vendors only."):format(faction)
    elseif has("quest") and not has("trainer") then
        text = ("Only %s quests give it."):format(faction)
    elseif has("trainer") and not has("quest") then
        text = ("Taught only by %s trainers."):format(faction)
    else
        text = ("Taught only by %s trainers and quests."):format(faction)
    end
    local itemID = ns.RecipeItem(recipeID)
    if itemID and C_Item.GetItemInfo then
        local bind = select(14, C_Item.GetItemInfo(itemID))
        if bind == nil then
            C_Item.RequestLoadItemDataByID(itemID)
        elseif bind ~= 1 then
            text = text .. " The recipe can be traded: try the auction house."
        end
    end
    return text
end

function Places.CanPin(p)
    return p.mapID and p.x and C_Map.CanSetUserWaypointOnMap
        and C_Map.CanSetUserWaypointOnMap(p.mapID) or false
end

-- The player may have removed the waypoint, reached it or set another.
function Places.IsPinned(p)
    if Places.pinned ~= p.id then return false end
    local point = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
    return point and point.uiMapID == p.mapID or false
end

function Places.Pin(p)
    if not Places.CanPin(p) then return false end
    -- Blizzard's UiMapPoint helper loads only for the retail game type, so build the point here.
    C_Map.SetUserWaypoint({ uiMapID = p.mapID, position = CreateVector2D(p.x, p.y) })
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    Places.pinned = p.id
    return true
end
