-- SkillPlan.lua: the way from a character's skill to the most their training allows, using what the
-- account holds first (or, with Auctionator, the cheapest), kept until a step can't be done, and
-- the plans put on Shopping.

local _, ns = ...
local Plan = {}
ns.SkillPlan = Plan

local DEAR = 1000000
local EFFORT = 100
local MAX_DEPTH = 3
local SWITCH = 1.2
local LEARN = 1.2
local TIE = 1.1
local FETCH = EFFORT
local SHORT, FOLD, TRIES = 2, 10000, 6
local FOLD_SHARE = 0.03

-- The window scan saves the game's own grey; the library's yellow is moved to match the color the
-- window showed.
local function Levels(recipeID, skillLine, scan)
    local t = ns.SkillUpLevels(skillLine, recipeID)
    local saved = ns.db.recipes[recipeID]
    local grey = saved and saved.trivial or (t and t[4])
    if not grey then return nil end
    local yellow = math.min(t and t[2] or grey, grey)
    local seen = scan.scanned and scan.skill and scan.known[recipeID]
    if seen == 0 then
        yellow = math.min(math.max(yellow, scan.skill + 1), grey)
    elseif seen == 1 or seen == 2 then
        yellow = math.min(yellow, scan.skill)
    end
    return yellow, grey
end

-- Between yellow and grey, the formula Classic players use: Forever publishes none.
local function Chance(c, skill)
    if skill >= c.grey then return 0 end
    if skill < c.yellow then return 1 end
    return (c.grey - skill) / (c.grey - c.yellow)
end
Plan.Chance = Chance

-- The library lists vendors that stand nowhere in the world: only ones with a place on the map
-- count.
function Plan.LearnFrom(recipeID)
    local kind = ns.RecipeSourceKind(recipeID)
    if kind == "Trainer" then return "trainer" end
    if kind ~= "Vendor" or ns.Favor.IsRecipe(recipeID) then return nil end
    for _, p in ipairs((ns.Places.ForRecipe(recipeID))) do
        if p.kind == "vendor" and p.mapID then return "vendor" end
    end
end

local function Candidates(scan, skillLine, skill, target)
    local out = {}
    local function AddCandidate(recipeID, learnAt, learnFrom)
        if ns.Ignore.Is(recipeID) then return end
        local reagents = ns.Reagents(recipeID, skillLine)
        if #reagents == 0 then return end
        local yellow, grey = Levels(recipeID, skillLine, scan)
        if grey and grey > skill and (learnAt or 0) < target then
            out[#out + 1] = { recipeID = recipeID, reagents = reagents, yellow = yellow, grey = grey, learnAt = learnAt,
                              learnFrom = learnFrom }
        end
    end
    for recipeID in pairs(scan.known) do AddCandidate(recipeID) end
    for recipeID in pairs(scan.unknown or {}) do
        local from = Plan.LearnFrom(recipeID)
        local required = from and ns.RequiredSkill(recipeID, skillLine)
        if required then AddCandidate(recipeID, required, from) end
    end
    table.sort(out, function(a, b) return a.recipeID < b.recipeID end)
    return out
end

