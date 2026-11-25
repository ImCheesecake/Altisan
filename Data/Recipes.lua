-- Reads the open profession window and saves each character's recipes, plus the sorting and
-- counting the recipe lists use. The whole list is only readable while that window is open;
-- known recipes can be read at login.

local _, ns = ...

ns.DIFFICULTY = {
    [0] = { color = "ff8040", text = "Orange: always a skill-up" },
    [1] = { color = "ffff00", text = "Yellow: usually a skill-up" },
    [2] = { color = "40bf40", text = "Green: sometimes a skill-up" },
    [3] = { color = "808080", text = "Grey: no skill-ups" },
}

local function CategoryOf(categoryID, cache)
    if not categoryID then return nil end
    if cache[categoryID] == nil then
        cache[categoryID] = C_TradeSkillUI.GetCategoryInfo(categoryID) or false
    end
    return cache[categoryID] or nil
end

local function RememberRecipe(recipeID, info, category, skillLine)
    local entry = ns.db.recipes[recipeID]
    if not entry then
        entry = {}
        ns.db.recipes[recipeID] = entry
    end
    entry.name = info.name
    entry.icon = info.icon
    entry.category = category and category.name or entry.category
    entry.categoryID = info.categoryID
    entry.skillLine = skillLine
    entry.trivial = info.maxTrivialLevel
    entry.itemLevel = info.itemLevel

    -- GetRecipeSourceText is often empty on Forever; false = asked, so it isn't asked again.
    if not info.learned and type(entry.source) ~= "string" and C_TradeSkillUI.GetRecipeSourceText then
        local ok, text = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
        text = ok and text and strtrim(text) or ""
        entry.source = text ~= "" and text or false
    end

    if entry.reagents == nil or entry.fromLibrary or entry.made == nil then
        entry.fromLibrary = nil
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        entry.item = schematic and schematic.outputItemID or nil
        entry.made = schematic and schematic.quantityMin or 1
        entry.reagents = {}
        for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
            local reagent = slot.reagents and slot.reagents[1]
            if reagent and reagent.itemID and (slot.quantityRequired or 0) > 0 then
                table.insert(entry.reagents, { reagent.itemID, slot.quantityRequired })
            end
        end
    end
end

local function ShownProfession()
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local child = C_TradeSkillUI.GetChildProfessionInfo()
    if not child or not child.professionID or child.professionID == 0 then
        child = base   -- Some NPC crafting windows have no child line.
    end
    return base, child
end

-- The skill line sits at any level of the category tree; a chain naming another line is the last
-- profession's list still in the window. IsRecipeInSkillLine is too loose: last resort only.
local function BelongsTo(recipeID, categoryID, lines, cache)
    local namedAny = false
    local seen = 0
    while categoryID and seen < 10 do
        local category = CategoryOf(categoryID, cache)
        if not category then break end
        local line = category.skillLineID
        if line and line ~= 0 then
            if lines[line] then return true end
            namedAny = true
        end
        categoryID = category.parentCategoryID
        seen = seen + 1
    end
    if namedAny then return false end
    for line in pairs(lines) do
        if C_TradeSkillUI.IsRecipeInSkillLine(recipeID, line) then return true end
    end
    return false
end

local function RememberCategory(categoryID, cache)
    local seen = 0
    while categoryID and seen < 10 do
        local category = CategoryOf(categoryID, cache)
        if not category then return end
        ns.db.categories[categoryID] = {
            name = category.name,
            order = category.uiOrder or 0,
            parent = category.parentCategoryID,
        }
        categoryID = category.parentCategoryID
        seen = seen + 1
    end
end

local tries = 0
local function TryAgainSoon()
    if tries < 10 then
        tries = tries + 1
        C_Timer.After(0.5, ns.ScanOpenProfession)
    else
        tries = 0
    end
end

