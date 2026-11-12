--[[
    HunterSwingTimer.lua
    Vanilla 1.12 Hunter Auto Shot Swing Timer with Aim/Cast Bar & Safe Weave Window.
    Includes dedicated crystal-clear castbar for Steady Shot and Aimed Shot.
    Recreates the TBC "Feels Like Cheating" Auto Shot clipping visual for Vanilla / Turtle WoW.
]]

local _G = _G or getfenv(0)

-- Default Configuration
HunterSwingTimer_Config = HunterSwingTimer_Config or {
    x = 0,
    y = -140,
    point = "CENTER",
    relPoint = "CENTER",
    scale = 1.0,
    showMelee = true,
    locked = true,
}

local AIM_DURATION = 0.5 -- 0.5s draw/aim time for Auto Shot

-- Runtime State
local HST = {
    isHunting = false,          -- Player is Hunter
    isAutoRepeat = false,       -- Auto Shot toggled on
    rangedSpeed = 2.8,          -- Live ranged weapon speed
    meleeSpeed = 2.0,           -- Live melee weapon speed

    -- Ranged Auto Shot Cycle
    rangedState = "IDLE",       -- "IDLE", "AIMING", "RELOADING"
    rangedStart = 0,            -- GetTime() when current cycle began
    rangedDuration = 0,         -- Total duration of current cycle
    aimStart = 0,               -- GetTime() when Auto Shot aim began
    aimDuration = AIM_DURATION, -- 0.5s

    -- Active Cast (Steady Shot, Aimed Shot, etc.)
    activeCast = nil,           -- Spell name
    activeCastStart = 0,        -- Start time
    activeCastDuration = 0,     -- Cast duration in seconds

    -- Melee Timer
    meleeStart = 0,
    meleeDuration = 0,

    -- Test Mode
    isTest = false,
}

-- ----------------------------------------------------------------------------
-- UI Construction
-- ----------------------------------------------------------------------------
local backdrop = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

-- Main Container Frame
local mainFrame = CreateFrame("Frame", "HunterSwingTimerFrame", UIParent)
mainFrame:SetWidth(230)
mainFrame:SetHeight(44)
mainFrame:SetPoint(HunterSwingTimer_Config.point or "CENTER", UIParent, HunterSwingTimer_Config.relPoint or "CENTER", HunterSwingTimer_Config.x or 0, HunterSwingTimer_Config.y or -140)
mainFrame:SetClampedToScreen(true)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(false)
mainFrame:SetBackdrop(backdrop)
mainFrame:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
mainFrame:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.95)
mainFrame:Hide()

-- Drag Handle (visible when unlocked)
local dragHandle = CreateFrame("Button", "HunterSwingTimerHandle", mainFrame)
dragHandle:SetWidth(230)
dragHandle:SetHeight(18)
dragHandle:SetPoint("BOTTOM", mainFrame, "TOP", 0, 2)
dragHandle:SetBackdrop(backdrop)
dragHandle:SetBackdropColor(0.1, 0.5, 0.85, 0.9)
dragHandle:SetBackdropBorderColor(0.3, 0.9, 1.0, 1)
dragHandle:EnableMouse(true)
dragHandle:RegisterForDrag("LeftButton")
dragHandle:Hide()

local dragText = dragHandle:CreateFontString(nil, "OVERLAY")
dragText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
dragText:SetPoint("CENTER", dragHandle, "CENTER", 0, 0)
dragText:SetText("HUNTER SWING TIMER (DRAG)")
dragText:SetTextColor(1, 1, 1, 1)

dragHandle:SetScript("OnDragStart", function()
    mainFrame:StartMoving()
end)

dragHandle:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    HunterSwingTimer_Config.point = point
    HunterSwingTimer_Config.relPoint = relPoint
    HunterSwingTimer_Config.x = x
    HunterSwingTimer_Config.y = y
end)

