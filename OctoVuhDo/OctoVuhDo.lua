-- ============================================================================
-- OctoVuhDo - Advanced Raid & Party Frames (Vanilla 1.12.1 / OktoWoW)
-- Full-featured VuhDo & Grid2 inspired raid unit frames:
-- * Multi-button click-casting (Left, Right, Middle, Button4, Button5, WheelUp, WheelDown + Shift/Ctrl/Alt)
-- * Class & dispel debuff highlighting with center debuff icon
-- * 4-Corner HoT & buff tracker (Top-Left, Top-Right, Bottom-Left, Bottom-Right)
-- * Target indicator & emergency low HP pulse/flash alert (<30%)
-- * Raid Target lucky charms (Skull, Cross, Square, etc.)
-- * Granular sizing for bars, mana, fonts, gaps, and corner icons
-- * 1-Click visual themes (VuhDo Dark, Grid2 Minimalist, Healer Pro, Classic)
-- * Test mode for 5/10/20/40 players with realistic deficits and debuffs
-- ============================================================================

local OVD = CreateFrame("Frame", "OctoVuhDoCoreFrame", UIParent)
OctoVuhDoDB = OctoVuhDoDB or {}

-- ----------------------------------------------------------------------------
-- 1. Default Configuration & Database
-- ----------------------------------------------------------------------------
local DEFAULT_DB = {
    locked = false,
    scale = 1.0,
    barWidth = 84,
    barHeight = 36,
    barGap = 4,
    powerBarHeight = 5,
    nameFontSize = 9,
    hpFontSize = 8,
    powerFontSize = 7,
    hotSize = 8,
    debuffIconSize = 16,
    barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga",
    font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf",
    theme = "vuhdo_dark",
    
    -- Toggles & Display Options
    showNames = true,
    showHpText = true,
    showHpPct = true,
    showDeficit = true,
    showPower = true,
    showPowerText = false,
    manaOnly = false,
    classColors = true,
    showAggro = true,
    showDebuffs = true,
    showDebuffIcon = true,
    dispelMyClassOnly = false,
    showHots = true,
    rangeCheck = true,
    showTargetBorder = true,
    showRaidIcons = true,
    emergencyFlash = true,
    emergencyThreshold = 30, -- % HP
    showGroupHeaders = true,
    orientation = "HORIZONTAL", -- Horizontal groups vs Vertical
    hideBlizzParty = true, -- Automatically hide default Blizzard party frames
    
    testMode = false,
    testSize = 20,
    perSizePosition = true,
    positions = {
        [5] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [10] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [20] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [40] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
    },
    
    -- Click-Casting Bindings
    spells = {
        ["left"] = "target",
        ["right"] = "menu",
        ["middle"] = "",
        ["shift-left"] = "",
        ["shift-right"] = "",
        ["ctrl-left"] = "",
        ["ctrl-right"] = "",
        ["alt-left"] = "",
        ["alt-right"] = "",
        ["btn4"] = "",
        ["btn5"] = "",
        ["wheelup"] = "",
        ["wheeldown"] = "",
        ["shift-wheelup"] = "",
        ["shift-wheeldown"] = ""
    }
}

local CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, hex = "c79c6e" },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94, hex = "69ccf0" },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04, hex = "ff7d0a" },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73, hex = "f58cba" },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87, hex = "0070de" },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79, hex = "9482c9" },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45, hex = "abd473" },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41, hex = "fff569" }
}

local DEBUFF_COLORS = {
    Magic   = { r = 0.2, g = 0.6, b = 1.0 },
    Curse   = { r = 0.6, g = 0.0, b = 1.0 },
    Poison  = { r = 0.0, g = 0.8, b = 0.0 },
    Disease = { r = 0.6, g = 0.4, b = 0.0 }
}

local _, PLAYER_CLASS = UnitClass("player")
local DISPEL_CAPABILITIES = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    DRUID   = { Curse = true, Poison = true },
    MAGE    = { Curse = true },
    SHAMAN  = { Poison = true, Disease = true }
}

-- ----------------------------------------------------------------------------
-- 2. Test Simulation Data
-- ----------------------------------------------------------------------------
local TEST_NAMES = {
    "Ironshield", "Lightbearer", "Sunstrider", "Shadowweaver", "Wildheart",
    "Stormcaller", "Bloodthorn", "Swiftshot", "Nightstalker", "Earthshaker",
    "Flamecaller", "Frostweaver", "Doombringer", "Starbreeze", "Oakenshield",
    "Silverhand", "Goldenspear", "Shadowdancer", "Deeproots", "Thunderstrike",
    "Soulwarden", "Deathchill", "Firebrand", "Voidwalker", "Beastmaster",
    "Windwalker", "Steelcrusher", "Moonwhisper", "Brightblade", "Darkseeker",
    "Gravekeeper", "Lifegiver", "Stonewall", "Dawnbringer", "Wintermist",
    "Ragefire", "Dreadnaught", "Spiritwalker", "Bladestorm", "Holyfire"
}
local TEST_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "DRUID", "PALADIN", "SHAMAN", "WARLOCK", "ROGUE", "HUNTER" }

local function GetTestUnitData(index)
    local name = TEST_NAMES[index] or ("RaidMember" .. index)
    local cls = TEST_CLASSES[math.mod(index - 1, table.getn(TEST_CLASSES)) + 1]
    local maxHp = 4500 + (math.mod(index * 31, 25) * 50)
    local curHp = maxHp
    local debuffType = nil
    local debuffIcon = nil
    local hasAggro = false
    local raidIcon = nil

    if math.mod(index, 7) == 0 then
        curHp = math.floor(maxHp * 0.22) -- Emergency low HP (<30%)
        hasAggro = true
        raidIcon = 8 -- Skull
    elseif math.mod(index, 5) == 0 then
        curHp = math.floor(maxHp * 0.65)
        debuffType = "Curse"
        debuffIcon = "Interface\\Icons\\Spell_Shadow_GatherShadows"
    elseif math.mod(index, 4) == 0 then
        curHp = math.floor(maxHp * 0.80)
        debuffType = "Magic"
        debuffIcon = "Interface\\Icons\\Spell_Fire_Fireball"
        raidIcon = 7 -- Cross
    elseif math.mod(index, 9) == 0 then
        curHp = 0 -- Dead
    elseif math.mod(index, 3) == 0 then
        debuffType = "Poison"
        debuffIcon = "Interface\\Icons\\Spell_Nature_CorrosiveBreath"
    end

    local maxMp = (cls == "WARRIOR" or cls == "ROGUE") and 100 or 4000
    local curMp = (cls == "WARRIOR") and 45 or ((cls == "ROGUE") and 70 or 2800)

    return {
        name = name,
        class = cls,
        curHp = curHp,
        maxHp = maxHp,
        curPower = curMp,
        maxPower = maxMp,
        powerType = (cls == "WARRIOR" and 1 or (cls == "ROGUE" and 3 or 0)),
        inRange = (math.mod(index, 11) ~= 0),
        hasAggro = hasAggro,
        debuffType = debuffType,
        debuffIcon = debuffIcon,
        raidIcon = raidIcon,
        hotTL = (math.mod(index, 2) == 0),
        hotTR = (math.mod(index, 3) == 0),
        hotBL = (math.mod(index, 4) == 0),
        hotBR = (math.mod(index, 5) == 0),
        isTarget = (index == 1)
    }
end

-- ----------------------------------------------------------------------------
-- 3. Main Raid Container Frame & Headers
-- ----------------------------------------------------------------------------
local raidContainer = CreateFrame("Frame", "OctoVuhDoFrame", UIParent)
raidContainer:SetWidth(440)
raidContainer:SetHeight(200)
raidContainer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
raidContainer:SetClampedToScreen(true)
raidContainer:SetMovable(true)
raidContainer:EnableMouse(true)

-- Movable drag handle (Visible when UNLOCKED)
local dragHandle = CreateFrame("Button", nil, raidContainer)
dragHandle:SetPoint("BOTTOMLEFT", raidContainer, "TOPLEFT", 0, 3)
dragHandle:SetPoint("BOTTOMRIGHT", raidContainer, "TOPRIGHT", 0, 3)
dragHandle:SetHeight(18)
dragHandle:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
dragHandle:SetBackdropColor(0.08, 0.08, 0.12, 0.9)
dragHandle:SetBackdropBorderColor(0.2, 0.8, 1.0, 1)
dragHandle:EnableMouse(true)
dragHandle:RegisterForDrag("LeftButton")

local handleText = dragHandle:CreateFontString(nil, "OVERLAY")
handleText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
handleText:SetPoint("LEFT", dragHandle, "LEFT", 4, 0)
handleText:SetTextColor(0.4, 0.9, 1.0, 1)

local currentAppliedBracket = nil

local function GetCurrentRosterBracket()
    if OctoVuhDoDB.testMode then
        return OctoVuhDoDB.testSize or 20
    end
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        if numRaid <= 5 then return 5
        elseif numRaid <= 10 then return 10
        elseif numRaid <= 20 then return 20
        else return 40
        end
    else
        return 5
    end
end

local function UpdateHandleText(bracket)
    bracket = bracket or GetCurrentRosterBracket()
    if OctoVuhDoDB.perSizePosition then
        handleText:SetText("OctoVuhDo |cffffd200[" .. bracket .. "-Man]|r |cff88ff88[Drag to Move]|r")
    else
        handleText:SetText("OctoVuhDo Raid Frames |cff88ff88[Drag to Move]|r")
    end
end

local function ApplyRosterPosition(bracket, force)
    bracket = bracket or GetCurrentRosterBracket()
    if not force and currentAppliedBracket == bracket then
        UpdateHandleText(bracket)
        return
    end
    currentAppliedBracket = bracket

    local pos = nil
    if OctoVuhDoDB.perSizePosition and OctoVuhDoDB.positions and OctoVuhDoDB.positions[bracket] then
        pos = OctoVuhDoDB.positions[bracket]
    elseif OctoVuhDoDB.pos then
        pos = OctoVuhDoDB.pos
    end

    if pos and pos.point then
        raidContainer:ClearAllPoints()
        raidContainer:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    UpdateHandleText(bracket)
end

