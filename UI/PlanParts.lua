-- PlanParts.lua: a plan to the next rank on screen: the card beside Blizzard's window, the plan in
-- Altisan's pane (one line, or in full with what the account holds) and a step in full.

local _, ns = ...
local UI = ns.UI

UI.STEP_PAD = 3
local PAD = UI.STEP_PAD
local COUNT_WIDTH = 30

local function SideBySide(left, right, x, y, width)
    left:SetWidth(0)
    right:SetWidth(0)
    local lw, rw = left:GetStringWidth(), right:GetStringWidth()
    left:ClearAllPoints()
    right:ClearAllPoints()
    left:SetPoint("TOPLEFT", x, y)
    if lw + 10 + rw <= width then
        right:SetJustifyH("RIGHT")
        right:SetPoint("TOPRIGHT", left:GetParent(), "TOPLEFT", x + width, y)
        return math.max(left:GetStringHeight(), right:GetStringHeight())
    end
    left:SetWidth(width)
    right:SetJustifyH("LEFT")
    right:SetWidth(width - 10)
    right:SetPoint("TOPLEFT", x + 10, y - left:GetStringHeight() - 1)
    return left:GetStringHeight() + 1 + right:GetStringHeight()
end

function UI.StepRow(parent)
    local b = UI.MakeSelectable(CreateFrame("Button", nil, parent))
    b.tracked = UI.TrackedFill(b)
    b.count = UI.Text(b, "GameFontHighlightSmall", 2)
    b.count:SetJustifyH("RIGHT")
    b.text:SetFontObject("GameFontHighlightSmall")
    b.text:SetSpacing(2)
    b.text:SetWordWrap(true)
    b.range = UI.Text(b, "GameFontHighlightSmall", 2)
    b.range:SetJustifyH("RIGHT")
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        UI.RowTooltip(self)
        self.tip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function b:Set(spec, width)
        self.tip = spec.tip
        self:SetSelected(spec.tint == "selected", true)
        self.tracked:SetShown(spec.tint == "tracked")
        self:SetWidth(width + 2 * PAD)
        self.count:SetWidth(0)
        self.count:SetText(spec.count)
        local countWidth = math.max(COUNT_WIDTH, math.ceil(self.count:GetStringWidth()))
        self.count:SetWidth(countWidth)
        self.range:SetWidth(0)
        self.range:SetText(UI.Soft(spec.range))
        local nameWidth = width - countWidth - 8 - self.range:GetStringWidth() - 8
        self.text:SetWidth(nameWidth)
        self.text:SetText(spec.row)
        self.count:ClearAllPoints()
        self.count:SetPoint("TOPLEFT", PAD, -2)
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", PAD + countWidth + 8, -2)
        self.range:ClearAllPoints()
        self.range:SetPoint("TOPRIGHT", -PAD, -2)
        local height = self.text:GetStringHeight() + 4
        self:SetHeight(height)
        return height
    end
    return b
end

function UI.StepBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.left = UI.Text(f, "GameFontHighlightSmall")
    f.right = UI.Text(f, "GameFontHighlightSmall")
    f.right:SetJustifyH("RIGHT")
    f.holder, f.fill = UI.SkillBar(f, 100)
    f.ticks = {}
    function f:Set(spec, width)
        self.left:SetText(UI.Soft(spec.left or ""))
        self.right:SetText(UI.Gold(spec.right or ""))
        local labels = SideBySide(self.left, self.right, 0, 0, width)
        self:SetSize(width, labels + 8)
        self.holder:SetWidth(width)
        self.holder:ClearAllPoints()
        self.holder:SetPoint("TOPLEFT", 0, -(labels + 4))
        self.fill:SetMinMaxValues(0, spec.max)
        self.fill:SetValue(spec.bar)
        local ticks = type(spec.tick) == "table" and spec.tick or { spec.tick }
        for i, at in ipairs(ticks) do
            local tick = self.ticks[i]
            if not tick then
                tick = self.holder:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(unpack(UI.C.stepEnd))
                tick:SetSize(2, 10)
                self.ticks[i] = tick
            end
            tick:ClearAllPoints()
            tick:SetPoint("CENTER", self.holder, "LEFT", width * math.min(at, spec.max) / spec.max, 0)
            tick:Show()
        end
        for i = #ticks + 1, #self.ticks do self.ticks[i]:Hide() end
        return labels + 8
    end
    return f
end

local function PlanButton(blocks, plan, gap, remake)
    local SP = ns.SkillPlan
    local tracked = SP.Tracked(plan.key, plan.skillLine) ~= nil
    local buttons = { {
        label = tracked and "Remove plan from shopping list" or "Add plan to shopping list",
        kind = tracked and "primary" or "quiet",
        onClick = function() SP.Toggle(plan.key, plan.skillLine) end,
        tip = tracked and "On the Shopping page. It shrinks as the skill goes up and leaves at the target. A click takes it off now."
            or ("Puts every step's materials on the Shopping page: who can mail what to %s, what to make first and what to buy.")
                :format(UI.CharName(plan.char, plan.key)),
    } }
    if remake then
        buttons[2] = { label = "Make a new plan", onClick = function() SP.Forget(plan.key, plan.skillLine) end,
                       tip = "Replaces this plan with one from your skill and what your characters hold now." }
    end
    blocks:Buttons(buttons, gap)
