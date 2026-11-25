-- Widgets.lua: the shapes and small pieces every page draws with: rounded boxes and masks, the thin
-- bar, a character's portrait and name, a selectable button, the search box.

local _, ns = ...

local UI = ns.UI
local C = UI.C

local TEXTURE_SIZE = 32
local RADII = { [3] = true, [5] = true, [6] = true, [8] = true, [9] = true, [10] = true }

local function Slices(f, layer, sublevel, file, r)
    local s, e = r / TEXTURE_SIZE, 1 - r / TEXTURE_SIZE
    local pieces = {}
    local function Piece(left, right, top, bottom)
        local t = f:CreateTexture(nil, layer, nil, sublevel)
        t:SetTexture(file)
        t:SetTexCoord(left, right, top, bottom)
        pieces[#pieces + 1] = t
        return t
    end
    local tl, tr = Piece(0, s, 0, s), Piece(e, 1, 0, s)
    local bl, br = Piece(0, s, e, 1), Piece(e, 1, e, 1)
    for _, corner in ipairs({ { tl, "TOPLEFT" }, { tr, "TOPRIGHT" }, { bl, "BOTTOMLEFT" }, { br, "BOTTOMRIGHT" } }) do
        corner[1]:SetSize(r, r)
        corner[1]:SetPoint(corner[2])
    end
    local function Between(t, a, aPoint, b, bPoint)
        t:SetPoint("TOPLEFT", a, aPoint)
        t:SetPoint("BOTTOMRIGHT", b, bPoint)
    end
    Between(Piece(s, e, 0, s), tl, "TOPRIGHT", tr, "BOTTOMLEFT")
    Between(Piece(s, e, e, 1), bl, "TOPRIGHT", br, "BOTTOMLEFT")
    Between(Piece(0, s, s, e), tl, "BOTTOMLEFT", bl, "TOPRIGHT")
    Between(Piece(e, 1, s, e), tr, "BOTTOMLEFT", br, "TOPRIGHT")
    Between(Piece(s, e, s, e), tl, "BOTTOMRIGHT", br, "TOPLEFT")
    return pieces
end

local function Tint(pieces, color)
    for _, t in ipairs(pieces) do t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
end

-- The edge sits a sublevel above the fill so an opaque fill can't cover it.
function UI.RoundedBox(f, radius, layer)
    assert(RADII[radius], "no rounded texture for radius " .. tostring(radius))
    local box = { shown = true }
    box.fill = Slices(f, layer or "BACKGROUND", 1, UI.MEDIA .. "RoundFill" .. radius, radius)
    box.edge = Slices(f, layer or "BACKGROUND", 2, UI.MEDIA .. "RoundEdge" .. radius, radius)
    function box:SetFill(color) Tint(self.fill, color) end
    function box:SetEdge(color) Tint(self.edge, color) end
    function box:SetShown(shown)
        self.shown = shown and true or false
        for _, t in ipairs(self.fill) do t:SetShown(shown) end
        for _, t in ipairs(self.edge) do t:SetShown(shown) end
    end
    box:SetFill(C.clear)
    box:SetEdge(C.clear)
    return box
end

function UI.RoundedHover(f, radius)
    Tint(Slices(f, "HIGHLIGHT", 0, UI.MEDIA .. "RoundFill" .. radius, radius), C.hover)
end

function UI.CircleMask(f, texture)
    local mask = f:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

function UI.RoundedMask(f, texture, radius)
    local mask = f:CreateMaskTexture()
    mask:SetTexture(UI.MEDIA .. "RoundFill" .. radius, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

function UI.SkillBar(parent, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 4)
    local track = holder:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(unpack(C.track))
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetAllPoints()
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(unpack(C.rule))
    return holder, bar
end

-- Atlas names use the race's file name in lower case, except Scourge ("undead").
local RACE_ATLAS_NAMES = { Scourge = "undead" }
function UI.PortraitAtlas(char)
    if not (char.race and char.sex) then return nil end
    local race = RACE_ATLAS_NAMES[char.race] or char.race:lower()
    local atlas = ("raceicon128-%s-%s"):format(race, char.sex == 3 and "female" or "male")
    return C_Texture.GetAtlasInfo(atlas) and atlas or nil
end

function UI.Portrait(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    local frame = UI.RoundedBox(holder, 6)
    frame:SetFill(C.portrait)
    frame:SetEdge(C.border)

    holder.image = holder:CreateTexture(nil, "ARTWORK")
    holder.image:SetPoint("TOPLEFT", 1, -1)
    holder.image:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.RoundedMask(holder, holder.image, 5)

    holder.classIcon = holder:CreateTexture(nil, "ARTWORK")
    holder.classIcon:SetAllPoints(holder.image)
    holder.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")

    function holder:SetCharacter(char)
        local atlas = UI.PortraitAtlas(char)
        self.image:SetShown(atlas ~= nil)
        if atlas then self.image:SetAtlas(atlas) end
        local coords = not atlas and char.class and CLASS_ICON_TCOORDS[char.class]
        self.classIcon:SetShown(coords and true or false)
        if coords then self.classIcon:SetTexCoord(unpack(coords)) end
    end
    return holder
end

function UI.CharacterName(key, char)
    local name = char.fullName or char.name or key
    local color = char.class and RAID_CLASS_COLORS[char.class]
    return color and color:WrapTextInColorCode(name) or name, color
end

function UI.MakeSelectable(b)
    b.fill = UI.RoundedBox(b, 6)
    b.fill:SetFill(C.selected)
    UI.RoundedHover(b, 6)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetJustifyH("LEFT")

    function b:SetSelected(selected, keepTextColor)
        self.fill:SetShown(selected)
        if not keepTextColor then
            self.text:SetTextColor(unpack(UI.Hex(selected and UI.TEXT.gold or UI.TEXT.body)))
        end
    end
    return b
end

function UI.SelectableButton(parent, height)
    local b = UI.MakeSelectable(CreateFrame("Button", nil, parent))
    b:SetHeight(height)
    b.text:SetWordWrap(false)
    b:SetSelected(false)
    return b
end

-- The box is a frame one level below the edit box so it never covers the text.
function UI.SearchBox(parent, onChange)
    local search = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    search:SetSize(200, 20)
    for _, art in ipairs({ "Left", "Middle", "Right" }) do
        local texture = search[art]
        if type(texture) == "table" then texture:Hide() end
    end
    local back = CreateFrame("Frame", nil, parent)
    back:SetPoint("TOPLEFT", search, "TOPLEFT", -6, 2)
    back:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 0, -2)
    back:SetFrameLevel(math.max(search:GetFrameLevel() - 1, 0))
    local box = UI.RoundedBox(back, 6)
    box:SetFill(C.searchFill)
    box:SetEdge(C.searchEdge)
    -- A sibling, not a child, so these hooks hide and show it with the box.
    search:HookScript("OnHide", function() back:Hide() end)
    search:HookScript("OnShow", function() back:Show() end)
    search.back = back
    search:HookScript("OnTextChanged", function(self) onChange(self:GetText() or "") end)
    return search
end