dragHandle:SetScript("OnDragStart", function()
    if not OctoVuhDoDB.locked then
        raidContainer:StartMoving()
        raidContainer.isMoving = true
    end
end)

dragHandle:SetScript("OnDragStop", function()
    if raidContainer.isMoving then
        raidContainer:StopMovingOrSizing()
        raidContainer.isMoving = false
        local point, _, relPoint, x, y = raidContainer:GetPoint()
        if point then
            local curPos = { point = point, relPoint = relPoint or point, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
            OctoVuhDoDB.pos = curPos
            local bracket = GetCurrentRosterBracket()
            if OctoVuhDoDB.perSizePosition then
                OctoVuhDoDB.positions = OctoVuhDoDB.positions or {}
                OctoVuhDoDB.positions[bracket] = curPos
                DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Saved position for |cffffd200" .. bracket .. "-Man|r group.")
            end
            currentAppliedBracket = bracket
            UpdateHandleText(bracket)
        end
    end
end)

local function UpdateLockState()
    if OctoVuhDoDB.locked then
        dragHandle:Hide()
        raidContainer:EnableMouse(false)
    else
        UpdateHandleText()
        dragHandle:Show()
        raidContainer:EnableMouse(true)
    end
end

-- Manage Blizzard Party Frames Visibility
local function UpdateBlizzardPartyFrames()
    for i = 1, 4 do
        local f = getglobal("PartyMemberFrame" .. i)
        if f then
            if not f.OVD_Hooked then
                f.OVD_Hooked = true
                local origShow = f.Show
                f.Show = function(self)
                    if OctoVuhDoDB.hideBlizzParty then
                        return
                    end
                    origShow(self)
                end
            end
            if OctoVuhDoDB.hideBlizzParty then
                f:Hide()
                f:UnregisterAllEvents()
            else
                f:RegisterEvent("PARTY_MEMBERS_CHANGED")
                f:RegisterEvent("PARTY_MEMBER_ENABLE")
                f:RegisterEvent("PARTY_MEMBER_DISABLE")
                f:RegisterEvent("UNIT_HEALTH")
                f:RegisterEvent("UNIT_MANA")
                if GetNumPartyMembers() >= i then
                    f:Show()
                end
            end
        end
    end
end

-- Group Headers (Group 1 - 8)
local groupHeaders = {}
local function GetGroupHeader(grpIdx)
    if not groupHeaders[grpIdx] then
        local fs = raidContainer:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        fs:SetTextColor(0.8, 0.8, 0.8, 0.9)
        fs:SetText("G" .. grpIdx)
        groupHeaders[grpIdx] = fs
    end
    return groupHeaders[grpIdx]
end

-- ----------------------------------------------------------------------------
-- 4. Unit Buttons Pool & Click-Casting
-- ----------------------------------------------------------------------------
local unitButtons = {}
local RefreshRoster -- Forward declaration

local function ExecuteClickCast(unit, mouseAction)
    if not unit or not UnitExists(unit) then
        if not OctoVuhDoDB.testMode then return end
    end

    local mod = ""
    if IsAltKeyDown() then mod = mod .. "alt-" end
    if IsControlKeyDown() then mod = mod .. "ctrl-" end
    if IsShiftKeyDown() then mod = mod .. "shift-" end

    local actionKey = mod .. mouseAction
    local action = OctoVuhDoDB.spells and OctoVuhDoDB.spells[actionKey]

    if not action or action == "" then
        if mouseAction == "left" then action = "target"
        elseif mouseAction == "right" then action = "menu"
        end
    end

    if action == "target" then
        if unit and UnitExists(unit) then TargetUnit(unit) end
    elseif action == "menu" then
        if unit and UnitExists(unit) then TargetUnit(unit) end
    elseif action and action ~= "" then
        if unit and UnitExists(unit) then
            TargetUnit(unit)
            CastSpellByName(action)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Cast |cffffd200" .. action .. "|r (Simulated on " .. (unit or "Unit") .. ")")
        end
    end
end

local function CreateUnitButton(index)
    local btn = CreateFrame("Button", "OctoVuhDoUnitBtn" .. index, raidContainer)
    btn:SetWidth(OctoVuhDoDB.barWidth or 84)
    btn:SetHeight(OctoVuhDoDB.barHeight or 36)

    -- Deficit Dark Background (Solid 100% opaque backing - prevents 3D world terrain/grass bleed-through)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture("Interface\\AddOns\\OctoVuhDo\\Images\\white_square_16_16.tga")
    bg:SetVertexColor(0.08, 0.08, 0.10, 1.0)
    btn.bg = bg

    -- Mouseover Highlight Glow (Authentic VuhDo feel)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.28)
    btn.highlight = hl

    -- Health Status Bar
    local hpBar = CreateFrame("StatusBar", nil, btn)
    hpBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    hpBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, (OctoVuhDoDB.showPower and (OctoVuhDoDB.powerBarHeight or 5) or 1))
    hpBar:SetStatusBarTexture(OctoVuhDoDB.barTexture or "Interface\\TargetingFrame\\UI-StatusBar")
    hpBar:SetMinMaxValues(0, 100)
    hpBar:SetValue(100)
    btn.hpBar = hpBar

    -- Power / Mana Mini Bar
    local powerBar = CreateFrame("StatusBar", nil, btn)
    powerBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
    powerBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    powerBar:SetHeight(OctoVuhDoDB.powerBarHeight or 5)
    powerBar:SetStatusBarTexture(OctoVuhDoDB.barTexture or "Interface\\TargetingFrame\\UI-StatusBar")
    powerBar:SetMinMaxValues(0, 100)
    powerBar:SetValue(100)
    powerBar:SetStatusBarColor(0.2, 0.4, 1.0, 1)
    btn.powerBar = powerBar

    -- Power Bar Text
    local powerText = powerBar:CreateFontString(nil, "OVERLAY")
    powerText:SetFont("Fonts\\FRIZQT__.TTF", OctoVuhDoDB.powerFontSize or 7, "OUTLINE")
    powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
    powerText:SetTextColor(1, 1, 1, 1)
    btn.powerText = powerText

    -- Threat / Debuff Highlight Border (Clean 9-slice frame, no center lines)
    local border = CreateFrame("Frame", nil, btn)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    border:SetFrameLevel(btn:GetFrameLevel() + 1)
    border:Hide()
    btn.border = border

    -- Target Indicator Border (Gold 9-slice frame, clean edges only)
    local targetBorder = CreateFrame("Frame", nil, btn)
    targetBorder:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    targetBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    targetBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    targetBorder:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    targetBorder:SetFrameLevel(btn:GetFrameLevel() + 2)
    targetBorder:Hide()
    btn.targetBorder = targetBorder

    -- Emergency Flash Overlay (<30% HP)
    local flashOverlay = btn:CreateTexture(nil, "OVERLAY")
    flashOverlay:SetAllPoints(btn)
    flashOverlay:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    flashOverlay:SetVertexColor(1, 0, 0, 0.35)
    flashOverlay:SetBlendMode("ADD")
    flashOverlay:Hide()
    btn.flashOverlay = flashOverlay

    -- Unit Name Text
    local nameText = hpBar:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", OctoVuhDoDB.nameFontSize or 9, "OUTLINE")
    nameText:SetPoint("TOP", hpBar, "TOP", 0, -2)
    nameText:SetTextColor(1, 1, 1, 1)
    btn.nameText = nameText

    -- Health / Deficit Text
    local hpText = hpBar:CreateFontString(nil, "OVERLAY")
    hpText:SetFont("Fonts\\FRIZQT__.TTF", OctoVuhDoDB.hpFontSize or 8, "OUTLINE")
    hpText:SetPoint("BOTTOM", hpBar, "BOTTOM", 0, 1)
    hpText:SetTextColor(0.85, 0.85, 0.85, 1)
    btn.hpText = hpText

    -- Center Debuff Icon
    local debuffIcon = hpBar:CreateTexture(nil, "OVERLAY")
    debuffIcon:SetWidth(OctoVuhDoDB.debuffIconSize or 16)
    debuffIcon:SetHeight(OctoVuhDoDB.debuffIconSize or 16)
    debuffIcon:SetPoint("CENTER", hpBar, "CENTER", 0, 0)
    debuffIcon:Hide()
    btn.debuffIcon = debuffIcon

    -- Raid Target Icon (Lucky Charm)
    local raidIcon = hpBar:CreateTexture(nil, "OVERLAY")
    raidIcon:SetWidth(14); raidIcon:SetHeight(14)
    raidIcon:SetPoint("TOP", hpBar, "TOP", 0, 2)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:Hide()
    btn.raidIcon = raidIcon

    -- 4-Corner HoT Indicators
    local hotTL = hpBar:CreateTexture(nil, "OVERLAY")
    hotTL:SetWidth(OctoVuhDoDB.hotSize or 8); hotTL:SetHeight(OctoVuhDoDB.hotSize or 8)
    hotTL:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 1, -1)
    hotTL:SetTexture(0.2, 0.8, 1.0, 1) -- Renew / Priest (Cyan)
    hotTL:Hide()
    btn.hotTL = hotTL

    local hotTR = hpBar:CreateTexture(nil, "OVERLAY")
    hotTR:SetWidth(OctoVuhDoDB.hotSize or 8); hotTR:SetHeight(OctoVuhDoDB.hotSize or 8)
    hotTR:SetPoint("TOPRIGHT", hpBar, "TOPRIGHT", -1, -1)
    hotTR:SetTexture(0.2, 1.0, 0.4, 1) -- Rejuv / Druid (Green)
    hotTR:Hide()
    btn.hotTR = hotTR

    local hotBL = hpBar:CreateTexture(nil, "OVERLAY")
    hotBL:SetWidth(OctoVuhDoDB.hotSize or 8); hotBL:SetHeight(OctoVuhDoDB.hotSize or 8)
    hotBL:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 1, 1)
    hotBL:SetTexture(1.0, 0.8, 0.2, 1) -- Shield / BoP (Gold)
    hotBL:Hide()
    btn.hotBL = hotBL

    local hotBR = hpBar:CreateTexture(nil, "OVERLAY")
    hotBR:SetWidth(OctoVuhDoDB.hotSize or 8); hotBR:SetHeight(OctoVuhDoDB.hotSize or 8)
    hotBR:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", -1, 1)
    hotBR:SetTexture(1.0, 0.4, 0.2, 1) -- Regrowth / Lifebloom (Orange)
    hotBR:Hide()
    btn.hotBR = hotBR

    -- Clicks & MouseWheel Support (Left, Right, Middle, Button4, Button5, WheelUp, WheelDown)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    btn:EnableMouseWheel(true)

    btn:SetScript("OnClick", function()
        local mouseAct = "left"
        if arg1 == "RightButton" then mouseAct = "right"
        elseif arg1 == "MiddleButton" then mouseAct = "middle"
        elseif arg1 == "Button4" then mouseAct = "btn4"
        elseif arg1 == "Button5" then mouseAct = "btn5"
        end
        ExecuteClickCast(this.unit, mouseAct)
    end)

    btn:SetScript("OnMouseWheel", function()
        local mouseAct = (arg1 > 0) and "wheelup" or "wheeldown"
        ExecuteClickCast(this.unit, mouseAct)
    end)

    btn:SetScript("OnEnter", function()
        if this.unit and UnitExists(this.unit) then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(this.unit)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

-- ----------------------------------------------------------------------------
-- 5. Range Checking, Debuffs & Visual Updaters
-- ----------------------------------------------------------------------------
local function CheckUnitRange(unit)
    if not UnitExists(unit) then return false end
    if UnitIsUnit(unit, "player") then return true end
    if CheckInteractDistance(unit, 4) then return true end
    if CheckInteractDistance(unit, 1) then return true end
    return false
end

-- Scan unit debuffs in 1.12
local function GetUnitDispelDebuff(unit)
    if not unit or not UnitExists(unit) then return nil, nil end
    for i = 1, 16 do
        local texture, count, debuffType = UnitDebuff(unit, i)
        if not texture then break end
        if debuffType and DEBUFF_COLORS[debuffType] then
            if not OctoVuhDoDB.dispelMyClassOnly or (DISPEL_CAPABILITIES[PLAYER_CLASS] and DISPEL_CAPABILITIES[PLAYER_CLASS][debuffType]) then
                return debuffType, texture
            end
        end
    end
    return nil, nil
end

local function UpdateUnitVisual(btn, data)
    local cur = data.curHp or 1
    local max = math.max(data.maxHp or 1, 1)
    local pct = math.floor((cur / max) * 100)
    local barTex = OctoVuhDoDB.barTexture or "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga"
    local font = OctoVuhDoDB.font or "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"

    btn.hpBar:SetMinMaxValues(0, max)
    btn.hpBar:SetValue(cur)
    btn.hpBar:SetStatusBarTexture(barTex)

    -- Bar Color (Class Colored or Classic Green)
    local color = CLASS_COLORS[data.class] or { r = 0.2, g = 0.8, b = 0.2 }
    if OctoVuhDoDB.classColors then
        btn.hpBar:SetStatusBarColor(color.r, color.g, color.b, 1)
        btn.nameText:SetTextColor(1, 1, 1, 1)
    else
        btn.hpBar:SetStatusBarColor(0.2, 0.8, 0.3, 1)
        btn.nameText:SetTextColor(color.r, color.g, color.b, 1)
    end

    -- 1. Name Text
    btn.nameText:SetFont(font, OctoVuhDoDB.nameFontSize or 9, "OUTLINE")
    if OctoVuhDoDB.showNames then
        btn.nameText:SetText(data.name or "Unit")
        btn.nameText:Show()
    else
        btn.nameText:Hide()
    end

    -- 2. Health & Deficit Text
    btn.hpText:SetFont(font, OctoVuhDoDB.hpFontSize or 8, "OUTLINE")
    if not OctoVuhDoDB.showHpText then
        btn.hpText:Hide()
    else
        btn.hpText:Show()
        if cur <= 0 then
            btn.hpText:SetText("|cffff2020DEAD|r")
            btn.hpBar:SetValue(0)
        else
            local showPct = OctoVuhDoDB.showHpPct
            local showDef = OctoVuhDoDB.showDeficit

            if showPct and showDef then
                if pct < 100 then
                    local deficit = max - cur
                    local defStr = deficit >= 1000 and string.format("-%.1fk", deficit / 1000) or ("-" .. deficit)
                    btn.hpText:SetText(pct .. "% (" .. defStr .. ")")
                else
                    btn.hpText:SetText("100%")
                end
            elseif showPct and not showDef then
                btn.hpText:SetText(pct .. "%")
            elseif not showPct and showDef then
                if pct < 100 then
                    local deficit = max - cur
                    local defStr = deficit >= 1000 and string.format("-%.1fk", deficit / 1000) or ("-" .. deficit)
                    btn.hpText:SetText(defStr)
                else
                    btn.hpText:SetText("")
                end
            else
                btn.hpText:SetText("")
            end
        end
    end

    -- 3. Power / Mana Bar
    local isManaUser = (data.powerType == 0)
    local shouldShowPower = OctoVuhDoDB.showPower and (not OctoVuhDoDB.manaOnly or isManaUser)
    local powerH = OctoVuhDoDB.powerBarHeight or 5

    if shouldShowPower then
        btn.powerBar:SetHeight(powerH)
        btn.hpBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, powerH + 1)
        btn.powerBar:Show()
        btn.powerBar:SetStatusBarTexture(barTex)
        btn.powerBar:SetMinMaxValues(0, math.max(data.maxPower or 1, 1))
        btn.powerBar:SetValue(data.curPower or 0)

        if data.powerType == 1 then
            btn.powerBar:SetStatusBarColor(1, 0.2, 0.2, 1) -- Rage
        elseif data.powerType == 3 then
            btn.powerBar:SetStatusBarColor(1, 0.8, 0.1, 1) -- Energy
        else
            btn.powerBar:SetStatusBarColor(0.2, 0.5, 1.0, 1) -- Mana
        end

        if OctoVuhDoDB.showPowerText and data.maxPower and data.maxPower > 0 then
            local powPct = math.floor((data.curPower / data.maxPower) * 100)
            btn.powerText:SetFont(font, OctoVuhDoDB.powerFontSize or 7, "OUTLINE")
            btn.powerText:SetText(powPct .. "%")
            btn.powerText:Show()
        else
            btn.powerText:Hide()
        end
    else
        btn.powerBar:Hide()
        btn.powerText:Hide()
        btn.hpBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end

    -- 4. Aggro & Debuff Borders
    local hasAggroAlert = OctoVuhDoDB.showAggro and data.hasAggro
    local hasDebuffAlert = OctoVuhDoDB.showDebuffs and data.debuffType and DEBUFF_COLORS[data.debuffType]

    if hasAggroAlert then
        btn.border:SetBackdropBorderColor(1, 0.1, 0.1, 1)
        btn.border:Show()
    elseif hasDebuffAlert then
        local dc = DEBUFF_COLORS[data.debuffType]
        btn.border:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1)
        btn.border:Show()
    else
        btn.border:Hide()
    end

    -- 5. Center Debuff Icon
    local debuffIconSize = OctoVuhDoDB.debuffIconSize or 16
    btn.debuffIcon:SetWidth(debuffIconSize)
    btn.debuffIcon:SetHeight(debuffIconSize)
    if OctoVuhDoDB.showDebuffIcon and data.debuffIcon then
        btn.debuffIcon:SetTexture(data.debuffIcon)
        btn.debuffIcon:Show()
    else
        btn.debuffIcon:Hide()
    end

    -- 6. Emergency Low HP Flash (<30%)
    local thresh = OctoVuhDoDB.emergencyThreshold or 30
    if OctoVuhDoDB.emergencyFlash and cur > 0 and pct <= thresh then
        btn.flashOverlay:Show()
    else
        btn.flashOverlay:Hide()
    end

    -- 7. Target Indicator Border
    local isTarget = data.isTarget
    if isTarget == nil and btn.unit and UnitExists("target") then
        isTarget = UnitIsUnit(btn.unit, "target")
    end
    if OctoVuhDoDB.showTargetBorder and isTarget then
        btn.targetBorder:Show()
    else
        btn.targetBorder:Hide()
    end

    -- 8. Raid Target Lucky Charm (Skull, Cross, etc.)
    if OctoVuhDoDB.showRaidIcons and data.raidIcon and data.raidIcon > 0 and data.raidIcon <= 8 then
        SetRaidTargetIconTexture(btn.raidIcon, data.raidIcon)
        btn.raidIcon:Show()
    else
        btn.raidIcon:Hide()
    end

    -- 9. 4-Corner HoT Indicators
    local hotS = OctoVuhDoDB.hotSize or 8
    btn.hotTL:SetWidth(hotS); btn.hotTL:SetHeight(hotS)
    btn.hotTR:SetWidth(hotS); btn.hotTR:SetHeight(hotS)
    btn.hotBL:SetWidth(hotS); btn.hotBL:SetHeight(hotS)
    btn.hotBR:SetWidth(hotS); btn.hotBR:SetHeight(hotS)

    if OctoVuhDoDB.showHots then
        if data.hotTL then btn.hotTL:Show() else btn.hotTL:Hide() end
        if data.hotTR then btn.hotTR:Show() else btn.hotTR:Hide() end
        if data.hotBL then btn.hotBL:Show() else btn.hotBL:Hide() end
        if data.hotBR then btn.hotBR:Show() else btn.hotBR:Hide() end
    else
        btn.hotTL:Hide(); btn.hotTR:Hide(); btn.hotBL:Hide(); btn.hotBR:Hide()
    end

    -- 10. Range Fading (Fade internal elements; keep button & background 100% opaque to block 3D world/grass bleed-through)
    btn:SetAlpha(1.0)
    local isOutOfRange = OctoVuhDoDB.rangeCheck and not data.inRange
    if isOutOfRange then
        btn.hpBar:SetAlpha(0.35)
        btn.powerBar:SetAlpha(0.35)
        btn.nameText:SetAlpha(0.55)
        btn.hpText:SetAlpha(cur <= 0 and 0.65 or 0.55)
    else
        btn.hpBar:SetAlpha(1.0)
        btn.powerBar:SetAlpha(1.0)
        btn.nameText:SetAlpha(1.0)
        btn.hpText:SetAlpha(1.0)
    end
