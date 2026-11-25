-- Overview.lua: the Overview page. A summary strip, Next up, then one row per character with
-- their professions; click a row to open that character's recipes.

local _, ns = ...

local View = {}
ns.OverviewView = View

local panel
local cols

local SUMMARY_HEIGHT = 58
local PAGE = ns.UI.PAGE
local LABELS_GAP = 6
local LIST_GAP = 24
local ROW_HEIGHT = 50

local CRAFTING, CRAFTING_COUNT = ns.CRAFTING, ns.CRAFTING_COUNT

local LEGACY_REACH = 20

local NAME_X = 44
local NAME_WIDTH = 150
local CELL_MIN, CELL_MAX = 100, 190
local SECONDARY_WIDTH = 110
local GAP = 20

local function ColumnsFor(width)
    local spare = width - NAME_X - NAME_WIDTH - GAP
    local secondary = spare - SECONDARY_WIDTH - GAP >= 2 * CELL_MIN + GAP
    if secondary then spare = spare - SECONDARY_WIDTH - GAP end

    local cell = math.max(CELL_MIN, math.min(CELL_MAX, math.floor((spare - GAP) / 2)))
    local nameWidth = NAME_WIDTH + math.max(0, spare - (2 * cell + GAP)) / (secondary and 2 or 1)
    nameWidth = math.floor(math.min(nameWidth, 230))

    local cols = { name = NAME_X, nameWidth = nameWidth, cell = cell, secondary = secondary }
    cols.prof1 = NAME_X + nameWidth + GAP
    cols.prof2 = cols.prof1 + cell + GAP
    cols.secondaryX = cols.prof2 + cell + GAP
    return cols
end

local InitRow, RowHeight