-- 1. Cast / Aim Bar (Top Bar - Steady Shot / Aimed Shot / Auto Shot Draw)
local castBar = CreateFrame("StatusBar", "HSTCastBar", mainFrame)
castBar:SetWidth(224)
castBar:SetHeight(17)
castBar:SetPoint("TOP", mainFrame, "TOP", 0, -3)
castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
castBar:SetStatusBarColor(1.0, 0.82, 0.1, 0.95) -- Bright Gold default for Steady Shot
castBar:SetMinMaxValues(0, 1)
castBar:SetValue(0)

local castBarBg = castBar:CreateTexture(nil, "BACKGROUND")
castBarBg:SetAllPoints(castBar)
castBarBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
castBarBg:SetVertexColor(0.12, 0.1, 0.02, 0.7)

local castTextLeft = castBar:CreateFontString(nil, "OVERLAY")
castTextLeft:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
castTextLeft:SetPoint("LEFT", castBar, "LEFT", 5, 0)
castTextLeft:SetText("STEADY SHOT")
castTextLeft:SetTextColor(1, 1, 1, 1)

local castTextRight = castBar:CreateFontString(nil, "OVERLAY")
castTextRight:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
castTextRight:SetPoint("RIGHT", castBar, "RIGHT", -5, 0)
castTextRight:SetText("1.5s")
castTextRight:SetTextColor(1, 1, 0.8, 1)

-- 2. Reload / Swing & Safe Weave Bar (Bottom Bar)
local reloadBar = CreateFrame("StatusBar", "HSTReloadBar", mainFrame)
reloadBar:SetWidth(224)
reloadBar:SetHeight(15)
reloadBar:SetPoint("TOP", castBar, "BOTTOM", 0, -3)
reloadBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
reloadBar:SetStatusBarColor(0.15, 0.75, 1.0, 0.95) -- Cyan / Safe
reloadBar:SetMinMaxValues(0, 1)
reloadBar:SetValue(0)

local reloadBarBg = reloadBar:CreateTexture(nil, "BACKGROUND")
reloadBarBg:SetAllPoints(reloadBar)
reloadBarBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
reloadBarBg:SetVertexColor(0.04, 0.12, 0.20, 0.7)

local reloadTextLeft = reloadBar:CreateFontString(nil, "OVERLAY")
reloadTextLeft:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
reloadTextLeft:SetPoint("LEFT", reloadBar, "LEFT", 5, 0)
reloadTextLeft:SetText("AUTO SHOT")
reloadTextLeft:SetTextColor(1, 1, 1, 1)

local reloadTextRight = reloadBar:CreateFontString(nil, "OVERLAY")
reloadTextRight:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
reloadTextRight:SetPoint("RIGHT", reloadBar, "RIGHT", -5, 0)
reloadTextRight:SetText("2.8s")
reloadTextRight:SetTextColor(1, 1, 1, 1)

-- 3. Melee Swing Bar (Underneath)
local meleeBar = CreateFrame("StatusBar", "HSTMeleeBar", mainFrame)
meleeBar:SetWidth(224)
meleeBar:SetHeight(6)
meleeBar:SetPoint("TOP", reloadBar, "BOTTOM", 0, -2)
meleeBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
meleeBar:SetStatusBarColor(0.9, 0.25, 0.25, 0.85) -- Red
meleeBar:SetMinMaxValues(0, 1)
meleeBar:SetValue(0)
meleeBar:Hide()

local meleeBarBg = meleeBar:CreateTexture(nil, "BACKGROUND")
meleeBarBg:SetAllPoints(meleeBar)
meleeBarBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
meleeBarBg:SetVertexColor(0.2, 0.05, 0.05, 0.5)

-- ----------------------------------------------------------------------------
-- Core Logic & Timers
-- ----------------------------------------------------------------------------
local function UpdateSpeeds()
    local speed = UnitRangedDamage("player")
    if speed and speed > 0 then
        HST.rangedSpeed = speed
    end
    local mSpeed = UnitAttackSpeed("player")
    if mSpeed and mSpeed > 0 then
        HST.meleeSpeed = mSpeed
    end
end

