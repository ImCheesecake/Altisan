-- Window.lua: the main window in either look, its sidebar, switching pages and resizing.

local _, ns = ...

local frame, body, sidebar, content
local views = {}
ns.view = { character = nil, section = nil, profession = nil, filter = "use", search = "", stats = {} }

local UI = ns.UI
local C = UI.C

local pages, pageKeys = {}, {}
function UI.AddPage(key, page)
    pages[key] = page
    pageKeys[#pageKeys + 1] = key
end
local function Opened(key, ...)
    local page = pages[key]
    if page and page.Opened then page.Opened(...) end
end

local MIN_WIDTH, MIN_HEIGHT = 900, 440
local MAX_WIDTH, MAX_HEIGHT = 1400, 1000
local FULL_WIDTH, FULL_HEIGHT = 1140, 600
local SIDEBAR_WIDTH = 190
local ENTRY_TEXT_WIDTH = SIDEBAR_WIDTH - 16 - 12

function ns.ApplyWindowScale()
    if frame then
        frame:SetScale(ns.db.window.scale)
        UI.FitDividers()
    end
end


local function PassesFilters(char, key, me)
    if key == ns.CharacterKey() then return true end
    if not ns.db.list.otherRealms and not ns.Bags.SameRuleset(char, me) then return false end
    if not ns.db.list.otherFaction and char.faction ~= me.faction then return false end
    return true
end

function ns.VisibleCharacters()
    local myKey = ns.CharacterKey()
    local me = ns.db.characters[myKey] or {}
    local list = {}
    for key, char in pairs(ns.db.characters) do
        if PassesFilters(char, key, me) then
            table.insert(list, { key = key, char = char })
        end
    end
    table.sort(list, function(a, b)
        if (a.key == myKey) ~= (b.key == myKey) then return a.key == myKey end
        if (a.char.level or 0) ~= (b.char.level or 0) then return (a.char.level or 0) > (b.char.level or 0) end
        return a.key < b.key
    end)

    local factions = {}
    for _, entry in ipairs(list) do
        if entry.char.faction then factions[entry.char.faction] = true end
    end
    return list, (factions.Horde and factions.Alliance) and true or false
end

function ns.ShowCharacter(key, profession, recipeID)
    if recipeID then ns.view.plan = nil end
    ns.view.character = key
    ns.view.section = nil
    ns.view.profession = profession
    Opened("recipes", recipeID)
    ns.RefreshWindow()
end

function ns.ShowPlan(key, profession)
    ns.view.plan, ns.view.planStep, ns.view.openRecipe = { key = key, line = profession }, nil, nil
    ns.ShowCharacter(key, profession)
end

function ns.ShowSection(section, ...)
    ns.view.character = nil
    ns.view.section = section
    Opened(section or "overview", ...)
    ns.RefreshWindow()
end

local SECTIONS = {
    { key = nil, label = "Overview" },
    { key = "coverage", label = "Coverage" },
    { key = "camp", label = "Camp" },
    { key = "shopping", label = "Shopping" },
    { key = "gathering", label = "Gathering" },
}
local SECTION_HEIGHT, CHARACTER_HEIGHT, GAP = 26, 36, 2
local PINNED = SECTION_HEIGHT + 13
local sectionButtons = {}
local charactersHeading, characterList, whatsNew

local function GetSectionButton(index)
    if sectionButtons[index] then return sectionButtons[index] end
    local b = UI.SelectableButton(sidebar, SECTION_HEIGHT)
    b:SetPoint("RIGHT")
    b.text:SetPoint("LEFT", 10, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    if UI.Style().sectionIcons then
        -- SectionIcons is a strip of 8 cells in SECTIONS order.
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetTexture(UI.MEDIA .. "SectionIcons")
        b.icon:SetTexCoord((index - 1) / 8, index / 8, 0, 1)
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 10, 0)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    end
    b:SetScript("OnClick", function(self) ns.ShowSection(self.key) end)
    sectionButtons[index] = b
    return b
end

local function ConfirmForget(key)
    local char = ns.db.characters[key]
    if not char then return end
    if not StaticPopupDialogs.ALTISAN_FORGET then
        StaticPopupDialogs.ALTISAN_FORGET = {
            text = "Forget %s?\n\n%s",
            button1 = "Forget",
            button2 = CANCEL,
            OnAccept = function(_, data) ns.ForgetCharacter(data) end,
            timeout = 0, whileDead = 1, hideOnEscape = 1,
        }
    end
    local fullName = char.fullName or char.name or key
    local color = char.class and RAID_CLASS_COLORS[char.class]
    local first = char.name or fullName
    local body = UI.ColorText(UI.TEXT.light, ("Altisan removes %s's professions, recipes, bags, bank and tracked crafts. "
        .. "Log in on %s again and Altisan reads them back."):format(first, first))
    StaticPopup_Show("ALTISAN_FORGET", color and color:WrapTextInColorCode(fullName) or fullName, body, key)
end

local function CharacterMenu(b)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local key = b.key
    local char = ns.db.characters[key]
    MenuUtil.CreateContextMenu(b, function(_, root)
        root:CreateTitle(char and char.fullName or char and char.name or key)
        root:CreateButton("Show recipes", function() ns.ShowCharacter(key) end)
        root:CreateCheckbox("Not played any more", function() return not ns.IsPlayed(key) end, function()
            ns.db.notPlayed[key] = ns.IsPlayed(key) or nil
            ns.RefreshWindow()
        end)
        root:CreateDivider()
        local forget = root:CreateButton("Forget this character…", function() ConfirmForget(key) end)
        if key == ns.CharacterKey() then
            forget:SetEnabled(false)
            if forget.SetTooltip then
                forget:SetTooltip(function(tooltip)
                    UI.TipLine(tooltip, ("You're logged in on %s: Altisan would read them again right away.")
                        :format(UI.CharName(char, key)), nil, true)
                end)
            end
        end
    end)
end

local EntryHeight
local function InitCharacterEntry(b, data)
    if not b.made then
        b.made = true
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.heading = UI.SmallHeading(b, "Not played")
        b.heading:SetPoint("BOTTOMLEFT", 10, 6)
        UI.MakeSelectable(b)
        -- Widths of their own: the list fills a row before it has one, and text laid out on
        -- no width stays cut with "..." until the next resize.
        b.text:SetPoint("TOPLEFT", 10, -4)
        b.text:SetWidth(ENTRY_TEXT_WIDTH)
        b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -3)
        b.sub:SetWidth(ENTRY_TEXT_WIDTH)
        b.sub:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self, button)
            if not self.key then return end
            if button == "RightButton" then CharacterMenu(self) else ns.ShowCharacter(self.key) end
        end)
    end
    local isHeading = data.heading and true or false
    b.heading:SetShown(isHeading)
    b.text:SetShown(not isHeading)
    b.sub:SetShown(not isHeading)
    b:EnableMouse(not isHeading)
    if isHeading then
        b.key = nil
        b.fill:SetShown(false)
        return
    end
    b.key = data.key
    b:SetHeight(EntryHeight(data))
    b.text:SetText((UI.CharacterName(data.key, data.char)))
    b.sub:SetText(data.line)
    local alpha = ns.IsPlayed(data.key) and 1 or 0.55
    b.text:SetAlpha(alpha)
    b.sub:SetAlpha(alpha)
    b.fill:SetShown(ns.view.character == data.key)
