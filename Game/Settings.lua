-- Settings.lua: Options > AddOns > Altisan, a page Altisan draws itself (a canvas) in the look of
-- Blizzard's own. Rows from Blizzard's settings list are shared by every page, and once an addon
-- fills them, Blizzard's Discord checkbox on the Audio page is blocked and blames the addon.

local _, ns = ...
local UI = ns.UI

local Options = { rows = {} }
ns.Options = Options

local category

-- Sizes and offsets copied from Blizzard's settings list and row templates.
local ROW, HEADER, GAP, PAD, INDENT = 26, 45, 9, 10, 15

local function OpenKeyBindings()
    if Settings.KEYBINDINGS_CATEGORY_ID then
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_ALTISAN)
    end
end

local function Saved(group, name, after)
    return function() return ns.db[group][name] end,
        function(value)
            ns.db[group][name] = value
            if after then after() end
        end
end

local function WithSaved(def)
    if def.get then return def end
    def.get, def.set = Saved(def.group, def.name, def.after)
    return def
end

local ROWS = {
    { kind = "address", label = "Found a bug? Have an idea?",
      tooltip = "Leave a comment on Altisan's CurseForge page. Click the address, then press Ctrl+C." },

    { kind = "header", label = "General" },
    WithSaved({ kind = "check", key = "SHOW_MINIMAP", label = "Show minimap button", default = true,
          tooltip = "Altisan is also in the minimap's addon menu, so you can hide this button and still open it.",
          get = function() return not ns.db.minimap.hide end,
          set = function(value) ns.SetMinimapShown(value) end }),
    { kind = "button", label = "Key to open Altisan", text = "Key Bindings", click = OpenKeyBindings,
      tooltip = "Opens the game's key bindings at Altisan, where you can set a key for \"Open Altisan\"." },

    { kind = "header", label = "Item tooltips" },
    WithSaved({ kind = "check", key = "ITEM_TIPS", label = "Who uses it", default = true, group = "tooltips", name = "items",
          tooltip = "Item tooltips say which of your characters use the item and who to keep it for." }),
    WithSaved({ kind = "check", key = "SHIFT_ONLY", label = "Only while holding Shift", default = false, under = "ITEM_TIPS",
          group = "tooltips", name = "shiftOnly",
          tooltip = "Altisan adds nothing to item tooltips until you hold Shift, then shows the full version. For tooltips that other addons already fill." }),
    WithSaved({ kind = "check", key = "KEEP_FOR_LATER", label = "Keep for later", default = true, under = "ITEM_TIPS",
          group = "tooltips", name = "keepForLater",
          tooltip = "Also keep items for recipes a character can learn soon, not just the ones they know." }),
    WithSaved({ kind = "slider", key = "KEEP_REACH", label = "Learn soon: within", default = 20, under = "KEEP_FOR_LATER",
          group = "tooltips", name = "reach", min = 10, max = 150, step = 10,
          format = function(value) return ("%d skill"):format(value) end,
          tooltip = "How far above a character's skill a recipe can be and still count for Keep for later." }),
    WithSaved({ kind = "check", key = "ITEM_COUNTS", label = "Show counts", default = true, under = "ITEM_TIPS",
          group = "tooltips", name = "counts",
          tooltip = "\"On your account: 23\" and who holds them. Turn it off if a bag addon already shows counts." }),

    { kind = "header", label = "Characters" },
    WithSaved({ kind = "check", key = "OTHER_REALMS", label = "Show other rulesets", default = false,
          group = "list", name = "otherRealms", after = function() ns.RefreshWindow() end,
          tooltip = "Include characters on other rulesets (Normal, PvP, RP, Hardcore). They can't mail or trade with this one." }),
    WithSaved({ kind = "check", key = "OTHER_FACTION", label = "Show other faction", default = true,
          group = "list", name = "otherFaction", after = function() ns.RefreshWindow() end,
          tooltip = "Include characters of the other faction. They can't receive mail from your other characters. (Only possible on Normal, RP and Hardcore: PvP locks an account to one faction.)" }),

    { kind = "header", label = "Window" },
    WithSaved({ kind = "dropdown", key = "LOOK", label = "Window style", default = "radar",
          group = "window", name = "look", after = function() ns.RebuildWindow() end,
          tooltip = "How the Altisan window looks.",
          options = {
              { value = "radar", label = "Altisan", tooltip = "Blizzard's window frame in Forever's colors, with cards and bronze skill bars." },
              { value = "ledger", label = "Ledger", tooltip = "The Altisan window in a painted leather cover with brass corners." },
          } }),
    WithSaved({ kind = "slider", key = "SCALE", label = "Window scale", default = 1,
          group = "window", name = "scale", after = function() ns.ApplyWindowScale() end,
          min = 0.7, max = 1.5, step = 0.05, format = FormatPercentage,
          tooltip = "Makes text and everything in the window bigger or smaller. To fit more in, drag the window's corner instead." }),
    WithSaved({ kind = "dropdown", key = "TOOLTIPS", label = "Tooltips", default = "mouse", group = "window", name = "tooltips",
          tooltip = "Where tooltips for rows in the Altisan window show up. Item tooltips in your bags aren't affected.",
          options = {
              { value = "mouse", label = "At the mouse", tooltip = "Next to the row you point at." },
              { value = "fixed", label = "Fixed", tooltip = "Where the game shows its tooltips, or wherever a tooltip addon moved them." },
          } }),

    { kind = "header", label = "Profession window" },
    WithSaved({ kind = "check", key = "SLOT_NOTES", label = "Show where to get missing materials", default = true,
          group = "window", name = "slotNotes", after = function() ns.ProfessionCard.Refresh() end,
          tooltip = "Beside each material you're short of in Blizzard's profession window: who on your account holds it, that vendors sell it, or that you can create it." }),
    WithSaved({ kind = "check", key = "PROFESSION_CARD", label = "Show the recipe card", default = true,
          group = "window", name = "card", after = function() ns.ProfessionCard.Refresh() end,
          tooltip = "Beside Blizzard's profession window: whether the recipe is in your plan, what's missing when the lines beside the materials are off or don't fit, who else knows it, and the track buttons." }),
    WithSaved({ kind = "check", key = "SKILL_PLAN", label = "Show a plan to the next rank", default = true,
          group = "window", name = "plan", after = function() ns.RefreshWindow() end,
          tooltip = "What to craft to reach the most your training allows: the fewest crafts and materials, then what your characters already know and hold. On the card beside Blizzard's profession window, the character page and Next up." }),
    WithSaved({ kind = "check", key = "PLAN_CARD", label = "Beside Blizzard's window", default = true,
          under = "SKILL_PLAN", group = "window", name = "planCard", after = function() ns.ProfessionCard.Refresh() end,
          tooltip = "Your plan to the next rank beside Blizzard's profession window. The character page and Next up keep it either way." }),
    WithSaved({ kind = "check", key = "PLAN_CHEAPEST", label = "Plan the cheapest way, by Auctionator's prices", default = false,
          under = "SKILL_PLAN", group = "window", name = "planCheapest", after = function() ns.RefreshWindow() end,
          available = function() return ns.AH.Available() end, unavailable = "Needs Auctionator.",
          tooltip = "Picks the recipes that cost least by your Auctionator scans, counting what your characters hold as free, instead of the fewest crafts and materials." }),
}

