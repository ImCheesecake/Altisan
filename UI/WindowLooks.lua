-- WindowLooks.lua: the window's two looks, built on the frame they're given: Altisan (Blizzard's
-- window frame in Forever's art, cut into slices) and Ledger (the painted cover in pieces).

local _, ns = ...

local UI = ns.UI
local C = UI.C

local function IconButton(parent, size, normal, highlight, pushed, tooltip, onClick, artSize)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalAtlas(normal)
    b:SetHighlightAtlas(highlight or normal, highlight and nil or "ADD")
    if pushed then b:SetPushedAtlas(pushed) end
    if artSize then
        for _, texture in ipairs({ b:GetNormalTexture(), b:GetHighlightTexture(), b:GetPushedTexture() }) do
            texture:ClearAllPoints()
            texture:SetPoint("CENTER")
            texture:SetSize(artSize, artSize)
        end
    end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local BETA_LINES = {
    "Most of Altisan's data comes from the Forever beta. Missing or not confirmed yet:",
    " ",
    { bullet = "Where Camp Blueprints drop: Altisan's data doesn't have it." },
    { bullet = "Changes since the beta, such as hotfixed required skills." },
    { bullet = "Some sources and required skills are borrowed from Vanilla (marked \"Vanilla data\")." },
    { bullet = "Which vendors sell a material, and its price: borrowed from Vanilla." },
    " ",
    "This fills in as the data libraries are updated.",
}
local function BetaTag(parent, after)
    local tag = CreateFrame("Frame", nil, parent)
    tag:SetHeight(18)
    tag.box = UI.RoundedBox(tag, 6)
    tag.box:SetEdge(UI.Hex(UI.TEXT.amber, 0.7))
    tag.box:SetFill(UI.Hex(UI.TEXT.amber, 0.12))
    tag.text = tag:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag.text:SetPoint("CENTER", 0, 0)
    tag.text:SetText("Beta data")
    tag.text:SetTextColor(unpack(UI.Hex(UI.TEXT.amber)))
    tag:SetWidth(tag.text:GetStringWidth() + 16)
    tag:SetPoint("LEFT", after, "RIGHT", 10, 0)
    tag:EnableMouse(true)
    tag:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        UI.TipLine(GameTooltip, "Beta data", "gold")
        for _, line in ipairs(BETA_LINES) do
            local text = type(line) == "table" and (UI.ColorText(UI.TEXT.bullet, "•") .. "  " .. line.bullet) or line
            UI.TipLine(GameTooltip, text, nil, true)
        end
        GameTooltip:Show()
    end)
    tag:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tag
end

