-- Feedback.lua: the speech bubble in the window's title bar, and the panel it opens with
-- Altisan's CurseForge address. Also the address box the settings page uses.

local _, ns = ...

local Feedback = {}
ns.Feedback = Feedback

ns.FEEDBACK_URL = "curseforge.com/wow/addons/altisan"

local WIDTH = 290

-- Addons can't open links or reach the clipboard: the address sits selected in a box for Ctrl+C.
function Feedback.AddressBox(parent, template)
    local box = CreateFrame("EditBox", nil, parent, template)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetText(ns.FEEDBACK_URL)
    ns.UI.ReadOnly(box, function() return ns.FEEDBACK_URL end)
    return box
end

local function Panel(button)
    local UI = ns.UI
    local panel
    panel = ns.Dropdown.Popup(button:GetParent(), button, WIDTH, function() panel.address:ClearFocus() end)
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -6)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Found a bug? Have an idea?")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 14, -34)
    text:SetWidth(WIDTH - 28)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(UI.Hex(UI.TEXT.light)))
    text:SetText("Leave a comment on Altisan's CurseForge page:")

    local frame = UI.InputFrame(panel)
    frame:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    frame:SetSize(WIDTH - 28, 24)
    panel.address = Feedback.AddressBox(frame)
    panel.address:SetPoint("TOPLEFT", 8, -4)
    panel.address:SetPoint("BOTTOMRIGHT", -8, 4)
    panel.address:SetScript("OnEscapePressed", function() panel:Hide() end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -10)
    hint:SetTextColor(unpack(UI.Hex(UI.TEXT.green)))
    hint:SetText("Press Ctrl+C to copy.")
    panel:SetHeight(math.ceil(34 + text:GetStringHeight() + 6 + 24 + 10 + hint:GetStringHeight() + 12))

    panel:HookScript("OnShow", function()
        panel.address:SetText(ns.FEEDBACK_URL)
        panel.address:SetFocus()
        panel.address:HighlightText()
    end)
    return panel
end

function Feedback.Button(parent)
    local UI = ns.UI
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.feedback = true
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(UI.MEDIA .. "Feedback")
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(b.icon)
    glow:SetTexture(UI.MEDIA .. "Feedback")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.5)
    b.panel = Panel(b)

    b:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        self.panel:SetShown(not self.panel:IsShown())
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Found a bug?")
        ns.UI.TipLine(GameTooltip, "Where to report it, or to share an idea.")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
