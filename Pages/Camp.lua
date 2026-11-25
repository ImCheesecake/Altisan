-- Camp.lua: the Camp page. What each character can bring to a campfire, and the Blueprints
-- closest to use. A camp is a temporary campfire where each player adds one object, so
-- nothing about it belongs to the account: the page is per character.

local _, ns = ...

local Camp = {}
ns.CampView = Camp

local TEXT = ns.UI.TEXT
local Color = ns.UI.ColorText
local LIGHT = TEXT.light
local ShortName = ns.UI.ShortName

local PAGE = ns.UI.PAGE
local PROF_WIDTH = 130
local SIDE_WIDTH = 240
local GAP = 14
local WIDE = 700
local MAX_BLUEPRINTS = 5

local panel
local last = { list = {}, width = 600, height = 400 }

local function CellText(p, o)
    if not o then return Color(LIGHT, "-"), "" end
    if o.campfire then
        return Color(TEXT.body, o.name), Color(LIGHT, "Known by every cook"), true
    end
    if #o.knowers > 0 then
        local who = (#p.holders > 1 and #o.knowers == #p.holders) and "everyone" or table.concat(ns.UI.ShortNames(o.knowers), ", ")
        return Color(TEXT.body, o.name), Color(LIGHT, "Known by ") .. who, true
    end
    local best = p.best
    if not best then return Color(TEXT.soft, o.name), Color(LIGHT, "nobody you play has it scanned") end
    local skill = best.prof.skill or 0
    if not o.required then
        return Color(TEXT.canLearn, o.name), ShortName(best) .. Color(LIGHT, " can learn it")
    elseif skill >= o.required then
        return Color(TEXT.canLearn, o.name), ShortName(best) .. Color(TEXT.green, " can learn it")
            .. Color(LIGHT, o.required > 20 and ", needs the Blueprint" or "")
    end
    return Color(TEXT.soft, o.name), Color(LIGHT, ("Needs %d, "):format(o.required)) .. ShortName(best) .. Color(LIGHT, " has " .. skill)
end

local PlaceCells

local function CellTextHeight(name, note, width)
    return ns.UI.TextHeight(name, width) + 2 + ns.UI.TextHeight(note, width, "GameFontHighlightSmall")
end

local function InitRow(row, p)
    if not row.made then
        row.made = true
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("BOTTOMLEFT", row, "LEFT", 6, 1)
        row.best = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.best:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.cells = {}
        for i = 1, 3 do
            -- Each cell is its own frame, text included: a child frame draws over its parent's
            -- text, so a fill on the row hid it.
            local c = {}
            c.box = CreateFrame("Frame", nil, row)
            c.bg = CreateFrame("Frame", nil, row)
            c.bg:SetFrameLevel(c.box:GetFrameLevel() + 1)
            c.name = c.bg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            c.name:SetPoint("TOPLEFT", 6, -5)
            c.name:SetJustifyH("LEFT")
            c.note = c.bg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            c.note:SetJustifyH("LEFT")
            c.note:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -2)
            -- Anchored to the note, not given a height, so the game resizes it as the text wraps.
            c.box:SetPoint("TOPLEFT", c.bg, "TOPLEFT")
            c.box:SetPoint("TOPRIGHT", c.bg, "TOPRIGHT")
            c.box:SetPoint("BOTTOM", c.note, "BOTTOM", 0, -5)
            c.fill = ns.UI.RoundedBox(c.box, 6)
            c.fill:SetFill(ns.UI.C.picked)
            row.cells[i] = c
        end
        row.line = ns.UI.Divider(row)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
    end
    row.name:SetText(p.name or "")
    row.best:SetText(p.best and (ns.UI.CharName(p.best.char, p.best.key) .. " " .. (p.best.prof.skill or 0)) or "")
    local cellWidth = last.cellWidth or 140
    for i, c in ipairs(row.cells) do
        local known = false
        if not p.scanned then
            c.name:SetText(i == 1 and Color(TEXT.amber, "Not scanned yet") or "")
            c.note:SetText(i == 1 and Color(LIGHT, "Open the profession window once") or "")
        else
            local name, note
            name, note, known = CellText(p, p.slots[i])
            c.name:SetText(name)
            c.note:SetText(note)
        end
        c.height = math.ceil(CellTextHeight(c.name:GetText(), c.note:GetText(), cellWidth - 12) + 10)
        c.fill:SetShown(known and true or false)
    end
    PlaceCells(row)
