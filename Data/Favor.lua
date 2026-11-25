-- Favor.lua: recipes bought with Merchant's Favor at the profession quartermasters, and their prices,
-- saved for the account (favorPrice[itemID] = cost) when a player opens a quartermaster's shop.

local _, ns = ...

local Favor = {}
ns.Favor = Favor

local CURRENCY = 3402
Favor.NAME = ns.FAVOR_NAME

-- The game says which NPCs sell for Favor only in their shop, so the quartermasters are listed by
-- ID.
local QUARTERMASTERS = {}
for id = 248196, 248202 do QUARTERMASTERS[id] = true end
for id = 256729, 256735 do QUARTERMASTERS[id] = true end

local function OnlyQuartermasters(ids)
    if not ids or #ids == 0 then return false end
    for _, v in ipairs(ids) do
        if not QUARTERMASTERS[type(v) == "table" and v.id or v] then return false end
    end
    return true
end

local recipes = {}
function Favor.IsRecipe(recipeID)
    if recipes[recipeID] == nil then
        local sources = ns.RecipeSources(recipeID)
        recipes[recipeID] = OnlyQuartermasters(sources and sources.vendor)
    end
    return recipes[recipeID]
end

function Favor.IsItem(itemID)
    return OnlyQuartermasters(ns.QuestieForever and ns.QuestieForever.itemVendors[itemID])
end

-- The library's price is the Alliance quartermasters' on both sides.
function Favor.ItemPrice(itemID)
    if ns.db.favorPrice[itemID] then return ns.db.favorPrice[itemID] end
    for _, use in ipairs(ns.ItemUses.Teaches(itemID) or {}) do
        for _, entry in ipairs((ns.RecipeSources(use.recipe) or {}).vendor or {}) do
            for _, part in ipairs(entry.cost or {}) do
                if part.currencyID == CURRENCY then return part.amount end
            end
        end
    end
end

local function Quartermaster(recipeID)
    for _, entry in ipairs(ns.RecipeSources(recipeID).vendor) do
        local npc = ns.Places.NPC(entry.id)
        if npc and ns.Places.OnMySide(npc.friendlyToFaction) then return npc.name end
    end
end

function Favor.CostText(itemID, count)
    local price = itemID and Favor.ItemPrice(itemID)
    return price and ("%d %s"):format(price * (count or 1), Favor.NAME) or Favor.NAME
end

function Favor.Lines(recipeID)
    if not Favor.IsRecipe(recipeID) then return nil end
    local itemID = ns.RecipeItem(recipeID)
    if itemID and Favor.ItemPrice(itemID) then
        return { ("Costs %s, not gold."):format(Favor.CostText(itemID)) }
    end
    local who = Quartermaster(recipeID)
    return { ("Costs %s, not gold."):format(Favor.NAME),
             ns.UI.Soft(("The price shows here after you talk to %s once."):format(who or "the quartermaster")) }
end

function Favor.ReadMerchant()
    if not (GetMerchantNumItems and GetMerchantItemID and GetMerchantItemCostInfo and GetMerchantItemCostItem
            and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyIDFromLink) then return end
    local changed = false
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        for c = 1, itemID and GetMerchantItemCostInfo(i) or 0 do
            local _, value, link = GetMerchantItemCostItem(i, c)
            if link and value and C_CurrencyInfo.GetCurrencyIDFromLink(link) == CURRENCY
               and ns.db.favorPrice[itemID] ~= value then
                ns.db.favorPrice[itemID] = value
                changed = true
            end
        end
    end
    if changed then ns.RefreshWindow() end
end
