-- Coverage.lua: the Coverage page. How much of each profession the account knows, and the
-- recipes nobody knows yet: ready to learn, or needing more skill.

local _, ns = ...

local View = {}
ns.CoverageView = View

local TEXT = ns.UI.TEXT
local CAN_LEARN = TEXT.canLearn
local GREEN, MUTED, SOFT, GOLD = TEXT.green, TEXT.muted, TEXT.soft, TEXT.gold
local Color = ns.UI.ColorText

local function PlayedFirst(a, b)
    if ns.IsPlayed(a.key) ~= ns.IsPlayed(b.key) then return ns.IsPlayed(a.key) end
    return (a.prof.skill or 0) > (b.prof.skill or 0)
end

local lastList, lastWidth, lastHeight = {}, 600, 400

local ShortName = ns.UI.ShortName

local Plural = ns.UI.Plural

local function ProfessionNote(p)
    if #p.holders == 0 then return nil end
    local who = #p.holders == 1 and ShortName(p.holders[1]) or (#p.holders .. " characters")
    if not p.scanned then
        if p.known > 0 then return ("%d known by %s, open the window for the %%"):format(p.known, who) end
        return "Not scanned yet, " .. who
    end
    return ("%d of %d, %s"):format(p.known, p.total, who)
end

local function ProfessionShare(p)
    if #p.holders == 0 then return "Nobody" end
    if p.total == 0 then return "?" end
    return math.floor(p.known / p.total * 100 + 0.5) .. "%"
end

