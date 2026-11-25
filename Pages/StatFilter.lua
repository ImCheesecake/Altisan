-- StatFilter.lua: the Stats filter in a character's recipe list: reads each crafted item's stats
-- once (saved in AltisanDB.itemStats), its menu rows and chips. RecipeView does the filtering.

local _, ns = ...

local Stats = {}
ns.StatFilter = Stats

local PRIMARY = {
    { key = "ITEM_MOD_STRENGTH_SHORT", short = "Str" },
    { key = "ITEM_MOD_AGILITY_SHORT", short = "Agi" },
    { key = "ITEM_MOD_STAMINA_SHORT", short = "Sta" },
    { key = "ITEM_MOD_INTELLECT_SHORT", short = "Int" },
    { key = "ITEM_MOD_SPIRIT_SHORT", short = "Spi" },
}
local PRIMARY_RANK, SHORT = {}, {}
for i, stat in ipairs(PRIMARY) do
    PRIMARY_RANK[stat.key] = i
    SHORT[stat.key] = stat.short
end

local ARMOR = "RESISTANCE0_NAME"

-- The game reports a resistance under two names: RESISTANCE2_NAME ("Fire Resistance") and
-- ITEM_MOD_FIRE_RESISTANCE_SHORT ("Fire resistance"). Keep one, or the menu lists it twice.
local RESISTANCE_SCHOOLS = { HOLY = 1, FIRE = 2, NATURE = 3, FROST = 4, SHADOW = 5, ARCANE = 6 }
function Stats.Normalize(stats)
    for key, value in pairs(stats) do
        local school = key:match("^ITEM_MOD_(%u+)_RESISTANCE_SHORT$")
        if school and RESISTANCE_SCHOOLS[school] then
            local canonical = "RESISTANCE" .. RESISTANCE_SCHOOLS[school] .. "_NAME"
            stats[canonical] = stats[canonical] or value
            stats[key] = nil
        end
    end
    return stats
end

local function ResistanceNumber(key)
    return tonumber(key:match("^RESISTANCE(%d)_NAME$"))
end
local function Group(key)
    if PRIMARY_RANK[key] or ResistanceNumber(key) then return "stats" end
    return "equip"
end

function Stats.Name(key)
    local name = _G[key]
    if type(name) == "string" and name ~= "" then return name end
    local words = key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
    return (words:gsub("^%l", string.upper))
end

-- Ratings are internal numbers (crit 14 = "1.0%" on the tooltip): never show those numbers.
local function IsRating(key)
    return key:find("_RATING") ~= nil
end

local function SortKey(key)
    if PRIMARY_RANK[key] then return ("1%02d"):format(PRIMARY_RANK[key]) end
    local resistance = ResistanceNumber(key)
    if resistance then return "2" .. resistance end
    return "3" .. Stats.Name(key):lower()
end
local function Sorted(keys)
    table.sort(keys, function(a, b) return SortKey(a) < SortKey(b) end)
    return keys
end

