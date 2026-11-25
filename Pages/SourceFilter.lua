-- SourceFilter.lua: the Source menu in a character's recipe list: one where-to-learn group, the
-- same ones as Coverage's filter (ns.SOURCE_KINDS). Nothing is saved.

local _, ns = ...

local Source = {}
ns.SourceFilter = Source

local WIDTH = 210
local menu

local function KindLabel(key)
    for _, kind in ipairs(ns.SOURCE_KINDS) do
        if kind.key == key then return kind.label end
    end
end

function Source.Matches(recipeID)
    local pick = ns.view.source
    return not pick or ns.RecipeSourceKeys(recipeID)[pick] == true
end

function Source.NewTally()
    local tally = { all = 0 }
    function tally:Count(recipeID)
        self.all = self.all + 1
        for key in pairs(ns.RecipeSourceKeys(recipeID)) do self[key] = (self[key] or 0) + 1 end
    end
    return tally
end

function Source.RefreshButton()
    local pick = ns.view.source
    menu.button:SetState(pick and ("Source: " .. KindLabel(pick)) or "Source", pick ~= nil, menu.popup:IsShown())
end

function Source.Update(tally)
    menu.button:SetShown(tally.all > 0)
    if tally.all == 0 then menu.popup:Hide() end
    if ns.view.source and not tally[ns.view.source] then
        ns.view.source = nil
        return true
    end
    local options = { { key = "all", label = "All", count = tally.all } }
    for _, kind in ipairs(ns.SOURCE_KINDS) do
        if tally[kind.key] then options[#options + 1] = { key = kind.key, label = kind.label, count = tally[kind.key] } end
    end
    menu:Fill(options, ns.view.source or "all")
    Source.RefreshButton()
    return false
end

function Source.Hide()
    menu.button:Hide()
    menu.popup:Hide()
end

function Source.Build(parent)
    menu = ns.Dropdown.RadioMenu(parent, WIDTH, function(key)
        ns.view.source = key ~= "all" and key or nil
        ns.RecipeView.RefreshList()
    end, function() Source.RefreshButton() end)
    Source.RefreshButton()
    return menu.button
end
