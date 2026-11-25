-- Core.lua: saved data, events, the character scan and the slash command.

local ADDON_NAME, ns = ...

ns.TITLE = "Altisan"
ns.ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"

local DEFAULTS = {
    tracker = {
        attached = true,
    },
    minimap = {         -- LibDBIcon reads these fields by name.
        hide = false,
        minimapPos = 225,
    },
    window = {
        look = "radar",
        scale = 1,
        tooltips = "mouse",
        card = true,
        planCard = true,
        cardsHidden = false,
        slotNotes = true,
        plan = true,
        planFolded = {},
    },
    list = {
        otherRealms = false,   -- Forever reports rulesets as realms.
        otherFaction = true,
    },
    characters = {},
    collapsed = {},
    categories = {},
    recipes = {},
    itemStats = {},
    dismissed = {
        items = {},
    },
    notPlayed = {},
    tooltips = {
        items = true,
        shiftOnly = false,
        keepForLater = true,
        reach = 20,
        counts = true,
    },
    accountBank = {},
    tracked = {},
    plans = {},
    questLog = {},
    stock = {},
    stockInTracker = false,
    ignored = {},
    trainerSkill = {},
    favorPrice = {},
    errors = {},
}

local MAX_ERRORS = 10
local early = {}
local function KeepError(message, stack)
    if canaccessvalue and not canaccessvalue(message) then return end
    local text = tostring(message)
    if not (text:find("AddOns[\\/]" .. ADDON_NAME .. "[\\/]") or text:find("^" .. ADDON_NAME .. " ")) then return end
    local list = ns.db and ns.db.errors or early
    local now = date("%Y-%m-%d %H:%M")
    for _, e in ipairs(list) do
        if e.message == text then
            e.count, e.last = e.count + 1, now
            return
        end
    end
    list[#list + 1] = { message = text, stack = stack, count = 1, first = now, last = now }
    while #list > MAX_ERRORS do table.remove(list, 1) end
end
local gameHandler = geterrorhandler()
seterrorhandler(function(message, ...)
    pcall(KeepError, message, debugstack and debugstack(2, 12, 0) or nil)
    return gameHandler(message, ...)
end)

local function FillDefaults(saved, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(saved[key]) ~= "table" then saved[key] = {} end
            FillDefaults(saved[key], value)
        elseif saved[key] == nil then
            saved[key] = value
        end
    end
end

-- On Forever, UnitName's second value is a surname, not a realm ("Lilith", "Skyborn").
function ns.PlayerNames()
    local name, surname = UnitName("player")
    local fullName = name
    if NameUtil and NameUtil.GetFullNameWithoutRealm then
        fullName = NameUtil.GetFullNameWithoutRealm(name, surname)
    end
    return name, surname, fullName
end

local redraws = {}
function ns.OnRefresh(redraw) redraws[#redraws + 1] = redraw end
ns.dataStamp = 0
function ns.RefreshWindow(layoutOnly)
    if not layoutOnly then ns.dataStamp = ns.dataStamp + 1 end
    for _, redraw in ipairs(redraws) do redraw(layoutOnly) end
end

function ns.OpenSettings()
    if ns.settingsCategory then Settings.OpenToCategory(ns.settingsCategory:GetID()) end
end

function ns.IsPlayed(key)
    return not (ns.db.notPlayed and ns.db.notPlayed[key])
end

-- The realm must come from GetNormalizedRealmName.
function ns.CharacterKey()
    local _, _, fullName = ns.PlayerNames()
    return fullName .. "-" .. GetNormalizedRealmName()
end

local function MoveOldRecord()
    local name, second = UnitFullName("player")
    if not (name and second and second ~= "") then return end
    local oldKey = name .. "-" .. second
    local newKey = ns.CharacterKey()
    local chars = ns.db.characters
    if oldKey ~= newKey and chars[oldKey] and not chars[newKey] then
        chars[newKey] = chars[oldKey]
    end
    if oldKey ~= newKey then chars[oldKey] = nil end
end

function ns.CurrentCharacter()
    local key = ns.CharacterKey()
    local chars = ns.db.characters
    chars[key] = chars[key] or {}
    return chars[key], key
end

-- Never the one logged in: the next scan would bring them straight back.
function ns.ForgetCharacter(key)
    if key == ns.CharacterKey() then return end
    local db = ns.db
    local lines = {}
    for line in pairs(db.characters[key] and db.characters[key].recipes or {}) do lines[#lines + 1] = line end
    db.characters[key] = nil
    db.notPlayed[key] = nil
    db.questLog[key] = nil
    for _, line in ipairs(lines) do ns.FillLoginListsFrom(line) end
    for _, saved in ipairs({ db.tracked, db.plans }) do
        for i = #saved, 1, -1 do
            if saved[i].key == key then table.remove(saved, i) end
        end
    end
    if ns.view and ns.view.character == key then ns.view.character = nil end
    ns.ItemUses.Forget()
    ns.RefreshWindow()
end

-- GetProfessions() on Forever: primary, primary, First Aid, Fishing, Cooking.
local SLOT_KINDS = { "primary", "primary", "secondary", "secondary", "secondary" }

function ns.ScanCharacter()
    local char = ns.CurrentCharacter()

    local className, classFile = UnitClass("player")
    local name, surname, fullName = ns.PlayerNames()
    char.name = name
    char.surname = surname
    char.fullName = fullName
    char.realm = GetNormalizedRealmName()
    char.class = classFile
    char.className = className
    char.level = UnitLevel("player")
    char.faction = UnitFactionGroup("player")
    char.race = select(2, UnitRace("player"))
    char.sex = UnitSex("player")
    char.lastSeen = time()

    char.professions = {}
    local slots = { GetProfessions() }
    for slot = 1, 5 do
        local index = slots[slot]
        if index then
            local name, icon, skill, maxSkill, _, _, skillLine = GetProfessionInfo(index)
            table.insert(char.professions, {
                name = name,
                icon = icon,
                skill = skill,
                maxSkill = maxSkill,
                skillLine = skillLine,
                kind = SLOT_KINDS[slot],
            })
        end
    end

    ns.ReadKnownAtLogin()
    ns.ItemUses.Forget()
    ns.RefreshWindow()
end

-- Logging in fires a burst of skill events; scan once a second later.
local scanPending = false
function ns.ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(1, function()
        scanPending = false
        ns.ScanCharacter()
    end)
end

ns.L = setmetatable({}, { __index = function(_, phrase) return phrase end })
function ns.TrackerHostSettings() return ns.db and ns.db.tracker end

local events = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(name)
    -- Blizzard's profession window loads the first time it's opened.
    if name == "Blizzard_Professions" then ns.ProfessionCard.Init() return end
    if name ~= ADDON_NAME then return end
    local isNew = AltisanDB == nil
    AltisanDB = AltisanDB or {}
    local window = AltisanDB.window
    if window and window.card == false and window.planCard == nil then window.planCard = false end
    FillDefaults(AltisanDB, DEFAULTS)
    AltisanDB.window.style = nil
    if AltisanDB.window.look == "blizzard" then AltisanDB.window.look = "radar" end
    ns.ForgetOldScans(AltisanDB)
    if not AltisanDB.tooltips.reachMoved then
        if AltisanDB.tooltips.reach == 50 then AltisanDB.tooltips.reach = 20 end
        AltisanDB.tooltips.reachMoved = true
    end
    -- Every save holds the old default, so changing DEFAULTS alone moves nothing.
    if not AltisanDB.list.rulesetsMoved then
        AltisanDB.list.otherRealms = false
        AltisanDB.list.rulesetsMoved = true
    end
    ns.db = AltisanDB
    for _, e in ipairs(early) do KeepError(e.message, e.stack) end
    ns.WhatsNew.Init(AltisanDB, isNew)
end

function handlers.PLAYER_LOGIN()
    MoveOldRecord()
    ns.ScanCharacter()
    ns.CreateMinimapButton()
    ns.CreateSettings()
    ns.ItemTooltip.Init()
    ns.Bags.ScanBags()
    ns.Mail.Init()
    ns.Tracking.SyncQuestLog()
    ns.Cooldowns.ReadItems(ns.CurrentCharacter())
    if C_AddOns.IsAddOnLoaded("Blizzard_Professions") then ns.ProfessionCard.Init() end
    ns.RedrawTracker()
end

function handlers.TRACKED_RECIPE_UPDATE(recipeID, tracked) ns.Tracking.OnTrackedRecipe(recipeID, tracked) end

function handlers.SKILL_LINES_CHANGED() ns.ScanSoon() end
function handlers.PLAYER_LEVEL_UP() ns.ScanSoon() end

function handlers.TRADE_SKILL_SHOW() ns.ScanProfessionSoon() end
function handlers.TRADE_SKILL_LIST_UPDATE() ns.ScanProfessionSoon() end
function handlers.NEW_RECIPE_LEARNED(recipeID) ns.OnRecipeLearned(recipeID) end
-- A craft can start a cooldown; the scan reads it while the window is open.
function handlers.UNIT_SPELLCAST_SUCCEEDED(unit)
    if unit == "player" and ProfessionsFrame and ProfessionsFrame:IsShown() then ns.ScanProfessionSoon() end
end
function handlers.BAG_UPDATE_COOLDOWN() ns.Cooldowns.ReadItems(ns.CurrentCharacter()) end

function handlers.BAG_UPDATE_DELAYED()
    ns.Bags.OnBagsChanged()
    ns.RedrawTracker()
end
function handlers.PLAYERBANKSLOTS_CHANGED() ns.Bags.OnBagsChanged() end
function handlers.BANKFRAME_OPENED() ns.Bags.OnBankOpened() end
function handlers.BANKFRAME_CLOSED() ns.Bags.OnBankClosed() end
function handlers.TRAINER_SHOW() ns.Trainers.Read(true) end
function handlers.TRAINER_UPDATE() ns.Trainers.Read() end
function handlers.TRAINER_CLOSED() ns.Trainers.PutFiltersBack() end
function handlers.MERCHANT_SHOW() ns.Favor.ReadMerchant() end
function handlers.MERCHANT_UPDATE() ns.Favor.ReadMerchant() end
function handlers.MAIL_SHOW() ns.Mail.OnShow() end
function handlers.MAIL_INBOX_UPDATE() ns.Mail.Read() end
function handlers.MAIL_CLOSED() ns.Mail.OnClosed() end
function handlers.MAIL_SEND_SUCCESS() ns.Mail.OnSendSuccess() end
function handlers.MAIL_FAILED() ns.Mail.OnSendFailed() end

function handlers.ACHIEVEMENT_EARNED()
    ns.Legacy.Forget()
    ns.RefreshWindow()
end

for event in pairs(handlers) do
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        events:RegisterUnitEvent(event, "player")
    else
        events:RegisterEvent(event)
    end
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

BINDING_HEADER_ALTISAN = ns.TITLE
BINDING_NAME_ALTISAN_TOGGLE = "Open Altisan"
function Altisan_ToggleWindow() ns.ToggleWindow() end

SLASH_ALTISAN1 = "/altisan"
SLASH_ALTISAN2 = "/alt"
SlashCmdList.ALTISAN = function(msg)
    msg = strtrim(tostring(msg or "")):lower()
    local width, height = msg:match("^size%s+(%d+)%s*[x%s]%s*(%d+)$")
    if msg == "size" or width then
        local w, h, pw, ph = ns.SetWindowSize(tonumber(width), tonumber(height))
        print(("%s: the window is %d x %d (%d x %d pixels on your screen). /alt size 1140 600 sets it.")
            :format(ns.TITLE, w, h, pw, ph))
    elseif msg == "minimap" then
        ns.SetMinimapShown(ns.db.minimap.hide)
    elseif msg == "debug" then
        ns.DebugProfession()
    elseif msg == "check" then
        ns.RunChecks()
    else
        ns.ToggleWindow()
    end
end