function ns.ScanOpenProfession()
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsNPCCrafting() then
        return
    end

    -- While loading or switching, the list still holds the old profession (or nothing).
    if not C_TradeSkillUI.IsTradeSkillReady() or C_TradeSkillUI.IsDataSourceChanging() then
        TryAgainSoon()
        return
    end

    local base, child = ShownProfession()
    if not base or not base.professionID or base.professionID == 0 then return end
    local line = child.professionID
    -- Saved under the parent line: the number GetProfessionInfo reports.
    local parent = child.parentProfessionID or base.professionID

    local categories = {}
    local known, unknown, order = {}, {}, {}

    local lines = { [line] = true, [parent] = true, [base.professionID] = true }

    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and not info.isDummyRecipe and not ns.IsHiddenRecipe(recipeID, info.categoryID)
            and BelongsTo(recipeID, info.categoryID, lines, categories) then
            local category = CategoryOf(info.categoryID, categories)
            RememberRecipe(recipeID, info, category, parent)
            RememberCategory(info.categoryID, categories)
            table.insert(order, recipeID)
            if info.learned then
                known[recipeID] = info.relativeDifficulty or 3
            else
                unknown[recipeID] = true
            end
        end
    end

    -- Nothing matched: the list hasn't caught up with the profession yet.
    if #order == 0 then
        TryAgainSoon()
        return
    end
    tries = 0

    local char = ns.CurrentCharacter()
    char.recipes = char.recipes or {}
    char.recipes[parent] = {
        name = child.parentProfessionName or base.professionName,
        skillLine = parent,
        line = line,
        known = known,
        unknown = unknown,
        order = order,
        scanned = time(),
        skill = child.skillLevel,
        maxSkill = child.maxSkillLevel,
    }
    ns.Cooldowns.FromScan(char, parent, known)

    ns.FillLoginListsFrom(parent)
    ns.ItemUses.Forget()
    ns.ForgetMakers()
    ns.RefreshWindow()
end

function ns.ProfessionDebugLines()
    if not C_TradeSkillUI.IsTradeSkillReady() then return nil end
    local out = {}
    local function say(text) out[#out + 1] = text end
    local base, child = ShownProfession()
    say(("Base: %s (%s)   Shown: %s (%s), parent %s"):format(
        tostring(base and base.professionName), tostring(base and base.professionID),
        tostring(child and child.professionName), tostring(child and child.professionID),
        tostring(child and child.parentProfessionID)))
    for _, info in ipairs(C_TradeSkillUI.GetChildProfessionInfos() or {}) do
        say(("  child line: %s (%s)"):format(tostring(info.professionName), tostring(info.professionID)))
    end

    local groups, list, categories = {}, {}, {}
    local lines = { [child.professionID] = true, [base.professionID] = true }
    if child.parentProfessionID then lines[child.parentProfessionID] = true end
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info then
            local category = CategoryOf(info.categoryID, categories)
            local id = info.categoryID or 0
            local g = groups[id]
            if not g then
                local parentCategory = category and CategoryOf(category.parentCategoryID, categories)
                g = { id = id, name = category and category.name or "?", line = category and category.skillLineID,
                      parentID = category and category.parentCategoryID,
                      parentLine = parentCategory and parentCategory.skillLineID,
                      inBase = C_TradeSkillUI.IsRecipeInSkillLine(recipeID, base.professionID),
                      inShown = C_TradeSkillUI.IsRecipeInSkillLine(recipeID, child.professionID),
                      total = 0, learned = 0, kept = 0, hidden = 0 }
                groups[id] = g
                table.insert(list, g)
            end
            g.total = g.total + 1
            if info.learned then g.learned = g.learned + 1 end
            if ns.IsHiddenRecipe(recipeID, info.categoryID) then
                g.hidden = g.hidden + 1
            elseif not info.isDummyRecipe and BelongsTo(recipeID, info.categoryID, lines, categories) then
                g.kept = g.kept + 1
            end
        end
    end
    for _, g in ipairs(list) do
        say(("  %s #%s [line %s, parent #%s line %s, in base %s, in shown %s]: %d recipes, %d learned, %d kept, %d hidden"):format(
            g.name, tostring(g.id), tostring(g.line), tostring(g.parentID), tostring(g.parentLine),
            g.inBase and "y" or "n", g.inShown and "y" or "n", g.total, g.learned, g.kept, g.hidden))
    end

    local db = ns.ProfessionDB()
    if db then
        local _, game = db:GetMeta()
        say(("  LibProfessionDB: loaded and ready (%s data, %d recipes)"):format(tostring(game), db:Count()))
    else
        say("  LibProfessionDB: not loaded")
    end

    local withText, unlearned, example = 0, 0, nil
    for recipeID, recipe in pairs(ns.db.recipes) do
        if recipe.source ~= nil then
            unlearned = unlearned + 1
            if recipe.source then
                withText = withText + 1
                example = example or (recipe.name .. ": " .. recipe.source:gsub("|n", " / "):gsub("\n", " / "))
            end
        end
    end
    say(("  where to learn: %d of %d unlearned recipes have text%s"):format(withText, unlearned,
        C_TradeSkillUI.GetRecipeSourceText and "" or " (GetRecipeSourceText doesn't exist)"))
    if example then say("  e.g. " .. example) end

    for _, line in ipairs(ns.Legacy.DebugLines()) do say(line) end
    for _, line in ipairs(ns.Bags.DebugLines()) do say(line) end

    return "Altisan debug: " .. tostring(base and base.professionName), out
end

-- The window sends a burst of updates while it fills in; scan once they settle.
local scanPending = false
function ns.ScanProfessionSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = false
        ns.ScanOpenProfession()
    end)