local byKey = {}
for _, def in ipairs(ROWS) do
    if def.key then byKey[def.key] = def end
end

local function IsOn(def)
    if def.available and not def.available() then return false end
    local parent = def.under and byKey[def.under]
    while parent do
        if not parent.get() then return false end
        parent = parent.under and byKey[parent.under]
    end
    return true
end

local function Tooltip(tooltip, title, text)
    UI.TipLine(tooltip, title, "white")
    UI.TipLine(tooltip, text, "gold", true)
end

local function ShowTip(owner, def)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", -10, 0)
    local missing = def.available and not def.available()
    Tooltip(GameTooltip, def.label, missing and (def.unavailable .. " " .. def.tooltip) or def.tooltip)
    GameTooltip:Show()
end

local function TipOn(frame, def)
    frame:HookScript("OnEnter", function(self) ShowTip(self, def) end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function Options.Refresh()
    for _, row in ipairs(Options.rows) do
        local def, on = row.def, IsOn(row.def)
        if row.text then
            row.text:SetFontObject(on and (def.under and "GameFontNormalSmall" or "GameFontNormal")
                or (def.under and "GameFontDisableSmall" or "GameFontDisable"))
        end
        if def.kind == "check" then
            row.control:SetChecked(def.get() and true or false)
            row.control:SetEnabled(on)
        elseif def.kind == "slider" then
            row.control:SetValue(def.get())
            row.control:SetEnabled(on)
        elseif def.kind == "dropdown" then
            row.control.Dropdown:GenerateMenu()
        elseif def.kind == "address" then
            -- Set at login, while the page was hidden, the box showed empty in game.
            row.control:SetText(ns.FEEDBACK_URL)
            row.control:SetCursorPosition(0)
        end
    end
end

local function Set(def, value)
    def.set(value)
    Options.Refresh()
end

local function AddLabel(row, frame, def)
    local text = frame:CreateFontString(nil, "OVERLAY", def.under and "GameFontNormalSmall" or "GameFontNormal")
    text:SetJustifyH("LEFT")
    text:SetPoint("LEFT", (def.under and INDENT or 0) + 37, 0)
    text:SetPoint("RIGHT", frame, "CENTER", -85, 0)
    text:SetText(def.label)
    row.text = text

    local hover = CreateFrame("Frame", nil, frame)
    hover:SetPoint("TOPLEFT")
    hover:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -80, 0)
    local glow = hover:CreateTexture(nil, "BACKGROUND", "HoverBackgroundTemplate")
    hover:SetScript("OnEnter", function(self)
        glow:Show()
        ShowTip(self, def)
    end)
    hover:SetScript("OnLeave", function()
        glow:Hide()
        GameTooltip:Hide()
    end)
    row.hover = hover
