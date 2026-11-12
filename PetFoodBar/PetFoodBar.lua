--[[
    PetFoodBar.lua
    Scans bags for food your pet can eat and displays a small box with one-click icons to auto-feed your pet.
]]

local _G = _G or getfenv(0)

PetFoodBar_Config = PetFoodBar_Config or {
    x = 0,
    y = -70,
    point = "CENTER",
    relPoint = "CENTER",
    locked = false,
    scale = 1.0,
}

local PFB = {
    buttons = {},
    foods = {},
    allowedDiets = {},
    isFeeding = false,
}

-- ----------------------------------------------------------------------------
-- Hidden Tooltip for Scanning
-- ----------------------------------------------------------------------------
local scanTooltip = CreateFrame("GameTooltip", "PetFoodBarScanTooltip", UIParent, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- ----------------------------------------------------------------------------
-- UI Construction
-- ----------------------------------------------------------------------------
local backdrop = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local mainFrame = CreateFrame("Frame", "PetFoodBarFrame", UIParent)
mainFrame:SetWidth(150)
mainFrame:SetHeight(56)
mainFrame:SetPoint(PetFoodBar_Config.point or "CENTER", UIParent, PetFoodBar_Config.relPoint or "CENTER", PetFoodBar_Config.x or 0, PetFoodBar_Config.y or -70)
mainFrame:SetClampedToScreen(true)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:SetBackdrop(backdrop)
mainFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
mainFrame:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.95)
mainFrame:Hide()

-- Title & Drag Header
local titleBar = CreateFrame("Frame", nil, mainFrame)
titleBar:SetHeight(16)
titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -2)
titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -2)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")

local titleText = titleBar:CreateFontString(nil, "OVERLAY")
titleText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
titleText:SetPoint("LEFT", titleBar, "LEFT", 2, 0)
titleText:SetText("|cffabd473PET FOOD|r")

local happyText = titleBar:CreateFontString(nil, "OVERLAY")
happyText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
happyText:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
happyText:SetText("")

titleBar:SetScript("OnDragStart", function()
    if not PetFoodBar_Config.locked then
        mainFrame:StartMoving()
    end
end)

titleBar:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    local point, _, relPoint, x, y = mainFrame:GetPoint()
    PetFoodBar_Config.point = point
    PetFoodBar_Config.relPoint = relPoint
    PetFoodBar_Config.x = x
    PetFoodBar_Config.y = y
end)

-- "No Food" label
local emptyText = mainFrame:CreateFontString(nil, "OVERLAY")
emptyText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
emptyText:SetPoint("CENTER", mainFrame, "CENTER", 0, -8)
emptyText:SetText("|cff888888No pet food in bags|r")
emptyText:Hide()

-- ----------------------------------------------------------------------------
-- Food Action Buttons
-- ----------------------------------------------------------------------------
local function CreateFoodButton(id)
    local btn = CreateFrame("Button", "PetFoodBarButton" .. id, mainFrame)
    btn:SetWidth(32)
    btn:SetHeight(32)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(btn)
    btn.icon = icon

    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    count:SetTextColor(1, 1, 1, 1)
    btn.countText = count

    btn:SetScript("OnClick", function()
        if this.bag and this.slot then
            CastSpellByName("Feed Pet")
            PickupContainerItem(this.bag, this.slot)
            if SpellIsTargeting() then
                SpellStopTargeting()
            end
        end
    end)

    btn:SetScript("OnEnter", function()
        if this.bag and this.slot then
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetBagItem(this.bag, this.slot)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Click to feed pet|r", 0, 1, 0)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

-- ----------------------------------------------------------------------------
-- Bag Scanner & Diet Matching
-- ----------------------------------------------------------------------------
local function UpdatePetDiets()
    PFB.allowedDiets = {}
    if not UnitExists("pet") then return end

    local diets = { GetPetFoodTypes() }
    for _, diet in ipairs(diets) do
        if diet and type(diet) == "string" then
            PFB.allowedDiets[string.lower(diet)] = true
        end
    end
end

-- Fallback tooltip scan for consumable foods
local function IsConsumableFood(bag, slot)
    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bag, slot)
    for i = 1, scanTooltip:NumLines() do
        local line = _G["PetFoodBarScanTooltipTextLeft" .. i]
        if line and line:GetText() then
            local text = line:GetText()
            if string.find(text, "Restores %d+ health") or string.find(text, "Restores %d+ to %d+ health") then
                return true
            end
        end
    end
    return false
end