end

local function Flags(plan)
    local learns, odds = false, false
    for _, step in ipairs(plan.steps) do
        learns = learns or step.learn ~= nil
        odds = odds or step.to > step.yellow
    end
    return learns, odds
end

local function LearnHint(plan)
    local from = {}
    for _, step in ipairs(plan.steps) do
        if step.learn then from[step.learnFrom or "trainer"] = true end
    end
    if from.vendor and from.trainer then return "Tinted: learn or buy the recipe when you get there." end
    if from.vendor then return "Tinted: buy the recipe from a vendor when you get there." end
    return "Tinted: learn it from a trainer when you get there."
end

local function OddsNote(blocks)
    blocks:Text(UI.ColorText(UI.TEXT.muted, "Counts are averages: yellow and green don't always give a point."), 6)
end

local function RankBlocks(blocks, plan, color, redraw)
    local n = ns.SkillPlan.NextRank(plan)
    local line = ("%d is the most %s allows. "):format(plan.target, plan.rank)
    if n.book then
        line = line .. ("Buy %s%s and use it to go on."):format(UI.ItemLabel(n.book, redraw),
            n.price and (", " .. UI.Money(n.price) .. ",") or "")
    else
        line = line .. ("Learn %s %s from a %s to go on."):format(plan.nextRank, plan.name, n.from)
    end
    blocks:Text(color(line), 4)
    local nearest = { unpack(n.places, 1, math.min(#n.places, UI.SHOWN_PLACES)) }
    if #nearest > 0 then blocks[#blocks + 1] = { places = nearest, total = #nearest, gap = 4 } end
end

local function NothingLine(at)
    return ("Nothing you know or can learn or buy gives skill at %d."):format(at)
end

local function LearnWhen(step) return step.learn == "now" and "now" or ("at %d"):format(step.learn) end

local function HaveNeedLines(blocks, plan, steps, redraw)
    for i, e in ipairs(ns.SkillPlan.HaveNeed(plan, steps)) do
        local rest = {}
        if e.make > 0 then
            local who = e.maker.key == plan.key and "you make %d"
                or (UI.CharName(ns.db.characters[e.maker.key], e.maker.key) .. " makes %d")
            rest[#rest + 1] = who:format(e.make)
        end
        if e.buy > 0 then rest[#rest + 1] = ("buy %d"):format(e.buy) end
        blocks:Pair(("%d / %d %s"):format(e.have, e.need, UI.ItemLabel(e.itemID, redraw)),
                    UI.Soft(#rest > 0 and table.concat(rest, ", ") or "all held"), i == 1 and 4 or 2, e.itemID)
    end
end

function UI.PlanCardBlocks(blocks, plan, opts)
    local SP = ns.SkillPlan
    local corner = opts.corner and UI.ColorText(UI.TEXT.muted, opts.corner)
    if plan.reason == "cap" then
        if not plan.nextRank then return end
        blocks[#blocks + 1] = { text = UI.Gold(("%s to %d"):format(plan.name, plan.target + 75)), font = "GameFontNormal",
                                right = corner, gap = 0 }
        RankBlocks(blocks, plan, UI.Light, opts.redraw)
        return
    end
    if plan.reason == "scan" or #plan.steps == 0 then return end
    local open = {
        label = "Open plan in Altisan", onClick = opts.onOpen,
        tip = "What your characters hold of each material, where to learn each recipe, and Add plan to shopping list.",
    }
    blocks:Fold(UI.Gold(("%s to %d"):format(plan.name, plan.target)), corner, not opts.folded, opts.onFold)
    if opts.folded then
        local first = plan.steps[1]
        blocks:Text(UI.Light(("%s. Next: %d × %s."):format(SP.Size(plan), first.make,
            ns.RecipeName(first.recipeID, plan.skillLine) or "?")), 4)
        blocks:Buttons({ open }, 8)
        return
    end
    blocks:Heading("Make", UI.Count(plan.crafts, "craft", "crafts"))
    local learns, odds = Flags(plan)
    for _, step in ipairs(plan.steps) do
        local count, range = SP.RowParts(step)
        local name = ns.RecipeName(step.recipeID, plan.skillLine) or "?"
        local hint = opts.rowHint and opts.rowHint(step)
        blocks:Row(count, UI.Light(name), range, opts.onStep and function() opts.onStep(step) end,
                   step.learn and "selected" or nil, function(tip)
                UI.TipLine(tip, SP.StepLine(plan, step, name), "white", true)
                if step.learn then
                    UI.TipLine(tip, step.learnFrom == "vendor" and "Buy the recipe from a vendor first."
                        or "Learn it from a trainer first.", "light")
                end
                if hint then UI.TipLine(tip, hint, "light") end
            end)
    end
    if learns then blocks:Text(UI.ColorText(UI.TEXT.muted, LearnHint(plan)), 4) end
    blocks:Heading("Materials")
    for i, m in ipairs(SP.Materials(plan)) do
        blocks:Pair(("%d × %s"):format(m[2], UI.ItemLabel(m[1], opts.redraw)), "", i == 1 and 4 or 2, m[1])
    end
    if odds then OddsNote(blocks) end
    blocks:Buttons({ open }, 8)
end

function UI.PlanSummaryBlocks(blocks, plan, opts)
    local SP = ns.SkillPlan
    if plan.reason == "scan" then return end
    if plan.reason == "cap" then
        if not plan.nextRank then return end
        blocks:Heading(("Plan to %d"):format(plan.target + 75))
        RankBlocks(blocks, plan, UI.Soft)
        return
    end
    if #plan.steps == 0 then
        blocks:Heading(("Plan to %d"):format(plan.target))
        blocks:Text(UI.Soft(NothingLine(plan.skill)), 4)
        return
    end
    local first = plan.steps[1]
    blocks:Heading(("Plan to %d"):format(plan.target), SP.Size(plan))
    blocks:Text(UI.Light(("Next: %d × %s, %d to %d."):format(first.make, ns.RecipeName(first.recipeID, plan.skillLine) or "?",
        first.from, first.to)), 4)
    blocks:Buttons({ { label = "Show plan", onClick = opts.onShow,
        tip = "The plan's steps in place of the recipe list, with what your characters hold and where to learn each recipe." } }, 8)
end

function UI.PlanPaneBlocks(blocks, plan, opts)
    local ticks = {}
    for i, step in ipairs(plan.steps) do ticks[i] = step.to end
    blocks:Text(UI.Gold(("Plan to %d"):format(plan.target)), 0, "GameFontNormalLarge")
    blocks:Bar(plan.skill, plan.target, ticks, ("%s %d / %d"):format(plan.name, plan.skill, plan.target))
    blocks:Heading(#plan.steps == 1 and "Materials" or ("Materials for all %d steps"):format(#plan.steps), "have / need")
    HaveNeedLines(blocks, plan, plan.steps, opts.redraw)
    local learns, odds = Flags(plan)
    if learns then
        blocks:Heading("Recipes to learn")
        local first = true
        for _, step in ipairs(plan.steps) do
            if step.learn then
                blocks:Pair(ns.RecipeName(step.recipeID, plan.skillLine) or "?",
                            UI.Soft(ns.SkillPlan.LearnSource(step) .. " " .. LearnWhen(step)), first and 4 or 2)
                first = false
            end
        end
    end
    if plan.reason == "none" then blocks:Text(UI.Soft(NothingLine(plan.steps[#plan.steps].to)), 6) end
    PlanButton(blocks, plan, 12, true)
    local remade = ns.SkillPlan.RemadeLine(plan)
    if remade then blocks:Text(UI.ColorText(UI.TEXT.muted, remade), 6) end
    if odds then OddsNote(blocks) end
end

function UI.StepViewBlocks(blocks, plan, i, opts)
    local SP, step = ns.SkillPlan, plan.steps[i]
    local recipe = ns.db.recipes[step.recipeID] or {}
    blocks:Buttons({ { label = "Back to the plan", onClick = opts.onBack } })
    blocks:Text(("|T%s:20:20|t %s"):format(recipe.icon or 134400, ns.RecipeName(step.recipeID, plan.skillLine) or "?"), 12,
                "GameFontHighlightLarge")
    blocks:Text(SP.StepLine(plan, step, "it") .. " " .. SP.StepWhen(plan, i), 4)
    blocks:Bar(plan.skill, plan.target, step.to, ("%s %d / %d"):format(plan.name, plan.skill, plan.target),
               ("this step ends at %d"):format(step.to))
    blocks:Text(UI.Light(SP.OddsLine(step)), 6)
    if step.learn then
        blocks:Heading(step.learn == "now" and "Learn it first" or ("Learn it at %d"):format(step.learn), SP.LearnNote(step))
        if opts.places and #opts.places[1] > 0 then
            blocks[#blocks + 1] = { places = opts.places[1], total = opts.places[2], expanded = opts.places[3], gap = 4 }
        end
    end
    blocks:Heading("This step needs", "have / need")
    HaveNeedLines(blocks, plan, { step }, opts.redraw)
    PlanButton(blocks, plan, 12)
    blocks:Text(UI.ColorText(UI.TEXT.muted, "Shift-click an item to link it or search the auction house."), 6)
end