end

local BUILD = {}

function BUILD.header(row, frame, def)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", 7, -16)
    title:SetText(def.label)
end

function BUILD.address(row, frame, def)
    AddLabel(row, frame, def)
    local box = ns.Feedback.AddressBox(frame, "InputBoxTemplate")
    box:SetSize(230, 20)
    box:SetPoint("LEFT", frame, "CENTER", -36, 0)
    row.control = box
end

function BUILD.check(row, frame, def)
    AddLabel(row, frame, def)
    -- Blizzard's checkbox with our own tooltip: the template's would write to SettingsTooltip,
    -- which other pages share and our code would taint. So the row's highlight is ours to show.
    local box = CreateFrame("CheckButton", nil, frame, "SettingsCheckboxTemplate")
    box:SetPoint("LEFT", frame, "CENTER", -80, 0)
    box:SetScript("OnEnter", function(self)
        self.HoverBackground:Show()
        ShowTip(self, def)
    end)
    box:SetScript("OnLeave", function(self)
        self.HoverBackground:Hide()
        GameTooltip:Hide()
    end)
    box:SetScript("OnClick", function(self)
        local value = self:GetChecked() and true or false
        PlaySound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        Set(def, value)
    end)
    row.hover:SetScript("OnMouseUp", function()
        if box:IsEnabled() then box:Click() end
    end)
    row.control = box
end

