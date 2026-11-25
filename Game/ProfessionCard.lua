-- ProfessionCard.lua: Blizzard's profession window with what only the account knows: beside each
-- missing material where to get it, and past the side tabs, in a drawer, the picked recipe's card
-- (in your plan, who else knows it, the track buttons) with the plan to the next rank under it.

local _, ns = ...
local UI = ns.UI

local Card = {}
ns.ProfessionCard = Card

local MIN_WIDTH, GAP, BETWEEN = 270, 6, 10
local MIN_PLAN, MIN_RECIPE = 120, 60
-- Blizzard lays basic reagents out 4 to a column; with more, its second column is taken.
local INLINE_MAX = 4

local page, card, planCard, handle, notes, recipeID

local function CreateText(itemID, count, char)
    for _, m in ipairs(ns.RecipesMaking(itemID)) do
        local scan = ns.GetProfessionRecipes(char, m.skillLine)
        if scan and scan.known[m.recipeID] then
            local crafts = ns.CraftsFor(m.recipeID, count)
            local short = {}
            for _, r in ipairs(ns.Reagents(m.recipeID, m.skillLine)) do
                local lacking = r[2] * crafts - ns.Bags.InBags(char, r[1])
                if lacking > 0 then short[#short + 1] = lacking .. " " .. UI.ItemLabel(r[1], Card.Refresh) end
            end
            return "create " .. crafts .. (#short > 0 and (", short of " .. UI.JoinNames(short)) or "")
        end
    end
end

-- Counts bags only, as Blizzard's window does; the bank counts as a holder.
local function Missing(id, char, list)
    local line = (ns.db.recipes[id] or {}).skillLine
    local missing, toPlan = {}, false
    for _, r in ipairs(ns.Reagents(id, line)) do
        local short = r[2] - ns.Bags.InBags(char, r[1])
        if short > 0 then
            local held, places = ns.Bags.HeldText(r[1], list, { skipBagsOf = char })
            local vendor = ns.Places.Vendors(r[1])
            local create = CreateText(r[1], short, char)
            if create then
                held = places > 0 and (create .. " or " .. held) or create
            end
            if vendor then
                local n, cost = ns.Places.WholeStacks(vendor, short)
                local buy = "sold by vendors" .. (cost and (", " .. UI.Money(cost) .. (vendor.stack > 1 and (" for " .. n) or "")) or "")
                held = (places > 0 or create) and (held .. " or " .. buy) or buy
            else
                toPlan = true
            end
            missing[#missing + 1] = { itemID = r[1], short = short, held = held }
        end
    end
    return missing, toPlan
end

local function SlotsFor(missing)
    local form = page.SchematicForm
    local slots = form.GetSlotsByReagentType and form:GetSlotsByReagentType(Enum.CraftingReagentType.Basic)
    if not slots or #slots == 0 or #slots > INLINE_MAX then return nil end
    local byItem = {}
    for _, slot in ipairs(slots) do
        local schematic = slot.GetReagentSlotSchematic and slot:GetReagentSlotSchematic()
        local reagent = schematic and schematic.reagents and schematic.reagents[1]
        if reagent and reagent.itemID then byItem[reagent.itemID] = slot end
    end
    for _, m in ipairs(missing) do
        if not byItem[m.itemID] then return nil end
    end
    return byItem, slots[1]
end

local function RecipeCardBlocks(id, plan, missing, toPlan, inline, list)
    local line = (ns.db.recipes[id] or {}).skillLine
    local char, key = ns.CurrentCharacter()
    local blocks = UI.Blocks()
    blocks[1] = { text = UI.Gold(ns.RecipeName(id, line) or "?"), font = "GameFontNormal",
                  right = UI.ColorText(UI.TEXT.muted, ns.TITLE), gap = 0 }
    local inPlan = ns.SkillPlan.InPlanLine(plan, id)
    if inPlan then blocks:Text(UI.Light(inPlan), 4) end
    local others = ns.KnownBy(id, line, list, key)
    local tracked = ns.Tracking.InQuestLog(id, key) or ns.Tracking.Find(id, key) ~= nil
    local listed = not inline and #missing > 0
    if not (listed or #others > 0 or tracked or inPlan or toPlan) then return nil end
    if listed then
        blocks:Heading("Missing")
        for i, m in ipairs(missing) do
            local left, right = UI.ReagentLine(m.itemID, m.short, m.held, Card.Refresh)
            blocks:Pair(left, right, i == 1 and 4 or 2)
        end
    end
    if #others > 0 then
        blocks:Heading("Also known by")
        local lines = {}
        for i, entry in ipairs(others) do
            local t = ns.Cooldowns.ForRecipe(entry.char, id)
            local timer = t and t.ends > time()
                and UI.Soft((" can %s %s"):format(ns.Cooldowns.What(t), ns.Cooldowns.When(t.ends))) or ""
            lines[i] = UI.ShortName(entry) .. timer
        end
        blocks:Text(table.concat(lines, "\n"), 4)
    end
    if toPlan or tracked then
        blocks[#blocks + 1] = { track = id, key = key, char = char, gap = 12 }
    end
    return blocks
end

local function PlanCardBlocks(plan, onTop)
    if not plan then return nil end
    local char, key = ns.CurrentCharacter()
    local scan = ns.GetProfessionRecipes(char, plan.skillLine)
    local function Learned(step) return scan and scan.known[step.recipeID] end
    local folded = ns.db.window.planFolded
    local blocks = UI.Blocks()
    UI.PlanCardBlocks(blocks, plan, { corner = onTop and ns.TITLE or nil, redraw = Card.Refresh,
        folded = folded[plan.skillLine] == true,
        onFold = function()
            folded[plan.skillLine] = not folded[plan.skillLine] or nil
            Card.Refresh()
        end,
        onOpen = function()
            ns.ShowWindow()
            ns.ShowPlan(key, plan.skillLine)
        end,
        rowHint = function(step) return Learned(step) and "Click to open it in the profession window." or nil end,
        onStep = function(step)
            if Learned(step) and not InCombatLockdown() then C_TradeSkillUI.OpenRecipe(step.recipeID) end
        end })
    return #blocks > 0 and blocks or nil
end

-- Measured live: another addon may resize or hide the side tabs.
local function Anchor(open)
    local frame = ProfessionsFrame
    local right, frameTop = frame:GetRight(), frame:GetTop()
    local tabs, below, list = 0, nil, { unpack(frame.rightProfessionTabs or {}) }
    if frame.ProfessionsOverviewTab then list[#list + 1] = frame.ProfessionsOverviewTab end
    for _, tab in ipairs(list) do
        local tabRight, tabTop = tab:IsShown() and tab:GetRight(), tab:IsShown() and tab:GetTop()
        if tabRight and right then tabs = math.max(tabs, tabRight - right) end
        if tabTop and frameTop then below = math.min(below or math.huge, frameTop - tabTop) end
    end
    local beside = GAP + UI.HANDLE_WIDTH + GAP
    local screen = UIParent:GetRight() and UIParent:GetRight() * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local left = right and screen and right + tabs + beside + card:GetWidth() > screen
    handle:ClearAllPoints()
    if left then
        handle:SetPoint("TOPRIGHT", frame, "TOPLEFT", -GAP, -(below or 0))
    else
        handle:SetPoint("TOPLEFT", frame, "TOPRIGHT", tabs + GAP, -(below or 0))
    end
    handle:SetPointing(open ~= left and "<" or ">", open and "Hide Altisan's cards" or "Show Altisan's cards")
    if not open then return end
    local top = card:IsShown() and card or planCard
    top:ClearAllPoints()
    if left then
        top:SetPoint("TOPRIGHT", frame, "TOPLEFT", -beside, 0)
    else
        top:SetPoint("TOPLEFT", frame, "TOPRIGHT", tabs + beside, 0)
    end
    if top == card then
        planCard:ClearAllPoints()
        planCard:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -BETWEEN)
    end
end

local function SetNotes(missing, slots, first)
    if not notes then return end
    local entries = {}
    for _, m in ipairs(missing or {}) do entries[#entries + 1] = { slot = slots[m.itemID], text = m.held } end
    notes:Set(entries, first)
end

local function ToggleDrawer()
    ns.db.window.cardsHidden = not ns.db.window.cardsHidden
    Card.Refresh()
end

function Card.Refresh()
    if not (page and page:IsVisible()) then return end
    local own = recipeID and not (C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsNPCCrafting())
    local list = ns.VisibleCharacters()
    local missing, toPlan = {}, false
    if own then missing, toPlan = Missing(recipeID, ns.CurrentCharacter(), list) end
    local slots, first
    if own and ns.db.window.slotNotes then slots, first = SlotsFor(missing) end
    SetNotes(slots and missing, slots, first)

    local line = own and (ns.db.recipes[recipeID] or {}).skillLine
    local plan = line and ns.db.window.plan and ns.SkillPlan.Cached(list, ns.CharacterKey(), line)
    local recipeBlocks, planBlocks
    if own and ns.db.window.card then
        recipeBlocks = RecipeCardBlocks(recipeID, plan, missing, toPlan, slots ~= nil, list)
    end
    if own and ns.db.window.planCard then planBlocks = PlanCardBlocks(plan, not recipeBlocks) end
    if not (recipeBlocks or planBlocks) then
        if card then card:Hide() planCard:Hide() handle:Hide() end
        return
    end
    if not card then
        -- Built lazily: the game's fonts must be ready to measure the track buttons.
        local width = math.max(MIN_WIDTH, UI.ScrollPaneWidth(UI.TrackButtonsWidth(recipeID, ns.CharacterKey())))
        card = UI.BlockPane(page, width, nil, true)
        planCard = UI.BlockPane(page, width, nil, true)
        handle = UI.DrawerHandle(page, ToggleDrawer)
    end
    handle:Show()
    local open = not ns.db.window.cardsHidden
    card:SetShown(open and recipeBlocks ~= nil)
    planCard:SetShown(open and planBlocks ~= nil)
    if open then
        local room = ProfessionsFrame:GetHeight() or math.huge
        if recipeBlocks then
            local mine = planBlocks and math.max(room - BETWEEN - MIN_PLAN, MIN_RECIPE) or room
            card:SetHeight(math.min(card:SetBlocks(recipeBlocks), mine))
            room = room - card:GetHeight() - BETWEEN
        end
        if planBlocks then planCard:SetHeight(math.min(planCard:SetBlocks(planBlocks), math.max(room, MIN_PLAN))) end
    end
    Anchor(open)
end

-- Children of the crafting page: they move, scale and hide with Blizzard's window.
ns.OnRefresh(function(layoutOnly) if not layoutOnly then Card.Refresh() end end)

function Card.Init()
    local crafting = ProfessionsFrame and ProfessionsFrame.CraftingPage
    if page or not (crafting and crafting.SchematicForm) then return end
    page = crafting
    notes = UI.SlotNotes(page.SchematicForm)
    page:HookScript("OnShow", Card.Refresh)
    hooksecurefunc(page.SchematicForm, "Init", function(_, info)
        recipeID = info and info.recipeID
        Card.Refresh()
    end)
end

Card.Frame = function() return card end
Card.PlanFrame = function() return planCard end
Card.Handle = function() return handle end
Card.Notes = function() return notes end
