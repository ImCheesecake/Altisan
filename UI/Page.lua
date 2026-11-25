-- Page.lua: what every page is built of: the spacing from the top (UI.PAGE), titles, headings,
-- cards, buttons, checkboxes, the stepper, fold headers, lines, a page's data kept while resizing.

local _, ns = ...
local UI = ns.UI

UI.PAGE = {
    top = -8,
    titleSize = 22,
    titleHeight = 26,
    gap = 12,
    tabHeight = 26,
    controlsToStatus = 28,
    statusToList = 18,
    paneWidth = 330,
    paneGap = 14,
}

local PAGE = UI.PAGE

function UI.Below(y, height)
    return y - height - PAGE.gap
end

function UI.Flow(frames, width, gap, startX, place)
    local row, x, previous = 0, startX or 0, nil
    for _, frame in ipairs(frames) do
        local w = frame:GetWidth()
        if (previous or x > 0) and x + (previous and gap or 0) + w > width then
            row, x, previous = row + 1, 0, nil
        end
        if previous then x = x + gap end
        place(frame, row, previous)
        x, previous = x + w, frame
    end
    return row
end

function UI.PageTitle(parent)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    local fontFile = GameFontNormalLarge:GetFont()
    title:SetFont(fontFile, PAGE.titleSize, "")
    title:SetShadowOffset(1, -1)
    return title
end

function UI.Page(parent, title)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page.title = UI.PageTitle(page)
    page.title:SetPoint("TOPLEFT", 0, PAGE.top)
    page.title:SetText(title)
    page.subtitle = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    page.subtitle:SetPoint("BOTTOMLEFT", page.title, "BOTTOMRIGHT", 10, 1)
    return page
end

function UI.SmallHeading(parent, text)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetTextColor(unpack(UI.Hex(UI.TEXT.muted)))
    h:SetText((text or ""):upper())
    return h
end

function UI.Card(parent, radius, solid)
    local card = CreateFrame("Frame", nil, parent)
    local box = UI.RoundedBox(card, radius or 8)
    box:SetFill(solid and UI.C.background or UI.C.cardFill)
    box:SetEdge(solid and UI.C.border or UI.C.divider)
    card.box = box
    return card
end

