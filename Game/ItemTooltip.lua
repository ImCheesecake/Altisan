-- ItemTooltip.lua: Altisan's lines in item tooltips: who to keep a crafting item for,
-- tracked crafts short of it, how many the account holds. Recipe items say who can learn them.

local _, ns = ...

local Tip = {}
ns.ItemTooltip = Tip

local MAX_SHIFT = 3
local MAX_PLACES = 2
local MAX_LATER = 2

local INDENT = "   "
-- ns.UI loads after this file, so both are looked up when called.
local function Color(hex, text) return ns.UI.ColorText(hex, text) end
local function ShortName(...) return ns.UI.ShortName(...) end

local function HasOwnUse(itemID)
    local getSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
    if not getSpell then return false end
    local ok, spell = pcall(getSpell, itemID)
    return ok and spell ~= nil
end

local function TrackedLines(itemID, list)
    local byKey = {}
    for _, entry in ipairs(list) do byKey[entry.key] = entry end
    local lines = {}
    for _, c in ipairs(ns.Gathering.Crafts(itemID, list)) do
        local entry = byKey[c.key]
        local short = c.need - ns.Bags.Held(entry.char, itemID)
        if short > 0 and #lines < 2 then
            lines[#lines + 1] = ShortName(entry) .. Color(ns.UI.TEXT.amber, (" needs %d more for %d × %s"):format(
                short, c.count, c.name))
        end
    end
    return lines
end

local function ToGo(profName, skill, gap)
    if gap == 0 then return Color(ns.UI.TEXT.light, ("%s %d, "):format(profName, skill)) .. Color(ns.UI.GAME.tooltipGreen, "can learn now") end
    return Color(ns.UI.TEXT.light, ("%s %d, %d to go"):format(profName, skill, gap))
end

local function SkillNote(recipeID, prof)
    local required, gap = ns.SkillGap(recipeID, prof.skillLine, prof.skill)
    if gap == 0 then return Color(ns.UI.GAME.tooltipGreen, ": can learn now") end
    if not required then return Color(ns.UI.TEXT.light, ": required skill unknown") end
    return Color(ns.UI.TEXT.light, (": %s %d"):format(prof.name, required))
end

local function LaterLines(farther)
    local out, seen = {}, {}
    for _, u in ipairs(farther) do
        if not seen[u.entry.key] and #out < MAX_LATER then
            seen[u.entry.key] = true
            local required, gap = ns.SkillGap(u.past[1], u.prof.skillLine, u.prof.skill)
            if required then
                out[#out + 1] = { ShortName(u.entry) .. Color(ns.UI.TEXT.white, (" can use it at %d"):format(required)),
                                  ToGo(u.prof.name, u.prof.skill or 0, gap) }
            else
                out[#out + 1] = { ShortName(u.entry) .. Color(ns.UI.TEXT.white, " can use it later"),
                                  Color(ns.UI.TEXT.light, "required skill unknown") }
            end
        end
    end
    return out
end