function Stats.RowText(stats)
    if not stats or next(stats) == nil then return nil end
    local keys = {}
    for key in pairs(stats) do keys[#keys + 1] = key end
    local parts = {}
    for _, key in ipairs(Sorted(keys)) do
        if IsRating(key) then
            parts[#parts + 1] = Stats.Name(key)
        else
            parts[#parts + 1] = ("+%d %s"):format(stats[key], SHORT[key] or Stats.Name(key))
        end
    end
    return table.concat(parts, "  ")
end

local pending = {}
local refreshQueued = false

function Stats.Get(itemID)
    return itemID and ns.db.itemStats[itemID]
end

-- GetItemStats works only once the item is loaded, and counts armor as a stat (RESISTANCE0_NAME).
local function Save(itemID)
    local saved = {}
    local stats = C_Item.GetItemStats("item:" .. itemID)
    for key, value in pairs(stats or {}) do
        if key ~= ARMOR and value ~= 0 then saved[key] = value end
    end
    ns.db.itemStats[itemID] = Stats.Normalize(saved)
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function()
        refreshQueued = false
        if ns.RecipeView then ns.RecipeView.RefreshList() end
    end)
end

local unavailable = {}

-- ContinueOnItemLoad errors on an item the client lacks, so check DoesItemExistByID first. On
-- success = false, saving would store "no stats" for good, so skip the item this session only.
function Stats.Load(itemIDs)
    for _, itemID in ipairs(itemIDs) do
        if not ns.db.itemStats[itemID] and not pending[itemID] and not unavailable[itemID] then
            if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(itemID) then
                unavailable[itemID] = true
            else
                pending[itemID] = true
                Item:CreateFromItemID(itemID):ContinueOnItemLoad(function(_, success)
                    pending[itemID] = nil
                    if success == false then
                        unavailable[itemID] = true
                    else
                        Save(itemID)
                    end
                    QueueRefresh()
                end)
            end
        end
    end
end

local function Loading()
    return next(pending) ~= nil
end

function Stats.Selected()
    ns.view.stats = ns.view.stats or {}
    return ns.view.stats
end

function Stats.IsSelected(key)
    return tContains(Stats.Selected(), key)
end

function Stats.Matches(stats)
    local selected = Stats.Selected()
    if #selected == 0 then return true end
    if not stats then return false end
    for _, key in ipairs(selected) do
        if not stats[key] then return false end
    end
    return true
end

local function Toggle(key)
    local selected = Stats.Selected()
    for i, k in ipairs(selected) do
        if k == key then
            table.remove(selected, i)
            ns.RecipeView.RefreshList()
            return
        end
    end
    table.insert(selected, key)
    ns.RecipeView.RefreshList()
end

local function Clear()
    ns.view.stats = {}
    ns.RecipeView.RefreshList()
end

function Stats.SelectedNames()
    local names = {}
    for i, key in ipairs(Stats.Selected()) do names[i] = Stats.Name(key) end
    return ns.UI.JoinNames(names)
end

function Stats.Summary(total)
    return ("%s with %s"):format(ns.UI.Count(total, "recipe", "recipes"), Stats.SelectedNames())
end

local UI, Dropdown
local button, popup, chips
local menuRows, headers = {}, {}
local current = { present = {}, counts = {} }

local MENU_WIDTH = 260
local MENU_ROW = 24

local function MenuHeader(index, text)
    local h = headers[index]
    if not h then
        h = Dropdown.Header(popup, text)
        headers[index] = h
    end
    h:SetText(text:upper())
    h:Show()
    return h
end

local function MenuRow(index)
    local row = menuRows[index]
    if row then return row end
    row = Dropdown.CheckRow(popup, MENU_WIDTH - 20, MENU_ROW)
    row:SetScript("OnClick", function(self) Toggle(self.key) end)
    menuRows[index] = row
    return row
end

local function RefreshMenu()
    for _, row in ipairs(menuRows) do row:Hide() end
    for _, h in ipairs(headers) do h:Hide() end

    local groups = { stats = {}, equip = {} }
    for key in pairs(current.present) do table.insert(groups[Group(key)], key) end

    local y, rowIndex, headerIndex = -12, 0, 0
    for _, group in ipairs({ { key = "stats", label = "Stats" }, { key = "equip", label = "Equip bonuses" } }) do
        local keys = Sorted(groups[group.key])
        if #keys > 0 then
            headerIndex = headerIndex + 1
            if headerIndex > 1 then y = y - 8 end
            local h = MenuHeader(headerIndex, group.label)
            h:SetPoint("TOPLEFT", 16, y)
            y = y - 18
            for _, key in ipairs(keys) do
                rowIndex = rowIndex + 1
                local row = MenuRow(rowIndex)
                local checked = Stats.IsSelected(key)
                row.key = key
                row:SetPoint("TOPLEFT", 10, y)
                local count = current.counts[key] or 0
                y = y - row:Set(Stats.Name(key), (count > 0 or checked) and tostring(count) or "", checked)
            end
        end
    end

    if rowIndex == 0 then
        popup.empty:SetText(Loading() and "Reading item stats..." or "Nothing this profession makes has stats.")
        popup.empty:SetPoint("TOPLEFT", 16, y)
        popup.empty:Show()
        y = y - 24
    else
        popup.empty:Hide()
    end

    popup.divider:SetPoint("TOPLEFT", 10, y - 6)
    popup.divider:SetPoint("TOPRIGHT", -10, y - 6)
    popup.footer:SetPoint("TOPLEFT", 16, y - 17)
    popup.footer:SetWidth(MENU_WIDTH - 16 - 10 - popup.clear:GetWidth() - 8)
    popup.clear:SetPoint("TOPRIGHT", -10, y - 12)
    popup:SetHeight(-y + 17 + math.max(popup.footer:GetStringHeight(), 18) + 6)
end

function Stats.RefreshButton()
    local count = #Stats.Selected()
    button:SetState(count > 0 and ("Stats: " .. count) or "Stats", count > 0, popup:IsShown())
end

local function RefreshChips(into)
    local picks = {}
    for i, key in ipairs(Stats.Selected()) do picks[i] = { label = Stats.Name(key), value = key } end
    return chips.Lay(picks, into)
end

function Stats.Hide(into)
    button:Hide()
    popup:Hide()
    return chips.Lay({}, into)
end

function Stats.Update(present, counts, into)
    current.present, current.counts = present, counts
    for _, key in ipairs(Stats.Selected()) do current.present[key] = true end
    Stats.RefreshButton()
    if popup:IsShown() then RefreshMenu() end
    return RefreshChips(into)
end

function Stats.Build(parent)
    UI, Dropdown = ns.UI, ns.Dropdown
    menuRows, headers = {}, {}
    chips = Dropdown.Chips(parent, Toggle)
    -- Saves from older versions keep a resistance under two names.
    for _, stats in pairs(ns.db.itemStats) do Stats.Normalize(stats) end

    button, popup = Dropdown.Menu(parent, MENU_WIDTH, RefreshMenu, function() Stats.RefreshButton() end)
    Stats.button, Stats.popup = button, popup

    popup.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.empty:SetTextColor(unpack(UI.Hex(UI.TEXT.muted)))
    popup.divider = ns.UI.Divider(popup)
    popup.footer = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.footer:SetTextColor(unpack(UI.Hex(UI.TEXT.muted)))
    popup.footer:SetText("Ticked stats must all be on the item")
    popup.clear = CreateFrame("Button", nil, popup)
    popup.clear:SetSize(44, 20)
    popup.clear.text = popup.clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popup.clear.text:SetPoint("CENTER")
    popup.clear.text:SetTextColor(unpack(UI.Hex(UI.TEXT.gold)))
    popup.clear.text:SetText("Clear")
    UI.RoundedHover(popup.clear, 5)
    popup.clear:SetScript("OnClick", Clear)

    Stats.RefreshButton()
    return button
end