local function Pools(list, key, char)
    local pools = { { key = key, char = char, own = true, items = {} } }
    for _, entry in ipairs(ns.Bags.CanReach(list, char, key)) do
        pools[#pools + 1] = { key = entry.key, char = entry.char, items = {} }
    end
    pools[#pools + 1] = { bank = true, items = {} }
    local function Left(pool, itemID)
        local n = pool.items[itemID]
        if n == nil then
            if pool.bank then
                n = ns.db.accountBank and ns.db.accountBank.items and ns.db.accountBank.items[itemID] or 0
            else
                n = ns.Bags.Held(pool.char, itemID)
            end
            pool.items[itemID] = n
        end
        return n
    end
    return pools, Left
end

function Plan.Cheapest()
    return ns.db.window.planCheapest == true and ns.AH.Available()
end

local function KeptRoute(key, skillLine)
    local mine = ns.db.planRoutes[key]
    local route = mine and mine[skillLine]
    if route and route.cheapest == Plan.Cheapest() then return route end
end

local function KeepRoute(key, skillLine, plan)
    local mine = ns.db.planRoutes[key] or {}
    ns.db.planRoutes[key] = mine
    if plan.reason or plan.reached < plan.target then
        mine[skillLine] = nil
        return
    end
    local steps = {}
    for i, s in ipairs(plan.steps) do steps[i] = { s.recipeID, s.from, s.to } end
    mine[skillLine] = { target = plan.target, cheapest = Plan.Cheapest(), steps = steps }
end

local function KeptRecipe(route, skill)
    for _, s in ipairs(route.steps) do
        if skill >= s[2] and skill < s[3] then return s[1] end
    end
end

local remade = {}
local function Order(steps)
    local ids = {}
    for i, s in ipairs(steps) do ids[i] = s.recipeID or s[1] end
    return table.concat(ids, ",")
end

function Plan.Forget(key, skillLine)
    local mine = ns.db.planRoutes[key]
    local route = mine and mine[skillLine]
    remade[key .. ":" .. skillLine] = { before = route and Order(route.steps) or "" }
    if mine then mine[skillLine] = nil end
    ns.RefreshWindow()
end

function Plan.Remade(plan)
    local id = plan.key .. ":" .. plan.skillLine
    local r = remade[id]
    if not r then return nil end
    local now = Order(plan.steps)
    r.after = r.after or now
    if r.after ~= now then
        remade[id] = nil
        return nil
    end
    return r.before == now and "same" or "changed"
end

local NONE = {}
local function Banned(banned, recipeID, skill)
    for _, r in ipairs(banned[recipeID] or NONE) do
        if skill >= r[1] and skill < r[2] then return true end
    end
    return false
end

local function Route(list, key, skillLine, banned, follow)
    local char = ns.db.characters[key]
    local prof
    for _, p in ipairs(char and char.professions or {}) do
        if p.skillLine == skillLine then prof = p end
    end
    if not (prof and (ns.CRAFTING[skillLine] or ns.SECONDARY[skillLine])) then return nil end
    local skill, target = prof.skill or 0, prof.maxSkill or 0
    if target <= 0 then return nil end
    local plan = { key = key, char = char, skillLine = skillLine, name = prof.name, skill = skill,
                   target = target, steps = {}, cost = 0, crafts = 0 }
    if skill >= target then
        plan.reason = "cap"
        plan.rank, plan.nextRank = ns.RANKS[target], ns.RANKS[target + 75]
        return plan
    end
    local scan = ns.GetProfessionRecipes(char, skillLine)
    if not scan then
        plan.reason = "scan"
        return plan
    end
    local pools, Left = Pools(list, key, char)
    local touches, pricing = {}, nil
    local function LeftInReach(itemID)
        if pricing then
            touches[itemID] = touches[itemID] or {}
            touches[itemID][pricing] = true
        end
        local n = 0
        for _, pool in ipairs(pools) do n = n + Left(pool, itemID) end
        return n
    end

    local reach = ns.Bags.CanReach(list, char)
    local prices, makers = {}, {}
    local function Price(itemID)
        if not prices[itemID] then prices[itemID] = { ns.ItemPrice(itemID) } end
        return unpack(prices[itemID])
    end
    local function MadeBy(itemID)
        if makers[itemID] == nil then
            makers[itemID] = false
            for _, m in ipairs(ns.RecipesMaking(itemID)) do
                for _, entry in ipairs(reach) do
                    local s = ns.GetProfessionRecipes(entry.char, m.skillLine)
                    local found = makers[itemID]
                    if s and s.known[m.recipeID] and (not found or (entry.key == key and found.key ~= key)) then
                        makers[itemID] = { recipeID = m.recipeID, skillLine = m.skillLine, key = entry.key }
                    end
                end
            end
        end
        return makers[itemID] or nil
    end
    local function UnitCost(itemID, depth)
        local price, from = Price(itemID)
        local maker = depth < MAX_DEPTH and MadeBy(itemID)
        if maker then
            local made = 0
            for _, r in ipairs(ns.Reagents(maker.recipeID, maker.skillLine)) do
                made = made + r[2] * (LeftInReach(r[1]) > 0 and 0 or UnitCost(r[1], depth + 1))
            end
            made = made / ns.MadePer(maker.recipeID)
            if not price or made < price then return made, "create", maker end
        end
        if price then return price, from end
        return DEAR
    end
    local cheapest = Plan.Cheapest()
    local function Fetch(itemID)
        local price, from = Price(itemID)
        return from == "vendor" and price or FETCH
    end
    local function CraftCost(c)
        if c.cost then return c.cost end
        pricing = c
        local cost = EFFORT
        for _, r in ipairs(c.reagents) do
            local short = r[2] - LeftInReach(r[1])
            if short > 0 then cost = cost + short * (cheapest and UnitCost(r[1], 1) or Fetch(r[1])) end
        end
        pricing = nil
        c.cost = cost
        return cost
    end
    local function Covered(c)
        local held, made, counted = 0, 0, 0
        for _, r in ipairs(c.reagents) do
            if r[2] > 0 then
                counted = counted + 1
                held = held + math.min(1, LeftInReach(r[1]) / r[2])
                if MadeBy(r[1]) then made = made + 1 end
            end
        end
        if counted == 0 then return 1, 0 end
        return held / counted, made / counted
    end
    local function Better(a, b)
        if (a.c.learnAt == nil) ~= (b.c.learnAt == nil) then return a.c.learnAt == nil end
        if a.held ~= b.held then return a.held > b.held end
        if a.made ~= b.made then return a.made > b.made end
        return a.cost < b.cost
    end

    local function Use(step, itemID, count, depth)
        local own = depth == 1 and (step.own[itemID] or { held = 0, make = 0, buy = 0 }) or nil
        if own then step.own[itemID] = own end
        for _, pool in ipairs(pools) do
            local n = math.min(count, Left(pool, itemID))
            if n > 0 then
                pool.items[itemID] = pool.items[itemID] - n
                for c in pairs(touches[itemID] or {}) do c.cost = nil end
                count = count - n
                local who = pool.own and "own" or pool.bank and "bank" or pool.key
                step.held[itemID] = step.held[itemID] or {}
                step.held[itemID][who] = (step.held[itemID][who] or 0) + n
                if own then own.held = own.held + n end
            end
        end
        if count <= 0 then return end
        local unit, how, maker = UnitCost(itemID, depth)
        if own then
            if how == "create" then own.make = own.make + count else own.buy = own.buy + count end
        end
        if how == "create" then
            step.create[itemID] = (step.create[itemID] or 0) + count
            step.makers[itemID] = maker
            for _, r in ipairs(ns.Reagents(maker.recipeID, maker.skillLine)) do
                Use(step, r[1], r[2] * count / ns.MadePer(maker.recipeID), depth + 1)
            end
        else
            local b = step.buy[itemID] or { count = 0, unit = unit ~= DEAR and unit or nil, from = how }
            b.count = b.count + count
            step.buy[itemID] = b
        end
    end

    local candidates = Candidates(scan, skillLine, skill, target)
    local learned = {}
    local step, last
    while skill < target do
        local best, bestCost, bestChance, lastCost, lastChance
        local options = {}
        for _, c in ipairs(candidates) do
            local chance = (c.learnAt or 0) <= skill and not Banned(banned, c.recipeID, skill) and Chance(c, skill) or 0
            if chance > 0 then
                local cost = CraftCost(c) / chance * (not cheapest and c.learnAt and not learned[c] and LEARN or 1)
                options[#options + 1] = { c = c, cost = cost, chance = chance }
                if c == last then lastCost, lastChance = cost, chance end
                if not best or cost < bestCost or (cost == bestCost and chance > bestChance) then
                    best, bestCost, bestChance = c, cost, chance
                end
            end
        end
        local lowest = bestCost
        if follow then
            local want = KeptRecipe(follow, skill)
            best = nil
            for _, o in ipairs(options) do
                if o.c.recipeID == want then best, bestCost, bestChance = o.c, o.cost, o.chance end
            end
            if not best then
                plan.broken = true
                break
            end
        elseif best and not cheapest then
            local pick
            for _, o in ipairs(options) do
                if o.cost <= lowest * TIE then
                    o.held, o.made = Covered(o.c)
                    if not pick or Better(o, pick) then pick = o end
                end
            end
            best, bestCost, bestChance = pick.c, pick.cost, pick.chance
        end
        if not follow and lastCost and lastCost <= lowest * SWITCH then best, bestCost, bestChance = last, lastCost, lastChance end
        plan.score = (plan.score or 0) + (bestCost or 0)
        if not best then
            plan.reason = "none"
            break
        end
        if best ~= last then
            step = { recipeID = best.recipeID, from = skill, crafts = 0, held = {}, buy = {}, create = {}, makers = {},
                     own = {}, yellow = best.yellow, grey = best.grey, learned = best.learnAt == nil,
                     learn = best.learnAt and not learned[best] and (best.learnAt > plan.skill and best.learnAt or "now") or nil }
            step.learnFrom = step.learn and best.learnFrom or nil
            learned[best] = true
            plan.steps[#plan.steps + 1] = step
            last = best
        end
        local crafts = 1 / bestChance
        step.crafts = step.crafts + crafts
        for _, r in ipairs(best.reagents) do Use(step, r[1], r[2] * crafts, 1) end
        skill = skill + 1
        step.to = skill
    end
    plan.reached = skill
    for _, s in ipairs(plan.steps) do
        s.make = math.ceil(s.crafts - 0.001)
        plan.crafts = plan.crafts + s.make
        for _, b in pairs(s.buy) do
            b.count = math.ceil(b.count - 0.001)
            if b.unit then plan.cost = plan.cost + b.unit * b.count else plan.unpriced = true end
        end
    end
    return plan
end

local function ShortStep(plan, tried)
    for i, s in ipairs(plan.steps) do
        if s.to - s.from <= SHORT and not tried[s.recipeID .. ":" .. s.from] then
            local to = math.huge
            for j = i + 1, #plan.steps do
                if plan.steps[j].recipeID == s.recipeID then to = plan.steps[j].from break end
            end
            return s, to
        end
    end
end

local function Fresh(list, key, skillLine)
    local plan = Route(list, key, skillLine, {})
    if not plan then return nil end
    local banned, tried = {}, {}
    for _ = 1, TRIES do
        local s, to = ShortStep(plan, tried)
        if not s then break end
        tried[s.recipeID .. ":" .. s.from] = true
        local trial = {}
        for id, ranges in pairs(banned) do trial[id] = { unpack(ranges) } end
        trial[s.recipeID] = trial[s.recipeID] or {}
        table.insert(trial[s.recipeID], { s.from, to })
        local folded = Route(list, key, skillLine, trial)
        local worth = Plan.Cheapest() and folded.cost - plan.cost < FOLD and (plan.unpriced or not folded.unpriced)
            or not Plan.Cheapest() and folded.score - plan.score < plan.score * FOLD_SHARE
        if folded.reached >= plan.reached and worth then
            plan, banned = folded, trial
        end
    end
    return plan
end

function Plan.Make(list, key, skillLine)
    local route, plan = KeptRoute(key, skillLine), nil
    if route then
        plan = Route(list, key, skillLine, {}, route)
        if plan and (plan.broken or plan.target ~= route.target) then plan = nil end
    end
    plan = plan or Fresh(list, key, skillLine)
    if plan then KeepRoute(key, skillLine, plan) end
    return plan
end

local kept = {}
function Plan.Cached(list, key, skillLine)
    local id = ("%s:%d:%d"):format(key, skillLine, #list)
    local k = kept[id]
    if not (k and k.stamp == ns.dataStamp and k.window == ns.db.window.plan) then
        k = { stamp = ns.dataStamp, window = ns.db.window.plan, plan = Plan.Make(list, key, skillLine) }
        kept[id] = k
    end
    return k.plan
end

function Plan.Difficulty(step, skill)
    if skill >= step.grey then return 3 end
    if skill >= (step.yellow + step.grey) / 2 then return 2 end
    if skill >= step.yellow then return 1 end
    return 0
end

function Plan.Tracked(key, skillLine)
    for i, t in ipairs(ns.db.plans) do
        if t.key == key and t.skillLine == skillLine then return i end
    end
end

function Plan.Toggle(key, skillLine)
    local i = Plan.Tracked(key, skillLine)
    if i then table.remove(ns.db.plans, i) else table.insert(ns.db.plans, { key = key, skillLine = skillLine }) end
    ns.RefreshWindow()
end

function Plan.Untrack(i)
    table.remove(ns.db.plans, i)
    ns.RefreshWindow()
end

function Plan.AllCrafts(list)
    local out, plans = {}, {}
    for _, t in ipairs(ns.db.tracked) do out[#out + 1] = t end
    for i = #ns.db.plans, 1, -1 do
        local t = ns.db.plans[i]
        local listed = false
        for _, e in ipairs(list) do listed = listed or e.key == t.key end
        local plan = listed and Plan.Cached(list, t.key, t.skillLine)
        if plan and plan.reason == "cap" then
            table.remove(ns.db.plans, i)
        elseif plan then
            table.insert(plans, 1, { index = i, plan = plan })
        end
    end
    for _, p in ipairs(plans) do
        for _, s in ipairs(p.plan.steps) do
            out[#out + 1] = { recipe = s.recipeID, key = p.plan.key, count = s.make, plan = p.plan }
        end
    end
    return out, plans
end
