-- One character's recipes: a tab per profession, a list by category, and a pane with the picked
-- recipe or, with nothing picked, the profession. Unlearned recipes get two colors of their own
-- (can learn now, needs more skill), so they never look like a grey learned recipe.

local _, ns = ...

local View = {}
ns.RecipeView = View

local panel
local tabs = {}
local currentKey, currentChar

local ROW_HEIGHT = 20
local MORE_HEIGHT = 24
local HEADER_HEIGHT = ns.UI.HEADING.height
local ICON_ROOM = 30
local ACTION_WIDTH, STATS_WIDTH = 64, 150
local PORTRAIT_SIZE = 48
local PAGE = ns.UI.PAGE
local PANE_WIDTH, PANE_GAP = PAGE.paneWidth, PAGE.paneGap
local TABS_TOP = ns.UI.Below(PAGE.top, PORTRAIT_SIZE)

local LEARNED = { icon = 1 }
local CAN_LEARN = { text = ns.UI.TEXT.canLearn, icon = 0.6 }
local NEEDS_SKILL = { text = ns.UI.TEXT.needsSkill, icon = 0.35 }

-- Not "can learn now": 300-skill raid recipes with no known skill would show in a low character's
-- list.
local function RecipeState(learned, required, skill)
    if learned then return "learned" end
    if not required then return "unknown" end
    if skill and skill < required then return "needskill" end
    return "canlearn"
end

local function NameText(data, withIcon)
    local recipe = ns.db.recipes[data.recipeID] or {}
    local color
    if data.state == "learned" then
        color = (ns.DIFFICULTY[data.difficulty] or ns.DIFFICULTY[3]).color
    else
        color = (data.state == "canlearn" and CAN_LEARN or NEEDS_SKILL).text
    end
    local icon = withIcon and ("|T%s:16:16|t "):format(recipe.icon or 134400) or ""
    return icon .. ns.UI.ColorText(color, recipe.name or "?")
end

local function Held(itemID) return ns.Bags.Held(currentChar, itemID) end

