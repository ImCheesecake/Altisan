-- SkillPlanText.lua: a plan to the next rank in words. Every number carries its unit: a skill is a
-- range with the profession's name, a count says "times" or "×".

local _, ns = ...
local UI = ns.UI
local Plan = ns.SkillPlan

local function Rounded(count) return math.max(1, math.ceil(count - 0.001)) end

local function Times(n) return n == 1 and "once" or (n .. " times") end
Plan.Times = Times

local function SortedKeys(t, less)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out, less)
    return out
end

local function Who(key)
    return UI.CharName(ns.db.characters[key], key)
end

function Plan.StepLine(plan, step, what)
    return ("%s %d to %d: make %s %s."):format(plan.name, step.from, step.to, what, Times(step.make))
end

-- The plan is worked out again after every point, so the first step is always the one you're on.
function Plan.StepWhen(plan, i)
    if i > 1 then return ("Starts after %s."):format(UI.Count(i - 1, "step", "steps")) end
    local left = #plan.steps - 1
    if left == 0 then return ("This step reaches %d."):format(plan.steps[1].to) end
    return ("%s after this one to reach %d."):format(UI.Count(left, "more step", "more steps"), plan.steps[#plan.steps].to)
end

function Plan.OddsLine(step)
    local green = math.floor((step.yellow + step.grey) / 2)
    if step.from < step.yellow then
        return ("Orange until %d: a point every craft. Yellow until %d, then green: points come less often.")
            :format(step.yellow, green)
    elseif step.from < green then
        return ("Yellow until %d: a point most crafts. Then green: points come less often."):format(green)
    end
    return ("Green until %d: points come less often the closer it gets."):format(step.grey)
end

local PLACE_WORDS = { bags = "bags", bank = "bank", mail = "mailbox" }
local function WhereHeld(key, itemID)
    local char, best, most = ns.db.characters[key], "bags", 0
    for _, place in ipairs(ns.Bags.PLACES) do
        local data = char and char[place.field]
        local n = data and data.items and data.items[itemID] or 0
        if n > most then best, most = place.field, n end
    end
    return ("in %s's %s"):format(Who(key), PLACE_WORDS[best])
end

local function ItemCount(n, itemID, redraw) return ("%d × %s"):format(n, UI.ItemLabel(itemID, redraw)) end

function Plan.NextRank(plan)
    local from = (ns.RANK_LEARNED_FROM[plan.skillLine] or {})[plan.target + 75] or "trainer"
    if from == "quest" then return { from = from, places = ns.Places.ForSkillQuests(plan.skillLine, plan.target) } end
    local book = from == "book" and ns.RankBook(plan.skillLine)
    if not book then return { from = from, places = {} } end
    local vendor = ns.Places.Vendors(book)
    return { from = from, book = book, price = vendor and vendor.price, places = vendor and vendor.places or {} }
end

function Plan.LearnSource(step) return step.learnFrom == "vendor" and "from a vendor" or "from a trainer" end

function Plan.LearnNote(step)
    local itemID = step.learnFrom == "vendor" and ns.RecipeItem(step.recipeID)
    local vendor = itemID and ns.Places.Vendors(itemID)
    return Plan.LearnSource(step) .. (vendor and vendor.price and (", " .. UI.Money(vendor.price)) or "")
end

function Plan.StepNeeds(plan, step, redraw)
    local groups = {}
    if step.learn then
        groups[#groups + 1] = { label = step.learn == "now" and "Learn it first" or ("Learn it at %d"):format(step.learn),
                                short = Plan.LearnSource(step) .. (step.learn == "now" and " first" or (" at %d"):format(step.learn)),
                                learn = true, lines = {} }
    end
    local fromWho = {}
    for _, itemID in ipairs(SortedKeys(step.held)) do
        for who, n in pairs(step.held[itemID]) do
            if who ~= "own" then
                fromWho[who] = fromWho[who] or {}
                table.insert(fromWho[who], { itemID = itemID, n = Rounded(n) })
            end
        end
    end
    local function BankLast(a, b)
        if (a == "bank") ~= (b == "bank") then return b == "bank" end
        return a < b
    end
    for _, who in ipairs(SortedKeys(fromWho, BankLast)) do
        local g = { label = who == "bank" and "From the account bank" or ("Mail from %s"):format(Who(who)), lines = {} }
        for _, it in ipairs(fromWho[who]) do
            local where = who == "bank" and "in the account bank" or WhereHeld(who, it.itemID)
            g.lines[#g.lines + 1] = { ItemCount(it.n, it.itemID, redraw), where, it.itemID, n = it.n, source = where }
        end
        groups[#groups + 1] = g
    end
    if next(step.buy) then
        local g, total, priced = { label = "Buy", lines = {} }, 0, true
        for _, itemID in ipairs(SortedKeys(step.buy)) do
            local b = step.buy[itemID]
            local right = not b.unit and "price not known"
                or b.from == "vendor" and ("sold by vendors, %s"):format(UI.Money(b.unit * b.count))
                or ("auction house, about %s"):format(UI.RoughMoney(b.unit * b.count))
            if b.unit then total = total + b.unit * b.count else priced = false end
            g.lines[#g.lines + 1] = { ItemCount(b.count, itemID, redraw), right, itemID, n = b.count,
                                      source = not b.unit and "price not known" or b.from == "vendor" and "vendor" or "auction house" }
        end
        g.right = total > 0 and ("about %s%s"):format(UI.RoughMoney(total), priced and "" or ", and more") or nil
        groups[#groups + 1] = g
    end
    if next(step.create) then
        local g = { label = "Make", lines = {} }
        for _, itemID in ipairs(SortedKeys(step.create)) do
            local count, maker = Rounded(step.create[itemID]), step.makers[itemID]
            local crafts = ns.CraftsFor(maker.recipeID, count)
            local from = {}
            for _, r in ipairs(ns.Reagents(maker.recipeID, maker.skillLine)) do
                from[#from + 1] = ("%d %s"):format(r[2] * crafts, UI.ItemLabel(r[1], redraw))
            end
            local who = maker.key == plan.key and "you" or Who(maker.key)
            g.lines[#g.lines + 1] = { ItemCount(count, itemID, redraw), ("%s, from %s"):format(who, UI.JoinNames(from)), itemID,
                                      n = count, source = who, by = maker.key ~= plan.key and who or nil }
        end
        groups[#groups + 1] = g
    end
    for _, g in ipairs(groups) do
        if not g.short then
            local parts = {}
            for _, line in ipairs(g.lines) do parts[#parts + 1] = (line.by and (line.by .. ": ") or "") .. line[1] end
            g.short = table.concat(parts, ", ")
        end
    end
    return groups
end

function Plan.InPlanLine(plan, recipeID)
    local ranges = {}
    for _, step in ipairs(plan and plan.steps or {}) do
        if step.recipeID == recipeID then ranges[#ranges + 1] = ("%d to %d"):format(step.from, step.to) end
    end
    if #ranges == 0 then return nil end
    return ("In your plan: %s %s."):format(plan.name, UI.JoinNames(ranges))
end

function Plan.Materials(plan)
    local total, out = {}, {}
    for _, s in ipairs(plan.steps) do
        for _, r in ipairs(ns.Reagents(s.recipeID, plan.skillLine)) do total[r[1]] = (total[r[1]] or 0) + r[2] * s.make end
    end
    for itemID, n in pairs(total) do out[#out + 1] = { itemID, n } end
    table.sort(out, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    return out
end

function Plan.HaveNeed(plan, steps)
    local by, out = {}, {}
    for _, s in ipairs(steps) do
        local counted = {}   -- a material a recipe lists twice: its step.own once
        for _, r in ipairs(ns.Reagents(s.recipeID, plan.skillLine)) do
            local e = by[r[1]]
            if not e then
                e = { itemID = r[1], need = 0, held = 0, make = 0, buy = 0 }
                by[r[1]], out[#out + 1] = e, e
            end
            e.need = e.need + r[2] * s.make
            local own = not counted[r[1]] and s.own and s.own[r[1]]
            counted[r[1]] = true
            if own then
                e.held, e.make, e.buy = e.held + own.held, e.make + own.make, e.buy + own.buy
                if own.make > 0 then e.maker = s.makers[r[1]] end
            end
        end
    end
    for _, e in ipairs(out) do
        e.have = math.min(e.need, math.floor(e.held + 0.5))
        local rest = e.need - e.have
        local made = e.buy > 0 and math.min(rest, math.floor(e.make + 0.5)) or (e.make > 0 and rest or 0)
        e.make, e.buy = made, rest - made
    end
    table.sort(out, function(a, b)
        if a.need ~= b.need then return a.need > b.need end
        return a.itemID < b.itemID
    end)
    return out
end

function Plan.Size(plan)
    local seen, recipes = {}, 0
    for _, s in ipairs(plan.steps) do
        if not seen[s.recipeID] then seen[s.recipeID], recipes = true, recipes + 1 end
    end
    return ("%s, %s"):format(UI.Count(recipes, "recipe", "recipes"), UI.Count(plan.crafts, "craft", "crafts"))
end

function Plan.RowParts(step)
    return ("%d ×"):format(step.make), ("%d to %d"):format(step.from, step.to)
end