local function ScanBagsForPetFood()
    PFB.foods = {}
    if not UnitExists("pet") then return end

    UpdatePetDiets()

    local foundItems = {}

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, itemID = string.find(link, "item:(%d+)")
                    itemID = tonumber(itemID)
                    if itemID then
                        local isPetFood = PetFood_MatchesPet(itemID, PFB.allowedDiets)

                        -- Fallback for custom foods on Turtle WoW
                        if not isPetFood and IsConsumableFood(bag, slot) then
                            -- Check if any diet keyword matches item name or tooltip
                            local itemName = GetItemInfo(link)
                            if itemName then
                                local lowerName = string.lower(itemName)
                                for dietName, _ in pairs(PFB.allowedDiets) do
                                    if string.find(lowerName, dietName) then
                                        isPetFood = true
                                        break
                                    end
                                end
                            end
                        end

                        if isPetFood then
                            local _, count, _, _, _ = GetContainerItemInfo(bag, slot)
                            local texture = GetContainerItemInfo(bag, slot)
                            local itemName = GetItemInfo(link) or "Food"

                            if foundItems[itemID] then
                                foundItems[itemID].count = foundItems[itemID].count + (count or 1)
                            else
                                local entry = {
                                    itemID = itemID,
                                    name = itemName,
                                    texture = texture,
                                    count = (count or 1),
                                    bag = bag,
                                    slot = slot,
                                }
                                foundItems[itemID] = entry
                                table.insert(PFB.foods, entry)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Update Display
-- ----------------------------------------------------------------------------
local function UpdateHappinessIndicator()
    if not UnitExists("pet") then
        happyText:SetText("")
        return
    end

    local happiness, damagePct, loyaltyRate = GetPetHappiness()
    if happiness == 3 then
        happyText:SetText("|cff00ff00[Happy (125%)]|r")
    elseif happiness == 2 then
        happyText:SetText("|cffffff00[Content (100%)]|r")
    elseif happiness == 1 then
        happyText:SetText("|cffff2020[Unhappy (75%)]|r")
    else
        happyText:SetText("")
    end

    -- Check if pet is currently eating (Feed Pet Effect buff)
    for i = 1, 16 do
        local buff = UnitBuff("pet", i)
        if buff and string.find(buff, "Ability_Hunter_BeastTraining") then
            happyText:SetText("|cff33ccff[Eating...]|r")
            break
        end
    end
end

local function UpdatePetFoodBar()
    local _, class = UnitClass("player")
    if class ~= "HUNTER" or not UnitExists("pet") or UnitIsDead("pet") then
        mainFrame:Hide()
        return
    end

    ScanBagsForPetFood()
    UpdateHappinessIndicator()

    local numFoods = table.getn(PFB.foods)

    if numFoods == 0 then
        -- Hide all buttons
        for _, btn in ipairs(PFB.buttons) do
            btn:Hide()
        end
        mainFrame:SetWidth(150)
        emptyText:Show()
        mainFrame:Show()
        return
    end

    emptyText:Hide()

    -- Adjust frame width to fit food buttons: padding + (count * 36)
    local width = 8 + (numFoods * 36)
    if width < 120 then width = 120 end
    mainFrame:SetWidth(width)

    for i = 1, numFoods do
        local food = PFB.foods[i]
        local btn = PFB.buttons[i]
        if not btn then
            btn = CreateFoodButton(i)
            PFB.buttons[i] = btn
        end

        btn.bag = food.bag
        btn.slot = food.slot
        btn.itemID = food.itemID

        btn.icon:SetTexture(food.texture)
        if food.count and food.count > 1 then
            btn.countText:SetText(food.count)
        else
            btn.countText:SetText("")
        end

        btn:ClearAllPoints()
        btn:SetPoint("LEFT", mainFrame, "LEFT", 6 + ((i - 1) * 36), -7)
        btn:Show()
    end

    -- Hide remaining unused buttons
    for i = numFoods + 1, table.getn(PFB.buttons) do
        PFB.buttons[i]:Hide()
    end

    mainFrame:Show()
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PET_UI_UPDATE")
eventFrame:RegisterEvent("UNIT_HAPPINESS")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function()
    if event == "UNIT_AURA" and arg1 ~= "pet" then
        return
    end
    UpdatePetFoodBar()
end)

-- ----------------------------------------------------------------------------
-- Slash Commands
-- ----------------------------------------------------------------------------
SLASH_PETFOODBAR1 = "/pfb"
SLASH_PETFOODBAR2 = "/petfood"
SLASH_PETFOODBAR3 = "/feedbar"

SlashCmdList["PETFOODBAR"] = function(msg)
    local cmd = string.lower(msg or "")

    if cmd == "reset" then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -70)
        PetFoodBar_Config.point = "CENTER"
        PetFoodBar_Config.relPoint = "CENTER"
        PetFoodBar_Config.x = 0
        PetFoodBar_Config.y = -70
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[Pet Food Bar]|r Position reset to center.")

    elseif cmd == "lock" then
        PetFoodBar_Config.locked = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[Pet Food Bar]|r Locked.")

    elseif cmd == "unlock" then
        PetFoodBar_Config.locked = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473[Pet Food Bar]|r Unlocked. Drag by the title bar.")

    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffabd473--- Pet Food Bar Commands ---|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/pfb|r - Show help commands.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/pfb lock|r - Lock position.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/pfb unlock|r - Unlock position to drag.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/pfb reset|r - Reset position to center screen.")
        UpdatePetFoodBar()
    end
end
