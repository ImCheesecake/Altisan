-- Tracking.lua: crafts tracked across characters (`tracked`) and Blizzard's quest log tracker for
-- them (`questLog`), handed to each character at their login and followed both ways.

local _, ns = ...

local Tracking = {}
ns.Tracking = Tracking

function Tracking.Tracked()
    return ns.db.tracked
end

function Tracking.Find(recipeID, key)
    for i, t in ipairs(ns.db.tracked) do
        if t.recipe == recipeID and t.key == key then return i, t end
    end
end

function Tracking.Track(recipeID, key, count)
    local _, t = Tracking.Find(recipeID, key)
    if t then
        t.count = t.count + (count or 1)
    else
        table.insert(ns.db.tracked, { recipe = recipeID, key = key, count = count or 1 })
    end
    ns.RefreshWindow()
end

function Tracking.Change(index, delta)
    local t = ns.db.tracked[index]
    if not t then return end
    t.count = t.count + delta
    if t.count <= 0 then table.remove(ns.db.tracked, index) end
    ns.RefreshWindow()
end

function Tracking.Untrack(index)
    table.remove(ns.db.tracked, index)
    ns.RefreshWindow()
end

-- Blizzard's recipe tracker only shows on the logged-in character, so each list is handed over at login.
function Tracking.InQuestLog(recipeID, key)
    local list = ns.db.questLog[key]
    local on = list and list[recipeID]
    return on == true or on == "next"
end

function Tracking.WaitsForLogin(recipeID, key)
    local list = ns.db.questLog[key]
    return list and list[recipeID] == "next" or false
end

local function SetTracked(recipeID, on)
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
        pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, on, false)
    end
end

function Tracking.ToggleQuestLog(recipeID, key)
    local list = ns.db.questLog[key] or {}
    ns.db.questLog[key] = list
    local on = not Tracking.InQuestLog(recipeID, key)
    if key == ns.CharacterKey() then
        list[recipeID] = on or nil
        SetTracked(recipeID, on)
    else
        list[recipeID] = on and "next"
    end
    ns.RefreshWindow()
end

function Tracking.TrackedBy(recipeID, key)
    local byKey, out = {}, {}
    local function Entry(k)
        if key and k ~= key then return nil end
        if not byKey[k] then
            byKey[k] = { key = k, char = ns.db.characters[k] }
            out[#out + 1] = byKey[k]
        end
        return byKey[k]
    end
    for k, list in pairs(ns.db.questLog) do
        local e = (list[recipeID] == true or list[recipeID] == "next") and Entry(k)
        if e then e.inLog, e.waits = true, list[recipeID] == "next" end
    end
    for _, t in ipairs(ns.db.tracked) do
        local e = t.recipe == recipeID and Entry(t.key)
        if e then e.onList = true end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function Tracking.IsTracked(recipeID, key)
    return #Tracking.TrackedBy(recipeID, key) > 0
end

function Tracking.SyncQuestLog()
    local key = ns.CharacterKey()
    local list = ns.db.questLog[key] or {}
    ns.db.questLog[key] = list
    for recipeID, on in pairs(list) do
        if on == false then
            SetTracked(recipeID, false)
            list[recipeID] = nil
        end
    end
    local ok, tracked = pcall(C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked, false)
    for _, recipeID in ipairs(ok and tracked or {}) do list[recipeID] = true end
    for recipeID in pairs(list) do
        list[recipeID] = true
        SetTracked(recipeID, true)
    end
    Tracking.synced = true
end

-- The game can restore its tracker before login, when there's no character key yet.
function Tracking.OnTrackedRecipe(recipeID, tracked)
    if not Tracking.synced then return end
    local list = ns.db.questLog[ns.CharacterKey()]
    if not list or (list[recipeID] == true) == tracked then return end
    list[recipeID] = tracked or nil
    ns.RefreshWindow()
end
