--[[
    NameplatePvPBuffs.lua
    Displays high-priority enemy PvP buffs/cooldowns floating ABOVE enemy nameplates.
    Strictly separated from debuffs so they never collide or mix!
    Verified for Turtle WoW (1.12.1 Vanilla Plus).
]]
local _G = _G or getfenv(0)

-- Authentic Turtle WoW (1.12.1 Vanilla Plus) PvP Class Auras Table
local PVP_BUFFS = {
    -- 1. MAGE
    ["Ice Block"]             = { icon = "Interface\\Icons\\Spell_Frost_Frost", duration = 10, prio = 10, type = "IMMUNE" },
    ["Ice Barrier"]           = { icon = "Interface\\Icons\\Spell_Frost_IceBarrier", duration = 60, prio = 7, type = "DEF" },
    ["Combustion"]            = { icon = "Interface\\Icons\\Spell_Fire_SealOfFire", duration = 60, prio = 8, type = "OFF" },
    ["Arcane Power"]          = { icon = "Interface\\Icons\\Spell_Nature_Lightning", duration = 15, prio = 8, type = "OFF" },
    ["Presence of Mind"]      = { icon = "Interface\\Icons\\Spell_Nature_EnchantArmor", duration = 60, prio = 6, type = "OFF" },
    ["Mana Shield"]           = { icon = "Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility", duration = 60, prio = 5, type = "DEF" },

    -- 2. PALADIN
    ["Divine Shield"]         = { icon = "Interface\\Icons\\Spell_Holy_DivineIntervention", duration = 12, prio = 10, type = "IMMUNE" },
    ["Blessing of Protection"]= { icon = "Interface\\Icons\\Spell_Holy_SealOfProtection", duration = 10, prio = 9, type = "IMMUNE" },
    ["Blessing of Freedom"]   = { icon = "Interface\\Icons\\Spell_Holy_SealOfValor", duration = 16, prio = 8, type = "UTIL" },
    ["Holy Shield"]           = { icon = "Interface\\Icons\\Spell_Holy_BlessingOfProtection", duration = 10, prio = 6, type = "DEF" },

    -- 3. PRIEST
    ["Power Word: Shield"]    = { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", duration = 30, prio = 7, type = "DEF" },
    ["Power Infusion"]        = { icon = "Interface\\Icons\\Spell_Holy_PowerInfusion", duration = 15, prio = 8, type = "OFF" },
    ["Inner Focus"]           = { icon = "Interface\\Icons\\Spell_Frost_WindWalkOn", duration = 60, prio = 5, type = "UTIL" },
    ["Fear Ward"]             = { icon = "Interface\\Icons\\Spell_Holy_Excorcism", duration = 180, prio = 6, type = "UTIL" },

    -- 4. ROGUE
    ["Evasion"]               = { icon = "Interface\\Icons\\Spell_Shadow_ShadowWard", duration = 15, prio = 9, type = "DEF" },
    ["Vanish"]                = { icon = "Interface\\Icons\\Ability_Vanish", duration = 10, prio = 8, type = "DEF" },
    ["Sprint"]                = { icon = "Interface\\Icons\\Ability_Rogue_Sprint", duration = 15, prio = 6, type = "UTIL" },
    ["Adrenaline Rush"]       = { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate", duration = 15, prio = 8, type = "OFF" },
    ["Blade Flurry"]          = { icon = "Interface\\Icons\\Ability_Warrior_PunishingBlow", duration = 15, prio = 7, type = "OFF" },
    ["Cold Blood"]            = { icon = "Interface\\Icons\\Spell_Ice_Lament", duration = 60, prio = 7, type = "OFF" },

    -- 5. WARRIOR
    ["Shield Wall"]           = { icon = "Interface\\Icons\\Ability_Warrior_ShieldWall", duration = 10, prio = 10, type = "DEF" },
    ["Retaliation"]           = { icon = "Interface\\Icons\\Ability_Warrior_Challange", duration = 15, prio = 9, type = "OFF" },
    ["Recklessness"]          = { icon = "Interface\\Icons\\Ability_CriticalStrike", duration = 15, prio = 9, type = "OFF" },
    ["Berserker Rage"]        = { icon = "Interface\\Icons\\Spell_Nature_AncestralGuardian", duration = 10, prio = 7, type = "UTIL" },
    ["Last Stand"]            = { icon = "Interface\\Icons\\Spell_Holy_AshesToAshes", duration = 20, prio = 8, type = "DEF" },
    ["Death Wish"]            = { icon = "Interface\\Icons\\Spell_Shadow_DeathPact", duration = 30, prio = 8, type = "OFF" },
    ["Sweeping Strikes"]      = { icon = "Interface\\Icons\\Ability_Rogue_SliceDice", duration = 20, prio = 7, type = "OFF" },
    ["Shield Block"]          = { icon = "Interface\\Icons\\Ability_Defend", duration = 5, prio = 6, type = "DEF" },
    ["Bloodrage"]             = { icon = "Interface\\Icons\\Ability_Racial_BloodRage", duration = 10, prio = 5, type = "UTIL" },

    -- 6. DRUID
    ["Barkskin"]              = { icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem", duration = 15, prio = 9, type = "DEF" },
    ["Innervate"]             = { icon = "Interface\\Icons\\Spell_Nature_Lightning", duration = 20, prio = 8, type = "UTIL" },
    ["Nature's Swiftness"]    = { icon = "Interface\\Icons\\Spell_Nature_RavenForm", duration = 60, prio = 8, type = "OFF" },
    ["Frenzied Regeneration"] = { icon = "Interface\\Icons\\Ability_BullRush", duration = 10, prio = 7, type = "DEF" },
    ["Tiger's Fury"]          = { icon = "Interface\\Icons\\Ability_Mount_JungleTiger", duration = 6, prio = 5, type = "OFF" },
    ["Dash"]                  = { icon = "Interface\\Icons\\Ability_Druid_Dash", duration = 15, prio = 5, type = "UTIL" },

    -- 7. HUNTER
    ["Bestial Wrath"]         = { icon = "Interface\\Icons\\Ability_Druid_FerociousBite", duration = 18, prio = 10, type = "IMMUNE" },
    ["Deterrence"]            = { icon = "Interface\\Icons\\Ability_Whirlwind", duration = 10, prio = 8, type = "DEF" },
    ["Rapid Fire"]            = { icon = "Interface\\Icons\\Ability_Hunter_RunningShot", duration = 15, prio = 7, type = "OFF" },
    ["Quick Shots"]           = { icon = "Interface\\Icons\\Ability_Warrior_InnerRage", duration = 12, prio = 6, type = "OFF" },

    -- 8. WARLOCK
    ["Soul Link"]             = { icon = "Interface\\Icons\\Spell_Shadow_GatherShadows", duration = 600, prio = 7, type = "DEF" },
    ["Shadow Ward"]           = { icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", duration = 30, prio = 6, type = "DEF" },
    ["Fel Domination"]        = { icon = "Interface\\Icons\\Spell_Nature_RemoveCurse", duration = 15, prio = 6, type = "UTIL" },

    -- 9. SHAMAN
    ["Elemental Mastery"]     = { icon = "Interface\\Icons\\Spell_Nature_WispHeal", duration = 60, prio = 8, type = "OFF" },
    ["Grounding Totem Effect"]= { icon = "Interface\\Icons\\Spell_Nature_GroundingTotem", duration = 10, prio = 7, type = "DEF" },
}

local BORDER_COLORS = {
    ["IMMUNE"] = { 1.0, 0.85, 0.1, 1.0 }, -- Bright Golden Yellow (Total Immunities: Ice Block, Divine Shield, BoP, Bestial Wrath)
    ["DEF"]    = { 0.2, 0.7, 1.0, 1.0 },  -- Bright Cyan Blue (Defensive Reductions / Absorbs: Shield Wall, Barkskin, PW:S, Ice Barrier)
    ["OFF"]    = { 1.0, 0.2, 0.2, 1.0 },  -- Crimson Red (Burst Damage: Recklessness, Death Wish, Combustion, Arcane Power, Power Infusion)
    ["UTIL"]   = { 0.2, 1.0, 0.3, 1.0 },  -- Emerald Green (Speed / Freedom: Freedom, Berserker Rage, Sprint, Innervate)
}

-- Buff tracking cache: PvPBuffsCache[unitName][spellName] = { expires, icon, prio, type }
local PvPBuffsCache = {}

local function AddBuff(unitName, spellName)
    local info = PVP_BUFFS[spellName]
    if not info or not unitName or unitName == "" then return end
    if not PvPBuffsCache[unitName] then PvPBuffsCache[unitName] = {} end
    PvPBuffsCache[unitName][spellName] = {
        icon = info.icon,
        expires = GetTime() + info.duration,
        duration = info.duration,
        prio = info.prio,
        type = info.type,
    }
end

local function RemoveBuff(unitName, spellName)
    if PvPBuffsCache[unitName] and PvPBuffsCache[unitName][spellName] then
        PvPBuffsCache[unitName][spellName] = nil
    end
end

-- Hidden tooltip scanner to extract 100% accurate spell names (avoids icon collision bugs!)
local scanner = CreateFrame("GameTooltip", "PvPBuffScannerTooltip", UIParent, "GameTooltipTemplate")
scanner:SetOwner(UIParent, "ANCHOR_NONE")

local function ScanTargetBuffs()
    if not UnitExists("target") then return end
    local targetName = UnitName("target")
    if not targetName or targetName == "" then return end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 32 do
            local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "HELPFUL")
            if not aura then break end
            if aura.name and PVP_BUFFS[aura.name] then
                local rem = (aura.expirationTime and aura.expirationTime > 0) and (aura.expirationTime - GetTime()) or PVP_BUFFS[aura.name].duration
                if not PvPBuffsCache[targetName] then PvPBuffsCache[targetName] = {} end
                PvPBuffsCache[targetName][aura.name] = {
                    icon = aura.icon or PVP_BUFFS[aura.name].icon,
                    expires = GetTime() + rem,
                    duration = aura.duration or PVP_BUFFS[aura.name].duration,
                    prio = PVP_BUFFS[aura.name].prio,
                    type = PVP_BUFFS[aura.name].type,
                }
            end
        end
    else
        for i = 1, 32 do
            local tex = UnitBuff("target", i)
            if not tex then break end
            scanner:ClearLines()
            scanner:SetUnitBuff("target", i)
            local txt = _G["PvPBuffScannerTooltipTextLeft1"]
            local spellName = txt and txt:GetText()
            if spellName and PVP_BUFFS[spellName] then
                AddBuff(targetName, spellName)
            elseif not spellName then
                -- Fallback icon matching
                for name, info in pairs(PVP_BUFFS) do
                    if string.find(string.lower(tex), string.lower(string.gsub(info.icon, "Interface\\Icons\\", ""))) then
                        AddBuff(targetName, name)
                        break
                    end
                end
            end
        end
    end
end

-- Robust Combat Log Parser (Strictly separates self-buffs vs buffs cast on allies)
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFFS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_OTHER")

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" then
        ScanTargetBuffs()
    elseif event == "UNIT_AURA" then
        if arg1 == "target" then ScanTargetBuffs() end
    elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS" or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFFS" then
        if arg1 then
            -- 1. "Target gains Spell."
            local _, _, unit, spell = string.find(arg1, "^(.-) gains (.-)%.$")
            if unit and spell and PVP_BUFFS[spell] then
                AddBuff(unit, spell)
                return
            end

            -- 2. "Caster casts Spell on Recipient." (e.g. Paladin casts Freedom on Rogue)
            local _, _, caster, spellOn, recipient = string.find(arg1, "^(.-) casts (.-) on (.-)%.$")
            if recipient and spellOn and PVP_BUFFS[spellOn] then
                AddBuff(recipient, spellOn)
                return
            end

            -- 3. "Caster casts Spell." (Self-cast buff)
            local _, _, casterSelf, spellSelf = string.find(arg1, "^(.-) casts (.-)%.$")
            if casterSelf and spellSelf and PVP_BUFFS[spellSelf] then
                AddBuff(casterSelf, spellSelf)
                return
            end
        end
    elseif event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
        if arg1 then
            local _, _, spell, unit = string.find(arg1, "^(.-) fades from (.-)%.$")
            if unit and spell and PVP_BUFFS[spell] then
                RemoveBuff(unit, spell)
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Nameplate Attachment System (Physically Separated from Debuffs!)
-- ----------------------------------------------------------------------------
local ICON_SIZE = 22
local ICON_SPACING = 3

local function CreatePlateBuffRow(plate)
    local row = CreateFrame("Frame", nil, plate)
    row:SetWidth(ICON_SIZE * 4 + ICON_SPACING * 3)
    row:SetHeight(ICON_SIZE)

    -- ANCHORING RULE:
    -- Debuffs in ShaguPlates sit directly above plate.health (Y ~ 4-10px).
    -- We anchor this PvP Buff row ABOVE THE ENEMY'S NAME (plate.name or top of plate)!
    -- This guarantees a clean 2-tier display with zero overlap:
    --   [PvP BUFFS]  (Top Crown - Ice Block, BoP, Freedom, Evasion)
    --   [Enemy Name]
    --   [Debuffs]    (On health bar - Rend, Hamstring, Mortal Strike)
    --   [Health Bar]
    if plate.name then
        row:SetPoint("BOTTOM", plate.name, "TOP", 0, 4)
    else
        row:SetPoint("BOTTOM", plate, "TOP", 0, 20)
    end
    row:SetFrameStrata("HIGH")

    row.icons = {}
    for i = 1, 4 do
        local btn = CreateFrame("Frame", nil, row)
        btn:SetWidth(ICON_SIZE)
        btn:SetHeight(ICON_SIZE)
        btn:SetPoint("LEFT", row, "LEFT", (i - 1) * (ICON_SIZE + ICON_SPACING), 0)

        -- Dark background border backing
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture(0, 0, 0, 0.9)

        -- Icon texture (inset slightly for crisp border)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1.5, -1.5)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1.5, 1.5)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom in to remove default Blizzard icon borders
        btn.icon = tex

        -- Colored status border
        btn:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropBorderColor(1, 0.85, 0, 1)

        -- Countdown duration text
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        txt:SetTextColor(1, 1, 1, 1)
        btn.timerText = txt

        btn:Hide()
        row.icons[i] = btn
    end

    return row
end

local function UpdatePlateBuffs(row, unitName)
    if not unitName or not PvPBuffsCache[unitName] then
        row:Hide()
        return
    end

    local now = GetTime()
    local activeList = {}
    for spell, data in pairs(PvPBuffsCache[unitName]) do
        if data.expires > now then
            table.insert(activeList, {
                spell = spell,
                icon = data.icon,
                rem = data.expires - now,
                prio = data.prio or 5,
                type = data.type or "DEF",
            })
        else
            PvPBuffsCache[unitName][spell] = nil
        end
    end

    local count = table.getn(activeList)
    if count == 0 then
        row:Hide()
        return
    end

    -- Sort by priority (Immunities first, then high-threat cooldowns)
    table.sort(activeList, function(a, b) return a.prio > b.prio end)

    row:Show()
    local displayCount = math.min(count, 4)
    local totalWidth = displayCount * ICON_SIZE + (displayCount - 1) * ICON_SPACING
    row:SetWidth(totalWidth)

    for i = 1, 4 do
        local btn = row.icons[i]
        if i <= displayCount then
            local info = activeList[i]
            btn.icon:SetTexture(info.icon)
            local remSec = math.ceil(info.rem)
            btn.timerText:SetText(remSec > 0 and tostring(remSec) or "")

            -- Color code: Gold = Immune, Blue = Defense/Shield, Red = Burst, Green = Speed/Freedom
            local col = BORDER_COLORS[info.type] or { 1, 1, 1, 1 }
            btn:SetBackdropBorderColor(col[1], col[2], col[3], col[4])
            btn:Show()
        else
            btn:Hide()
        end
    end
end

-- Safely iterate ShaguPlates frames and attach to Name text
local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed < 0.15 then return end
    elapsed = 0

    for id = 1, 40 do
        local plate = _G["ShaguPlate" .. id]
        if plate and plate:IsShown() and plate.name then
            if not plate.pvpRow then
                plate.pvpRow = CreatePlateBuffRow(plate)
            end
            local unitName = plate.name:GetText()
            UpdatePlateBuffs(plate.pvpRow, unitName)
        elseif plate and plate.pvpRow then
            plate.pvpRow:Hide()
        end
    end
end)

-- Slash command to verify or test in-game
SLASH_PVPBUFFS1 = "/pvpbuffs"
SlashCmdList.PVPBUFFS = function(msg)
    if msg == "clear" then
        PvPBuffsCache = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCC[PvP Buffs]|r Cache cleared.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100========== [NAMEPLATE PVP BUFF TRACKER] ==========|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFFFFFStatus:|r Active & separated from debuffs.")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFFFFFLayout:|r Enemy Buffs display |cFF00FFCCABOVE player name|r (Crown).")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFFFFFColors:|r |cFFFFD100Gold=Immunity|r, |cFF3399FFBlue=Defensive|r, |cFFFF3333Red=Burst|r, |cFF33FF66Green=Freedom/Speed|r")
        DEFAULT_CHAT_FRAME:AddMessage("  |cFFFFFFFFCommand:|r Type |cFF00FFCC/pvpbuffs clear|r to reset active timers.")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100===================================================|r")
    end
end
