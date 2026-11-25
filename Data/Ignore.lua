-- Ignore.lua: recipes ignored on every character. They leave Next up, Coverage's counts and the
-- item tooltips' verdicts; a tracked recipe can't be ignored, and an ignored one can't be tracked.

local _, ns = ...

local Ignore = {}
ns.Ignore = Ignore

function Ignore.Is(recipeID) return ns.db.ignored[recipeID] == true end

function Ignore.Set(recipeID, on)
    ns.db.ignored[recipeID] = on and true or nil
    ns.RefreshWindow()
end

function Ignore.AddMenuLine(root, recipeID)
    if Ignore.Is(recipeID) then
        root:CreateButton("Stop ignoring", function() Ignore.Set(recipeID, false) end)
    elseif not ns.Tracking.IsTracked(recipeID) then
        root:CreateDivider()
        root:CreateButton("Ignore on every character", function() Ignore.Set(recipeID, true) end)
    end
end