function View.Build(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    panel.list = ns.UI.ScrollList(panel, function(data) return data.height end, function(row, data) InitRow(row, data) end)

    panel.labels = {}
    for key, text in pairs({ name = "Character", prof1 = "Professions", secondary = "Secondary skills" }) do
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetText(text)
        panel.labels[key] = label
    end

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetText("Log in on a character to add it here.")

    local summary = ns.UI.TileStrip(panel, 3, { height = SUMMARY_HEIGHT })
    summary:SetPoint("TOPLEFT", 0, PAGE.top)
    summary:SetPoint("TOPRIGHT", 0, PAGE.top)
    panel.summary = summary

    panel.nextUp = ns.NextUp.Build(panel)

    return panel
end

-- Legacy points are per account: two Tailors at 140 are one point.
local function Summary(list)
    local recipes = 0
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            if CRAFTING[prof.skillLine] then
                local scan = ns.GetProfessionRecipes(entry.char, prof.skillLine)
                if scan then recipes = recipes + (ns.CountRecipes(scan)) end
            end
        end
    end
    local legacy, craftCount = 0, 0
    for line, best in pairs(ns.Legacy.BestPerProfession(list)) do
        craftCount = craftCount + 1
        local _, toGo = ns.Legacy.Next(line, best.prof.skill)
        if toGo and toGo <= LEGACY_REACH then legacy = legacy + 1 end
    end
    return recipes, legacy, craftCount
end


local function RefreshSummary(list, width, layoutOnly)
    local recipes, legacy, crafts = ns.UI.Data("overview.summary", layoutOnly, function() return Summary(list) end)
    local content = {
        { "Recipes known", tostring(recipes), "in " .. ns.UI.Count(crafts, "profession", "professions") },
        { "Legacy points in reach", tostring(legacy), "within " .. LEGACY_REACH .. " skill" },
        { "Crafting professions", crafts .. " of " .. CRAFTING_COUNT, "on this account" },
    }
    for i, tile in ipairs(content) do panel.summary:SetTile(i, tile[1], tile[2], tile[3]) end
    panel.summary:Layout(width)
end

local function CreateProfessionCell(row)
    local cell = {}

    cell.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.label:SetJustifyH("LEFT")

    cell.holder, cell.bar = ns.UI.SkillBar(row, CELL_MIN)
    cell.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cell.note:SetJustifyH("LEFT")
    return cell
end

local function PlaceProfessionCell(cell, row, x, width)
    cell.label:SetPoint("TOPLEFT", row, "TOPLEFT", x, -8)
    cell.holder:SetPoint("TOPLEFT", row, "TOPLEFT", x, -23)
    cell.holder:SetWidth(width)
    cell.label:SetWidth(width - 60)
    cell.value:SetPoint("TOPRIGHT", row, "TOPLEFT", x + width, -8)
    cell.note:SetPoint("TOPLEFT", row, "TOPLEFT", x, -31)
    cell.note:SetWidth(width)
end

local SecondaryText
local function MakeRow(row)
    local UI = ns.UI
    row.made = true
    row:SetScript("OnClick", function(self) ns.ShowCharacter(self.key) end)
    row:SetScript("OnEnter", function(self)
        if not self.char or (cols and cols.secondary) then return end
        UI.RowTooltip(self)
        GameTooltip:AddLine((UI.CharacterName(self.key, self.char)))
        ns.UI.TipLine(GameTooltip, "Secondary skills", "gold")
        for line in (SecondaryText(self.char) .. "\n"):gmatch("(.-)\n") do
            if line ~= "" then ns.UI.TipLine(GameTooltip, line) end
        end
        GameTooltip:AddLine(" ")
        ns.UI.TipLine(GameTooltip, "Click to open their recipes", "light")
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.shade = row:CreateTexture(nil, "BACKGROUND")
    row.shade:SetAllPoints()
    row.shade:SetColorTexture(unpack(UI.C.zebra))

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(unpack(UI.C.hover))

    row.portrait = UI.Portrait(row, 34)
    row.portrait:SetPoint("LEFT", 4, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", NAME_X, -10)
    row.name:SetJustifyH("LEFT")

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.info:SetJustifyH("LEFT")

    row.prof1 = CreateProfessionCell(row)
    row.prof2 = CreateProfessionCell(row)

    row.secondary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.secondary:SetJustifyH("LEFT")
    row.secondary:SetSpacing(2)
end

local function PlaceRow(row, cols)
    row.name:SetWidth(cols.nameWidth)
    row.info:SetWidth(cols.nameWidth)
    PlaceProfessionCell(row.prof1, row, cols.prof1, cols.cell)
    PlaceProfessionCell(row.prof2, row, cols.prof2, cols.cell)
    row.secondary:SetPoint("TOPLEFT", row, "TOPLEFT", cols.secondaryX, -7)
    row.secondary:SetShown(cols.secondary)
end

local function RecipeNote(char, prof)
    local scan = ns.GetProfessionRecipes(char, prof.skillLine)
    if ns.GATHERING[prof.skillLine] then
        local learned = scan and ns.CountRecipes(scan) or 0
        if learned == 0 then return "" end
        return ns.UI.Count(learned, "camping recipe", "camping recipes")
    end
    if not scan then return "Not scanned yet" end
    local learned = ns.CountRecipes(scan)
    return ns.UI.Count(learned, "recipe known", "recipes known")
end

local function FillProfessionCell(cell, char, prof)
    local shown = prof ~= nil
    cell.holder:SetShown(shown)
    cell.note:SetShown(shown)
    cell.value:SetShown(shown)

    if not shown then
        cell.label:SetText(ns.UI.ColorText(ns.UI.TEXT.muted, "Free slot"))
        return
    end

    cell.label:SetText(prof.name)
    cell.bar:SetMinMaxValues(0, math.max(prof.maxSkill, 1))
    cell.bar:SetValue(prof.skill)
    cell.value:SetText(("%d / %d"):format(prof.skill, prof.maxSkill))
    cell.note:SetText(RecipeNote(char, prof))
end

function SecondaryText(char)
    local lines = {}
    for _, prof in ipairs(char.professions or {}) do
        if prof.kind == "secondary" then
            table.insert(lines, prof.name .. " " .. ns.UI.Soft(("%d/%d"):format(prof.skill, prof.maxSkill)))
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or ns.UI.ColorText(ns.UI.TEXT.muted, "None")
end

local function InfoText(char, showFaction)
    local faction = showFaction and char.faction and (", " .. ns.UI.FactionText(char.faction)) or ""
    return ("Level %d %s"):format(char.level or 0, char.className or "") .. faction
end

function RowHeight(data)
    local name = ns.UI.TextHeight((ns.UI.CharacterName(data.key, data.char)), cols.nameWidth)
    local info = ns.UI.TextHeight(InfoText(data.char, data.mixed), cols.nameWidth, "GameFontDisableSmall")
    return math.max(ROW_HEIGHT, math.ceil(10 + name + 4 + info + 10))
end

local function FillRow(row, key, char, showFaction)
    row.key, row.char = key, char
    row.name:SetText((ns.UI.CharacterName(key, char)))

    row.portrait:SetCharacter(char)

    row.info:SetText(InfoText(char, showFaction))

    local primaries = {}
    for _, prof in ipairs(char.professions or {}) do
        if prof.kind == "primary" then table.insert(primaries, prof) end
    end
    FillProfessionCell(row.prof1, char, primaries[1])
    FillProfessionCell(row.prof2, char, primaries[2])

    row.secondary:SetText(SecondaryText(char))
end

function InitRow(row, data)
    if not row.made then MakeRow(row) end
    if row.shade then row.shade:SetShown(data.index % 2 == 0) end
    PlaceRow(row, cols)
    row:SetHeight(data.height)
    FillRow(row, data.key, data.char, data.mixed)
end

function View.Refresh(list, width, height, layoutOnly, mixed)
    RefreshSummary(list, width, layoutOnly)
    panel.summary:SetShown(#list > 0)
    cols = ColumnsFor(width)

    local cardsY = ns.UI.Below(PAGE.top, panel.summary.height)
    panel.nextUp:ClearAllPoints()
    panel.nextUp:SetPoint("TOPLEFT", 0, cardsY)
    panel.nextUp:SetWidth(width)
    local tableRoom = LIST_GAP + 2 * ROW_HEIGHT
    local maxCards = (height or 400) + cardsY - PAGE.gap - tableRoom
    local cardsHeight = #list > 0 and ns.NextUp.Refresh(list, width, layoutOnly, maxCards) or 0
    panel.nextUp:SetShown(#list > 0)
    local tableY = cardsHeight > 0 and ns.UI.Below(cardsY, cardsHeight) or cardsY
    local labelsY = tableY - LABELS_GAP
    panel.labels.name:SetPoint("TOPLEFT", cols.name, labelsY)
    panel.labels.prof1:SetPoint("TOPLEFT", cols.prof1, labelsY)
    panel.labels.secondary:SetPoint("TOPLEFT", cols.secondaryX, labelsY)
    panel.labels.secondary:SetShown(cols.secondary)

    ns.UI.PlaceList(panel.list, tableY - LIST_GAP)
    if layoutOnly and panel.list.box:HasDataProvider() then
        panel.list.box:ForEachFrame(function(row) PlaceRow(row, cols) end)
    else
        local items = {}
        for i, entry in ipairs(list) do
            items[i] = { index = i, key = entry.key, char = entry.char, mixed = mixed }
            items[i].height = RowHeight(items[i])
        end
        panel.list.box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
    end
    panel.empty:SetShown(#list == 0)
end

ns.UI.AddPage("overview", View)