UI.CARD_PIN = 18
function UI.TitledCard(parent, title)
    local card = UI.Card(parent, 8)
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 16, -12)
    card.title:SetJustifyH("LEFT")
    card.title:SetText(title or "")
    card.lines = {}
    function card:SetLines(lines, width, top)
        local y = -34 - (top or 0)
        for i, text in ipairs(lines) do
            local pair = self.lines[i]
            if not pair then
                pair = { left = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                         right = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
                pair.left:SetJustifyH("LEFT")
                pair.left:SetSpacing(2)
                pair.right:SetJustifyH("RIGHT")
                self.lines[i] = pair
            end
            local left, right = text:match("^(.-)\t(.*)$")
            pair.left:SetText(left or text)
            pair.right:SetText(right or "")
            pair.left:ClearAllPoints()
            pair.left:SetPoint("TOPLEFT", 16, y)
            pair.left:Show()
            pair.right:ClearAllPoints()
            pair.right:SetShown(right ~= nil)
            local under = right and UI.FitPair(pair.left, pair.right, width - 32, right == "" and UI.CARD_PIN or nil)
            if not right then pair.left:SetWidth(width - 32) end
            if under then
                y = y - pair.left:GetStringHeight() - 2
                pair.right:SetPoint("TOPLEFT", 16 + UI.PAIR_GAP, y)
                y = y - pair.right:GetStringHeight() - 4
            else
                pair.right:SetPoint("TOPRIGHT", -16, y)
                y = y - pair.left:GetStringHeight() - 4
            end
        end
        for i = #lines + 1, #self.lines do
            self.lines[i].left:Hide()
            self.lines[i].right:Hide()
        end
        self.text = table.concat(lines, "\n")
        return y
    end
    function card:Fit(y, bottom)
        self:SetHeight(math.ceil(-y + (bottom or 8)))
    end
    return card
end

function UI.TileStrip(parent, count, opts)
    opts = opts or {}
    local strip = UI.Card(parent, 10)
    strip.baseHeight = opts.height or 58
    strip.height = strip.baseHeight
    strip:SetHeight(strip.height)
    strip.tiles = {}
    for i = 1, count do
        local tile = {}
        tile.label = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if opts.labelColor then tile.label:SetTextColor(unpack(opts.labelColor)) end
        tile.value = strip:CreateFontString(nil, "OVERLAY", opts.valueFont or "GameFontHighlightLarge")
        tile.note = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tile.note:SetJustifyH("LEFT")
        if i > 1 then
            tile.line = UI.Divider(strip, true)
        end
        if opts.bars and opts.bars[i] then
            tile.track, tile.bar = UI.SkillBar(strip, 1)
            tile.bar:SetMinMaxValues(0, 1)
        end
        strip.tiles[i] = tile
    end

    function strip:SetTile(i, label, value, note)
        local tile = self.tiles[i]
        tile.label:SetText(label or "")
        tile.value:SetText(value or "")
        tile.note:SetText(note or "")
    end
    function strip:SetBar(i, value, max)
        self.tiles[i].bar:SetValue((max and max > 0) and math.min(1, (value or 0) / max) or 0)
    end
    function strip:Layout(width)
        local tileWidth = math.floor(width / #self.tiles)
        local labelY, valueY = -11, -28
        if self.baseHeight < 58 then labelY, valueY = -9, -24 end
        local under = false
        for _, tile in ipairs(self.tiles) do
            tile.note:SetWidth(0)
            if tile.note:GetText() ~= "" and tile.note:GetStringWidth() > tileWidth - 32 - tile.value:GetStringWidth() - 6 then
                under = true
            end
        end
        local extra = 0
        for i, tile in ipairs(self.tiles) do
            local x = (i - 1) * tileWidth
            tile.label:SetPoint("TOPLEFT", self, "TOPLEFT", x + 16, labelY)
            tile.value:SetPoint("TOPLEFT", self, "TOPLEFT", x + 16, valueY)
            tile.note:ClearAllPoints()
            if under then
                tile.note:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -3)
                tile.note:SetWidth(tileWidth - 32)
                if tile.note:GetText() ~= "" then extra = math.max(extra, math.ceil(tile.note:GetStringHeight()) + 3) end
            else
                tile.note:SetPoint("BOTTOMLEFT", tile.value, "BOTTOMRIGHT", 6, 1)
                tile.note:SetWidth(math.max(1, tileWidth - 32 - tile.value:GetStringWidth() - 6))
            end
            if tile.line then
                -- By its left edge: centered on x, a one-pixel line starts half a pixel off.
                tile.line:SetPoint("TOPLEFT", self, "TOPLEFT", x, -10)
                tile.line:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 10)
            end
            if tile.track then
                tile.track:SetPoint("TOPLEFT", self, "TOPLEFT", x + 16, valueY - 18)
                tile.track:SetWidth(tileWidth - 32)
            end
        end
        self.height = self.baseHeight + extra
        self:SetHeight(self.height)
        return self.height
    end
    return strip
end

function UI.Button(parent, label, kind, small)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(small and 20 or 26)
    b.pad = small and 18 or 28
    b.box = UI.RoundedBox(b, 6)
    UI.RoundedHover(b, 6)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    function b:SetKind(newKind, newLabel)
        if newLabel then self.text:SetText(newLabel) end
        local primary = newKind ~= "quiet"
        self.kind = primary and "primary" or "quiet"
        self.box:SetFill(primary and UI.C.active or UI.C.clear)
        self.box:SetEdge(primary and UI.C.chipEdge or UI.C.edgeIdle)
        self.text:SetTextColor(unpack(UI.Hex(primary and UI.TEXT.gold or UI.TEXT.light)))
        self:SetWidth(self.text:GetStringWidth() + self.pad)
    end
    b:SetKind(kind or "primary", label)
    return b
end

-- Kept while only resizing (layoutOnly): working it out on every frame of a drag makes resizing lag.
local kept = {}

function UI.Data(key, layoutOnly, compute)
    local k = kept[key]
    if not (layoutOnly and k) then
        k = { n = 0 }
        local function Keep(...) k.n = select("#", ...) for i = 1, k.n do k[i] = select(i, ...) end end
        Keep(compute())
        kept[key] = k
    end
    return unpack(k, 1, k.n)
end

