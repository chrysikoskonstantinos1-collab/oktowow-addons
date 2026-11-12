--[[
    BottomActionBars.lua
    Moves MultiBarRight and MultiBarLeft down to horizontal rows above MultiBarBottomRight
    and provides independent scaling and Mouseover Autohide for the top bar.
]]
local _G = _G or getfenv(0)

local currentMainScale = 1.0
local currentExtraScale = 1.0
local mouseoverTopBar = true
local isRepositioning = false

-- ----------------------------------------------------------------------------
-- 1. Main Action Bars Scale (MainMenuBar, BottomLeft, BottomRight)
-- ----------------------------------------------------------------------------
function CleveRoids_SetMainBarScale(scale)
    if not scale or scale <= 0 then scale = 1.0 end
    if scale > 2.0 then scale = 2.0 end
    if scale < 0.4 then scale = 0.4 end
    currentMainScale = scale

    if CleveRoidMacros then
        CleveRoidMacros.MainBarScale = scale
        CleveRoidMacros.ActionBarScale = scale
    end

    if MainMenuBar and MainMenuBar.SetScale then
        MainMenuBar:SetScale(scale)
    end
    if MultiBarBottomLeft and MultiBarBottomLeft.SetScale then
        MultiBarBottomLeft:SetScale(scale)
    end
    if MultiBarBottomRight and MultiBarBottomRight.SetScale then
        MultiBarBottomRight:SetScale(scale)
    end
end

function CleveRoids_GetMainBarScale()
    return currentMainScale or 1.0
end

function CleveRoids_SetActionBarScale(scale)
    CleveRoids_SetMainBarScale(scale)
end
function CleveRoids_GetActionBarScale()
    return CleveRoids_GetMainBarScale()
end

-- ----------------------------------------------------------------------------
-- 2. Extra Action Bars Scale (MultiBarRight & MultiBarLeft - from the right side)
-- ----------------------------------------------------------------------------
function CleveRoids_SetExtraBarScale(scale)
    if not scale or scale <= 0 then scale = 1.0 end
    if scale > 2.0 then scale = 2.0 end
    if scale < 0.4 then scale = 0.4 end
    currentExtraScale = scale

    if CleveRoidMacros then
        CleveRoidMacros.ExtraBarScale = scale
    end

    if MultiBarRight and MultiBarRight.SetScale then
        MultiBarRight:SetScale(scale)
    end
    if MultiBarLeft and MultiBarLeft.SetScale then
        MultiBarLeft:SetScale(scale)
    end
end

function CleveRoids_GetExtraBarScale()
    return currentExtraScale or 1.0
end

-- ----------------------------------------------------------------------------
-- 3. Mouseover Autohide for Top Extra Bar (MultiBarLeft)
-- ----------------------------------------------------------------------------
function CleveRoids_SetTopBarMouseover(enable)
    mouseoverTopBar = enable
    if CleveRoidMacros then
        CleveRoidMacros.TopBarMouseover = enable
    end
    if not enable then
        if MultiBarLeft then MultiBarLeft:SetAlpha(1.0) end
        for i = 1, 12 do
            local btn = _G["MultiBarLeftButton" .. i]
            if btn then btn:SetAlpha(1.0) end
        end
    end
end

function CleveRoids_GetTopBarMouseover()
    return mouseoverTopBar
end

local function CheckTopBarHover()
    if not mouseoverTopBar then return true end
    if CursorHasItem() or CursorHasSpell() then return true end

    if MultiBarLeft and MouseIsOver(MultiBarLeft) then return true end
    for i = 1, 12 do
        local btn = _G["MultiBarLeftButton" .. i]
        if btn and btn:IsShown() and MouseIsOver(btn) then
            return true
        end
    end
    return false
end

