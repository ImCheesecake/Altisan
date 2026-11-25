-- WhatsNew.lua: the notes for each version, the What's new page, and the sidebar's dot until the
-- newest notes are read.

local _, ns = ...

local WhatsNew = {}
ns.WhatsNew = WhatsNew

-- Newest first; the first version must match the .toc's. No date means not released yet.
WhatsNew.CHANGES = {
    {
        version = "0.15.0",
        date = "2026-11-25",
        intro = "The plan to the next rank now uses what you already have.",
        groups = {
            { "New", {
                { "Plan to the next rank", "**Make a new plan** works it out again from what your characters hold now, and says if it's still the best way." },
            } },
            { "Changed", {
                { "Plan to the next rank", "uses the materials your characters already have first, instead of what a vendor would pay for them, and keeps the same plan until a step can't be done." },
                { "Forever data", "more recipes show who drops them." },
            } },
            { "Fixed", {
                { "Characters", "since Forever removed realms from names, characters showed up twice or went missing. Each one shows once again, characters on your other ruleset are hidden by default again, and plans no longer count on mail between rulesets." },
            } },
        },
    },
    {
        version = "0.14.1",
        date = "2026-11-24",
        intro = "Newer Forever data: vendors for more items, more recipe drops, and city NPCs on the city's map.",
        groups = {
            { "Changed", {
                { "Shopping and the profession window", "vendors for more of Forever's own items, and more vendors where only a few were listed." },
                { "Where to learn it", "more recipes show who drops them." },
                { "Map pins", "trainers and vendors in Stormwind, Ironforge, Darnassus and Thunder Bluff now show the city as their zone, and their pin goes on the city's map." },
                { "Forever data", "the newest LibItemDB, LibQuestDB and QuestieDB." },
            } },
        },
    },
    {
        version = "0.14.0",
        date = "2026-11-17",
        intro = "The profession window now shows where to get each material you're missing, right beside it.",
        groups = {
            { "New", {
                { "Profession window", "beside each material you're short of, a line says where to get it: who on your account has it, that vendors sell it and for how much, or that you can make it. Recipes with 5 or more materials keep the list on Altisan's card." },
                { "Altisan's cards", "a handle past the side tabs slides them out of the way and back. It remembers your choice." },
            } },
            { "Changed", {
                { "Settings", "**Show Altisan's cards** is now **Show the recipe card**. The new **Beside Blizzard's window**, under the plan, hides only the plan card." },
            } },
        },
    },
    {
        version = "0.13.3",
        date = "2026-11-17",
        intro = "Item tooltips now say who can use a material later, so you don't sell what an alt will need.",
        groups = {
            { "Changed", {
                { "Item tooltips", "a material only used by recipes your characters will learn later now says who can use it and at what skill (\"Malric can use it at 160\") instead of \"No use\". With Shift, each recipe you haven't learned shows the skill it needs. An empty line now keeps Altisan's lines apart from other addons'." },
            } },
        },
    },
    {
        version = "0.13.2",
        date = "2026-11-16",
        intro = "Newer recipe data: Forever's skill for more recipes, more drops, and Beneris's enchants for the Horde.",
        groups = {
            { "Changed", {
                { "Where to learn it", "more Tailoring, Alchemy and Herbalism recipes ask for Forever's skill, and more recipes show who drops them." },
                { "Merchant's Favor", "Horde players see Beneris for six more enchants." },
                { "Forever data", "the newest LibProfessionDB and QuestieDB." },
            } },
            { "Fixed", {
                { "Item tooltips", "enchant scrolls and engineering devices no longer say who can learn them." },
            } },
        },
    },
    {
        version = "0.13.1",
        date = "2026-11-16",
        intro = "Newer recipe data: Merchant's Favor prices up front, Forever's skill for more recipes, and more dungeon drops.",
        groups = {
            { "Changed", {
                { "Merchant's Favor", "recipes show their price before you've opened the quartermaster's shop." },
                { "Plan to the next rank", "when a recipe turns yellow now matches the game for 44 more recipes." },
                { "Where to learn it", "Leatherworking and First Aid recipes ask for Forever's skill, often 5 to 25 points lower than before." },
                { "Coverage", "41 more recipes that only drop in dungeons are under Dungeon or raid, with their dungeons named." },
                { "Forever data", "the newest LibProfessionDB, LibItemDB and QuestieDB." },
            } },
            { "Fixed", {
                { "Quest tracker", "with Shortest Path or another ForeverCore addon, Keep in stock now sits in ForeverCore's column, and ForeverCore's quest list setting works again." },
            } },
        },
    },
    {
        version = "0.13.0",
        date = "2026-11-13",
        intro = "A plan for Cooking and First Aid, recipes bought from vendors in every plan, and Shopping in whole merchant stacks.",
        groups = {
            { "New", {
                { "Plan to the next rank", "Cooking and First Aid get the plan too, in their profession window and on the character page." },
                { "Plan to the next rank", "recipes sold by a vendor count, not only a trainer's. The step is tinted and its tooltip says to buy the recipe first; **Add plan to shopping list** puts the recipe on Shopping." },
                { "Plan to the next rank", "at the top of a rank it says how to go on: Expert Cooking and First Aid from a book, with its price and who sells it; Artisan from a quest, with who starts it." },
            } },
            { "Changed", {
                { "Plan to the next rank", "with Auctionator, a material you can only farm yourself counts as more work, so the plan picks fish from the auction house over Dig Rats." },
                { "Shopping", "To buy says what a merchant hands over: \"5 × Empty Vial, 20c\", not one vial at a time." },
                { "Coverage", "cleaner columns: no Also ready column, Requires on one line (\"25, 5 to go\"), and a wider list of professions." },
                { "Where to learn it", "a recipe sold by a vendor shows the vendor, not trainers who don't teach it on Forever (Spotted Yellowtail: Gikkix)." },
                { "Forever data", "where to learn 769 of Forever's own recipes (was 729), and vendors from LibItemDB's Forever lists." },
            } },
            { "Fixed", {
                { "Shopping", "vendor prices are for one item: vials, spices and drinks were 5 times too dear." },
                { "Coverage", "First Aid's new Forever recipes, such as Minor Healing Potion, say Trainer once a trainer has listed them." },
            } },
        },
    },
    {
        version = "0.12.0",
        date = "2026-11-11",
        intro = "A plan to your next profession rank, Merchant's Favor recipes, and a Source menu on each character's recipes.",
        groups = {
            { "New", {
                { "Plan to the next rank", "what to craft to reach your next rank, using what your characters already hold. **Show plan** on a character's page shows every step, and **Add plan to shopping list** puts it on Shopping." },
                { "Profession window", "a second card shows the plan: what to make, in order, and the materials it takes. **Open plan in Altisan** opens it in full." },
                { "Settings", "**Show a plan to the next rank** turns the plan off. **Plan the cheapest way, by Auctionator's prices** plans by your auction house prices instead." },
                { "Merchant's Favor", "recipes sold by profession quartermasters, like Jim'bek, say they cost Merchant's Favor, not gold. The price shows once one of your characters opens that shop." },
                { "Character page", "a **Source** menu beside Slot and Stats: Trainer, Vendor, Merchant's Favor, Quest, Drop, Dungeon or raid, with a count for each." },
                { "Trainers", "talking to one saves the skill each recipe needs on Forever, often lower than Altisan showed before." },
            } },
            { "Changed", {
                { "Coverage", "**Merchant's Favor** and **Dungeon or raid** filters. Where names the dungeon or raid (\"Dire Maul\", \"4 dungeons\")." },
                { "Shopping", "To buy has a **Bought with Merchant's Favor** group, left out of **Send to Auctionator**." },
                { "Quest tracker", "Keep in stock shows the account's stock on every character, as the Gathering page does." },
                { "Character page", "You can learn now ends with a **Show all N in the list** button." },
                { "Forever data", "where to learn 729 of Forever's own recipes (was 519) and who sells 2,306 items (was 1,089), from QuestieDB's newest data." },
            } },
            { "Fixed", {
                { "Window", "long names and notes wrap and their row grows at any window size, instead of being cut with \"...\" or drawn over the next line." },
                { "Recipe lists", "yellow and green skill-up colors match the game's." },
                { "Character page", "the search box's outline no longer stays behind the plan's title." },
            } },
        },
    },
    {
        version = "0.11.0",
        date = "2026-11-09",
        intro = "Profession cooldowns, a card beside the profession window, and what you keep in stock in the quest tracker.",
        groups = {
            { "New", {
                { "Profession window", "a card beside it says which materials you're missing and who on your account holds them, that a vendor sells them, or that you can create them, and who else knows the recipe. **Show Altisan's card** in the settings turns it off." },
                { "Cooldowns", "every character's transmute, Mooncloth and Salt Shaker timers, in the recipe pane. Next up says who can use one again." },
                { "Quest tracker", "**Show in quest tracker** on the Gathering page lists the herbs and ore you keep in stock and are still short of, wherever you are. Click a line to open it on Gathering." },
            } },
            { "Changed", {
                { "Gathering", "**By zone** has a continent and a zone menu with every zone, and names what you're short of on its zones." },
                { "Gathering", "**Keep in stock** takes any number: type it in, or change it one at a time." },
                { "Gathering", "where a herb grows or ore is mined: most nodes first, the zone you're in marked, then **Show N more**. Quest items like Root Sample are left out." },
                { "Who holds it", "each character is named once: \"Malric 3 (2 in bank)\"." },
                { "Names", "a character's surname shows when another character shares the first name." },
                { "Window", "characters on other rulesets are hidden. Settings: **Show other rulesets** brings them back." },
                { "Window", "the Altisan look has Blizzard's window frame. The Blizzard look is gone; if you used it, Altisan opens in the Altisan look." },
                { "Shopping", "vendors for Forever's own items, like Mote of Magic." },
                { "What's new", "easier to read; older versions fold to one line." },
            } },
            { "Fixed", {
                { "Window", "clicking the profession window brings it in front of Altisan." },
                { "Shopping", "Backspace no longer empties the **Copy list** box." },
            } },
        },
    },
    {
        version = "0.10.1",
        date = "2026-11-05",
        intro = "No more \"Altisan has been blocked\" message from the game's options.",
        groups = {
            { "Fixed", {
                { "Settings", "after opening Altisan's settings, the game's Audio page no longer says \"Altisan has been blocked from an action\". The page looks the same, but the options search box no longer finds Altisan's settings." },
            } },
        },
    },
    {
        version = "0.10.0",
        date = "2026-11-04",
        intro = "Ready for launch: your mailbox counts, a Gathering page, a leather window, and recipes you'll never make out of the way.",
        groups = {
            { "New", {
                { "Gathering", "a page for the whole account's herbs and ore: what you're short of, what's in stock, by zone, and **Find a herb or ore**. **Keep in stock** sets how many you want; **Add to shopping list** puts what's missing on Shopping's To buy." },
                { "Mailbox", "crafting items in each character's mailbox count wherever Altisan says who holds what, as \"(mail)\". Items you mail to your own characters count the moment you press Send." },
                { "Recipe lists and Coverage", "right-click a recipe, **Ignore on every character**: it leaves Next up, Coverage's counts and item tooltips, and waits behind **Show 1 ignored**. Coverage lists them under Ignored, with a × to undo." },
                { "Settings", "**Window style** > **Ledger**: Altisan in a painted leather cover." },
            } },
            { "Changed", {
                { "Recipe tooltips", "the three nearest trainers or vendors your faction can use, with their zones. Hold Shift for more." },
                { "Where to learn", "Forever's own recipes now say who sells them, what drops them and which quest gives them." },
                { "Shopping", "vendors are named in German, Spanish, French, Korean, Russian and Chinese too." },
                { "Icon", "a painted ledger, on the minimap button and in the AddOns list." },
            } },
            { "Fixed", {
                { "Camp", "works on German, Russian, Korean and Chinese clients." },
                { "Recipe lists", "two recipes with the same name in your language no longer hide each other." },
            } },
        },
    },
    {
        version = "0.9.0",
        date = "2026-10-20",
        intro = "A calmer character page, and a shopping list that crafts what it can.",
        groups = {
            { "New", {
                { "Character page", "the list on the left, the recipe you pick on the right: where to learn it with pins, materials, who holds them, the two track buttons. With nothing picked, the right side shows what gives skill now and what you can learn." },
                { "Shopping", "a material one of your characters can make is made, not bought, and **Create first** says who makes what. Its own materials go on the list instead (2 bolts short: 6 Wool Cloth)." },
                { "Shopping", "To buy is split into **From vendors**, with prices, and **Auction house**. Only the auction house items go to Auctionator." },
            } },
            { "Changed", {
                { "Character page", "**Show** replaces the four filter buttons. Its first choice, **What you can use**, folds the recipes you need more skill for into one line per category." },
                { "Character page", "a row ends with what you can do: \"learn\" or \"needs 150\". Scan times are in each profession tab's tooltip." },
                { "Where to learn", "words instead of counts: \"World drop\", \"2 vendors\". A recipe that drops and is found in lockboxes says World drop." },
            } },
            { "Fixed", {
                { "Where to learn", "lockboxes are named as lockboxes, not as the enemy that shares their number." },
                { "Camp", "Herbalism's and Skinning's camp objects no longer say \"can learn it\" before you have the skill." },
            } },
        },
    },
    {
        version = "0.8.0",
        date = "2026-10-20",
        intro = "Where to learn every recipe, and tracking it.",
        groups = {
            { "New", {
                { "Coverage and recipe lists", "where to learn it: your faction's trainers, vendors and quest givers, nearest first, with a map pin." },
                { "Coverage and recipe lists", "**Track materials** puts a recipe in the quest log, even for another character (at their next login). **Add to shopping list** puts it on Shopping." },
                { "Coverage", "recipes grouped by rank, Apprentice to Artisan, each one folds; filters by where to learn it." },
                { "Lists", "a tracked recipe's row is faintly warm." },
            } },
            { "Changed", {
                { "Shopping", "a craft you haven't learned lists its recipe first under Materials, and puts it on To buy." },
                { "Character page", "Horde and Alliance in their colors, the scan line's professions stand out, and Tracked in the legend." },
                { "Coverage", "character names in class colors; tooltips start with the crafted item." },
                { "Coverage", "when only the other faction sells or teaches a recipe, it says so, and whether the recipe can be traded." },
            } },
            { "Fixed", {
                { "Settings", "no Lua error when the list scrolls or opens again." },
                { "Mail plan and item tooltips", "never name a character of the other faction or realm." },
                { "Coverage", "the Trainer and Vendor filters only count what your faction can use." },
                { "Window", "lines stay even and still while you resize, and Camp resizes without lag." },
            } },
        },
    },
    {
        version = "0.7.1",
        date = "2026-10-18",
        items = {
            { "What's new", "this page. After an update, a dot by it in the sidebar until you've read it." },
            { "Bugs and ideas", "the speech bubble in the title bar has the address to report a bug or share an idea. It's also at the top of Altisan's settings." },
        },
    },
    {
        version = "0.7.0",
        date = "2026-10-17",
        intro = "First public beta, for WoW: Forever.",
        items = {
            { "Overview", "every character's professions on one page, and Next up: what's worth doing now." },
            { "Item tooltips", "which of your characters craft with a material, and how many you hold." },
            { "Recipe lists", "every recipe, learned or not, with filters for skill, slot, armor type and stats, and where each one is taught." },
            { "Coverage", "recipes your account doesn't know yet, and which character can learn them." },
            { "Shopping", "track crafts, count materials across every character's bags and banks, a mail plan, and a shopping list for Auctionator." },
            { "Camp", "what each character can bring to a camp, and which Blueprints to look for." },
        },
    },
}

