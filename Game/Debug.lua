-- Debug.lua: a copyable text window for /alt debug and /alt check (chat text can't be copied).
-- The last report is also saved in AltisanDB.lastDebug, written on logout or /reload.

local _, ns = ...

local frame

function ns.DebugProfession()
    local title, lines = ns.ProfessionDebugLines()
    if not title then
        print(ns.UI.ColorText(ns.UI.TEXT.chatName, "Altisan") .. " Open a profession window first, then type /alt debug again.")
        return
    end
    ns.ShowDebugText(title, lines)
end

local NO_SCAN_PAIR = "   No scanned profession with both known and unknown recipes yet."

local function CreateDebugWindow()
    frame = CreateFrame("Frame", "AltisanDebugFrame", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetSize(720, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    table.insert(UISpecialFrames, "AltisanDebugFrame")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -34)
    hint:SetText("Click in the text, press Ctrl+A then Ctrl+C to copy it.")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -56)
    scroll:SetPoint("BOTTOMRIGHT", -30, 18)
    if scroll.CharCount then scroll.CharCount:Hide() end
    local box = scroll.EditBox
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(660)
    box:SetMaxLetters(0)
    ns.UI.ReadOnly(box, function() return frame.text end, function() frame:Hide() end)
    frame.box = box
end

function ns.ShowDebugText(title, lines, keep)
    if not frame then CreateDebugWindow() end
    frame.text = table.concat(lines, "\n")
    frame:SetTitle(title)
    frame.box:SetText(frame.text)
    frame.box:SetCursorPosition(0)
    frame:Show()
    if not keep then ns.db.lastDebug = lines end
end

local function Show(value, depth)
    depth = depth or 0
    if type(value) == "string" then return ("%q"):format(value) end
    if type(value) ~= "table" then return tostring(value) end
    if depth >= 2 then return "{...}" end
    local parts = {}
    for k, v in pairs(value) do
        if #parts == 12 then parts[#parts + 1] = "..." break end
        parts[#parts + 1] = (type(k) == "number" and "" or (tostring(k) .. " = ")) .. Show(v, depth + 1)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Lua 5.1 has no table.pack, and {...} alone loses trailing nils.
local function Pack(...) return { n = select("#", ...), ... } end

local function Try(label, fn, ...)
    if type(fn) ~= "function" then return label .. " → not in this client" end
    local r = Pack(pcall(fn, ...))
    if not r[1] then return label .. " → error: " .. tostring(r[2]) end
    local out = {}
    for i = 2, r.n do out[#out + 1] = Show(r[i]) end
    return label .. " → " .. (#out > 0 and table.concat(out, ", ") or "nothing")
end

local function KnownAndUnknown(char)
    for _, scan in pairs(char and char.recipes or {}) do
        local known, unknown = next(scan.known or {}), next(scan.unknown or {})
        if known and unknown then return known, unknown end
    end
end

local function FindCraftedItem(test)
    for _, recipe in pairs(ns.db.recipes) do
        if recipe.item and test(recipe.item) then return recipe.item end
    end
end

local function ItemWithStat(word)
    for itemID, stats in pairs(ns.db.itemStats or {}) do
        for key in pairs(stats) do
            if tostring(key):find(word) then return itemID end
        end
    end
end

-- Blizzard asks the guild by the parent profession line, the one recipes are saved under.
local function KnownWithLine(char)
    for line, scan in pairs(char and char.recipes or {}) do
        local known = next(scan.known or {})
        if known then return line, known end
    end
end

local WAITING = "   Waiting for GUILD_RECIPE_KNOWN_BY_MEMBERS (up to 5 seconds)..."

-- The answer arrives later by event: edit lines in place, since this run is already saved in
-- AltisanDB.checks.
local function WaitForGuild(lines, at)
    local function Answer(text)
        frame:UnregisterEvent("GUILD_RECIPE_KNOWN_BY_MEMBERS")
        frame.guildRun = nil
        lines[at] = "   " .. text
        if frame:IsShown() then ns.ShowDebugText("Altisan checks", lines, true) end
    end
    if frame.guildRun then frame.guildRun[frame.guildAt] = "   Not answered before the next run." end
    frame.guildRun, frame.guildAt = lines, at
    frame:RegisterEvent("GUILD_RECIPE_KNOWN_BY_MEMBERS")
    frame:SetScript("OnEvent", function()
        if frame.guildRun ~= lines then return end
        local r = Pack(pcall(GetGuildRecipeInfoPostQuery))
        if not r[1] then return Answer("GetGuildRecipeInfoPostQuery → error: " .. tostring(r[2])) end
        local names = {}
        for i = 1, math.min(tonumber(r[4]) or 0, 3) do
            local ok, name = pcall(GetGuildRecipeMember, i)
            names[#names + 1] = ok and tostring(name) or "?"
        end
        Answer(("Answer → skill line %s, recipe %s, %s members%s"):format(Show(r[2]), Show(r[3]), Show(r[4]),
            #names > 0 and (": " .. table.concat(names, ", ")) or ""))
    end)
    C_Timer.After(5, function()
        if frame.guildRun == lines then Answer("No answer in 5 seconds.") end
    end)
end

function ns.RunChecks()
    if not frame then CreateDebugWindow() end
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local char = ns.CurrentCharacter()
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    Add(("Altisan checks · build %s · %s"):format(build, date and date("%Y-%m-%d %H:%M") or ""))
    local windowOpen = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())

    Add("")
    Add("1. Known recipes without the profession window")
    if windowOpen then Add("   A profession window is open: close it and run /alt check again for this one.") end
    local known, unknown = KnownAndUnknown(char)
    if known then
        local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown or IsSpellKnown
        Add("   " .. Try(("IsSpellKnown(%d) %s, known"):format(known, ns.RecipeName(known)), isKnown, known))
        Add("   " .. Try(("IsSpellKnown(%d) %s, not known"):format(unknown, ns.RecipeName(unknown)), isKnown, unknown))
    else
        Add(NO_SCAN_PAIR)
    end

    Add("")
    Add("2. The bank" .. (ns.Bags.IsBankOpen() and " (open)" or " (closed: open it and run again)"))
    Add("   " .. Try("C_Bank.FetchViewableBankTypes()", C_Bank and C_Bank.FetchViewableBankTypes))
    Add("   " .. Try("C_Bank.ShouldUsePlayerBagsInBank()", C_Bank and C_Bank.ShouldUsePlayerBagsInBank))

    Add("")
    Add("3. Bank counts away from the bank")
    local bankItem = char and char.bank and next(char.bank.items or {})
    if bankItem then
        local count = C_Item and C_Item.GetItemCount or GetItemCount
        Add(("   %s: %d in the bank at the last visit"):format(ns.UI.ItemLabel(bankItem), char.bank.items[bankItem]))
        Add("   " .. Try(("GetItemCount(%d)"):format(bankItem), count, bankItem))
        Add("   " .. Try(("GetItemCount(%d, true)"):format(bankItem), count, bankItem, true))
    else
        Add("   No bank read yet: visit the bank once.")
    end

    Add("")
    Add("4. Stats of crafted items")
    for _, word in ipairs({ "HIT", "HEAL" }) do
        local itemID = ItemWithStat(word)
        if itemID then
            Add("   " .. Try(("GetItemStats %s"):format(ns.UI.ItemLabel(itemID)), C_Item and C_Item.GetItemStats, "item:" .. itemID))
        else
            Add(("   No saved item with a %s stat yet (tick a stat in the Stats filter once)."):format(word:lower()))
        end
    end

    Add("")
    Add("5. A crafted cloak (expect class 4, subclass 1 at the end)")
    local instant = C_Item and C_Item.GetItemInfoInstant
    local cloak = instant and FindCraftedItem(function(itemID)
        local ok, _, _, _, slot = pcall(instant, itemID)
        return ok and slot == "INVTYPE_CLOAK"
    end)
    Add("   " .. (cloak and Try("GetItemInfoInstant " .. ns.UI.ItemLabel(cloak), instant, cloak) or "No crafted cloak among the scanned recipes."))

    Add("")
    Add("6. Auctionator")
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    Add("   " .. (api and Try("GetAuctionPriceByItemID(Silk Cloth)", api.GetAuctionPriceByItemID, "Altisan", 4306)
        or "Auctionator isn't loaded."))

    Add("")
    Add("7. Crafting stations (needs a profession window open)")
    if windowOpen and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local found, checked = 0, 0
        for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            if checked >= 300 or found >= 3 then break end
            checked = checked + 1
            local ok, req = pcall(C_TradeSkillUI.GetRecipeRequirements, recipeID)
            if ok and type(req) == "table" and #req > 0 then
                found = found + 1
                Add(("   %s (%d) → %s"):format(ns.RecipeName(recipeID), recipeID, Show(req)))
            end
        end
        if found == 0 then Add(("   None of %d recipes reported a requirement."):format(checked)) end
    else
        Add("   Open a profession window with a station recipe (a Tanning Rack one, say) and run again.")
    end

    Add("")
    Add("8. Items with their own use (for the item tooltip's verdict)")
    for _, itemID in ipairs({ 6530, 118, 2318 }) do
        local getSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
        Add("   " .. Try(("GetItemSpell(%d) %s"):format(itemID, ns.UI.ItemLabel(itemID)), getSpell, itemID))
        Add("   " .. Try(("GetItemInfoInstant(%d)"):format(itemID), instant, itemID))
    end

    Add("")
    Add("9. Guild crafters (Blizzard's own list; needs a guild)")
    Add("   " .. Try("C_TradeSkillUI.IsGuildTradeSkillsEnabled()", C_TradeSkillUI and C_TradeSkillUI.IsGuildTradeSkillsEnabled))
    local line, learned = KnownWithLine(char)
    if not (IsInGuild and IsInGuild()) then
        Add("   Not in a guild: join one and run again.")
    elseif not learned then
        Add("   No scanned profession yet: open one profession window and run again.")
    else
        local query = C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe
        Add("   " .. Try(("QueryGuildMembersForRecipe(%d, %d) %s"):format(line, learned, ns.RecipeName(learned)), query, line, learned))
        if query then
            Add(WAITING)
            WaitForGuild(lines, #lines)
        end
    end

    Add("")
    Add("10. Map waypoints (the game's own pin)")
    local canPin = C_Map and C_Map.CanSetUserWaypointOnMap
    Add("   " .. Try("CanSetUserWaypointOnMap(1453) Stormwind", canPin, 1453))
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if here then Add("   " .. Try(("CanSetUserWaypointOnMap(%d) where you are"):format(here), canPin, here)) end
    Add("   " .. Try("HasUserWaypoint()", C_Map and C_Map.HasUserWaypoint))

    Add("")
    Add("11. The game's encoder (for guild sync)")
    local enc = C_EncodingUtil
    Add("   " .. Try('EncodeBase64("Altisan")', enc and enc.EncodeBase64, "Altisan"))
    Add("   " .. Try("SerializeCBOR, then DeserializeCBOR", enc and function()
        return enc.DeserializeCBOR(enc.SerializeCBOR({ recipe = 2385, known = true }))
    end))
    Add("   " .. Try("CompressString, then DecompressString", enc and function()
        return enc.DecompressString(enc.CompressString("Altisan Altisan Altisan"))
    end))

    Add("")
    Add("12. Syndicator (every character's bags, bank and mail, if installed)")
    local syn = Syndicator and Syndicator.API
    if syn then
        local names = {}
        for name, value in pairs(syn) do
            if type(value) == "function" then names[#names + 1] = name end
        end
        table.sort(names)
        Add("   Its public API: " .. table.concat(names, ", "))
        Add("   Altisan calls this character " .. Show(ns.CharacterKey()))
        Add("   " .. Try("IsReady()", syn.IsReady))
        Add("   " .. Try("GetCurrentCharacter()", syn.GetCurrentCharacter))
        Add("   " .. Try("GetAllCharacters()", syn.GetAllCharacters))
        local bagItem = char and char.bags and next(char.bags.items or {})
        if bagItem then
            Add("   " .. Try(("GetInventoryInfoByItemID(%d) %s"):format(bagItem, ns.UI.ItemLabel(bagItem)),
                syn.GetInventoryInfoByItemID, bagItem, true, true))
        end
    else
        Add("   Syndicator isn't loaded.")
    end

    Add("")
    Add("13. The quest log's recipe tracker (tracks, reads back, untracks at once)")
    local trackKnown, trackUnknown = KnownAndUnknown(char)
    local ui = C_TradeSkillUI
    if not (ui and ui.SetRecipeTracked and ui.IsRecipeTracked) then
        Add("   " .. Try("C_TradeSkillUI.SetRecipeTracked", ui and ui.SetRecipeTracked))
    elseif not trackKnown then
        Add(NO_SCAN_PAIR)
    else
        if windowOpen then Add("   A profession window is open: close it and run again for this one.") end
        for _, pick in ipairs({ { trackKnown, "known" }, { trackUnknown, "not known" } }) do
            local id = pick[1]
            local before = ui.IsRecipeTracked(id, false)
            Add("   " .. Try(("SetRecipeTracked(%d) %s, %s"):format(id, ns.RecipeName(id), pick[2]), ui.SetRecipeTracked, id, true, false))
            Add("   " .. Try("   then IsRecipeTracked", ui.IsRecipeTracked, id, false))
            if not before then pcall(ui.SetRecipeTracked, id, false, false) end
        end
    end

    Add("")
    Add("14. One faction's recipes (needs the Cooking window open)")
    if windowOpen and ui and ui.GetRecipeInfo then
        local function Has(list, id)
            for _, v in ipairs(list or {}) do if v == id then return true end end
            return false
        end
        local all = ui.GetAllRecipeIDs and ui.GetAllRecipeIDs()
        local filtered = ui.GetFilteredRecipeIDs and ui.GetFilteredRecipeIDs()
        for _, id in ipairs({ 2795, 6413, 6501, 2538 }) do
            local ok, info = pcall(ui.GetRecipeInfo, id)
            info = ok and type(info) == "table" and info or {}
            Add(("   %s (%d): in all %s, in filtered %s, learned %s, disabled %s, reason %s, sourceType %s"):format(
                ns.RecipeName(id), id, Show(Has(all, id)), Show(Has(filtered, id)), Show(info.learned),
                Show(info.disabled), Show(info.disabledReason), Show(info.sourceType)))
            Add("      " .. Try("GetRecipeSourceText", ui.GetRecipeSourceText, id))
            Add("      " .. Try("GetFactionSpecificOutputItem", ui.GetFactionSpecificOutputItem, id))
        end
    else
        Add("   Open the Cooking window and run again.")
    end

    Add("")
    Add("15. Recipe items: does the tooltip name a faction or races? (red lines are ones you can't meet)")
    local getTip = C_TooltipInfo and C_TooltipInfo.GetItemByID
    for _, itemID in ipairs({ 2889, 5483, 5528 }) do
        local ok, tip = pcall(getTip, itemID)
        local texts = {}
        for _, line in ipairs(ok and type(tip) == "table" and tip.lines or {}) do
            local color = line.leftColor and line.leftColor.GenerateHexColor and line.leftColor:GenerateHexColor() or ""
            texts[#texts + 1] = (line.leftText or "") .. (color:find("^ffff2020") and " (red)" or "")
        end
        Add(("   %s: %s"):format(ns.UI.ItemLabel(itemID), #texts > 0 and table.concat(texts, " / ") or "no lines (run again once it loads)"))
    end

    Add("")
    Add("16. Whole pixels in the open window (open Altisan on the page to check, then run this)")
    local window = _G.AltisanFrame
    if not (window and window:IsVisible() and GetPhysicalScreenSize) then
        Add("   Open the Altisan window first.")
    else
        local factor = 768 / select(2, GetPhysicalScreenSize())
        local function Px(v, region) return v and (v * region:GetEffectiveScale() / factor) end
        local function Off(v) return v and math.abs(v - math.floor(v + 0.5)) > 0.01 end
        local thin, offEdge, notRounded, snapping, minPx, maxPx, samples = 0, 0, 0, 0, math.huge, 0, {}
        local masked = {}
        local function Look(r, owner)
            if not (r.IsVisible and r:IsVisible()) then return end
            local rounded = r.GetRoundLayoutToNearestPixel and r:GetRoundLayoutToNearestPixel()
            if rounded == false then notRounded = notRounded + 1 end
            if r.IsObjectType and r:IsObjectType("Texture") then
                if r.IsSnappingToPixelGrid and r:IsSnappingToPixelGrid() then snapping = snapping + 1 end
                local w, h = r:GetWidth(), r:GetHeight()
                local thick = math.min(Px(w, r) or 99, Px(h, r) or 99)
                if (w > 0 and w < 3) or (h > 0 and h < 3) then
                    thin = thin + 1
                    minPx, maxPx = math.min(minPx, thick), math.max(maxPx, thick)
                    local edges = { Px(r:GetLeft(), r), Px(r:GetRight(), r), Px(r:GetTop(), r), Px(r:GetBottom(), r) }
                    local off = false
                    for _, e in ipairs(edges) do if Off(e) then off = true end end
                    if off then
                        offEdge = offEdge + 1
                        if #samples < 4 then
                            samples[#samples + 1] = ("%.2f px thick, left %.2f top %.2f, rounded %s, in %s"):format(
                                thick, edges[1] or -1, edges[3] or -1, tostring(rounded), owner)
                        end
                    end
                end
                if r.GetNumMaskTextures and r:GetNumMaskTextures() > 0 and #masked < 2 then
                    local mask = r:GetMaskTexture(1)
                    masked[#masked + 1] = ("picture %.2fx%.2f px at %.2f,%.2f rounded %s · mask rounded %s at %.2f,%.2f"):format(
                        Px(r:GetWidth(), r), Px(r:GetHeight(), r), Px(r:GetLeft(), r) or -1, Px(r:GetTop(), r) or -1, tostring(rounded),
                        tostring(mask and mask.GetRoundLayoutToNearestPixel and mask:GetRoundLayoutToNearestPixel()),
                        mask and Px(mask:GetLeft(), mask) or -1, mask and Px(mask:GetTop(), mask) or -1)
                end
            end
        end
        local function Walk(f, depth)
            if depth > 40 then return end
            Look(f, "frame")
            local owner = (f.GetDebugName and f:GetDebugName()) or "?"
            for _, r in ipairs({ f:GetRegions() }) do Look(r, owner) end
            for _, c in ipairs({ f:GetChildren() }) do Walk(c, depth + 1) end
        end
        Walk(window, 0)
        Add(("   Screen %d px tall, window scale %.3f, a UI unit is %.3f px here"):format(select(2, GetPhysicalScreenSize()),
            window:GetEffectiveScale(), window:GetEffectiveScale() / factor))
        Add(("   Thin lines shown: %d · thickness %.2f to %.2f px · %d with an edge between pixels"):format(
            thin, thin > 0 and minPx or 0, maxPx, offEdge))
        for _, s in ipairs(samples) do Add("      " .. s) end
        Add(("   Shown regions not rounded to pixels: %d · textures snapping each corner: %d"):format(notRounded, snapping))
        for _, s in ipairs(masked) do Add("   " .. s) end
    end

    Add("")
    Add("17. Sell prices the plan weighs materials by (expect copper: Linen Cloth 13, Strange Dust 1, Silk Cloth 150)")
    for _, itemID in ipairs({ 2589, 10940, 4306 }) do
        Add("   " .. Try("sell price of " .. ns.UI.ItemLabel(itemID), function(id) return (select(11, C_Item.GetItemInfo(id))) end, itemID))
    end

    Add("")
    Add("18. Trainer requirements against the library (talk to a profession trainer first, then run this)")
    if not (GetNumTrainerServices and GetTrainerServiceSkillReq) then
        Add("   Not in this client.")
    else
        -- A set per name: two recipes can share one. The library's numbers on purpose:
        -- ns.RequiredSkill prefers trainers' saved ones.
        local library, db = {}, ns.ProfessionDB and ns.ProfessionDB()
        for _, line in ipairs(db and db:GetProfessions() or {}) do
            local profession = ns.ProfessionName(line) or ""
            for recipeID, recipe in pairs(db:GetRecipes(line) or {}) do
                if recipe.requiredSkill then
                    local id = profession .. ":" .. ns.RecipeName(recipeID, line)
                    library[id] = library[id] or {}
                    library[id][recipe.requiredSkill] = true
                end
            end
        end
        local differ, same, services = {}, 0, 0
        local ok, err = ns.Trainers.EachService(function(name, skill, rank)
            services = services + 1
            local known = name and skill and rank and library[skill .. ":" .. name]
            if known and known[rank] then
                same = same + 1
            elseif known then
                local levels = {}
                for level in pairs(known) do levels[#levels + 1] = level end
                table.sort(levels)
                differ[#differ + 1] = ("   %s: trainer %d, library %s"):format(name, rank, table.concat(levels, " or "))
            end
        end)
        if not ok then
            Add("   error: " .. tostring(err))
        elseif services == 0 then
            Add("   No profession trainer services listed: talk to a profession trainer first.")
        else
            Add(("   %d services, %d match the library, %d differ%s"):format(services, same, #differ, #differ > 0 and ":" or "."))
            for _, line in ipairs(differ) do Add(line) end
        end
    end

    Add("")
    Add("Saved in AltisanDB.checks (the last 5 runs). /reload or log out to write the file.")
    -- Some checks need the bank or a profession window open, so several runs are kept.
    ns.db.checks = ns.db.checks or {}
    table.insert(ns.db.checks, lines)
    while #ns.db.checks > 5 do table.remove(ns.db.checks, 1) end
    ns.ShowDebugText("Altisan checks", lines, true)
    return lines
end