end

function ns.OnRecipeLearned(recipeID)
    -- Errors for spells that aren't recipes.
    local ok, line, _, parent = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
    if not ok then return end
    local char = ns.CurrentCharacter()
    for _, skillLine in ipairs({ parent or false, line or false }) do
        local prof = skillLine and char.recipes and char.recipes[skillLine]
        if prof then
            prof.known[recipeID] = prof.known[recipeID] or 0
            prof.unknown[recipeID] = nil
            ns.RefreshWindow()
            return
        end
    end
end

-- Unlearned recipes can't come from the library at login: it also lists Season of Discovery recipes
-- Forever lacks. They come from another character's window scan of the same profession.

local IsKnown = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown

local function RememberFromLibrary(recipeID, r, line)
    if ns.db.recipes[recipeID] then return end
    local reagents = {}
    for itemID, count in pairs(r.reagents or {}) do reagents[#reagents + 1] = { itemID, count } end
    table.sort(reagents, function(a, b) return a[1] < b[1] end)
    local icon = r.craftedItemId and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.craftedItemId)
    ns.db.recipes[recipeID] = {
        name = r.name,
        icon = icon or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID)),
        skillLine = line,
        item = r.craftedItemId,
        trivial = r.difficulty and r.difficulty[4],
        reagents = reagents,
        fromLibrary = true,
    }
end

local function AccountList(line)
    local best, bestKey
    for key, char in pairs(ns.db.characters) do
        local scan = char.recipes and char.recipes[line]
        if scan and scan.scanned and (not best or scan.scanned > best.scanned) then best, bestKey = scan, key end
    end
    return best, bestKey
end