end

function PlaceCells(row)
    local cellWidth = last.cellWidth or 140
    for i, c in ipairs(row.cells) do
        c.name:SetWidth(cellWidth - 12)
        c.note:SetWidth(cellWidth - 12)
        c.bg:ClearAllPoints()
        c.bg:SetPoint("LEFT", row, "LEFT", PROF_WIDTH + (i - 1) * (cellWidth + 10) - 6, 0)
        c.bg:SetSize(cellWidth, c.height or 34)
    end
end

local function RowHeight(p)
    local tallest = 34
    for i = 1, 3 do
        local name, note
        if p.scanned then name, note = CellText(p, p.slots[i]) else name, note = "Not scanned yet", "Open the profession window once" end
        tallest = math.max(tallest, CellTextHeight(name, note, last.cellWidth - 12))
    end
    return math.ceil(tallest + 12)
end

function Camp.Refresh(list, width, height, layoutOnly)
    last.list, last.width, last.height = list, width or last.width, height or last.height
    local wide = last.width >= WIDE
    local mainWidth = wide and (last.width - SIDE_WIDTH - GAP) or last.width
    last.cellWidth = math.floor((mainWidth - PROF_WIDTH - 20 - 14) / 3)

    local data = ns.UI.Data("camp", layoutOnly, function()
        local d = { professions = ns.CampData.Professions(list), fire = ns.CampData.Campfire(list) }
        d.blueprints = ns.CampData.Blueprints(d.professions, d.fire)
        return d
    end)
    local professions, fire = data.professions, data.fire
    local count, known = 0, 0
    for _, p in ipairs(professions) do
        for _, o in ipairs(p.objects) do
            count = count + 1
            if #o.knowers > 0 then known = known + 1 end
        end
    end
    panel.subtitle:SetText(count > 0 and ("%d of %d camp objects known on this account"):format(known, count) or "")

    local card = panel.fire
    card:SetWidth(mainWidth)
    local lines = {}
    if fire.current then
        lines[1] = Color(TEXT.body, fire.current.name) .. Color(LIGHT, (" holds %d objects. Each player at the fire adds one."):format(fire.current.holds))
    else
        lines[1] = Color(LIGHT, "Nobody on the account has Cooking: no campfire. A Cook learns the Basic Campfire with the profession.")
    end
    if fire.next and fire.next.learn then
        local cook = fire.cook
        lines[2] = Color(TEXT.body, fire.next.name) .. Color(LIGHT, (" holds %d: Blueprint, learn at Cooking %d, place at %d."):format(
            fire.next.holds, fire.next.learn, fire.next.place))
            .. (cook and (" " .. ShortName(cook) .. Color(LIGHT, " is at " .. (cook.prof.skill or 0) .. ".")) or "")
    end
    local holds = fire.current and fire.current.holds or 0
    local nextHolds = fire.next and fire.next.holds or holds
    for i, dot in ipairs(card.dots) do
        local lit, soon = i <= holds, i > holds and i <= nextHolds
        dot:SetSize(lit and 12 or 9, lit and 12 or 9)
        if lit then
            dot:SetVertexColor(unpack(ns.UI.Hex(TEXT.gold)))
        elseif soon then
            local r, g, b = unpack(ns.UI.C.border)
            dot:SetVertexColor(r, g, b, 0.9)
        else
            dot:SetVertexColor(unpack(ns.UI.C.unlit))
        end
    end
    card:Fit(card:SetLines(lines, mainWidth, 22), 10)
    local fireHeight = card:GetHeight()

    local bp = panel.blueprints
    local list2 = data.blueprints
    local bpLines = {}
    for i = 1, math.min(#list2, MAX_BLUEPRINTS) do
        local b = list2[i]
        local note = b.gap == 0 and Color(TEXT.green, " can learn it now") or Color(LIGHT, (", %s %d of %d"):format(b.prof.name or "", b.who.prof.skill or 0, b.required))
        if #bpLines > 0 then bpLines[#bpLines + 1] = " " end
        bpLines[#bpLines + 1] = Color(TEXT.body, "Blueprint: " .. b.name)
        bpLines[#bpLines + 1] = ShortName(b.who) .. note
    end
    if #bpLines == 0 then bpLines[1] = Color(LIGHT, "Nothing in reach yet.") end
    local bpWidth = wide and SIDE_WIDTH or mainWidth
    bp:SetWidth(bpWidth)
    bp:Fit(bp:SetLines(bpLines, bpWidth), 10)
    bp:ClearAllPoints()

    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, ns.UI.Below(PAGE.top, PAGE.titleHeight))
    local tableY = ns.UI.Below(ns.UI.Below(PAGE.top, PAGE.titleHeight), fireHeight)
    if wide then
        bp:SetPoint("TOPRIGHT", 0, PAGE.top)
    else
        bp:SetPoint("TOPLEFT", 0, tableY)
        tableY = ns.UI.Below(tableY, bp:GetHeight())
    end
    local labels = panel.labels
    labels.prof:SetPoint("TOPLEFT", 6, tableY)
    for i, key in ipairs({ "t1", "t2", "t3" }) do
        labels[key]:SetPoint("TOPLEFT", PROF_WIDTH + (i - 1) * (last.cellWidth + 10), tableY)
    end
    panel.labelLine:SetPoint("TOPLEFT", 0, tableY - 16)
    panel.labelLine:SetWidth(mainWidth)
    -- Filled before the list: the list's height leaves room for it.
    local nobody = {}
    local have = {}
    for _, p in ipairs(professions) do have[p.skillLine] = true end
    for line, name in pairs(ns.PROFESSION_NAMES) do
        if not have[line] then nobody[#nobody + 1] = name end
    end
    table.sort(nobody)
    panel.footer:SetWidth(mainWidth)
    panel.footer:SetText(#nobody > 0 and (table.concat(nobody, ", ") .. ": nobody on this account has them.") or "")
    panel.listFrame:ClearAllPoints()
    panel.listFrame:SetPoint("TOPLEFT", 0, tableY - 20)
    panel.listFrame:SetPoint("BOTTOMLEFT", 0, panel.footer:GetText() ~= "" and math.ceil(panel.footer:GetStringHeight() + 12) or 0)
    panel.listFrame:SetWidth(mainWidth)


    if layoutOnly and ns.UI.RedrawRows(panel.list, PlaceCells) then return end
    for _, p in ipairs(professions) do p.height = RowHeight(p) end
    panel.list.box:SetDataProvider(CreateDataProvider(professions), ScrollBoxConstants.RetainScrollPosition)
    panel.empty:SetShown(#professions == 0)
end

function Camp.Build(parent)
    local UI = ns.UI
    panel = UI.Page(parent, "Camp")
    panel.camp = true

    local Card = UI.TitledCard
    panel.fire = Card(panel, "Your campfire")
    panel.fire.dots = {}
    for i = 1, 10 do
        local dot = panel.fire:CreateTexture(nil, "OVERLAY")
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        dot:SetPoint("CENTER", panel.fire, "TOPLEFT", 22 + (i - 1) * 18, -44)
        UI.CircleMask(panel.fire, dot)
        panel.fire.dots[i] = dot
    end
    panel.blueprints = Card(panel, "Blueprints to find")

    panel.labels = {}
    for key, text in pairs({ prof = "Profession", t1 = "From skill 20", t2 = "Skill 140 and a Blueprint", t3 = "Skill 300 and a Blueprint" }) do
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetText(text)
        panel.labels[key] = label
    end
    panel.labelLine = UI.Divider(panel)

    panel.listFrame = CreateFrame("Frame", nil, panel)
    panel.list = UI.ScrollList(panel.listFrame, function(p) return p.height or 44 end, InitRow)
    UI.PlaceList(panel.list, 0)
    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    panel.footer:SetJustifyH("LEFT")
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("TOP", panel.listFrame, "TOP", 0, -40)
    panel.empty:SetText("No camp recipes scanned yet. Open a profession window once.")

    return panel
end

ns.UI.AddPage("camp", Camp)