local function StartAiming()
    UpdateSpeeds()
    HST.rangedState = "AIMING"
    HST.aimStart = GetTime()
    HST.aimDuration = AIM_DURATION

    -- If no hard cast (Steady/Aimed) is active, show the 0.5s aim on castBar
    if not HST.activeCast then
        castBar:SetStatusBarColor(1.0, 0.55, 0.05, 0.95) -- Bright Flame Orange
        castTextLeft:SetText("|cffff9900AIMING (STAND STILL)|r")
        castTextRight:SetText("0.5s")
        castBar:SetValue(0)
    end

    reloadBar:SetStatusBarColor(1.0, 0.25, 0.2, 0.95) -- Danger Red
    reloadTextLeft:SetText("|cffff4444CLIP ZONE|r")

    mainFrame:Show()
end

local function StartReloading(castSpellName)
    UpdateSpeeds()
    HST.rangedState = "RELOADING"
    HST.rangedStart = GetTime()
    HST.rangedDuration = HST.rangedSpeed

    -- If no active hard cast, reset cast bar
    if not HST.activeCast then
        castBar:SetValue(1)
        castBar:SetStatusBarColor(0.25, 0.25, 0.3, 0.5)
        castTextLeft:SetText("|cffaaaaaaREADY|r")
        castTextRight:SetText("")
    end

    -- Reload bar starts in Safe Weave mode
    reloadBar:SetStatusBarColor(0.15, 0.8, 1.0, 0.95) -- Cyan (Safe to move / weave)
    reloadTextLeft:SetText(castSpellName or "|cff33ddffSAFE TO MOVE|r")

    mainFrame:Show()
end

local function StartMeleeSwing()
    UpdateSpeeds()
    HST.meleeStart = GetTime()
    HST.meleeDuration = HST.meleeSpeed
    if HunterSwingTimer_Config.showMelee then
        meleeBar:Show()
    end
end