function WhatsNew.Init(db, isNew)
    if isNew then db.whatsNewSeen = WhatsNew.CHANGES[1].version end
end

function WhatsNew.Unread()
    return ns.db.whatsNewSeen ~= WhatsNew.CHANGES[1].version
end

function WhatsNew.MarkRead()
    ns.db.whatsNewSeen = WhatsNew.CHANGES[1].version
end

local View = {}
ns.WhatsNewView = View

local MAX_WIDTH = 640
local PAD = 16
local BAR_ROOM = 14
local ITEM_FONT, INTRO_FONT, SPACING = "GameFontHighlightSmall", "GameFontHighlight", 2
local ITEM_GAP, BULLET = 7, 12
local GROUP_GAP, GROUP_HEIGHT = 14, 20
local FOLD_TOP, FOLD_BOTTOM = 9, 9
local CARD_GAP = 12
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local panel
local opened = {}

local function ShowDate(iso)
    local y, m, d = (iso or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return "not released yet" end
    return ("%s %d, %s"):format(MONTHS[tonumber(m)], tonumber(d), y)
end

local function ItemText(item)
    local UI, TEXT = ns.UI, ns.UI.TEXT
    local parts, at = {}, 1
    for before, name, after in item[2]:gmatch("()%*%*(.-)%*%*()") do
        parts[#parts + 1] = UI.ColorText(TEXT.body, item[2]:sub(at, before - 1))
        parts[#parts + 1] = UI.ColorText(TEXT.white, name)
        at = after
    end
    parts[#parts + 1] = UI.ColorText(TEXT.body, item[2]:sub(at))
    return UI.ColorText(TEXT.place, item[1] .. ":") .. " " .. table.concat(parts)
end

local function Lines(change)
    local lines = {}
    for _, item in ipairs(change.items or {}) do lines[#lines + 1] = { item = item } end
    for _, group in ipairs(change.groups or {}) do
        if #group[2] > 0 then
            lines[#lines + 1] = { heading = group[1] }
            for _, item in ipairs(group[2]) do lines[#lines + 1] = { item = item } end
        end
    end
    return lines
end

local function FoldNote(change)
    local UI = ns.UI
    local note = UI.ColorText(UI.TEXT.muted, ShowDate(change.date))
    return change.intro and (note .. "   " .. change.intro) or note
end

local function FoldNoteWidth(change, width)
    return ns.UI.FoldNoteWidth(width - BAR_ROOM, 2, change.version)
end

local function Layout(entry, width)
    local UI = ns.UI
    local textWidth = width - 2 * PAD - BAR_ROOM
    if entry.kind == "fold" then
        local note = UI.TextHeight(FoldNote(entry.change), FoldNoteWidth(entry.change, width), ITEM_FONT)
        return {}, math.ceil((entry.first and CARD_GAP or 0) + FOLD_TOP + math.max(14, note) + FOLD_BOTTOM)
    end
    local spots, y = { lines = {} }, 2
    if entry.kind == "card" then
        y = 12 + 26
        if entry.change.intro then
            spots.intro = y
            y = y + UI.TextHeight(entry.change.intro, textWidth, INTRO_FONT, SPACING)
        end
    end
    for i, line in ipairs(Lines(entry.change)) do
        if line.heading then
            y = y + GROUP_GAP
            spots.lines[i] = y
            y = y + GROUP_HEIGHT
        else
            spots.lines[i] = y
            y = y + UI.TextHeight(ItemText(line.item), textWidth - BULLET, ITEM_FONT, SPACING) + ITEM_GAP
        end
    end
    return spots, math.ceil(y + (entry.kind == "card" and 8 or 4))
end

local function Entries(width)
    local entries = {}
    for i, change in ipairs(WhatsNew.CHANGES) do
        if i == 1 then
            entries[1] = { kind = "card", change = change }
        else
            entries[#entries + 1] = { kind = "fold", change = change, first = i == 2 }
            if opened[change.version] then entries[#entries + 1] = { kind = "body", change = change } end
        end
    end
    for _, entry in ipairs(entries) do
        local _, height = Layout(entry, width)
        entry.height = height
    end
    return entries
end

local function Draw()
    panel.list.box:SetDataProvider(CreateDataProvider(Entries(panel.listWidth)), ScrollBoxConstants.RetainScrollPosition)
end

local function InitRow(row, entry)
    local UI = ns.UI
    if not row.made then
        row.made = true
        -- On the row itself, not a card frame: a child frame would draw over the row's text.
        row.box = UI.RoundedBox(row, 8)
        row.box:SetFill(UI.C.cardFill)
        row.box:SetEdge(UI.C.divider)
        row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.heading:SetPoint("TOPLEFT", PAD, -12)
        row.date = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.date:SetPoint("BOTTOMLEFT", row.heading, "BOTTOMRIGHT", 8, 0)
        row.rule = UI.Divider(row)
        row.intro = UI.Text(row, INTRO_FONT, SPACING)
        row.fold = UI.FoldHeader(row)
        row.items, row.bullets, row.groups = {}, {}, {}
    end
    local width = panel.listWidth
    local spots = Layout(entry, width)
    local card, fold = entry.kind == "card", entry.kind == "fold"
    local top = entry.first and CARD_GAP or 0
    row.box:SetShown(card)
    row.rule:SetShown(card or entry.first or false)
    row.rule:ClearAllPoints()
    row.rule:SetPoint("TOPLEFT", card and PAD or 0, card and -32 or -top)
    row.rule:SetPoint("TOPRIGHT", card and -PAD or 0, card and -32 or -top)
    row.heading:SetShown(card)
    row.date:SetShown(card)
    row.fold:SetShown(fold)
    row:SetScript("OnClick", nil)
    if card then
        row.heading:SetText(entry.change.version)
        row.date:SetText(ShowDate(entry.change.date))
    elseif fold then
        local version = entry.change.version
        row.fold:Set({ x = 2, top = top + FOLD_TOP, line = true, open = opened[version] or false,
                       title = version, note = FoldNote(entry.change), wrap = FoldNoteWidth(entry.change, width) })
        row:SetScript("OnClick", function()
            opened[version] = not opened[version] or nil
            Draw()
        end)
    end

    row.intro:SetShown(spots.intro ~= nil)
    if spots.intro then
        row.intro:SetText(entry.change.intro)
        row.intro:SetWidth(width - 2 * PAD - BAR_ROOM)
        row.intro:SetPoint("TOPLEFT", PAD, -spots.intro)
    end
    local items, groups = 0, 0
    if not fold then
        for i, line in ipairs(Lines(entry.change)) do
            if line.heading then
                groups = groups + 1
                local heading = row.groups[groups] or UI.Text(row, "GameFontNormal")
                row.groups[groups] = heading
                heading:SetText(line.heading)
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", PAD, -spots.lines[i])
                heading:Show()
            else
                items = items + 1
                local text, bullet = row.items[items], row.bullets[items]
                if not text then
                    text, bullet = UI.Text(row, ITEM_FONT, SPACING), UI.Text(row, ITEM_FONT, SPACING)
                    bullet:SetText(UI.ColorText(UI.TEXT.bullet, "•"))
                    row.items[items], row.bullets[items] = text, bullet
                end
                text:SetText(ItemText(line.item))
                text:SetWidth(width - 2 * PAD - BAR_ROOM - BULLET)
                text:ClearAllPoints()
                text:SetPoint("TOPLEFT", PAD + BULLET, -spots.lines[i])
                bullet:ClearAllPoints()
                bullet:SetPoint("TOPLEFT", PAD, -spots.lines[i])
                text:Show()
                bullet:Show()
            end
        end
    end
    for i = items + 1, #row.items do
        row.items[i]:Hide()
        row.bullets[i]:Hide()
    end
    for i = groups + 1, #row.groups do row.groups[i]:Hide() end
end

function View.Refresh(_, width, height, layoutOnly)
    local listWidth = math.floor(math.min(width or MAX_WIDTH, MAX_WIDTH))
    panel.subtitle:SetText(ns.TITLE .. " " .. WhatsNew.CHANGES[1].version)
    if layoutOnly and listWidth == panel.listWidth then return end
    panel.listWidth = listWidth
    panel.listFrame:SetWidth(listWidth)
    Draw()
end

function View.Build(parent)
    local UI, PAGE = ns.UI, ns.UI.PAGE
    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.whatsNewPage = true

    panel.title = UI.PageTitle(panel)
    panel.title:SetPoint("TOPLEFT", 0, PAGE.top)
    panel.title:SetText("What's new")
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.subtitle:SetPoint("BOTTOMLEFT", panel.title, "BOTTOMRIGHT", 10, 1)

    panel.listFrame = CreateFrame("Frame", nil, panel)
    panel.listFrame:SetPoint("TOPLEFT", 0, PAGE.top - PAGE.titleHeight - PAGE.gap)
    panel.listFrame:SetPoint("BOTTOMLEFT", 0, 0)
    panel.list = UI.ScrollList(panel.listFrame, function(entry) return entry.height end, InitRow)
    UI.PlaceList(panel.list, 0)
    return panel
end

View.Opened = WhatsNew.MarkRead
function View.Badge() return WhatsNew.CHANGES[1].version, WhatsNew.Unread() end
ns.UI.AddPage("whatsnew", View)
