-- Lists.lua: scrolling lists and their rows, list columns, wrapped text, clickable lines, a card
-- whose content scrolls, and the panes drawn from blocks of text, lines, places and buttons.

local _, ns = ...
local UI = ns.UI

-- Rows are reused: init(row, data) sets everything, every time. Never put a gap in the extent
-- (use spacing): while resizing, rows are re-laid by their real height and every row below shifts.
function UI.ScrollList(parent, extent, init, spacing)
    local list = { init = init }
    list.bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    list.box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, spacing or 0)
    view:SetElementExtentCalculator(function(_, data) return extent(data) end)
    view:SetElementInitializer("Button", function(row, data)
        init(row, data)
        UI.RoundToPixels(row)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(list.box, list.bar, view)
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior and AnchorUtil and AnchorUtil.CreateAnchor then
        list.visibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(list.box, list.bar)
    end
    return list
end

-- Cheaper than a new data provider, which rebuilds every row.
function UI.RedrawRows(list, fill)
    if not list.box:HasDataProvider() then return false end
    list.box:ForEachFrame(function(row, data)
        (fill or list.init)(row, data)
        -- return nothing: ForEachFrame stops at the first truthy return
    end)
    return true
end

function UI.Columns(start, room, name, columns, gap)
    gap = gap or 12
    local always = 0
    for _, col in ipairs(columns) do
        if col.always then always = always + col.width + gap end
    end
    local c = { x = {} }
    c.name = math.max(name.min or 120, math.min(name.width, room - always))
    local used = c.name
    local x = start + c.name + gap
    for _, col in ipairs(columns) do
        if col.always or col.force or room - used >= col.width + gap then
            c[col.key] = true
            c.x[col.key] = x
            c.last = col.key
            used = used + col.width + gap
            x = x + col.width + gap
        else
            break
        end
    end
    local lastCol
    for _, col in ipairs(columns) do if col.key == c.last then lastCol = col end end
    c.lastWidth = lastCol and math.max(lastCol.width, start + room - c.x[c.last]) or 0
    local parts = { c.name }
    for _, col in ipairs(columns) do parts[#parts + 1] = tostring(c[col.key] or false) end
    c.key = table.concat(parts, ":")
    return c
end

function UI.PlaceList(list, top, bottom, right)
    bottom, right = bottom or 4, right or 0
    -- Pages call this every frame of a resize, and re-anchoring a scroll box re-lays all its rows.
    if list.placedTop == top and list.placedBottom == bottom and list.placedRight == right then return end
    list.placedTop, list.placedBottom, list.placedRight = top, bottom, right
    list.bar:ClearAllPoints()
    list.bar:SetPoint("TOPRIGHT", -right, top)
    list.bar:SetPoint("BOTTOMRIGHT", -right, bottom)
    -- Blizzard's behavior shows the bar only when there's something to scroll, and picks one of these.
    local v = list.visibility
    if v then
        local parent = list.box:GetParent()
        v.scrollBoxAnchorsWithBar = {
            AnchorUtil.CreateAnchor("TOPLEFT", parent, "TOPLEFT", 0, top),
            AnchorUtil.CreateAnchor("BOTTOMRIGHT", list.bar, "BOTTOMLEFT", -6, 0),
        }
        v.scrollBoxAnchorsWithoutBar = {
            AnchorUtil.CreateAnchor("TOPLEFT", parent, "TOPLEFT", 0, top),
            AnchorUtil.CreateAnchor("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right, bottom),
        }
        v.appliedAnchors = nil
        v:EvaluateVisibility(true)
        return
    end
    list.box:ClearAllPoints()
    list.box:SetPoint("TOPLEFT", 0, top)
    list.box:SetPoint("BOTTOMRIGHT", list.bar, "BOTTOMLEFT", -6, 0)
end

function UI.Text(parent, fontObject, spacing)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetSpacing(spacing or 3)
    return text
end

local LINK_PAD, LINK_MIN = 4, 20
function UI.LinkLine(parent)
    local line = UI.SelectableButton(parent, LINK_MIN)
    line.text:SetWordWrap(true)
    line.right = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    function line:Set(left, right, width)
        self:SetWidth(width)
        self.text:SetText(left)
        self.right:SetText(right or "")
        local under = UI.FitPair(self.text, self.right, width - 2 * LINK_PAD)
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", LINK_PAD, -LINK_PAD)
        self.right:ClearAllPoints()
        local height = self.text:GetStringHeight()
        if under then
            self.right:SetPoint("TOPLEFT", self.text, "BOTTOMLEFT", UI.PAIR_GAP, -2)
            height = height + 2 + self.right:GetStringHeight()
        else
            self.right:SetPoint("TOPRIGHT", -LINK_PAD, -LINK_PAD)
        end
        self:SetHeight(math.max(LINK_MIN, math.ceil(height + 2 * LINK_PAD)))
        self:SetSelected(false, true)
        return self:GetHeight()
    end
    return line
end

local PANE_PAD = 14

local PANE_INSET = 6

local PANE_BAR = 10

function UI.ScrollPaneWidth(contentWidth) return contentWidth + 2 * PANE_PAD + PANE_BAR end

function UI.ScrollPane(parent, width, solid)
    local pane = UI.Card(parent, 8, solid)
    pane:SetWidth(width)
    pane.width = width - UI.ScrollPaneWidth(0)
    pane.content = CreateFrame("Frame", nil, pane)
    pane.content:SetWidth(pane.width)
    pane.list = UI.ScrollList(pane, function(data) return data.height end, function(row)
        pane.content:SetParent(row)
        pane.content:ClearAllPoints()
        pane.content:SetPoint("TOPLEFT", PANE_PAD, -PANE_PAD)
        pane.content:Show()
    end)
    UI.PlaceList(pane.list, -PANE_INSET, PANE_INSET, 4)
    function pane:Fit(height, keepScroll)
        self.content:SetHeight(math.max(height, 1))
        local rowHeight = math.ceil(height) + 2 * PANE_PAD
        self.list.box:SetDataProvider(CreateDataProvider({ { height = rowHeight } }),
            keepScroll and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition)
        return rowHeight + 2 * PANE_INSET
    end
    return pane
end

function UI.Blocks()
    local blocks = {}
    function blocks:Text(text, gap, font) self[#self + 1] = { text = text, gap = gap, font = font } end
    function blocks:Heading(text, right)
        self[#self + 1] = { text = UI.ColorText(UI.TEXT.gold, text), gap = 14, right = right and UI.Soft(right) }
    end
    function blocks:Pair(left, right, gap, itemID)
        self[#self + 1] = { pair = left, right = right, gap = gap or 2, itemID = itemID }
    end
    function blocks:Row(count, name, range, onClick, tint, tip)
        self[#self + 1] = { row = name, count = count, range = range, onClick = onClick, tint = tint, tip = tip, gap = 2 }
    end
    function blocks:Bar(value, max, tick, left, right)
        self[#self + 1] = { bar = value, max = max, tick = tick, left = left, right = right, gap = 6 }
    end
    function blocks:Line(left, right, onClick) self[#self + 1] = { line = left, right = right, onClick = onClick } end
    function blocks:Buttons(buttons, gap) self[#self + 1] = { buttons = buttons, gap = gap } end
    function blocks:Fold(title, right, open, onClick)
        self[#self + 1] = { fold = title, right = right, open = open, onClick = onClick, gap = 0 }
    end
    return blocks
end

function UI.FoldTitle(parent)
    local b = CreateFrame("Button", nil, parent)
    b.sign = UI.FoldSign(b)
    b.sign:SetPoint("LEFT")
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("LEFT", b.sign, "RIGHT", UI.FOLD_GAP, 0)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT")
    function b:Set(spec, width)
        self:SetSize(width, 20)
        self.sign:SetOpen(spec.open)
        self.title:SetText(spec.fold)
        self.right:SetText(spec.right or "")
        self:SetScript("OnClick", spec.onClick)
        return 20
    end
    return b
end

function UI.ButtonTip(button, tip)
    button:SetScript("OnEnter", tip and function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.text:GetText(), unpack(UI.Hex(UI.TEXT.white)))
        UI.TipLine(GameTooltip, type(tip) == "function" and tip() or tip, "light", true)
        GameTooltip:Show()
    end or nil)
    button:SetScript("OnLeave", tip and function() GameTooltip:Hide() end or nil)
end

function UI.BlockPane(parent, width, onMorePlaces, solid)
    local pane = UI.ScrollPane(parent, width, solid)
    local c = pane.content
    local p = { texts = {}, rights = {}, pairs = {}, hits = {}, lines = {}, rows = {}, bars = {}, buttons = {}, folds = {} }
    p.places = UI.PlaceLines(c, onMorePlaces)
    p.track = UI.TrackButtons(c)
    p.stepper = UI.Stepper(c, function(s, delta) s.onChange(delta) end)
    p.stepNote = UI.Text(c)
    pane.parts = p

    local function PutAt(region, x, y)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", x, y)
        region:Show()
    end

    function pane:SetBlocks(blocks, keepScroll)
        local w = self.width
        -- pairs, not ipairs: p.rights has gaps.
        for _, list in ipairs({ p.texts, p.rights, p.pairs, p.hits, p.lines, p.rows, p.bars, p.buttons, p.folds }) do
            for _, region in pairs(list) do region:Hide() end
        end
        p.places:Hide()
        p.track:SetShown(false)
        p.stepper:Hide()
        p.stepNote:Hide()
        local y, texts, pairCount, lines, buttons = 0, 0, 0, 0, 0
        local used = { rows = 0, bars = 0, folds = 0 }
        local function Region(list, make)
            used[list] = used[list] + 1
            local r = p[list][used[list]] or make(c)
            p[list][used[list]] = r
            return r
        end
        for i, b in ipairs(blocks) do
            if i > 1 then y = y - (b.gap or 6) end
            if b.text then
                texts = texts + 1
                local t = p.texts[texts] or UI.Text(c)
                p.texts[texts] = t
                t:SetFontObject(b.font or "GameFontHighlightSmall")
                t:SetSpacing(3)
                t:SetText(b.text)
                local room = w
                if b.right then
                    local r = p.rights[texts] or UI.Text(c)
                    p.rights[texts] = r
                    r:SetJustifyH("RIGHT")
                    r:SetWidth(0)
                    r:SetText(b.right)
                    room = w - r:GetStringWidth() - 12
                    r:ClearAllPoints()
                    r:SetPoint("BOTTOMRIGHT", t, "BOTTOMLEFT", w, 0)
                    r:Show()
                end
                t:SetWidth(room)
                PutAt(t, 0, y)
                y = y - t:GetStringHeight()
            elseif b.pair then
                pairCount = pairCount + 1
                local left, right = p.pairs[2 * pairCount - 1] or UI.Text(c), p.pairs[2 * pairCount] or UI.Text(c)
                p.pairs[2 * pairCount - 1], p.pairs[2 * pairCount] = left, right
                left:SetText(b.pair)
                right:SetText(b.right or "")
                left:SetWidth(0)
                local lw = left:GetStringWidth()
                PutAt(left, 0, y)
                if UI.FitPair(left, right, w) then
                    y = y - left:GetStringHeight() - 2
                    PutAt(right, UI.PAIR_GAP, y)
                    y = y - right:GetStringHeight()
                else
                    right:ClearAllPoints()
                    right:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, y)
                    right:Show()
                    y = y - math.max(left:GetStringHeight(), right:GetStringHeight())
                end
                if b.itemID then
                    local hit = p.hits[pairCount]
                    if not hit then
                        hit = CreateFrame("Frame", nil, c)
                        UI.ItemHover(hit, function(self) return self.itemID end, "OnMouseUp")
                        p.hits[pairCount] = hit
                    end
                    hit.itemID = b.itemID
                    hit:ClearAllPoints()
                    hit:SetPoint("TOPLEFT", left, "TOPLEFT")
                    hit:SetSize(math.min(lw, left:GetWidth()), left:GetStringHeight())
                    hit:EnableMouse(true)
                    hit:Show()
                end
            elseif b.fold then
                local fold = Region("folds", UI.FoldTitle)
                PutAt(fold, 0, y)
                y = y - fold:Set(b, w)
            elseif b.row then
                local row = Region("rows", UI.StepRow)
                row:SetScript("OnClick", b.onClick)
                PutAt(row, -UI.STEP_PAD, y)
                y = y - row:Set(b, w)
            elseif b.bar then
                local bar = Region("bars", UI.StepBar)
                PutAt(bar, 0, y)
                y = y - bar:Set(b, w)
            elseif b.line then
                lines = lines + 1
                local l = p.lines[lines] or UI.LinkLine(c)
                p.lines[lines] = l
                local height = l:Set(b.line, b.right, w)
                l:SetScript("OnClick", b.onClick)
                PutAt(l, -4, y)
                y = y - height
            elseif b.places then
                y = y - p.places:Layout(b.places, b.total, 0, y, w, b.expanded)
            elseif b.track then
                p.track:Set(b.track, b.key, b.char)
                PutAt(p.track.materials, 0, y)
                p.track.shopping:ClearAllPoints()
                p.track.shopping:SetPoint("LEFT", p.track.materials, "RIGHT", 6, 0)
                p.track:SetShown(true)
                y = y - 20
            elseif b.buttons then
                local x = 0
                for _, spec in ipairs(b.buttons) do
                    buttons = buttons + 1
                    local button = p.buttons[buttons] or UI.Button(c, "", "quiet", true)
                    p.buttons[buttons] = button
                    button:SetKind(spec.kind or "quiet", spec.label)
                    button:SetScript("OnClick", spec.onClick)
                    UI.ButtonTip(button, spec.tip)
                    if x > 0 and x + button:GetWidth() > w then x, y = 0, y - 26 end
                    PutAt(button, x, y)
                    x = x + button:GetWidth() + 6
                end
                y = y - 20
            elseif b.stepper then
                p.stepper.min, p.stepper.onChange = b.min or 1, b.onChange
                p.stepper:SetValue(b.stepper)
                PutAt(p.stepper, 0, y)
                p.stepNote:SetWidth(w - p.stepper:GetWidth() - 12)
                p.stepNote:SetText(b.note or "")
                p.stepNote:ClearAllPoints()
                p.stepNote:SetPoint("LEFT", p.stepper, "RIGHT", 12, 0)
                p.stepNote:Show()
                y = y - 24
            end
        end
        return self:Fit(-y, keepScroll)
    end
    return pane
end
