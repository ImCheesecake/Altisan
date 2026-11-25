-- RecipeParts.lua: the pieces about a recipe every page shows the same way: its tooltip's start,
-- where to learn it (place lines and map pins), and the two track buttons with their tracked look.

local _, ns = ...
local UI = ns.UI

local PLACE_LINE, PLACE_GAP, PIN_ROOM, SHOWN_PLACES, MORE_HEIGHT = 24, 2, 32, 3, 32
UI.SHOWN_PLACES = SHOWN_PLACES

function UI.CraftedItem(recipeID, recipe, skillLine)
    if recipe and recipe.item then return recipe.item end
    local db = ns.ProfessionDB()
    skillLine = skillLine or (recipe and recipe.skillLine)
    return db and skillLine and db:GetCraftedItemID(skillLine, recipeID) or nil
end

-- GameTooltip must already have its owner.
function UI.RecipeTooltipTop(recipeID, recipe, name, skillLine, redraw)
    local itemID = UI.CraftedItem(recipeID, recipe, skillLine)
    if itemID and C_Item.IsItemDataCachedByID(itemID) then
        UI.drawingItem = true
        GameTooltip:SetItemByID(itemID)
        UI.drawingItem = false
        GameTooltip:AddLine(" ")
        return
    end
    -- Asking for an item the client doesn't have is an error.
    if itemID and Item and Item.CreateFromItemID and (not C_Item.DoesItemExistByID or C_Item.DoesItemExistByID(itemID)) then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(redraw)
    end
    UI.TipLine(GameTooltip, name or (recipe and recipe.name) or "")
    local db = ns.ProfessionDB()
    skillLine = skillLine or (recipe and recipe.skillLine)
    local effect = not itemID and db and skillLine and db:GetEffect(skillLine, recipeID)
    if effect then UI.TipLine(GameTooltip, effect, "effect", true) end
end