local function Craftable(recipe)
    if not (recipe.reagents and #recipe.reagents > 0) then return nil end
    local n = math.huge
    for _, reagent in ipairs(recipe.reagents) do n = math.min(n, math.floor(Held(reagent[1]) / reagent[2])) end
    return n
end

local function ProfessionByLine(char, skillLine)
    for _, prof in ipairs(char and char.professions or {}) do
        if prof.skillLine == skillLine and not ns.GATHERING[prof.skillLine] then return prof end
    end
end

-- ScrollBox only makes the row frames that fit and reuses them while scrolling.

local placesFor = {}

local ShowRecipeTooltip
local function RedrawTooltip()
    local row = View.tooltipRow
    if row and GameTooltip:IsOwned(row) then ShowRecipeTooltip(row) end
end
local AlsoKnownBy
function ShowRecipeTooltip(row)
    local data = row.data
    if data and data.planStep then
        ns.UI.RowTooltip(row)
        ns.UI.TipLine(GameTooltip, ns.SkillPlan.StepLine(data.plan, data.step, data.name), "white", true)
        ns.UI.TipLine(GameTooltip, "Click to see this step in full.", "light")
        GameTooltip:Show()
        return
    end
    local recipe = data and data.recipeID and ns.db.recipes[data.recipeID]
    if not recipe then return end

    ns.UI.RowTooltip(row)

    ns.UI.RecipeTooltipTop(data.recipeID, recipe, recipe.name, nil, function()
        if GameTooltip:IsOwned(row) and row.data == data then ShowRecipeTooltip(row) end
    end)

    local prof = ProfessionByLine(currentChar, ns.view.profession)
    local who = currentChar and ns.UI.CharName(currentChar, currentKey) or "This character"
    if data.learned then
        local difficulty = ns.DIFFICULTY[data.difficulty] or ns.DIFFICULTY[3]
        GameTooltip:AddLine("|cff" .. difficulty.color .. difficulty.text .. "|r")
    else
        if data.state == "canlearn" and prof then
            ns.UI.TipLine(GameTooltip, ("%s can learn it now, %s %d"):format(who, prof.name, prof.skill or 0), "green")
        elseif data.state == "needskill" and prof then
            ns.UI.TipLine(GameTooltip, ("%s needs %s %d, has %d"):format(who, prof.name, data.required, prof.skill or 0), "light")
        else
            ns.UI.TipLine(GameTooltip, data.state == "unknown" and "Not learned, required skill unknown" or "Not learned", "light")
        end
        if data.wouldBe then
            local difficulty = ns.DIFFICULTY[data.wouldBe]
            GameTooltip:AddLine("|cff" .. difficulty.color .. "Once learned: " .. difficulty.text .. "|r")
        end
    end

    local shiftForMore = false
    if not data.learned then
        local withNames = IsShiftKeyDown()
        local places, total, only = ns.Places.Kept(placesFor, data.recipeID)
        local lines, hasNames = ns.RecipeWhere(data.recipeID, withNames, #places > 0 or only ~= nil)
        local requirement = ns.RecipeRequirement(data.recipeID, recipe.skillLine, prof and prof.name, withNames)
        if #places > 0 or only or lines or recipe.source or requirement then
            GameTooltip:AddLine(" ")
            ns.UI.TipLine(GameTooltip, "Where to learn it", "gold")
            local morePlaces = ns.UI.AddPlaceLines(GameTooltip, places, total, withNames)
            if #places == 0 and only then ns.UI.TipLine(GameTooltip, ns.Places.OnlyText(data.recipeID, only), "light", true) end
            if lines then
                for _, line in ipairs(lines) do ns.UI.TipLine(GameTooltip, line, nil, true) end
            elseif #places == 0 and not only and recipe.source then
                ns.UI.TipLine(GameTooltip, recipe.source, nil, true)
            end
            shiftForMore = (morePlaces or hasNames) and not withNames
            if requirement then ns.UI.TipLine(GameTooltip, requirement, nil, true) end
        end
    end

    if recipe.reagents and #recipe.reagents > 0 then
        GameTooltip:AddLine(" ")
        ns.UI.TipLine(GameTooltip, "Reagents", "gold")
        for _, reagent in ipairs(recipe.reagents) do
            local itemID, count = reagent[1], reagent[2]
            local name = ns.UI.ItemLabel(itemID, RedrawTooltip)
            local have = Held(itemID)
            local enough = have >= count
            ns.UI.TipDoubleLine(GameTooltip, ("%d × %s"):format(count, name), ("you have %d"):format(have),
                                 nil, enough and "green" or "light")
        end
    end
    local also = AlsoKnownBy(data.recipeID, ns.view.profession)
    if #also > 0 then
        GameTooltip:AddLine(" ")
        ns.UI.TipLine(GameTooltip, "Also known by", "gold")
        ns.UI.TipLine(GameTooltip, table.concat(also, ", "), nil, true)
    end
    ns.UI.AddTrackedLines(data.recipeID)
    GameTooltip:AddLine(" ")
    local click = ns.view.openRecipe == data.recipeID and "Click to close" or "Click to open"
    ns.UI.TipLine(GameTooltip, click, "light")
    if shiftForMore then ns.UI.TipLine(GameTooltip, "Shift: more places", "light") end
    GameTooltip:Show()

    View.tooltipRow = row
    panel:RegisterEvent("MODIFIER_STATE_CHANGED")
end

local function RecipeMenu(row)
    local data = row.data
    if not (data and data.recipeID and currentKey and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local recipe = ns.db.recipes[data.recipeID] or {}
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(recipe.name or "")
        if ns.Ignore.Is(data.recipeID) then
            ns.Ignore.AddMenuLine(root, data.recipeID)
            return
        end
        local inLog = ns.Tracking.InQuestLog(data.recipeID, currentKey)
        root:CreateButton(inLog and "Untrack materials" or "Track materials", function()
            ns.Tracking.ToggleQuestLog(data.recipeID, currentKey)
        end)
        local index = ns.Tracking.Find(data.recipeID, currentKey)
        root:CreateButton(index and "Remove from shopping list" or "Add to shopping list", function()
            if index then ns.Tracking.Untrack(index) else ns.Tracking.Track(data.recipeID, currentKey) end
        end)
        ns.Ignore.AddMenuLine(root, data.recipeID)
    end)
end

function View.Pick(recipeID, reveal)
    ns.view.openRecipe, ns.view.allPlaces, ns.view.planStep = recipeID, nil, nil
    placesFor = {}
    panel.reveal = reveal and recipeID or nil
    View.RefreshList()
end

local function OnRowClick(row, button)
    local data = row.data
    if not data then return end
    if button == "RightButton" then
        if data.recipeID and not data.planStep then RecipeMenu(row) end
        return
    end
    if data.header then
        local closed = ns.db.collapsed[data.skillLine] or {}
        ns.db.collapsed[data.skillLine] = closed
        closed[data.key] = not closed[data.key] or nil
        View.RefreshList()
    elseif data.more then
        ns.view.showAll = ns.view.showAll or {}
        ns.view.showAll[data.key] = not ns.view.showAll[data.key] or nil
        View.RefreshList()
    elseif data.planStep and not IsShiftKeyDown() then
        View.OpenStep(ns.view.planStep ~= data.planStep and data.planStep or nil)
    elseif data.recipeID and IsShiftKeyDown() then
-- A recipe's ID is its spell ID, so the spell link works.
        ns.UI.InsertLink(C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(data.recipeID))
    elseif data.recipeID then
        View.Pick(ns.view.openRecipe ~= data.recipeID and data.recipeID or nil)
    end
end

local viewWidth = 600
local function ListWidth() return viewWidth - PANE_WIDTH - PANE_GAP end
local function RightWidth(data) return data.statText and STATS_WIDTH or ACTION_WIDTH end
local function NameWidth(data)
    local listWidth = ListWidth() - 14
    return listWidth - ICON_ROOM - RightWidth(data) - 16 - (data.depth or 0) * 14
end

local function RightText(data)
    if data.planStep then return ns.UI.Soft(("%d to %d"):format(data.step.from, data.step.to)) end
    if data.statText then return data.statText end
    if data.state == "canlearn" then
        return ns.UI.ColorText(data.wouldBe and ns.DIFFICULTY[data.wouldBe].color or ns.UI.TEXT.body, "learn")
    elseif data.state == "needskill" then
        return ns.UI.ColorText(ns.UI.TEXT.amber, "needs " .. data.required)
    elseif data.state == "unknown" then
        return ns.UI.ColorText(NEEDS_SKILL.text, "needs ?")
    end
    return ""
end

-- Row frames are reused for every kind of row, so every call sets or hides every part.
local function InitRow(row, data)
    local UI = ns.UI
    if not row.made then
        row.made = true
        row:SetHeight(ROW_HEIGHT)

        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(unpack(ns.UI.C.hover))
        row.tracked = UI.TrackedFill(row)
        row.picked = UI.RoundedBox(row, 6)
        row.picked:SetFill(UI.C.selected)
        row.opened = UI.RoundedBox(row, 6)
        row.opened:SetFill(UI.C.hover)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)

        row.require = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.require:SetJustifyH("RIGHT")
        row.require:SetPoint("RIGHT", -8, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetJustifyH("LEFT")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)

        row.fold = UI.FoldHeader(row)
        row.more = UI.Button(row, "", "quiet", true)
        row.more:SetPoint("LEFT", ICON_ROOM - 6, 0)
        row.more:SetScript("OnClick", function() OnRowClick(row, "LeftButton") end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", ShowRecipeTooltip)
        row.redrawTooltip = function(self) if View.tooltipRow == self then ShowRecipeTooltip(self) end end
        row:SetScript("OnLeave", function()
            View.tooltipRow = nil
            panel:UnregisterEvent("MODIFIER_STATE_CHANGED")
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", OnRowClick)
    end

    row.data = data
    local isRecipe = data.recipeID ~= nil
    row.fold:SetShown(data.header ~= nil)
    row.more:SetShown(data.more ~= nil)
    row.tracked:SetShown(isRecipe and not data.planStep and ns.Tracking.IsTracked(data.recipeID, currentKey))
    row.picked:SetShown(isRecipe and (data.recipeID == ns.view.openRecipe or data.planStep == 1))
    row.opened:SetShown(data.opened == true and data.planStep ~= 1)
    row.icon:SetShown(isRecipe)
    row.text:SetShown(isRecipe)
    row.require:SetShown(isRecipe)
    row.hover:SetShown(not data.more)
    row.hover:ClearAllPoints()
    if data.header then
        row.hover:SetPoint("BOTTOMLEFT", 0, 4)
        row.hover:SetPoint("BOTTOMRIGHT", 0, 4)
        row.hover:SetHeight(HEADER_HEIGHT - 4)
    else
        row.hover:SetAllPoints()
    end

    local indent = (data.depth or 0) * 14
    if data.header then
-- Same height as its extent in the list, or rows under it shift during a resize.
        row:SetHeight(ns.UI.HeadingExtent(data.first))
        row.fold:Set({ x = 4 + indent, title = data.header, open = not data.collapsed, line = true,
                       count = ("%d / %d"):format(data.learned, data.total) })
        return
    elseif data.more then
        row:SetHeight(MORE_HEIGHT)
        UI.SetShowMore(row.more, data.more, data.expanded, data.what or "that need more skill")
        return
    end

    row:SetHeight(data.height or ROW_HEIGHT)
    row.icon:SetPoint("LEFT", 6 + indent, 0)
    local recipe = ns.db.recipes[data.recipeID] or {}
    row.icon:SetTexture(recipe.icon or 134400)
    local look = data.state == "learned" and LEARNED or (data.state == "canlearn" and CAN_LEARN or NEEDS_SKILL)
    row.icon:SetDesaturated(data.state ~= "learned")
    row.icon:SetAlpha(look.icon)
    row.text:SetText(NameText(data))
    row.text:SetWidth(NameWidth(data))
    row.require:SetWidth(RightWidth(data))
    row.require:SetTextColor(unpack(ns.UI.Hex(data.statText and ns.UI.TEXT.stat or ns.UI.TEXT.body)))
    row.require:SetText(RightText(data))
    if data.planStep then row.text:SetText(("%d × %s"):format(data.step.make, UI.Light(data.name))) end
end

local listed = {}

function AlsoKnownBy(recipeID, skillLine)
    return ns.UI.ShortNames(ns.KnownBy(recipeID, skillLine, listed, currentKey))
end

local Gold = ns.UI.Gold
local Soft = ns.UI.Soft

local function Requirement(recipeID, recipe, prof)
    return ns.RecipeRequirement(recipeID, recipe.skillLine, prof.name, true)
end

local function RecipeBlocks(data, prof)
    local recipeID = data.recipeID
    local recipe = ns.db.recipes[recipeID] or {}
    local blocks = ns.UI.Blocks()
    blocks:Buttons({ { label = "Back to " .. prof.name, onClick = function() View.Pick(nil) end } })
    blocks:Text(("|T%s:20:20|t %s"):format(recipe.icon or 134400, recipe.name or "?"), 12, "GameFontHighlightLarge")
    if recipe.category then blocks:Text(Soft(recipe.category), 2) end

    if data.state == "learned" then
        local difficulty = ns.DIFFICULTY[data.difficulty] or ns.DIFFICULTY[3]
        local n = Craftable(recipe)
        blocks:Text("Learned. " .. ns.UI.ColorText(difficulty.color, difficulty.text)
            .. (recipe.trivial and recipe.trivial > 0 and Soft(". Stops giving skill at " .. recipe.trivial .. ".") or "")
            .. (n and n > 0 and ("\nYou can make " .. n .. ".") or ""), 10)
        local timer = ns.Cooldowns.ForRecipe(currentChar, recipeID)
        if timer and timer.ends > time() then
            local count = #(timer.recipes or {})
            blocks:Text(ns.UI.ColorText(ns.UI.TEXT.amber, ("Can %s again %s"):format(ns.Cooldowns.What(timer),
                ns.Cooldowns.When(timer.ends))) .. (count > 1 and Soft(("\n%d recipes share this timer."):format(count)) or ""), 6)
        end
    else
        local requirement = Requirement(recipeID, recipe, prof)
        local first
        if data.state == "canlearn" then
            first = ns.UI.ColorText(ns.UI.TEXT.green, "You can learn it now.")
        elseif data.state == "needskill" then
            first = ns.UI.ColorText(ns.UI.TEXT.amber, ("Needs %d more skill."):format(data.required - (prof.skill or 0)))
        else
            first = Soft("Not learned. The addon's data has no required skill for it.")
        end
        local wouldBe = data.wouldBe and ns.DIFFICULTY[data.wouldBe]
        blocks:Text(first .. (requirement and ("\n" .. requirement) or "")
            .. (wouldBe and ("\nOnce learned: " .. ns.UI.ColorText(wouldBe.color, wouldBe.text)) or ""), 10)

        blocks:Heading("Where to learn it")
        local places, total, only = ns.Places.Kept(placesFor, recipeID)
        if #places > 0 then blocks[#blocks + 1] = { places = places, total = total, expanded = ns.view.allPlaces == recipeID, gap = 4 } end
        local lines = {}
        if #places == 0 and only then lines[#lines + 1] = Soft(ns.Places.OnlyText(recipeID, only)) end
        for _, line in ipairs(ns.RecipeWhere(recipeID, true, #places > 0 or only ~= nil) or {}) do lines[#lines + 1] = line end
        if #lines == 0 and #places == 0 then lines[1] = recipe.source or Soft("Not in the addon's data yet.") end
        if #lines > 0 then blocks:Text(table.concat(lines, "\n"), 4) end
    end

    if recipe.reagents and #recipe.reagents > 0 then
        blocks:Heading("Materials for one")
        for i, reagent in ipairs(recipe.reagents) do
            local item, held = ns.UI.ReagentLine(reagent[1], reagent[2], (ns.Bags.HeldText(reagent[1], listed)))
            blocks:Pair(item, held, i == 1 and 4 or 2)
        end
    end
    if ns.Ignore.Is(recipeID) then
        blocks:Buttons({ { label = "Stop ignoring", kind = "quiet", onClick = function() ns.Ignore.Set(recipeID, false) end } }, 14)
    else
        blocks[#blocks + 1] = { track = recipeID, key = currentKey, char = currentChar, gap = 14 }
    end
    local also = AlsoKnownBy(recipeID, ns.view.profession)
    if #also > 0 then blocks:Text(table.concat(also, ", ") .. Soft(ns.UI.Plural(#also, " knows it too.", " know it too.")), 12) end
    return blocks
end

-- Legacy points are earned once per account, so the best character counts.
local function LegacyText(prof)
    if not ns.CRAFTING[prof.skillLine] then return prof.name .. " gives no Legacy points." end
    local best = ns.Legacy.BestPerProfession(ns.VisibleCharacters())[prof.skillLine]
    local at = ns.Legacy.Next(prof.skillLine, math.max(prof.skill or 0, best and best.prof.skill or 0))
    if not at then return "Every Legacy point is earned on this account." end
    local text = ("%d more skill to the Legacy point at %d."):format(math.max(0, at - (prof.skill or 0)), at)
    if best and best.key ~= currentKey and (best.prof.skill or 0) > (prof.skill or 0) then
        text = text .. (" %s is at %d."):format(ns.UI.CharName(best.char, best.key), best.prof.skill)
    end
    return text
end

local function ScanText(scan)
    if scan and scan.scanned then return "Recipe list from " .. ns.UI.ScanTime(scan.scanned) end
    if scan and scan.atLogin then
        local from = scan.listFrom and ns.db.characters[scan.listFrom]
        return "Read at login " .. ns.UI.ScanTime(scan.atLogin) .. (from and (", list from " .. ns.UI.CharName(from, scan.listFrom)) or "")
    end
    return ns.UI.ColorText(ns.UI.TEXT.amber, "Not scanned yet")
end

local function LoginNote(char, prof, scan)
    local name = ns.UI.CharName(char, "this character")
    local whose = currentKey == ns.CharacterKey() and "your" or (name .. "'s")
    if scan.listFrom then
        local from = ns.db.characters[scan.listFrom]
        return ("What %s knows comes from the game at login. The recipe list and its groups come from %s's %s window. %s own window, once opened, takes over.")
            :format(name, from and ns.UI.CharName(from, scan.listFrom) or "another character", prof.name, (whose:gsub("^%l", string.upper)))
    end
    return ("These are the recipes %s knows. Open %s %s window once for Blizzard's groups and the recipes still to learn.")
        :format(name, whose, prof.name)
end

local SHOWN_IN_PANE = 3

local function StepBlocks(prof)
    local n = ns.view.planStep
    local plan = n and ns.db.window.plan and ns.SkillPlan.Cached(listed, currentKey, prof.skillLine)
    for i, step in ipairs(plan and plan.steps or {}) do
        if i == n then
            local places = step.learn and { ns.Places.Kept(placesFor, step.recipeID) }
            if places then places[3] = ns.view.allPlaces == n end
            local blocks = ns.UI.Blocks()
            ns.UI.StepViewBlocks(blocks, plan, i, { onBack = function() View.OpenStep(nil) end, places = places,
                                                    redraw = View.RefreshList })
            return blocks
        end
    end
    ns.view.planStep = nil
end

function View.OpenStep(n)
    ns.view.openRecipe, ns.view.allPlaces, ns.view.planStep = nil, nil, n
    View.RefreshList()
end

function View.ShowPlan(on)
    ns.view.plan = on and { key = currentKey, line = ns.view.profession } or nil
    ns.view.openRecipe, ns.view.planStep, ns.view.allPlaces = nil, nil, nil
    View.RefreshList()
end

local function OpenPlan(prof)
    local open = ns.view.plan
    if not (prof and open and open.key == currentKey) then return nil end
    if not ns.db.window.plan then
        ns.view.plan = nil
        return nil
    end
    if open.line ~= prof.skillLine or ns.view.openRecipe then
        ns.view.plan = nil
        return nil
    end
    local plan = ns.SkillPlan.Cached(listed, currentKey, prof.skillLine)
    if plan and #plan.steps > 0 then return plan end
    ns.view.plan = nil
end

local function PlanItems(plan)
    local items = {}
    for i, step in ipairs(plan.steps) do
        items[i] = { recipeID = step.recipeID, planStep = i, step = step, plan = plan, state = "learned", opened = i == ns.view.planStep,
                     name = ns.RecipeName(step.recipeID, plan.skillLine) or "?" }
    end
    return items
end

local function PlanControls(plan)
    local on = plan ~= nil
    -- Source and Slot show themselves on refresh (Slot only for gear), so they aren't shown here.
    local selfShown = { [panel.sourceButton] = true, [panel.slotButton] = true }
    for _, control in ipairs({ panel.search, panel.showButton, panel.sourceButton, panel.slotButton, panel.statsButton }) do
        if on then control:Hide() elseif not selfShown[control] then control:Show() end
    end
    panel.planLabel:SetShown(on)
    panel.planBack:SetShown(on)
    if on then panel.planLabel:SetText(("Plan to %d: %s"):format(plan.target, ns.SkillPlan.Size(plan))) end
end

local function ProfessionBlocks(prof, scan, summary)
    local blocks = ns.UI.Blocks()
    blocks:Text(Gold(prof.name), 0, "GameFontNormalLarge")
    local count = ""
    if ns.HasFullList(scan) then
        count = (" %d of %d recipes learned."):format(ns.CountRecipes(scan))
    elseif scan then
        count = (" %d known; the rest once the window opens."):format(ns.CountRecipes(scan))
    end
    blocks:Text(LegacyText(prof) .. count, 4)
    if not scan then return blocks end

    local plan = ns.db.window.plan and ns.SkillPlan.Cached(listed, currentKey, prof.skillLine)
    if plan then
        ns.UI.PlanSummaryBlocks(blocks, plan, { onShow = function() View.ShowPlan(true) end })
    else
        blocks:Heading("Skill-ups you can make now")
        for i = 1, math.min(#summary.ready, SHOWN_IN_PANE) do
            local item = summary.ready[i]
            blocks:Line(NameText(item, true), "make " .. item.make, function() View.Pick(item.recipeID, true) end)
        end
        local rest = summary.needMaterials + math.max(0, #summary.ready - SHOWN_IN_PANE)
        if #summary.ready == 0 and rest == 0 then
            blocks:Text(Soft("Nothing you know gives skill any more."), 4)
        elseif rest > 0 then
            blocks:Text(Soft(("%d more give skill once you have the materials."):format(rest)), 4)
        end
    end

    if ns.HasFullList(scan) then
        blocks:Heading(("You can learn now: %d"):format(#summary.learnable))
        for i = 1, math.min(#summary.learnable, SHOWN_IN_PANE) do
            local item = summary.learnable[i]
            blocks:Line(NameText(item, true), Soft(ns.RecipeWhereShort(item.recipeID) or "no known source"),
                        function() View.Pick(item.recipeID, true) end)
        end
        if #summary.learnable == 0 then
            blocks:Text(Soft("Nothing to learn at this skill."), 4)
        elseif #summary.learnable > SHOWN_IN_PANE and ns.view.filter ~= "canlearn" then
            blocks:Buttons({ { label = ("Show all %d in the list"):format(#summary.learnable), onClick = function()
                ns.view.filter = "canlearn"
                View.RefreshList()
            end } })
        end
    end
    local note = scan.atLogin and not scan.scanned and LoginNote(currentChar, prof, scan) or (ScanText(scan) .. ".")
    blocks:Text(Soft(note .. " Pick a recipe to see where to learn it and what it needs."), 16)
    return blocks
end

local SHOW = {
    { key = "use", label = "What you can use" },
    { key = "all", label = "All recipes" },
    { key = "learned", label = "Learned" },
    { key = "canlearn", label = "Can learn now" },
    { key = "needskill", label = "Needs more skill" },
}
local NOT_LEARNED_FILTER = { canlearn = true, needskill = true }
local SHOW_WIDTH = 210

local function ShowLabel()
    for _, s in ipairs(SHOW) do if s.key == ns.view.filter then return s.label end end
    return SHOW[1].label
end

local function RefreshShowButton()
    panel.showButton:SetState("Show: " .. ShowLabel(), ns.view.filter ~= "use", panel.showMenu:IsShown())
end

local function RefreshShowMenu(counts, knownOnly)
    local options = {}
    for _, s in ipairs(SHOW) do
        if not (knownOnly and NOT_LEARNED_FILTER[s.key]) then
            options[#options + 1] = { key = s.key, label = s.label, count = counts[s.key] or 0 }
        end
    end
    panel.show:Fill(options, ns.view.filter)
    RefreshShowButton()
end

function View.Build(parent)
    local UI = ns.UI
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    tabs = {}
    panel:SetScript("OnEvent", function(_, event, key)
        local row = View.tooltipRow
        if event == "MODIFIER_STATE_CHANGED" and key and key:find("SHIFT") and row and GameTooltip:IsOwned(row) then
            ShowRecipeTooltip(row)
        end
    end)

    panel.portrait = UI.Portrait(panel, PORTRAIT_SIZE)
    panel.portrait:SetPoint("TOPLEFT", 0, PAGE.top)

    panel.name = UI.PageTitle(panel)
    panel.name:SetPoint("TOPLEFT", PORTRAIT_SIZE + 12, PAGE.top)
    panel.info = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.info:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 1, -4)

    panel.search = UI.SearchBox(panel, function(text)
        ns.view.search = text
        View.RefreshList()
    end)

    panel.show = ns.Dropdown.RadioMenu(panel, SHOW_WIDTH, function(key)
        ns.view.filter = key
        View.RefreshList()
    end, RefreshShowButton)
    panel.showButton, panel.showMenu = panel.show.button, panel.show.popup

    panel.sourceButton = ns.SourceFilter.Build(panel)
    panel.slotButton = ns.SlotFilter.Build(panel)
    panel.statsButton = ns.StatFilter.Build(panel)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetJustifyH("LEFT")

    panel.planLabel = UI.Text(panel, "GameFontNormal")
    panel.planBack = UI.Button(panel, "Back to recipes", "quiet")
    panel.planBack:SetScript("OnClick", function() View.ShowPlan(false) end)
    panel.planLabel:Hide()
    panel.planBack:Hide()

    panel.list = UI.ScrollList(panel, function(data)
        if data.header then return ns.UI.HeadingExtent(data.first) end
        if data.more then return MORE_HEIGHT end
        return data.height or ROW_HEIGHT
    end, InitRow)
    panel.scrollBox, panel.scrollBar = panel.list.box, panel.list.bar

    panel.pane = UI.BlockPane(panel, PANE_WIDTH, function()
        local shown = ns.view.openRecipe or ns.view.planStep
        ns.view.allPlaces = ns.view.allPlaces ~= shown and shown or nil
        View.RefreshList()
    end)
    panel.pane:SetPoint("BOTTOMRIGHT", 0, 4)

    panel.message = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.message:SetPoint("TOP", panel.scrollBox, "TOP", 0, -40)
    panel.message:SetWidth(300)
    panel.message:SetSpacing(3)

    RefreshShowButton()
    return panel
end

local function TabTooltip(tab)
    local char, prof = currentChar, ProfessionByLine(currentChar, tab.skillLine)
    if not prof then return end
    local UI = ns.UI
    GameTooltip:SetOwner(tab, "ANCHOR_BOTTOM")
    GameTooltip:SetText(("%s %d / %d"):format(prof.name, prof.skill or 0, prof.maxSkill or 0), unpack(UI.Hex(UI.TEXT.white)))
    local soft = UI.Hex(UI.TEXT.soft)
    GameTooltip:AddLine(ScanText(ns.GetProfessionRecipes(char, prof.skillLine)), soft[1], soft[2], soft[3])
    GameTooltip:AddLine(char.bags and ("Bags as of " .. UI.ScanTime(char.bags.scanned)) or UI.ColorText(UI.TEXT.amber, "Bags not read yet"),
                        soft[1], soft[2], soft[3])
    GameTooltip:AddLine(char.bank and ("Bank as of " .. UI.ScanTime(char.bank.scanned)) or UI.ColorText(UI.TEXT.amber, "Bank not visited yet"),
                        soft[1], soft[2], soft[3])
    local mail = char.mail and char.mail.scanned
    GameTooltip:AddLine(mail and ("Mailbox as of " .. UI.ScanTime(mail)) or UI.ColorText(UI.TEXT.amber, "Mailbox not visited yet"),
                        soft[1], soft[2], soft[3])
    GameTooltip:Show()
end

local function GetTab(index)
    if tabs[index] then return tabs[index] end
    local b = ns.UI.SelectableButton(panel, 26)
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", function(self)
        ns.view.profession = self.skillLine
        View.Pick(nil)
        View.RefreshTabs()
    end)
    b:SetScript("OnEnter", TabTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tabs[index] = b
    return b
end

local function RecipeProfessions(char)
    local list = {}
    for _, prof in ipairs(char.professions or {}) do
        if not ns.GATHERING[prof.skillLine] then table.insert(list, prof) end
    end
    return list
end

function View.RefreshTabs()
    local char = currentChar
    local previous
    local professions = RecipeProfessions(char)

    local function Label(prof, withSkill)
        return withSkill and (prof.name .. " " .. ns.UI.Soft(prof.skill)) or prof.name
    end
    local withSkill, total = true, 0
    for i, prof in ipairs(professions) do
        local b = GetTab(i)
        b.text:SetText(Label(prof, true))
        total = total + b.text:GetStringWidth() + 24 + 4
    end
    if total > viewWidth then withSkill = false end

    for i, prof in ipairs(professions) do
        local b = GetTab(i)
        b.skillLine = prof.skillLine
        b.text:SetText(Label(prof, withSkill))
        b:SetWidth(b.text:GetStringWidth() + 24)
        b:ClearAllPoints()
        if previous then
            b:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", 0, TABS_TOP)
        end
        b:SetSelected(prof.skillLine == ns.view.profession)
        b:Show()
        previous = b
    end
    for i = #professions + 1, #tabs do
        tabs[i]:Hide()
    end
end

-- table.sort isn't stable: the original position breaks ties, keeping Blizzard's order.
local STATE_RANK = { learned = 1, canlearn = 2, needskill = 3, unknown = 4 }
function View.OrderForLearning(items)
    for i, item in ipairs(items) do item.position = i end
    table.sort(items, function(a, b)
        local ra, rb = STATE_RANK[a.state], STATE_RANK[b.state]
        if ra ~= rb then return ra < rb end
        if a.state == "needskill" and a.required ~= b.required then return a.required < b.required end
        if a.state == "canlearn" and (a.wouldBe or 4) ~= (b.wouldBe or 4) then
            return (a.wouldBe or 4) < (b.wouldBe or 4)
        end
        return a.position < b.position
    end)
end

local SEARCH_WIDTH, SEARCH_MIN = 200, 120
local SEARCH_GAP, DROPDOWN_GAP = 10, 6

local function AfterShow()
    local list = {}
    for _, button in ipairs({ panel.sourceButton, panel.slotButton, panel.statsButton }) do
        if button:IsShown() then list[#list + 1] = button end
    end
    return list
end

local MENU_ROW = 28
local function PlaceDropdowns(listWidth)
    local last = ns.UI.Flow(AfterShow(), panel.restTop and listWidth or math.huge, DROPDOWN_GAP, 0, function(button, row, previous)
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", DROPDOWN_GAP, 0)
        elseif panel.restTop then
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, panel.restTop - row * MENU_ROW)
        else
            button:SetPoint("LEFT", panel.showButton, "RIGHT", DROPDOWN_GAP, 0)
        end
    end)
    return panel.restTop and last or 0
end

local CHIP_ROW, CHIP_GAP, STATUS_GAP = 24, 6, 10
local function PlaceStatus(chips)
    local status, listWidth = panel.status, ListWidth()
    status:SetWidth(0)
    local oneLine = status:GetStringWidth()
    local wrapped = oneLine > listWidth
    if wrapped then status:SetWidth(listWidth) end
    local extra = wrapped and math.ceil(status:GetStringHeight() - ns.UI.TextHeight("A", 0, "GameFontHighlightSmall")) or 0
    local startX = wrapped and math.huge or oneLine + STATUS_GAP
    local last = ns.UI.Flow(chips, listWidth, CHIP_GAP, startX, function(chip, row, previous)
        chip:ClearAllPoints()
        if previous then
            chip:SetPoint("LEFT", previous, "RIGHT", CHIP_GAP, 0)
        elseif row == 0 then
            chip:SetPoint("LEFT", status, "RIGHT", STATUS_GAP, 0)
        else
            chip:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, panel.statusTop - extra - row * CHIP_ROW)
        end
    end)
    return extra + (#chips > 0 and last or 0) * CHIP_ROW
end

local function DropdownsWidth()
    local width = panel.showButton:GetWidth()
    for _, button in ipairs(AfterShow()) do width = width + DROPDOWN_GAP + button:GetWidth() end
    return width
end

local function Layout()
    local controlsY = ns.UI.Below(TABS_TOP, PAGE.tabHeight)
    local listWidth = ListWidth()
    local dropdowns = DropdownsWidth()
    panel.laidOutDropdowns = dropdowns
    local room = listWidth - 6 - SEARCH_GAP - dropdowns
    local besideShow = listWidth - 6 - SEARCH_GAP - panel.showButton:GetWidth()
    local belowControls = controlsY - PAGE.controlsToStatus
    panel.showButton:ClearAllPoints()
    panel.restTop = nil
    local showBelow = false
    if room >= SEARCH_MIN or panel.planBack:IsShown() then
        panel.search:SetWidth(math.min(SEARCH_WIDTH, room))
    elseif besideShow >= SEARCH_MIN then
        panel.search:SetWidth(math.min(SEARCH_WIDTH, besideShow))
        panel.restTop = controlsY - MENU_ROW
        belowControls = belowControls - MENU_ROW
    else
        panel.search:SetWidth(math.max(SEARCH_MIN, listWidth - 6))
        showBelow = true
        panel.restTop = controlsY - 2 * MENU_ROW
        belowControls = belowControls - 2 * MENU_ROW
    end
    if showBelow then
        panel.showButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, controlsY - 28)
    else
        panel.showButton:SetPoint("LEFT", panel.search, "RIGHT", SEARCH_GAP, 0)
    end
    belowControls = belowControls - PlaceDropdowns(listWidth) * MENU_ROW
-- 6 px in: the search box's art reaches a little to the left.
    panel.search:SetPoint("TOPLEFT", 6, controlsY)
    panel.planBack:ClearAllPoints()
    panel.planBack:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(PANE_WIDTH + PANE_GAP), controlsY)
    panel.planLabel:ClearAllPoints()
    panel.planLabel:SetPoint("LEFT", panel, "TOPLEFT", 2, controlsY - panel.planBack:GetHeight() / 2)
    panel.planLabel:SetPoint("RIGHT", panel.planBack, "LEFT", -8, 0)
    panel.status:SetPoint("TOPLEFT", 0, belowControls)
    panel.statusTop = belowControls
    panel.laidOutExtra = PlaceStatus(panel.chips or {})
    panel.laidOutStatus = panel.status:GetText() ~= nil and panel.status:GetText() ~= ""
    panel.laidOutPlan = panel.planBack:IsShown()
    local listTop = belowControls - panel.laidOutExtra - (panel.laidOutStatus and PAGE.statusToList or 0)
    ns.UI.PlaceList(panel.list, listTop, 4, PANE_WIDTH + PANE_GAP)
    panel.pane:SetPoint("TOPRIGHT", 0, controlsY + 2)
end

function View.RefreshList()
    if not (panel and currentChar) then return end
    local char = currentChar
    listed = ns.VisibleCharacters()

    if panel.slotsFor ~= ns.view.profession then
        ns.view.slot, ns.view.armor = nil, nil
        panel.slotsFor = ns.view.profession
    end

    local prof = ProfessionByLine(char, ns.view.profession)
    local scan = prof and ns.GetProfessionRecipes(char, prof.skillLine)

    local knownOnly = scan and not ns.HasFullList(scan)
    if knownOnly and NOT_LEARNED_FILTER[ns.view.filter] then ns.view.filter = "use" end
    local filter = ns.view.filter
    local items = {}
    local StatFilter, SlotFilter = ns.StatFilter, ns.SlotFilter
    local statsTicked = #StatFilter.Selected() > 0
    local present, statCounts, shownCount = {}, {}, 0
    local tally = SlotFilter.NewTally()
    local SourceFilter = ns.SourceFilter
    local sources = SourceFilter.NewTally()
    local counts = { use = 0, all = 0, learned = 0, canlearn = 0, needskill = 0 }
    local summary = { ready = {}, needMaterials = 0, learnable = {} }
    local open, picked = ns.view.openRecipe, nil
    panel.status:SetText("")

    if not prof then
        panel.message:SetText("No crafting professions on this character yet.")
    elseif not scan then
        local who = (currentKey == ns.CharacterKey()) and "your" or (ns.UI.CharName(char, "this character") .. "'s")
        panel.message:SetText(("Not scanned yet.\nOpen %s %s window once to read its recipes."):format(who, prof.name))
    else
        local toLoad = {}
        local search = strtrim(ns.view.search or ""):lower()
        local folds = filter == "use" and search == "" and not statsTicked and SlotFilter.Describe() == nil
            and not ns.view.source
        local closed = ns.db.collapsed[prof.skillLine] or {}
        for _, group in ipairs(ns.SortedRecipes(scan)) do
            local matches, ignored = {}, {}
            for _, recipeID in ipairs(group.ids) do
                local recipe = ns.db.recipes[recipeID]
                local isLearned = scan.known[recipeID] ~= nil
                local required = not isLearned and ns.RequiredSkill(recipeID, prof.skillLine) or nil
                local state = RecipeState(isLearned, required, prof.skill)
                local wouldBe = state == "canlearn" and ns.WouldBeDifficulty(recipeID, prof.skillLine, prof.skill) or nil
                local data = { recipeID = recipeID, learned = isLearned, state = state, required = required,
                               difficulty = scan.known[recipeID], wouldBe = wouldBe, depth = group.depth }
-- Plain find, so "-" isn't a pattern character.
                local passesSearch = search == ""
                    or (recipe and recipe.name and recipe.name:lower():find(search, 1, true))
                if ns.Ignore.Is(recipeID) and recipeID ~= open then
                    if recipe and passesSearch then ignored[#ignored + 1] = data end
                else
                    local counted = state == "unknown" and "needskill" or state
                    counts[counted], counts.all = counts[counted] + 1, counts.all + 1
                    if state == "learned" or state == "canlearn" then counts.use = counts.use + 1 end
                    if state == "learned" and (data.difficulty or 3) <= 2 and recipe then
                        local n = Craftable(recipe)
                        if n and n > 0 then
                            data.make = n
                            summary.ready[#summary.ready + 1] = data
                        else
                            summary.needMaterials = summary.needMaterials + 1
                        end
                    elseif state == "canlearn" then
                        summary.learnable[#summary.learnable + 1] = data
                    end
                    if recipeID == open then
                        picked = data
                        if panel.reveal == open then closed[group.key] = nil end
                    end
                    local passesFilter = filter == "all" or filter == "use" or filter == state
                        or (filter == "needskill" and state == "unknown")
                    local itemID = recipe and ns.UI.CraftedItem(recipeID, recipe)
                    local itemStats = StatFilter.Get(itemID)
                    if itemID and not itemStats then table.insert(toLoad, itemID) end
                    for key in pairs(itemStats or {}) do present[key] = true end
                    local slot, armor = SlotFilter.Info(itemID)
                    tally:See(slot, armor)
                    if recipe and passesFilter then sources:Count(recipeID) end
                    local passesOthers = recipe and passesFilter and passesSearch and SourceFilter.Matches(recipeID)
                        and StatFilter.Matches(itemStats)
                    if passesOthers then tally:Count(slot, armor) end
                    if (passesOthers and SlotFilter.Matches(slot, armor)) or recipeID == open then
                        shownCount = shownCount + 1
                        for key in pairs(itemStats or {}) do statCounts[key] = (statCounts[key] or 0) + 1 end
                        data.statText = statsTicked and StatFilter.RowText(itemStats) or nil
                        table.insert(matches, data)
                    end
                end
            end
            View.OrderForLearning(matches)
            if #matches + #ignored > 0 then
                local isClosed = closed[group.key] and search == ""
                table.insert(items, { header = group.name, key = group.key, skillLine = prof.skillLine,
                                      depth = group.depth, first = #items == 0, collapsed = isClosed,
                                      learned = group.learned, total = #group.ids })
                if not isClosed then
                    local expanded = ns.view.showAll and ns.view.showAll[group.key]
                    local folded = 0
                    for _, item in ipairs(matches) do
                        local usable = item.state == "learned" or item.state == "canlearn" or item.recipeID == open
                        if not folds or usable or expanded then table.insert(items, item) end
                        if folds and not usable then folded = folded + 1 end
                    end
                    if folded > 0 then
                        table.insert(items, { more = folded, key = group.key, expanded = expanded })
                    end
                    if #ignored > 0 then
                        local key = group.key .. ":ignored"
                        local shown = ns.view.showAll and ns.view.showAll[key]
                        View.OrderForLearning(ignored)
                        for _, item in ipairs(shown and ignored or {}) do table.insert(items, item) end
                        table.insert(items, { more = #ignored, key = key, expanded = shown, what = "ignored" })
                    end
                end
            end
        end
        table.sort(summary.ready, function(a, b)
            if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
            return a.make > b.make
        end)
        View.OrderForLearning(summary.learnable)
        StatFilter.Load(toLoad)
        local slotWhat = SlotFilter.Describe()
        if slotWhat then
            panel.status:SetText(("%s: %s"):format(ns.UI.Count(shownCount, "recipe", "recipes"), slotWhat)
                .. (statsTicked and (" with " .. StatFilter.SelectedNames()) or ""))
        elseif statsTicked then
            panel.status:SetText(StatFilter.Summary(shownCount))
        end
        if slotWhat or statsTicked then
            panel.message:SetText(#items == 0
                and "No recipe matches all of these. Remove a chip above to widen the search." or "")
        else
            panel.message:SetText(#items == 0 and "No recipes match." or "")
        end
    end
    if not picked and open then ns.view.openRecipe = nil end

    RefreshShowMenu(counts, knownOnly)
    local plan = OpenPlan(prof)
    if plan then
        items = PlanItems(plan)
        panel.status:SetText(ns.UI.Soft("Marked: the step you're on. Click a step for it in full."))
        panel.message:SetText("")
        panel.showMenu:Hide()
        SourceFilter.Hide()
        panel.chips = StatFilter.Hide(SlotFilter.Hide({}))
    else
        if SourceFilter.Update(sources) then return View.RefreshList() end
        panel.chips = StatFilter.Update(present, statCounts, SlotFilter.Update(tally, prof and prof.name, {}))
    end
    PlaceDropdowns(ListWidth())
    PlanControls(plan)
    if DropdownsWidth() ~= panel.laidOutDropdowns or (panel.status:GetText() ~= "") ~= panel.laidOutStatus
        or panel.planBack:IsShown() ~= panel.laidOutPlan or PlaceStatus(panel.chips) ~= panel.laidOutExtra then Layout() end
    panel.message:SetShown(panel.message:GetText() ~= "")
    for _, item in ipairs(items) do
        if item.recipeID then
            local recipe = ns.db.recipes[item.recipeID]
            local text = item.planStep and ("%d × %s"):format(item.step.make, item.name) or (recipe and recipe.name or "?")
            local right = ns.UI.TextHeight(RightText(item), RightWidth(item), "GameFontHighlightSmall")
            item.height = math.max(ROW_HEIGHT, math.ceil(math.max(ns.UI.TextHeight(text, NameWidth(item)), right) + 6))
        end
    end
    panel.scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
    if panel.reveal and picked then
        local id = picked.recipeID
        panel.scrollBox:ScrollToElementDataByPredicate(function(data) return data.recipeID == id end, ScrollBoxConstants.AlignCenter)
    end
    panel.reveal = nil

    panel.pane:SetShown(prof ~= nil)
    if prof then
        local stepView = not picked and StepBlocks(prof)
        local planView = not (picked or stepView) and plan and ns.UI.Blocks()
        if planView then ns.UI.PlanPaneBlocks(planView, plan, { redraw = View.RefreshList }) end
        local paneFor = picked and picked.recipeID or stepView and ("step " .. ns.view.planStep)
            or planView and ("plan " .. prof.skillLine) or ("profession " .. prof.skillLine)
        panel.pane:SetBlocks(picked and RecipeBlocks(picked, prof) or stepView or planView or ProfessionBlocks(prof, scan, summary),
                             paneFor == panel.paneFor)
        panel.paneFor = paneFor
    end
end

function View.Refresh(key, char, width)
    viewWidth = width or viewWidth
    if key ~= currentKey then
        panel.scrollBox:ScrollToBegin()
        ns.view.openRecipe, ns.view.planStep = nil, nil
        if ns.view.plan and ns.view.plan.key ~= key then ns.view.plan = nil end
    end
    currentKey, currentChar = key, char

    if not ProfessionByLine(char, ns.view.profession) then
        local first = RecipeProfessions(char)[1]
        ns.view.profession = first and first.skillLine or nil
    end

    local name = ns.UI.CharacterName(key, char)
    panel.name:SetText(name)
    local faction = char.faction and (", " .. ns.UI.FactionText(char.faction)) or ""
    panel.info:SetText(("Level %d %s"):format(char.level or 0, char.className or "") .. faction)

    panel.portrait:SetCharacter(char)

    if panel.search:GetText() ~= (ns.view.search or "") then
        panel.search:SetText(ns.view.search or "")
    end

    Layout()
    View.RefreshTabs()
    View.RefreshList()
end

function View.Relayout(width)
    if not currentChar then return end
    viewWidth = width or viewWidth
    Layout()
    View.RefreshTabs()
end

-- Opened runs before the page is drawn: the pick waits for the list, for that character only.
local toPick
ns.UI.AddPage("recipes", {
    Build = View.Build,
    Opened = function(recipeID) toPick = recipeID and { key = ns.view.character, recipe = recipeID } end,
    Refresh = function(_, width, _, layoutOnly)
        if layoutOnly then return View.Relayout(width) end
        View.Refresh(ns.view.character, ns.db.characters[ns.view.character], width)
        if toPick and toPick.key == ns.view.character then View.Pick(toPick.recipe, true) end
        toPick = nil
    end,
})
