--[[
    OctoCTC.lua
    Live Combat Table Coverage (CTC) & Uncrushable HUD for Protection Warriors.
    Calculates Miss + Dodge + Parry + Block in real-time, tracking Shield Block buffs,
    Defense rating, and boss level differentials.

    Author: Antigravity
    Version: 1.0
]]

local _G = _G or getfenv(0)
OctoCTCDB = OctoCTCDB or {}

local Frame = CreateFrame("Frame", "OctoCTCFrame", UIParent)
OctoCTC = Frame

-- ----------------------------------------------------------------------------
-- Spec & Equipment Checks
-- ----------------------------------------------------------------------------
local function IsWarrior()
    local _, englishClass = UnitClass("player")
    return englishClass == "WARRIOR"
end

local function IsProtSpec()
    local _, _, arms = GetTalentTabInfo(1)
    local _, _, fury = GetTalentTabInfo(2)
    local _, _, prot = GetTalentTabInfo(3)
    arms = arms or 0
    fury = fury or 0
    prot = prot or 0
    return (prot >= arms and prot >= fury and prot > 0)
end

local function HasShieldEquipped()
    local link = GetInventoryItemLink("player", 17)
    if not link then return false end
    -- Check if item is a shield
    local _, _, id = string.find(link, "item:(%d+)")
    if id then
        local _, _, _, _, _, itemType = GetItemInfo(id)
        if itemType == "Shields" or itemType == "Shield" then return true end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Live Combat Table Calculations
-- ----------------------------------------------------------------------------
local function CalculateCTC()
    local playerLevel = UnitLevel("player") or 60
    local targetLevel = playerLevel + 3
    local isBoss = true

    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local tLvl = UnitLevel("target")
        if tLvl and tLvl > 0 then
            targetLevel = tLvl
            isBoss = (targetLevel >= playerLevel + 3)
        else
            -- Skull or world boss (-1 level)
            targetLevel = playerLevel + 3
            isBoss = true
        end
    end

    local baseDef, armorDef = UnitDefense("player")
    baseDef = baseDef or (playerLevel * 5)
    armorDef = armorDef or 0
    local totalDef = baseDef + armorDef

    -- Defense vs target weapon skill
    local targetSkill = targetLevel * 5
    local defDelta = totalDef - targetSkill

    -- Boss miss chance: Base 5.0% + 0.04% per point of Defense difference
    local miss = 5.0 + (defDelta * 0.04)
    if miss < 0 then miss = 0 end

    local dodge = GetDodgeChance() or 0
    local parry = GetParryChance() or 0
    local block = GetBlockChance() or 0

    -- Combat Table Coverage (Single-roll table)
    local ctc = miss + dodge + parry + block

    -- Required coverage against target:
    -- Level 63 boss (+3) requires 102.4% coverage to completely eliminate crushing blows
    local targetCTC = 100.0
    if targetLevel > playerLevel then
        targetCTC = 100.0 + ((targetLevel - playerLevel) * 0.8)
    end

    -- Check if Shield Block buff is currently active on player (Ability_Defend texture in 1.12)
    local shieldBlockActive = false
    for i = 1, 32 do
        local buffTex = UnitBuff("player", i)
        if not buffTex then break end
        local lowTex = string.lower(buffTex)
        if string.find(lowTex, "ability_defend", 1, true) or string.find(lowTex, "shieldblock", 1, true) then
            shieldBlockActive = true
            break
        end
    end

    return ctc, targetCTC, miss, dodge, parry, block, totalDef, targetLevel, isBoss, shieldBlockActive
end