local function TitleButtons(f, right, top)
    local close = IconButton(f, 18, "simplecheckout-close-normal-1x", "simplecheckout-close-hover-1x",
        "simplecheckout-close-pressed-1x", "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -right, -top)

    -- The cog atlas is mostly empty space: 40 px makes the gear as big as the close X.
    local cog = IconButton(f, 22, "GM-icon-settings", nil, nil, "Settings", function() ns.OpenSettings() end, 40)
    cog:SetPoint("RIGHT", close, "LEFT", -12, 0)
    local feedback = ns.Feedback.Button(f)
    feedback:SetPoint("RIGHT", cog, "LEFT", -8, 0)
    return feedback
end

local function BrownTile(parent, tex)
    tex:SetTexture("Interface\\Collections\\CollectionsBackgroundTile", "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    local layer, sublevel = tex:GetDrawLayer()
    local wash = parent:CreateTexture(nil, layer or "BACKGROUND", nil, (sublevel or 1) + 1)
    wash:SetAllPoints(tex)
    wash:SetColorTexture(unpack(C.wash))
end

-- Drawn by hand: NineSliceUtil can't leave the title strip's dark band out, so the top pieces go in
-- slices. In the art the top line ends at 33/190 and the lower line starts at 72/190.
local TOP_CUT, LOW_CUT = 33 / 190, 72 / 190
local SIDE_LINE = { TopLeft = { 18 / 190, 39 / 190 }, TopRight = { 166 / 190, 1 } }
local TITLE_HEIGHT = 50
local FRAME_LEFT, FRAME_RIGHT, FRAME_TOP, FRAME_BOTTOM = -8, 2, 16, -8
local LINE_IN = { left = 11, right = 8, bottom = 5 }
local MARGIN = 14
UI.STYLES.radar.pad = LINE_IN.left + MARGIN
UI.STYLES.radar.bodyBottom = LINE_IN.bottom + MARGIN
UI.STYLES.radar.bodyTop = TITLE_HEIGHT + 8

local function Slice(f, atlas, u0, u1, v0, v1, wrapH)
    local info = C_Texture.GetAtlasInfo(atlas)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(info.file or info.filename, wrapH and "REPEAT" or "CLAMP", "CLAMP")
    local l, r, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    t.top, t.bottom = top + (bottom - top) * v0, top + (bottom - top) * v1
    t:SetTexCoord(l + (r - l) * u0, l + (r - l) * u1, t.top, t.bottom)
    t:SetSize(info.width * (u1 - u0), info.height * (v1 - v0))
    return t
end

-- Tile flags must be set before the atlas, as NineSliceUtil does.
local function Tiled(f, atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetHorizTile(info.tilesHorizontally)
    t:SetVertTile(info.tilesVertically)
    t:SetAtlas(atlas, true)
    return t
end

local function MetalFrame(f)
    local strip = FRAME_TOP + TITLE_HEIGHT
    local function Corner(side, x)
        local atlas = "UI-Frame-Metal-Corner" .. side
        local top = Slice(f, atlas, 0, 1, 0, TOP_CUT)
        local point = side == "TopLeft" and "TOPLEFT" or "TOPRIGHT"
        top:SetPoint(point, x, FRAME_TOP)
        local gap = strip - top:GetHeight()
        local u = SIDE_LINE[side]
        local line = Slice(f, atlas, u[1], u[2], TOP_CUT, LOW_CUT)
        line:SetHeight(gap)
        line:SetPoint("TOPLEFT", top, "BOTTOMLEFT", top:GetWidth() * u[1], 0)
        local bottom = Slice(f, atlas, 0, 1, LOW_CUT, 1)
        bottom:SetPoint(point, top, side == "TopLeft" and "BOTTOMLEFT" or "BOTTOMRIGHT", 0, -gap)
        return top, bottom
    end
    local tlTop, tlBottom = Corner("TopLeft", FRAME_LEFT)
    local trTop, trBottom = Corner("TopRight", FRAME_RIGHT)

    local edgeWidth = C_Texture.GetAtlasInfo("_UI-Frame-Metal-EdgeTop").width
    local lines = {}
    for i, cut in ipairs({ { 0, TOP_CUT, tlTop, trTop }, { LOW_CUT, 1, tlBottom, trBottom } }) do
        local line = Slice(f, "_UI-Frame-Metal-EdgeTop", 0, 1, cut[1], cut[2], true)
        line:SetPoint("TOPLEFT", cut[3], "TOPRIGHT")
        line:SetPoint("BOTTOMRIGHT", cut[4], "BOTTOMLEFT")
        lines[i] = line
    end
    function f.FitFrame()
        local repeats = (f:GetWidth() - FRAME_LEFT + FRAME_RIGHT - tlTop:GetWidth() - trTop:GetWidth()) / edgeWidth
        for _, line in ipairs(lines) do line:SetTexCoord(0, repeats, line.top, line.bottom) end
    end

    local bl = Tiled(f, "UI-Frame-Metal-CornerBottomLeft")
    bl:SetPoint("BOTTOMLEFT", FRAME_LEFT, FRAME_BOTTOM)
    local br = Tiled(f, "UI-Frame-Metal-CornerBottomRight")
    br:SetPoint("BOTTOMRIGHT", FRAME_RIGHT, FRAME_BOTTOM)
    local bottom = Tiled(f, "_UI-Frame-Metal-EdgeBottom")
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = Tiled(f, "!UI-Frame-Metal-EdgeLeft")
    left:SetPoint("TOPLEFT", tlBottom, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local right = Tiled(f, "!UI-Frame-Metal-EdgeRight")
    right:SetPoint("TOPRIGHT", trBottom, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMLEFT", br, "TOPLEFT")
end

local function BuildRadarShell()
    local f = CreateFrame("Frame", "AltisanFrame", UIParent)
    f:SetToplevel(true)

    -- Under the frame's lines, never past them: they sit 3-11 in on the left, 1-8 on the right.
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    fill:SetPoint("TOPLEFT", 4, 0)
    fill:SetPoint("BOTTOMRIGHT", -4, 2)
    fill:SetColorTexture(unpack(C.background))
    local tile = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile:SetAllPoints(fill)
    BrownTile(f, tile)
    MetalFrame(f)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", LINE_IN.left + MARGIN, -14)
    icon:SetTexture(ns.ICON)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(ns.TITLE)

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
    f.betaTag = BetaTag(f, f.subtitle)

    TitleButtons(f, LINE_IN.right + MARGIN, 16)
    return f
end

local LEDGER_CORNER, LEDGER_EDGE, LEDGER_SIDE = 118, 67, 56
local LEDGER_PLATE_WIDTH, LEDGER_PLATE_HEIGHT, LEDGER_PLATE_V = 263, 73, 71 / 128

local function BuildLedgerShell()
    local f = CreateFrame("Frame", "AltisanFrame", UIParent)
    f:SetToplevel(true)

    local inside = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    inside:SetPoint("TOPLEFT", LEDGER_SIDE, -LEDGER_EDGE)
    inside:SetPoint("BOTTOMRIGHT", -LEDGER_SIDE, LEDGER_EDGE)
    inside:SetTexture(UI.MEDIA .. "LedgerInside")

    -- Repeating needs both the wrap mode and the tile flag, as Blizzard's
    -- SetTextureWithAddressModeOptions does.
    local function Edge(file, from, to, horizontal)
        local t = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetTexture(UI.MEDIA .. file, horizontal and "REPEAT" or "CLAMP", horizontal and "CLAMP" or "REPEAT")
        t:SetHorizTile(horizontal)
        t:SetVertTile(not horizontal)
        t:SetPoint(from)
        t:SetPoint(to)
        return t
    end
    local top = Edge("LedgerEdgeTop", "TOPLEFT", "TOPRIGHT", true)
    local bottom = Edge("LedgerEdgeBottom", "BOTTOMLEFT", "BOTTOMRIGHT", true)
    local left = Edge("LedgerEdgeLeft", "TOPLEFT", "BOTTOMLEFT", false)
    local right = Edge("LedgerEdgeRight", "TOPRIGHT", "BOTTOMRIGHT", false)
    top:SetHeight(LEDGER_EDGE)
    bottom:SetHeight(LEDGER_EDGE)
    left:SetWidth(LEDGER_SIDE)
    right:SetWidth(LEDGER_SIDE)

    for i, point in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local corner = f:CreateTexture(nil, "BORDER")
        corner:SetTexture(UI.MEDIA .. "LedgerCorners")
        local u, v = ((i - 1) % 2) / 2, math.floor((i - 1) / 2) / 2
        corner:SetTexCoord(u, u + 0.5, v, v + 0.5)
        corner:SetSize(LEDGER_CORNER, LEDGER_CORNER)
        corner:SetPoint(point)
    end

    local plate = f:CreateTexture(nil, "ARTWORK")
    plate:SetTexture(UI.MEDIA .. "LedgerPlate")
    plate:SetTexCoord(0, 1, 0, LEDGER_PLATE_V)
    plate:SetSize(LEDGER_PLATE_WIDTH, LEDGER_PLATE_HEIGHT)
    plate:SetPoint("TOP")

    local pad = UI.STYLES.ledger.pad
    local feedback = TitleButtons(f, pad, 62)
    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.betaTag = BetaTag(f, f.subtitle)
    f.betaTag:ClearAllPoints()
    f.betaTag:SetPoint("RIGHT", feedback, "LEFT", -12, 0)
    f.subtitle:SetPoint("RIGHT", f.betaTag, "LEFT", -10, 0)

    return f
end

ns.WindowLooks = { radar = BuildRadarShell, ledger = BuildLedgerShell }