end

-- ----------------------------------------------------------------------------
-- 6. Roster Layout & Positioning Engine
-- ----------------------------------------------------------------------------
RefreshRoster = function()
    local barW = OctoVuhDoDB.barWidth or 84
    local barH = OctoVuhDoDB.barHeight or 36
    local gap = OctoVuhDoDB.barGap or 4
    local showHeaders = OctoVuhDoDB.showGroupHeaders

    -- Check and apply bracket position if group size changed
    local bracket = GetCurrentRosterBracket()
    if not raidContainer.isMoving and currentAppliedBracket ~= bracket then
        ApplyRosterPosition(bracket)
    end

    -- Hide all group headers first
    for i = 1, 8 do
        if groupHeaders[i] then groupHeaders[i]:Hide() end
    end

    -- 1. TEST MODE PREVIEW
    if OctoVuhDoDB.testMode then
        local numTest = OctoVuhDoDB.testSize or 20
        local groups = math.ceil(numTest / 5)
        local headerHeight = showHeaders and 14 or 0

        for i = 1, 40 do
            if not unitButtons[i] then unitButtons[i] = CreateUnitButton(i) end
            local btn = unitButtons[i]
            if i <= numTest then
                btn.unit = nil
                btn:SetWidth(barW)
                btn:SetHeight(barH)

                local group = math.floor((i - 1) / 5)
                local member = math.mod(i - 1, 5)
                local posX = group * (barW + gap)
                local posY = -headerHeight - (member * (barH + gap))

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", raidContainer, "TOPLEFT", posX, posY)
                btn:Show()

                -- Group Header positioning
                if showHeaders and member == 0 then
                    local gh = GetGroupHeader(group + 1)
                    gh:ClearAllPoints()
                    gh:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 2, 2)
                    gh:Show()
                end

                local data = GetTestUnitData(i)
                UpdateUnitVisual(btn, data)
            else
                btn:Hide()
            end
        end

        local totalW = groups * (barW + gap) - gap
        local totalH = headerHeight + 5 * (barH + gap) - gap
        raidContainer:SetWidth(totalW)
        raidContainer:SetHeight(totalH)
        UpdateLockState()
        return
    end

    -- 2. LIVE ROSTER
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()

    if numRaid > 0 then
        local groupsUsed = {}
        local headerHeight = showHeaders and 14 or 0
        local maxSubgroup = 1
        local maxMemberInGroup = 0

        for i = 1, 40 do
            if not unitButtons[i] then unitButtons[i] = CreateUnitButton(i) end
            local btn = unitButtons[i]

            if i <= numRaid then
                local unit = "raid" .. i
                btn.unit = unit
                btn:SetWidth(barW)
                btn:SetHeight(barH)

                local name, rank, subgroup = GetRaidRosterInfo(i)
                subgroup = subgroup or math.floor((i - 1) / 5) + 1
                if subgroup > maxSubgroup then maxSubgroup = subgroup end
                groupsUsed[subgroup] = (groupsUsed[subgroup] or 0) + 1
                local memberInGroup = groupsUsed[subgroup] - 1
                if memberInGroup > maxMemberInGroup then maxMemberInGroup = memberInGroup end

                local posX = (subgroup - 1) * (barW + gap)
                local posY = -headerHeight - (memberInGroup * (barH + gap))

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", raidContainer, "TOPLEFT", posX, posY)
                btn:Show()

                if showHeaders and memberInGroup == 0 then
                    local gh = GetGroupHeader(subgroup)
                    gh:ClearAllPoints()
                    gh:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 2, 2)
                    gh:Show()
                end

                local _, cls = UnitClass(unit)
                local curHp = UnitHealth(unit)
                local maxHp = UnitHealthMax(unit)
                local curPow = UnitMana(unit)
                local maxPow = UnitManaMax(unit)
                local pType = UnitPowerType(unit)
                local inRange = CheckUnitRange(unit)
                local debuffType, debuffIcon = GetUnitDispelDebuff(unit)
                local raidIcon = GetRaidTargetIndex(unit)

                -- Quick HoT check
                local hasRenew, hasRejuv = false, false
                for b = 1, 16 do
                    local t = UnitBuff(unit, b)
                    if not t then break end
                    if string.find(t, "Spell_Holy_Renew") then hasRenew = true end
                    if string.find(t, "Spell_Nature_Rejuvenation") then hasRejuv = true end
                end

                UpdateUnitVisual(btn, {
                    name = name or UnitName(unit),
                    class = cls,
                    curHp = curHp,
                    maxHp = maxHp,
                    curPower = curPow,
                    maxPower = maxPow,
                    powerType = pType,
                    inRange = inRange,
                    hasAggro = false,
                    debuffType = debuffType,
                    debuffIcon = debuffIcon,
                    raidIcon = raidIcon,
                    hotTL = hasRenew,
                    hotTR = hasRejuv,
                    hotBL = false,
                    hotBR = false
                })
            else
                btn:Hide()
            end
        end
        local totalW = maxSubgroup * (barW + gap) - gap
        local totalH = headerHeight + (maxMemberInGroup + 1) * (barH + gap) - gap
        raidContainer:SetWidth(math.max(totalW, barW))
        raidContainer:SetHeight(math.max(totalH, barH))
    elseif numParty > 0 then
        local totalUnits = numParty + 1
        for i = 1, 40 do
            if not unitButtons[i] then unitButtons[i] = CreateUnitButton(i) end
            local btn = unitButtons[i]

            if i <= totalUnits then
                local unit = (i == 1) and "player" or ("party" .. (i - 1))
                btn.unit = unit
                btn:SetWidth(barW)
                btn:SetHeight(barH)

                local posX = 0
                local posY = -((i - 1) * (barH + gap))

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", raidContainer, "TOPLEFT", posX, posY)
                btn:Show()

                local _, cls = UnitClass(unit)
                local debuffType, debuffIcon = GetUnitDispelDebuff(unit)
                local raidIcon = GetRaidTargetIndex(unit)

                UpdateUnitVisual(btn, {
                    name = UnitName(unit),
                    class = cls,
                    curHp = UnitHealth(unit),
                    maxHp = UnitHealthMax(unit),
                    curPower = UnitMana(unit),
                    maxPower = UnitManaMax(unit),
                    powerType = UnitPowerType(unit),
                    inRange = (i == 1 or CheckUnitRange(unit)),
                    hasAggro = false,
                    debuffType = debuffType,
                    debuffIcon = debuffIcon,
                    raidIcon = raidIcon,
                    hotTL = false,
                    hotTR = false,
                    hotBL = false,
                    hotBR = false
                })
            else
                btn:Hide()
            end
        end
        raidContainer:SetWidth(barW)
        raidContainer:SetHeight(totalUnits * (barH + gap) - gap)
    else
        for i = 1, 40 do
            if not unitButtons[i] then unitButtons[i] = CreateUnitButton(i) end
            local btn = unitButtons[i]
            if i == 1 then
                btn.unit = "player"
                btn:SetWidth(barW)
                btn:SetHeight(barH)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", raidContainer, "TOPLEFT", 0, 0)
                btn:Show()

                local _, cls = UnitClass("player")
                local debuffType, debuffIcon = GetUnitDispelDebuff("player")
                local raidIcon = GetRaidTargetIndex("player")

                UpdateUnitVisual(btn, {
                    name = UnitName("player"),
                    class = cls,
                    curHp = UnitHealth("player"),
                    maxHp = UnitHealthMax("player"),
                    curPower = UnitMana("player"),
                    maxPower = UnitManaMax("player"),
                    powerType = UnitPowerType("player"),
                    inRange = true,
                    hasAggro = false,
                    debuffType = debuffType,
                    debuffIcon = debuffIcon,
                    raidIcon = raidIcon,
                    hotTL = false,
                    hotTR = false,
                    hotBL = false,
                    hotBR = false
                })
            else
                btn:Hide()
            end
        end
        raidContainer:SetWidth(barW)
        raidContainer:SetHeight(barH)
    end

    UpdateLockState()