function UI.ItemHover(f, itemOf, clickScript, title)
    f:SetScript("OnEnter", function(self)
        local itemID = itemOf(self)
        if not itemID and not title then return end
        UI.RowTooltip(self)
        if itemID then
            GameTooltip:SetItemByID(itemID)
        else
            GameTooltip:SetText(title(self) or "", unpack(UI.Hex(UI.TEXT.white)))
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if clickScript then f:SetScript(clickScript, function(self) UI.ItemClick(itemOf(self)) end) end
end

-- Addons can't reach the clipboard, so any edit puts getText() back, selected. Hooked, not set: a
-- template's own handlers keep running.
function UI.ReadOnly(box, getText, onEscape)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self, userInput)
        local text = getText() or ""
        if userInput and self:GetText() ~= text then
            self:SetText(text)
            self:HighlightText()
        end
    end)
    box:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", onEscape or function(self) self:ClearFocus() end)
end

function UI.InputFrame(parent)
    local f = UI.Card(parent, 5)
    f.box:SetFill(UI.C.boxFill)
    f.box:SetEdge(UI.C.edgeIdle)
    return f
end

-- Follows the cursor: anchored to a wide row, the tooltip would show at its far end.
function UI.RowTooltip(owner)
    if ns.db.window.tooltips == "fixed" then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    end
end

-- Thin bars, not font glyphs: a font's "-" and "+" never sit centered.
local Q = math.pi / 4
local GLYPHS = {
    ["-"] = { { 10, 2, 0 } },
    ["+"] = { { 10, 2, 0 }, { 2, 10, 0 } },
    ["×"] = { { 11, 2, Q }, { 11, 2, -Q } },
    ["<"] = { { 7, 2, Q, 1, 2 }, { 7, 2, -Q, 1, -2 } },
    [">"] = { { 7, 2, -Q, -1, 2 }, { 7, 2, Q, -1, -2 } },
}

