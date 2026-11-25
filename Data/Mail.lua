-- Mail.lua: crafting items in each character's mailbox, read while it's open, and items mailed to
-- your own characters, counted the moment Send succeeds. A count leaves when its mail would expire.

local _, ns = ...

local Mail = {}
ns.Mail = Mail

local DAY = 86400
-- Blizzard's ATTACHMENTS_MAX_RECEIVE / _SEND live in MailFrame, which loads on demand.
local RECEIVE_SLOTS, SEND_SLOTS = 16, 12
local SENT_DAYS = 30

local function Totals(lots)
    local items = {}
    for _, lot in ipairs(lots) do items[lot.itemID] = (items[lot.itemID] or 0) + lot.count end
    return items
end

function Mail.Prune(char, now)
    local mail = char.mail
    if not (mail and mail.lots) then return false end
    local kept = {}
    for _, lot in ipairs(mail.lots) do
        if lot.expires > now then kept[#kept + 1] = lot end
    end
    if #kept == #mail.lots then return false end
    mail.lots, mail.items = kept, Totals(kept)
    return true
end

function Mail.PruneAll()
    local now = time()
    for _, char in pairs(ns.db.characters) do Mail.Prune(char, now) end
end

local open = false

-- Only the first 100 mails are readable; the rest show up once some are taken.
function Mail.Read()
    local char = open and ns.CurrentCharacter()
    if not char then return end
    local now, lots = time(), {}
    for index = 1, (GetInboxNumItems()) or 0 do
        local _, _, _, _, _, cod, daysLeft, itemCount = GetInboxHeaderInfo(index)
        if (cod or 0) == 0 and (itemCount or 0) > 0 then
            for slot = 1, RECEIVE_SLOTS do
                local _, itemID, _, count = GetInboxItem(index, slot)
                if itemID and ns.ItemUses.IsCraftingItem(itemID) then
                    lots[#lots + 1] = { itemID = itemID, count = count or 1, expires = now + math.floor((daysLeft or 0) * DAY) }
                end
            end
        end
    end
    ns.Bags.Store(char, "mail", Totals(lots)).lots = lots
end

-- Until Blizzard's MAIL_INBOX_UPDATE the inbox may read empty, and an empty read would wipe the
-- saved count.
function Mail.OnShow() open = true end

function Mail.OnClosed() open = false end

local function Receiver(typed)
    local me = ns.CurrentCharacter()
    local name, realm = strsplit("-", typed or "")
    if not (me and name and name ~= "") then return nil end
    if realm and realm ~= "" and realm:gsub("%s", "") ~= me.realm then return nil end
    for _, char in pairs(ns.db.characters) do
        if char ~= me and char.name and char.name:lower() == name:lower() and ns.Bags.CanMail(me, char) then return char end
    end
end

local sending

function Mail.OnSend(recipient)
    sending = nil
    local char = Receiver(recipient)
    if not char or (GetSendMailCOD() or 0) > 0 then return end
    local lots, expires = {}, time() + SENT_DAYS * DAY
    for slot = 1, SEND_SLOTS do
        local _, itemID, _, count = GetSendMailItem(slot)
        if itemID and ns.ItemUses.IsCraftingItem(itemID) then
            lots[#lots + 1] = { itemID = itemID, count = count or 1, expires = expires }
        end
    end
    if #lots > 0 then sending = { char = char, lots = lots } end
end

function Mail.OnSendSuccess()
    local s = sending
    sending = nil
    if not s then return end
    local mail = s.char.mail or { items = {}, lots = {} }
    s.char.mail = mail
    mail.lots = mail.lots or {}
    for _, lot in ipairs(s.lots) do table.insert(mail.lots, lot) end
    mail.items = Totals(mail.lots)
    ns.RefreshWindow()
end

function Mail.OnSendFailed() sending = nil end

function Mail.Init()
    Mail.PruneAll()
    hooksecurefunc("SendMail", function(recipient) Mail.OnSend(recipient) end)
end