end

-- ----------------------------------------------------------------------------
-- 7. Settings Menu Dialog (`OctoVuhDoOptionsFrame`)
-- ----------------------------------------------------------------------------
local opt = CreateFrame("Frame", "OctoVuhDoOptionsFrame", UIParent)
opt:SetWidth(460)
opt:SetHeight(480)
opt:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
opt:SetFrameStrata("DIALOG")
opt:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
opt:SetMovable(true)
opt:EnableMouse(true)
opt:RegisterForDrag("LeftButton")
opt:SetScript("OnDragStart", function() this:StartMoving() end)
opt:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
opt:Hide()

local optTitle = opt:CreateFontString(nil, "OVERLAY")
optTitle:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
optTitle:SetPoint("TOP", opt, "TOP", 0, -10)
optTitle:SetTextColor(0.4, 0.9, 1.0, 1)
optTitle:SetText("OctoVuhDo - Advanced Raid Frames Configuration")

local optClose = CreateFrame("Button", nil, opt, "UIPanelCloseButton")
optClose:SetWidth(24); optClose:SetHeight(24)
optClose:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -2, -2)
optClose:SetScript("OnClick", function() opt:Hide() end)

-- 5 Organized Tabs: [Sizing] [Toggles] [Click-Casting] [Themes] [Test Mode]
local tabs = {}
local panels = {}

local tabDefs = {
    { id = 1, name = "Sizing", width = 68 },
    { id = 2, name = "Toggles", width = 72 },
    { id = 3, name = "Click-Cast", width = 88 },
    { id = 4, name = "Themes", width = 75 },
    { id = 5, name = "Test Mode", width = 82 }
}

local function SwitchTab(tabIdx)
    for i = 1, table.getn(tabDefs) do
        if i == tabIdx then
            tabs[i]:SetText("|cff20ff20" .. tabDefs[i].name .. "|r")
            panels[i]:Show()
        else
            tabs[i]:SetText(tabDefs[i].name)
            panels[i]:Hide()
        end
    end
end

