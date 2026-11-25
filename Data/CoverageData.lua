-- CoverageData.lua: how much of each profession the account knows, and the recipes nobody knows
-- yet, worked out for the Coverage page.

local _, ns = ...

local Data = {}
ns.CoverageData = Data

function Data.Professions(list)
    local out, byLine = ns.ProfessionHolders(list, function(line) return not ns.GATHERING[line] end)
    for _, p in ipairs(out) do
        p.secondary = ns.SECONDARY[p.skillLine] ~= nil or p.holders[1].prof.kind == "secondary"
    end
    for line, name in pairs(ns.CRAFTING) do
        if not byLine[line] then
            local p = { skillLine = line, name = name, holders = {} }
            byLine[line] = p
            out[#out + 1] = p
        end
    end

    for _, p in ipairs(out) do
        local ids, known, total, ignored = {}, 0, 0, 0
        for _, h in ipairs(p.holders) do
            if h.scan then
                if ns.HasFullList(h.scan) then p.scanned = true else p.atLogin = true end
                local learnable = ns.LearnableFilter(h.scan)
                for _, id in ipairs(h.scan.order or {}) do
                    if learnable(id) then
                        local skip = ns.Ignore.Is(id)
                        if ids[id] == nil then
                            ids[id] = false
                            if skip then ignored = ignored + 1 else total = total + 1 end
                        end
                        if h.scan.known[id] and not ids[id] then
                            ids[id] = true
                            if not skip then known = known + 1 end
                        end
                    end
                end
            end
        end
        if not p.scanned then total = 0 end
        p.ids, p.known, p.total, p.ignored = ids, known, total, ignored
    end

    local function Rank(p)
        if p.secondary then return 1 end
        return #p.holders > 0 and 2 or 3
    end
    table.sort(out, function(a, b)
        if Rank(a) ~= Rank(b) then return Rank(a) < Rank(b) end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function Data.BestHolder(p) return ns.BestHolder(p.holders, { scanned = true, played = true }) end

function Data.Recipes(p, search)
    local groups = { ready = {}, needs = {}, known = {}, ignored = {} }
    local best = Data.BestHolder(p)
    for id in pairs(p.ids or {}) do
        local name = ns.RecipeName(id, p.skillLine)
        if search == "" or name:lower():find(search, 1, true) then
            local item = { id = id, name = name, knowers = {} }
            if ns.Ignore.Is(id) then
                item.state = "ignored"
                table.insert(groups.ignored, item)
            else
                for _, h in ipairs(p.holders) do
                    if h.scan and h.scan.known[id] then table.insert(item.knowers, h) end
                end
                if #item.knowers > 0 then
                    item.state = "known"
                    table.insert(groups.known, item)
                else
                    item.required, item.borrowed = ns.RequiredSkill(id, p.skillLine)
                    item.best = best
                    if item.required and best and (best.prof.skill or 0) >= item.required then
                        item.state = "ready"
                        table.insert(groups.ready, item)
                    else
                        item.state = "needs"
                        table.insert(groups.needs, item)
                    end
                end
            end
        end
    end
    local function ByRequirement(a, b)
        local ra, rb = a.required or math.huge, b.required or math.huge
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end
    table.sort(groups.ready, ByRequirement)
    table.sort(groups.needs, ByRequirement)
    table.sort(groups.known, function(a, b) return a.name < b.name end)
    table.sort(groups.ignored, function(a, b) return a.name < b.name end)
    return groups
end

function Data.OnlyKnownBy(p)
    local out = {}
    for _, h in ipairs(p.holders) do
        if h.scan then
            local count = 0
            for id in pairs(h.scan.known) do
                if p.ids[id] ~= nil then
                    local others = false
                    for _, other in ipairs(p.holders) do
                        if other ~= h and other.scan and other.scan.known[id] then others = true break end
                    end
                    if not others then count = count + 1 end
                end
            end
            out[#out + 1] = { holder = h, count = count }
        end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end
