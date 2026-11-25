-- Text.lua: the words and colors pages share: text colors (UI.TEXT) and their helpers, counts and
-- name lists, character names, money, tooltip lines, text measuring, item names and clicks, times ago.

local _, ns = ...
local UI = ns.UI
local P, GAME = UI.PALETTE, UI.GAME

function UI.ColorText(hex, text)
    return "|cff" .. hex .. text .. "|r"
end

function UI.Plural(n, one, many) return n == 1 and one or many end

function UI.Count(n, one, many) return n .. " " .. UI.Plural(n, one, many) end

function UI.JoinNames(names, word, hex)
    if #names <= 1 then return names[1] or "" end
    local comma, last = ", ", " " .. (word or "and") .. " "
    if hex then comma, last = UI.ColorText(hex, comma), UI.ColorText(hex, last) end
    return table.concat(names, comma, 1, #names - 1) .. last .. names[#names]
end

UI.TEXT = {
    gold = P.gold,
    body = P.body,
    light = P.light,
    soft = P.soft,
    muted = P.muted,
    canLearn = P.parchment,
    needsSkill = P.dim,
    green = P.green,
    amber = P.amber,
    white = GAME.white,
    effect = GAME.effect,
    stat = GAME.stat,
    chatName = P.brass,
    place = P.brass,
    bullet = P.bronze,
}

function UI.Soft(text) return UI.ColorText(UI.TEXT.soft, text) end

function UI.Gold(text) return UI.ColorText(UI.TEXT.gold, text) end

-- The window's darker greys don't read on a tooltip.
function UI.Light(text) return UI.ColorText(UI.TEXT.light, text) end

function UI.TipLine(tooltip, text, color, wrap)
    local r, g, b = unpack(UI.Hex(UI.TEXT[color or "white"]))
    tooltip:AddLine(text, r, g, b, wrap)
end

function UI.TipDoubleLine(tooltip, left, right, leftColor, rightColor)
    local r, g, b = unpack(UI.Hex(UI.TEXT[leftColor or "white"]))
    local r2, g2, b2 = unpack(UI.Hex(UI.TEXT[rightColor or "white"]))
    tooltip:AddDoubleLine(left, right, r, g, b, r2, g2, b2)
end

UI.FACTION = { Horde = P.horde, Alliance = P.alliance }

function UI.FactionText(faction)
    return faction and UI.ColorText(UI.FACTION[faction] or UI.TEXT.body, faction) or ""
end

function UI.Money(copper)
    copper = math.floor(copper + 0.5)
    local parts = {}
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if copper % 100 > 0 or #parts == 0 then parts[#parts + 1] = (copper % 100) .. "c" end
    return table.concat(parts, " ")
end

function UI.RoughMoney(copper)
    if copper >= 1000000 then return math.floor(copper / 10000 + 0.5) .. "g" end
    if copper >= 100 then return UI.Money(math.floor(copper / 100 + 0.5) * 100) end
    return math.floor(copper + 0.5) .. "c"
end

function UI.CharName(char, key)
    local name = char and char.name
    if not name then return key or "?" end
    for _, other in pairs(ns.db.characters) do
        if other ~= char and other.name == name then return char.fullName or name end
    end
    return name
end

function UI.ShortName(entryOrChar, key)
    local char = entryOrChar and entryOrChar.char or entryOrChar
    key = entryOrChar and entryOrChar.key or key
    local name = UI.CharName(char, key)
    local color = char and char.class and RAID_CLASS_COLORS[char.class]
    return color and color:WrapTextInColorCode(name) or name
end

function UI.ShortNames(entries)
    local names = {}
    for i, e in ipairs(entries) do names[i] = UI.ShortName(e) end
    return names
end

local measurers = {}

function UI.TextHeight(text, width, fontObject, spacing)
    fontObject, spacing = fontObject or "GameFontHighlight", spacing or 0
    local id = fontObject .. ":" .. spacing
    local m = measurers[id]
    if not m then
        m = UIParent:CreateFontString(nil, "OVERLAY", fontObject)
        m:SetSpacing(spacing)
        m:Hide()
        measurers[id] = m
    end
    m:SetWidth(width)
    m:SetText(text or "")
    return m:GetStringHeight()
end

function UI.TextWidth(text, fontObject)
    UI.TextHeight(text, 0, fontObject)
    return measurers[(fontObject or "GameFontHighlight") .. ":0"]:GetStringWidth()
end

UI.PAIR_GAP = 12
local function PairWidths(leftWidth, rightWidth, width, room)
    local keep = math.max(rightWidth, room or 0)
    if keep == 0 then return width end
    if rightWidth == 0 or leftWidth + UI.PAIR_GAP + keep <= width then return width - keep - UI.PAIR_GAP end
    return width, width - UI.PAIR_GAP
end

function UI.FitPair(left, right, width, room)
    left:SetWidth(0)
    right:SetWidth(0)
    local leftWidth, under = PairWidths(left:GetStringWidth(), right:GetStringWidth(), width, room)
    left:SetWidth(leftWidth)
    right:SetJustifyH(under and "LEFT" or "RIGHT")
    if under then right:SetWidth(under) end
    return under ~= nil
end

function UI.PairHeight(left, right, width, leftFont, rightFont)
    local leftWidth, under = PairWidths(UI.TextWidth(left, leftFont), UI.TextWidth(right, rightFont), width)
    local leftHeight = UI.TextHeight(left, leftWidth, leftFont)
    if under then return leftHeight + 2 + UI.TextHeight(right, under, rightFont), true end
    return math.max(leftHeight, right ~= "" and UI.TextHeight(right, 0, rightFont) or 0), false
end

local pending, redrawSoon = {}, {}
function UI.WhenItemLoads(itemID, fn)
    redrawSoon[fn] = true
    if not pending[itemID] and Item and Item.CreateFromItemID
        and (not C_Item.DoesItemExistByID or C_Item.DoesItemExistByID(itemID)) then
        pending[itemID] = true
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pending[itemID] = nil
            if UI.redrawTimer then return end
            UI.redrawTimer = true
            C_Timer.After(0.1, function()
                UI.redrawTimer = nil
                local calls = redrawSoon
                redrawSoon = {}
                for call in pairs(calls) do call() end
            end)
        end)
    end