local prevTab = nil
for i = 1, table.getn(tabDefs) do
    local def = tabDefs[i]
    local btn = CreateFrame("Button", "OVD_Tab" .. i, opt, "UIPanelButtonTemplate")
    btn:SetWidth(def.width); btn:SetHeight(20)
    if prevTab then
        btn:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
    else
        btn:SetPoint("TOPLEFT", opt, "TOPLEFT", 12, -26)
    end
    btn:SetText(i == 1 and ("|cff20ff20" .. def.name .. "|r") or def.name)
    local idx = i
    btn:SetScript("OnClick", function() SwitchTab(idx) end)
    tabs[i] = btn
    prevTab = btn

    local pan = CreateFrame("Frame", nil, opt)
    pan:SetPoint("TOPLEFT", opt, "TOPLEFT", 10, -50)
    pan:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", -10, 10)
    if i > 1 then pan:Hide() end
    panels[i] = pan
end

-- Helper: Sizing Controls
local function CreateSliderRow(parent, label, yOfs, minVal, maxVal, step, suffix, getVal, setVal)
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10)
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOfs)
    lbl:SetText(label)

    local dec = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    dec:SetWidth(22); dec:SetHeight(18); dec:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -80, yOfs + 2); dec:SetText("-")

    local valText = parent:CreateFontString(nil, "OVERLAY")
    valText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    valText:SetWidth(45); valText:SetJustifyH("CENTER")
    valText:SetPoint("LEFT", dec, "RIGHT", 2, 0)

    local inc = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    inc:SetWidth(22); inc:SetHeight(18); inc:SetPoint("LEFT", valText, "RIGHT", 2, 0); inc:SetText("+")

    local function UpdateText()
        valText:SetText(tostring(getVal()) .. (suffix or ""))
    end
    UpdateText()

    dec:SetScript("OnClick", function()
        local v = getVal() - step
        if v < minVal then v = minVal end
        setVal(v)
        UpdateText()
        RefreshRoster()
    end)
    inc:SetScript("OnClick", function()
        local v = getVal() + step
        if v > maxVal then v = maxVal end
        setVal(v)
        UpdateText()
        RefreshRoster()
    end)
end