-- ----------------------------------------------------------------------------
-- OnUpdate Frame Loop
-- ----------------------------------------------------------------------------
mainFrame:SetScript("OnUpdate", function()
    local now = GetTime()

    -- 1. Active Cast Bar (Steady Shot / Aimed Shot / Auto Shot Aim)
    if HST.activeCast then
        local elapsed = now - HST.activeCastStart
        local remaining = HST.activeCastDuration - elapsed
        local progress = elapsed / HST.activeCastDuration

        if progress >= 1.0 then
            castBar:SetValue(1.0)
            castTextRight:SetText("0.0s")
            HST.activeCast = nil
        else
            castBar:SetValue(progress)
            castTextRight:SetText(string.format("%.1fs / %.1fs", (remaining > 0 and remaining or 0), HST.activeCastDuration))
        end

    elseif HST.rangedState == "AIMING" then
        local elapsed = now - HST.aimStart
        local remaining = HST.aimDuration - elapsed
        local progress = elapsed / HST.aimDuration

        if progress >= 1.0 then
            castBar:SetValue(1.0)
            castTextRight:SetText("0.0s")
            StartReloading("Auto Shot")
        else
            castBar:SetValue(progress)
            castTextRight:SetText(string.format("%.1fs", remaining > 0 and remaining or 0))
            reloadBar:SetValue(1.0)
            reloadTextRight:SetText(string.format("%.1fs", remaining > 0 and remaining or 0))
        end
    end

    -- 2. Reload / Swing & Safe Weave Bar
    if HST.rangedState == "RELOADING" then
        local elapsed = now - HST.rangedStart
        local remaining = HST.rangedDuration - elapsed
        local progress = elapsed / HST.rangedDuration

        if progress >= 1.0 then
            if HST.isAutoRepeat or HST.isTest then
                StartAiming()
            else
                HST.rangedState = "IDLE"
                reloadBar:SetValue(0)
                reloadTextLeft:SetText("AUTO SHOT")
                reloadTextRight:SetText("READY")
            end
        else
            reloadBar:SetValue(1.0 - progress)
            reloadTextRight:SetText(string.format("%.1fs", remaining > 0 and remaining or 0))

            -- Kippzo Weave / Clip Indicator:
            if remaining <= AIM_DURATION then
                -- Within final 0.5s: Danger Zone (Auto Shot aim is about to draw!)
                reloadBar:SetStatusBarColor(1.0, 0.35, 0.15, 0.95) -- Orange / Red Warning
                reloadTextLeft:SetText("|cffff4422CLIP DANGER (STOP)|r")
            else
                -- Safe window to cast Steady Shot, Multi-Shot, or kite
                reloadBar:SetStatusBarColor(0.15, 0.8, 1.0, 0.95) -- Cyan Safe
                if not HST.activeCast then
                    reloadTextLeft:SetText("|cff33ddffSAFE WEAVE WINDOW|r")
                end
            end
        end
    end

    -- 3. Melee Swing Bar
    if HunterSwingTimer_Config.showMelee and HST.meleeDuration > 0 then
        local mElapsed = now - HST.meleeStart
        local mRemaining = HST.meleeDuration - mElapsed
        local mProgress = mElapsed / HST.meleeDuration

        if mProgress >= 1.0 then
            meleeBar:SetValue(0)
            if now - HST.meleeStart > 6.0 then
                meleeBar:Hide()
                HST.meleeDuration = 0
            end
        else
            meleeBar:SetValue(1.0 - mProgress)
        end
    end

    -- 4. Auto-hide when idle and out of combat
    if not HST.isTest and HST.rangedState == "IDLE" and not HST.activeCast and not HST.isAutoRepeat and not UnitAffectingCombat("player") then
        if now - HST.rangedStart > 4.0 then
            mainFrame:Hide()
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Combat Log & Event Handling
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
eventFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
eventFrame:RegisterEvent("SPELLCAST_START")
eventFrame:RegisterEvent("SPELLCAST_STOP")
eventFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("SPELLCAST_FAILED")
eventFrame:RegisterEvent("SPELLCAST_DELAYED")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        local _, class = UnitClass("player")
        HST.isHunting = (class == "HUNTER")
        UpdateSpeeds()
        if HunterSwingTimer_Config.locked then
            dragHandle:Hide()
            mainFrame:EnableMouse(false)
        else
            dragHandle:Show()
            mainFrame:EnableMouse(true)
            mainFrame:Show()
        end

    elseif not HST.isHunting then
        return

    elseif event == "START_AUTOREPEAT_SPELL" then
        HST.isAutoRepeat = true
        if HST.rangedState == "IDLE" and not HST.activeCast then
            StartAiming()
        end

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        HST.isAutoRepeat = false

    elseif event == "SPELLCAST_START" then
        -- arg1 = Spell Name (e.g., "Steady Shot", "Aimed Shot")
        -- arg2 = Cast Duration in milliseconds (e.g. 1500 for 1.5s)
        local spell = arg1 or ""
        local duration = (arg2 and arg2 > 0) and (arg2 / 1000.0) or 1.5

        HST.activeCast = spell
        HST.activeCastStart = GetTime()
        HST.activeCastDuration = duration

        mainFrame:Show()

        if string.find(spell, "Steady") then
            -- Crystal-clear Bold Golden Yellow for Steady Shot
            castBar:SetStatusBarColor(1.0, 0.85, 0.05, 0.98)
            castTextLeft:SetText("|cffffff00STEADY SHOT|r")
            castTextRight:SetText(string.format("%.1fs / %.1fs", duration, duration))
        elseif string.find(spell, "Aimed") then
            -- Arcane Purple for Aimed Shot
            castBar:SetStatusBarColor(0.85, 0.45, 1.0, 0.98)
            castTextLeft:SetText("|cffdd88ffAIMED SHOT|r")
            castTextRight:SetText(string.format("%.1fs / %.1fs", duration, duration))
        else
            -- General hunter cast (Scare Beast, Revive Pet, etc.)
            castBar:SetStatusBarColor(0.25, 0.75, 1.0, 0.98)
            castTextLeft:SetText("|cff55ccff" .. string.upper(spell) .. "|r")
            castTextRight:SetText(string.format("%.1fs / %.1fs", duration, duration))
        end

    elseif event == "SPELLCAST_DELAYED" then
        -- Pushback from taking damage
        if HST.activeCast and arg1 and arg1 > 0 then
            HST.activeCastDuration = HST.activeCastDuration + (arg1 / 1000.0)
        end

    elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_FAILED" then
        if HST.activeCast then
            HST.activeCast = nil
            if HST.rangedState == "RELOADING" then
                -- Resume reload bar state
                castBar:SetValue(1)
                castBar:SetStatusBarColor(0.25, 0.25, 0.3, 0.5)
                castTextLeft:SetText("|cffaaaaaaREADY|r")
                castTextRight:SetText("")
            end
        end

    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        if not arg1 then return end
        if string.find(arg1, "Your Auto Shot") then
            StartReloading("Auto Shot")
        elseif string.find(arg1, "Your Steady Shot") then
            reloadTextLeft:SetText("STEADY SHOT")
        elseif string.find(arg1, "Your Multi%-Shot") then
            reloadTextLeft:SetText("MULTI-SHOT")
        elseif string.find(arg1, "Your Aimed Shot") then
            StartReloading("Aimed Shot")
        elseif string.find(arg1, "Your Raptor Strike") or string.find(arg1, "Your Mongoose Bite") then
            StartMeleeSwing()
        end

    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        StartMeleeSwing()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        UpdateSpeeds()

    elseif event == "PLAYER_REGEN_ENABLED" then
        HST.isAutoRepeat = false
    end
end)