end

-- The list's extent and the entry's own height must agree, so both come from here.
function EntryHeight(data)
    if data.heading then return 26 end
    if not data.height then
        data.height = math.max(CHARACTER_HEIGHT, math.ceil(4 + UI.TextHeight(UI.CharacterName(data.key, data.char), ENTRY_TEXT_WIDTH)
            + 3 + UI.TextHeight(data.line, ENTRY_TEXT_WIDTH, "GameFontDisableSmall") + 6))
    end
    return data.height
end

local function CharacterLine(char)
    local names = {}
    for _, prof in ipairs(char.professions or {}) do
        if prof.kind == "primary" then table.insert(names, prof.name) end
    end
    local level = tostring(char.level or 0)
    return #names > 0 and ("Level " .. level .. ", " .. UI.JoinNames(names)) or ("Level " .. level)
end

local function RefreshWhatsNew()
    if not whatsNew then
        whatsNew = UI.SelectableButton(sidebar, SECTION_HEIGHT)
        whatsNew.whatsNew = true
        whatsNew:SetPoint("BOTTOMLEFT", 0, 4)
        whatsNew:SetPoint("BOTTOMRIGHT", 0, 4)
        whatsNew.text:SetPoint("LEFT", 10, 0)
        whatsNew.text:SetText("What's new")
        whatsNew.version = whatsNew:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        whatsNew.version:SetPoint("RIGHT", -8, 0)
        whatsNew.dot = whatsNew:CreateTexture(nil, "OVERLAY")
        whatsNew.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        whatsNew.dot:SetVertexColor(unpack(UI.Hex(UI.TEXT.gold)))
        whatsNew.dot:SetSize(7, 7)
        whatsNew.dot:SetPoint("RIGHT", whatsNew.version, "LEFT", -6, 0)
        UI.CircleMask(whatsNew, whatsNew.dot)
        local line = UI.Divider(sidebar)
        line:SetPoint("BOTTOMLEFT", whatsNew, "TOPLEFT", 10, 6)
        line:SetPoint("BOTTOMRIGHT", whatsNew, "TOPRIGHT", -6, 6)
        whatsNew:SetScript("OnClick", function() ns.ShowSection("whatsnew") end)
    end
    local version, unread = pages.whatsnew.Badge()
    whatsNew:SetSelected(ns.view.character == nil and ns.view.section == "whatsnew")
    whatsNew.version:SetText(version)
    whatsNew.version:SetTextColor(unpack(UI.Hex(unread and UI.TEXT.gold or UI.TEXT.muted)))
    whatsNew.dot:SetShown(unread)
