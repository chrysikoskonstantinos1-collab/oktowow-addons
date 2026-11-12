-- ============================================================================
-- RaidSynergy - Clean Floating Buffs & Debuffs Monitor (Vanilla 1.12.1 / OktoWoW)
-- Two independent, movable frames:
-- 1. Buffs on You (Combined from all classes in your party/raid)
-- 2. Debuffs on Target (Combined from all classes in your party/raid)
-- Clean, borderless floating icons.
-- Vibrant (100% opacity) if active, Dimmed (25% opacity) if missing.
-- Includes Test Mode (simulate all buffs/debuffs active) & In-game Size Scaling!
-- ============================================================================

local RS = CreateFrame("Frame", "RaidSynergyCoreFrame", UIParent)
RaidSynergyDB = RaidSynergyDB or {}

-- Default scale to 0.85 for sleek compact size
if not RaidSynergyDB.buffsScale then RaidSynergyDB.buffsScale = 0.85 end
if not RaidSynergyDB.debuffsScale then RaidSynergyDB.debuffsScale = 0.85 end

-- ----------------------------------------------------------------------------
-- 1. Class Synergy Spell Registry
-- ----------------------------------------------------------------------------
local CLASS_SPELLS = {
    WARRIOR = {
        name = "Warrior",
        buffs = {
            { name = "Battle Shout", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", class = "Warrior", desc = "Increases Attack Power for party members." }
        },
        debuffs = {
            { name = "Sunder Armor", icon = "Interface\\Icons\\Ability_Warrior_Sunder", class = "Warrior", maxStacks = 5, desc = "Reduces target Armor by up to 2250 (5 stacks)." },
            { name = "Demoralizing Shout", icon = "Interface\\Icons\\Ability_Warrior_WarCry", class = "Warrior", desc = "Reduces target Attack Power by up to 140." },
            { name = "Thunder Clap", icon = "Interface\\Icons\\Spell_Nature_ThunderClap", class = "Warrior", desc = "Slows target attack speed by 10%." }
        }
    },
    PRIEST = {
        name = "Priest",
        buffs = {
            { name = "Power Word: Fortitude", alt = "Prayer of Fortitude", icon = "Interface\\Icons\\Spell_Holy_WordFortitude", class = "Priest", desc = "Increases Stamina by up to 70." },
            { name = "Shadow Protection", alt = "Prayer of Shadow Protection", icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", class = "Priest", desc = "Increases Shadow Resistance by up to 60." },
            { name = "Divine Spirit", alt = "Prayer of Spirit", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", class = "Priest", desc = "Increases Spirit by up to 50." }
        },
        debuffs = {
            { name = "Shadow Vulnerability", alt = "Shadow Weaving", icon = "Interface\\Icons\\Spell_Shadow_BlackPlague", class = "Priest", maxStacks = 5, desc = "Increases Shadow damage taken by up to 15% (5 stacks)." }
        }
    },
    MAGE = {
        name = "Mage",
        buffs = {
            { name = "Arcane Intellect", alt = "Arcane Brilliance", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", class = "Mage", desc = "Increases Intellect by up to 31." },
            { name = "Amplify Magic", icon = "Interface\\Icons\\Spell_Holy_FlashHeal", class = "Mage", desc = "Increases magic damage & healing taken." },
            { name = "Dampen Magic", icon = "Interface\\Icons\\Spell_Nature_AbolishPoison", class = "Mage", desc = "Decreases magic damage & healing taken." }
        },
        debuffs = {
            { name = "Winter's Chill", icon = "Interface\\Icons\\Spell_Frost_ChillingBlast", class = "Mage", maxStacks = 5, desc = "Increases Frost critical strike chance by up to 10% (5 stacks)." },
            { name = "Fire Vulnerability", alt = "Improved Scorch", icon = "Interface\\Icons\\Spell_Fire_SoulBurn", class = "Mage", maxStacks = 5, desc = "Increases Fire damage taken by up to 15% (5 stacks)." }
        }
    },
    DRUID = {
        name = "Druid",
        buffs = {
            { name = "Mark of the Wild", alt = "Gift of the Wild", icon = "Interface\\Icons\\Spell_Nature_Regeneration", class = "Druid", desc = "Increases Armor, All Attributes, and All Resistances." },
            { name = "Thorns", icon = "Interface\\Icons\\Spell_Nature_Thorns", class = "Druid", desc = "Causes Nature damage to attackers on hit." },
            { name = "Leader of the Pack", icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina", class = "Druid", desc = "Increases melee and ranged Critical Strike chance by 3% for party." },
            { name = "Moonkin Aura", icon = "Interface\\Icons\\Spell_Nature_Moonglow", class = "Druid", desc = "Increases Spell Critical Strike chance by 3% for party." }
        },
        debuffs = {
            { name = "Faerie Fire", alt = "Faerie Fire (Feral)", icon = "Interface\\Icons\\Spell_Nature_FaerieFire", class = "Druid", desc = "Reduces target Armor by 505 and prevents stealth." }
        }
    },
    PALADIN = {
        name = "Paladin",
        buffs = {
            { name = "Blessing of Might", alt = "Greater Blessing of Might", icon = "Interface\\Icons\\Spell_Holy_FistOfJustice", class = "Paladin", desc = "Increases Melee Attack Power." },
            { name = "Blessing of Kings", alt = "Greater Blessing of Kings", icon = "Interface\\Icons\\Spell_Magic_MageArmor", class = "Paladin", desc = "Increases all stats by 10%." },
            { name = "Blessing of Salvation", alt = "Greater Blessing of Salvation", icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation", class = "Paladin", desc = "Reduces threat generated by 30%." },
            { name = "Blessing of Light", alt = "Greater Blessing of Light", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", class = "Paladin", desc = "Increases Holy Light & Flash of Light healing taken." },
            { name = "Blessing of Sanctuary", alt = "Greater Blessing of Sanctuary", icon = "Interface\\Icons\\Spell_Nature_LightningShield", class = "Paladin", desc = "Reduces damage taken and reflects damage on block." },
            { name = "Blessing of Wisdom", alt = "Greater Blessing of Wisdom", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", class = "Paladin", desc = "Restores mana every 5 seconds." }
        },
        debuffs = {
            { name = "Judgement of the Crusader", icon = "Interface\\Icons\\Spell_Holy_HolySmite", class = "Paladin", desc = "Increases Holy damage taken by the target." },
            { name = "Judgement of Light", icon = "Interface\\Icons\\Spell_Holy_RighteousnessAura", class = "Paladin", desc = "Heals attackers on hit." },
            { name = "Judgement of Wisdom", icon = "Interface\\Icons\\Spell_Holy_RighteousnessAura", class = "Paladin", desc = "Restores mana to attackers on hit." }
        }
    },
    SHAMAN = {
        name = "Shaman",
        buffs = {
            { name = "Windfury Totem", icon = "Interface\\Icons\\Spell_Nature_Windfury", class = "Shaman", desc = "Gives melee attacks a 20% chance to grant extra attacks." },
            { name = "Grace of Air", icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem", class = "Shaman", desc = "Increases party Agility by up to 77." },
            { name = "Strength of Earth", icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem", class = "Shaman", desc = "Increases party Strength by up to 77." },
            { name = "Stoneskin", icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem", class = "Shaman", desc = "Reduces melee damage taken by up to 30." },
            { name = "Mana Spring", icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", class = "Shaman", desc = "Restores mana to party members every 2 seconds." }
        },
        debuffs = {
            { name = "Stormstrike", icon = "Interface\\Icons\\Spell_Holy_SealOfMight", class = "Shaman", desc = "Increases Nature damage taken by 20% for next 2 hits." }
        }
    },
    WARLOCK = {
        name = "Warlock",
        buffs = {
            { name = "Blood Pact", icon = "Interface\\Icons\\Spell_Shadow_BloodBoil", class = "Warlock", desc = "Imp aura that increases party Stamina by up to 42." },
            { name = "Soulstone Resurrection", alt = "Soulstone", icon = "Interface\\Icons\\Spell_Shadow_SoulGem", class = "Warlock", desc = "Allows player to resurrect upon death." }
        },
        debuffs = {
            { name = "Curse of the Elements", icon = "Interface\\Icons\\Spell_Shadow_ChillTouch", class = "Warlock", desc = "Reduces Fire & Frost resist and increases Fire/Frost damage by up to 10%." },
            { name = "Curse of Shadow", icon = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde", class = "Warlock", desc = "Reduces Shadow & Arcane resist and increases Shadow/Arcane damage by up to 10%." },
            { name = "Curse of Recklessness", icon = "Interface\\Icons\\Spell_Shadow_UnholyStrength", class = "Warlock", desc = "Reduces target Armor by up to 640 and prevents fleeing." }
        }
    },
    HUNTER = {
        name = "Hunter",
        buffs = {
            { name = "Trueshot Aura", icon = "Interface\\Icons\\Ability_TrueShot", class = "Hunter", desc = "Increases ranged and melee Attack Power by up to 100 for party." }
        },
        debuffs = {
            { name = "Hunter's Mark", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", class = "Hunter", desc = "Increases ranged Attack Power against target by up to 110." }
        }
    },
    ROGUE = {
        name = "Rogue",
        buffs = {},
        debuffs = {
            { name = "Expose Armor", icon = "Interface\\Icons\\Ability_Warrior_Riposte", class = "Rogue", maxStacks = 1, desc = "Reduces target Armor by up to 2050 (finishing move)." }
        }
    }
}

local CLASS_ORDER = { "WARRIOR", "PRIEST", "MAGE", "DRUID", "PALADIN", "SHAMAN", "WARLOCK", "HUNTER", "ROGUE" }

-- Hidden tooltip for 1.12 aura scanning
local scanTip = CreateFrame("GameTooltip", "RaidSynergyScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- ----------------------------------------------------------------------------
-- 2. Aura Scanning & PvP Check Helpers
-- ----------------------------------------------------------------------------
local function IsInPvPInstance()
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "pvp" or instanceType == "arena") then
            return true
        end
    end

    if GetNumBattlefieldScores and GetNumBattlefieldScores() > 0 then
        return true
    end

    local zone = GetZoneText() or ""
    local zl = string.lower(zone)
    if string.find(zl, "warsong") or string.find(zl, "arathi basin") or string.find(zl, "alterac") 
       or string.find(zl, "arena") or string.find(zl, "gurubashi") or string.find(zl, "blood ring")
       or string.find(zl, "sunnyglade") then
        return true
    end

    return false
end

local function CheckBuffActive(buffName, altName)
    if RaidSynergyDB.testMode then
        return true, 1
    end

    local target1 = string.lower(buffName)
    local target2 = altName and string.lower(altName) or nil

    if C_UnitAuras and C_UnitAuras.UnitAura then
        for i = 1, 32 do
            local name, rank, count = C_UnitAuras.UnitAura("player", i, "HELPFUL")
            if not name then break end
            local nl = string.lower(name)
            if string.find(nl, target1) or (target2 and string.find(nl, target2)) then
                return true, count or 1
            end
        end
    end

    for i = 1, 32 do
        scanTip:ClearLines()
        scanTip:SetUnitBuff("player", i)
        local line = RaidSynergyScanTipTextLeft1 and RaidSynergyScanTipTextLeft1:GetText()
        if not line then break end
        local ll = string.lower(line)
        if string.find(ll, target1) or (target2 and string.find(ll, target2)) then
            local count = 1
            local _, apps = UnitBuff("player", i)
            if apps and apps > 1 then count = apps end
            return true, count
        end
    end

    return false, 0
end

local function CheckDebuffActive(debuffName, altName, maxStacks)
    if RaidSynergyDB.testMode then
        return true, maxStacks or 1
    end

    if not UnitExists("target") or UnitIsFriend("player", "target") then
        return false, 0
    end

    local target1 = string.lower(debuffName)
    local target2 = altName and string.lower(altName) or nil

    if C_UnitAuras and C_UnitAuras.UnitAura then
        for i = 1, 32 do
            local name, rank, count = C_UnitAuras.UnitAura("target", i, "HARMFUL")
            if not name then break end
            local nl = string.lower(name)
            if string.find(nl, target1) or (target2 and string.find(nl, target2)) then
                return true, count or 1
            end
        end
    end

    local lib = (ShaguTweaks and ShaguTweaks.libdebuff) or (pfUI and pfUI.api and pfUI.api.libdebuff)
    if lib and lib.UnitDebuff then
        for i = 1, 16 do
            local effect, rank, texture, stacks = lib:UnitDebuff("target", i)
            if not texture then break end
            if effect then
                local el = string.lower(effect)
                if string.find(el, target1) or (target2 and string.find(el, target2)) then
                    return true, stacks or 1
                end
            end
        end
    end

    for i = 1, 16 do
        scanTip:ClearLines()
        scanTip:SetUnitDebuff("target", i)
        local line = RaidSynergyScanTipTextLeft1 and RaidSynergyScanTipTextLeft1:GetText()
        if not line then break end
        local ll = string.lower(line)
        if string.find(ll, target1) or (target2 and string.find(ll, target2)) then
            local count = 1
            local _, apps = UnitDebuff("target", i)
            if apps and apps > 1 then count = apps end
            return true, count
        end
    end

    return false, 0
end

-- ----------------------------------------------------------------------------
-- 3. Two Independent Frames (Buffs Frame & Debuffs Frame)
-- ----------------------------------------------------------------------------

-- FRAME 1: BUFFS ON ME
local buffsFrame = CreateFrame("Frame", "RaidSynergyBuffsFrame", UIParent)
buffsFrame:SetWidth(200)
buffsFrame:SetHeight(28)
buffsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
buffsFrame:SetClampedToScreen(true)
buffsFrame:SetMovable(true)
buffsFrame:EnableMouse(true)
buffsFrame:SetScale(RaidSynergyDB.buffsScale or 0.85)

-- FRAME 2: DEBUFFS ON TARGET
local debuffsFrame = CreateFrame("Frame", "RaidSynergyDebuffsFrame", UIParent)
debuffsFrame:SetWidth(200)
debuffsFrame:SetHeight(28)
debuffsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
debuffsFrame:SetClampedToScreen(true)
debuffsFrame:SetMovable(true)
debuffsFrame:EnableMouse(true)
debuffsFrame:SetScale(RaidSynergyDB.debuffsScale or 0.85)

local RebuildBars -- Forward declaration
local UpdateLockVisuals -- Forward declaration

-- Helper to setup smooth dragging on any element
local function MakeDraggable(trigger, targetFrame, dbKey)
    trigger:EnableMouse(true)
    trigger:RegisterForDrag("LeftButton")
    trigger:SetScript("OnDragStart", function()
        if not RaidSynergyDB.locked then
            targetFrame:StartMoving()
            targetFrame.isMoving = true
        end
    end)
    trigger:SetScript("OnDragStop", function()
        if targetFrame.isMoving then
            targetFrame:StopMovingOrSizing()
            targetFrame.isMoving = false
            local point, _, relPoint, x, y = targetFrame:GetPoint()
            RaidSynergyDB[dbKey] = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)
end

MakeDraggable(buffsFrame, buffsFrame, "buffsPos")
MakeDraggable(debuffsFrame, debuffsFrame, "debuffsPos")

-- ----------------------------------------------------------------------------
-- 4. Interactive Anchor Bars with Sizing [-] [+] & Test Mode & Rows Selector
-- ----------------------------------------------------------------------------
local function CreateAnchor(parent, labelText, dbKey, scaleKey, hasTestBtn, hasRowsBtn)
    local anchor = CreateFrame("Button", nil, parent)
    anchor:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 3)
    anchor:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 3)
    anchor:SetHeight(18)
    anchor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    anchor:SetBackdropColor(0.08, 0.08, 0.12, 0.9)
    anchor:SetBackdropBorderColor(0.9, 0.8, 0.2, 1)

    MakeDraggable(anchor, parent, dbKey)

    local txt = anchor:CreateFontString(nil, "OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    txt:SetPoint("LEFT", anchor, "LEFT", 4, 0)
    txt:SetTextColor(1, 0.9, 0.3, 1)
    txt:SetText(labelText)
    anchor.txt = txt

    -- Sizing Controls: [-]  [ 85% ]  [+]
    local incBtn = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
    incBtn:SetWidth(15)
    incBtn:SetHeight(14)
    incBtn:SetPoint("RIGHT", anchor, "RIGHT", -2, 0)
    incBtn:SetText("+")

    local scaleValText = anchor:CreateFontString(nil, "OVERLAY")
    scaleValText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    scaleValText:SetWidth(28)
    scaleValText:SetJustifyH("CENTER")
    scaleValText:SetPoint("RIGHT", incBtn, "LEFT", -1, 0)
    scaleValText:SetTextColor(1, 1, 1, 1)
    anchor.scaleValText = scaleValText

    local function UpdateScaleText()
        local s = RaidSynergyDB[scaleKey] or 0.85
        scaleValText:SetText(string.format("%d%%", math.floor(s * 100 + 0.5)))
    end
    UpdateScaleText()

    local decBtn = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
    decBtn:SetWidth(15)
    decBtn:SetHeight(14)
    decBtn:SetPoint("RIGHT", scaleValText, "LEFT", -1, 0)
    decBtn:SetText("-")

    decBtn:SetScript("OnClick", function()
        local s = RaidSynergyDB[scaleKey] or 0.85
        s = s - 0.05
        if s < 0.4 then s = 0.4 end
        RaidSynergyDB[scaleKey] = s
        parent:SetScale(s)
        UpdateScaleText()
    end)

    incBtn:SetScript("OnClick", function()
        local s = RaidSynergyDB[scaleKey] or 0.85
        s = s + 0.05
        if s > 2.0 then s = 2.0 end
        RaidSynergyDB[scaleKey] = s
        parent:SetScale(s)
        UpdateScaleText()
    end)

    -- Mousewheel sizing directly on anchor
    anchor:EnableMouseWheel(true)
    anchor:SetScript("OnMouseWheel", function()
        local delta = arg1
        local s = RaidSynergyDB[scaleKey] or 0.85
        s = s + (delta * 0.05)
        if s < 0.4 then s = 0.4 end
        if s > 2.0 then s = 2.0 end
        RaidSynergyDB[scaleKey] = s
        parent:SetScale(s)
        UpdateScaleText()
    end)

    -- Test Mode Button (on Buffs anchor)
    if hasTestBtn then
        local testBtn = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        testBtn:SetWidth(56)
        testBtn:SetHeight(14)
        testBtn:SetPoint("RIGHT", decBtn, "LEFT", -4, 0)

        local function UpdateTestBtn()
            if RaidSynergyDB.testMode then
                testBtn:SetText("|cff20ff20Test:ON|r")
            else
                testBtn:SetText("|cffff5050Test:OFF|r")
            end
        end
        UpdateTestBtn()

        testBtn:SetScript("OnClick", function()
            RaidSynergyDB.testMode = not RaidSynergyDB.testMode
            UpdateTestBtn()
            if RebuildBars then RebuildBars() end
            if RaidSynergyDB.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Test Mode |cff20ff20ON|r (all raid buffs & debuffs active at 5 stacks).")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Test Mode |cffff4040OFF|r (live scanning restored).")
            end
        end)
        anchor.testBtn = testBtn
        anchor.UpdateTestBtn = UpdateTestBtn
    end

    -- Rows Selector Button (on Debuffs anchor: 1, 2, or 3 rows!)
    if hasRowsBtn then
        local rowsBtn = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        rowsBtn:SetWidth(52)
        rowsBtn:SetHeight(14)
        rowsBtn:SetPoint("RIGHT", decBtn, "LEFT", -4, 0)

        local function UpdateRowsBtn()
            local r = RaidSynergyDB.debuffRows or 2
            rowsBtn:SetText(string.format("Rows:%d", r))
        end
        UpdateRowsBtn()

        rowsBtn:SetScript("OnClick", function()
            local r = RaidSynergyDB.debuffRows or 2
            r = r + 1
            if r > 3 then r = 1 end
            RaidSynergyDB.debuffRows = r
            UpdateRowsBtn()
            if RebuildBars then RebuildBars() end
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Target debuffs arranged in " .. r .. " row(s).")
        end)
        anchor.rowsBtn = rowsBtn
        anchor.UpdateRowsBtn = UpdateRowsBtn
    end

    return anchor
end

buffsFrame.anchor = CreateAnchor(buffsFrame, "Buffs (You)", "buffsPos", "buffsScale", true, false)
debuffsFrame.anchor = CreateAnchor(debuffsFrame, "Target Debuffs", "debuffsPos", "debuffsScale", false, true)

UpdateLockVisuals = function()
    if RaidSynergyDB.locked then
        buffsFrame.anchor:Hide()
        debuffsFrame.anchor:Hide()
    else
        buffsFrame.anchor:Show()
        debuffsFrame.anchor:Show()
        if buffsFrame.anchor.UpdateTestBtn then buffsFrame.anchor.UpdateTestBtn() end
        if debuffsFrame.anchor.UpdateRowsBtn then debuffsFrame.anchor.UpdateRowsBtn() end
    end
end

-- ----------------------------------------------------------------------------
-- 5. Shared Icon Factory & Pools
-- ----------------------------------------------------------------------------
local function CreateActionIcon(parent, isDebuff, dbKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(28)
    btn:SetHeight(28)

    -- Draggable when unlocked directly by clicking any icon!
    MakeDraggable(btn, parent, dbKey)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture(0.04, 0.04, 0.04, 0.8)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -7, 7)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 7, -7)
    border:Hide()
    btn.border = border

    local stackText = btn:CreateFontString(nil, "OVERLAY")
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    stackText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    stackText:SetTextColor(1, 1, 0.2, 1)
    btn.stackText = stackText

    btn.isDebuff = isDebuff

    btn:SetScript("OnEnter", function()
        if not this.spellInfo then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local info = this.spellInfo
        local color = info.isDebuff and "|cffff6060[Debuff on Target]|r" or "|cff60ff60[Buff on You]|r"
        GameTooltip:AddLine(info.name .. " " .. color, 1, 1, 1)
        if info.class then
            GameTooltip:AddLine("Provided by: |cffffd200" .. info.class .. "|r", 0.9, 0.9, 0.9)
        end
        if info.desc then
            GameTooltip:AddLine(info.desc, 0.8, 0.8, 0.8, 1)
        end
        if this.isActive then
            local extra = (this.stacks and this.stacks > 1) and (" (Stacks: " .. this.stacks .. ")") or ""
            GameTooltip:AddLine("Status: |cff20ff20ACTIVE|r" .. extra, 0.2, 1, 0.2)
        else
            if info.isDebuff then
                GameTooltip:AddLine("Status: |cffff4040MISSING ON TARGET|r", 1, 0.3, 0.3)
            else
                GameTooltip:AddLine("Status: |cffff4040MISSING ON YOU|r", 1, 0.3, 0.3)
            end
        end
        if not RaidSynergyDB.locked then
            GameTooltip:AddLine("|cff88ff88(Unlocked: Left-Click & Drag to reposition)|r", 0.5, 1, 0.5)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local buffIcons = {}
local debuffIcons = {}

-- ----------------------------------------------------------------------------
-- 6. Roster Scanning & Dynamic Row Population
-- ----------------------------------------------------------------------------
local activeClasses = {}

local function ScanRoster()
    activeClasses = {}

    -- In Test Mode, activate ALL 9 classes!
    if RaidSynergyDB.testMode then
        for _, cls in ipairs(CLASS_ORDER) do
            activeClasses[cls] = true
        end
        return
    end

    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()

    -- 1. Scan Player
    local _, playerClass = UnitClass("player")
    if playerClass then
        activeClasses[playerClass] = true
    end

    -- 2. Scan Raid or Party
    if numRaid > 0 then
        for i = 1, numRaid do
            local _, cls = UnitClass("raid" .. i)
            if cls then activeClasses[cls] = true end
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local _, cls = UnitClass("party" .. i)
            if cls then activeClasses[cls] = true end
        end
    end
end

local function UpdateAuraStates()
    if IsInPvPInstance() and not RaidSynergyDB.testMode then
        if buffsFrame:IsShown() then buffsFrame:Hide() end
        if debuffsFrame:IsShown() then debuffsFrame:Hide() end
        return
    else
        if not buffsFrame:IsShown() and not RaidSynergyDB.hidden then
            buffsFrame:Show()
            debuffsFrame:Show()
        end
    end

    -- 1. Update Buffs on Player
    for _, btn in ipairs(buffIcons) do
        if btn:IsShown() and btn.spellInfo then
            local info = btn.spellInfo
            local active, stacks = CheckBuffActive(info.name, info.alt)
            btn.isActive = active
            btn.stacks = stacks
            if active then
                btn.icon:SetAlpha(1.0)
                btn.icon:SetDesaturated(false)
                btn.border:SetVertexColor(0.2, 1.0, 0.3, 1)
                btn.border:Show()
                if stacks and stacks > 1 then
                    btn.stackText:SetText(stacks)
                else
                    btn.stackText:SetText("")
                end
            else
                btn.icon:SetAlpha(0.25)
                btn.icon:SetDesaturated(true)
                btn.border:Hide()
                btn.stackText:SetText("")
            end
        end
    end

    -- 2. Update Debuffs on Target
    local hasEnemy = UnitExists("target") and not UnitIsFriend("player", "target")
    if RaidSynergyDB.testMode then hasEnemy = true end

    for _, btn in ipairs(debuffIcons) do
        if btn:IsShown() and btn.spellInfo then
            local info = btn.spellInfo
            local active, stacks = false, 0
            if hasEnemy then
                active, stacks = CheckDebuffActive(info.name, info.alt, info.maxStacks)
            end
            btn.isActive = active
            btn.stacks = stacks
            if active then
                btn.icon:SetAlpha(1.0)
                btn.icon:SetDesaturated(false)
                btn.border:SetVertexColor(1.0, 0.8, 0.1, 1)
                btn.border:Show()
                if stacks and stacks > 1 then
                    btn.stackText:SetText(stacks)
                else
                    btn.stackText:SetText("")
                end
            else
                btn.icon:SetAlpha(0.25)
                btn.icon:SetDesaturated(true)
                btn.border:Hide()
                btn.stackText:SetText("")
            end
        end
    end
end

RebuildBars = function()
    if IsInPvPInstance() and not RaidSynergyDB.testMode then
        buffsFrame:Hide()
        debuffsFrame:Hide()
        return
    else
        if not buffsFrame:IsShown() and not RaidSynergyDB.hidden then
            buffsFrame:Show()
            debuffsFrame:Show()
        end
    end

    ScanRoster()

    -- Gather combined list of all buffs and debuffs from ALL present classes
    local combinedBuffs = {}
    local combinedDebuffs = {}

    for _, classKey in ipairs(CLASS_ORDER) do
        if activeClasses[classKey] then
            local data = CLASS_SPELLS[classKey]
            if data then
                if data.buffs then
                    for _, b in ipairs(data.buffs) do
                        table.insert(combinedBuffs, b)
                    end
                end
                if data.debuffs then
                    for _, d in ipairs(data.debuffs) do
                        table.insert(combinedDebuffs, d)
                    end
                end
            end
        end
    end

    -- 1. Populate Buffs Row
    for _, btn in ipairs(buffIcons) do btn:Hide() end
    local iconSize = 28
    local gap = 4
    local buffCount = table.getn(combinedBuffs)

    for i = 1, buffCount do
        if not buffIcons[i] then
            buffIcons[i] = CreateActionIcon(buffsFrame, false, "buffsPos")
        end
        local btn = buffIcons[i]
        btn.spellInfo = combinedBuffs[i]
        btn.icon:SetTexture(combinedBuffs[i].icon)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", buffsFrame, "LEFT", (i - 1) * (iconSize + gap), 0)
        btn:Show()
    end

    local buffsWidth = math.max(buffCount * (iconSize + gap) - gap, 28)
    buffsFrame:SetWidth(buffsWidth)
    buffsFrame:SetHeight(iconSize)

    -- 2. Populate Debuffs Row (Configurable in 1, 2, or 3 rows!)
    for _, btn in ipairs(debuffIcons) do btn:Hide() end
    local debuffCount = table.getn(combinedDebuffs)
    local numRows = RaidSynergyDB.debuffRows or 2
    if numRows < 1 then numRows = 1 end
    if numRows > 3 then numRows = 3 end

    local cols = math.ceil(debuffCount / numRows)
    if cols < 1 then cols = 1 end

    local actualRows = 0
    for i = 1, debuffCount do
        if not debuffIcons[i] then
            debuffIcons[i] = CreateActionIcon(debuffsFrame, true, "debuffsPos")
        end
        local btn = debuffIcons[i]
        btn.spellInfo = combinedDebuffs[i]
        btn.icon:SetTexture(combinedDebuffs[i].icon)

        local col = math.mod(i - 1, cols)
        local row = math.floor((i - 1) / cols)
        if row + 1 > actualRows then actualRows = row + 1 end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", debuffsFrame, "TOPLEFT", col * (iconSize + gap), -(row * (iconSize + gap)))
        btn:Show()
    end

    local debuffsWidth = math.max(cols * (iconSize + gap) - gap, 28)
    local debuffsHeight = math.max(actualRows * (iconSize + gap) - gap, 28)
    debuffsFrame:SetWidth(debuffsWidth)
    debuffsFrame:SetHeight(debuffsHeight)

    UpdateLockVisuals()
    UpdateAuraStates()
end

-- ----------------------------------------------------------------------------
-- 7. Event Listeners & Periodic Refresh
-- ----------------------------------------------------------------------------
RS:RegisterEvent("PLAYER_ENTERING_WORLD")
RS:RegisterEvent("ZONE_CHANGED_NEW_AREA")
RS:RegisterEvent("ZONE_CHANGED")
RS:RegisterEvent("PARTY_MEMBERS_CHANGED")
RS:RegisterEvent("RAID_ROSTER_UPDATE")
RS:RegisterEvent("PLAYER_TARGET_CHANGED")
RS:RegisterEvent("UNIT_AURA")
RS:RegisterEvent("VARIABLES_LOADED")

RS:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if RaidSynergyDB.buffsPos and RaidSynergyDB.buffsPos.point then
            local p = RaidSynergyDB.buffsPos
            buffsFrame:ClearAllPoints()
            buffsFrame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
        end
        if RaidSynergyDB.debuffsPos and RaidSynergyDB.debuffsPos.point then
            local p = RaidSynergyDB.debuffsPos
            debuffsFrame:ClearAllPoints()
            debuffsFrame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
        end
        if RaidSynergyDB.buffsScale then buffsFrame:SetScale(RaidSynergyDB.buffsScale) end
        if RaidSynergyDB.debuffsScale then debuffsFrame:SetScale(RaidSynergyDB.debuffsScale) end
        UpdateLockVisuals()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        RebuildBars()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateAuraStates()
    elseif event == "UNIT_AURA" then
        if arg1 == "player" or arg1 == "target" then
            UpdateAuraStates()
        end
    end
end)

local timer = 0
buffsFrame:SetScript("OnUpdate", function()
    timer = timer + (arg1 or 0.05)
    if timer >= 0.4 then
        timer = 0
        UpdateAuraStates()
    end
end)

-- ----------------------------------------------------------------------------
-- 8. Minimap Button
-- ----------------------------------------------------------------------------
local minimapBtn = CreateFrame("Button", "RaidSynergyMinimapBtn", Minimap)
minimapBtn:SetWidth(32)
minimapBtn:SetHeight(32)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(9)

local mIcon = minimapBtn:CreateTexture(nil, "BACKGROUND")
mIcon:SetTexture("Interface\\Icons\\Spell_Holy_AuraMastery")
mIcon:SetWidth(20)
mIcon:SetHeight(20)
mIcon:SetPoint("CENTER", minimapBtn, "CENTER", 0, 0)

local mBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mBorder:SetWidth(52)
mBorder:SetHeight(52)
mBorder:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 0, 0)

local mHighlight = minimapBtn:CreateTexture(nil, "HIGHLIGHT")
mHighlight:SetWidth(32)
mHighlight:SetHeight(32)
mHighlight:SetPoint("CENTER", minimapBtn, "CENTER", 0, 0)
mHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mHighlight:SetBlendMode("ADD")

local function UpdateMinimapPos(angle)
    angle = tonumber(angle) or (RaidSynergyDB and tonumber(RaidSynergyDB.minimapAngle)) or 2.1
    local rad = 80
    local x = math.cos(angle) * rad
    local y = math.sin(angle) * rad
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local defaultAngle = 2.1
local curAngle = (RaidSynergyDB and RaidSynergyDB.minimapAngle) or defaultAngle
UpdateMinimapPos(curAngle)

minimapBtn:RegisterForDrag("LeftButton", "RightButton")
minimapBtn:SetScript("OnDragStart", function() this.isDragging = true end)
minimapBtn:SetScript("OnDragStop", function() this.isDragging = false end)
minimapBtn:SetScript("OnUpdate", function()
    if this.isDragging then
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.atan2(cy - my, cx - mx)
        UpdateMinimapPos(angle)
        if RaidSynergyDB then RaidSynergyDB.minimapAngle = angle end
    end
end)

minimapBtn:SetScript("OnClick", function()
    if IsShiftKeyDown() then
        if buffsFrame:IsShown() or debuffsFrame:IsShown() then
            buffsFrame:Hide()
            debuffsFrame:Hide()
            RaidSynergyDB.hidden = true
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons Hidden.")
        else
            RaidSynergyDB.hidden = false
            buffsFrame:Show()
            debuffsFrame:Show()
            RebuildBars()
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons Shown.")
        end
    elseif IsControlKeyDown() then
        RaidSynergyDB.testMode = not RaidSynergyDB.testMode
        RebuildBars()
        local tState = RaidSynergyDB.testMode and "|cff20ff20ON|r" or "|cffff4040OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Test Mode is now " .. tState)
    else
        RaidSynergyDB.locked = not RaidSynergyDB.locked
        UpdateLockVisuals()
        if RaidSynergyDB.locked then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons |cffff4040LOCKED|r (clean floating icons).")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons |cff20ff20UNLOCKED|r. Drag handles to move, click [-]/[+] to resize, click Rows to change grid.")
        end
    end
end)

minimapBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffffd200RaidSynergy|r (Buff & Debuff Monitor)")
    GameTooltip:AddLine("|cffffffffClick:|r Lock / Unlock dragging", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cffffffffCtrl + Click:|r Toggle Test Mode (All Buffs ON)", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cffffffffShift + Click:|r Show / Hide floating bars", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("|cffffffffDrag Button:|r Move around Minimap", 0.7, 0.7, 0.7)
    local state = RaidSynergyDB.locked and "|cffff4040Locked|r" or "|cff20ff20Unlocked (Draggable)|r"
    local tState = RaidSynergyDB.testMode and "|cff20ff20ON|r" or "|cffff4040OFF|r"
    GameTooltip:AddLine("Lock State: " .. state, 1, 1, 1)
    GameTooltip:AddLine("Test Mode: " .. tState, 1, 1, 1)
    if IsInPvPInstance() then
        GameTooltip:AddLine("|cffff4040Disabled inside PvP / Arena|r", 1, 0.4, 0.4)
    end
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

UpdateMinimapPos()

-- ----------------------------------------------------------------------------
-- 9. Slash Commands: /rs or /raidsynergy
-- ----------------------------------------------------------------------------
SLASH_RAIDSYNERGY1 = "/raidsynergy"
SLASH_RAIDSYNERGY2 = "/rs"
SlashCmdList["RAIDSYNERGY"] = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "test" then
        RaidSynergyDB.testMode = not RaidSynergyDB.testMode
        RebuildBars()
        local tState = RaidSynergyDB.testMode and "|cff20ff20ON|r" or "|cffff4040OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Test Mode is now " .. tState)
    elseif string.find(cmd, "^rows") or string.find(cmd, "^row") then
        local _, _, val = string.find(cmd, "row[s]?%s+(%d+)")
        local num = tonumber(val)
        if num and num >= 1 and num <= 3 then
            RaidSynergyDB.debuffRows = num
            if debuffsFrame.anchor and debuffsFrame.anchor.UpdateRowsBtn then
                debuffsFrame.anchor.UpdateRowsBtn()
            end
            RebuildBars()
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Target debuffs arranged into " .. num .. " row(s).")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Usage: /rs rows 1, /rs rows 2, or /rs rows 3")
        end
    elseif cmd == "lock" then
        RaidSynergyDB.locked = true
        UpdateLockVisuals()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons LOCKED.")
    elseif cmd == "unlock" or cmd == "move" then
        RaidSynergyDB.locked = false
        UpdateLockVisuals()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons UNLOCKED. Drag the yellow handles to position each bar.")
    elseif cmd == "reset" then
        buffsFrame:ClearAllPoints()
        buffsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
        debuffsFrame:ClearAllPoints()
        debuffsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
        RaidSynergyDB.buffsPos = nil
        RaidSynergyDB.debuffsPos = nil
        RaidSynergyDB.buffsScale = 0.85
        RaidSynergyDB.debuffsScale = 0.85
        RaidSynergyDB.debuffRows = 2
        buffsFrame:SetScale(0.85)
        debuffsFrame:SetScale(0.85)
        buffsFrame:Show()
        debuffsFrame:Show()
        RebuildBars()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Positions, sizes, and rows reset to default.")
    elseif string.find(cmd, "^scale") then
        local _, _, val = string.find(cmd, "scale%s+([%d%.]+)")
        local num = tonumber(val)
        if num and num >= 0.4 and num <= 2.0 then
            RaidSynergyDB.buffsScale = num
            RaidSynergyDB.debuffsScale = num
            buffsFrame:SetScale(num)
            debuffsFrame:SetScale(num)
            RebuildBars()
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Scale set to " .. num)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Usage: /rs scale 0.5 to 1.5")
        end
    else
        -- Default toggle lock/unlock
        RaidSynergyDB.locked = not RaidSynergyDB.locked
        UpdateLockVisuals()
        if RaidSynergyDB.locked then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons LOCKED (borderless floating icons).")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200RaidSynergy:|r Icons UNLOCKED. Drag handles to move, click [-]/[+] to resize, click Rows to change grid.")
        end
    end
end
