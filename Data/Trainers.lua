-- Trainers.lua: what profession trainers ask, read from their window when a player talks to one and
-- saved for the account (trainerSkill[recipeID] = skill). LibProfessionDB's are Vanilla's on Forever.

local _, ns = ...

local Trainers = {}
ns.Trainers = Trainers

local function LineByName(name)
    local db = ns.ProfessionDB and ns.ProfessionDB()
    for _, line in ipairs(db and db:GetProfessions() or {}) do
        if ns.ProfessionName(line) == name then return line end
    end
end

local function RecipesByName(line)
    local out, db = {}, ns.ProfessionDB and ns.ProfessionDB()
    local function AddRecipe(recipeID)
        local name = ns.RecipeName(recipeID, line)
        out[name] = out[name] or {}
        for _, id in ipairs(out[name]) do if id == recipeID then return end end
        table.insert(out[name], recipeID)
    end
    for recipeID in pairs(db and db:GetRecipes(line) or {}) do AddRecipe(recipeID) end
    for recipeID, r in pairs(ns.db.recipes) do if r.skillLine == line then AddRecipe(recipeID) end end
    return out
end

local switchedOn = {}

local function PutFiltersBack()
    for _, filter in ipairs(switchedOn) do pcall(SetTrainerServiceTypeFilter, filter, false) end
    switchedOn = {}
end
Trainers.PutFiltersBack = PutFiltersBack

local HIDDEN_BY_DEFAULT = { "unavailable", "used" }
local reading = false
function Trainers.EachService(each, allServices)
    if reading or not (GetNumTrainerServices and GetTrainerServiceSkillReq) then return true end
    if IsTradeskillTrainer and not IsTradeskillTrainer() then return true end
    reading = true
    local ok, err = pcall(function()
        for _, filter in ipairs(allServices and GetTrainerServiceTypeFilter and HIDDEN_BY_DEFAULT or {}) do
            if not GetTrainerServiceTypeFilter(filter) then
                switchedOn[#switchedOn + 1] = filter
                SetTrainerServiceTypeFilter(filter, true)
            end
        end
        for i = 1, GetNumTrainerServices() do
            local name = GetTrainerServiceInfo(i)
            local skill, rank = GetTrainerServiceSkillReq(i)
            each(name, skill, rank)
        end
    end)
    if not ok or not allServices then PutFiltersBack() end
    reading = false
    return ok, err
end

-- allServices only on TRAINER_SHOW: the server lists a filter's services only with the next
-- TRAINER_UPDATE, so that read restores the filters; it fires one more, read without switching.
function Trainers.Read(allServices)
    local ranks, byLine = {}, {}
    local ok, err = Trainers.EachService(function(name, skill, rank)
        local line = name and rank and skill and LineByName(skill)
        if not line then return end
        byLine[line] = byLine[line] or RecipesByName(line)
        for _, recipeID in ipairs(byLine[line][name] or {}) do
            -- A name two services share with different skills is left out: either could be this one.
            local seen = ranks[recipeID]
            ranks[recipeID] = (seen == nil or seen == rank) and rank or false
        end
    end, allServices)
    if not ok then
        geterrorhandler()(err)
        return 0
    end
    local changed = 0
    for recipeID, rank in pairs(ranks) do
        if rank and ns.db.trainerSkill[recipeID] ~= rank then
            ns.db.trainerSkill[recipeID] = rank
            changed = changed + 1
        end
    end
    if changed > 0 then
        ns.ForgetSourceKeys()
        ns.RefreshWindow()
    end
    return changed
end