local function Subtitle(p)
    if #p.holders == 0 then return "Nobody on this account has it" end
    local who = #p.holders == 1 and ("Only " .. ShortName(p.holders[1]) .. " has it.")
        or (#p.holders .. " characters have it.")
    if not p.scanned then
        if p.known > 0 then return ("%d known. %s"):format(p.known, who) end
        return "Not scanned yet. " .. who
    end
    local ignored = (p.ignored or 0) > 0 and (", %d ignored"):format(p.ignored) or ""
    return ("%d of %d known%s. %s"):format(p.known, p.total, ignored, who)
end

local function GroupNote(p, key)
    local best = ns.CoverageData.BestHolder(p)
    if not best then return "" end
    if key == "ready" then return ("%s: skill %d"):format(ShortName(best), best.prof.skill or 0) end
    if key == "needs" then return ("%s is closest"):format(ShortName(best)) end
    return ""
end

local function RequiresText(item)
    if item.state == "known" then return "" end
    if not item.required then return Color(MUTED, "?") end
    if item.state == "needs" and item.best then
        return Color(TEXT.amber, ("%d, %d to go"):format(item.required, item.required - (item.best.prof.skill or 0)))
    end
    return tostring(item.required)
end

local function WhereText(item)
    return ns.RecipeWhereShort(item.id) or Color(MUTED, "Unknown")
end

local Reagents = ns.Reagents

local function RequiredOf(item, p) return item.required or ns.RequiredSkill(item.id, p.skillLine) end

local function DetailText(p, item, withNames)
    local lines = {}
    local required = RequiredOf(item, p)
    if required and required > 1 then
        lines[#lines + 1] = ("Requires %s %d"):format(p.name, required) .. (item.borrowed and Color(MUTED, " (Vanilla data)") or "")
    end
    local places, _, only = ns.Places.Kept(item, item.id)
    if #places == 0 and only then lines[#lines + 1] = Color(MUTED, ns.Places.OnlyText(item.id, only)) end
    local sources = ns.RecipeWhere(item.id, withNames, #places > 0 or only ~= nil)
    for _, line in ipairs(sources or {}) do lines[#lines + 1] = line end
    local reagents = Reagents(item.id, p.skillLine)
    if #reagents > 0 then
        lines[#lines + 1] = " "
        lines[#lines + 1] = Color(GOLD, "Materials for one")
        for _, r in ipairs(reagents) do
            local material, held = ns.UI.ReagentLine(r[1], r[2], (ns.Bags.HeldText(r[1], lastList or {}, { max = 2 })))
            lines[#lines + 1] = material .. ": " .. held
        end
    end
    return table.concat(lines, "\n")
end

local function HolderText(h, item)
    local skill = h.prof.skill or 0
    local note
    if h.scan and h.scan.known[item.id] then
        note = Color(SOFT, ": knows it")
    elseif not h.scan then
        note = Color(SOFT, ": not scanned yet")
    elseif item.required and skill >= item.required then
        note = Color(GREEN, (": skill %d, can learn it"):format(skill))
    else
        note = Color(SOFT, (": skill %d, needs %s"):format(skill, item.required or "?"))
    end
    if not ns.IsPlayed(h.key) then note = note .. Color(SOFT, ", not played") end
    return ShortName(h) .. note
end

local function GapLines(professions, p)
    local lines = {}
    local nobody = {}
    for _, other in ipairs(professions) do
        if #other.holders == 0 then nobody[#nobody + 1] = other.name end
    end
    if #nobody > 0 then
        lines[#lines + 1] = table.concat(nobody, ", ")
        lines[#lines + 1] = Color(SOFT, Plural(#nobody, "Nobody on this account has it.", "Nobody on this account has them."))
    else
        lines[#lines + 1] = Color(SOFT, "Every crafting profession is on this account.")
    end
    if p and p.scanned then
        local losses = {}
        for _, loss in ipairs(ns.CoverageData.OnlyKnownBy(p)) do
            if loss.count > 0 and #losses < 5 then
                losses[#losses + 1] = ShortName(loss.holder) .. "\t" .. loss.count
            end
        end
        if #losses > 0 then
            lines[#lines + 1] = " "
            lines[#lines + 1] = "Before you unlearn " .. p.name
            lines[#lines + 1] = Color(SOFT, "Recipes only they know")
            for _, text in ipairs(losses) do lines[#lines + 1] = text end
        end
    end
    return lines
end

local LIST_WIDTH = 210
local GAP = 14
local NOTE_TOP, NOTE_WIDTH = 31, LIST_WIDTH - 16
local NAME_ONLY = 24
local ROW_HEIGHT = 22
local HEADER_HEIGHT = 26
local INDENT = 28
local TRACK_ROW = 26

local REQUIRES_WIDTH, WHERE_WIDTH, NAME_WIDTH = 92, 110, 240

local PAGE = ns.UI.PAGE
local CONTROLS_Y = ns.UI.Below(PAGE.top, PAGE.titleHeight)
local LABELS_Y = CONTROLS_Y - PAGE.controlsToStatus
local LIST_TOP = LABELS_Y - PAGE.statusToList

local panel
local profButtons = {}
local state = { professions = {}, current = nil, groups = nil, items = {}, cols = {} }

local function Picks()
    ns.view.coverage = ns.view.coverage or { search = "", closed = { known = true } }
    return ns.view.coverage
end

local Refresh
local PlaceFilters


local function GetProfButton(index)
    if profButtons[index] then return profButtons[index] end
    local UI = ns.UI
    local b = CreateFrame("Button", nil, panel)
    b:SetWidth(LIST_WIDTH)
    b.fill = UI.RoundedBox(b, 6)
    b.fill:SetFill(UI.C.selected)
    UI.RoundedHover(b, 6)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("TOPLEFT", 8, -6)
    b.share = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.share:SetPoint("TOPRIGHT", -8, -7)
    local holder, bar = UI.SkillBar(b, LIST_WIDTH - 16)
    holder:SetPoint("TOPLEFT", 8, -23)
    holder:SetPoint("TOPRIGHT", -8, -23)
    bar:SetMinMaxValues(0, 1)
    b.bar, b.barHolder = bar, holder
    b.note = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.note:SetPoint("TOPLEFT", 8, -NOTE_TOP)
    b.note:SetPoint("TOPRIGHT", -8, -NOTE_TOP)
    b.note:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        local picks = Picks()
        picks.profession, picks.open = self.skillLine, nil
        Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        if state.gapsShown then return end
        local p
        for _, other in ipairs(state.professions) do
            if other.skillLine == self.skillLine then p = other end
        end
        ns.UI.RowTooltip(self)
        ns.UI.TipLine(GameTooltip, "Account gaps", "gold")
        for _, line in ipairs(GapLines(state.professions, p)) do
            local left, right = line:match("^(.-)\t(.*)$")
            if left then ns.UI.TipDoubleLine(GameTooltip, left, right) else ns.UI.TipLine(GameTooltip, line, nil, true) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    profButtons[index] = b
    return b
end

local function RefreshProfessions()
    local picks = Picks()
    local y = PAGE.top - 18
    for i, p in ipairs(state.professions) do
        local b = GetProfButton(i)
        local selected = p.skillLine == picks.profession
        b.skillLine = p.skillLine
        b:SetPoint("TOPLEFT", 0, y)
        b.fill:SetShown(selected)
        b.name:SetText(p.name)
        if selected then
            b.name:SetTextColor(unpack(ns.UI.Hex(GOLD)))
        elseif #p.holders == 0 then
            b.name:SetTextColor(unpack(ns.UI.Hex(SOFT)))
        else
            b.name:SetTextColor(unpack(ns.UI.Hex(TEXT.body)))
        end
        b.share:SetText(ProfessionShare(p))
        b.share:SetTextColor(unpack(ns.UI.Hex(#p.holders == 0 and SOFT or TEXT.light)))
        b.bar:SetValue(p.total > 0 and p.known / p.total or 0)
        local note = ProfessionNote(p)
        b.barHolder:SetShown(note ~= nil)
        b.note:SetText(note or "")
        b:SetHeight(note and NOTE_TOP + ns.UI.TextHeight(note, NOTE_WIDTH, "GameFontDisableSmall") + 4 or NAME_ONLY)
        b:Show()
        y = y - b:GetHeight() - 2
    end
    for i = #state.professions + 1, #profButtons do profButtons[i]:Hide() end

    panel.gaps:Fit(panel.gaps:SetLines(GapLines(state.professions, state.current), LIST_WIDTH))
    panel.gaps.body = panel.gaps.text
    panel.gaps:ClearAllPoints()
    panel.gaps:SetPoint("TOPLEFT", 0, y - 10)
    state.gapsTop = -(y - 10)
    state.gapsShown = state.gapsTop + panel.gaps:GetHeight() <= lastHeight
    panel.gaps:SetShown(state.gapsShown)
end

local function ShowRowTooltip(row)
    local item = row.data and row.data.item
    local p = state.current
    if not item or not p or item.state == "ignored" then return end
    ns.UI.RowTooltip(row)
    ns.UI.RecipeTooltipTop(item.id, ns.db.recipes[item.id], item.name, p.skillLine, function()
        if GameTooltip:IsOwned(row) and row.data and row.data.item == item then ShowRowTooltip(row) end
    end)
    local required = RequiredOf(item, p)
    if required and required > 1 then ns.UI.TipLine(GameTooltip, ("Requires %s %d"):format(p.name, required)) end
    local withNames = IsShiftKeyDown()
    local places, total, only = ns.Places.Kept(item, item.id)
    ns.UI.AddPlaceLines(GameTooltip, places, total, withNames)
    if #places == 0 and only then ns.UI.TipLine(GameTooltip, ns.Places.OnlyText(item.id, only), "light", true) end
    for _, line in ipairs(ns.RecipeWhere(item.id, withNames, #places > 0 or only ~= nil) or {}) do
        ns.UI.TipLine(GameTooltip, line)
    end
    if item.state == "known" then
        GameTooltip:AddLine(" ")
        ns.UI.TipLine(GameTooltip, "Known by", "gold")
        ns.UI.TipLine(GameTooltip, table.concat(ns.UI.ShortNames(item.knowers), ", "), nil, true)
    end
    ns.UI.AddTrackedLines(item.id)
    GameTooltip:AddLine(" ")
    ns.UI.TipLine(GameTooltip, "Click to open", "light")
    ns.UI.TipLine(GameTooltip, "Right-click: track materials or add to shopping list", "light")
    GameTooltip:Show()
end

local function TrackMenu(row)
    local item = row.data and row.data.item
    local p = state.current
    if not (item and p and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(item.name)
        if item.state == "ignored" then
            ns.Ignore.AddMenuLine(root, item.id)
            return
        end
        local holders = {}
        for _, h in ipairs(p.holders) do if h.scan then holders[#holders + 1] = h end end
        table.sort(holders, PlayedFirst)
        for _, h in ipairs(holders) do
            local index = ns.Tracking.Find(item.id, h.key)
            root:CreateButton((index and "Remove from shopping list for " or "Add to shopping list for ") .. ns.UI.CharName(h.char, h.key), function()
                if index then ns.Tracking.Untrack(index) else ns.Tracking.Track(item.id, h.key) end
            end)
        end
        ns.Ignore.AddMenuLine(root, item.id)
    end)
end

local function OnRowClick(row, button)
    local data = row.data
    if not data or data.detail then return end
    if button == "RightButton" then
        if data.item then TrackMenu(row) end
        return
    end
    local picks = Picks()
    if data.group then
        picks.closed[data.group] = not picks.closed[data.group] or nil
    elseif data.sub then
        picks.closed[data.sub] = not picks.closed[data.sub] or nil
    elseif data.item and data.item.state ~= "ignored" then
        picks.open = picks.open ~= data.item.id and data.item.id or nil
    end
    Refresh()
end

local function DetailParts(row)
    if row.detailParts then return row.detailParts end
    local UI = ns.UI
    local d = { holders = {} }
    d.box = UI.Card(row, 8)
    d.box:SetPoint("TOPLEFT", INDENT, -2)
    d.box:SetPoint("BOTTOMRIGHT", -4, 8)
    d.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.text:SetPoint("TOPLEFT", INDENT + 12, -12)
    d.text:SetJustifyH("LEFT")
    d.text:SetSpacing(3)
    d.whoTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.whoTitle:SetText("Who can get it")
    d.whereTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.whereTitle:SetText("Where to learn it")
    d.places = UI.PlaceLines(row, function()
        local open = Picks().allPlaces
        Picks().allPlaces = open ~= row.placesFor and row.placesFor or nil
        Refresh()
    end)
    function d.Holder(i)
        if d.holders[i] then return d.holders[i] end
        local h = {}
        h.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        h.text:SetJustifyH("LEFT")
        h.track = UI.TrackButtons(row)
        d.holders[i] = h
        return h
    end
    row.detailParts = d
    return d
end

local function HideDetail(row)
    local d = row.detailParts
    if not d then return end
    d.box:Hide()
    d.text:Hide()
    d.whoTitle:Hide()
    d.whereTitle:Hide()
    d.places:Hide()
    for _, h in ipairs(d.holders) do h.text:Hide() h.track:SetShown(false) end
end

local function PlacesHeight(item)
    local places, total = ns.Places.Kept(item, item.id)
    if #places == 0 then return 0 end
    return 18 + ns.UI.PlaceLinesHeight(places, total, state.cols.detailWidth, Picks().allPlaces == item.id) + 8
end

local STACKED = 22
local function NameColumn(item)
    local widest = 0
    for _, h in ipairs(state.current.holders) do
        widest = math.max(widest, ns.UI.TextWidth(HolderText(h, item), "GameFontHighlightSmall"))
    end
    return widest + 14
end
local function Stacked(h, item)
    return h.scan ~= nil and NameColumn(item) + ns.UI.TrackButtonsWidth(item.id, h.key) > state.cols.detailWidth
end

local function DetailHeight(item)
    local p = state.current
    local text = ns.UI.TextHeight(DetailText(p, item, true), state.cols.detailWidth, "GameFontHighlightSmall", 3)
    local holders = 0
    for _, h in ipairs(p.holders) do holders = holders + TRACK_ROW + (Stacked(h, item) and STACKED or 0) end
    return math.ceil(12 + PlacesHeight(item) + text + 12 + 16 + holders + 18)
end

local function InitDetail(row, data)
    local d = DetailParts(row)
    local p, item = state.current, data.detail
    d.box:Show()
    local y = -12
    local places, total = ns.Places.Kept(item, item.id)
    row.placesFor = item.id
    if #places > 0 then
        d.whereTitle:ClearAllPoints()
        d.whereTitle:SetPoint("TOPLEFT", INDENT + 12, y)
        d.whereTitle:Show()
        y = y - 18 - d.places:Layout(places, total, INDENT + 12, y - 18, state.cols.detailWidth, Picks().allPlaces == item.id) - 8
    else
        d.whereTitle:Hide()
        d.places:Hide()
    end
    d.text:ClearAllPoints()
    d.text:SetPoint("TOPLEFT", INDENT + 12, y)
    d.text:SetWidth(state.cols.detailWidth)
    d.text:SetText(DetailText(p, item, true))
    d.text:Show()
    y = y - d.text:GetStringHeight() - 12
    d.whoTitle:ClearAllPoints()
    d.whoTitle:SetPoint("TOPLEFT", INDENT + 12, y)
    d.whoTitle:Show()
    y = y - 18
    local holders = {}
    for _, h in ipairs(p.holders) do holders[#holders + 1] = h end
    table.sort(holders, PlayedFirst)
    for i, h in ipairs(holders) do
        local line = d.Holder(i)
        line.text:ClearAllPoints()
        line.text:SetPoint("TOPLEFT", INDENT + 12, y - 6)
        line.text:SetText(HolderText(h, item))
        line.text:Show()
        local stacked = Stacked(h, item)
        line.track:Set(item.id, h.key, h.char)
        line.track.materials:ClearAllPoints()
        if stacked then
            line.track.materials:SetPoint("TOPLEFT", INDENT + 12, y - STACKED - 2)
        else
            line.track.materials:SetPoint("TOPLEFT", INDENT + 12 + NameColumn(item), y - 3)
        end
        line.track.shopping:ClearAllPoints()
        line.track.shopping:SetPoint("LEFT", line.track.materials, "RIGHT", 6, 0)
        line.track:SetShown(h.scan ~= nil)
        y = y - TRACK_ROW - (stacked and STACKED or 0)
    end
    for i = #holders + 1, #d.holders do d.holders[i].text:Hide() d.holders[i].track:SetShown(false) end
end

local function HeaderOptions(data)
    return { x = data.sub and INDENT - 6 or 6, title = data.title, note = data.note, open = not data.closed,
             count = tostring(data.count), line = data.sub ~= nil, width = state.cols.rowWidth }
end

-- Frames are reused while scrolling, so every call sets everything.
local function InitRow(row, data)
    local UI = ns.UI
    if not row.made then
        row.made = true
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetPoint("TOPLEFT", 0, 0)
        row.hover:SetPoint("BOTTOMRIGHT", 0, 0)
        row.hover:SetColorTexture(unpack(UI.C.hover))
        row.tracked = UI.TrackedFill(row)
        row.pickedFill = UI.RoundedBox(row, 6)
        row.pickedFill:SetFill(UI.C.selected)

        row.fold = UI.FoldHeader(row)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetJustifyH("LEFT")
        row.requires = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.requires:SetJustifyH("LEFT")
        row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.where:SetJustifyH("LEFT")
        row.where:SetTextColor(unpack(UI.Hex(TEXT.light)))
        row.unignore = UI.SquareButton(row, "×", "Stop ignoring", 20)
        row.unignore:SetPoint("RIGHT", -8, 0)
        row.unignore:SetScript("OnClick", function() ns.Ignore.Set(row.data.item.id, false) end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", OnRowClick)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.data = data
    local isHeader, isDetail = data.group ~= nil or data.sub ~= nil, data.detail ~= nil
    local isRecipe = not isHeader and not isDetail
    local isIgnored = isRecipe and data.item.state == "ignored"
    row.fold:SetShown(isHeader)
    row.name:SetShown(isRecipe)
    row.requires:SetShown(isRecipe and not isIgnored)
    row.where:SetShown(isRecipe and not isIgnored and state.cols.where)
    row.unignore:SetShown(isIgnored)
    row.hover:SetShown(not isDetail)
    row.pickedFill:SetShown(isRecipe and data.item.id == Picks().open)
    row.tracked:SetShown(isRecipe and data.item.id ~= Picks().open and ns.Tracking.IsTracked(data.item.id))
    if not isDetail then HideDetail(row) end
    if isHeader then
        row.fold:Set(HeaderOptions(data))
        return
    end
    if isDetail then
        InitDetail(row, data)
        return
    end

    local cols, item = state.cols, data.item
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", cols.nameX, 0)
    row.name:SetWidth(cols.name)
    row.requires:ClearAllPoints()
    row.requires:SetPoint("LEFT", cols.requiresX, 0)
    row.requires:SetWidth(REQUIRES_WIDTH)
    if cols.where then
        row.where:ClearAllPoints()
        row.where:SetPoint("LEFT", cols.whereX, 0)
        row.where:SetWidth(cols.whereWidth)
        row.where:SetText(WhereText(item))
    end
    local color = item.state == "ready" and CAN_LEARN or TEXT.body
    row.name:SetText(Color(color, item.name))
    row.requires:SetText(RequiresText(item))
end

local function RecipeHeight(item)
    local cols, small = state.cols, "GameFontHighlightSmall"
    local name = ns.UI.TextHeight(item.name, cols.name)
    if item.state == "ignored" then return math.max(ROW_HEIGHT, math.ceil(name + 6)) end
    local tallest = math.max(name,
        ns.UI.TextHeight(RequiresText(item), REQUIRES_WIDTH, small),
        cols.where and ns.UI.TextHeight(WhereText(item), cols.whereWidth, small) or 0)
    return math.max(ROW_HEIGHT, math.ceil(tallest + 6))
end

local RANKS = {
    { key = "apprentice", title = ns.RANKS[75], range = "1–75", below = 75 },
    { key = "journeyman", title = ns.RANKS[150], range = "75–150", below = 150 },
    { key = "expert", title = ns.RANKS[225], range = "150–225", below = 225 },
    { key = "artisan", title = ns.RANKS[300], range = "225–300", below = math.huge },
}
local UNKNOWN_RANK = { key = "unknown", title = "Skill unknown" }
local function RankOf(required)
    if not required then return UNKNOWN_RANK end
    for _, r in ipairs(RANKS) do
        if required < r.below then return r end
    end
end

local function ListItems(groups)
    local picks = Picks()
    local p = state.current
    local items = {}
    for _, g in ipairs({ { key = "ready", title = "Ready to learn" }, { key = "needs", title = "Needs more skill" },
                         { key = "known", title = "Known" }, { key = "ignored", title = "Ignored" } }) do
        local list = groups[g.key] or {}
        if #list > 0 then
            local closed = picks.closed[g.key] and true or false
            local note = GroupNote(p, g.key)
            items[#items + 1] = { group = g.key, title = g.title, note = note, count = #list,
                                  closed = closed, first = #items == 0 }
            local function AddRows(rows)
                for _, item in ipairs(rows) do
                    items[#items + 1] = { item = item, height = RecipeHeight(item) }
                    if item.id == picks.open then
                        items[#items + 1] = { detail = item, height = DetailHeight(item) }
                    end
                end
            end
            if not closed and (g.key == "known" or g.key == "ignored") then
                AddRows(list)
            elseif not closed then
                -- Relies on the list being sorted by required skill, so ranks come in order.
                local byRank, ranks = {}, {}
                for _, item in ipairs(list) do
                    local r = RankOf(item.required)
                    if not byRank[r] then byRank[r], ranks[#ranks + 1] = {}, r end
                    table.insert(byRank[r], item)
                end
                local split = #ranks > 1
                for _, r in ipairs(ranks) do
                    local key = g.key .. ":" .. r.key
                    local subClosed = split and picks.closed[key] and true or false
                    if split then
                        items[#items + 1] = { sub = key, title = r.title, closed = subClosed, note = r.range,
                                              count = #byRank[r], firstSub = r == ranks[1] }
                    end
                    if not subClosed then AddRows(byRank[r]) end
                end
            end
        end
    end
    return items
end

local WHERE_FILTERS = { { key = "all", label = "All" } }
for _, kind in ipairs(ns.SOURCE_KINDS) do WHERE_FILTERS[#WHERE_FILTERS + 1] = kind end
local FILTER_GAP, FILTER_ROW = 4, 28

local function WhereKeys(item)
    item.where = item.where or ns.RecipeSourceKeys(item.id)
    return item.where
end
View.WhereKeys = WhereKeys
View.SIZES = { filterGap = FILTER_GAP, filterRow = FILTER_ROW, noteTop = NOTE_TOP, noteWidth = NOTE_WIDTH }

function PlaceFilters()
    local shown, width = {}, 0
    for _, b in ipairs(panel.whereButtons) do
        if b:IsShown() then
            width = width + b:GetWidth() + (#shown > 0 and FILTER_GAP or 0)
            shown[#shown + 1] = b
        end
    end
    local room = panel.middle:GetWidth() or 0
    local beside = 6 + panel.search:GetWidth() + 16 + (panel.hideKnown:GetWidth() or 0) + 16
    local fits = #shown == 0 or beside + width <= room
    local last = ns.UI.Flow(shown, room - 6, FILTER_GAP, fits and (beside - 6) or 0, function(b, row, previous)
        b:ClearAllPoints()
        if previous then
            b:SetPoint("LEFT", previous, "RIGHT", FILTER_GAP, 0)
        elseif fits then
            b:SetPoint("LEFT", panel.hideKnown, "RIGHT", 16, 0)
        else
            b:SetPoint("TOPLEFT", 6, CONTROLS_Y - (row + 1) * FILTER_ROW)
        end
    end)
    local rows = fits and 0 or last + 1
    local shift = rows * FILTER_ROW
    local cols = state.cols
    panel.nameLabel:SetPoint("TOPLEFT", cols.nameX, LABELS_Y - shift)
    panel.requiresLabel:SetPoint("TOPLEFT", cols.requiresX, LABELS_Y - shift)
    panel.whereLabel:SetPoint("TOPLEFT", cols.whereX, LABELS_Y - shift)
    panel.whereLabel:SetShown(cols.where)
    panel.listLine:SetPoint("TOPLEFT", 0, LIST_TOP + 2 - shift)
    panel.listLine:SetPoint("TOPRIGHT", 0, LIST_TOP + 2 - shift)
    ns.UI.PlaceList(panel.middle.list, LIST_TOP - 2 - shift)
end

local function FilterGroups(groups)
    local picks = Picks()
    local counts = { all = 0 }
    for _, key in ipairs({ "ready", "needs" }) do
        for _, item in ipairs(groups and groups[key] or {}) do
            counts.all = counts.all + 1
            for kind in pairs(WhereKeys(item)) do counts[kind] = (counts[kind] or 0) + 1 end
        end
    end
    if not groups or not counts[picks.where or "all"] then picks.where = nil end
    local pick = picks.where or "all"
    for i, f in ipairs(WHERE_FILTERS) do
        local b = panel.whereButtons[i]
        local n = counts[f.key]
        b:SetShown(groups ~= nil and n ~= nil)
        b.text:SetText(f.label .. "  " .. Color(MUTED, tostring(n or 0)))
        b:SetWidth(b.text:GetStringWidth() + 20)
        b:SetSelected(f.key == pick)
    end
    if groups and pick ~= "all" then
        for _, key in ipairs({ "ready", "needs" }) do
            local kept = {}
            for _, item in ipairs(groups[key]) do
                if WhereKeys(item)[pick] then kept[#kept + 1] = item end
            end
            groups[key] = kept
        end
    end
end

local function Layout(width)
    local middleX = LIST_WIDTH + GAP
    local middleWidth = width - middleX
    panel.middle:ClearAllPoints()
    panel.middle:SetPoint("TOPLEFT", middleX, 0)
    panel.middle:SetPoint("BOTTOMLEFT", middleX, 0)
    panel.middle:SetWidth(middleWidth)

    local rowWidth = middleWidth - 16 - 14
    local cols = ns.UI.Columns(INDENT, rowWidth - INDENT, { width = NAME_WIDTH, min = 120 }, {
        { key = "requires", width = REQUIRES_WIDTH, always = true },
        { key = "where", width = WHERE_WIDTH },
    })
    cols.nameX, cols.rowWidth = INDENT, rowWidth
    cols.requiresX, cols.whereX = cols.x.requires, cols.x.where or 0
    cols.whereWidth = cols.where and cols.lastWidth or WHERE_WIDTH
    cols.detailWidth = middleWidth - INDENT - 24 - 14 - 16
    state.cols = cols
    PlaceFilters()
end

local function RefreshMiddle()
    local picks = Picks()
    local p = state.current
    local middle = panel.middle
    middle.title:SetText(p and p.name or "")
    middle.subtitle:SetText(p and Subtitle(p) or "")
    panel.hideKnown:SetChecked(picks.closed.known and true or false)

    local message = ""
    if not p then
        message = "Log in on a character to add it here."
        state.groups, state.items = nil, {}
    elseif #p.holders == 0 then
        message = ("Nobody on this account has %s yet."):format(p.name)
        state.groups, state.items = nil, {}
    elseif not p.scanned then
        local h = p.holders[1]
        local who = (h.key == ns.CharacterKey()) and "your" or (ns.UI.CharName(h.char, h.key) .. "'s")
        message = p.known > 0
            and ("%d known so far, read at login.\nOpen %s %s window once for the full list and what's left to learn.")
                :format(p.known, who, p.name)
            or ("Not scanned yet.\nOpen %s %s window once to read its recipes."):format(who, p.name)
        state.groups, state.items = nil, {}
    else
        state.groups = ns.CoverageData.Recipes(p, strtrim(picks.search or ""):lower())
        FilterGroups(state.groups)
        state.items = ListItems(state.groups)
        if #state.items == 0 then message = "No recipes match." end
    end
    if not state.groups then FilterGroups(nil) end
    PlaceFilters()
    middle.message:SetText(message)
    middle.message:SetShown(message ~= "")
    state.drawnKey = state.cols.key
    middle.list.box:SetDataProvider(CreateDataProvider(state.items), ScrollBoxConstants.RetainScrollPosition)
end

local function PickProfession()
    local picks = Picks()
    local first, firstScanned
    for _, p in ipairs(state.professions) do
        if p.skillLine == picks.profession then return p end
        first = first or p
        if p.scanned and not firstScanned then firstScanned = p end
    end
    local p = firstScanned or first
    picks.profession = p and p.skillLine or nil
    return p
end

function Refresh()
    state.professions = ns.CoverageData.Professions(lastList)
    state.current = PickProfession()
    Layout(lastWidth)
    RefreshProfessions()
    RefreshMiddle()
end

function View.Refresh(list, width, height, layoutOnly)
    lastList, lastWidth, lastHeight = list, width or lastWidth, height or lastHeight
    local search = Picks().search or ""
    if panel.search:GetText() ~= search then panel.search:SetText(search) end
    if layoutOnly and state.current then
        Layout(lastWidth)
        state.gapsShown = (state.gapsTop or 0) + panel.gaps:GetHeight() <= lastHeight
        panel.gaps:SetShown(state.gapsShown)
        if state.cols.key ~= state.drawnKey then
            state.drawnKey = state.cols.key
            if not ns.UI.RedrawRows(panel.middle.list) then
                panel.middle.list.box:SetDataProvider(CreateDataProvider(state.items), ScrollBoxConstants.RetainScrollPosition)
            end
        end
        return
    end
    Refresh()
end

function View.Build(parent)
    local UI = ns.UI
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.coverage = true
    profButtons = {}

    panel.listHeader = UI.SmallHeading(panel, "Known on this account")
    panel.listHeader:SetPoint("TOPLEFT", 8, PAGE.top)
    panel.gaps = UI.TitledCard(panel, "Account gaps")
    panel.gaps:SetWidth(LIST_WIDTH)

    local middle = CreateFrame("Frame", nil, panel)
    panel.middle = middle
    middle.title = UI.PageTitle(middle)
    middle.title:SetPoint("TOPLEFT", 0, PAGE.top)
    middle.subtitle = middle:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    middle.subtitle:SetPoint("BOTTOMLEFT", middle.title, "BOTTOMRIGHT", 10, 1)

    panel.search = UI.SearchBox(middle, function(text)
        Picks().search = text
        if state.current then RefreshMiddle() end
    end)
    -- 6 px in: the search box's art reaches a little to the left.
    panel.search:SetPoint("TOPLEFT", 6, CONTROLS_Y)

    panel.hideKnown = UI.Checkbox(middle, "Hide known", function(checked)
        Picks().closed.known = checked or nil
        Refresh()
    end)
    panel.hideKnown:SetPoint("LEFT", panel.search, "RIGHT", 16, 0)

    panel.whereButtons = {}
    for i, f in ipairs(WHERE_FILTERS) do
        local b = UI.SelectableButton(middle, 22)
        b.text:SetPoint("CENTER")
        b.text:SetFontObject("GameFontHighlightSmall")
        b.key = f.key
        b:SetScript("OnClick", function(self)
            Picks().where = self.key ~= "all" and self.key or nil
            RefreshMiddle()
        end)
        panel.whereButtons[i] = b
    end

    for key, text in pairs({ nameLabel = "Recipe", requiresLabel = "Requires", whereLabel = "Where" }) do
        local label = middle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetText(text)
        panel[key] = label
    end
    panel.listLine = UI.Divider(middle)

    middle.list = UI.ScrollList(middle, function(data)
        local extra = (data.group or data.sub) and ns.UI.FoldNoteExtra(HeaderOptions(data), state.cols.rowWidth) or 0
        if data.group then return HEADER_HEIGHT + (data.first and 0 or 8) + extra end
        if data.sub then return ns.UI.HeadingExtent(data.firstSub) + extra end
        return data.height or ROW_HEIGHT
    end, InitRow)
    middle.scrollBox = middle.list.box

    middle.message = middle:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    middle.message:SetPoint("TOP", middle.list.box, "TOP", 0, -40)
    middle.message:SetWidth(360)
    middle.message:SetSpacing(3)


    return panel
end

ns.UI.AddPage("coverage", View)