local VUHDO_TEXTURES = {
    { name = "VuhDo Minimalist", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga" },
    { name = "VuhDo Concave Dark", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar4.tga" },
    { name = "VuhDo Polished Wood", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar15.tga" },
    { name = "VuhDo Flat", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar6.tga" },
    { name = "VuhDo Pipe Dark", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar3.tga" },
    { name = "VuhDo Pipe Light", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar5.tga" },
    { name = "VuhDo Concave Light", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar7.tga" },
    { name = "VuhDo Convex", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar8.tga" },
    { name = "VuhDo Aluminium", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar18.tga" },
    { name = "VuhDo Rhombs", file = "Interface\\AddOns\\OctoVuhDo\\Images\\bar1.tga" },
    { name = "Blizzard Classic", file = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Blizzard Smooth", file = "Interface\\Tooltips\\UI-Tooltip-Background" },
}

local VUHDO_FONTS = {
    { name = "VuhDo Emblem", file = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf" },
    { name = "VuhDo Arial Black", file = "Interface\\AddOns\\OctoVuhDo\\Fonts\\ariblk.ttf" },
    { name = "Blizzard Friz", file = "Fonts\\FRIZQT__.TTF" },
}

-- ----------------------------------------------------------------------------
-- TAB 1: Sizing Controls
-- ----------------------------------------------------------------------------
local p1 = panels[1]
CreateSliderRow(p1, "Frame Width (px):", -8, 40, 180, 4, "px",
    function() return OctoVuhDoDB.barWidth or 84 end,
    function(v) OctoVuhDoDB.barWidth = v end)

CreateSliderRow(p1, "Frame Height (px):", -34, 18, 90, 2, "px",
    function() return OctoVuhDoDB.barHeight or 36 end,
    function(v) OctoVuhDoDB.barHeight = v end)

CreateSliderRow(p1, "Mana Bar Height (px):", -60, 2, 24, 1, "px",
    function() return OctoVuhDoDB.powerBarHeight or 5 end,
    function(v) OctoVuhDoDB.powerBarHeight = v end)

CreateSliderRow(p1, "Grid Spacing / Gap (px):", -86, 0, 16, 1, "px",
    function() return OctoVuhDoDB.barGap or 4 end,
    function(v) OctoVuhDoDB.barGap = v end)

CreateSliderRow(p1, "Name Font Size:", -112, 6, 18, 1, "pt",
    function() return OctoVuhDoDB.nameFontSize or 9 end,
    function(v) OctoVuhDoDB.nameFontSize = v end)

CreateSliderRow(p1, "Health Text Font Size:", -138, 6, 18, 1, "pt",
    function() return OctoVuhDoDB.hpFontSize or 8 end,
    function(v) OctoVuhDoDB.hpFontSize = v end)

CreateSliderRow(p1, "Mana Text Font Size:", -164, 5, 14, 1, "pt",
    function() return OctoVuhDoDB.powerFontSize or 7 end,
    function(v) OctoVuhDoDB.powerFontSize = v end)

CreateSliderRow(p1, "HoT Corner Icon Size:", -190, 4, 18, 1, "px",
    function() return OctoVuhDoDB.hotSize or 8 end,
    function(v) OctoVuhDoDB.hotSize = v end)

CreateSliderRow(p1, "Center Debuff Icon Size:", -216, 10, 32, 2, "px",
    function() return OctoVuhDoDB.debuffIconSize or 16 end,
    function(v) OctoVuhDoDB.debuffIconSize = v end)

CreateSliderRow(p1, "Low HP Alert Threshold (%):", -242, 10, 60, 5, "%",
    function() return OctoVuhDoDB.emergencyThreshold or 30 end,
    function(v) OctoVuhDoDB.emergencyThreshold = v end)

CreateSliderRow(p1, "Overall UI Scale (%):", -268, 50, 200, 5, "%",
    function() return math.floor((OctoVuhDoDB.scale or 1.0) * 100 + 0.5) end,
    function(v)
        OctoVuhDoDB.scale = v / 100
        raidContainer:SetScale(OctoVuhDoDB.scale)
    end)

-- Texture Selector Row
local texRowY = -296
local texLbl = p1:CreateFontString(nil, "OVERLAY")
texLbl:SetFont("Fonts\\FRIZQT__.TTF", 10)
texLbl:SetPoint("TOPLEFT", p1, "TOPLEFT", 14, texRowY)
texLbl:SetText("Status Bar Texture:")

local function GetCurrentTexIdx()
    local cur = OctoVuhDoDB.barTexture or "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga"
    for i = 1, table.getn(VUHDO_TEXTURES) do
        if VUHDO_TEXTURES[i].file == cur then return i end
    end
    return 1
end

local texPrev = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
texPrev:SetWidth(22); texPrev:SetHeight(18); texPrev:SetPoint("TOPRIGHT", p1, "TOPRIGHT", -150, texRowY + 2); texPrev:SetText("<")

local texName = p1:CreateFontString(nil, "OVERLAY")
texName:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
texName:SetWidth(125); texName:SetJustifyH("CENTER")
texName:SetPoint("LEFT", texPrev, "RIGHT", 2, 0)

local texNext = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
texNext:SetWidth(22); texNext:SetHeight(18); texNext:SetPoint("LEFT", texName, "RIGHT", 2, 0); texNext:SetText(">")

local function UpdateTexDisplay()
    local idx = GetCurrentTexIdx()
    texName:SetText(VUHDO_TEXTURES[idx].name)
end
UpdateTexDisplay()

texPrev:SetScript("OnClick", function()
    local idx = GetCurrentTexIdx() - 1
    if idx < 1 then idx = table.getn(VUHDO_TEXTURES) end
    OctoVuhDoDB.barTexture = VUHDO_TEXTURES[idx].file
    UpdateTexDisplay()
    RefreshRoster()
end)

texNext:SetScript("OnClick", function()
    local idx = GetCurrentTexIdx() + 1
    if idx > table.getn(VUHDO_TEXTURES) then idx = 1 end
    OctoVuhDoDB.barTexture = VUHDO_TEXTURES[idx].file
    UpdateTexDisplay()
    RefreshRoster()
end)

-- Font Selector Row
local fontRowY = -322
local fontLbl = p1:CreateFontString(nil, "OVERLAY")
fontLbl:SetFont("Fonts\\FRIZQT__.TTF", 10)
fontLbl:SetPoint("TOPLEFT", p1, "TOPLEFT", 14, fontRowY)
fontLbl:SetText("Unit Text Font:")

local function GetCurrentFontIdx()
    local cur = OctoVuhDoDB.font or "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
    for i = 1, table.getn(VUHDO_FONTS) do
        if VUHDO_FONTS[i].file == cur then return i end
    end
    return 1
end

local fontPrev = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
fontPrev:SetWidth(22); fontPrev:SetHeight(18); fontPrev:SetPoint("TOPRIGHT", p1, "TOPRIGHT", -150, fontRowY + 2); fontPrev:SetText("<")

local fontName = p1:CreateFontString(nil, "OVERLAY")
fontName:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
fontName:SetWidth(125); fontName:SetJustifyH("CENTER")
fontName:SetPoint("LEFT", fontPrev, "RIGHT", 2, 0)

local fontNext = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
fontNext:SetWidth(22); fontNext:SetHeight(18); fontNext:SetPoint("LEFT", fontName, "RIGHT", 2, 0); fontNext:SetText(">")

local function UpdateFontDisplay()
    local idx = GetCurrentFontIdx()
    fontName:SetText(VUHDO_FONTS[idx].name)
end
UpdateFontDisplay()

fontPrev:SetScript("OnClick", function()
    local idx = GetCurrentFontIdx() - 1
    if idx < 1 then idx = table.getn(VUHDO_FONTS) end
    OctoVuhDoDB.font = VUHDO_FONTS[idx].file
    UpdateFontDisplay()
    RefreshRoster()
end)

fontNext:SetScript("OnClick", function()
    local idx = GetCurrentFontIdx() + 1
    if idx > table.getn(VUHDO_FONTS) then idx = 1 end
    OctoVuhDoDB.font = VUHDO_FONTS[idx].file
    UpdateFontDisplay()
    RefreshRoster()
end)

-- ----------------------------------------------------------------------------
-- TAB 2: Toggles & Display Options
-- ----------------------------------------------------------------------------
local p2 = panels[2]
local function CreateToggleBtn(parent, xOfs, yOfs, width, label, getVal, setVal)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(width); btn:SetHeight(22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOfs, yOfs)

    local function UpdateText()
        local state = getVal() and "|cff20ff20ON|r" or "|cffff4040OFF|r"
        btn:SetText(label .. ": " .. state)
    end
    UpdateText()

    btn:SetScript("OnClick", function()
        setVal(not getVal())
        UpdateText()
        RefreshRoster()
    end)
    return btn
end

-- Column 1: Health & Text (Left: 12)
CreateToggleBtn(p2, 12, -8, 200, "Show Player Names",
    function() return OctoVuhDoDB.showNames end,
    function(v) OctoVuhDoDB.showNames = v end)

CreateToggleBtn(p2, 12, -34, 200, "Show Health Text",
    function() return OctoVuhDoDB.showHpText end,
    function(v) OctoVuhDoDB.showHpText = v end)

CreateToggleBtn(p2, 12, -60, 200, "Show % of HP",
    function() return OctoVuhDoDB.showHpPct end,
    function(v) OctoVuhDoDB.showHpPct = v end)

CreateToggleBtn(p2, 12, -86, 200, "Show HP Deficit",
    function() return OctoVuhDoDB.showDeficit end,
    function(v) OctoVuhDoDB.showDeficit = v end)

CreateToggleBtn(p2, 12, -112, 200, "Show Power/Mana Bars",
    function() return OctoVuhDoDB.showPower end,
    function(v) OctoVuhDoDB.showPower = v end)

CreateToggleBtn(p2, 12, -138, 200, "Show Mana % Text",
    function() return OctoVuhDoDB.showPowerText end,
    function(v) OctoVuhDoDB.showPowerText = v end)

CreateToggleBtn(p2, 12, -164, 200, "Mana Users Only",
    function() return OctoVuhDoDB.manaOnly end,
    function(v) OctoVuhDoDB.manaOnly = v end)

CreateToggleBtn(p2, 12, -190, 200, "Low HP Emergency Flash",
    function() return OctoVuhDoDB.emergencyFlash end,
    function(v) OctoVuhDoDB.emergencyFlash = v end)

CreateToggleBtn(p2, 12, -216, 200, "Group Headers (G1-G8)",
    function() return OctoVuhDoDB.showGroupHeaders end,
    function(v) OctoVuhDoDB.showGroupHeaders = v end)

CreateToggleBtn(p2, 12, -242, 200, "Hide Blizzard Party",
    function() return OctoVuhDoDB.hideBlizzParty end,
    function(v)
        OctoVuhDoDB.hideBlizzParty = v
        UpdateBlizzardPartyFrames()
    end)

-- Column 2: Highlights & Indicators (Right: 226)
CreateToggleBtn(p2, 226, -8, 200, "Class Colors",
    function() return OctoVuhDoDB.classColors end,
    function(v) OctoVuhDoDB.classColors = v end)

CreateToggleBtn(p2, 226, -34, 200, "Aggro Highlights",
    function() return OctoVuhDoDB.showAggro end,
    function(v) OctoVuhDoDB.showAggro = v end)

CreateToggleBtn(p2, 226, -60, 200, "Debuff Borders",
    function() return OctoVuhDoDB.showDebuffs end,
    function(v) OctoVuhDoDB.showDebuffs = v end)

CreateToggleBtn(p2, 226, -86, 200, "Center Debuff Icon",
    function() return OctoVuhDoDB.showDebuffIcon end,
    function(v) OctoVuhDoDB.showDebuffIcon = v end)

CreateToggleBtn(p2, 226, -112, 200, "Dispel My Class Only",
    function() return OctoVuhDoDB.dispelMyClassOnly end,
    function(v) OctoVuhDoDB.dispelMyClassOnly = v end)

CreateToggleBtn(p2, 226, -138, 200, "HoT Corner Indicators",
    function() return OctoVuhDoDB.showHots end,
    function(v) OctoVuhDoDB.showHots = v end)

CreateToggleBtn(p2, 226, -164, 200, "Target Gold Border",
    function() return OctoVuhDoDB.showTargetBorder end,
    function(v) OctoVuhDoDB.showTargetBorder = v end)

CreateToggleBtn(p2, 226, -190, 200, "Raid Target Icons",
    function() return OctoVuhDoDB.showRaidIcons end,
    function(v) OctoVuhDoDB.showRaidIcons = v end)

CreateToggleBtn(p2, 226, -216, 200, "Range Fading (40yd)",
    function() return OctoVuhDoDB.rangeCheck end,
    function(v) OctoVuhDoDB.rangeCheck = v end)

local lockBtnP2 = CreateFrame("Button", nil, p2, "UIPanelButtonTemplate")
lockBtnP2:SetWidth(200); lockBtnP2:SetHeight(24)
lockBtnP2:SetPoint("TOPLEFT", p2, "TOPLEFT", 120, -276)
local function UpdateLockP2()
    lockBtnP2:SetText(OctoVuhDoDB.locked and "Frame Lock: |cffff4040LOCKED|r" or "Frame Lock: |cff20ff20UNLOCKED (Move)|r")
end
UpdateLockP2()
lockBtnP2:SetScript("OnClick", function()
    OctoVuhDoDB.locked = not OctoVuhDoDB.locked
    UpdateLockP2()
    UpdateLockState()
end)

-- ----------------------------------------------------------------------------
-- TAB 3: Click-Casting Setup
-- ----------------------------------------------------------------------------
local p3 = panels[3]
local function CreateBindingInput(parent, yOfs, label, actionKey)
    local lbl = parent:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 9)
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOfs)
    lbl:SetText(label)

    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, yOfs + 2)
    eb:SetWidth(210); eb:SetHeight(18)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 9)
    eb:SetAutoFocus(false)
    eb:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    eb:SetBackdropColor(0, 0, 0, 0.8)
    eb:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local val = (OctoVuhDoDB.spells and OctoVuhDoDB.spells[actionKey]) or ""
    eb:SetText(val)

    eb:SetScript("OnTextChanged", function()
        if not OctoVuhDoDB.spells then OctoVuhDoDB.spells = {} end
        OctoVuhDoDB.spells[actionKey] = eb:GetText()
    end)
end

local bindLabel = p3:CreateFontString(nil, "OVERLAY")
bindLabel:SetFont("Fonts\\FRIZQT__.TTF", 8)
bindLabel:SetPoint("TOPLEFT", p3, "TOPLEFT", 14, -2)
bindLabel:SetTextColor(0.8, 0.8, 0.8, 1)
bindLabel:SetText("Enter spell name (e.g. Flash Heal, Cleanse, Rejuvenation) or 'target'/'menu':")

CreateBindingInput(p3, -18, "Left Click:", "left")
CreateBindingInput(p3, -38, "Right Click:", "right")
CreateBindingInput(p3, -58, "Middle Click:", "middle")
CreateBindingInput(p3, -78, "Shift + Left:", "shift-left")
CreateBindingInput(p3, -98, "Shift + Right:", "shift-right")
CreateBindingInput(p3, -118, "Ctrl + Left:", "ctrl-left")
CreateBindingInput(p3, -138, "Ctrl + Right:", "ctrl-right")
CreateBindingInput(p3, -158, "Alt + Left:", "alt-left")
CreateBindingInput(p3, -178, "Alt + Right:", "alt-right")
CreateBindingInput(p3, -198, "Mouse Button 4:", "btn4")
CreateBindingInput(p3, -218, "Mouse Button 5:", "btn5")
CreateBindingInput(p3, -238, "Wheel Up:", "wheelup")
CreateBindingInput(p3, -258, "Wheel Down:", "wheeldown")
CreateBindingInput(p3, -278, "Shift + Wheel Up:", "shift-wheelup")
CreateBindingInput(p3, -298, "Shift + Wheel Down:", "shift-wheeldown")

-- ----------------------------------------------------------------------------
-- TAB 4: Themes & Visual Presets
-- ----------------------------------------------------------------------------
local p4 = panels[4]
local thHeader = p4:CreateFontString(nil, "OVERLAY")
thHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
thHeader:SetPoint("TOPLEFT", p4, "TOPLEFT", 14, -8)
thHeader:SetTextColor(1, 0.85, 0.2, 1)
thHeader:SetText("One-Click Aesthetic Presets")

local thDesc = p4:CreateFontString(nil, "OVERLAY")
thDesc:SetFont("Fonts\\FRIZQT__.TTF", 9)
thDesc:SetPoint("TOPLEFT", thHeader, "BOTTOMLEFT", 0, -4)
thDesc:SetTextColor(0.8, 0.8, 0.8, 1)
thDesc:SetText("Instantly configure colors, bar sizes, and layout styles with one click:")

local function ApplyTheme(themeKey)
    if themeKey == "vuhdo_wotlk" then
        OctoVuhDoDB.barWidth = 66
        OctoVuhDoDB.barHeight = 42
        OctoVuhDoDB.powerBarHeight = 3
        OctoVuhDoDB.barGap = 2
        OctoVuhDoDB.nameFontSize = 9
        OctoVuhDoDB.hpFontSize = 8
        OctoVuhDoDB.powerFontSize = 7
        OctoVuhDoDB.hotSize = 8
        OctoVuhDoDB.debuffIconSize = 16
        OctoVuhDoDB.classColors = true
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.manaOnly = true
        OctoVuhDoDB.showDebuffIcon = true
        OctoVuhDoDB.showHots = true
        OctoVuhDoDB.showTargetBorder = true
        OctoVuhDoDB.showAggro = true
        OctoVuhDoDB.barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga"
        OctoVuhDoDB.font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200VuhDo 3.3.5 (Your WotLK Raid UI)|r")
    elseif themeKey == "vuhdo_concave" then
        OctoVuhDoDB.barWidth = 84
        OctoVuhDoDB.barHeight = 36
        OctoVuhDoDB.powerBarHeight = 5
        OctoVuhDoDB.barGap = 4
        OctoVuhDoDB.classColors = true
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar4.tga"
        OctoVuhDoDB.font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200VuhDo Concave Dark|r")
    elseif themeKey == "vuhdo_wood" then
        OctoVuhDoDB.barWidth = 75
        OctoVuhDoDB.barHeight = 36
        OctoVuhDoDB.powerBarHeight = 4
        OctoVuhDoDB.barGap = 3
        OctoVuhDoDB.classColors = true
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar15.tga"
        OctoVuhDoDB.font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200VuhDo Polished Wood (Tank)|r")
    elseif themeKey == "vuhdo_dark" then
        OctoVuhDoDB.barWidth = 84
        OctoVuhDoDB.barHeight = 36
        OctoVuhDoDB.powerBarHeight = 5
        OctoVuhDoDB.barGap = 4
        OctoVuhDoDB.classColors = true
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.showDebuffIcon = true
        OctoVuhDoDB.showHots = true
        OctoVuhDoDB.barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga"
        OctoVuhDoDB.font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200VuhDo Classic Dark|r")
    elseif themeKey == "grid2" then
        OctoVuhDoDB.barWidth = 60
        OctoVuhDoDB.barHeight = 44
        OctoVuhDoDB.powerBarHeight = 3
        OctoVuhDoDB.barGap = 2
        OctoVuhDoDB.nameFontSize = 8
        OctoVuhDoDB.hpFontSize = 7
        OctoVuhDoDB.classColors = true
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.showDebuffIcon = false
        OctoVuhDoDB.barTexture = "Interface\\Tooltips\\UI-Tooltip-Background"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200Grid2 Minimalist Tiles|r")
    elseif themeKey == "healer_pro" then
        OctoVuhDoDB.barWidth = 92
        OctoVuhDoDB.barHeight = 40
        OctoVuhDoDB.powerBarHeight = 6
        OctoVuhDoDB.barGap = 4
        OctoVuhDoDB.nameFontSize = 10
        OctoVuhDoDB.hpFontSize = 9
        OctoVuhDoDB.hotSize = 10
        OctoVuhDoDB.debuffIconSize = 18
        OctoVuhDoDB.showPower = true
        OctoVuhDoDB.showPowerText = true
        OctoVuhDoDB.showDebuffIcon = true
        OctoVuhDoDB.emergencyFlash = true
        OctoVuhDoDB.emergencyThreshold = 35
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200Healer Pro Dashboard|r")
    elseif themeKey == "compact_tank" then
        OctoVuhDoDB.barWidth = 75
        OctoVuhDoDB.barHeight = 28
        OctoVuhDoDB.powerBarHeight = 3
        OctoVuhDoDB.barGap = 3
        OctoVuhDoDB.showPowerText = false
        OctoVuhDoDB.showHots = false
        OctoVuhDoDB.showAggro = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Applied preset: |cffffd200Tank / DPS Compact|r")
    end
    RefreshRoster()
end

local function CreateThemeBtn(label, themeKey, yOfs)
    local btn = CreateFrame("Button", nil, p4, "UIPanelButtonTemplate")
    btn:SetWidth(230); btn:SetHeight(24)
    btn:SetPoint("TOPLEFT", p4, "TOPLEFT", 14, yOfs)
    btn:SetText(label)
    btn:SetScript("OnClick", function() ApplyTheme(themeKey) end)
    return btn
end

CreateThemeBtn("VuhDo 3.3.5 (Raid UI)", "vuhdo_wotlk", -40)
CreateThemeBtn("VuhDo Classic Dark", "vuhdo_dark", -68)
CreateThemeBtn("VuhDo Concave Dark", "vuhdo_concave", -96)
CreateThemeBtn("VuhDo Polished Wood (Tank)", "vuhdo_wood", -124)
CreateThemeBtn("Grid2 Minimalist Tiles", "grid2", -152)
CreateThemeBtn("Healer Pro Dashboard", "healer_pro", -180)
CreateThemeBtn("Tank / DPS Compact", "compact_tank", -208)

-- ----------------------------------------------------------------------------
-- TAB 5: Test Mode & Presets
-- ----------------------------------------------------------------------------
local p5 = panels[5]
local testHeader = p5:CreateFontString(nil, "OVERLAY")
testHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
testHeader:SetPoint("TOPLEFT", p5, "TOPLEFT", 14, -8)
testHeader:SetTextColor(1, 0.85, 0.2, 1)
testHeader:SetText("Simulated Raid Preview & Group Size Positions")

local testExpl = p5:CreateFontString(nil, "OVERLAY")
testExpl:SetFont("Fonts\\FRIZQT__.TTF", 9)
testExpl:SetPoint("TOPLEFT", testHeader, "BOTTOMLEFT", 0, -4)
testExpl:SetTextColor(0.8, 0.8, 0.8, 1)
testExpl:SetText("Test mode lets you preview raid sizes and configure custom screen positions\nfor 5-man, 10-man, 20-man, and 40-man groups independently.")

local testToggleBtn = CreateFrame("Button", nil, p5, "UIPanelButtonTemplate")
testToggleBtn:SetWidth(200); testToggleBtn:SetHeight(24)
testToggleBtn:SetPoint("TOPLEFT", p5, "TOPLEFT", 14, -54)
local function UpdateTestToggle()
    testToggleBtn:SetText(OctoVuhDoDB.testMode and "Test Mode: |cff20ff20ENABLED|r" or "Test Mode: |cffff4040DISABLED|r")
end
UpdateTestToggle()

local presetLabel = p5:CreateFontString(nil, "OVERLAY")
presetLabel:SetFont("Fonts\\FRIZQT__.TTF", 9)
presetLabel:SetPoint("TOPLEFT", testToggleBtn, "BOTTOMLEFT", 0, -12)
presetLabel:SetText("Preview & Position Group Size Presets:")

local sizePresetBtns = {}
local function UpdateSizePresetBtns()
    local curSize = OctoVuhDoDB.testSize or 20
    for sz, btn in pairs(sizePresetBtns) do
        if OctoVuhDoDB.testMode and curSize == sz then
            btn:SetText("|cff20ff20" .. sz .. "-Man|r")
        else
            btn:SetText(sz .. "-Man")
        end
    end
end

local function CreateSizePresetBtn(size, xOfs)
    local btn = CreateFrame("Button", nil, p5, "UIPanelButtonTemplate")
    btn:SetWidth(75); btn:SetHeight(22)
    btn:SetPoint("TOPLEFT", presetLabel, "BOTTOMLEFT", xOfs, -6)
    btn:SetText(size .. "-Man")
    btn:SetScript("OnClick", function()
        OctoVuhDoDB.testSize = size
        OctoVuhDoDB.testMode = true
        UpdateTestToggle()
        UpdateSizePresetBtns()
        ApplyRosterPosition(size, true)
        RefreshRoster()
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Previewing |cffffd200" .. size .. "-Man|r layout & position. Drag header to position.")
    end)
    sizePresetBtns[size] = btn
    return btn
end

CreateSizePresetBtn(5, 0)
CreateSizePresetBtn(10, 80)
CreateSizePresetBtn(20, 160)
CreateSizePresetBtn(40, 240)
UpdateSizePresetBtns()

testToggleBtn:SetScript("OnClick", function()
    OctoVuhDoDB.testMode = not OctoVuhDoDB.testMode
    UpdateTestToggle()
    UpdateSizePresetBtns()
    ApplyRosterPosition(GetCurrentRosterBracket(), true)
    RefreshRoster()
    if OctoVuhDoDB.testMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Test Mode |cff20ff20ON|r (" .. (OctoVuhDoDB.testSize or 20) .. " simulated players).")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Test Mode |cffff4040OFF|r (live roster restored).")
    end
end)

-- Group-Size Position Options Section
local posSectionHeader = p5:CreateFontString(nil, "OVERLAY")
posSectionHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
posSectionHeader:SetPoint("TOPLEFT", presetLabel, "BOTTOMLEFT", 0, -42)
posSectionHeader:SetTextColor(1, 0.85, 0.2, 1)
posSectionHeader:SetText("Distinct Positions per Group Size")

local posSectionExpl = p5:CreateFontString(nil, "OVERLAY")
posSectionExpl:SetFont("Fonts\\FRIZQT__.TTF", 9)
posSectionExpl:SetPoint("TOPLEFT", posSectionHeader, "BOTTOMLEFT", 0, -4)
posSectionExpl:SetTextColor(0.8, 0.8, 0.8, 1)
posSectionExpl:SetText("When enabled, the frame automatically remembers and switches to your saved\nscreen position whenever your party/raid changes size (5, 10, 20, or 40 players).")

local perSizeToggleBtn = CreateFrame("Button", nil, p5, "UIPanelButtonTemplate")
perSizeToggleBtn:SetWidth(280); perSizeToggleBtn:SetHeight(24)
perSizeToggleBtn:SetPoint("TOPLEFT", posSectionExpl, "BOTTOMLEFT", 0, -10)
local function UpdatePerSizeToggle()
    perSizeToggleBtn:SetText(OctoVuhDoDB.perSizePosition and "Per-Size Positions: |cff20ff20ENABLED|r" or "Per-Size Positions: |cffff4040DISABLED (Single Pos)|r")
end
UpdatePerSizeToggle()
perSizeToggleBtn:SetScript("OnClick", function()
    OctoVuhDoDB.perSizePosition = not OctoVuhDoDB.perSizePosition
    UpdatePerSizeToggle()
    ApplyRosterPosition(GetCurrentRosterBracket(), true)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Per-group-size positions " .. (OctoVuhDoDB.perSizePosition and "|cff20ff20ENABLED|r." or "|cffff4040DISABLED|r."))
end)

-- Reset Position Buttons
local resetCurBtn = CreateFrame("Button", nil, p5, "UIPanelButtonTemplate")
resetCurBtn:SetWidth(180); resetCurBtn:SetHeight(22)
resetCurBtn:SetPoint("TOPLEFT", perSizeToggleBtn, "BOTTOMLEFT", 0, -10)
resetCurBtn:SetText("Reset Current Size Position")
resetCurBtn:SetScript("OnClick", function()
    local bracket = GetCurrentRosterBracket()
    if OctoVuhDoDB.positions then
        OctoVuhDoDB.positions[bracket] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
    end
    ApplyRosterPosition(bracket, true)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Position for |cffffd200" .. bracket .. "-Man|r reset to center.")
end)

local resetAllBtn = CreateFrame("Button", nil, p5, "UIPanelButtonTemplate")
resetAllBtn:SetWidth(150); resetAllBtn:SetHeight(22)
resetAllBtn:SetPoint("LEFT", resetCurBtn, "RIGHT", 10, 0)
resetAllBtn:SetText("Reset All Positions")
resetAllBtn:SetScript("OnClick", function()
    OctoVuhDoDB.positions = {
        [5] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [10] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [20] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        [40] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
    }
    OctoVuhDoDB.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
    ApplyRosterPosition(GetCurrentRosterBracket(), true)
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r All group size positions reset to center.")
end)

-- ----------------------------------------------------------------------------
-- 8. Event Handling & Periodic Refresh
-- ----------------------------------------------------------------------------
OVD:RegisterEvent("VARIABLES_LOADED")
OVD:RegisterEvent("PLAYER_ENTERING_WORLD")
OVD:RegisterEvent("PARTY_MEMBERS_CHANGED")
OVD:RegisterEvent("RAID_ROSTER_UPDATE")
OVD:RegisterEvent("PLAYER_TARGET_CHANGED")
OVD:RegisterEvent("UNIT_HEALTH")
OVD:RegisterEvent("UNIT_MAXHEALTH")
OVD:RegisterEvent("UNIT_MANA")
OVD:RegisterEvent("UNIT_MAXMANA")
OVD:RegisterEvent("UNIT_RAGE")
OVD:RegisterEvent("UNIT_ENERGY")
OVD:RegisterEvent("RAID_TARGET_UPDATE")

OVD:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        for k, v in pairs(DEFAULT_DB) do
            if OctoVuhDoDB[k] == nil then
                OctoVuhDoDB[k] = v
            end
        end

        if OctoVuhDoDB.font == nil then
            OctoVuhDoDB.font = "Interface\\AddOns\\OctoVuhDo\\Fonts\\Emblem.ttf"
        end
        if OctoVuhDoDB.barTexture == nil or OctoVuhDoDB.barTexture == "Interface\\TargetingFrame\\UI-StatusBar" then
            OctoVuhDoDB.barTexture = "Interface\\AddOns\\OctoVuhDo\\Images\\bar17.tga"
        end

        if OctoVuhDoDB.positions == nil then
            OctoVuhDoDB.positions = {}
        end
        if OctoVuhDoDB.perSizePosition == nil then
            OctoVuhDoDB.perSizePosition = true
        end
        if OctoVuhDoDB.pos and OctoVuhDoDB.pos.point then
            for _, sz in ipairs({5, 10, 20, 40}) do
                if not OctoVuhDoDB.positions[sz] then
                    OctoVuhDoDB.positions[sz] = {
                        point = OctoVuhDoDB.pos.point,
                        relPoint = OctoVuhDoDB.pos.relPoint or OctoVuhDoDB.pos.point,
                        x = OctoVuhDoDB.pos.x or 0,
                        y = OctoVuhDoDB.pos.y or 0
                    }
                end
            end
        end

        ApplyRosterPosition(GetCurrentRosterBracket(), true)
        if OctoVuhDoDB.scale then
            raidContainer:SetScale(OctoVuhDoDB.scale)
        end
        UpdateLockState()
        UpdateBlizzardPartyFrames()
        RefreshRoster()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not OctoVuhDoDB.testMode then
            for i = 1, 40 do
                local btn = unitButtons[i]
                if btn and btn:IsShown() and btn.unit then
                    if UnitExists("target") and UnitIsUnit(btn.unit, "target") and OctoVuhDoDB.showTargetBorder then
                        btn.targetBorder:Show()
                    else
                        btn.targetBorder:Hide()
                    end
                end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        UpdateBlizzardPartyFrames()
        RefreshRoster()
    elseif not OctoVuhDoDB.testMode then
        local u = arg1
        local found = false
        if u then
            for i = 1, 40 do
                local btn = unitButtons[i]
                if btn and btn:IsShown() and btn.unit and UnitIsUnit(btn.unit, u) then
                    local curHp = UnitHealth(btn.unit)
                    local maxHp = UnitHealthMax(btn.unit)
                    local curPow = UnitMana(btn.unit)
                    local maxPow = UnitManaMax(btn.unit)
                    local pType = UnitPowerType(btn.unit)
                    local _, cls = UnitClass(btn.unit)
                    local inRange = CheckUnitRange(btn.unit)
                    local debuffType, debuffIcon = GetUnitDebuffInfo(btn.unit)
                    local raidIcon = GetRaidTargetIndex(btn.unit)
                    local hasRenew, hasRejuv = false, false
                    for b = 1, 16 do
                        local t = UnitBuff(btn.unit, b)
                        if not t then break end
                        if string.find(t, "Spell_Holy_Renew") then hasRenew = true end
                        if string.find(t, "Spell_Nature_Rejuvenation") then hasRejuv = true end
                    end
                    UpdateUnitVisual(btn, {
                        name = UnitName(btn.unit),
                        class = cls,
                        curHp = curHp,
                        maxHp = maxHp,
                        curPower = curPow,
                        maxPower = maxPow,
                        powerType = pType,
                        inRange = inRange,
                        hasAggro = false,
                        debuffType = debuffType,
                        debuffIcon = debuffIcon,
                        raidIcon = raidIcon,
                        hotTL = hasRenew,
                        hotTR = hasRejuv,
                    })
                    found = true
                    break
                end
            end
        end
        if not found and not u then
            RefreshRoster()
        end
    end
end)

local timer = 0
raidContainer:SetScript("OnUpdate", function()
    timer = timer + (arg1 or 0.05)
    if timer >= 0.25 then
        timer = 0
        if not OctoVuhDoDB.testMode and raidContainer:IsShown() then
            RefreshRoster()
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 9. Minimap Button
-- ----------------------------------------------------------------------------
local mm = CreateFrame("Button", "OctoVuhDoMinimapBtn", Minimap)
mm:SetWidth(32); mm:SetHeight(32)
mm:SetFrameStrata("MEDIUM"); mm:SetFrameLevel(9)

local mmIcon = mm:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\Spell_Holy_Heal02")
mmIcon:SetWidth(20); mmIcon:SetHeight(20)
mmIcon:SetPoint("CENTER", mm, "CENTER", 0, 0)

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetWidth(52); mmBorder:SetHeight(52)
mmBorder:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)

local mmHighlight = mm:CreateTexture(nil, "HIGHLIGHT")
mmHighlight:SetWidth(32); mmHighlight:SetHeight(32)
mmHighlight:SetPoint("CENTER", mm, "CENTER", 0, 0)
mmHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mmHighlight:SetBlendMode("ADD")

local function UpdateMMPos(angle)
    local rad = 80
    local x = math.cos(angle) * rad
    local y = math.sin(angle) * rad
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local curAngle = (OctoVuhDoDB and OctoVuhDoDB.minimapAngle) or 1.2
UpdateMMPos(curAngle)

mm:RegisterForDrag("LeftButton", "RightButton")
mm:SetScript("OnDragStart", function() this.isDragging = true end)
mm:SetScript("OnDragStop", function() this.isDragging = false end)
mm:SetScript("OnUpdate", function()
    if this.isDragging then
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.atan2(cy - my, cx - mx)
        UpdateMMPos(angle)
        if OctoVuhDoDB then OctoVuhDoDB.minimapAngle = angle end
    end
end)

mm:SetScript("OnClick", function()
    if IsShiftKeyDown() then
        OctoVuhDoDB.locked = not OctoVuhDoDB.locked
        UpdateLockState()
        local state = OctoVuhDoDB.locked and "|cffff4040Locked|r" or "|cff20ff20Unlocked (Draggable)|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Frames " .. state)
    else
        if opt:IsShown() then opt:Hide() else opt:Show() end
    end
end)

mm:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff69ccf0OctoVuhDo|r (Raid & Party UI)")
    GameTooltip:AddLine("|cffffffffClick:|r Open Settings Dialog", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cffffffffShift + Click:|r Lock / Unlock dragging", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cffffffffDrag Button:|r Move around Minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ----------------------------------------------------------------------------
-- 10. Slash Commands: /ovd, /vd, /vuhdo
-- ----------------------------------------------------------------------------
SLASH_OCTOVUHDO1 = "/ovd"
SLASH_OCTOVUHDO2 = "/vd"
SLASH_OCTOVUHDO3 = "/vuhdo"
SlashCmdList["OCTOVUHDO"] = function(msg)
    local raw = msg or ""
    local cmd = string.lower(raw)
    if cmd == "test" then
        OctoVuhDoDB.testMode = not OctoVuhDoDB.testMode
        ApplyRosterPosition(GetCurrentRosterBracket(), true)
        RefreshRoster()
        local state = OctoVuhDoDB.testMode and "|cff20ff20ON|r" or "|cffff4040OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Test Mode is now " .. state)
    elseif string.sub(cmd, 1, 4) == "test" then
        local sz = tonumber(string.sub(cmd, 6))
        if sz and (sz == 5 or sz == 10 or sz == 20 or sz == 40) then
            OctoVuhDoDB.testSize = sz
            OctoVuhDoDB.testMode = true
            ApplyRosterPosition(sz, true)
            RefreshRoster()
            DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Previewing |cffffd200" .. sz .. "-Man|r layout & position. Drag header to position.")
        end
    elseif cmd == "lock" or cmd == "unlock" then
        OctoVuhDoDB.locked = not OctoVuhDoDB.locked
        UpdateLockState()
        local state = OctoVuhDoDB.locked and "|cffff4040LOCKED|r" or "|cff20ff20UNLOCKED|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Frames " .. state)
    elseif cmd == "resetpos" then
        local bracket = GetCurrentRosterBracket()
        if OctoVuhDoDB.positions then
            OctoVuhDoDB.positions[bracket] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
        end
        ApplyRosterPosition(bracket, true)
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r Position for |cffffd200" .. bracket .. "-Man|r reset to center.")
    elseif cmd == "resetpos all" or cmd == "reset" then
        raidContainer:ClearAllPoints()
        raidContainer:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        OctoVuhDoDB.pos = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
        OctoVuhDoDB.positions = {
            [5] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
            [10] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
            [20] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
            [40] = { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 },
        }
        OctoVuhDoDB.scale = 1.0
        raidContainer:SetScale(1.0)
        ApplyRosterPosition(GetCurrentRosterBracket(), true)
        RefreshRoster()
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[OctoVuhDo]|r All frame positions reset to center.")
    else
        if opt:IsShown() then opt:Hide() else opt:Show() end
    end
end