end

function UI.ItemName(itemID, redraw)
    local name = C_Item.GetItemNameByID(itemID)
    if name then return name end
    if redraw then UI.WhenItemLoads(itemID, redraw) end
    return nil
end

function UI.ItemLabel(itemID, redraw)
    return UI.ItemName(itemID, redraw or UI.RedrawWindow) or ("Item " .. itemID)
end

function UI.ReagentLine(itemID, count, held, redraw)
    return ("%d × %s"):format(count, UI.ItemLabel(itemID, redraw)), UI.Soft(held)
end

function UI.InsertLink(link)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    return insert and link and insert(link) and true or false
end

function UI.ItemClick(itemID)
    if not itemID then return false end
    local _, link = C_Item.GetItemInfo(itemID)
    if not link then
        C_Item.RequestLoadItemDataByID(itemID)
        return false
    end
    if HandleModifiedItemClick then return HandleModifiedItemClick(link) and true or false end
    return IsModifiedClick("CHATLINK") and UI.InsertLink(link) or false
end

function UI.RedrawWindow()
    ns.RefreshWindow()
end

function UI.TimeAgo(when)
    local seconds = math.max(0, time() - (when or 0))
    if seconds < 90 then return "just now" end
    local minutes = math.floor(seconds / 60)
    if minutes < 90 then return minutes .. " minutes ago" end
    local hours = math.floor(minutes / 60)
    if hours < 36 then return hours .. " hours ago" end
    return math.floor(hours / 24) .. " days ago"
end

function UI.ScanTime(when)
    if not when then return nil end
    local day = date("%Y%m%d", when)
    local clock = date("%H:%M", when)
    if day == date("%Y%m%d") then return "today, " .. clock end
    if day == date("%Y%m%d", time() - 86400) then return "yesterday, " .. clock end
    return UI.TimeAgo(when)
end