local function FillFromAccount(scan)
    local list, key = AccountList(scan.skillLine)
    scan.unknown, scan.order, scan.listFrom = {}, {}, key
    local listed = {}
    for _, id in ipairs(list and list.order or {}) do
        scan.order[#scan.order + 1] = id
        listed[id] = true
        if not scan.known[id] then scan.unknown[id] = true end
    end
    local extra = {}
    for id in pairs(scan.known) do
        if not listed[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do scan.order[#scan.order + 1] = id end
end

function ns.HasFullList(scan)
    return scan ~= nil and (scan.scanned ~= nil or scan.listFrom ~= nil)
end

function ns.ReadKnownAtLogin()
    local db = ns.ProfessionDB and ns.ProfessionDB()
    if not (db and IsKnown) then return end
    local char = ns.CurrentCharacter()
    char.recipes = char.recipes or {}
    for _, prof in ipairs(char.professions or {}) do
        local line = prof.skillLine
        local own = line and char.recipes[line]
        if line and not ns.GATHERING[line] and not (own and own.scanned) then
            local known = {}
            for recipeID, r in pairs(db:GetRecipes(line) or {}) do
                -- Rank spells ("Cooking") are in the lists too: nothing made, no materials.
                local real = r.craftedItemId or (r.reagents and next(r.reagents))
                if real and not ns.IsHiddenRecipe(recipeID) and IsKnown(recipeID) then
                    known[recipeID] = ns.WouldBeDifficulty(recipeID, line, prof.skill) or 3
                    RememberFromLibrary(recipeID, r, line)
                end
            end
            local scan = { name = prof.name, skillLine = line, known = known, atLogin = time(),
                           skill = prof.skill, maxSkill = prof.maxSkill }
            FillFromAccount(scan)
            char.recipes[line] = (scan.listFrom or next(known)) and scan or nil
        end
    end
end

function ns.FillLoginListsFrom(line)
    for _, char in pairs(ns.db.characters) do
        local scan = char.recipes and char.recipes[line]
        if scan and not scan.scanned and scan.atLogin then FillFromAccount(scan) end
    end
end

function ns.Reagents(recipeID, skillLine)
    local saved = ns.db.recipes[recipeID]
    if saved and saved.reagents and #saved.reagents > 0 then return saved.reagents end
    local db = ns.ProfessionDB and ns.ProfessionDB()
    if not db then return {} end
    for _, prof in ipairs(skillLine and { skillLine } or db:GetProfessions()) do
        local reagents = db:GetReagents(prof, recipeID)
        if reagents then
            local list = {}
            for itemID, count in pairs(reagents) do list[#list + 1] = { itemID, count } end
            table.sort(list, function(a, b) return a[1] < b[1] end)
            return list
        end
    end
    return {}
end

local makers
function ns.ForgetMakers() makers = nil end

function ns.RecipesMaking(itemID)
    if not makers then
        makers = {}
        local function AddMaker(item, recipeID, skillLine)
            if not (item and skillLine) then return end
            makers[item] = makers[item] or {}
            for _, m in ipairs(makers[item]) do if m.recipeID == recipeID then return end end
            table.insert(makers[item], { recipeID = recipeID, skillLine = skillLine })
        end
        local db = ns.ProfessionDB and ns.ProfessionDB()
        for _, prof in ipairs(db and db:GetProfessions() or {}) do
            for recipeID, r in pairs(db:GetRecipes(prof) or {}) do AddMaker(r.craftedItemId, recipeID, prof) end
        end
        for recipeID, r in pairs(ns.db.recipes) do AddMaker(r.item, recipeID, r.skillLine) end
    end
    return makers[itemID] or {}
end

function ns.MadePer(recipeID) return (ns.db.recipes[recipeID] or {}).made or 1 end

function ns.CraftsFor(recipeID, count) return math.ceil(count / ns.MadePer(recipeID)) end

function ns.ProfessionHolders(list, keep)
    local byLine, out = {}, {}
    for _, entry in ipairs(list) do
        for _, prof in ipairs(entry.char.professions or {}) do
            local line = prof.skillLine
            if line and (not keep or keep(line, prof)) then
                local p = byLine[line]
                if not p then
                    p = { skillLine = line, name = prof.name, holders = {} }
                    byLine[line] = p
                    out[#out + 1] = p
                end
                table.insert(p.holders, { key = entry.key, char = entry.char, prof = prof,
                                          scan = ns.GetProfessionRecipes(entry.char, line) })
            end
        end
    end
    return out, byLine
end

function ns.BestHolder(holders, opts)
    opts = opts or {}
    local best
    for _, h in ipairs(holders) do
        if (not opts.scanned or h.scan) and (not opts.played or ns.IsPlayed(h.key))
            and (not best or (h.prof.skill or 0) > (best.prof.skill or 0)) then
            best = h
        end
    end
    return best
end

function ns.KnownBy(recipeID, skillLine, list, exceptKey)
    local out = {}
    for _, entry in ipairs(list) do
        if entry.key ~= exceptKey then
            local scan = ns.GetProfessionRecipes(entry.char, skillLine)
            if scan and scan.known[recipeID] then out[#out + 1] = entry end
        end
    end
    return out
end

function ns.GetProfessionRecipes(char, skillLine)
    return char.recipes and char.recipes[skillLine]
end

-- Raising this drops every saved scan; each is read again when its window next opens.
local DATA_VERSION = 3
function ns.ForgetOldScans(db)
    if (db.dataVersion or 1) >= DATA_VERSION then return end
    for _, char in pairs(db.characters or {}) do
        char.recipes = nil
    end
    db.recipes = {}
    db.categories = {}
    db.dataVersion = DATA_VERSION
end

ns.GATHERING = { [182] = true, [186] = true, [393] = true, [356] = true }

-- English fallbacks: the game only names professions a character on the account has.
ns.CRAFTING = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting",
                [202] = "Engineering", [165] = "Leatherworking", [197] = "Tailoring" }
ns.CRAFTING_COUNT = 6
-- Fishing is left out: it has no recipes.
ns.SECONDARY = { [129] = "First Aid", [185] = "Cooking" }

ns.RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
-- On Forever these First Aid and Cooking ranks come from a book or a quest, not a trainer.
ns.RANK_LEARNED_FROM = { [129] = { [225] = "book", [300] = "quest" }, [185] = { [225] = "book", [300] = "quest" } }

ns.PROFESSION_NAMES = { [182] = "Herbalism", [186] = "Mining", [393] = "Skinning", [356] = "Fishing" }
for line, name in pairs(ns.CRAFTING) do ns.PROFESSION_NAMES[line] = name end
for line, name in pairs(ns.SECONDARY) do ns.PROFESSION_NAMES[line] = name end

function ns.ProfessionName(skillLine)
    return ns.PROFESSION_NAMES[skillLine] or ("Profession " .. skillLine)
end

local function CategoryPath(categoryID, fallbackName)
    local path = {}
    local seen = 0
    while categoryID and ns.db.categories[categoryID] and seen < 10 do
        local category = ns.db.categories[categoryID]
        table.insert(path, 1, { category.order or 0, category.name or "" })
        categoryID = category.parent
        seen = seen + 1
    end
    if #path == 0 then path[1] = { math.huge, fallbackName or "Other" } end
    return path
end

-- strcmputf8i ignores case and sorts letters like Å and É the way the game does.
local function NameBefore(a, b)
    if strcmputf8i then return strcmputf8i(a, b) < 0 end
    return a:lower() < b:lower()
end

local function PathBefore(a, b)
    for i = 1, math.min(#a, #b) do
        if a[i][1] ~= b[i][1] then return a[i][1] < b[i][1] end
        if a[i][2] ~= b[i][2] then return NameBefore(a[i][2], b[i][2]) end
    end
    return #a < #b
end

-- Blizzard's own order inside a category.
local function RecipeBefore(scan)
    return function(a, b)
        local la, lb = scan.known[a] ~= nil, scan.known[b] ~= nil
        if la ~= lb then return la end
        local ra, rb = ns.db.recipes[a] or {}, ns.db.recipes[b] or {}
        if (ra.trivial or 0) ~= (rb.trivial or 0) then return (ra.trivial or 0) > (rb.trivial or 0) end
        if (ra.itemLevel or 0) ~= (rb.itemLevel or 0) then return (ra.itemLevel or 0) > (rb.itemLevel or 0) end
        if (ra.name or "") ~= (rb.name or "") then return NameBefore(ra.name or "", rb.name or "") end
        return a < b
    end
end

function ns.SortedRecipes(scan)
    local groups, byKey = {}, {}
    local learnable = ns.LearnableFilter(scan)
    local ungrouped = ns.HasFullList(scan) and "Other" or "Known"
    for _, recipeID in ipairs(scan.order) do
        if learnable(recipeID) then
            local recipe = ns.db.recipes[recipeID] or {}
            local key = recipe.categoryID or recipe.category or ungrouped
            local group = byKey[key]
            if not group then
                local path = CategoryPath(recipe.categoryID, recipe.category or ungrouped)
                group = { key = key, name = path[#path][2], depth = #path - 1, path = path, ids = {},
                          learned = 0 }
                byKey[key] = group
                table.insert(groups, group)
            end
            table.insert(group.ids, recipeID)
            if scan.known[recipeID] then group.learned = group.learned + 1 end
        end
    end
    table.sort(groups, function(a, b) return PathBefore(a.path, b.path) end)
    local before = RecipeBefore(scan)
    for _, group in ipairs(groups) do
        table.sort(group.ids, before)
    end
    return groups
end

function ns.CountRecipes(scan)
    local learned, total = 0, 0
    for _ in pairs(scan.known) do learned = learned + 1 end
    total = learned
    local learnable = ns.LearnableFilter(scan)
    for recipeID in pairs(scan.unknown) do
        if learnable(recipeID) then total = total + 1 end
    end
    return learned, total
end
