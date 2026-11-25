-- SlotFilter.lua: the Slot filter in a character's recipe list: one slot pick (a radio list),
-- plus an armor type list when the profession makes more than one type. Nothing is saved.

local _, ns = ...

local Slots = {}
ns.SlotFilter = Slots

local SLOT_ORDER = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST",
    "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST",
    "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONOFFHAND",
    "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN", "INVTYPE_AMMO", "INVTYPE_RELIC", "INVTYPE_BAG", "INVTYPE_QUIVER",
}
local SLOT_RANK = {}
for i, key in ipairs(SLOT_ORDER) do SLOT_RANK[key] = i end

local OTHER = "OTHER"

local FALLBACK_NAMES = {
    INVTYPE_CLOAK = "Back", INVTYPE_ROBE = "Chest", INVTYPE_BODY = "Shirt", INVTYPE_HAND = "Hands",
    INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_SHIELD = "Off Hand", INVTYPE_HOLDABLE = "Held In Off-hand",
    INVTYPE_RANGEDRIGHT = "Ranged",
}

local function SlotName(key)
    if key == OTHER then return "Other" end
    local name = _G[key]
    if type(name) == "string" and name ~= "" then return name end
    if FALLBACK_NAMES[key] then return FALLBACK_NAMES[key] end
    local words = key:gsub("^INVTYPE_", ""):lower()
    return (words:gsub("^%l", string.upper))
end

-- INVTYPE_ROBE and INVTYPE_CHEST both show as "Chest": one key per shown name.
local sameAs = {}
local function SlotKey(equipLoc)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE"
        or equipLoc == "INVTYPE_NON_EQUIP" then
        return OTHER
    end
    if sameAs[equipLoc] then return sameAs[equipLoc] end
    local name = SlotName(equipLoc)
    local key = equipLoc
    for _, k in ipairs(SLOT_ORDER) do
        if SlotName(k) == name then key = k break end
    end
    sameAs[equipLoc] = key
    return key
end

-- Cloaks are left out: they're all cloth, even Leatherworking's.
local ARMOR_CLASS = 4
local ARMOR_TYPES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

local function ArmorName(subclass)
    local name = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(ARMOR_CLASS, subclass)
    return (type(name) == "string" and name ~= "") and name or ARMOR_TYPES[subclass]
end

local info = {}
function Slots.Info(itemID)
    if not itemID then return OTHER, nil end
    local known = info[itemID]
    if known then return known[1], known[2] end
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    local slot = SlotKey(equipLoc)
    local armor = classID == ARMOR_CLASS and ARMOR_TYPES[subclassID] and equipLoc ~= "INVTYPE_CLOAK"
        and subclassID or nil
    info[itemID] = { slot, armor }
    return slot, armor
end

function Slots.Matches(slot, armor)
    local view = ns.view
    return (view.slot == nil or view.slot == slot) and (view.armor == nil or view.armor == armor)
end

function Slots.Describe()
    local view = ns.view
    if view.slot == nil and view.armor == nil then return nil end
    local slot = view.slot and (view.slot == OTHER and "other items" or SlotName(view.slot):lower())
    local armor = view.armor and ArmorName(view.armor):lower()
    if slot and armor then return armor .. " " .. slot end
    return slot or (armor .. " armor")
end

local function Pick(field, value)
    ns.view[field] = value
    ns.RecipeView.RefreshList()
end

function Slots.NewTally()
    local tally = { slots = {}, armors = {}, slotCounts = {}, armorCounts = {}, anySlot = 0, anyArmor = 0 }
    function tally:See(slot, armor)
        self.slots[slot] = true
        if armor then self.armors[armor] = true end
    end
    function tally:Count(slot, armor)
        local view = ns.view
        if view.armor == nil or view.armor == armor then
            self.slotCounts[slot] = (self.slotCounts[slot] or 0) + 1
            self.anySlot = self.anySlot + 1
        end
        if view.slot == nil or view.slot == slot then
            if armor then self.armorCounts[armor] = (self.armorCounts[armor] or 0) + 1 end
            self.anyArmor = self.anyArmor + 1
        end
    end
    return tally
end

local UI, Dropdown
local button, popup, chips
local slotRows, armorRows = {}, {}
local current = { tally = Slots.NewTally(), profession = "" }

local COLUMN_WIDTH = 190
local COLUMN_GAP = 17
local MENU_ROW = 24

local function Wanted(tally)
    for slot in pairs(tally.slots) do
        if slot ~= OTHER then return true end
    end
    return ns.view.slot ~= nil or ns.view.armor ~= nil
end

