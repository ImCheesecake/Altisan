-- Sources.lua: where to learn a recipe and which recipes can't be learned on Forever (LibProfessionDB).
-- Its Forever sources are partly borrowed from Vanilla (IsBorrowed); its NPC names are English only.

local _, ns = ...

-- Season of Discovery: in Forever's client files, but not learnable.
local SOD_CATEGORIES = { [2592] = true, [2593] = true, [2594] = true, [2595] = true,
                         [2596] = true, [2597] = true, [2598] = true }

local function Library()
    local db = LibStub and LibStub("LibProfessionDB-1.0", true)
    if db and db:IsReady() then return db end
    return false
end
ns.ProfessionDB = Library

function ns.RecipeItem(recipeID)
    local db = Library()
    if not db then return nil, false end
    return db:GetRecipeItem(recipeID)
end

-- The library keeps a rank as an entry of the profession whose recipe item it marks as a rank book.
local rankBooks = {}
function ns.RankBook(skillLine)
    local db = Library()
    if not db then return nil end
    if rankBooks[skillLine] == nil then
        rankBooks[skillLine] = false
        for recipeID in pairs(db:GetRecipes(skillLine) or {}) do
            local itemID, isRankBook = ns.RecipeItem(recipeID)
            if isRankBook then rankBooks[skillLine] = itemID end
        end
    end
    return rankBooks[skillLine] or nil
end

function ns.RecipeName(recipeID, skillLine)
    local saved = ns.db.recipes[recipeID]
    if saved and saved.name then return saved.name end
    local db = Library()
    for _, line in ipairs(db and (skillLine and { skillLine } or db:GetProfessions()) or {}) do
        local name = db:GetName(line, recipeID)
        if name then return name end
    end
    return "Recipe " .. recipeID
end

