-- Legacy.lua: Forever's profession Legacy challenges, read from the achievements (earned once per
-- account). Without them, falls back to 150/225/300 and guesses "earned" from the skill.

local _, ns = ...

local Legacy = {}
ns.Legacy = Legacy

local SKILL_CRITERIA = 7
local FALLBACK = { 150, 225, 300 }
local RETRY = 30

local challenges
local lastTry

-- Forever's challenges name the child line (2948 for Tailoring), not the parent (197).
local function ProfessionOf(skillLine)
    if ns.CRAFTING[skillLine] then return skillLine end
    local info = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
        and C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
    local parent = info and info.parentProfessionID
    return parent and ns.CRAFTING[parent] and parent or nil
end

local function Read()
    if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo
            and GetAchievementCriteriaInfo and GetAchievementNumCriteria) then
        return nil
    end
    local found
    for _, category in ipairs(GetCategoryList() or {}) do
        for index = 1, (GetCategoryNumAchievements(category)) or 0 do
            local id, _, _, completed = GetAchievementInfo(category, index)
            -- Asking for criteria an achievement lacks is an error, so count first.
            local numCriteria = id and GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0
            if id and numCriteria >= 1 then
                -- The 8th return (asset) is the skill line for type 7.
                local _, kind, _, _, required, _, _, asset = GetAchievementCriteriaInfo(id, 1)
                local profession = kind == SKILL_CRITERIA and asset and ProfessionOf(asset)
                if profession and required then
                    found = found or {}
                    found[profession] = found[profession] or {}
                    table.insert(found[profession], { id = id, at = required, earned = completed and true or false })
                end
            end
        end
    end
    for _, list in pairs(found or {}) do
        table.sort(list, function(a, b) return a.at < b.at end)
    end
    return found
end

local function Challenges()
    if challenges then return challenges end
    local now = GetTime and GetTime() or 0
    if lastTry and now - lastTry < RETRY then return nil end
    lastTry = now
    local ok, read = pcall(Read)
    challenges = ok and read or nil
    Legacy.lastError = not ok and read or nil
    return challenges
end

function Legacy.Forget()
    challenges, lastTry = nil, nil
end

function Legacy.Source()
    return Challenges() and "game" or "fallback"
end

function Legacy.For(skillLine)
    local read = Challenges()
    if read and read[skillLine] then return read[skillLine] end
    local list = {}
    for i, at in ipairs(FALLBACK) do list[i] = { at = at } end
    return list
end

function Legacy.Next(skillLine, skill)
    skill = skill or 0
    for _, challenge in ipairs(Legacy.For(skillLine)) do
        local earned = challenge.earned
        if earned == nil then earned = skill >= challenge.at end
        if not earned then return challenge.at, math.max(0, challenge.at - skill) end
    end
end

function Legacy.DebugLines()
    local lines = {}
    local read = Challenges() or {}
    for line, name in pairs(ns.CRAFTING) do
        local parts = {}
        for _, c in ipairs(read[line] or {}) do
            parts[#parts + 1] = ("%d (%d)%s"):format(c.at, c.id, c.earned and " earned" or "")
        end
        lines[#lines + 1] = ("    %s: %s"):format(name, #parts > 0 and table.concat(parts, ", ") or "none found")
    end
    table.sort(lines)
    table.insert(lines, 1, "  Legacy: " .. (Legacy.Source() == "game" and "read from the game's achievements"
                                            or "not found in the achievements, using 150/225/300"))
    return lines
end

function Legacy.BestPerProfession(list)
    local best = {}
    for _, p in ipairs(ns.ProfessionHolders(list, function(line) return ns.CRAFTING[line] end)) do
        best[p.skillLine] = ns.BestHolder(p.holders)
    end
    return best
end