local function ArmorTypes(tally)
    local list = {}
    for subclass = 1, 4 do
        if tally.armors[subclass] or ns.view.armor == subclass then list[#list + 1] = subclass end
    end
    return list
end

local function ShowsArmor(tally)
    return #ArmorTypes(tally) > 1 or ns.view.armor ~= nil
end

local function MenuRow(pool, index)
    local row = pool[index]
    if row then return row end
    row = Dropdown.RadioRow(popup, COLUMN_WIDTH, MENU_ROW)
    row:SetScript("OnClick", function(self)
        Pick(self.field, self.value)
        if not ShowsArmor(current.tally) then popup:Hide() end
    end)
    pool[index] = row
    return row
end

local function FillRow(row, field, value, name, count, x, y)
    local picked = ns.view[field] == value
    row.field, row.value = field, value
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", x, y)
    return y - row:Set(name, (count > 0 or picked) and tostring(count) or "", picked)
end

local function MakesTypes(list)
    local names = {}
    for i, subclass in ipairs(list) do names[i] = ArmorName(subclass):lower() end
    return (#names == 2 and "makes both " or "makes ") .. UI.JoinNames(names)
end

local function RefreshMenu()
    for _, row in ipairs(slotRows) do row:Hide() end
    for _, row in ipairs(armorRows) do row:Hide() end
    local tally, profession = current.tally, current.profession

    local slots = {}
    for slot in pairs(tally.slots) do
        if slot ~= OTHER then slots[#slots + 1] = slot end
    end
    if ns.view.slot and not tally.slots[ns.view.slot] and ns.view.slot ~= OTHER then
        slots[#slots + 1] = ns.view.slot
    end
    table.sort(slots, function(a, b)
        local ra, rb = SLOT_RANK[a] or 99, SLOT_RANK[b] or 99
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    if tally.slots[OTHER] or ns.view.slot == OTHER then slots[#slots + 1] = OTHER end

    local x, top = 10, -12
    popup.slotHeader:SetPoint("TOPLEFT", x + 6, top)
    local y = FillRow(MenuRow(slotRows, 1), "slot", nil, "Any slot", tally.anySlot, x, top - 18)
    for i, slot in ipairs(slots) do
        y = FillRow(MenuRow(slotRows, i + 1), "slot", slot, SlotName(slot), tally.slotCounts[slot] or 0, x, y)
    end
    local slotBottom = y

    local twoColumns = ShowsArmor(tally)
    popup.armorHeader:SetShown(twoColumns)
    popup.columnLine:SetShown(twoColumns)
    local bottom
    if twoColumns then
        local ax = x + COLUMN_WIDTH + COLUMN_GAP
        popup.columnLine:SetPoint("TOPLEFT", x + COLUMN_WIDTH + 8, top)
        popup.armorHeader:SetPoint("TOPLEFT", ax + 6, top)
        y = FillRow(MenuRow(armorRows, 1), "armor", nil, "Any", tally.anyArmor, ax, top - 18)
        local types = ArmorTypes(tally)
        for i, subclass in ipairs(types) do
            y = FillRow(MenuRow(armorRows, i + 1), "armor", subclass, ArmorName(subclass),
                        tally.armorCounts[subclass] or 0, ax, y)
        end
        popup.note:ClearAllPoints()
        popup.note:SetPoint("TOPLEFT", ax + 6, y - 8)
        popup.note:SetWidth(COLUMN_WIDTH - 12)
        popup.note:SetText(#types > 1 and ("Shown because " .. profession .. " " .. MakesTypes(types) .. ".") or "")
        popup.footerLine:Hide()
        bottom = math.min(slotBottom, y - 8 - popup.note:GetStringHeight())
        popup:SetWidth(2 * COLUMN_WIDTH + COLUMN_GAP + 20)
    else
        local types = ArmorTypes(tally)
        local text = "Only slots " .. profession .. " makes."
        if #types == 1 then
            text = text .. " " .. profession .. " is all " .. ArmorName(types[1]):lower() .. ", so there's no armor type."
        end
        popup.footerLine:Show()
        popup.footerLine:SetPoint("TOPLEFT", x, slotBottom - 6)
        popup.footerLine:SetPoint("TOPRIGHT", -10, slotBottom - 6)
        popup.note:ClearAllPoints()
        popup.note:SetPoint("TOPLEFT", x + 6, slotBottom - 14)
        popup.note:SetWidth(COLUMN_WIDTH - 12)
        popup.note:SetText(text)
        bottom = slotBottom - 14 - popup.note:GetStringHeight()
        popup:SetWidth(COLUMN_WIDTH + 20)
    end
    popup.columnLine:SetHeight(top - bottom)
    popup:SetHeight(-bottom + 12)
end

function Slots.RefreshButton()
    local view = ns.view
    local parts = {}
    if view.slot then parts[#parts + 1] = SlotName(view.slot) end
    if view.armor then parts[#parts + 1] = ArmorName(view.armor) end
    local active = #parts > 0
    button:SetState(active and ("Slot: " .. table.concat(parts, ", ")) or "Slot", active, popup:IsShown())
end

local function RefreshChips(into)
    local picks = {}
    if ns.view.slot then picks[#picks + 1] = { label = SlotName(ns.view.slot), value = "slot" } end
    if ns.view.armor then picks[#picks + 1] = { label = ArmorName(ns.view.armor), value = "armor" } end
    return chips.Lay(picks, into)
end

function Slots.Hide(into)
    button:Hide()
    popup:Hide()
    return chips.Lay({}, into)
end

function Slots.Update(tally, profession, into)
    current.tally, current.profession = tally, profession or ""
    button:SetShown(Wanted(tally))
    if not button:IsShown() then popup:Hide() end
    Slots.RefreshButton()
    if popup:IsShown() then RefreshMenu() end
    return RefreshChips(into)
end

function Slots.Build(parent)
    UI, Dropdown = ns.UI, ns.Dropdown
    slotRows, armorRows = {}, {}
    chips = Dropdown.Chips(parent, function(field) Pick(field, nil) end)

    button, popup = Dropdown.Menu(parent, COLUMN_WIDTH + 20, RefreshMenu, function() Slots.RefreshButton() end)
    Slots.button, Slots.popup = button, popup
    popup.slotHeader = Dropdown.Header(popup, "Slot")
    popup.armorHeader = Dropdown.Header(popup, "Armor type")
    popup.columnLine = ns.UI.Divider(popup, true)
    popup.footerLine = ns.UI.Divider(popup)
    popup.note = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.note:SetTextColor(unpack(UI.Hex(UI.TEXT.muted)))
    popup.note:SetJustifyH("LEFT")
    popup.note:SetSpacing(2)

    Slots.RefreshButton()
    return button
end