local fromQuestie = {}
local function QuestieSources(recipeID)
    local row = ns.QuestieForever and ns.QuestieForever.sources[recipeID]
    if not row then return nil end
    if not fromQuestie[recipeID] then
        local sources = {}
        for _, kind in ipairs({ "vendor", "drop", "quest" }) do
            if row[kind] then
                local list = {}
                for _, id in ipairs(row[kind]) do
                    local npc = kind ~= "quest" and ns.Places.NPC(id)
                    list[#list + 1] = { id = id, name = npc and npc.name or nil }
                end
                sources[kind] = list
            end
        end
        fromQuestie[recipeID] = sources
    end
    return fromQuestie[recipeID]
end

-- The library has the Alliance quartermasters only; QuestieDB has the Horde ones too.
local function AddQuestie(sources, recipeID)
    for kind, extra in pairs(QuestieSources(recipeID) or {}) do
        local list = sources[kind]
        if not list then
            list = {}
            for i, entry in ipairs(extra) do list[i] = entry end
            sources[kind] = list
        else
            local have = {}
            for _, entry in ipairs(list) do have[entry.id] = true end
            for _, entry in ipairs(extra) do
                if not have[entry.id] then
                    list[#list + 1] = entry
                    list.total = list.total and list.total + 1
                end
            end
        end
    end
end

local function TrainerListed(recipeID)
    return ns.db ~= nil and ns.db.trainerSkill ~= nil and ns.db.trainerSkill[recipeID] ~= nil
end

-- The library's trainer lists come from later expansions: a recipe it lists with vendors too is
-- only a vendor's on Forever (Spotted Yellowtail is Gikkix's), unless a trainer here listed it.
function ns.RecipeSources(recipeID)
    local db = Library()
    local sources = db and db:GetRecipeSources(recipeID)
    if not sources then return QuestieSources(recipeID) end
    AddQuestie(sources, recipeID)
    if sources.trainer and sources.vendor and not TrainerListed(recipeID) then sources.trainer = nil end
    return sources
end

function ns.IsHiddenRecipe(recipeID, categoryID)
    if categoryID and SOD_CATEGORIES[categoryID] then return true end
    local db = Library()
    return db and db:IsHiddenRecipe(recipeID) or false
end

-- The Faction Banner, the only recipe pair (one per faction) in the client's data. By ID: in some
-- languages different recipes share a name.
local FACTION_TWIN = { [1229504] = 1263425, [1263425] = 1229504 }
function ns.FactionTwin(recipeID) return FACTION_TWIN[recipeID] end

-- Recipes the library doesn't know stay: it's built from an older build.
function ns.LearnableFilter(scan)
    return function(recipeID)
        if scan.known[recipeID] then return true end
        local twin = FACTION_TWIN[recipeID]
        if twin and scan.known[twin] then return false end
        local recipe = ns.db.recipes[recipeID]
        return not ns.IsHiddenRecipe(recipeID, recipe and recipe.categoryID)
    end
end

-- A drop before a container: nearly every lockbox recipe also drops from many kinds of creature.
local KINDS = {
    { key = "trainer", label = "Trainer" },
    { key = "vendor", label = "Sold by" },
    { key = "quest", label = "Quest" },
    { key = "drop", label = "Drops from" },
    { key = "container", label = "Found in" },
}
local MAX_NAMES = 3

-- The library names every ID from its NPC names, but a quest's ID is a quest and a container's an
-- item (4632 is Ornate Bronze Lockbox, not the NPC Kolkar Centaur): the game names those.
local function EntryName(kind, entry)
    if kind == "quest" then return ns.Places.QuestTitle(entry.id) end
    if kind == "container" then return ns.UI.ItemName(entry.id, ns.UI.RedrawWindow) end
    return entry.name
end

-- The library caps its lists; list.total is the real count.
local function Names(list, kind)
    local names = {}
    for _, entry in ipairs(list) do
        if #names >= MAX_NAMES then break end
        names[#names + 1] = EntryName(kind, entry)
    end
    local more = (list.total or #list) - #names
    local text = table.concat(names, ", ")
    if more > 0 then
        text = text == "" and ns.UI.Count(more, "source", "sources")
                          or (text .. (" and %d more"):format(more))
    end
    return text
end

function ns.RequiredSkill(recipeID, skillLine)
    local trainer = ns.db and ns.db.trainerSkill and ns.db.trainerSkill[recipeID]
    if trainer then return trainer, false end
    local db = Library()
    local recipe = db and skillLine and db:GetRecipe(skillLine, recipeID)
    local skill = recipe and recipe.requiredSkill
    if not skill then return nil end
    return skill, db:IsBorrowed(recipeID, "requiredSkill")
end

function ns.SkillUpLevels(skillLine, recipeID)
    local db = Library()
    local t = db and skillLine and db:GetDifficulty(skillLine, recipeID)
    if not (t and t[1] and t[2] and t[3] and t[4]) then return nil end
    return t
end

function ns.WouldBeDifficulty(recipeID, skillLine, skill)
    local t = skill and ns.SkillUpLevels(skillLine, recipeID)
    if not t then return nil end
    if skill < t[2] then return 0 end
    if skill < t[3] then return 1 end
    if skill < t[4] then return 2 end
    return 3
end

local function NoSourceWord(db, recipeID)
    if db:IsAutoTaughtRecipe(recipeID) then return "Taught" end
    if TrainerListed(recipeID) then return "Trainer" end
    return nil
end

local function LibraryAndSources(recipeID)
    local db = Library()
    if db then return db, ns.RecipeSources(recipeID) end
end

local SHORT_KINDS = { trainer = "Trainer", vendor = "Vendor", quest = "Quest", container = "Container", drop = "Drop" }
function ns.RecipeSourceKind(recipeID)
    local db, sources = LibraryAndSources(recipeID)
    if not db then return nil end
    if sources then
        for _, kind in ipairs(KINDS) do
            if sources[kind.key] then return SHORT_KINDS[kind.key] end
        end
    end
    return NoSourceWord(db, recipeID)
end

ns.FAVOR_NAME = "Merchant's Favor"
ns.SOURCE_KINDS = {
    { key = "trainer", label = "Trainer" }, { key = "vendor", label = "Vendor" }, { key = "favor", label = ns.FAVOR_NAME },
    { key = "quest", label = "Quest" }, { key = "drop", label = "Drop" }, { key = "dungeon", label = "Dungeon or raid" },
    { key = "unknown", label = "Unknown" },
}

local sourceKeys = {}
function ns.RecipeSourceKeys(recipeID)
    if sourceKeys[recipeID] then return sourceKeys[recipeID] end
    local db = Library()
    local sources = ns.RecipeSources(recipeID)
    local _, _, _, mine = ns.Places.ForRecipe(recipeID)
    local keys, npcKinds, any = {}, { trainer = true, vendor = true, quest = true }, false
    for kind in pairs(sources or {}) do
        if npcKinds[kind] and mine[kind] then any = true end
    end
    for kind in pairs(sources or {}) do
        if not npcKinds[kind] or mine[kind] or not any then keys[kind == "container" and "drop" or kind] = true end
    end
    if next(keys) == nil then
        keys[db and (db:IsAutoTaughtRecipe(recipeID) or TrainerListed(recipeID)) and "trainer" or "unknown"] = true
    end
    if keys.vendor and ns.Favor.IsRecipe(recipeID) then keys.vendor, keys.favor = nil, true end
    if keys.drop and ns.Places.DropInstances(recipeID) then keys.drop, keys.dungeon = sources.container ~= nil or nil, true end
    if db then sourceKeys[recipeID] = keys end
    return keys
end

function ns.ForgetSourceKeys() wipe(sourceKeys) end

local function InstancesText(areas)
    if #areas > 1 then return #areas .. " dungeons" end
    local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areas[1])
    return name and name ~= "" and name or "Dungeon"
end

local PLURAL = { vendor = "vendors", quest = "quests", container = "containers" }
local WORLD_DROP = 12   -- Named mobs' drop lists stop at 9 kinds of creature; more is a world drop.
function ns.RecipeWhereShort(recipeID)
    local db, sources = LibraryAndSources(recipeID)
    if not db then return nil end
    if sources then
        for _, kind in ipairs(KINDS) do
            local list = sources[kind.key]
            if list then
                local total = list.total or #list
                if kind.key == "vendor" and ns.Favor.IsRecipe(recipeID) then return ns.Favor.NAME end
                local instances = kind.key == "drop" and ns.Places.DropInstances(recipeID)
                if instances then return InstancesText(instances) end
                if kind.key == "drop" then return total >= WORLD_DROP and "World drop" or "Drop" end
                if total > 1 and PLURAL[kind.key] then return total .. " " .. PLURAL[kind.key] end
                return SHORT_KINDS[kind.key]
            end
        end
    end
    return NoSourceWord(db, recipeID)
end

local SUMMARY = {
    trainer = { word = "Trainer", one = "trainer teaches it", many = "trainers teach it", heading = "Taught by" },
    vendor = { word = "Vendor", one = "vendor sells it", many = "vendors sell it", heading = "Sold by" },
    quest = { word = "Quest", one = "quest", many = "quests", from = true, heading = "Quests" },
    container = { word = "Container", one = "container", many = "containers", foundIn = true, heading = "Found in", inline = true },
    drop = { word = "Drop", one = "kind of creature", many = "kinds of creature", from = true, heading = "Drops from", inline = true },
}
local MAX_LISTED = 8

-- ns.UI loads after this file.
local function Light(text) return ns.UI.Light(text) end

function ns.SkillGap(recipeID, skillLine, skill)
    local required = ns.RequiredSkill(recipeID, skillLine)
    if not required then return nil, math.huge end
    return required, math.max(0, required - (skill or 0))
end

local function NoSourceLine(db, recipeID)
    if db:IsAutoTaughtRecipe(recipeID) then return "Learned with the profession" end
    if TrainerListed(recipeID) then return SUMMARY.trainer.word .. ": " .. Light("a trainer teaches it") end
    local itemID = ns.RecipeItem(recipeID)
    return itemID and ns.UI.ItemName(itemID, ns.UI.RedrawWindow)
end

function ns.RecipeWhere(recipeID, withNames, skipNPCs)
    local db, sources = LibraryAndSources(recipeID)
    if not db then return nil end
    local lines, hasNames = ns.Favor.Lines(recipeID) or {}, false
    if sources then
        for _, kind in ipairs(KINDS) do
            local list = sources[kind.key]
            local words = SUMMARY[kind.key]
            if skipNPCs and (kind.key == "trainer" or kind.key == "vendor" or kind.key == "quest") then list = nil end
            if list and words then
                local named = {}
                for _, entry in ipairs(list) do
                    named[#named + 1] = EntryName(kind.key, entry)
                end
                local total = list.total or #list
                if #named > 0 and total > 1 then hasNames = true end
                if withNames and #named > 0 then
                    lines[#lines + 1] = ns.UI.ColorText(ns.UI.TEXT.gold, words.heading)
                    if words.inline then
                        lines[#lines + 1] = Names(list, kind.key):gsub("( and %d+ more)$", Light("%1"))
                    else
                        for i = 1, math.min(#named, MAX_LISTED) do lines[#lines + 1] = named[i] end
                        local more = total - math.min(#named, MAX_LISTED)
                        if more > 0 then lines[#lines + 1] = Light(("and %d more"):format(more)) end
                    end
                elseif total == 1 and named[1] then
                    lines[#lines + 1] = words.word .. ": " .. Light(named[1])
                else
                    local what = ns.UI.Plural(total, words.one, words.many)
                    if words.from then what = "from " .. total .. " " .. what
                    elseif words.foundIn then what = "found in " .. total .. " " .. what
                    else what = total .. " " .. what end
                    lines[#lines + 1] = words.word .. ": " .. Light(what)
                end
            end
        end
    else
        lines[#lines + 1] = NoSourceLine(db, recipeID)
    end
    if #lines == 0 then return nil end
    return lines, hasNames, sources and db:IsBorrowed(recipeID, "sources") or nil
end

function ns.RecipeRequirement(recipeID, skillLine, professionName, long)
    local skill, borrowed = ns.RequiredSkill(recipeID, skillLine)
    if not skill or skill <= 1 then return nil end
    local text = ("Requires %s %d"):format(professionName or "skill", skill)
    if borrowed then
        local from = type(borrowed) == "string" and borrowed or "Vanilla"
        text = text .. Light((long and " (%s data, not confirmed on Forever)" or " (%s data)"):format(from))
    end
    return text
end

function ns.RecipeSourceLines(recipeID, skillLine)
    local db, sources = LibraryAndSources(recipeID)
    if not db then return nil end
    local lines = {}
    if sources then
        for _, kind in ipairs(KINDS) do
            local list = sources[kind.key]
            if list then
                local names = Names(list, kind.key)
                lines[#lines + 1] = names ~= "" and (kind.label .. ": " .. names) or kind.label
            end
        end
    else
        lines[#lines + 1] = NoSourceLine(db, recipeID)
    end

    local skill, borrowedSkill = ns.RequiredSkill(recipeID, skillLine)
    if skill and skill > 1 then
        lines[#lines + 1] = ("Requires skill %d%s"):format(skill, borrowedSkill and " (unconfirmed)" or "")
    end

    if #lines == 0 then return nil end
    return lines, sources and db:IsBorrowed(recipeID, "sources") or nil
end