function BUILD.slider(row, frame, def)
    AddLabel(row, frame, def)
    local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(250)
    slider:SetPoint("LEFT", frame, "CENTER", -80, 3)
    slider:Init(def.get(), def.min, def.max, Round((def.max - def.min) / def.step),
        { [MinimalSliderWithSteppersMixin.Label.Right] = def.format })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if value ~= def.get() then Set(def, value) end
    end, slider)
    TipOn(slider.Slider, def)
    row.control = slider
end

function BUILD.dropdown(row, frame, def)
    AddLabel(row, frame, def)
    local control = CreateFrame("Frame", nil, frame, "SettingsDropdownWithButtonsTemplate")
    control:SetPoint("LEFT", frame, "CENTER", -48, 3)
    control.Dropdown:SetWidth(220)
    control.Dropdown:SetupMenu(function(_, root)
        for _, option in ipairs(def.options) do
            local radio = root:CreateRadio(option.label,
                function() return def.get() == option.value end,
                function() Set(def, option.value) end, option.value)
            radio:SetTooltip(function(tooltip) Tooltip(tooltip, option.label, option.tooltip) end)
        end
    end)
    control:SetSteppersShown(true)
    TipOn(control.Dropdown, def)
    row.control = control
end

function BUILD.button(row, frame, def)
    AddLabel(row, frame, def)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(200, ROW)
    button:SetPoint("LEFT", frame, "CENTER", -40, 0)
    button:SetText(def.text)
    button:SetScript("OnClick", def.click)
    TipOn(button, def)
    row.control = button
end

function Options.Reset()
    for _, def in ipairs(ROWS) do
        if def.key then def.set(def.default) end
    end
    Options.Refresh()
end

local function ConfirmReset()
    if not StaticPopupDialogs.ALTISAN_RESET_SETTINGS then
        StaticPopupDialogs.ALTISAN_RESET_SETTINGS = {
            text = "Reset Altisan's settings to their defaults?",
            button1 = "Reset settings",
            button2 = CANCEL,
            OnAccept = function() Options.Reset() end,
            timeout = 0, whileDead = 1, hideOnEscape = 1,
        }
    end
    StaticPopup_Show("ALTISAN_RESET_SETTINGS")
end

local function Build()
    local page = CreateFrame("Frame")
    page:Hide()

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText(ns.TITLE)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider", true)
    line:SetPoint("TOP", 0, -50)
    local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    defaults:SetSize(96, 22)
    defaults:SetPoint("TOPRIGHT", -36, -16)
    defaults:SetText(SETTINGS_DEFAULTS)
    defaults:SetScript("OnClick", ConfirmReset)

    local content = CreateFrame("Frame", nil, page)
    local y = PAD
    for i, def in ipairs(ROWS) do
        local height = def.kind == "header" and HEADER or ROW
        local frame = CreateFrame("Frame", nil, content)
        frame:SetPoint("TOPLEFT", 0, -y)
        frame:SetPoint("TOPRIGHT", 0, -y)
        frame:SetHeight(height)
        local row = { def = def, frame = frame }
        BUILD[def.kind](row, frame, def)
        Options.rows[i] = row
        y = y + height + GAP
    end
    local height = y - GAP + PAD

    local list = UI.ScrollList(page, function(data) return data.height end, function(row)
        content:SetParent(row)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 10, 0)
        content:SetPoint("BOTTOMRIGHT")
        content:Show()
    end)
    UI.PlaceList(list, -52, 2, 12)
    list.box:SetDataProvider(CreateDataProvider({ { height = height } }))

    -- Blizzard's settings panel calls these by name.
    page.OnRefresh = Options.Refresh
    page.OnDefault = Options.Reset
    Options.page = page
    Options.Refresh()
    return page
end

function ns.CreateSettings()
    if category then return end
    category = Settings.RegisterCanvasLayoutCategory(Build(), ns.TITLE)
    ns.settingsCategory = category
    Settings.RegisterAddOnCategory(category)
end