function UI.PinButton(parent, size)
    size = size or 24
    local b = UI.SquareButton(parent, nil, nil, size)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(size - 8, size - 8)
    b.icon:SetPoint("CENTER")
    b:SetScript("OnClick", function(self)
        if self.place and ns.Places.Pin(self.place) then UI.RedrawWindow() end
    end)
    b:SetScript("OnEnter", function(self)
        local p = self.place
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Show on map", unpack(UI.Hex(UI.TEXT.white)))
        GameTooltip:AddLine(p.name .. (p.zone and (", " .. p.zone) or ""), unpack(UI.Hex(UI.TEXT.light)))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:SetPlace(p)
        self.place = p
        self.icon:SetAtlas(ns.Places.IsPinned(p) and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked")
    end
    return b
end

local function PlaceLeft(p)
    return p.name .. (p.title and ("\n" .. UI.ColorText(UI.TEXT.light, p.title)) or "")
end

local function ZoneRoom(p)
    return p.zone and (UI.TextWidth(p.zone, "GameFontHighlightSmall") + 8) or 0
end

-- The library names at most 12 places; the rest only show as a count (unnamed).
local function Visible(places, total, expanded)
    local shown = expanded and #places or math.min(#places, SHOWN_PLACES)
    local more = math.max(0, #places - SHOWN_PLACES)
    local unnamed = (expanded or #places <= SHOWN_PLACES) and total > #places and (total - #places) or 0
    return shown, more, unnamed
end

-- A tooltip can't be clicked, so "and N more" counts every place left out. Returns whether
function UI.AddPlaceLines(tooltip, places, total, expanded)
    local shown = Visible(places, total, expanded)
    for i = 1, shown do
        local p = places[i]
        UI.TipDoubleLine(tooltip, p.name, p.zone or "", "white", "light")
        if p.title then UI.TipLine(tooltip, p.title, "light", true) end
    end
    if total > shown then UI.TipLine(tooltip, ("and %d more"):format(total - shown), "light") end
    return #places > shown
end

local function LineHeight(p, width)
    return math.max(PLACE_LINE, UI.TextHeight(PlaceLeft(p), width - PIN_ROOM - ZoneRoom(p), "GameFontHighlightSmall") + 10)
end

function UI.PlaceLinesHeight(places, total, width, expanded)
    local shown, more, unnamed = Visible(places, total, expanded)
    local h = 0
    for i = 1, shown do h = h + LineHeight(places[i], width) + PLACE_GAP end
    if unnamed > 0 then h = h + 16 end
    if more > 0 then h = h + MORE_HEIGHT end
    return h
end

function UI.PlaceLines(parent, onMore)
    local block = { lines = {} }
    block.more = UI.Button(parent, "", "quiet")
    block.more:SetScript("OnClick", function() onMore() end)
    block.unnamed = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    block.unnamed:SetJustifyH("LEFT")
    local function Line(i)
        if block.lines[i] then return block.lines[i] end
        local line = { text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), pin = UI.PinButton(parent),
                       zone = UI.Text(parent) }
        line.text:SetJustifyH("LEFT")
        line.zone:SetJustifyH("RIGHT")
        block.lines[i] = line
        return line
    end
    function block:Layout(places, total, x, y, width, expanded)
        local shown, more, unnamed = Visible(places, total, expanded)
        local top = y
        for i = 1, shown do
            local p, line = places[i], Line(i)
            line.text:ClearAllPoints()
            line.text:SetPoint("TOPLEFT", x, y - 5)
            line.text:SetWidth(width - PIN_ROOM - ZoneRoom(p))
            line.text:SetText(PlaceLeft(p))
            line.text:Show()
            line.zone:ClearAllPoints()
            line.zone:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - PIN_ROOM, y - 5)
            line.zone:SetText(UI.ColorText(UI.TEXT.light, p.zone or ""))
            line.zone:SetShown(p.zone ~= nil)
            line.pin:ClearAllPoints()
            line.pin:SetPoint("TOPLEFT", x + width - 24, y)
            line.pin:SetPlace(p)
            line.pin:SetShown(ns.Places.CanPin(p))
            y = y - LineHeight(p, width) - PLACE_GAP
        end
        for i = shown + 1, #self.lines do self.lines[i].text:Hide() self.lines[i].zone:Hide() self.lines[i].pin:Hide() end
        self.unnamed:SetShown(unnamed > 0)
        if unnamed > 0 then
            self.unnamed:ClearAllPoints()
            self.unnamed:SetPoint("TOPLEFT", x, y - 1)
            self.unnamed:SetText(("and %d more the addon's data doesn't name"):format(unnamed))
            y = y - 16
        end
        UI.SetShowMore(self.more, more, expanded)
        if more > 0 then
            self.more:ClearAllPoints()
            self.more:SetPoint("TOPLEFT", x, y - 4)
            y = y - MORE_HEIGHT
        end
        return top - y
    end
    function block:Hide()
        for _, line in ipairs(self.lines) do line.text:Hide() line.zone:Hide() line.pin:Hide() end
        self.more:Hide()
        self.unnamed:Hide()
    end
    return block
end

local function TrackLabels(recipeID, key)
    return { "Track materials", "Untrack materials" }, { "Add to shopping list", "Remove from shopping list" },
        ns.Tracking.InQuestLog(recipeID, key), ns.Tracking.Find(recipeID, key) ~= nil
end

-- As wide as its longer label, so a click doesn't move the button beside it.
local function LabelWidth(labels)
    return math.max(UI.TextWidth(labels[1], "GameFontHighlightSmall"), UI.TextWidth(labels[2], "GameFontHighlightSmall")) + 18
end

function UI.TrackButtonsWidth(recipeID, key)
    local materials, shopping = TrackLabels(recipeID, key)
    return LabelWidth(materials) + LabelWidth(shopping) + 6
end

function UI.TrackedFill(row)
    local fill = UI.RoundedBox(row, 6)
    fill:SetFill(UI.C.tracked)
    return fill
end

-- Text can't hold an alpha, so the swatch is the fill laid over the panel's color.
function UI.TrackedSwatch()
    local c, under = UI.C.tracked, UI.C.panel
    local rgb = {}
    for i = 1, 3 do rgb[i] = math.floor((c[i] * c[4] + under[i] * (1 - c[4])) * 255 + 0.5) end
    return ("|TInterface\\Buttons\\WHITE8X8:12:22:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(rgb[1], rgb[2], rgb[3])
end

function UI.AddTrackedLines(recipeID, key)
    local who = ns.Tracking.TrackedBy(recipeID, key)
    if #who == 0 then return end
    GameTooltip:AddLine(" ")
    UI.TipLine(GameTooltip, "Tracked", "gold")
    for _, w in ipairs(who) do
        local what = {}
        if w.inLog then what[#what + 1] = w.waits and "quest log at next login" or "in the quest log" end
        if w.onList then what[#what + 1] = "on the shopping list" end
        UI.TipLine(GameTooltip, UI.ShortName(w.char, w.key) .. ": " .. table.concat(what, ", "), "light", true)
    end
end

function UI.TrackButtons(parent)
    local t = {}
    t.materials = UI.Button(parent, "Track materials", "quiet", true)
    t.shopping = UI.Button(parent, "Add to shopping list", "quiet", true)
    t.materials:SetScript("OnClick", function() ns.Tracking.ToggleQuestLog(t.recipe, t.key) end)
    t.shopping:SetScript("OnClick", function()
        local index = ns.Tracking.Find(t.recipe, t.key)
        if index then ns.Tracking.Untrack(index) else ns.Tracking.Track(t.recipe, t.key) end
    end)
    UI.ButtonTip(t.materials, function()
        local later = t.key ~= ns.CharacterKey() and (" It shows when %s logs in."):format(t.name) or ""
        if ns.Tracking.WaitsForLogin(t.recipe, t.key) then
            return ("%s goes in %s's quest log when %s logs in."):format(t.recipeName, t.name, t.name)
        elseif ns.Tracking.InQuestLog(t.recipe, t.key) then
            return ("%s is in %s's quest log."):format(t.recipeName, t.name)
        end
        return ("Lists what %s needs for %s in the quest log, with how many %s has, so you can gather them yourself.%s")
            :format(t.name, t.recipeName, t.name, later)
    end)
    UI.ButtonTip(t.shopping, function()
        local _, tracked = ns.Tracking.Find(t.recipe, t.key)
        if tracked then
            return ("%d on the Shopping page. A click takes it off the list, count and all."):format(tracked.count)
        end
        return ("Puts what's missing on the Shopping page: who can mail it to %s, and what to buy."):format(t.name)
    end)
    local function Label(button, labels, on)
        button:SetKind(on and "primary" or "quiet", labels[on and 2 or 1])
        button:SetWidth(LabelWidth(labels))
    end
    function t:Set(recipeID, key, char)
        self.recipe, self.key, self.name = recipeID, key, UI.CharName(char, key)
        self.recipeName = (ns.db.recipes[recipeID] or {}).name or "this recipe"
        local materials, shopping, inLog, tracked = TrackLabels(recipeID, key)
        Label(self.materials, materials, inLog)
        Label(self.shopping, shopping, tracked)
    end
    function t:SetShown(on)
        self.materials:SetShown(on)
        self.shopping:SetShown(on)
    end
    return t
end

-- A frame of our own on the pane: Blizzard's slots come from a pool the next recipe reuses.
local NOTE_GAP, NOTE_MARGIN, NOTE_MIN, NOTE_WIDTH = 8, 16, 120, 240
function UI.SlotNotes(pane)
    local holder = CreateFrame("Frame", nil, pane)
    holder:SetAllPoints()
    holder.label = UI.Text(holder)
    holder.label:SetText(UI.ColorText(UI.TEXT.muted, ns.TITLE))
    holder.notes, holder.entries = {}, {}
    local function Widths()
        local right = pane:GetRight()
        for i, entry in ipairs(holder.entries) do
            local slotRight = entry.slot:GetRight()
            local room = right and slotRight and (right - slotRight - NOTE_GAP - NOTE_MARGIN)
            holder.notes[i]:SetWidth(math.max(NOTE_MIN, room or NOTE_WIDTH))
        end
    end
    holder:SetScript("OnSizeChanged", Widths)
    function holder:Set(entries, first)
        for _, note in ipairs(self.notes) do note:Hide() end
        self.entries = entries
        self.label:SetShown(#entries > 0)
        if first then
            self.label:ClearAllPoints()
            self.label:SetPoint("BOTTOMLEFT", first, "TOPRIGHT", NOTE_GAP, 2)
        end
        for i, entry in ipairs(entries) do
            local note = self.notes[i] or UI.Text(holder)
            self.notes[i] = note
            note:ClearAllPoints()
            note:SetPoint("LEFT", entry.slot, "RIGHT", NOTE_GAP, 0)
            note:SetText(UI.Light(entry.text))
            note:Show()
        end
        Widths()
    end
    return holder
end