-- ----------------------------------------------------------------------------
-- UI Frame Setup
-- ----------------------------------------------------------------------------
local function BuildCTCUI()
    if Frame.isBuilt then return end

    Frame:SetWidth(184)
    Frame:SetHeight(38)
    Frame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    Frame:SetFrameStrata("MEDIUM")
    Frame:SetClampedToScreen(true)
    Frame:EnableMouse(true)
    Frame:SetMovable(true)

    -- Sleek Translucent Glass Backdrop
    Frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    Frame:SetBackdropColor(0.04, 0.05, 0.08, 0.85)
    Frame:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.8)

    -- Small Shield Icon perched on top of the box
    local iconFrame = CreateFrame("Frame", "OctoCTCShieldIcon", Frame)
    iconFrame:SetWidth(20)
    iconFrame:SetHeight(20)
    iconFrame:SetPoint("BOTTOM", Frame, "TOP", 0, 2)
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    iconFrame:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.9)
    iconFrame:EnableMouse(true)

    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints(iconFrame)
    iconBg:SetTexture(0.04, 0.05, 0.08, 0.95)

    local shieldIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    shieldIcon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    shieldIcon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    shieldIcon:SetTexture("Interface\\Icons\\Ability_Defend")
    shieldIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Frame.shieldIcon = shieldIcon
    Frame.iconFrame = iconFrame

    -- Main CTC Status Text (Properly centered in the top half of the box)
    local mainText = Frame:CreateFontString(nil, "OVERLAY")
    mainText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    mainText:SetPoint("TOP", Frame, "TOP", 0, -6)
    mainText:SetJustifyH("CENTER")
    mainText:SetText("CTC: 102.4%")
    Frame.mainText = mainText

    -- Subtext: Breakdown (Properly centered in the bottom half of the box)
    local subText = Frame:CreateFontString(nil, "OVERLAY")
    subText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    subText:SetPoint("BOTTOM", Frame, "BOTTOM", 0, 6)
    subText:SetJustifyH("CENTER")
    subText:SetTextColor(0.8, 0.8, 0.8, 1)
    subText:SetText("M:5% D:10% P:7% B:8% Def:340")
    Frame.subText = subText

    -- Dragging & Position Saving from Frame
    Frame:RegisterForDrag("LeftButton")
    Frame:SetScript("OnDragStart", function()
        if not (OctoCTCDB and OctoCTCDB.locked) then
            this:StartMoving()
        end
    end)
    Frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relPoint, x, y = this:GetPoint()
        OctoCTCDB = OctoCTCDB or {}
        OctoCTCDB.point = point
        OctoCTCDB.relPoint = relPoint
        OctoCTCDB.x = x
        OctoCTCDB.y = y
    end)

    -- Also allow Dragging from the Shield Icon
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", function()
        if not (OctoCTCDB and OctoCTCDB.locked) then
            Frame:StartMoving()
        end
    end)
    iconFrame:SetScript("OnDragStop", function()
        Frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = Frame:GetPoint()
        OctoCTCDB = OctoCTCDB or {}
        OctoCTCDB.point = point
        OctoCTCDB.relPoint = relPoint
        OctoCTCDB.x = x
        OctoCTCDB.y = y
    end)
    iconFrame:SetScript("OnEnter", function()
        local onEnter = Frame:GetScript("OnEnter")
        if onEnter then onEnter() end
    end)
    iconFrame:SetScript("OnLeave", function()
        local onLeave = Frame:GetScript("OnLeave")
        if onLeave then onLeave() end
    end)

    -- Tooltip on Hover
    Frame:SetScript("OnEnter", function()
        local ctc, targetCTC, miss, dodge, parry, block, totalDef, tLvl, isBoss, sbActive = CalculateCTC()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("|cFF00FFCCOctoCTC|r - Combat Table Coverage", 1, 1, 1)
        GameTooltip:AddLine(" ")

        local statusColor = (ctc >= targetCTC) and "|cff20ff20" or "|cffffd100"
        GameTooltip:AddDoubleLine("Total Coverage:", string.format("%s%.2f%% / %.1f%%|r", statusColor, ctc, targetCTC))
        GameTooltip:AddDoubleLine("Crush Status:", (ctc >= targetCTC) and "|cff20ff20UNCRUSHABLE|r" or string.format("|cffff4040Vulnerable (Needs +%.2f%%)|r", targetCTC - ctc))
        GameTooltip:AddDoubleLine("Target Checked:", string.format("Level %d %s", tLvl, isBoss and "(Boss)" or ""))
        GameTooltip:AddLine(" ")

        GameTooltip:AddLine("|cFF00D1FFStat Breakdown:|r")
        GameTooltip:AddDoubleLine("• Miss Chance:", string.format("%.2f%%", miss), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• Dodge Chance:", string.format("%.2f%%", dodge), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• Parry Chance:", string.format("%.2f%%", parry), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• Block Chance:", string.format("%.2f%% %s", block, sbActive and "|cff20ff20(+75% Active)|r" or ""), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("• Total Defense:", string.format("%d / 440 (Crit Cap)", totalDef), 1, 1, 1, 1, 1, 1)

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF888888<Left-Click Drag to Move>|r")
        GameTooltip:AddLine("|cFF888888</ctc lock to Lock / Unlock Position>|r")
        GameTooltip:Show()
    end)
    Frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Restore saved position and scale
    if OctoCTCDB then
        if OctoCTCDB.point and OctoCTCDB.x and OctoCTCDB.y then
            Frame:ClearAllPoints()
            Frame:SetPoint(OctoCTCDB.point, UIParent, OctoCTCDB.relPoint or "CENTER", OctoCTCDB.x, OctoCTCDB.y)
        end
        if OctoCTCDB.scale then
            Frame:SetScale(OctoCTCDB.scale)
        end
    end

    Frame.isBuilt = true
end

-- ----------------------------------------------------------------------------
-- Update Display
-- ----------------------------------------------------------------------------
local function UpdateCTCDisplay()
    if not Frame.isBuilt then return end
    if not IsWarrior() then
        Frame:Hide()
        return
    end

    -- Check if we should show the display
    local showFrame = true
    if OctoCTCDB and OctoCTCDB.alwaysShow then
        showFrame = true
    else
        -- Only show if Protection Spec OR Shield is currently equipped
        showFrame = IsProtSpec() or HasShieldEquipped()
    end

    if not showFrame then
        Frame:Hide()
        return
    end

    Frame:Show()

    local ctc, targetCTC, miss, dodge, parry, block, totalDef, tLvl, isBoss, sbActive = CalculateCTC()

    if ctc >= targetCTC then
        -- UNCRUSHABLE! Glowing green
        Frame.mainText:SetText(string.format("|cff20ff20CTC: %.1f%%|r |cff00ffcc[UNCRUSH]|r", ctc))
        Frame:SetBackdropBorderColor(0.1, 0.9, 0.2, 0.9)
        if Frame.iconFrame then
            Frame.iconFrame:SetBackdropBorderColor(0.1, 0.9, 0.2, 1.0)
        end
        Frame.shieldIcon:SetVertexColor(1, 1, 1, 1)
    else
        -- Vulnerable to crushing blows
        local needed = targetCTC - ctc
        Frame.mainText:SetText(string.format("|cffffd100CTC: %.1f%%|r |cffff6060(-%.1f%%)|r", ctc, needed))
        Frame:SetBackdropBorderColor(0.25, 0.35, 0.45, 0.85)
        if Frame.iconFrame then
            Frame.iconFrame:SetBackdropBorderColor(0.25, 0.35, 0.45, 0.9)
        end
        Frame.shieldIcon:SetVertexColor(0.85, 0.85, 0.85, 0.9)
    end

    -- If Shield Block active (+75% block), highlight shield frame in golden yellow!
    if sbActive and Frame.iconFrame then
        Frame.iconFrame:SetBackdropBorderColor(1.0, 0.85, 0.2, 1.0)
        Frame.shieldIcon:SetVertexColor(1, 1, 1, 1)
    end

    -- Sub-line breakdown
    Frame.subText:SetText(string.format("M:%.1f D:%.1f P:%.1f B:%.1f |cffffffffDef:%d|r", miss, dodge, parry, block, totalDef))
end

-- ----------------------------------------------------------------------------
-- Event Listener & Throttle
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_STATS")
eventFrame:RegisterEvent("UNIT_DEFENSE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")

local elapsed = 0
eventFrame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= 0.15 then
        elapsed = 0
        UpdateCTCDisplay()
    end
end)

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        BuildCTCUI()
    end
    UpdateCTCDisplay()
