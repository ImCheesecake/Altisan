-- Dropdown.lua: what the recipe list's dropdown filters (Show, Source, Slot, Stats) share: the menu
-- button, the popup that closes on a click outside, radio rows, removable chips.

local _, ns = ...

local Dropdown = {}
ns.Dropdown = Dropdown

local C = ns.UI.C
local Hex, TEXT = ns.UI.Hex, ns.UI.TEXT
local GOLD, BODY, SOFT, MUTED = Hex(TEXT.gold), Hex(TEXT.body), Hex(TEXT.soft), Hex(TEXT.muted)

-- Two thin strokes (CreateLine) instead of an arrow texture, so it stays thin and takes the text's color.
local function Chevron(f)
    local lines = {}
    for i, stroke in ipairs({ { -21, 2, -17, -2 }, { -17, -2, -13, 2 } }) do
        local line = f:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.5)
        line:SetStartPoint("RIGHT", f, stroke[1], stroke[2])
        line:SetEndPoint("RIGHT", f, stroke[3], stroke[4])
        lines[i] = line
    end
    return lines
end

function Dropdown.Button(parent)
    local UI = ns.UI
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(24)
    button.box = UI.RoundedBox(button, 6)
    UI.RoundedHover(button, 6)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", 14, 0)
    button.chevron = Chevron(button)

    function button:SetState(label, active, open)
        self.active = active
        self.text:SetText(label)
        self:SetWidth(self.text:GetStringWidth() + 48)
        local color = active and GOLD or BODY
        self.text:SetTextColor(unpack(color))
        for _, line in ipairs(self.chevron) do line:SetColorTexture(unpack(color)) end
        self.box:SetFill(active and C.active or C.clear)
        self.box:SetEdge((active or open) and C.border or C.edgeIdle)
    end
    return button
end

-- Fixed DIALOG strata: above the window and the game's own windows, and a window raising its strata
-- can't pull it down.
function Dropdown.Popup(parent, button, width, onHide)
    local popup = CreateFrame("Frame", nil, parent)
    popup:SetFrameStrata("DIALOG")
    if popup.SetFixedFrameStrata then popup:SetFixedFrameStrata(true) end
    popup:SetWidth(width)
    popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    local box = ns.UI.RoundedBox(popup, 8)
    box:SetFill(C.menuFill)
    box:SetEdge(C.border)
    popup:EnableMouse(true)
    popup:Hide()

    popup:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    popup:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        if onHide then onHide() end
    end)
    popup:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
    end)
    return popup
end

---@class AltisanDropdownButton: Button
---@field SetState fun(self: AltisanDropdownButton, label: string, active: boolean, open: boolean)
---@return AltisanDropdownButton button, Frame popup
function Dropdown.Menu(parent, width, fill, refresh)
    local button = Dropdown.Button(parent)
    ---@cast button AltisanDropdownButton
    local popup = Dropdown.Popup(parent, button, width, refresh)
    button:SetScript("OnClick", function()
        local show = not popup:IsShown()
        if show and fill then fill() end
        popup:SetShown(show)
        refresh()
    end)
    return button, popup
end

---@class AltisanMenuRow: Button
---@field Set fun(self: AltisanMenuRow, name: string, count: string|number|nil, picked: boolean)
---@field key string? the Stats filter's stat
---@field field string? the Slot filter's "slot" or "armor"
---@field value any the Slot filter's pick

---@return AltisanMenuRow
local function BuildRow(popup, width, height, mark)
    local UI = ns.UI
    local row = CreateFrame("Button", nil, popup)
    ---@cast row AltisanMenuRow
    row:SetSize(width, height)
    row.minHeight = height

    row.fill = UI.RoundedBox(row, 5)
    row.fill:SetFill(C.picked)
    UI.RoundedHover(row, 5)

    row.mark = CreateFrame("Frame", nil, row)
    row.mark:SetPoint("LEFT", 6, 0)
    local setMark = mark(row.mark)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.mark, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")

    function row:Set(name, count, picked)
        self.name:SetText(name)
        self.name:SetTextColor(unpack(picked and GOLD or BODY))
        self.fill:SetShown(picked)
        setMark(picked)
        self.count:SetText(count or "")
        self.count:SetTextColor(unpack(picked and SOFT or MUTED))   -- muted is too dark on the picked fill
        local countRoom = (count and count ~= "") and self.count:GetStringWidth() + 6 or 0
        self.name:SetWidth(self:GetWidth() - 26 - 6 - countRoom)
        self:SetHeight(math.max(self.minHeight, math.ceil(self.name:GetStringHeight() + 8)))
        self:Show()
        return self:GetHeight()
    end
    return row
end

function Dropdown.RadioRow(popup, width, height)
    return BuildRow(popup, width, height, function(f)
        local UI = ns.UI
        f:SetSize(12, 12)
        local ring = UI.RoundedBox(f, 6, "ARTWORK")
        local dotFrame = CreateFrame("Frame", nil, f)
        dotFrame:SetSize(6, 6)
        dotFrame:SetPoint("CENTER")
        local dot = UI.RoundedBox(dotFrame, 3, "OVERLAY")
        dot:SetFill(GOLD)
        return function(on)
            ring:SetEdge(on and GOLD or C.edgeIdle)
            dot:SetShown(on)
        end
    end)
end

local RADIO_ROW = 24
function Dropdown.RadioMenu(parent, width, onPick, refresh)
    local button, popup = Dropdown.Menu(parent, width, nil, refresh)
    local menu, rows = { button = button, popup = popup }, {}
    function menu:Fill(options, picked)
        local y = -8
        for i, option in ipairs(options) do
            local row = rows[i]
            if not row then
                row = Dropdown.RadioRow(popup, width - 20, RADIO_ROW)
                row:SetScript("OnClick", function(self)
                    popup:Hide()
                    onPick(self.key)
                end)
                rows[i] = row
            end
            row.key = option.key
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 10, y)
            y = y - row:Set(option.label, option.count and tostring(option.count), option.key == picked)
        end
        for i = #options + 1, #rows do rows[i]:Hide() end
        popup:SetHeight(-y + 8)
    end
    return menu
end

function Dropdown.CheckRow(popup, width, height)
    return BuildRow(popup, width, height, function(f) return ns.UI.CheckMark(f) end)
end

function Dropdown.Header(popup, text)
    return ns.UI.SmallHeading(popup, text)
end

function Dropdown.Chip(parent, onClick)
    local UI = ns.UI
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(18)
    local box = UI.RoundedBox(chip, 9)
    box:SetFill(C.picked)
    box:SetEdge(C.chipEdge)
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chip.text:SetPoint("LEFT", 9, 0)
    chip.text:SetTextColor(unpack(GOLD))
    chip.x = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chip.x:SetPoint("LEFT", chip.text, "RIGHT", 5, 0)
    chip.x:SetTextColor(unpack(GOLD))
    chip.x:SetText("×")
    UI.RoundedHover(chip, 9)
    chip:SetScript("OnClick", onClick)

    function chip:SetLabel(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + self.x:GetStringWidth() + 23)
    end
    return chip
end

function Dropdown.Chips(parent, onRemove)
    local chips, row = {}, {}
    function row.Lay(picks, into)
        for i, pick in ipairs(picks) do
            local chip = chips[i]
            if not chip then
                chip = Dropdown.Chip(parent, function(self) onRemove(self.value) end)
                chips[i] = chip
            end
            chip.value = pick.value
            chip:SetLabel(pick.label)
            chip:Show()
            into[#into + 1] = chip
        end
        for i = #picks + 1, #chips do chips[i]:Hide() end
        return into
    end
    return row
end