-- ----------------------------------------------------------------------------
-- Slash Commands
-- ----------------------------------------------------------------------------
SLASH_HUNTERSWINGTIMER1 = "/hst"
SLASH_HUNTERSWINGTIMER2 = "/stimer"
SLASH_HUNTERSWINGTIMER3 = "/swingtimer"

SlashCmdList["HUNTERSWINGTIMER"] = function(msg)
    local cmd = string.lower(msg or "")

    if cmd == "unlock" or cmd == "move" then
        HunterSwingTimer_Config.locked = false
        dragHandle:Show()
        mainFrame:EnableMouse(true)
        mainFrame:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Unlocked. Drag the blue bar to position.")

    elseif cmd == "lock" then
        HunterSwingTimer_Config.locked = true
        dragHandle:Hide()
        mainFrame:EnableMouse(false)
        if not HST.isTest and HST.rangedState == "IDLE" and not HST.activeCast then
            mainFrame:Hide()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Locked in place.")

    elseif cmd == "test" then
        HST.isTest = not HST.isTest
        if HST.isTest then
            mainFrame:Show()
            -- Start demo cycle with Steady Shot preview
            HST.activeCast = "Steady Shot"
            HST.activeCastStart = GetTime()
            HST.activeCastDuration = 1.5
            castBar:SetStatusBarColor(1.0, 0.85, 0.05, 0.98)
            castTextLeft:SetText("|cffffff00STEADY SHOT|r")
            StartReloading("Auto Shot")
            DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Test mode |cff00ff00ON|r. Demonstrating Steady Shot cast + Auto Shot swing bar.")
        else
            HST.rangedState = "IDLE"
            HST.activeCast = nil
            mainFrame:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Test mode |cffff2020OFF|r.")
        end

    elseif cmd == "melee" then
        HunterSwingTimer_Config.showMelee = not HunterSwingTimer_Config.showMelee
        local st = HunterSwingTimer_Config.showMelee and "|cff00ff00ENABLED|r" or "|cffff2020DISABLED|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Melee swing bar: " .. st)

    elseif cmd == "reset" then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
        HunterSwingTimer_Config.point = "CENTER"
        HunterSwingTimer_Config.relPoint = "CENTER"
        HunterSwingTimer_Config.x = 0
        HunterSwingTimer_Config.y = -140
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[HST]|r Position reset to center.")

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473--- Hunter Swing Timer Commands ---|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/hst unlock|r - Unlock bar to drag and position.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/hst lock|r   - Lock bar in place.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/hst test|r   - Toggle test mode to preview Steady Shot + Swing timers.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/hst melee|r  - Toggle melee swing bar on/off.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/hst reset|r  - Reset position to center screen.")
    end
end
