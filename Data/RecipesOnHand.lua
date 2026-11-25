-- RecipesOnHand.lua: recipe items in bags, banks and mail that someone on the account can still
-- learn, and who, for Next up. A pattern every Tailor already knows isn't listed, nor one only
-- the other faction (or another realm) holds.

local _, ns = ...

local OnHand = {}
ns.RecipesOnHand = OnHand

local ShortName = ns.UI.ShortName

local WHERE = { bags = "in %s's bags", bank = "in %s's bank", mail = "in %s's mailbox" }

local function Where(place)
    if not place.char then return "in the account bank" end
    return WHERE[place.field]:format(ns.UI.CharName(place.char))
end

local function ReachablePlace(places, char)
    for _, place in ipairs(places) do
        if not place.char or ns.Bags.CanMail(place.char, char) then return place end
    end
end

function OnHand.Items(list)
    local seen, items = {}, {}
    local function Consider(itemID)
        if seen[itemID] then return end
        seen[itemID] = true
        local teaches = ns.ItemUses.Teaches(itemID)
        if not teaches then return end
        local _, places = ns.Bags.Holders(itemID, list)
        local wanted = {}
        for _, t in ipairs(teaches) do
            if not ns.Ignore.Is(t.recipe) then wanted[#wanted + 1] = t end
        end
        for _, t in ipairs(wanted) do
            local required
            local best
            for _, entry in ipairs(list) do
                for _, prof in ipairs(entry.char.professions or {}) do
                    local scan = prof.skillLine == t.prof and ns.GetProfessionRecipes(entry.char, t.prof)
                    -- Only what the character's own window listed as unlearned: that leaves out
                    -- recipes Forever can't teach (the other faction's are listed too).
                    local place = scan and scan.unknown[t.recipe] and ReachablePlace(places, entry.char)
                    if place then
                        local gap
                        required, gap = ns.SkillGap(t.recipe, t.prof, prof.skill)
                        if not best or gap < best.gap then best = { entry = entry, prof = prof, gap = gap, place = place } end
                    end
                end
            end
            if best then
                local who = ShortName(best.entry.char, best.entry.key)
                local note
                if best.gap == math.huge then
                    note = " can learn it, required skill unknown"
                elseif best.gap == 0 then
                    note = " can learn it now"
                else
                    note = (" can learn it at %s %d, %d to go"):format(best.prof.name, required, best.gap)
                end
                table.insert(items, { itemID = itemID, name = ns.UI.ItemLabel(itemID), gap = best.gap,
                                      key = best.entry.key, skillLine = t.prof,
                                      who = who .. ns.UI.ColorText(best.gap == 0 and ns.UI.TEXT.green or ns.UI.TEXT.soft, note),
                                      where = Where(best.place) })
                break
            end
        end
    end
    for _, entry in ipairs(list) do
        for _, place in ipairs(ns.Bags.PLACES) do
            local data = entry.char[place.field]
            for itemID in pairs(data and data.items or {}) do Consider(itemID) end
        end
    end
    for itemID in pairs(ns.db.accountBank and ns.db.accountBank.items or {}) do Consider(itemID) end
    table.sort(items, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        return a.name < b.name
    end)
    return items
end