function Tip.Lines(itemID, list, withNames)
    local lines = {}
    local function Line(text, right) lines[#lines + 1] = right and (text .. "\t" .. right) or text end

    for _, t in ipairs(ns.ItemUses.Teaches(itemID) or {}) do
        local name = ns.RecipeName(t.recipe, t.prof)
        local any = false
        for _, entry in ipairs(list) do
            for _, prof in ipairs(entry.char.professions or {}) do
                if prof.skillLine == t.prof then
                    any = true
                    local scan = ns.GetProfessionRecipes(entry.char, t.prof)
                    local skill = prof.skill or 0
                    local required, gap = ns.SkillGap(t.recipe, t.prof, skill)
                    if scan and scan.known[t.recipe] then
                        Line(ShortName(entry), Color(ns.UI.TEXT.light, "already knows it"))
                    elseif not ns.HasFullList(scan) then
                        Line(ShortName(entry), Color(ns.UI.TEXT.light, ("open their %s window once"):format(prof.name)))
                    elseif not scan.unknown[t.recipe] then
                        -- Never listed in their window: not taught on Forever, so no line.
                    elseif not required then
                        Line(ShortName(entry) .. Color(ns.UI.TEXT.white, " can learn it"), Color(ns.UI.TEXT.light, "required skill unknown"))
                    elseif gap > 0 then
                        Line(ShortName(entry) .. Color(ns.UI.TEXT.white, (" can learn it at %d"):format(required)),
                             ToGo(prof.name, skill, gap))
                    else
                        Line(ShortName(entry) .. Color(ns.UI.GAME.tooltipGreen, " can learn it now"), Color(ns.UI.TEXT.light, ("%s %d"):format(prof.name, skill)))
                    end
                end
            end
        end
        if not any then
            Line(Color(ns.UI.TEXT.white, "Teaches " .. name), Color(ns.UI.TEXT.light, "nobody here has " .. ns.ProfessionName(t.prof)))
        end
    end

    local users, _, _, farther = ns.ItemUses.Analyze(itemID, list)
    if not users then return lines end

    local people, byKey = {}, {}
    local function AddUse(u)
        local p = byKey[u.entry.key]
        if not p then
            p = { entry = u.entry, profs = {}, uses = {} }
            byKey[u.entry.key] = p
            people[#people + 1] = p
        end
        p.profs[#p.profs + 1] = u.prof.name
        p.uses[#p.uses + 1] = u
    end
    for _, u in ipairs(users) do AddUse(u) end
    local soon = #people
    for _, u in ipairs(farther) do AddUse(u) end

    if soon > 0 then
        local names = {}
        for i = 1, soon do names[i] = ShortName(people[i].entry) end
        Line(Color(ns.UI.GAME.tooltipGreen, "Keep it for ") .. ns.UI.JoinNames(names, nil, ns.UI.GAME.tooltipGreen))
    elseif #farther > 0 then
        for _, pair in ipairs(LaterLines(farther)) do Line(pair[1], pair[2]) end
    elseif not HasOwnUse(itemID) then
        Line(Color(ns.UI.TEXT.light, "No use for your characters' crafting"))
    end

    for _, text in ipairs(TrackedLines(itemID, list)) do Line(text) end

    if withNames and #people > 0 then
        for i = 1, math.min(#people, MAX_SHIFT) do
            local p = people[i]
            Line(" ")
            Line(ShortName(p.entry) .. Color(ns.UI.TEXT.white, ": " .. table.concat(p.profs, ", ")))
            local rows = {}
            for _, u in ipairs(p.uses) do
                for _, id in ipairs(u.known) do rows[#rows + 1] = { name = ns.RecipeName(id, u.prof.skillLine), note = "" } end
                for _, group in ipairs({ u.later, u.past }) do
                    for _, id in ipairs(group) do
                        rows[#rows + 1] = { name = ns.RecipeName(id, u.prof.skillLine), note = SkillNote(id, u.prof) }
                    end
                end
            end
            for r = 1, math.min(#rows, MAX_SHIFT) do Line(INDENT .. Color(ns.UI.TEXT.light, rows[r].name) .. rows[r].note) end
            if #rows > MAX_SHIFT then Line(INDENT .. Color(ns.UI.TEXT.light, ("and %d more on Coverage"):format(#rows - MAX_SHIFT))) end
        end
        if #people > MAX_SHIFT then Line(Color(ns.UI.TEXT.light, ("and %d more characters on Coverage"):format(#people - MAX_SHIFT))) end
    end

    if ns.db.tooltips.counts then
        local held, _, total = ns.Bags.HeldText(itemID, list, { max = MAX_PLACES, more = true })
        if total > 0 then
            if withNames then Line(" ") end
            Line(Color(ns.UI.TEXT.white, "On your account: " .. total), Color(ns.UI.TEXT.light, held))
        end
    end

    if not withNames and #people > 0 then Line(Color(ns.UI.TEXT.light, "Shift: who uses it and for what")) end
    return lines
end

local function OwnTooltip(tooltip)
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    return owner and owner.redrawTooltip and owner or nil
end

local function OnItemTooltip(tooltip, data)
    if ns.UI.drawingItem or not ns.db then return end
    -- The game rebuilds a tooltip when item data arrives (TOOLTIP_DATA_UPDATE) or on RefreshData,
    -- wiping our recipe tooltip's lines: redraw it next frame. UI.drawingItem stops it looping.
    local owner = OwnTooltip(tooltip)
    if owner then
        C_Timer.After(0, function()
            if GameTooltip:IsOwned(owner) then owner.redrawTooltip(owner) end
        end)
        return
    end
    if not ns.db.tooltips.items then return end
    if ns.db.tooltips.shiftOnly and not IsShiftKeyDown() then return end
    -- The post-call fires for comparison tooltips too: only the main one and clicked links.
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if not itemID then return end
    local me = ns.CurrentCharacter()
    local list = me and ns.Bags.CanReach(ns.VisibleCharacters(), me) or ns.VisibleCharacters()
    local lines = Tip.Lines(itemID, list, IsShiftKeyDown())
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    ns.UI.TipLine(tooltip, "Altisan", "gold")
    for _, line in ipairs(lines) do
        local left, right = line:match("^(.-)\t(.*)$")
        if left then
            ns.UI.TipDoubleLine(tooltip, left, right)
        else
            -- No wrapping: a wrapped line runs into the next one.
            ns.UI.TipLine(tooltip, line, nil, false)
        end
    end
    -- Other addons' lines that follow often start without a gap of their own.
    tooltip:AddLine(" ")
end

function Tip.Init()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
        return
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)

    -- The game never redraws ItemRefTooltip on Shift itself.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    watcher:SetScript("OnEvent", function(_, _, key)
        if not (key and key:find("SHIFT")) then return end
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tooltip and tooltip:IsShown() and tooltip.RefreshData and tooltip.GetItem
                and tooltip:GetItem() and not OwnTooltip(tooltip) then
                tooltip:RefreshData()
            end
        end
    end)
end