end)

-- ----------------------------------------------------------------------------
-- Slash Commands (/ctc)
-- ----------------------------------------------------------------------------
SLASH_OCTOCTC1 = "/ctc"
SlashCmdList["OCTOCTC"] = function(msg)
    OctoCTCDB = OctoCTCDB or {}
    local cmd = string.lower(msg or "")

    if cmd == "lock" then
        OctoCTCDB.locked = not OctoCTCDB.locked
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCCOctoCTC:|r Display is now %s.", OctoCTCDB.locked and "|cffff4040LOCKED|r" or "|cff20ff20UNLOCKED (Movable)|r"))
    elseif cmd == "reset" then
        Frame:ClearAllPoints()
        Frame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
        Frame:SetScale(1.0)
        OctoCTCDB.point = "CENTER"
        OctoCTCDB.relPoint = "CENTER"
        OctoCTCDB.x = 0
        OctoCTCDB.y = -170
        OctoCTCDB.scale = 1.0
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCCOctoCTC:|r Position and scale reset to center.")
    elseif string.find(cmd, "^scale%s*(%d*%.?%d*)") then
        local _, _, scaleStr = string.find(cmd, "^scale%s*(%d*%.?%d*)")
        local newScale = tonumber(scaleStr)
        if newScale and newScale >= 0.5 and newScale <= 2.0 then
            OctoCTCDB.scale = newScale
            Frame:SetScale(newScale)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCCOctoCTC:|r Scale set to %.2f.", newScale))
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCCOctoCTC:|r Usage: /ctc scale <0.5 - 2.0>")
        end
    elseif cmd == "always" then
        OctoCTCDB.alwaysShow = not OctoCTCDB.alwaysShow
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCCOctoCTC:|r Always Show mode: %s.", OctoCTCDB.alwaysShow and "|cff20ff20ENABLED|r" or "|cffff4040DISABLED (Prot/Shield only)|r"))
        UpdateCTCDisplay()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCC=== OctoCTC Commands ===|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100/ctc lock|r - Toggle lock / unlock frame dragging")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100/ctc reset|r - Reset position to center screen")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100/ctc scale <0.5-2.0>|r - Set scale size")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100/ctc always|r - Toggle showing always vs Prot/Shield only")
    end
end
