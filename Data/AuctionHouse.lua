-- AuctionHouse.lua: the only file that talks to Auctionator (optional), via Auctionator.API.v1.
-- Its code is All Rights Reserved: never copy it. Every call is pcall'd: bad input raises errors.

local _, ns = ...

local AH = {}
ns.AH = AH

local CALLER = "Altisan"
AH.LIST_NAME = "Altisan"

local function API()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function Call(name, ...)
    local api = API()
    local fn = api and api[name]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, CALLER, ...)
    if ok then return result end
    AH.lastError = result
    return nil
end

function AH.Available()
    local api = API()
    return api ~= nil and type(api.CreateShoppingList) == "function" and type(api.ConvertToSearchString) == "function"
end

function AH.GetPrice(itemID)
    return Call("GetAuctionPriceByItemID", itemID)
end

-- Names, not IDs: Auctionator searches by name.
function AH.MakeShoppingList(items)
    if not AH.Available() then return false end
    local strings = {}
    for _, item in ipairs(items) do
        -- These three characters break Auctionator's search format.
        local clean = (item.name or ""):gsub('[;%^"]', "")
        if clean ~= "" then
            local s = Call("ConvertToSearchString", { searchString = clean, isExact = true, quantity = item.count })
            if s then strings[#strings + 1] = s end
        end
    end
    if #strings == 0 then return false end
    local ok = pcall(API().CreateShoppingList, CALLER, AH.LIST_NAME, strings)
    return ok
end
