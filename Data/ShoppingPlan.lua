-- ShoppingPlan.lua: what the tracked crafts need: materials, what to create first, what to mail
-- where, and what to buy, with each character's stock handed out once.

local _, ns = ...

local TEXT = ns.UI.TEXT
local Color = ns.UI.ColorText

local Reagents = ns.Reagents

local ItemName = ns.UI.ItemLabel

local ShortName = ns.UI.ShortName

local MAX_DEPTH = 4

function ns.ItemPrice(itemID)
    local vendor = ns.Places.Vendors(itemID)
    if vendor and vendor.price then return vendor.price, "vendor" end
    local price = ns.AH.GetPrice(itemID)
    if price then return price, "ah" end
end

function ns.ShoppingPlan(list)
    local byKey = {}
    for _, entry in ipairs(list) do byKey[entry.key] = entry end
    local accountBank = ns.db.accountBank and ns.db.accountBank.items or {}

    local need, crafterOrder = {}, {}
    local allCrafts, plans = ns.SkillPlan.AllCrafts(list)
    for _, t in ipairs(allCrafts) do
        if byKey[t.key] then
            if not need[t.key] then
                need[t.key] = {}
                crafterOrder[#crafterOrder + 1] = t.key
            end
            for _, reagent in ipairs(Reagents(t.recipe)) do
                need[t.key][reagent[1]] = (need[t.key][reagent[1]] or 0) + reagent[2] * t.count
            end
        end
    end
    local first = {}
    for _, key in ipairs(crafterOrder) do
        local ids = {}
        for itemID in pairs(need[key]) do ids[#ids + 1] = itemID end
        table.sort(ids)
        for _, itemID in ipairs(ids) do first[#first + 1] = { key = key, itemID = itemID, count = need[key][itemID], parent = 0 } end
    end

    local plan = { crafts = {}, materials = {}, mail = {}, pickup = {}, buy = {}, creates = {}, allCrafts = allCrafts }
    local material, mailByPair, pickupBy, buyByItem, buyFor, createdBy = {}, {}, {}, {}, {}, {}
    local tally = {}
    local function Tally(key)
        tally[key] = tally[key] or { buy = 0, mail = 0, create = 0 }
        return tally[key]
    end

    local function Copy(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = v end
        return out
    end
    local stock = {}
    for _, entry in ipairs(list) do
        stock[entry.key] = {}
        for _, place in ipairs(ns.Bags.PLACES) do
            local data = entry.char[place.field]
            stock[entry.key][place.field] = Copy(data and data.items)
        end
    end
    local function Pooled(pools, itemID)
        local n = 0
        for _, place in ipairs(ns.Bags.PLACES) do n = n + (pools[place.field][itemID] or 0) end
        return n
    end
    local accountLeft = Copy(accountBank)
    local function Take(pool, itemID, wanted)
        local n = math.min(wanted, pool[itemID] or 0)
        if n > 0 then pool[itemID] = pool[itemID] - n end
        return n
    end
    local function InReach(key, itemID)
        local n = Pooled(stock[key], itemID) + (accountLeft[itemID] or 0)
        for _, entry in ipairs(ns.Bags.CanReach(list, byKey[key].char, key)) do
            n = n + Pooled(stock[entry.key], itemID)
        end
        return n
    end
    local function Pickup(key, itemID, count)
        local p = pickupBy[key]
        if not p then
            p = { who = ShortName(byKey[key].char, key), lines = {} }
            pickupBy[key] = p
            table.insert(plan.pickup, p)
        end
        table.insert(p.lines, ("%d × %s"):format(count, ItemName(itemID)))
    end

    local function Row(parent, itemID)
        local id = parent .. ":" .. itemID
        if not material[id] then
            material[id] = { itemID = itemID, parent = parent, need = 0, mail = 0, buy = 0, create = 0 }
        end
        return material[id]
    end

    local function ItemCheaper(itemID, count, reagents, crafts, makerKey)
        local itemPrice = ns.AH.GetPrice(itemID)
        if not itemPrice then return false end
        local cost = 0
        for _, reagent in ipairs(reagents) do
            local short = reagent[2] * crafts - InReach(makerKey, reagent[1])
            if short > 0 then
                local unit = ns.ItemPrice(reagent[1])
                if not unit then return false end
                cost = cost + short * unit
            end
        end
        return itemPrice * count < cost
    end

    local function Create(key, itemID, rest, nextRound)
        local best
        for _, maker in ipairs(ns.RecipesMaking(itemID)) do
            for _, entry in ipairs(ns.Bags.CanReach(list, byKey[key].char)) do
                local scan = ns.GetProfessionRecipes(entry.char, maker.skillLine)
                if scan and scan.known[maker.recipeID] then
                    local held = 0
                    for _, reagent in ipairs(Reagents(maker.recipeID, maker.skillLine)) do held = held + InReach(entry.key, reagent[1]) end
                    local score = entry.key == key and math.huge or held
                    if not best or score > best.score then
                        best = { entry = entry, recipeID = maker.recipeID, skillLine = maker.skillLine, score = score }
                    end
                end
            end
        end
        if not best then return 0 end
        local reagents = Reagents(best.recipeID, best.skillLine)
        local per = ns.MadePer(best.recipeID)
        local crafts = ns.CraftsFor(best.recipeID, rest)
        if ItemCheaper(itemID, rest, reagents, crafts, best.entry.key) then
            for _, reagent in ipairs(reagents) do
                if not ns.Places.Vendors(reagent[1]) then
                    crafts = math.min(crafts, math.floor(InReach(best.entry.key, reagent[1]) / reagent[2]))
                end
            end
        end
        if #reagents == 0 or crafts <= 0 then return 0 end
        for _, reagent in ipairs(reagents) do
            nextRound[#nextRound + 1] = { key = best.entry.key, itemID = reagent[1], count = reagent[2] * crafts, parent = itemID }
        end
        local id = best.entry.key .. ">" .. key .. ":" .. itemID
        local c = createdBy[id]
        if not c then
            c = { makerKey = best.entry.key, maker = ShortName(best.entry.char, best.entry.key), itemID = itemID, count = 0 }
            if best.entry.key ~= key then c.to = ShortName(byKey[key].char, key) end
            createdBy[id] = c
            table.insert(plan.creates, c)
        end
        c.count = c.count + crafts * per
        return math.min(rest, crafts * per)
    end

    local function Round(needs, depth)
        local left = {}
        for i, n in ipairs(needs) do
            Row(n.parent, n.itemID).need = Row(n.parent, n.itemID).need + n.count
            local rest = n.count - Take(stock[n.key].bags, n.itemID, n.count)
            rest = rest - Take(stock[n.key].bank, n.itemID, rest)
            local fromMail = Take(stock[n.key].mail, n.itemID, rest)
            if fromMail > 0 then
                Pickup(n.key, n.itemID, fromMail)
                Tally(n.key).mail = Tally(n.key).mail + 1
            end
            left[i] = rest - fromMail - Take(accountLeft, n.itemID, rest - fromMail)
        end
        local nextRound = {}
        for i, n in ipairs(needs) do
            local rest, m, itemID = left[i], Row(n.parent, n.itemID), n.itemID
            local crafter = byKey[n.key].char
            if rest > 0 then
                local others = {}
                for _, entry in ipairs(ns.Bags.CanReach(list, crafter, n.key)) do
                    for _, place in ipairs(ns.Bags.PLACES) do
                        local pool = stock[entry.key][place.field]
                        if (pool[itemID] or 0) > 0 then others[#others + 1] = { entry = entry, pool = pool, from = place.from or "" } end
                    end
                end
                table.sort(others, function(a, b) return a.pool[itemID] > b.pool[itemID] end)
                for _, o in ipairs(others) do
                    if rest <= 0 then break end
                    local got = Take(o.pool, itemID, rest)
                    rest = rest - got
                    m.mail = m.mail + got
                    Tally(n.key).mail = Tally(n.key).mail + 1
                    local pair = o.entry.key .. ">" .. n.key
                    if not mailByPair[pair] then
                        mailByPair[pair] = { from = ShortName(o.entry.char, o.entry.key), to = ShortName(crafter, n.key), lines = {} }
                        table.insert(plan.mail, mailByPair[pair])
                    end
                    table.insert(mailByPair[pair].lines, ("%d × %s%s"):format(got, ItemName(itemID), o.from))
                end
            end
            if rest > 0 and depth < MAX_DEPTH then
                local made = Create(n.key, itemID, rest, nextRound)
                if made > 0 then
                    rest = rest - made
                    m.create = m.create + made
                    Tally(n.key).create = Tally(n.key).create + 1
                end
            end
            if rest > 0 then
                m.buy = m.buy + rest
                Tally(n.key).buy = Tally(n.key).buy + 1
                buyByItem[itemID] = (buyByItem[itemID] or 0) + rest
                buyFor[itemID] = buyFor[itemID] or {}
                buyFor[itemID][n.key] = true
            end
        end
        if #nextRound > 0 then Round(nextRound, depth + 1) end
    end
    Round(first, 1)

    local status = {}
    for key, t in pairs(tally) do
        if t.buy > 0 then
            status[key] = { "buy " .. ns.UI.Count(t.buy, "item", "items"), TEXT.amber }
        elseif t.create > 0 then
            status[key] = { "create first", TEXT.amber }
        elseif t.mail > 0 then
            status[key] = { "after mail", TEXT.amber }
        end
    end
    for _, key in ipairs(crafterOrder) do status[key] = status[key] or { "ready", TEXT.green } end
    for _, c in ipairs(plan.creates) do c.name = ItemName(c.itemID) end

    -- Only the crafter's own window scan says a recipe is unlearned; a borrowed list can't tell.
    local function NeedsRecipe(t, entry)
        local scans = entry and entry.char.recipes or {}
        for _, scan in pairs(scans) do
            if scan.known and scan.known[t.recipe] then return false end
        end
        for _, scan in pairs(scans) do
            if scan.scanned and scan.unknown and scan.unknown[t.recipe] then return true end
        end
        return false
    end
    local recipeItems = {}
    local function NeedRecipeItem(key, recipeID)
        local itemID = ns.RecipeItem(recipeID)
        if itemID then
            recipeItems[key] = recipeItems[key] or {}
            recipeItems[key][itemID] = (recipeItems[key][itemID] or 0) + 1
        end
    end

    for index, t in ipairs(ns.db.tracked) do
        local entry = byKey[t.key]
        local recipe = ns.db.recipes[t.recipe]
        local s = status[t.key] or { "", TEXT.muted }
        if NeedsRecipe(t, entry) then
            s = { "learn it first", TEXT.amber }
            NeedRecipeItem(t.key, t.recipe)
        end
        table.insert(plan.crafts, { index = index, track = t, name = ns.RecipeName(t.recipe), icon = recipe and recipe.icon,
                                    crafter = entry and ShortName(entry.char, entry.key) or (t.key .. Color(TEXT.muted, " (hidden)")),
                                    status = s[1], statusColor = s[2] })
    end
    for _, p in ipairs(plans) do
        local skillPlan, entry = p.plan, byKey[p.plan.key]
        local s = status[skillPlan.key] or { "", TEXT.muted }
        local prof
        for _, pr in ipairs(skillPlan.char.professions or {}) do
            if pr.skillLine == skillPlan.skillLine then prof = pr end
        end
        for _, step in ipairs(skillPlan.steps) do
            if step.learnFrom == "vendor" then NeedRecipeItem(skillPlan.key, step.recipeID) end
        end
        table.insert(plan.crafts, 1, { planIndex = p.index, skillPlan = skillPlan, icon = prof and prof.icon,
                                    name = ("%s to %d, %s"):format(skillPlan.name, skillPlan.target,
                                                                   ns.UI.Count(skillPlan.crafts, "craft", "crafts")),
                                    crafter = ShortName(entry.char, entry.key), status = s[1], statusColor = s[2] })
    end

    local function HeldBy(itemID)
        return (ns.Bags.HeldText(itemID, list, { empty = Color(TEXT.muted, "none") }))
    end

    for _, m in pairs(material) do
        m.name = ItemName(m.itemID)
        m.where = HeldBy(m.itemID)
        if m.buy > 0 then
            m.missing, m.missingColor = "buy " .. m.buy, TEXT.amber
        elseif m.create > 0 then
            m.missing, m.missingColor = "create " .. m.create, TEXT.amber
        elseif m.mail > 0 then
            m.missing, m.missingColor = "mail " .. m.mail, TEXT.amber
        else
            m.missing, m.missingColor = "-", TEXT.muted
        end
    end

    local recipeRows = {}
    for key, items in pairs(recipeItems) do
        local reach = ns.Bags.CanReach(list, byKey[key].char)
        for itemID, wanted in pairs(items) do
            local missing = math.max(0, wanted - ns.Bags.Holders(itemID, reach))
            if missing > 0 then
                buyByItem[itemID] = (buyByItem[itemID] or 0) + missing
                buyFor[itemID] = buyFor[itemID] or {}
                buyFor[itemID][key] = true
            end
            local row = recipeRows[itemID]
            if not row then
                row = { itemID = itemID, need = 0, mail = 0, buy = 0, recipe = true, depth = 0 }
                recipeRows[itemID] = row
                table.insert(plan.materials, row)
            end
            row.need, row.buy = row.need + wanted, row.buy + missing
        end
    end
    for itemID, row in pairs(recipeRows) do
        row.name, row.where = ItemName(itemID), HeldBy(itemID)
        row.missing, row.missingColor = row.buy > 0 and ("buy " .. row.buy) or "learn it", TEXT.amber
    end
    table.sort(plan.materials, function(a, b) return a.name < b.name end)
    local byName, under = {}, {}
    for _, m in pairs(material) do
        if m.parent == 0 then byName[#byName + 1] = m else under[m.parent] = under[m.parent] or {} table.insert(under[m.parent], m) end
    end
    local function Emit(m, depth)
        m.depth = depth
        table.insert(plan.materials, m)
        local children = under[m.itemID]
        under[m.itemID] = nil
        table.sort(children or {}, function(a, b) return a.name < b.name end)
        for _, child in ipairs(children or {}) do Emit(child, depth + 1) end
    end
    table.sort(byName, function(a, b) return a.name < b.name end)
    for _, m in ipairs(byName) do Emit(m, 0) end

    plan.stock = {}
    local forStock = {}
    for itemID, s in pairs(ns.db.stock) do
        local held = accountLeft[itemID] or 0
        for _, pools in pairs(stock) do held = held + Pooled(pools, itemID) end
        plan.stock[itemID] = { have = held, short = math.max(0, s.target - held) }
        if s.buy and s.target > held then
            forStock[itemID] = s.target - held
            buyByItem[itemID] = (buyByItem[itemID] or 0) + forStock[itemID]
        end
    end

    for itemID, count in pairs(buyByItem) do
        local who = {}
        for key in pairs(buyFor[itemID] or {}) do who[#who + 1] = key end
        table.sort(who)
        local vendor, favor = ns.Places.Vendors(itemID), ns.Favor.IsItem(itemID)
        local buyCount, buyCost = count, nil
        if vendor and not favor then buyCount, buyCost = ns.Places.WholeStacks(vendor, count) end
        table.insert(plan.buy, { itemID = itemID, name = ItemName(itemID), count = count, buyCount = buyCount, buyCost = buyCost,
                                 vendor = vendor, favor = favor, forKeys = who, stock = forStock[itemID] })
    end
    table.sort(plan.buy, function(a, b) return a.name < b.name end)
    return plan
end