local function Glyph(b, glyph, x, y)
    local bars = {}
    for _, bar in ipairs(GLYPHS[glyph] or {}) do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(unpack(UI.Hex(UI.TEXT.gold)))
        t:SetSize(bar[1], bar[2])
        t:SetPoint("CENTER", (x or 0) + (bar[4] or 0), (y or 0) + (bar[5] or 0))
        if bar[3] ~= 0 then t:SetRotation(bar[3]) end
        bars[#bars + 1] = t
    end
    return bars
end

local function TitleTip(b, tooltip)
    b:SetScript("OnEnter", function(self)
        local text = type(tooltip) == "function" and tooltip() or tooltip
        if not text then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text, unpack(UI.Hex(UI.TEXT.white)))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.SquareButton(parent, glyph, tooltip, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    b.box = UI.RoundedBox(b, 5)
    b.box:SetFill(UI.C.squareFill)
    b.box:SetEdge(UI.C.edgeIdle)
    UI.RoundedHover(b, 5)
    b.bars = Glyph(b, glyph)
    b.glyph = glyph
    TitleTip(b, tooltip)
    local enable = b.SetEnabled
    function b:SetEnabled(on)
        enable(self, on)
        for _, t in ipairs(self.bars) do t:SetAlpha(on and 1 or 0.35) end
    end
    return b
end

local HANDLE_W, HANDLE_H, HANDLE_ICON = 26, 72, 18
UI.HANDLE_WIDTH = HANDLE_W
function UI.DrawerHandle(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(HANDLE_W, HANDLE_H)
    b.box = UI.RoundedBox(b, 6)
    b.box:SetFill(UI.C.background)
    b.box:SetEdge(UI.C.border)
    UI.RoundedHover(b, 6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(ns.ICON)
    b.icon:SetSize(HANDLE_ICON, HANDLE_ICON)
    b.icon:SetPoint("TOP", 0, -14)
    b.arrows = { ["<"] = Glyph(b, "<", 0, -14), [">"] = Glyph(b, ">", 0, -14) }
    TitleTip(b, function() return b.tip end)
    b:SetScript("OnClick", function(self)
        onClick(self)
        -- OnEnter won't fire again while the mouse stays: refresh the tooltip by hand.
        if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then self:GetScript("OnEnter")(self) end
    end)
    function b:SetPointing(arrow, tip)
        for which, bars in pairs(self.arrows) do
            for _, t in ipairs(bars) do t:SetShown(which == arrow) end
        end
        self.arrow, self.tip = arrow, tip
    end
    return b
end

local FOLD_SIGN = 14
UI.FOLD_GAP = 8
local FOLD_GAP = UI.FOLD_GAP

function UI.FoldSign(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(FOLD_SIGN, FOLD_SIGN)
    local box = UI.RoundedBox(s, 3, "ARTWORK")
    box:SetEdge(UI.C.foldEdge)
    s.across = s:CreateTexture(nil, "OVERLAY")
    s.across:SetColorTexture(unpack(UI.Hex(UI.TEXT.gold)))
    s.across:SetSize(8, 2)
    s.across:SetPoint("CENTER")
    s.down = s:CreateTexture(nil, "OVERLAY")
    s.down:SetColorTexture(unpack(UI.Hex(UI.TEXT.gold)))
    s.down:SetSize(2, 8)
    s.down:SetPoint("CENTER")
    function s:SetOpen(open)
        self.open = open
        self.down:SetShown(not open)
    end
    s:SetOpen(true)
    return s
end

local NOTE_FONT, COUNT_INSET = "GameFontHighlightSmall", 8
UI.HEADING = { height = 28, gap = 12 }

function UI.HeadingExtent(first) return UI.HEADING.height + (first and 0 or UI.HEADING.gap) end

function UI.FoldHeader(row)
    local h = {}
    h.sign = UI.FoldSign(row)
    h.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.title:SetPoint("LEFT", h.sign, "RIGHT", FOLD_GAP, 0)
    h.note = row:CreateFontString(nil, "OVERLAY", NOTE_FONT)
    h.note:SetTextColor(unpack(UI.Hex(UI.TEXT.light)))
    h.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", row, "RIGHT", -COUNT_INSET, 0)
    h.count:SetPoint("BOTTOM", h.sign, "BOTTOM", 0, 1)
    h.count:SetTextColor(unpack(UI.Hex(UI.TEXT.light)))
    h.line = UI.Divider(row)
    h.line:SetPoint("BOTTOMLEFT", 0, 4)
    h.line:SetPoint("BOTTOMRIGHT", 0, 4)
    function h:Set(o)
        local wrap, lift = o.wrap, 0
        if o.width then wrap, lift = UI.FoldNoteRoom(o, o.width), UI.FoldNoteExtra(o, o.width) end
        self.sign:ClearAllPoints()
        if o.top then
            self.sign:SetPoint("TOPLEFT", o.x or 4, -o.top)
        else
            self.sign:SetPoint("BOTTOMLEFT", o.x or 4, (o.line and 11 or 5) + lift)
        end
        self.note:ClearAllPoints()
        if wrap then
            self.note:SetPoint("TOPLEFT", self.title, "TOPRIGHT", FOLD_GAP, -2)
            self.note:SetJustifyH("LEFT")
        else
            self.note:SetPoint("LEFT", self.title, "RIGHT", FOLD_GAP, 0)
        end
        self.note:SetShown(not wrap or wrap > 0)
        self.note:SetWidth(wrap and math.max(wrap, 1) or 0)
        self.sign:SetOpen(o.open)
        self.title:SetText(o.title or "")
        self.note:SetText(o.note or "")
        self.count:SetText(o.count or "")
        self.line:SetShown(o.line and true or false)
    end
    function h:SetShown(on)
        for _, part in ipairs({ self.sign, self.title, self.note, self.count }) do part:SetShown(on) end
        if not on then self.line:Hide() end
    end
    return h
end

function UI.FoldNoteWidth(rowWidth, x, title)
    return rowWidth - (x or 4) - FOLD_SIGN - FOLD_GAP - math.ceil(UI.TextWidth(title, "GameFontNormal")) - FOLD_GAP
end

function UI.FoldNoteRoom(o, rowWidth)
    local count = (o.count and o.count ~= "") and math.ceil(UI.TextWidth(o.count, NOTE_FONT)) + FOLD_GAP or 0
    return UI.FoldNoteWidth(rowWidth, o.x, o.title or "") - count - COUNT_INSET
end

function UI.FoldNoteExtra(o, rowWidth)
    if not o.note or o.note == "" then return 0 end
    local lines = UI.TextHeight(o.note, UI.FoldNoteRoom(o, rowWidth), NOTE_FONT)
    return math.max(0, math.ceil(lines - UI.TextHeight("A", 0, NOTE_FONT)))
end

function UI.ShowMoreLabel(more, expanded, what)
    return expanded and "Show fewer" or ("Show %d %s"):format(more, what or "more")
end

function UI.SetShowMore(button, more, expanded, what)
    button:SetShown(more > 0)
    if more > 0 then button:SetKind("quiet", UI.ShowMoreLabel(more, expanded, what)) end
end

UI.STEPPER_WIDTH = 100

function UI.Stepper(parent, onChange, min)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(UI.STEPPER_WIDTH, 24)
    s.min = min or 1
    s.minus = UI.SquareButton(s, "-", "One fewer")
    s.minus:SetPoint("LEFT")
    s.plus = UI.SquareButton(s, "+", "One more")
    s.plus:SetPoint("RIGHT")
    s.field = UI.InputFrame(s)
    s.field:SetPoint("TOPLEFT", s.minus, "TOPRIGHT", 4, 0)
    s.field:SetPoint("BOTTOMRIGHT", s.plus, "BOTTOMLEFT", -4, 0)
    s.count = CreateFrame("EditBox", nil, s.field)
    s.count:SetAllPoints()
    s.count:SetFontObject("GameFontHighlight")
    s.count:SetJustifyH("CENTER")
    s.count:SetNumeric(true)
    s.count:SetMaxLetters(4)
    s.count:SetAutoFocus(false)
    s.count:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    s.count:SetScript("OnEscapePressed", function(box)
        box:SetText(tostring(s.value))
        box:ClearFocus()
    end)
    s.count:SetScript("OnEditFocusLost", function(box)
        local n = tonumber(box:GetText())
        if not s.discard and n and n >= s.min and n ~= s.value then onChange(s, n - s.value) end
        box:SetText(tostring(s.value))
    end)
    -- ClearFocus first: it commits a typed number before the click adds or takes one.
    s.minus:SetScript("OnClick", function() s.count:ClearFocus() onChange(s, -1) end)
    s.plus:SetScript("OnClick", function() s.count:ClearFocus() onChange(s, 1) end)
    -- A reused row can be redrawn mid-typing: discard it, or focus-lost applies it to the new
    -- material.
    function s:SetValue(n)
        if self.count:HasFocus() and n ~= self.value then
            self.discard = true
            self.count:ClearFocus()
            self.discard = nil
        end
        self.value = n
        if not self.count:HasFocus() then self.count:SetText(tostring(n)) end
        self.minus:SetEnabled(n > self.min)
    end
    return s
end

function UI.CheckMark(f)
    f:SetSize(14, 14)
    local box = UI.RoundedBox(f, 3, "ARTWORK")
    local tick = f:CreateTexture(nil, "OVERLAY")
    tick:SetSize(16, 16)
    tick:SetPoint("CENTER", f, "CENTER", 1, 0)
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetDesaturated(true)
    tick:SetVertexColor(unpack(UI.C.tick))
    local gold, fill, edge = UI.Hex(UI.TEXT.gold), UI.C.menuFill, UI.C.edgeIdle
    return function(checked)
        box:SetFill(checked and gold or fill)
        box:SetEdge(checked and gold or edge)
        tick:SetShown(checked and true or false)
    end
end

function UI.Checkbox(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.check = CreateFrame("Frame", nil, b)
    b.check:SetPoint("LEFT")
    local setCheck = UI.CheckMark(b.check)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b.check, "RIGHT", 6, 0)
    b.label:SetText(label)
    b:SetWidth(14 + 6 + b.label:GetStringWidth() + 4)
    function b:SetChecked(checked)
        self.checked = checked and true or false
        setCheck(self.checked)
    end
    b:SetScript("OnClick", function(self) onClick(not self.checked) end)
    b:SetChecked(false)
    return b
end

-- The game rounds each texture corner to a screen pixel, so anything between pixels shifts while
-- resizing. Corners aren't snapped, so a half-pixel edge stays soft instead of flickering.
local function PixelRegion(region)
    region:SetRoundLayoutToNearestPixel(true)
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        region:SetTexelSnappingBias(0)
    end
end

function UI.RoundToPixels(frame)
    PixelRegion(frame)
    for _, region in ipairs({ frame:GetRegions() }) do PixelRegion(region) end
    for _, child in ipairs({ frame:GetChildren() }) do UI.RoundToPixels(child) end
end

local dividers = setmetatable({}, { __mode = "k" })

local function FitDivider(line)
    local pixel = PixelUtil.GetNearestPixelSize(1, line:GetEffectiveScale(), 1)
    if dividers[line] == "vertical" then line:SetWidth(pixel) else line:SetHeight(pixel) end
end

function UI.FitDividers()
    for line in pairs(dividers) do FitDivider(line) end
end

function UI.Divider(parent, vertical)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(UI.C.divider))
    dividers[line] = vertical and "vertical" or "horizontal"
    line:SetRoundLayoutToNearestPixel(true)
    FitDivider(line)
    return line
end

local scaleWatch = CreateFrame("Frame")

scaleWatch:RegisterEvent("UI_SCALE_CHANGED")

scaleWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")

scaleWatch:SetScript("OnEvent", UI.FitDividers)
