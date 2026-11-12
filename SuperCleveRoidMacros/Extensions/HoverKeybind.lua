--[[
    HoverKeybind.lua
    Interactive Hover-Keybinding system for SuperCleveRoidMacros (/kb, /hoverbind).
    Hover over any action button and press any key or mouse button (M3/M4/M5) to bind,
    or press ESC or Right-Click to unbind.
]]
local _G = _G or getfenv(0)

local isHoverBindActive = false
local currentHoverBtn = nil

-- Hidden tooltip scanner to extract action / spell names
local scanTip = CreateFrame("GameTooltip", "CleveRoidKBScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Forward declarations
local highlightFrame, kbTooltip, UpdateHoverTooltip, OnKeyAction, ToggleHoverBindMode

-- ----------------------------------------------------------------------------
-- 1. Helper: Map Button Frame to Blizzard Binding Command
-- ----------------------------------------------------------------------------
local function GetButtonBindingCommand(btn)
    if not btn or not btn.GetName then return nil end
    local name = btn:GetName()
    if not name then return nil end

    local _, _, id = string.find(name, "^ActionButton(%d+)$")
    if id then return "ACTIONBUTTON" .. id end

    local _, _, id = string.find(name, "^BonusActionButton(%d+)$")
    if id then return "ACTIONBUTTON" .. id end

    local _, _, id = string.find(name, "^MultiBarBottomLeftButton(%d+)$")
    if id then return "MULTIACTIONBAR1BUTTON" .. id end

    local _, _, id = string.find(name, "^MultiBarBottomRightButton(%d+)$")
    if id then return "MULTIACTIONBAR2BUTTON" .. id end

    local _, _, id = string.find(name, "^MultiBarRightButton(%d+)$")
    if id then return "MULTIACTIONBAR3BUTTON" .. id end

    local _, _, id = string.find(name, "^MultiBarLeftButton(%d+)$")
    if id then return "MULTIACTIONBAR4BUTTON" .. id end

    local _, _, id = string.find(name, "^ShapeshiftButton(%d+)$")
    if id then return "SHAPESHIFTBUTTON" .. id end

    local _, _, id = string.find(name, "^PetActionButton(%d+)$")
    if id then return "BONUSACTIONBUTTON" .. id end

    -- Custom addons / ShaguBars / pfUI
    if btn.command then return btn.command end
    if btn.binding then return btn.binding end

    if btn.action and type(btn.action) == "number" then
        local slot = btn.action
        if slot >= 1 and slot <= 12 then return "ACTIONBUTTON" .. slot end
        if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. (slot - 24) end
        if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. (slot - 36) end
        if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. (slot - 48) end
        if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. (slot - 60) end
        if slot >= 73 and slot <= 108 then return "ACTIONBUTTON" .. (((slot - 1) % 12) + 1) end
    end

    return nil
end

local function GetButtonActionText(btn)
    if not btn then return "Empty" end
    local actionSlot = btn.action or (btn.GetID and btn:GetID())
    if actionSlot and HasAction(actionSlot) then
        local macroName = GetActionText(actionSlot)
        if macroName then return "|cff00ffffMacro:|r " .. macroName end

        scanTip:ClearLines()
        scanTip:SetAction(actionSlot)
        local line1 = CleveRoidKBScanTipTextLeft1:GetText()
        if line1 and line1 ~= "" then
            return "|cff20ff20" .. line1 .. "|r"
        end
        return "Action " .. actionSlot
    end
    if btn.GetName and string.find(btn:GetName(), "Shapeshift") then
        local id = btn.GetID and btn:GetID() or 1
        local _, name = GetShapeshiftFormInfo(id)
        if name then return "|cff20ff20" .. name .. "|r" end
    end
    return "|cff888888Empty|r"
end

local function FormatKeyDisplay(key)
    if not key or key == "" then return "" end
    key = string.gsub(key, "CTRL%-", "Ctrl-")
    key = string.gsub(key, "ALT%-", "Alt-")
    key = string.gsub(key, "SHIFT%-", "Shift-")
    key = string.gsub(key, "BUTTON1", "LeftClick")
    key = string.gsub(key, "BUTTON2", "RightClick")
    key = string.gsub(key, "BUTTON3", "MiddleMouse")
    key = string.gsub(key, "BUTTON4", "Mouse4")
    key = string.gsub(key, "BUTTON5", "Mouse5")
    key = string.gsub(key, "MOUSEWHEELUP", "WheelUp")
    key = string.gsub(key, "MOUSEWHEELDOWN", "WheelDown")
    return key
end

-- ----------------------------------------------------------------------------
-- 2. Update HotKey Labels on all Action Bars
-- ----------------------------------------------------------------------------
local function UpdateAllBarHotkeys()
    if ActionButton_UpdateHotkeys then
        pcall(ActionButton_UpdateHotkeys, "ACTIONBUTTON")
        pcall(ActionButton_UpdateHotkeys, "MULTIACTIONBAR1BUTTON")
        pcall(ActionButton_UpdateHotkeys, "MULTIACTIONBAR2BUTTON")
        pcall(ActionButton_UpdateHotkeys, "MULTIACTIONBAR3BUTTON")
        pcall(ActionButton_UpdateHotkeys, "MULTIACTIONBAR4BUTTON")
        pcall(ActionButton_UpdateHotkeys, "BONUSACTIONBUTTON")
        pcall(ActionButton_UpdateHotkeys, "SHAPESHIFTBUTTON")
    end

    local prefixes = {
        "ActionButton",
        "BonusActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "ShapeshiftButton",
    }

    for _, prefix in ipairs(prefixes) do
        local maxButtons = (prefix == "ShapeshiftButton") and 10 or 12
        for i = 1, maxButtons do
            local btn = _G[prefix .. i]
            local hotkey = _G[prefix .. i .. "HotKey"]
            if btn and hotkey then
                local cmd = GetButtonBindingCommand(btn)
                if cmd then
                    local key = GetBindingKey(cmd)
                    if key then
                        local short = key
                        short = string.gsub(short, "CTRL%-", "c-")
                        short = string.gsub(short, "ALT%-", "a-")
                        short = string.gsub(short, "SHIFT%-", "s-")
                        short = string.gsub(short, "BUTTON1", "M1")
                        short = string.gsub(short, "BUTTON2", "M2")
                        short = string.gsub(short, "BUTTON3", "M3")
                        short = string.gsub(short, "BUTTON4", "M4")
                        short = string.gsub(short, "BUTTON5", "M5")
                        short = string.gsub(short, "MOUSEWHEELUP", "WU")
                        short = string.gsub(short, "MOUSEWHEELDOWN", "WD")
                        hotkey:SetText(short)
                        hotkey:Show()
                    else
                        hotkey:SetText("")
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- 3. Visual Highlight & Tooltip Overlay
-- ----------------------------------------------------------------------------
highlightFrame = CreateFrame("Button", "CleveRoidKBHighlight", UIParent)
highlightFrame:SetFrameStrata("TOOLTIP")
highlightFrame:EnableMouse(true)
highlightFrame:EnableMouseWheel(true)
highlightFrame:RegisterForClicks(
    "LeftButtonDown", "RightButtonDown", "MiddleButtonDown", "Button4Down", "Button5Down",
    "LeftButtonUp", "RightButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up"
)
highlightFrame:Hide()

highlightFrame:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
highlightFrame:SetBackdropBorderColor(0.2, 1.0, 0.3, 1.0) -- Bright glowing green!

local highlightGlow = highlightFrame:CreateTexture(nil, "OVERLAY")
highlightGlow:SetAllPoints(highlightFrame)
highlightGlow:SetTexture(0.2, 1.0, 0.3, 0.22)

-- Floating Tooltip over hovered button
kbTooltip = CreateFrame("GameTooltip", "CleveRoidKBTooltip", UIParent, "GameTooltipTemplate")
kbTooltip:SetFrameStrata("TOOLTIP")
kbTooltip:EnableMouse(false)
kbTooltip:Hide()

UpdateHoverTooltip = function(focus)
    if not focus or not isHoverBindActive then
        highlightFrame:Hide()
        kbTooltip:Hide()
        return
    end

    local command = GetButtonBindingCommand(focus)
    if not command then
        highlightFrame:Hide()
        kbTooltip:Hide()
        return
    end

    local b1, b2 = GetBindingKey(command)
    local bindText = ""
    if b1 and b2 then
        bindText = "|cff20ff20" .. FormatKeyDisplay(b1) .. "|r, |cff20ff20" .. FormatKeyDisplay(b2) .. "|r"
    elseif b1 then
        bindText = "|cff20ff20" .. FormatKeyDisplay(b1) .. "|r"
    elseif b2 then
        bindText = "|cff20ff20" .. FormatKeyDisplay(b2) .. "|r"
    else
        bindText = "|cffff8888No Keybind|r"
    end

    kbTooltip:SetOwner(focus, "ANCHOR_TOP")
    kbTooltip:ClearLines()
    kbTooltip:AddLine("|cffffffff" .. (focus:GetName() or "Action Button") .. "|r", 1, 1, 1)
    kbTooltip:AddLine("Action: " .. GetButtonActionText(focus), 0.9, 0.9, 0.9)
    kbTooltip:AddLine("Current: " .. bindText, 1, 1, 1)
    kbTooltip:AddLine(" ")
    kbTooltip:AddLine("|cffffff00Press any key or mouse button to bind|r", 1, 0.9, 0.2)
    kbTooltip:AddLine("|cffff4040Press ESC or Right-Click to unbind|r", 1, 0.3, 0.3)
    kbTooltip:Show()
end

-- ----------------------------------------------------------------------------
-- 4. Key & Mouse Input Handlers
-- ----------------------------------------------------------------------------
local keyCaptureFrame = CreateFrame("Frame", "CleveRoidKBEngine", UIParent)
keyCaptureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
keyCaptureFrame:EnableMouse(false)
keyCaptureFrame:EnableKeyboard(true)
keyCaptureFrame:Hide()

local function IsModifierOnly(key)
    return key == "LALT" or key == "RALT" or key == "ALT"
        or key == "LCTRL" or key == "RCTRL" or key == "CTRL"
        or key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT"
        or key == "UNKNOWN"
end

OnKeyAction = function(key, target)
    if not isHoverBindActive then return end
    if IsModifierOnly(key) then return end

    local focus = target or currentHoverBtn or (highlightFrame and highlightFrame.targetBtn) or GetMouseFocus()
    local command = GetButtonBindingCommand(focus)

    -- ESCAPE: Unbind current button if bound, or exit /kb mode if nothing bound
    if key == "ESCAPE" then
        if command then
            local b1, b2 = GetBindingKey(command)
            if b1 or b2 then
                if b1 then SetBinding(b1, nil) end
                if b2 then SetBinding(b2, nil) end
                SaveBindings(GetCurrentBindingSet())
                UpdateAllBarHotkeys()
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[HoverBind]|r Unbound all keys from |cffffff00" .. focus:GetName() .. "|r (" .. GetButtonActionText(focus) .. ")")
                UpdateHoverTooltip(focus)
                PlaySound("igMainMenuOptionCheckBoxOff")
                return
            end
        end
        -- Not over a bound button: exit Hover Keybind mode
        ToggleHoverBindMode(false)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[HoverBind]|r Exited Hover Keybind mode. All bindings saved.")
        return
    end

    -- DELETE / BACKSPACE: Unbind
    if key == "DELETE" or key == "BACKSPACE" then
        if command then
            local b1, b2 = GetBindingKey(command)
            if b1 then SetBinding(b1, nil) end
            if b2 then SetBinding(b2, nil) end
            SaveBindings(GetCurrentBindingSet())
            UpdateAllBarHotkeys()
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[HoverBind]|r Unbound all keys from |cffffff00" .. focus:GetName() .. "|r (" .. GetButtonActionText(focus) .. ")")
            UpdateHoverTooltip(focus)
            PlaySound("igMainMenuOptionCheckBoxOff")
            return
        end
    end

    if not command then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[HoverBind]|r Hover over an action button first before pressing a key!")
        return
    end

    -- Build composite modifier string
    local bindKey = ""
    if IsAltKeyDown() then bindKey = bindKey .. "ALT-" end
    if IsControlKeyDown() then bindKey = bindKey .. "CTRL-" end
    if IsShiftKeyDown() then bindKey = bindKey .. "SHIFT-" end
    bindKey = bindKey .. key

    -- Notice if key was already bound to another action
    local oldAction = GetBindingAction(bindKey)
    if oldAction and oldAction ~= "" and oldAction ~= command then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[HoverBind]|r Key |cffffff00" .. FormatKeyDisplay(bindKey) .. "|r was unbound from |cffff8800" .. oldAction .. "|r")
    end

    SetBinding(bindKey, command)
    SaveBindings(GetCurrentBindingSet())
    UpdateAllBarHotkeys()
    PlaySound("igMainMenuOptionCheckBoxOn")
    DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20[HoverBind]|r Bound |cffffff00" .. FormatKeyDisplay(bindKey) .. "|r to |cff20ff20" .. focus:GetName() .. "|r (" .. GetButtonActionText(focus) .. ")")
    UpdateHoverTooltip(focus)
end

-- Keyboard capture
keyCaptureFrame:SetScript("OnKeyDown", function()
    OnKeyAction(arg1, currentHoverBtn)
end)

-- Mouse click dispatcher on the active highlight overlay
local lastMouseTriggerTime = 0
local function HandleMouseInput(btnName)
    if not isHoverBindActive then return end
    local now = GetTime()
    if (now - lastMouseTriggerTime) < 0.12 then return end
    lastMouseTriggerTime = now

    local target = currentHoverBtn or (highlightFrame and highlightFrame.targetBtn)
    if not target then return end

    if btnName == "Button4" then
        OnKeyAction("BUTTON4", target)
    elseif btnName == "Button5" then
        OnKeyAction("BUTTON5", target)
    elseif btnName == "MiddleButton" then
        OnKeyAction("BUTTON3", target)
    elseif btnName == "RightButton" then
        if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then
            OnKeyAction("BUTTON2", target)
        else
            -- Plain Right-Click unbinds the hovered button
            OnKeyAction("ESCAPE", target)
        end
    elseif btnName == "LeftButton" then
        if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then
            OnKeyAction("BUTTON1", target)
        else
            -- Plain Left-Click is reserved (don't lock out UI clicks)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[HoverBind]|r Plain Left-Click cannot be bound. Hold Shift, Ctrl, or Alt to bind Shift-LeftClick.")
        end
    end
end

highlightFrame:SetScript("OnMouseDown", function()
    HandleMouseInput(arg1)
end)

highlightFrame:SetScript("OnMouseUp", function()
    HandleMouseInput(arg1)
end)

highlightFrame:SetScript("OnMouseWheel", function()
    local wheelKey = (arg1 > 0) and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    local target = currentHoverBtn or (highlightFrame and highlightFrame.targetBtn)
    if target then
        OnKeyAction(wheelKey, target)
    end
end)

highlightFrame:SetScript("OnLeave", function()
    this:Hide()
    kbTooltip:Hide()
    currentHoverBtn = nil
    this.targetBtn = nil
end)

-- ----------------------------------------------------------------------------
-- 5. Top Information Banner / Dialog
-- ----------------------------------------------------------------------------
local banner = CreateFrame("Frame", "CleveRoidKBBanner", UIParent)
banner:SetWidth(420)
banner:SetHeight(72)
banner:SetPoint("TOP", UIParent, "TOP", 0, -30)
banner:SetFrameStrata("DIALOG")
banner:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
banner:SetMovable(true)
banner:EnableMouse(true)
banner:RegisterForDrag("LeftButton")
banner:SetScript("OnDragStart", function() this:StartMoving() end)
banner:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
banner:Hide()

local bannerTitle = banner:CreateFontString(nil, "OVERLAY")
bannerTitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
bannerTitle:SetPoint("TOP", banner, "TOP", 0, -8)
bannerTitle:SetTextColor(1, 0.85, 0.2, 1)
bannerTitle:SetText("HOVER KEYBIND MODE (/kb)")

local bannerDesc = banner:CreateFontString(nil, "OVERLAY")
bannerDesc:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
bannerDesc:SetPoint("TOP", bannerTitle, "BOTTOM", 0, -4)
bannerDesc:SetTextColor(1, 1, 1, 1)
bannerDesc:SetText("Hover your mouse over any action button and press any key or mouse button (M3/M4/M5).\nPress |cffff4040ESC|r or |cffff4040Right-Click|r while hovering to unbind that button.")

local bannerDoneBtn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
bannerDoneBtn:SetWidth(120)
bannerDoneBtn:SetHeight(20)
bannerDoneBtn:SetPoint("BOTTOM", banner, "BOTTOM", 0, 8)
bannerDoneBtn:SetText("Done & Save")
bannerDoneBtn:SetScript("OnClick", function()
    ToggleHoverBindMode(false)
    DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20[HoverBind]|r Saved and exited Hover Keybind mode.")
end)

-- Hover polling ticker: positions highlightFrame over the hovered action button
local hoverTicker = CreateFrame("Frame")
hoverTicker:SetScript("OnUpdate", function()
    if not isHoverBindActive then return end
    if highlightFrame:IsShown() then return end

    local focus = GetMouseFocus()
    if focus and focus ~= UIParent and focus ~= WorldFrame and focus ~= banner and focus ~= bannerDoneBtn and focus ~= highlightFrame then
        local command = GetButtonBindingCommand(focus)
        if command then
            currentHoverBtn = focus
            highlightFrame.targetBtn = focus
            highlightFrame:ClearAllPoints()
            highlightFrame:SetAllPoints(focus)
            highlightFrame:Show()
            UpdateHoverTooltip(focus)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 6. Toggle Hover Keybind Mode
-- ----------------------------------------------------------------------------
ToggleHoverBindMode = function(state)
    if state == nil then
        isHoverBindActive = not isHoverBindActive
    else
        isHoverBindActive = state
    end

    if isHoverBindActive then
        banner:Show()
        keyCaptureFrame:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20[HoverBind]|r ACTIVE! Hover over any action button and press a key or mouse button to bind it. Press |cffff4040ESC|r or |cffff4040Right-Click|r to unbind. Click 'Done' or type |cffffff00/kb|r to exit.")
        PlaySound("igMainMenuOpen")
    else
        banner:Hide()
        keyCaptureFrame:Hide()
        highlightFrame:Hide()
        kbTooltip:Hide()
        currentHoverBtn = nil
        highlightFrame.targetBtn = nil
        PlaySound("igMainMenuClose")
    end
end

-- ----------------------------------------------------------------------------
-- 7. Slash Commands: /kb, /hoverbind, /bind
-- ----------------------------------------------------------------------------
SLASH_CLEVEROID_KB1 = "/kb"
SLASH_CLEVEROID_KB2 = "/hoverbind"
SLASH_CLEVEROID_KB3 = "/hoverkeybind"
SlashCmdList.CLEVEROID_KB = function(msg)
    ToggleHoverBindMode()
end

-- ----------------------------------------------------------------------------
-- 8. Smart Focus Toggle Slash Commands: /togglefocus, /tfocus
--    - If hovering over a unit: sets focus to that mouseover unit.
--    - If pressed again without a new mouseover: clears current focus!
--    - If not hovering over a unit: targets current target, or toggles focus off.
-- ----------------------------------------------------------------------------
SLASH_TOGGLEFOCUS1 = "/togglefocus"
SLASH_TOGGLEFOCUS2 = "/tfocus"
SlashCmdList.TOGGLEFOCUS = function(msg)
    local Focus = _G.FocusCore
    if not Focus then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[Focus]|r FocusFrame addon is not loaded.")
        return
    end

    local mo = UnitExists("mouseover") and UnitName("mouseover")
    local cur = Focus:FocusExists() and Focus:GetName()

    if mo and mo ~= cur then
        Focus:SetFocus(mo)
        DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20[Focus]|r Focused mouseover: |cffffff00" .. mo .. "|r")
    elseif cur then
        Focus:ClearFocus()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[Focus]|r Focus cleared.")
    elseif UnitExists("target") then
        local tar = UnitName("target")
        Focus:SetFocus(tar)
        DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20[Focus]|r Focused target: |cffffff00" .. tar .. "|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[Focus]|r No mouseover or target to focus.")
    end
end

