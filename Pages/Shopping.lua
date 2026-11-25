-- Shopping.lua: the Shopping page. The tracked crafts, their materials, what to create first and
-- mail, and what to buy, from ns.ShoppingPlan; buying through Auctionator or a copied list.

local _, ns = ...

local Shop = {}
ns.Shopping = Shop

local TEXT = ns.UI.TEXT
local Color = ns.UI.ColorText
local ShortName = ns.UI.ShortName

local PAGE = ns.UI.PAGE
local RIGHT_WIDTH = 250
local GAP = 14
local CRAFT_ROW = 24
local MAX_CRAFTS = 6
local MATERIAL_ROW = 24
local WHERE_ROOM = 330
local SMALL = "GameFontHighlightSmall"

local panel
local craftRows = {}
local current = { buy = {} }

local STATUS_WIDTH = 90

local function GetCraftRow(index)
    if craftRows[index] then return craftRows[index] end
    local UI = ns.UI
    local row = CreateFrame("Frame", nil, panel.crafts)
    row:SetHeight(CRAFT_ROW)
    row.stepper = UI.Stepper(row, function(_, delta) ns.Tracking.Change(row.index, delta) end)
    row.stepper:SetPoint("LEFT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.stepper, "RIGHT", 10, 0)
    row.remove = UI.SquareButton(row, "×", "Stop tracking")
    row.remove:SetPoint("RIGHT", 0, 0)
    row.remove:SetScript("OnClick", function()
        if row.planIndex then ns.SkillPlan.Untrack(row.planIndex) else ns.Tracking.Untrack(row.index) end
    end)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.crafter = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row.hit = CreateFrame("Frame", nil, row)
    row.hit:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
    row.hit:SetPoint("BOTTOMRIGHT", row.text, "BOTTOMRIGHT", 2, -2)
    row.hit:EnableMouse(true)
    UI.ItemHover(row.hit, function()
        local recipe = row.recipe and ns.db.recipes[row.recipe]
        return recipe and recipe.item
    end, "OnMouseUp", function() return row.recipe and ns.RecipeName(row.recipe) end)
    craftRows[index] = row
    return row
end

local NAME_ROOM = 140
local function PlaceCraftRow(row, rowWidth)
    local fixed = ns.UI.STEPPER_WIDTH + 10 + 18 + 8 + 12 + 24
    local beside = 12 + row.crafter:GetStringWidth() + 12 + STATUS_WIDTH
    local stacked = rowWidth - fixed - beside < NAME_ROOM
    local nameWidth = stacked and (rowWidth - fixed) or (rowWidth - fixed - beside)
    row.text:ClearAllPoints()
    row.crafter:ClearAllPoints()
    row.status:ClearAllPoints()
    row.text:SetWidth(nameWidth)
    if stacked then
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.crafter:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
        row.status:SetPoint("LEFT", row.crafter, "RIGHT", 10, 0)
        row.status:SetWidth(0)
        row.status:SetJustifyH("LEFT")
        return math.max(CRAFT_ROW + 4, 6 + row.text:GetStringHeight() + 3 + row.crafter:GetStringHeight() + 7)
    end
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.status:SetPoint("RIGHT", row.remove, "LEFT", -12, 0)
    row.status:SetWidth(STATUS_WIDTH)
    row.status:SetJustifyH("RIGHT")
    row.crafter:SetPoint("RIGHT", row.status, "LEFT", -12, 0)
    return math.max(CRAFT_ROW + 4, row.text:GetStringHeight() + 8)
end


local function MaterialHeight(m)
    local cols = current.cols
    local tallest = math.max(ns.UI.TextHeight(m.name, cols.nameWidth - (m.depth or 0) * 14),
        cols.showWhere and ns.UI.TextHeight(m.where, cols.whereWidth, SMALL) or 0,
        ns.UI.TextHeight(m.missing, cols.missingWidth, SMALL))
    return math.max(MATERIAL_ROW, math.ceil(tallest + 10))
end

local function InitMaterialRow(row, m)
    if not row.made then
        row.made = true
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.need = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.missing = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        for _, f in ipairs({ row.name, row.need, row.where, row.missing }) do f:SetJustifyH("LEFT") end
        row.line = ns.UI.Divider(row)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        ns.UI.ItemHover(row, function(self) return self.itemID end, "OnClick")
    end
    row.itemID = m.itemID
    local cols = current.cols
    local indent = (m.depth or 0) * 14
    row.name:SetPoint("LEFT", cols.name + indent, 0)
    row.name:SetWidth(cols.nameWidth - indent)
    row.need:SetPoint("LEFT", cols.need, 0)
    row.where:SetPoint("LEFT", cols.where, 0)
    row.where:SetWidth(cols.whereWidth)
    row.missing:SetPoint("LEFT", cols.missing, 0)
    row.missing:SetWidth(cols.missingWidth)
    row.name:SetText(indent > 0 and Color(TEXT.light, m.name) or m.name)
    row.need:SetText(tostring(m.need))
    row.where:SetText(Color(TEXT.light, m.where))
    row.where:SetShown(cols.showWhere)
    row.missing:SetText(Color(m.missingColor, m.missing))
end

local Money = ns.UI.Money

local function BuyKey(buy)
    local parts = {}
    for _, b in ipairs(buy) do parts[#parts + 1] = b.itemID .. ":" .. b.count end
    return table.concat(parts, ",")
end

local function Answer(text, color)
    current.answer = { key = BuyKey(current.buy), text = text, color = color }
    print(ns.UI.ColorText(TEXT.chatName, "Altisan") .. " " .. text)
    ns.RefreshWindow()
end

-- Auctionator searches by name, so an item whose name isn't loaded yet is left out.
local function SendNow()
    local items, skipped = {}, 0
    local hasAH = ns.AH.Available()
    for _, b in ipairs(current.buy) do
        local name = C_Item.GetItemNameByID(b.itemID)
        if not name then
            skipped = skipped + 1
        elseif not (hasAH and (b.vendor or b.favor)) then
            items[#items + 1] = { name = name, count = b.buyCount, vendor = b.vendor ~= nil or b.favor }
        end
    end
    local note = skipped > 0 and (" %d without a name yet left out: press again in a moment."):format(skipped) or ""
    if ns.AH.Available() then
        local ok = #items > 0 and ns.AH.MakeShoppingList(items)
        if ok then
            Answer(("List made: \"%s\", %s. At the auction house, open Auctionator's Shopping tab and pick it.")
                   :format(ns.AH.LIST_NAME, ns.UI.Count(#items, "item", "items")) .. note, skipped > 0 and TEXT.amber or TEXT.green)
        else
            Answer("Auctionator didn't take the list. Check that Auctionator is up to date." .. note, TEXT.amber)
        end
    else
        local vendorLines, lines = {}, {}
        for _, item in ipairs(items) do
            table.insert(item.vendor and vendorLines or lines, ("%d × %s%s"):format(item.count, item.name, item.vendor and " (vendor)" or ""))
        end
        for i, line in ipairs(vendorLines) do table.insert(lines, i, line) end
        current.copying = { key = BuyKey(current.buy), text = table.concat(lines, "\n"), focus = true }
        if skipped > 0 then Answer(note:sub(2), TEXT.amber) else ns.RefreshWindow() end
    end
end

-- Forever keeps the clipboard to Blizzard's own UI, so "Copy list" shows the list selected in
-- a text box instead: Ctrl+C copies it.
local function StopCopying()
    current.copying = nil
    if panel.copyBox then panel.copyBox:ClearFocus() end
    ns.RefreshWindow()
end

-- Names come from the item cache: wait for missing ones, with a timeout since one may never arrive.
local function SendToBuyList()
    if current.waiting then return end
    local missing = {}
    for _, b in ipairs(current.buy) do
        local exists = not C_Item.DoesItemExistByID or C_Item.DoesItemExistByID(b.itemID)
        if exists and not C_Item.GetItemNameByID(b.itemID) then missing[#missing + 1] = b.itemID end
    end
    if #missing == 0 then
        SendNow()
        return
    end
    current.waiting = true
    ns.RefreshWindow()
    local left = #missing
    local function Done()
        if not current.waiting then return end
        current.waiting = false
        SendNow()
    end
    for _, itemID in ipairs(missing) do
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            left = left - 1
            if left == 0 then Done() end
        end)
    end
    C_Timer.After(3, Done)
end

function Shop.Refresh(list, width, height, layoutOnly)
    local reuse = layoutOnly and current.plan
    local plan = ns.UI.Data("shopping", layoutOnly, function() return ns.ShoppingPlan(list) end)
    current.plan = plan
    current.buy = plan.buy
    local leftWidth = width - RIGHT_WIDTH - GAP

    local crafts = panel.crafts
    crafts:SetWidth(leftWidth)
    crafts.hint:SetShown(32 + crafts.title:GetStringWidth() + 24 + crafts.hint:GetStringWidth() <= leftWidth)
    local y = -36
    local rowWidth = leftWidth - 32
    for i = 1, math.min(#plan.crafts, MAX_CRAFTS) do
        local c, row = plan.crafts[i], GetCraftRow(i)
        row.index, row.planIndex, row.name, row.recipe = c.index, c.planIndex, c.name, c.track and c.track.recipe
        row.stepper:SetShown(c.track ~= nil)
        if c.track then row.stepper:SetValue(c.track.count) end
        row.icon:SetTexture(c.icon or 134400)
        row.text:SetText(c.name)
        row.crafter:SetText(c.crafter)
        row.status:SetText(Color(c.statusColor, c.status))
        local height = PlaceCraftRow(row, rowWidth)
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, y)
        row:SetPoint("TOPRIGHT", -16, y)
        row:Show()
        y = y - height
    end
    for i = math.min(#plan.crafts, MAX_CRAFTS) + 1, #craftRows do craftRows[i]:Hide() end
    crafts.more:SetShown(#plan.crafts > MAX_CRAFTS)
    if #plan.crafts > MAX_CRAFTS then
        crafts.more:SetPoint("TOPLEFT", 16, y - 2)
        crafts.more:SetText(("and %d more"):format(#plan.crafts - MAX_CRAFTS))
        y = y - 18
    end
    crafts.empty:SetShown(#plan.crafts == 0)
    crafts.empty:SetWidth(leftWidth - 32)
    if #plan.crafts == 0 then y = y - crafts.empty:GetStringHeight() - 20 end
    local craftsHeight = -y + 10
    crafts:SetHeight(craftsHeight)

    local materials = panel.materials
    local materialsY = ns.UI.Below(PAGE.top, craftsHeight)
    materials:ClearAllPoints()
    materials:SetPoint("TOPLEFT", 0, materialsY)
    materials:SetPoint("BOTTOMLEFT", 0, 0)
    materials:SetWidth(leftWidth)
    local inner = leftWidth - 32
    local cols = { name = 0 }
    cols.showWhere = inner >= WHERE_ROOM
    cols.nameWidth = cols.showWhere and math.floor(inner * 0.32) or (inner - 50 - 80 - 24)
    cols.need = cols.nameWidth + 12
    cols.where = cols.need + 50 + 12
    cols.whereWidth = cols.showWhere and (inner - cols.where - 80 - 12) or 0
    cols.missing = cols.showWhere and (cols.where + cols.whereWidth + 12) or cols.where
    cols.missingWidth = inner - cols.missing
    current.cols = cols
    materials.whereLabel:SetShown(cols.showWhere)
    for key, x in pairs({ nameLabel = cols.name, needLabel = cols.need, whereLabel = cols.where, missingLabel = cols.missing }) do
        materials[key]:SetPoint("TOPLEFT", 16 + x, -36)
    end
    if not (reuse and ns.UI.RedrawRows(materials.list)) then
        materials.list.box:SetDataProvider(CreateDataProvider(plan.materials), ScrollBoxConstants.RetainScrollPosition)
    end
    materials.empty:SetShown(#plan.materials == 0)

    local me = ns.CharacterKey()
    local creates = {}
    for _, c in ipairs(plan.creates) do
        creates[#creates + 1] = (c.makerKey == me and "Create " or (c.maker .. Color(TEXT.soft, ": create "))) .. ("%d × %s"):format(c.count, c.name)
            .. (c.to and (Color(TEXT.soft, ", then mail them to ") .. c.to) or "")
    end
    panel.create:SetShown(#creates > 0)
    panel.create:Fit(panel.create:SetLines(creates, RIGHT_WIDTH))
    panel.mail:ClearAllPoints()
    if #creates > 0 then
        panel.mail:SetPoint("TOPRIGHT", panel.create, "BOTTOMRIGHT", 0, -PAGE.gap)
    else
        panel.mail:SetPoint("TOPRIGHT", 0, PAGE.top)
    end

    local mail = {}
    for _, p in ipairs(plan.pickup) do
        mail[#mail + 1] = Color(TEXT.soft, "Take from ") .. p.who .. Color(TEXT.soft, "'s mailbox")
        for _, line in ipairs(p.lines) do mail[#mail + 1] = Color(TEXT.light, line) end
    end
    for _, m in ipairs(plan.mail) do
        mail[#mail + 1] = m.from .. Color(TEXT.soft, " to ") .. m.to
        for _, line in ipairs(m.lines) do mail[#mail + 1] = Color(TEXT.light, line) end
    end
    if #mail == 0 then mail[1] = Color(TEXT.soft, #plan.crafts > 0 and "Nothing to mail." or "Track a craft to see what to mail where.") end
    mail[#mail + 1] = Color(TEXT.muted, "Send these from a mailbox. Altisan doesn't fill the send form yet.")
    panel.mail:Fit(panel.mail:SetLines(mail, RIGHT_WIDTH))

    local hasAH = ns.AH.Available()
    local copying = current.copying
    if copying and (hasAH or copying.key ~= BuyKey(plan.buy)) then
        copying, current.copying = nil, nil
    end
    local buy, lineItem, linePin, ahCount = {}, {}, {}, 0
    if not copying then
        local function For(b)
            local key = #b.forKeys == 1 and b.forKeys[1]
            local char = key and key ~= me and ns.db.characters[key]
            return char and Color(TEXT.soft, " for ") .. ShortName(char, key) or ""
        end
        local function VendorLines(b, cost)
            local place = b.vendor and b.vendor.places[1]
            buy[#buy + 1] = ("%d × %s"):format(b.buyCount, b.name) .. For(b) .. (cost and Color(TEXT.soft, ", " .. cost) or "")
            lineItem[#buy] = b.itemID
            if place then
                -- The trailing tab keeps room on the right for the pin.
                buy[#buy + 1] = Color(TEXT.soft, place.name .. (place.title and (", " .. place.title) or "") .. (place.zone and (", " .. place.zone) or "")) .. "\t"
                linePin[#buy] = place
            end
        end
        local vendorTotal, fromVendors, favorTotal, withFavor = 0, {}, 0, {}
        for _, b in ipairs(plan.buy) do
            if b.favor then
                withFavor[#withFavor + 1] = b
                local price = ns.Favor.ItemPrice(b.itemID)
                favorTotal = price and favorTotal and favorTotal + price * b.count or nil
            elseif b.vendor then
                fromVendors[#fromVendors + 1] = b
                vendorTotal = vendorTotal + (b.buyCost or 0)
            end
        end
        if #fromVendors > 0 then
            buy[#buy + 1] = Color(TEXT.muted, "From vendors") .. (vendorTotal > 0 and ("\t" .. Color(TEXT.muted, "about " .. ns.UI.RoughMoney(vendorTotal))) or "")
            for _, b in ipairs(fromVendors) do VendorLines(b, b.buyCost and Money(b.buyCost)) end
        end
        if #withFavor > 0 then
            buy[#buy + 1] = Color(TEXT.muted, "Bought with " .. ns.Favor.NAME)
                .. (favorTotal and ("\t" .. Color(TEXT.muted, ("%d %s"):format(favorTotal, ns.Favor.NAME))) or "")
            for _, b in ipairs(withFavor) do VendorLines(b, ns.Favor.CostText(b.itemID, b.count)) end
        end
        for _, b in ipairs(plan.buy) do
            if not b.vendor and not b.favor then
                if ahCount == 0 then buy[#buy + 1] = Color(TEXT.muted, "Auction house") end
                ahCount = ahCount + 1
                buy[#buy + 1] = ("%d × %s"):format(b.count, b.name) .. For(b)
                lineItem[#buy] = b.itemID
            end
        end
        if #buy == 0 then buy[1] = Color(TEXT.soft, "Nothing to buy.") end
    end
    local buyY = panel.buy:SetLines(buy, RIGHT_WIDTH)
    panel.buyPins = panel.buyPins or {}
    local pins = 0
    for i, place in pairs(linePin) do
        pins = pins + 1
        local pin = panel.buyPins[pins] or ns.UI.PinButton(panel.buy, ns.UI.CARD_PIN)
        panel.buyPins[pins] = pin
        pin:SetPlace(place)
        pin:ClearAllPoints()
        pin:SetPoint("TOPRIGHT", panel.buy.lines[i].right, "TOPRIGHT", 2, 3)
        pin:SetShown(ns.Places.CanPin(place))
    end
    for i = pins + 1, #panel.buyPins do panel.buyPins[i]:Hide() end
    local box = panel.copyBox
    box.frame:SetShown(copying ~= nil)
    if copying then
        local height = math.ceil(ns.UI.TextHeight(copying.text, RIGHT_WIDTH - 32 - 16, SMALL)) + 10
        box.frame:ClearAllPoints()
        box.frame:SetPoint("TOPLEFT", 16, -34)
        box.frame:SetSize(RIGHT_WIDTH - 32, height)
        if box:GetText() ~= copying.text then box:SetText(copying.text) end
        if copying.focus then
            copying.focus = nil
            box:SetFocus()
            box:HighlightText()
        end
        buyY = -34 - height - 4
    end
    panel.buyHits = panel.buyHits or {}
    local hits = 0
    for i, itemID in pairs(copying and {} or lineItem) do
        hits = hits + 1
        local hit = panel.buyHits[hits]
        if not hit then
            hit = CreateFrame("Button", nil, panel.buy)
            ns.UI.ItemHover(hit, function(self) return self.itemID end, "OnClick")
            panel.buyHits[hits] = hit
        end
        local line = panel.buy.lines[i].left
        hit.itemID = itemID
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", line, "TOPLEFT", -2, 2)
        hit:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 2, -2)
        hit:Show()
    end
    for i = hits + 1, #panel.buyHits do panel.buyHits[i]:Hide() end
    panel.buyButton:SetKind("primary", copying and "Done" or hasAH and "Send to Auctionator" or "Copy list")
    panel.buyButton:ClearAllPoints()
    panel.buyButton:SetPoint("TOPLEFT", 16, buyY - 6)
    local button = #plan.buy > 0 and (copying or not hasAH or ahCount > 0)
    panel.buyButton:SetShown(button)
    local y2 = buyY - (button and 40 or 4)
    local answer = current.answer
    local answerText
    if current.waiting then
        answerText = Color(TEXT.soft, "Getting item names from the game...")
    elseif answer and answer.key == BuyKey(plan.buy) and #plan.buy > 0 then
        answerText = Color(answer.color, answer.text)
    end
    panel.buyAnswer:SetShown(answerText ~= nil)
    if answerText then
        panel.buyAnswer:ClearAllPoints()
        panel.buyAnswer:SetPoint("TOPLEFT", 16, y2)
        panel.buyAnswer:SetText(answerText)
        y2 = y2 - panel.buyAnswer:GetStringHeight() - 6
    end
    panel.buyNote:ClearAllPoints()
    panel.buyNote:SetPoint("TOPLEFT", 16, y2)
    if copying then
        panel.buyNote:SetText(Color(TEXT.green, "Press Ctrl+C to copy.") .. "\nEscape or Done goes back to the list.")
    elseif hasAH then
        panel.buyNote:SetText(ahCount > 0 and (("Replaces the \"%s\" list in Auctionator's Shopping tab with the auction house items."):format(ns.AH.LIST_NAME)
                              .. " Shift-click an item to search for just that one at the auction house.")
                              or "Vendor prices are a vendor's base price, from Vanilla's data.")
    else
        panel.buyNote:SetText("Copies the list as text, one item per line.")
    end
    panel.buy:ClearAllPoints()
    panel.buy:SetPoint("TOPRIGHT", panel.mail, "BOTTOMRIGHT", 0, -PAGE.gap)
    panel.buy:SetHeight(-y2 + panel.buyNote:GetStringHeight() + 12)
end

local Card = ns.UI.TitledCard

function Shop.Build(parent)
    local UI = ns.UI
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.shopping = true
    craftRows = {}

    panel.crafts = Card(panel, "Tracked crafts")
    panel.crafts:SetPoint("TOPLEFT", 0, PAGE.top)
    panel.crafts.hint = panel.crafts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.crafts.hint:SetPoint("TOPRIGHT", -16, -14)
    panel.crafts.hint:SetText("Track from Coverage or a recipe list")
    panel.crafts.empty = panel.crafts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.crafts.empty:SetPoint("TOPLEFT", 16, -36)
    panel.crafts.empty:SetPoint("TOPRIGHT", -16, -36)
    panel.crafts.empty:SetJustifyH("LEFT")
    panel.crafts.empty:SetText("Nothing tracked yet. Track a recipe from its card on Coverage, or right-click it in a character's recipe list.")
    panel.crafts.more = panel.crafts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    local materials = Card(panel, "Materials")
    panel.materials = materials
    for key, text in pairs({ nameLabel = "Material", needLabel = "Need", whereLabel = "On your characters", missingLabel = "Missing" }) do
        materials[key] = materials:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        materials[key]:SetText(text)
    end
    local line = UI.Divider(materials)
    line:SetPoint("TOPLEFT", 16, -52)
    line:SetPoint("TOPRIGHT", -16, -52)
    materials.footer = materials:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    materials.footer:SetPoint("BOTTOMLEFT", 16, 10)
    materials.footer:SetText("Bank counts are from each character's last bank visit.")
    local listFrame = CreateFrame("Frame", nil, materials)
    listFrame:SetPoint("TOPLEFT", 16, -56)
    listFrame:SetPoint("BOTTOMRIGHT", -10, 28)
    materials.list = UI.ScrollList(listFrame, MaterialHeight, InitMaterialRow)
    UI.PlaceList(materials.list, 0)
    materials.empty = materials:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    materials.empty:SetPoint("TOPLEFT", 16, -62)
    materials.empty:SetText("The materials of what you track show up here.")

    panel.create = Card(panel, "Create first")
    panel.create:SetPoint("TOPRIGHT", 0, PAGE.top)
    panel.create:SetWidth(RIGHT_WIDTH)
    panel.mail = Card(panel, "Mail plan")
    panel.mail:SetPoint("TOPRIGHT", 0, PAGE.top)
    panel.mail:SetWidth(RIGHT_WIDTH)
    panel.buy = Card(panel, "To buy")
    panel.buy:SetWidth(RIGHT_WIDTH)
    panel.buyButton = UI.Button(panel.buy, "Copy list")
    panel.buyButton:SetScript("OnClick", function()
        if current.copying then StopCopying() else SendToBuyList() end
    end)
    local copyFrame = UI.InputFrame(panel.buy)
    copyFrame:Hide()
    local box = CreateFrame("EditBox", nil, copyFrame)
    box:SetPoint("TOPLEFT", 8, -5)
    box:SetPoint("BOTTOMRIGHT", -8, 5)
    box:SetMultiLine(true)
    box:SetFontObject("GameFontHighlightSmall")
    UI.ReadOnly(box, function() return current.copying and current.copying.text end, StopCopying)
    box.frame = copyFrame
    panel.copyBox = box
    panel:SetScript("OnHide", function() current.copying = nil end)
    panel.buyNote = panel.buy:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.buyNote:SetWidth(RIGHT_WIDTH - 32)
    panel.buyNote:SetJustifyH("LEFT")
    panel.buyAnswer = panel.buy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.buyAnswer:SetWidth(RIGHT_WIDTH - 32)
    panel.buyAnswer:SetJustifyH("LEFT")
    panel.buyAnswer:SetSpacing(2)
    return panel
end

ns.UI.AddPage("shopping", Shop)
