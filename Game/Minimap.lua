-- Minimap.lua: the minimap button (LibDBIcon) and the entry in the minimap's addon menu.

local _, ns = ...

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

local NAME = "Altisan"
local launcher

local function OnClick(mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenSettings()
    else
        ns.ToggleWindow()
    end
end

local function AddTooltipLines(tooltip)
    tooltip:AddLine(ns.TITLE)
    ns.UI.TipLine(tooltip, "Left-click: open or close")
    ns.UI.TipLine(tooltip, "Right-click: settings")
end

function ns.CreateMinimapButton()
    if launcher then return end
    local saved = ns.db.minimap
    if saved.angle and not saved.minimapPos then saved.minimapPos = saved.angle end
    saved.angle, saved.shape = nil, nil

    launcher = LDB:NewDataObject(NAME, {
        type = "launcher",
        label = ns.TITLE,
        text = ns.TITLE,
        icon = ns.ICON,
        OnClick = function(_, mouseButton) OnClick(mouseButton) end,
        OnTooltipShow = AddTooltipLines,
    })
    DBIcon:Register(NAME, launcher, saved)
end

function ns.SetMinimapShown(shown)
    ns.db.minimap.hide = not shown
    if shown then DBIcon:Show(NAME) else DBIcon:Hide(NAME) end
end

-- The addon menu calls these by the names in the .toc, so they're globals.
function Altisan_OnCompartmentClick(_, mouseButton)
    OnClick(mouseButton)
end

function Altisan_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    AddTooltipLines(GameTooltip)
    GameTooltip:Show()
end

function Altisan_OnCompartmentLeave()
    GameTooltip:Hide()
end
