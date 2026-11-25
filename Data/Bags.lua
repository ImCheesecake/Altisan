-- Bags.lua: counts crafting items (reagents and recipe items) in bags, banks and mail, per character,
-- for "who holds what". The bank is only readable while it's open.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

local function IsCraftingItem(itemID)
    return ns.ItemUses.IsCraftingItem(itemID)
end

local function Read(containers, items)
    for _, bag in ipairs(containers) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and IsCraftingItem(itemID) then
                items[itemID] = (items[itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return items
end

local function BagContainers()
    local list = { 0, 1, 2, 3, 4 }
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then table.insert(list, Enum.BagIndex.ReagentBag) end
    return list
end

-- Forever's bank has tabs: every purchased tab of each viewable bank type.
local function BankContainers()
    local out = { character = {}, account = {} }
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType then
        for kind, bankType in pairs({ character = Enum.BankType.Character, account = Enum.BankType.Account }) do
            if bankType and (not C_Bank.CanViewBank or C_Bank.CanViewBank(bankType)) then
                for _, tab in ipairs(C_Bank.FetchPurchasedBankTabData(bankType) or {}) do
                    if tab.ID then table.insert(out[kind], tab.ID) end
                end
            end
        end
    elseif BANK_CONTAINER then
        -- Older clients without bank tabs.
        table.insert(out.character, BANK_CONTAINER)
        for bag = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7) do
            table.insert(out.character, bag)
        end
    end
    return out
end

local function Same(a, b)
    a, b = a or {}, b or {}
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Redraws only when counts changed: looting fires bag updates constantly.
function Bags.Store(holder, field, items)
    local changed = not (holder[field] and Same(holder[field].items, items))
    holder[field] = { scanned = time(), items = items }
    if changed then ns.RefreshWindow() end
    return holder[field]
end
local Store = Bags.Store

-- In the order a crafter uses them up: the order matters.
Bags.PLACES = {
    { field = "bags" },
    { field = "bank", from = " (from bank)", word = "bank" },
    { field = "mail", from = " (from mailbox)", word = "mail" },
}

function Bags.Held(char, itemID)
    local n = 0
    for _, place in ipairs(Bags.PLACES) do
        local data = char and char[place.field]
        n = n + (data and data.items and data.items[itemID] or 0)
    end
    return n
end

function Bags.InBags(char, itemID)
    return char and char.bags and char.bags.items and char.bags.items[itemID] or 0
end

function Bags.ScanBags()
    local char = ns.CurrentCharacter()
    if not char then return end
    Store(char, "bags", Read(BagContainers(), {}))
end

local bankOpen = false
Bags.lastBank = nil

function Bags.ScanBank()
    if not bankOpen then return end
    local char = ns.CurrentCharacter()
    if not char then return end
    local containers = BankContainers()
    Bags.lastBank = containers
    if #containers.character > 0 then Store(char, "bank", Read(containers.character, {})) end
    if #containers.account > 0 then Store(ns.db, "accountBank", Read(containers.account, {})) end
end

-- Bags change in bursts (looting, stacking): read once things settle.
local pending = false
local function Soon(fn)
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        fn()
    end)
end

function Bags.OnBagsChanged()
    Soon(function()
        Bags.ScanBags()
        Bags.ScanBank()   -- moving items between bags and bank changes both
    end)
end

function Bags.OnBankOpened()
    bankOpen = true
    Bags.ScanBank()
end

function Bags.OnBankClosed()
    bankOpen = false
end

function Bags.IsBankOpen() return bankOpen end

-- Mail only reaches the same faction on the same realm (Forever's rulesets are realms too).
function Bags.CanMail(from, to)
    if from == to then return true end
    return from.realm == to.realm and (not from.faction or not to.faction or from.faction == to.faction)
end

function Bags.CanReach(list, char, exceptKey)
    local out = {}
    for _, entry in ipairs(list) do
        if entry.key ~= exceptKey and Bags.CanMail(entry.char, char) then out[#out + 1] = entry end
    end
    return out
end

function Bags.Holders(itemID, list)
    local places, total = {}, 0
    for _, entry in ipairs(list) do
        local char = entry.char
        for _, place in ipairs(Bags.PLACES) do
            local data = char[place.field]
            local count = data and data.items and data.items[itemID]
            if count and count > 0 then
                total = total + count
                table.insert(places, { name = ns.UI.CharName(char, entry.key), count = count, char = char,
                                       field = place.field, word = place.word, order = #places })
            end
        end
    end
    local account = ns.db.accountBank and ns.db.accountBank.items and ns.db.accountBank.items[itemID]
    if account and account > 0 then
        total = total + account
        table.insert(places, { name = "Account bank", count = account, order = #places })
    end
    table.sort(places, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.order < b.order
    end)
    return total, places
end

local function PerCharacter(holders, skipBagsOf)
    local byChar, out = {}, {}
    for _, h in ipairs(holders) do
        if not (skipBagsOf and h.char == skipBagsOf and h.field == "bags") then
            local key = h.char or h.name
            local c = byChar[key]
            if not c then
                c = { name = h.name, count = 0, away = {}, first = #out + 1 }
                byChar[key], out[#out + 1] = c, c
            end
            c.count = c.count + h.count
            if h.word then c.away[#c.away + 1] = h end
        end
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.first < b.first
    end)
    for _, c in ipairs(out) do
        c.label = c.name .. " " .. c.count
        if #c.away == 1 and c.away[1].count == c.count then
            c.label = ("%s (in %s)"):format(c.label, c.away[1].word)
        elseif #c.away > 0 then
            local parts = {}
            for i, h in ipairs(c.away) do parts[i] = ("%d in %s"):format(h.count, h.word) end
            c.label = ("%s (%s)"):format(c.label, table.concat(parts, ", "))
        end
    end
    return out
end

function Bags.HeldText(itemID, list, opts)
    opts = opts or {}
    local max = opts.max or 3
    local total, holders = Bags.Holders(itemID, list)
    local held, left = {}, 0
    for _, c in ipairs(PerCharacter(holders, opts.skipBagsOf)) do
        if #held < max then held[#held + 1] = c.label else left = left + 1 end
    end
    if opts.more and left > 0 then held[#held + 1] = left .. " more" end
    if #held == 0 then return opts.empty or "nobody on your account", 0, total end
    return table.concat(held, opts.sep or ", "), #held, total
end

function Bags.DebugLines()
    local char = ns.CurrentCharacter()
    local lines = {}
    local function Count(data)
        local n = 0
        for _ in pairs(data and data.items or {}) do n = n + 1 end
        return n
    end
    lines[1] = ("  Bags: %d crafting items%s"):format(Count(char and char.bags),
        char and char.bags and (", read " .. ns.UI.ScanTime(char.bags.scanned)) or ", not read yet")
    lines[2] = ("  Bank: %d crafting items%s"):format(Count(char and char.bank),
        char and char.bank and (", read " .. ns.UI.ScanTime(char.bank.scanned)) or ", not read yet (open the bank once)")
    lines[#lines + 1] = ("  Mailbox: %d crafting items%s"):format(Count(char and char.mail),
        char and char.mail and char.mail.scanned and (", read " .. ns.UI.ScanTime(char.mail.scanned)) or ", not read yet (open a mailbox once)")
    if Bags.lastBank then
        lines[#lines + 1] = ("    last bank visit: character containers %s, account containers %s"):format(
            table.concat(Bags.lastBank.character, ","), #Bags.lastBank.account > 0 and table.concat(Bags.lastBank.account, ",") or "none")
    end
    return lines
end