local topBarAlpha = 0.0
local faderFrame = CreateFrame("Frame")
faderFrame:SetScript("OnUpdate", function()
    if not MultiBarLeft then return end
    if not mouseoverTopBar then return end

    local isHovered = CheckTopBarHover()
    local targetAlpha = isHovered and 1.0 or 0.0

    if topBarAlpha ~= targetAlpha then
        if targetAlpha > topBarAlpha then
            topBarAlpha = topBarAlpha + (arg1 * 8)
            if topBarAlpha > 1.0 then topBarAlpha = 1.0 end
        else
            topBarAlpha = topBarAlpha - (arg1 * 3.5)
            if topBarAlpha < 0.0 then topBarAlpha = 0.0 end
        end

        MultiBarLeft:SetAlpha(topBarAlpha)
        for i = 1, 12 do
            local btn = _G["MultiBarLeftButton" .. i]
            if btn then
                btn:SetAlpha(topBarAlpha)
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 4. Horizontal Arrangement of Right Bars at the Bottom
-- ----------------------------------------------------------------------------
local function MoveBarsToBottom()
    if not MultiBarBottomRight or not MultiBarRight then return end

    -- Position MultiBarRight directly above MultiBarBottomRight as horizontal row 1
    MultiBarRight:ClearAllPoints()
    MultiBarRight:SetPoint("BOTTOMLEFT", MultiBarBottomRight, "TOPLEFT", 0, 4)
    MultiBarRight:SetWidth(498)
    MultiBarRight:SetHeight(38)

    if MultiBarRightButton1 then
        MultiBarRightButton1:ClearAllPoints()
        MultiBarRightButton1:SetPoint("BOTTOMLEFT", MultiBarRight, "BOTTOMLEFT", 0, 0)
        for i = 2, 12 do
            local btn = _G["MultiBarRightButton" .. i]
            local prev = _G["MultiBarRightButton" .. (i - 1)]
            if btn and prev then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            end
        end
    end

    -- Position MultiBarLeft directly above MultiBarRight as horizontal row 2
    if MultiBarLeft and MultiBarLeftButton1 then
        MultiBarLeft:ClearAllPoints()
        MultiBarLeft:SetPoint("BOTTOMLEFT", MultiBarRight, "TOPLEFT", 0, 4)
        MultiBarLeft:SetWidth(498)
        MultiBarLeft:SetHeight(38)

        MultiBarLeftButton1:ClearAllPoints()
        MultiBarLeftButton1:SetPoint("BOTTOMLEFT", MultiBarLeft, "BOTTOMLEFT", 0, 0)
        for i = 2, 12 do
            local btn = _G["MultiBarLeftButton" .. i]
            local prev = _G["MultiBarLeftButton" .. (i - 1)]
            if btn and prev then
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            end
        end
    end

    -- Keep PetActionBarFrame cleanly above the highest bottom bar (unless manually moved)
    if PetActionBarFrame and not PetActionBarFrame:IsUserPlaced() then
        local topBar = MultiBarBottomLeft
        if MultiBarRight and MultiBarRight:IsShown() then topBar = MultiBarRight end
        if MultiBarLeft and MultiBarLeft:IsShown() then topBar = MultiBarLeft end

        PetActionBarFrame:ClearAllPoints()
        PetActionBarFrame:SetPoint("BOTTOMLEFT", topBar, "TOPLEFT", 36, 4)
    end

    -- Apply scales safely without recursion
    if currentMainScale and currentMainScale ~= 1.0 then
        CleveRoids_SetMainBarScale(currentMainScale)
    end
    if currentExtraScale and currentExtraScale ~= 1.0 then
        CleveRoids_SetExtraBarScale(currentExtraScale)
    end
end

-- Hook UIParent_ManageFramePositions with strict re-entrancy guard
if UIParent_ManageFramePositions then
    local orig_UIParent_ManageFramePositions = UIParent_ManageFramePositions
    UIParent_ManageFramePositions = function(a1, a2, a3)
        orig_UIParent_ManageFramePositions(a1, a2, a3)
        if isRepositioning then return end
        isRepositioning = true
        MoveBarsToBottom()
        isRepositioning = false
    end
end

-- Slash commands for Extra Bars: /extrabarscale, /ebscale, /rightbarscale
SLASH_EXTRABARSCALE1 = "/extrabarscale"
SLASH_EXTRABARSCALE2 = "/ebscale"
SLASH_EXTRABARSCALE3 = "/rightbarscale"
SlashCmdList.EXTRABARSCALE = function(msg)
    if not msg or msg == "" then
        local pct = math.floor((currentExtraScale or 1.0) * 100 + 0.5)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Extra Bars Scale:|r Currently |cff20ff20" .. pct .. "%|r. Usage: |cffffff00/ebscale 80|r (for 80%) or |cffffff00/ebscale +|r / |cffffff00/ebscale -|r")
        return
    end

    msg = string.gsub(msg, "%s+", "")
    msg = string.gsub(msg, "%%", "")

    if msg == "+" or msg == "up" then
        CleveRoids_SetExtraBarScale((currentExtraScale or 1.0) + 0.05)
    elseif msg == "-" or msg == "down" then
        CleveRoids_SetExtraBarScale((currentExtraScale or 1.0) - 0.05)
    elseif msg == "reset" or msg == "100" or msg == "1" then
        CleveRoids_SetExtraBarScale(1.0)
    else
        local num = tonumber(msg)
        if num then
            if num > 2.0 then num = num / 100.0 end
            CleveRoids_SetExtraBarScale(num)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Extra Bars Scale:|r Invalid number. Example: |cffffff00/ebscale 80|r")
            return
        end
    end

    local pct = math.floor((currentExtraScale or 1.0) * 100 + 0.5)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Extra Bars Scale:|r Set to |cff20ff20" .. pct .. "%|r")
end

-- Slash command for Main Bars Scale: /mainbarscale, /barscale
SLASH_MAINBARSCALE1 = "/mainbarscale"
SLASH_MAINBARSCALE2 = "/mbscale"
SLASH_MAINBARSCALE3 = "/barscale"
SlashCmdList.MAINBARSCALE = function(msg)
    if not msg or msg == "" then
        local pct = math.floor((currentMainScale or 1.0) * 100 + 0.5)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Main Bars Scale:|r Currently |cff20ff20" .. pct .. "%|r. Usage: |cffffff00/mainbarscale 90|r (for 90%) or |cffffff00/barscale +|r")
        return
    end

    msg = string.gsub(msg, "%s+", "")
    msg = string.gsub(msg, "%%", "")

    if msg == "+" or msg == "up" then
        CleveRoids_SetMainBarScale((currentMainScale or 1.0) + 0.05)
    elseif msg == "-" or msg == "down" then
        CleveRoids_SetMainBarScale((currentMainScale or 1.0) - 0.05)
    elseif msg == "reset" or msg == "100" or msg == "1" then
        CleveRoids_SetMainBarScale(1.0)
    else
        local num = tonumber(msg)
        if num then
            if num > 2.0 then num = num / 100.0 end
            CleveRoids_SetMainBarScale(num)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Main Bars Scale:|r Invalid number. Example: |cffffff00/barscale 90|r")
            return
        end
    end

    local pct = math.floor((currentMainScale or 1.0) * 100 + 0.5)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Main Bars Scale:|r Set to |cff20ff20" .. pct .. "%|r")
end

-- Slash command for Mouseover toggle: /fadebar or /topbarmouseover
SLASH_FADEBAR1 = "/fadebar"
SLASH_FADEBAR2 = "/topbarmouseover"
SlashCmdList.FADEBAR = function(msg)
    local newState = not mouseoverTopBar
    CleveRoids_SetTopBarMouseover(newState)
    local stateText = newState and "|cff20ff20ON (Hidden until mouseover)|r" or "|cffff4040OFF (Always visible)|r"
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Top Bar Mouseover:|r Now " .. stateText)
end

local barFrame = CreateFrame("Frame")
barFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
barFrame:RegisterEvent("VARIABLES_LOADED")
barFrame:SetScript("OnEvent", function()
    if CleveRoidMacros then
        if CleveRoidMacros.MainBarScale and CleveRoidMacros.MainBarScale > 0 then
            currentMainScale = CleveRoidMacros.MainBarScale
        elseif CleveRoidMacros.ActionBarScale and CleveRoidMacros.ActionBarScale > 0 then
            currentMainScale = CleveRoidMacros.ActionBarScale
        end
        if CleveRoidMacros.ExtraBarScale and CleveRoidMacros.ExtraBarScale > 0 then
            currentExtraScale = CleveRoidMacros.ExtraBarScale
        end
        if CleveRoidMacros.TopBarMouseover ~= nil then
            mouseoverTopBar = CleveRoidMacros.TopBarMouseover
        end
    end
    MoveBarsToBottom()
end)

MoveBarsToBottom()

-- ----------------------------------------------------------------------------
-- 5. Pet Action Bar Mover (/movepet and /resetpet)
-- ----------------------------------------------------------------------------
local petDragHandle = CreateFrame("Button", "CleveRoids_PetDragHandle", UIParent)
petDragHandle:SetWidth(360)
petDragHandle:SetHeight(20)
petDragHandle:SetFrameStrata("TOOLTIP")
petDragHandle:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
petDragHandle:SetBackdropColor(0.1, 0.5, 0.9, 0.85)
petDragHandle:SetBackdropBorderColor(0.4, 0.9, 1.0, 1)
petDragHandle:EnableMouse(true)
petDragHandle:RegisterForDrag("LeftButton")
petDragHandle:Hide()

local petDragText = petDragHandle:CreateFontString(nil, "OVERLAY")
petDragText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
petDragText:SetPoint("CENTER", petDragHandle, "CENTER", 0, 0)
petDragText:SetText("PET ACTION BAR (DRAG TO MOVE)")
petDragText:SetTextColor(1, 1, 1, 1)

petDragHandle:SetScript("OnDragStart", function()
    if PetActionBarFrame then
        PetActionBarFrame:SetMovable(true)
        PetActionBarFrame:StartMoving()
        petDragHandle.isMoving = true
    end
end)

petDragHandle:SetScript("OnDragStop", function()
    if PetActionBarFrame then
        PetActionBarFrame:StopMovingOrSizing()
        PetActionBarFrame:SetUserPlaced(true)
        petDragHandle.isMoving = false
        petDragHandle:ClearAllPoints()
        petDragHandle:SetPoint("BOTTOMLEFT", PetActionBarFrame, "TOPLEFT", 36, 2)
    end
end)

petDragHandle:SetScript("OnUpdate", function()
    if petDragHandle.isMoving and PetActionBarFrame then
        petDragHandle:ClearAllPoints()
        petDragHandle:SetPoint("BOTTOMLEFT", PetActionBarFrame, "TOPLEFT", 36, 2)
    end
end)

SLASH_MOVEPET1 = "/movepet"
SLASH_MOVEPET2 = "/unlockpet"
SlashCmdList["MOVEPET"] = function()
    if petDragHandle:IsShown() then
        petDragHandle:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[Pet Bar]|r Locked in place.")
    else
        if PetActionBarFrame then
            PetActionBarFrame:SetMovable(true)
            petDragHandle:ClearAllPoints()
            petDragHandle:SetPoint("BOTTOMLEFT", PetActionBarFrame, "TOPLEFT", 36, 2)
            petDragHandle:Show()
            DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[Pet Bar]|r Unlocked! Drag the blue bar to position your pet bar. Type |cffffd200/movepet|r when done.")
        end
    end
end

SLASH_RESETPET1 = "/resetpet"
SlashCmdList["RESETPET"] = function()
    if PetActionBarFrame then
        PetActionBarFrame:SetUserPlaced(false)
        petDragHandle:Hide()
        MoveBarsToBottom()
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[Pet Bar]|r Reset to sit cleanly above action bars.")
    end
end