end

local function RefreshSidebar(list, layoutOnly)
    local y = 6

    for i, section in ipairs(SECTIONS) do
        local b = GetSectionButton(i)
        b:SetPoint("TOPLEFT", 0, -y)
        b.key = section.key
        b.text:SetText(section.label)
        local picked = ns.view.character == nil and ns.view.section == section.key
        b:SetSelected(picked)
        if b.icon then b.icon:SetVertexColor(unpack(picked and C.sectionIconPicked or C.sectionIcon)) end
        b:Show()
        y = y + SECTION_HEIGHT + GAP
    end
    RefreshWhatsNew()

    if not charactersHeading then
        charactersHeading = UI.SmallHeading(sidebar, "Characters")
    end
    y = y + 12
    charactersHeading:SetPoint("TOPLEFT", 10, -y)
    y = y + 16

    if not characterList then
        characterList = UI.ScrollList(sidebar, EntryHeight, InitCharacterEntry, GAP)
        sidebar.characterList = characterList
    end
    if layoutOnly and characterList.box:HasDataProvider() then return end
    UI.PlaceList(characterList, -y, PINNED)
    local items, later = {}, {}
    for _, entry in ipairs(list) do
        local item = { key = entry.key, char = entry.char, line = CharacterLine(entry.char) }
        table.insert(ns.IsPlayed(entry.key) and items or later, item)
    end
    if #later > 0 then
        items[#items + 1] = { heading = true }
        for _, item in ipairs(later) do items[#items + 1] = item end
    end
    characterList.box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
end

local function CreateWindow()
    local style = UI.Style()
    frame = ns.WindowLooks[UI.STYLES[ns.db.window.look] and ns.db.window.look or "radar"]()
    sectionButtons, charactersHeading, characterList, whatsNew = {}, nil, nil, nil

    -- UIParent's size is in UI units, before our own scale.
    local width, height = ns.db.window.width, ns.db.window.height
    if not width then
        local scale = ns.db.window.scale or 1
        width = math.min(FULL_WIDTH, math.floor(UIParent:GetWidth() * 0.9 / scale))
        height = math.min(FULL_HEIGHT, math.floor(UIParent:GetHeight() * 0.8 / scale))
    end
    frame:SetSize(math.max(width, MIN_WIDTH), math.max(height or MIN_HEIGHT, MIN_HEIGHT))
    frame:SetPoint("CENTER")

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    if not tContains(UISpecialFrames, "AltisanFrame") then
        table.insert(UISpecialFrames, "AltisanFrame")
    end

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -style.bodyTop)
    body:SetPoint("BOTTOMRIGHT", 0, style.bodyBottom)

    sidebar = CreateFrame("Frame", nil, body)
    sidebar:SetPoint("TOPLEFT", style.pad, 0)
    sidebar:SetPoint("BOTTOMLEFT", style.pad, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)

    local line = UI.Divider(body, true)
    line:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, -6)
    line:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 8, 0)

    content = CreateFrame("Frame", nil, body)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 18, 0)
    content:SetPoint("BOTTOMRIGHT", -style.pad, 0)

    for _, key in ipairs(pageKeys) do views[key] = pages[key].Build(content) end

    -- OnSizeChanged fires every frame while dragging, so it only re-lays out; letting go rebuilds.
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:SetScript("OnSizeChanged", function() ns.RefreshWindow(true) end)
    local grip = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
    grip:SetPoint("BOTTOMRIGHT", -style.grip, style.grip)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:Init(frame, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    grip.resizeStoppedCallback = function()
        ns.db.window.width, ns.db.window.height = frame:GetSize()
        ns.RefreshWindow()
    end

    frame:SetScript("OnShow", function() ns.RefreshWindow() end)
    frame:Hide()
    ns.ApplyWindowScale()
    UI.RoundToPixels(frame)
end

function ns.RebuildWindow()
    if not frame then return end
    local wasShown = frame:IsShown()
    local point, _, relativePoint, x, y = frame:GetPoint()
    frame:Hide()
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnSizeChanged", nil)

    CreateWindow()
    if point then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relativePoint, x, y)
    end
    if wasShown then frame:Show() end
