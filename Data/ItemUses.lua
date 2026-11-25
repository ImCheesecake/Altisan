-- ItemUses.lua: which recipes use an item as a material and which recipe an item teaches
-- (LibProfessionDB plus our own scans), and who on the account uses it.

local _, ns = ...

local Uses = {}
ns.ItemUses = Uses

local uses, teaches

local function Add(index, itemID, recipeID, prof, seen)
    local key = itemID .. ":" .. recipeID
    if seen[key] then return end
    seen[key] = true
    index[itemID] = index[itemID] or {}
    table.insert(index[itemID], { recipe = recipeID, prof = prof })
end

local function BuildIndex()
    uses, teaches = {}, {}
    local seen, seenTeach = {}, {}
    local db = ns.ProfessionDB()
    if db then
        local recipeItems = db:GetRecipeItems() or {}
        for _, prof in ipairs(db:GetProfessions()) do
            for recipeID, recipe in pairs(db:GetRecipes(prof) or {}) do
                if not db:IsHiddenRecipe(recipeID) then
                    for itemID in pairs(recipe.reagents or {}) do Add(uses, itemID, recipeID, prof, seen) end
                    local item = recipeItems[recipeID]
                    if item then Add(teaches, item, recipeID, prof, seenTeach) end
                end
            end
        end
    end
    for recipeID, recipe in pairs(ns.db.recipes) do
        if recipe.skillLine then
            for _, reagent in ipairs(recipe.reagents or {}) do Add(uses, reagent[1], recipeID, recipe.skillLine, seen) end
        end
    end
end

function Uses.IsCraftingItem(itemID)
    if not uses then BuildIndex() end
    return uses[itemID] ~= nil or teaches[itemID] ~= nil
end

function Uses.Teaches(itemID)
    if not uses then BuildIndex() end
    return teaches[itemID]
end

function Uses.Forget()
    uses, teaches = nil, nil
end

local function Gap(recipeID, prof) return select(2, ns.SkillGap(recipeID, prof.skillLine, prof.skill)) end

local function ClosestFirst(recipes, prof)
    table.sort(recipes, function(a, b)
        local ga, gb = Gap(a, prof), Gap(b, prof)
        if ga ~= gb then return ga < gb end
        return a < b
    end)
end

function Uses.Analyze(itemID, list)
    if not uses then BuildIndex() end
    local entries = uses[itemID]
    if not entries then return nil end
    local settings = ns.db.tooltips
    local byProf = {}
    for _, e in ipairs(entries) do
        if not ns.Ignore.Is(e.recipe) then
            byProf[e.prof] = byProf[e.prof] or {}
            table.insert(byProf[e.prof], e.recipe)
        end
    end

    local users, farther, has = {}, {}, {}
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local recipes = byProf[prof.skillLine]
            if recipes then
                has[prof.skillLine] = true
                local scan = ns.GetProfessionRecipes(entry.char, prof.skillLine)
                local known, later, past = {}, {}, {}
                for _, recipeID in ipairs(recipes) do
                    if scan and scan.known[recipeID] then
                        table.insert(known, recipeID)
                    elseif scan and scan.unknown[recipeID] then
                        local soon = settings.keepForLater and Gap(recipeID, prof) <= settings.reach
                        table.insert(soon and later or past, recipeID)
                    end
                end
                ClosestFirst(later, prof)
                ClosestFirst(past, prof)
                local use = { entry = entry, prof = prof, known = known, later = later, past = past }
                if #known + #later > 0 then
                    table.insert(users, use)
                elseif #past > 0 then
                    use.gap = Gap(past[1], prof)
                    table.insert(farther, use)
                end
            end
        end
    end
    table.sort(users, function(a, b) return #a.known + #a.later > #b.known + #b.later end)
    table.sort(farther, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        return a.entry.key < b.entry.key
    end)

    local nobody = {}
    for line in pairs(byProf) do
        if not has[line] then nobody[#nobody + 1] = ns.ProfessionName(line) end
    end
    table.sort(nobody)
    return users, nobody, byProf, farther
end
