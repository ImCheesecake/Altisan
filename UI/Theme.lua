-- Theme.lua: every color Altisan uses (UI.PALETTE, the game's in UI.GAME), the fills, edges and
-- lines that use them (UI.C), the window looks' sizes (UI.STYLES) and the media folder.

local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI
UI.drawingItem = false

function UI.Hex(hex, alpha)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255, alpha or 1 }
end

UI.PALETTE = {
    ink = "13100d", panel = "1b1815", raised = "2a241e", active = "3a3128",
    edgeLow = "5a4c3c", edge = "6e6253", dim = "7d7466", muted = "8a8174",
    soft = "a39a8a", light = "c8c0b0", parchment = "d8ccb4", body = "ece6da",
    bronze = "a67d45", brass = "cc9e52", gold = "ffd100", glow = "ffdb99",
    amber = "e0a050", green = "40bf40",
    black = "000000", white = "ffffff", horde = "ff6060", alliance = "6ea5ff",
}

-- The game's own colors, copied as the game shows them: not ours to change.
UI.GAME = {
    white = "ffffff",
    effect = "1fff00",
    tooltipGreen = "40ff40",
    stat = "9ec7ff",
}

local P = UI.PALETTE

UI.C = {
    background = UI.Hex(P.ink, 0.97),
    wash       = UI.Hex(P.black, 0.45),
    border     = UI.Hex(P.bronze),
    divider    = UI.Hex(P.bronze, 0.25),
    zebra      = UI.Hex(P.white, 0.025),
    hover      = UI.Hex(P.glow, 0.06),
    selected   = UI.Hex(P.bronze, 0.16),
    tracked    = UI.Hex(P.glow, 0.07),
    track      = UI.Hex(P.black, 0.45),
    rule       = UI.Hex(P.brass),
    clear      = UI.Hex(P.black, 0),
    cardFill   = UI.Hex(P.black, 0.25),
    boxFill    = UI.Hex(P.black, 0.6),
    portrait   = UI.Hex(P.black, 0.45),
    panel      = UI.Hex(P.panel),
    edgeIdle   = UI.Hex(P.edge),
    active     = UI.Hex(P.active),
    picked     = UI.Hex(P.raised),
    chipEdge   = UI.Hex(P.edgeLow),
    squareFill = UI.Hex(P.raised),
    foldEdge   = UI.Hex(P.bronze, 0.8),
    searchFill = UI.Hex(P.ink),
    searchEdge = UI.Hex(P.edge),             -- darker edges vanish on the game's background
    tick       = UI.Hex(P.panel),
    stepEnd    = UI.Hex(P.gold),
    menuFill   = UI.Hex(P.ink),
    unlit      = UI.Hex(P.edgeLow, 0.6),
    sectionIcon       = UI.Hex(P.brass),
    sectionIconPicked = UI.Hex(P.gold),
}
local C = UI.C

UI.STYLES = {
    radar = {
        grip = 10,
    },
    ledger = {
        bodyTop = 86,
        bodyBottom = 54,
        pad = 58,
        grip = 3,
        sectionIcons = true,
    },
}

function UI.Style()
    return UI.STYLES[ns.db.window.look] or UI.STYLES.radar
end

-- From the folder name: a texture path naming the wrong folder just draws nothing.
UI.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