end

local function Refresh(layoutOnly)
    if not (frame and frame:IsShown()) then return end
    if frame.FitFrame then frame.FitFrame() end

    local list, mixed = ns.VisibleCharacters()
    frame.subtitle:SetText(UI.Count(#list, "character", "characters"))

    local selected = ns.view.character and ns.db.characters[ns.view.character]
    if selected then
        local listed = false
        for _, entry in ipairs(list) do
            if entry.key == ns.view.character then listed = true end
        end
        if not listed then selected = nil end
    end
    if not selected then ns.view.character = nil end

    RefreshSidebar(list, layoutOnly)

    -- From the window's own size: the content frame's size may not be known yet on first open.
    local style = UI.Style()
    local height = frame:GetHeight() - style.bodyTop - style.bodyBottom
    local width = frame:GetWidth() - 2 * style.pad - SIDEBAR_WIDTH - 18

    local shown = selected and "recipes" or ns.view.section or "overview"
    for key, view in pairs(views) do view:SetShown(key == shown) end
    pages[shown].Refresh(list, width, height, layoutOnly, mixed)
    if not layoutOnly then
        for _, view in pairs(views) do
            if view:IsShown() then UI.RoundToPixels(view) end
        end
    end
end

ns.OnRefresh(Refresh)

function ns.SetWindowSize(width, height)
    if not frame then CreateWindow() end
    if width and height then
        width = math.min(math.max(width, MIN_WIDTH), MAX_WIDTH)
        height = math.min(math.max(height, MIN_HEIGHT), MAX_HEIGHT)
        frame:SetSize(width, height)
        ns.db.window.width, ns.db.window.height = width, height
        if frame:IsShown() then ns.RefreshWindow() else frame:Show() end
    end
    local w, h = frame:GetSize()
    -- A UI unit is 768 / screen height pixels at scale 1.
    local px = frame:GetEffectiveScale() * select(2, GetPhysicalScreenSize()) / 768
    return math.floor(w + 0.5), math.floor(h + 0.5), math.floor(w * px + 0.5), math.floor(h * px + 0.5)
end

function ns.ShowWindow()
    if not frame then CreateWindow() end
    frame:Show()
end

function ns.ToggleWindow()
    if frame and frame:IsShown() then frame:Hide() else ns.ShowWindow() end
end
