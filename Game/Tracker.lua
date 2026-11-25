-- Tracker.lua: the Keep in stock section in the shared quest tracker column: herbs and ore kept in
-- stock, still short and not bought, per kind. A click opens Gathering with it picked.

local _, ns = ...
local UI = ns.UI
local Gather = ns.Gathering

local section, groups = nil, {}
local Section = {
    headerText = "Keep in stock",
    blockTemplate = "ObjectiveTrackerAnimBlockTemplate",
    lineTemplate = "ObjectiveTrackerAnimLineTemplate",
}

-- The shared column can't take a section out, so an empty one means off, and a section's own events
-- never fire there: the bag and login handlers call this instead.
function ns.RedrawTracker()
    groups = Gather.InTracker() and Gather.TrackerRows(ns.VisibleCharacters()) or {}
    if not section and Gather.InTracker() and ns.TrackerHost then
        section = CreateFrame("Frame", nil, UIParent, "ObjectiveTrackerModuleTemplate")
        Mixin(section, Section)
        -- The template's OnLoad runs before our fields are mixed in.
        section:SetHeader(Section.headerText)
        section.uiOrder = 1
        ns.TrackerHost.Attach(section)
    end
    if section then section:MarkDirty() end
end
ns.OnRefresh(function(layoutOnly) if not layoutOnly then ns.RedrawTracker() end end)

-- Blizzard's tracker lines only follow links.
local function OnLineClick(line, button)
    if button ~= "LeftButton" or not line.itemID then return end
    ns.ShowSection("gathering", line.itemID)
    ns.ShowWindow()
end

function Section:LayoutContents()
    for _, group in ipairs(groups) do
        if not self:AddGroup(group) then return end
    end
end

function Section:AddGroup(group)
    local block = self:GetBlock(group.kind)
    block:SetHeader(Gather.TITLE[group.kind])
    for _, row in ipairs(group.rows) do
        local text = PROFESSIONS_TRACKER_REAGENT_FORMAT:format(
            PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(row.have, row.want), UI.ItemLabel(row.itemID, ns.RedrawTracker))
        local line = block:AddObjective(row.itemID, text)
        line.itemID = row.itemID
        line:EnableMouse(true)
        line:SetScript("OnMouseUp", OnLineClick)
    end
    return self:LayoutBlock(block)
end
