--[[
    OctoBiSPlanner.lua
    A complete virtual character paperdoll and BiS gear builder for OktoWoW / Turtle WoW.
    Indexes the entire AtlasLoot database to let you search every item, equip it virtually,
    apply enchants, and calculate your total stats in real-time.

    Author: Antigravity
    Version: 1.1
]]

local _G = _G or getfenv(0)
local Planner = CreateFrame("Frame", "OctoBiSPlannerFrame", UIParent)
OctoBiSPlanner = Planner

-- SavedVariables database
OctoBiSPlannerDB = OctoBiSPlannerDB or {}

-- ----------------------------------------------------------------------------
-- Constants & Slot Definitions
-- ----------------------------------------------------------------------------
local SLOTS = {
    -- Left Column (Armor)
    { id = 1,  name = "HEAD",       label = "Head",       col = 1, row = 1, token = "#s1#",  enchant = "HEAD",     icon = "Interface\\Icons\\INV_Helmet_06" },
    { id = 2,  name = "NECK",       label = "Neck",       col = 1, row = 2, token = "#s2#",                        icon = "Interface\\Icons\\INV_Jewelry_Necklace_07" },
    { id = 3,  name = "SHOULDER",   label = "Shoulder",   col = 1, row = 3, token = "#s3#",  enchant = "SHOULDER", icon = "Interface\\Icons\\INV_Shoulder_02" },
    { id = 4,  name = "BACK",       label = "Back",       col = 1, row = 4, token = "#s4#",  enchant = "BACK",     icon = "Interface\\Icons\\INV_Misc_Cape_19" },
    { id = 5,  name = "CHEST",      label = "Chest",      col = 1, row = 5, token = "#s5#",  enchant = "CHEST",    icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
    { id = 6,  name = "SHIRT",      label = "Shirt",      col = 1, row = 6, token = "#s6#",                        icon = "Interface\\Icons\\INV_Shirt_07" },
    { id = 7,  name = "TABARD",     label = "Tabard",     col = 1, row = 7, token = "#s7#",                        icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { id = 8,  name = "WRIST",      label = "Wrists",     col = 1, row = 8, token = "#s8#",  enchant = "WRIST",    icon = "Interface\\Icons\\INV_Bracer_07" },

    -- Right Column (Accessories & Armor)
    { id = 9,  name = "HANDS",      label = "Hands",      col = 2, row = 1, token = "#s9#",  enchant = "HANDS",    icon = "Interface\\Icons\\INV_Gauntlets_04" },
    { id = 10, name = "WAIST",      label = "Waist",      col = 2, row = 2, token = "#s10#",                       icon = "Interface\\Icons\\INV_Belt_03" },
    { id = 11, name = "LEGS",       label = "Legs",       col = 2, row = 3, token = "#s11#", enchant = "LEGS",     icon = "Interface\\Icons\\INV_Pants_02" },
    { id = 12, name = "FEET",       label = "Feet",       col = 2, row = 4, token = "#s12#", enchant = "FEET",     icon = "Interface\\Icons\\INV_Boots_01" },
    { id = 13, name = "FINGER1",    label = "Ring 1",     col = 2, row = 5, token = "#s13#",                       icon = "Interface\\Icons\\INV_Jewelry_Ring_03" },
    { id = 14, name = "FINGER2",    label = "Ring 2",     col = 2, row = 6, token = "#s13#",                       icon = "Interface\\Icons\\INV_Jewelry_Ring_03" },
    { id = 15, name = "TRINKET1",   label = "Trinket 1",  col = 2, row = 7, token = "#s14#",                       icon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01" },
    { id = 16, name = "TRINKET2",   label = "Trinket 2",  col = 2, row = 8, token = "#s14#",                       icon = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01" },

    -- Bottom Row (Weapons & Ranged)
    { id = 17, name = "MAINHAND",   label = "Main Hand",  col = 3, row = 1, isWeapon = true, enchant = "WEAPON",   icon = "Interface\\Icons\\INV_Sword_04" },
    { id = 18, name = "OFFHAND",    label = "Off Hand",   col = 3, row = 2, isOffhand = true, enchant = "OFFHAND", icon = "Interface\\Icons\\INV_Shield_04" },
    { id = 19, name = "RANGED",     label = "Ranged",     col = 3, row = 3, isRanged = true, enchant = "RANGED",   icon = "Interface\\Icons\\INV_Weapon_Bow_05" },
}

local INV_SLOT_MAP = {
    HEAD = "HeadSlot",
    NECK = "NeckSlot",
    SHOULDER = "ShoulderSlot",
    BACK = "BackSlot",
    CHEST = "ChestSlot",
    SHIRT = "ShirtSlot",
    TABARD = "TabardSlot",
    WRIST = "WristSlot",
    HANDS = "HandsSlot",
    WAIST = "WaistSlot",
    LEGS = "LegsSlot",
    FEET = "FeetSlot",
    FINGER1 = "Finger0Slot",
    FINGER2 = "Finger1Slot",
    TRINKET1 = "Trinket0Slot",
    TRINKET2 = "Trinket1Slot",
    MAINHAND = "MainHandSlot",
    OFFHAND = "SecondaryHandSlot",
    RANGED = "RangedSlot",
}

local QUALITY_COLORS = {
    [0] = { 0.6, 0.6, 0.6, "Poor" },
    [1] = { 1.0, 1.0, 1.0, "Common" },
    [2] = { 0.12, 1.0, 0.0, "Uncommon" },
    [3] = { 0.0, 0.44, 0.87, "Rare" },
    [4] = { 0.64, 0.21, 0.93, "Epic" },
    [5] = { 1.0, 0.5, 0.0, "Legendary" },
}

-- ----------------------------------------------------------------------------
-- Enchants Database
-- ----------------------------------------------------------------------------
local ENCHANTS = {
    HEAD = {
        { name = "Lesser Arcanum of Voracity (+8 Strength)",  str = 8 },
        { name = "Lesser Arcanum of Voracity (+8 Agility)",   agi = 8 },
        { name = "Lesser Arcanum of Constitution (+100 HP)",  sta = 10 },
        { name = "Presence of Might (+28 AP, +10 Defense)",   ap = 28, defense = 10 },
        { name = "Gift of Ferocity (+20 Energy / +5 Rage)",   desc = "+20 Energy / +5 Rage" },
        { name = "Syncretist's Sigil (+24 AP, +10 Stamina)",  ap = 24, sta = 10 },
        { name = "Presence of Sight (+18 Spell Dmg, +1% Spell Hit)", spellDmg = 18, spellHit = 1 },
    },
    SHOULDER = {
        { name = "Zandalar Signet of Might (+30 AP)",         ap = 30 },
        { name = "Might of the Scourge (+26 AP, +1% Crit)",   ap = 26, crit = 1 },
        { name = "Fortitude of the Scourge (+16 Armor, +100 HP)", armor = 16, sta = 10 },
        { name = "Zandalar Signet of Mojo (+18 Spell Dmg)",   spellDmg = 18 },
        { name = "Power of the Scourge (+15 Spell Dmg, +1% Spell Crit)", spellDmg = 15, spellCrit = 1 },
    },
    BACK = {
        { name = "Enchant Cloak - Lesser Agility (+3 Agi)",   agi = 3 },
        { name = "Enchant Cloak - Superior Defense (+70 Armor)", armor = 70 },
        { name = "Enchant Cloak - Greater Resistance (+5 All)", desc = "+5 All Res" },
        { name = "Enchant Cloak - Dodge (+1% Dodge)",         dodge = 1 },
        { name = "Enchant Cloak - Subtlety (-2% Threat)",     desc = "-2% Threat" },
    },
    CHEST = {
        { name = "Enchant Chest - Greater Stats (+4 All Stats)", str = 4, agi = 4, sta = 4, int = 4, spi = 4 },
        { name = "Enchant Chest - Major Health (+100 HP)",    sta = 10 },
        { name = "Enchant Chest - Major Mana (+100 Mana)",    desc = "+100 Mana" },
    },
    WRIST = {
        { name = "Enchant Bracer - Superior Strength (+9 Str)", str = 9 },
        { name = "Enchant Bracer - Superior Stamina (+9 Sta)",  sta = 9 },
        { name = "Enchant Bracer - Greater Agility (+7 Agi)",   agi = 7 },
        { name = "Enchant Bracer - Healing Power (+24 Healing)", healing = 24 },
        { name = "Enchant Bracer - Greater Intellect (+7 Int)", int = 7 },
    },
    HANDS = {
        { name = "Enchant Gloves - Superior Strength (+15 Str)", str = 15 },
        { name = "Enchant Gloves - Superior Agility (+15 Agi)",  agi = 15 },
        { name = "Enchant Gloves - Greater Agility (+7 Agi)",    agi = 7 },
        { name = "Enchant Gloves - Threat (+1% Threat)",         desc = "+1% Threat" },
        { name = "Enchant Gloves - Minor Haste (+1% Atk Speed)", desc = "+1% Haste" },
        { name = "Enchant Gloves - Healing Power (+30 Healing)", healing = 30 },
        { name = "Enchant Gloves - Fire / Frost / Shadow Power (+20)", spellDmg = 20 },
    },
    LEGS = {
        { name = "Lesser Arcanum of Voracity (+8 Strength)",  str = 8 },
        { name = "Lesser Arcanum of Voracity (+8 Agility)",   agi = 8 },
        { name = "Lesser Arcanum of Constitution (+100 HP)",  sta = 10 },
        { name = "Presence of Might (+28 AP, +10 Defense)",   ap = 28, defense = 10 },
        { name = "Syncretist's Sigil (+24 AP, +10 Stamina)",  ap = 24, sta = 10 },
        { name = "Presence of Sight (+18 Spell Dmg, +1% Spell Hit)", spellDmg = 18, spellHit = 1 },
    },
    FEET = {
        { name = "Enchant Boots - Greater Agility (+7 Agi)",  agi = 7 },
        { name = "Enchant Boots - Greater Stamina (+7 Sta)",  sta = 7 },
        { name = "Enchant Boots - Minor Speed (+8% Move Speed)", desc = "+8% Run Speed" },
        { name = "Enchant Boots - Spirit (+9 Spirit)",        spi = 9 },
    },
    WEAPON = {
        { name = "Enchant Weapon - Crusader (+100 Str Proc)", ap = 40, desc = "Crusader Proc" },
        { name = "Enchant 2H Weapon - Agility (+25 Agi)",     agi = 25 },
        { name = "Enchant Weapon - Agility (+15 Agi)",        agi = 15 },
        { name = "Enchant Weapon - Superior Striking (+5 Dmg)", desc = "+5 Weapon Dmg" },
        { name = "Enchant Weapon - Healing Power (+55 Healing)", healing = 55 },
        { name = "Enchant Weapon - Spell Power (+30 Spell Dmg)", spellDmg = 30 },
        { name = "Iron Counterweight (+3% Haste to 2H)",      desc = "+3% Haste" },
    },
    OFFHAND = {
        { name = "Enchant Shield - Greater Stamina (+7 Sta)", sta = 7 },
        { name = "Enchant Shield - Superior Defense (+30 Armor)", armor = 30 },
        { name = "Enchant Shield - Block (+2% Block)",        block = 2 },
        { name = "Enchant Weapon - Agility (+15 Agi - If 1H)", agi = 15 },
        { name = "Enchant Weapon - Crusader (If 1H Off-hand)", ap = 40, desc = "Crusader Proc" },
    },
    RANGED = {
        { name = "Biznicks 247x128 Accurascope (+3% Hit)",    hit = 3 },
        { name = "Sniper Scope (+7 Ranged Damage)",           desc = "+7 Ranged Dmg" },
    },
}

-- Current equipped virtual gear & enchants
local EquippedGear = {}
local EquippedEnchants = {}
local ActiveSlot = nil
local CurrentProfile = "Default"
local PendingStatUpdate = false
local ItemStatsCache = {}

-- ----------------------------------------------------------------------------
-- Tooltip Scanner for Accurate Item Stats
-- ----------------------------------------------------------------------------
local scanner = CreateFrame("GameTooltip", "OctoBiSScannerTooltip", UIParent, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ScanItemStats(itemID)
    if not itemID or itemID <= 0 then return {} end
    if ItemStatsCache[itemID] then
        return ItemStatsCache[itemID]
    end

    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanner:ClearLines()
    scanner:SetHyperlink("item:" .. itemID .. ":0:0:0")

    local numLines = scanner:NumLines() or 0
    if numLines == 0 then
        return {}
    end

    local stats = {
        str = 0, agi = 0, sta = 0, int = 0, spi = 0, armor = 0,
        ap = 0, hit = 0, crit = 0,
        defense = 0, dodge = 0, parry = 0, block = 0, blockValue = 0,
        spellDmg = 0, healing = 0, mp5 = 0,
    }

    local hasAnyStat = false

    for i = 1, numLines do
        local lineL = _G["OctoBiSScannerTooltipTextLeft" .. i]
        local lineR = _G["OctoBiSScannerTooltipTextRight" .. i]
        local pair = { lineL, lineR }
        for _, line in ipairs(pair) do
            if line then
                local text = line:GetText()
                if text and text ~= "" then
                    local clean = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
                    clean = string.gsub(clean, "|r", "")
                    clean = string.gsub(clean, "^%s+", "")

                    -- 1. All Stats
                    local _, _, v = string.find(clean, "%+(%d+)%s+[tT]o [aA]ll [sS]tats")
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+[aA]ll [sS]tats") end
                    if v then
                        local n = tonumber(v) or 0
                        stats.str = stats.str + n
                        stats.agi = stats.agi + n
                        stats.sta = stats.sta + n
                        stats.int = stats.int + n
                        stats.spi = stats.spi + n
                        hasAnyStat = true
                    end

                    -- 2. Primary Attributes
                    _, _, v = string.find(clean, "(%d+)%s+Strength")
                    if v then stats.str = stats.str + tonumber(v); hasAnyStat = true end

                    _, _, v = string.find(clean, "(%d+)%s+Agility")
                    if v then stats.agi = stats.agi + tonumber(v); hasAnyStat = true end

                    _, _, v = string.find(clean, "(%d+)%s+Stamina")
                    if v then stats.sta = stats.sta + tonumber(v); hasAnyStat = true end

                    _, _, v = string.find(clean, "(%d+)%s+Intellect")
                    if v then stats.int = stats.int + tonumber(v); hasAnyStat = true end

                    _, _, v = string.find(clean, "(%d+)%s+Spirit")
                    if v then stats.spi = stats.spi + tonumber(v); hasAnyStat = true end

                    -- 3. Armor (ignore "increases armor by")
                    if not string.find(clean, "by %d+ Armor") and not string.find(clean, "armor by") and not string.find(clean, "Armor by") then
                        _, _, v = string.find(clean, "(%d+)%s+Armor")
                        if v then stats.armor = stats.armor + tonumber(v); hasAnyStat = true end
                    end

                    -- 4. Attack Power
                    _, _, v = string.find(clean, "%+(%d+)%s+Attack Power")
                    if not v then _, _, v = string.find(clean, "[aA]ttack [pP]ower by (%d+)") end
                    if not v then _, _, v = string.find(clean, "[rR]anged [aA]ttack [pP]ower by (%d+)") end
                    if v then stats.ap = stats.ap + tonumber(v); hasAnyStat = true end

                    -- 5. Hit
                    _, _, v = string.find(clean, "chance to hit by (%d+)%%")
                    if not v then _, _, v = string.find(clean, "[hH]it %+(%d+)%%") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%%%s+[hH]it") end
                    if v then stats.hit = stats.hit + tonumber(v); hasAnyStat = true end

                    -- 6. Crit
                    _, _, v = string.find(clean, "critical strike by (%d+)%%")
                    if not v then _, _, v = string.find(clean, "[cC]rit %+(%d+)%%") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%%%s+[cC]rit") end
                    if v then stats.crit = stats.crit + tonumber(v); hasAnyStat = true end

                    -- 7. Defense
                    _, _, v = string.find(clean, "defense by (%d+)")
                    if not v then _, _, v = string.find(clean, "defense rating by (%d+)") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+Defense") end
                    if v then stats.defense = stats.defense + tonumber(v); hasAnyStat = true end

                    -- 8. Dodge
                    _, _, v = string.find(clean, "dodge.*by (%d+)%%")
                    if not v then _, _, v = string.find(clean, "%+(%d+)%%%s+[dD]odge") end
                    if v then stats.dodge = stats.dodge + tonumber(v); hasAnyStat = true end

                    -- 9. Parry
                    _, _, v = string.find(clean, "parry.*by (%d+)%%")
                    if not v then _, _, v = string.find(clean, "%+(%d+)%%%s+[pP]arry") end
                    if v then stats.parry = stats.parry + tonumber(v); hasAnyStat = true end

                    -- 10. Block Chance & Value
                    _, _, v = string.find(clean, "block attacks with a shield by (%d+)%%")
                    if not v then _, _, v = string.find(clean, "%+(%d+)%%%s+[bB]lock") end
                    if v then stats.block = stats.block + tonumber(v); hasAnyStat = true end

                    _, _, v = string.find(clean, "block value.*by (%d+)")
                    if not v then _, _, v = string.find(clean, "(%d+)%s+Block Value") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+Block Value") end
                    if v then stats.blockValue = stats.blockValue + tonumber(v); hasAnyStat = true end

                    -- 11. Spell Power / Spell Damage & Healing
                    _, _, v = string.find(clean, "damage and healing done by magical spells and effects by up to (%d+)")
                    if not v then _, _, v = string.find(clean, "damage done by magical spells and effects by up to (%d+)") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+[sS]pell [dD]amage") end
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+[sS]pell [pP]ower") end
                    if v then
                        local n = tonumber(v) or 0
                        stats.spellDmg = stats.spellDmg + n
                        stats.healing = stats.healing + n
                        hasAnyStat = true
                    end

                    -- 12. Healing
                    _, _, v = string.find(clean, "healing done by spells and effects by up to (%d+)")
                    if not v then _, _, v = string.find(clean, "%+(%d+)%s+[hH]ealing") end
                    if v then stats.healing = stats.healing + tonumber(v); hasAnyStat = true end

                    -- 13. MP5
                    _, _, v = string.find(clean, "(%d+)%s+[mM]ana per 5 sec")
                    if not v then _, _, v = string.find(clean, "Restores (%d+) [mM]ana per 5 sec") end
                    if v then stats.mp5 = stats.mp5 + tonumber(v); hasAnyStat = true end
                end
            end
        end
    end

    if hasAnyStat then
        ItemStatsCache[itemID] = stats
    end
    return stats
end

-- ----------------------------------------------------------------------------
-- AtlasLoot Database Indexing Engine
-- ----------------------------------------------------------------------------
local ItemDatabase = {}
local IsDatabaseIndexed = false

local function IndexAtlasLootData()
    if IsDatabaseIndexed then return end
    if not AtlasLoot_Data then return end

    for slotName in pairs({ HEAD=1, NECK=1, SHOULDER=1, BACK=1, CHEST=1, SHIRT=1, TABARD=1, WRIST=1, HANDS=1, WAIST=1, LEGS=1, FEET=1, FINGER=1, TRINKET=1, MAINHAND=1, OFFHAND=1, RANGED=1 }) do
        ItemDatabase[slotName] = {}
    end

    local seenItems = {}

    local function ParseEntry(v, cleanSource, sourceMinLvl, sourceMaxLvl)
        if type(v) ~= "table" then return end

        -- If nested array: v[1] is a table, recursively parse (handles sets and crafting tables)
        if type(v[1]) == "table" then
            for _, subEntry in ipairs(v) do
                ParseEntry(subEntry, cleanSource, sourceMinLvl, sourceMaxLvl)
            end
            return
        end

        local itemID = v[1]
        local isCraftSpell = false
        if type(itemID) == "string" and string.sub(itemID, 1, 1) == "s" then
            local spellID = tonumber(string.sub(itemID, 2))
            if spellID and AtlasLoot_Data and AtlasLoot_Data["Spells"] and AtlasLoot_Data["Spells"][spellID] then
                itemID = AtlasLoot_Data["Spells"][spellID]["craftItem"]
                isCraftSpell = true
            end
        end

        if type(itemID) ~= "number" or itemID <= 0 then return end
        if seenItems[itemID] then return end

        local rawDesc = (type(v[4]) == "string" and v[4]) or (type(v[2]) == "string" and v[2]) or ""

        -- Filter out world object loot containers that contain "Chest" in their name (e.g. Krom Stoutarm's Chest)
        local isChestObj = string.find(cleanSource, "FamilyChest") or string.find(cleanSource, "KromStoutarmChest") or string.find(cleanSource, "BaelogsChest") or string.find(cleanSource, "Tribute")

        -- Slot match check (AtlasLoot #s tags + crafting table names)
        local sHead     = string.find(rawDesc, "#s1#") or string.find(cleanSource, "Helm") or string.find(cleanSource, "Head")
        local sNeck     = string.find(rawDesc, "#s2#")
        local sShoulder = string.find(rawDesc, "#s3#") or string.find(cleanSource, "Shoulder")
        local sBack     = string.find(rawDesc, "#s4#") or string.find(cleanSource, "Cloak")
        local sChest    = string.find(rawDesc, "#s5#") or ((string.find(cleanSource, "Chest") or string.find(cleanSource, "Robe")) and not isChestObj)
        local sShirt    = string.find(rawDesc, "#s6#") or string.find(cleanSource, "Shirt")
        local sTabard   = string.find(rawDesc, "#s7#") or string.find(cleanSource, "Tabard")
        local sWrist    = string.find(rawDesc, "#s8#") or string.find(cleanSource, "Bracer")
        local sHands    = string.find(rawDesc, "#s9#") or string.find(cleanSource, "Glove")
        local sWaist    = string.find(rawDesc, "#s10#") or string.find(cleanSource, "Belt")
        local sLegs     = string.find(rawDesc, "#s11#") or string.find(cleanSource, "Pant") or string.find(cleanSource, "Leg")
        local sFeet     = string.find(rawDesc, "#s12#") or string.find(cleanSource, "Boot")
        local sFinger   = string.find(rawDesc, "#s13#") or string.find(cleanSource, "Ring")
        local sTrinket  = string.find(rawDesc, "#s14#") or string.find(cleanSource, "Trinket")
        local sMain     = string.find(rawDesc, "#h1#") or string.find(rawDesc, "#h2#") or string.find(rawDesc, "#h3#") or string.find(cleanSource, "Weapon")
        local sOff      = string.find(rawDesc, "#h1#") or string.find(rawDesc, "#h4#") or string.find(rawDesc, "#w8#") or string.find(rawDesc, "#s15#") or string.find(cleanSource, "Shield")
        local sRanged   = string.find(rawDesc, "#s16#") or string.find(rawDesc, "#w2#") or string.find(rawDesc, "#w3#") or string.find(rawDesc, "#w5#") or string.find(rawDesc, "#w11#") or string.find(rawDesc, "#w12#")

        if not (sHead or sNeck or sShoulder or sBack or sChest or sShirt or sTabard or sWrist or sHands or sWaist or sLegs or sFeet or sFinger or sTrinket or sMain or sOff or sRanged) then
            return
        end

        local rawName = (type(v[3]) == "string" and v[3]) or ""
        local icon = (type(v[2]) == "string" and not string.find(v[2], "#") and v[2]) or (type(v[4]) == "string" and not string.find(v[4], "#") and v[4]) or "INV_Misc_QuestionMark"

        -- Extract Quality & Name
        local _, _, qStr = string.find(rawName, "=q(%d)=")
        local quality = (qStr and tonumber(qStr)) or 1
        local cleanName = string.gsub(rawName, "=q%d=", "")
        cleanName = string.gsub(cleanName, "=ds=", "")
        if cleanName == "" or cleanName == " " then
            cleanName = "Item #" .. itemID
        end

        -- Extract Armor Type
        local armorType = nil
        if string.find(rawDesc, "#a4#") then armorType = "Plate"
        elseif string.find(rawDesc, "#a3#") then armorType = "Mail"
        elseif string.find(rawDesc, "#a2#") then armorType = "Leather"
        elseif string.find(rawDesc, "#a1#") then armorType = "Cloth"
        elseif string.find(cleanSource, "Tailoring") then armorType = "Cloth"
        elseif string.find(cleanSource, "Leather") then armorType = "Leather"
        elseif string.find(cleanSource, "Smithing") or string.find(cleanSource, "Blacksmithing") then
            armorType = "Plate"
        end

        -- Extract Weapon Type
        local weaponType = nil
        if string.find(rawDesc, "#w10#") then weaponType = "Sword"
        elseif string.find(rawDesc, "#w1#") then weaponType = "Axe"
        elseif string.find(rawDesc, "#w6#") then weaponType = "Mace"
        elseif string.find(rawDesc, "#w7#") then weaponType = "Polearm"
        elseif string.find(rawDesc, "#w4#") then weaponType = "Dagger"
        elseif string.find(rawDesc, "#w8#") then weaponType = "Shield"
        elseif string.find(rawDesc, "#w9#") then weaponType = "Staff"
        elseif string.find(rawDesc, "#w13#") then weaponType = "Fist"
        elseif sRanged then weaponType = "Ranged"
        end

        local fullIcon = icon
        if type(fullIcon) == "string" and not string.find(fullIcon, "\\") then
            fullIcon = "Interface\\Icons\\" .. fullIcon
        end

        -- Estimate level from craft skill requirement if available (=so1=XXX)
        local effLvl = 0
        local _, _, reqSkill = string.find(rawDesc, "=so1=(%d+)")
        if reqSkill then
            local sk = tonumber(reqSkill) or 0
            if sk <= 75 then effLvl = math.floor(sk / 5) + 1
            elseif sk <= 150 then effLvl = 15 + math.floor((sk - 75) / 5)
            elseif sk <= 225 then effLvl = 30 + math.floor((sk - 150) / 5)
            else effLvl = 45 + math.floor((sk - 225) / 5)
            end
        end

        local itemObj = {
            id = itemID,
            name = cleanName,
            quality = quality,
            icon = fullIcon,
            desc = rawDesc,
            armorType = armorType,
            weaponType = weaponType,
            source = cleanSource,
            sourceMinLvl = sourceMinLvl,
            sourceMaxLvl = sourceMaxLvl,
            effLevel = (effLvl > 0 and effLvl) or nil,
            reqLevel = (effLvl > 0 and effLvl) or sourceMinLvl or 0,
            itemLevel = 0,
        }

        seenItems[itemID] = true

        -- Insert into matching database slots
        if sHead then table.insert(ItemDatabase.HEAD, itemObj) end
        if sNeck then table.insert(ItemDatabase.NECK, itemObj) end
        if sShoulder then table.insert(ItemDatabase.SHOULDER, itemObj) end
        if sBack then table.insert(ItemDatabase.BACK, itemObj) end
        if sChest then table.insert(ItemDatabase.CHEST, itemObj) end
        if sShirt then table.insert(ItemDatabase.SHIRT, itemObj) end
        if sTabard then table.insert(ItemDatabase.TABARD, itemObj) end
        if sWrist then table.insert(ItemDatabase.WRIST, itemObj) end
        if sHands then table.insert(ItemDatabase.HANDS, itemObj) end
        if sWaist then table.insert(ItemDatabase.WAIST, itemObj) end
        if sLegs then table.insert(ItemDatabase.LEGS, itemObj) end
        if sFeet then table.insert(ItemDatabase.FEET, itemObj) end
        if sFinger then table.insert(ItemDatabase.FINGER, itemObj) end
        if sTrinket then table.insert(ItemDatabase.TRINKET, itemObj) end
        if sMain then table.insert(ItemDatabase.MAINHAND, itemObj) end
        if sOff then table.insert(ItemDatabase.OFFHAND, itemObj) end
        if sRanged then table.insert(ItemDatabase.RANGED, itemObj) end
    end

    local validTables = {
        "AtlasLootItems",
        "AtlasLootWBItems",
        "AtlasLootSetItems",
        "AtlasLootCrafting",
        "AtlasLootRepItems",
        "AtlasLootBGItems",
        "AtlasLootGeneralPvPItems",
        "AtlasLootWorldEvents",
    }
    for _, tblName in ipairs(validTables) do
        local dataSource = AtlasLoot_Data[tblName]
        if type(dataSource) == "table" then
            for dataID, data in pairs(dataSource) do
                if type(data) == "table" then
                    -- Resolve source title and level range ONCE per table
                    local cleanSource = tostring(dataID)
                    local sourceMinLvl = nil
                    local sourceMaxLvl = nil

                    local sourceInfo = nil
                    if AtlasLoot_TableNames and type(dataID) == "string" then
                        sourceInfo = AtlasLoot_TableNames[dataID] or AtlasLoot_TableNames[string.gsub(dataID, "C$", "")]
                    end

                    local skipTable = false
                    if sourceInfo then
                        local zone = sourceInfo[3] or sourceInfo[2] or ""
                        local _, _, minL, maxL = string.find(zone, "%[(%d+)%-(%d+)%]")
                        if minL and maxL then
                            sourceMinLvl = tonumber(minL)
                            sourceMaxLvl = tonumber(maxL)
                            -- Skip entire sub-level 20 dungeons
                            if sourceMaxLvl and sourceMaxLvl < 20 then
                                skipTable = true
                            end
                        elseif string.find(zone, "%[RAID%]") then
                            sourceMinLvl = 60
                            sourceMaxLvl = 60
                        end

                        if not skipTable then
                            local boss = sourceInfo[1] or ""
                            boss = string.gsub(boss, "|c%x%x%x%x%x%x%x%x", "")
                            boss = string.gsub(boss, "|r", "")
                            zone = string.gsub(zone, "|c%x%x%x%x%x%x%x%x", "")
                            zone = string.gsub(zone, "|r", "")

                            if boss ~= "" and zone ~= "" then
                                cleanSource = zone .. " (" .. boss .. ")"
                            elseif boss ~= "" then
                                cleanSource = boss
                            elseif zone ~= "" then
                                cleanSource = zone
                            end
                        end
                    end

                    if not skipTable then
                        for _, v in ipairs(data) do
                            ParseEntry(v, cleanSource, sourceMinLvl, sourceMaxLvl)
                        end
                    end
                end
            end
        end
    end

    IsDatabaseIndexed = true
end

-- ----------------------------------------------------------------------------
-- Main GUI Window Construction
-- ----------------------------------------------------------------------------
local SlotButtons = {}
local StatLabels = {}
local BrowserRows = {}
local FilterArmor = "ALL"
local FilterLevel = "ALL"
local SortMode = "LVL_ASC"
local FilterSearchText = ""
local CurrentBrowserItems = {}
local BrowserPage = 1
local ROWS_PER_PAGE = 7
local enchMenuFrame = nil
local UpdateSetUI = nil

local ArmorButtons = {}
local LevelButtons = {}
local SortButtonRef = nil

local function GetEffectiveLevel(item)
    if not item then return 0 end
    local gName, _, gQual, gMinLevel = GetItemInfo(item.id)
    if gMinLevel and type(gMinLevel) == "number" and gMinLevel > 0 then
        item.reqLevel = gMinLevel
        item.effLevel = gMinLevel
        return gMinLevel
    end
    if item.effLevel and type(item.effLevel) == "number" and item.effLevel > 0 then
        return item.effLevel
    end
    if item.reqLevel and type(item.reqLevel) == "number" and item.reqLevel > 0 then
        return item.reqLevel
    end
    local sMin = tonumber(item.sourceMinLvl) or 0
    if sMin > 0 then
        return sMin
    end
    item.effLevel = 0
    return 0
end

local function MatchesLevelFilter(effLvl, item, filter)
    if filter == "ALL" then return true end
    local eff = tonumber(effLvl) or 0
    local sMin = tonumber(item and item.sourceMinLvl) or 0
    local sMax = tonumber(item and item.sourceMaxLvl) or 0
    local req = tonumber(item and item.reqLevel) or 0

    local level = eff
    if level == 0 then level = req end

    if filter == "40+" then
        if level >= 40 then return true end
        if sMax >= 40 or sMin >= 38 then return true end
        if level == 0 and sMin == 0 and sMax == 0 then return true end -- allow uncached items from AtlasLoot
        return false
    elseif filter == "40-49" then
        if level >= 38 and level <= 49 then return true end
        -- Dungeon range overlap with [40, 49]
        if sMin > 0 and sMax > 0 then
            if sMin <= 49 and sMax >= 40 then return true end
        elseif sMin > 0 then
            if sMin >= 38 and sMin <= 49 then return true end
        end
        return false
    elseif filter == "50-59" then
        if level >= 50 and level <= 59 then return true end
        -- Dungeon range overlap with [50, 59]
        if sMin > 0 and sMax > 0 then
            if sMin <= 59 and sMax >= 50 then return true end
        elseif sMin > 0 then
            if sMin >= 50 and sMin <= 59 then return true end
        end
        return false
    elseif filter == "60" then
        if level >= 60 then return true end
        if sMax >= 60 or sMin >= 58 then return true end
        return false
    end
    return true
end

local function UpdateFilterButtons()
    for name, btn in pairs(ArmorButtons) do
        if name == FilterArmor then
            btn:SetBackdropColor(0.18, 0.45, 0.75, 0.95)
            btn:SetBackdropBorderColor(0.4, 0.8, 1.0, 1.0)
            btn.text:SetText("|cFFFFD100" .. name .. "|r")
        else
            btn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
            btn.text:SetText("|cFF888888" .. name .. "|r")
        end
    end
    for name, btn in pairs(LevelButtons) do
        if name == FilterLevel then
            btn:SetBackdropColor(0.18, 0.45, 0.75, 0.95)
            btn:SetBackdropBorderColor(0.4, 0.8, 1.0, 1.0)
            btn.text:SetText("|cFFFFD100" .. name .. "|r")
        else
            btn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
            btn.text:SetText("|cFF888888" .. name .. "|r")
        end
    end
    if SortButtonRef and SortButtonRef.text then
        if SortMode == "LVL_ASC" then
            SortButtonRef.text:SetText("|cFFFFD100Sort: Lvl ▲|r")
        elseif SortMode == "LVL_DESC" then
            SortButtonRef.text:SetText("|cFFFFD100Sort: Lvl ▼|r")
        else
            SortButtonRef.text:SetText("|cFFFFD100Sort: Qual|r")
        end
    end
end

local function UpdateStatSummary()
    local total = {
        str = 0, agi = 0, sta = 0, int = 0, spi = 0, armor = 0,
        ap = 0, hit = 0, crit = 0,
        defense = 0, dodge = 0, parry = 0, block = 0, blockValue = 0,
        spellDmg = 0, healing = 0, mp5 = 0,
    }

    local hasUncached = false

    -- 1. Sum up gear stats
    for slotName, item in pairs(EquippedGear) do
        if item and item.id then
            local s = ScanItemStats(item.id)
            local itemHadStat = false
            for k, val in pairs(s) do
                if total[k] then
                    total[k] = total[k] + val
                    if val > 0 then itemHadStat = true end
                end
            end
            if not itemHadStat and not ItemStatsCache[item.id] then
                hasUncached = true
            end
        end
    end

    -- 2. Sum up enchants
    for slotName, ench in pairs(EquippedEnchants) do
        if ench then
            for k, val in pairs(ench) do
                if total[k] and type(val) == "number" then
                    total[k] = total[k] + val
                end
            end
        end
    end

    PendingStatUpdate = hasUncached

    -- Update Stat display labels (2-column layout)
    if StatLabels.str then StatLabels.str:SetText(string.format("Str: |cFFFFFFFF%d|r", total.str)) end
    if StatLabels.agi then StatLabels.agi:SetText(string.format("Agi: |cFFFFFFFF%d|r", total.agi)) end
    if StatLabels.sta then StatLabels.sta:SetText(string.format("Sta: |cFFFFFFFF%d|r", total.sta)) end
    if StatLabels.int then StatLabels.int:SetText(string.format("Int: |cFFFFFFFF%d|r", total.int)) end
    if StatLabels.spi then StatLabels.spi:SetText(string.format("Spi: |cFFFFFFFF%d|r", total.spi)) end

    if StatLabels.armor then StatLabels.armor:SetText(string.format("Armor: |cFFFFFFFF%d|r", total.armor)) end
    if StatLabels.ap then StatLabels.ap:SetText(string.format("AP: |cFFFFD100%d|r", total.ap + (total.str * 2))) end
    if StatLabels.hit then StatLabels.hit:SetText(string.format("Hit: |cFF00FFCC+%d%%|r", total.hit)) end
    if StatLabels.crit then StatLabels.crit:SetText(string.format("Crit: |cFF00FFCC+%.1f%%|r", total.crit + (total.agi / 20))) end
    if StatLabels.def then StatLabels.def:SetText(string.format("Def: |cFF00FFCC+%d|r", total.defense)) end

    if StatLabels.dodge then StatLabels.dodge:SetText(string.format("Dodge: |cFF00FFCC+%.1f%%|r", total.dodge + (total.agi / 20))) end
    if StatLabels.parry then StatLabels.parry:SetText(string.format("Parry: |cFF00FFCC+%d%%|r", total.parry)) end
    if StatLabels.block then StatLabels.block:SetText(string.format("Block: |cFF00FFCC+%d%%|r", total.block)) end
    if StatLabels.bv then StatLabels.bv:SetText(string.format("BlkVal: |cFF00FFCC+%d|r", total.blockValue)) end

    if StatLabels.sp then StatLabels.sp:SetText(string.format("Spell: |cFFCC99FF+%d|r", total.spellDmg)) end
    if StatLabels.heal then StatLabels.heal:SetText(string.format("Heal: |cFF33FF66+%d|r", total.healing)) end
    if StatLabels.mp5 then StatLabels.mp5:SetText(string.format("MP5: |cFF66CCFF+%d|r", total.mp5)) end
end

local function HighlightActiveSlot()
    for name, b in pairs(SlotButtons) do
        local it = EquippedGear[name]
        if ActiveSlot and ActiveSlot.name == name then
            b:SetBackdropBorderColor(1.0, 0.85, 0.1, 1.0)
        elseif it then
            local qc = QUALITY_COLORS[it.quality] or QUALITY_COLORS[1]
            b:SetBackdropBorderColor(qc[1], qc[2], qc[3], 0.9)
        else
            b:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.7)
        end
    end
end

local function RefreshSlotDisplay(slotName)
    local btn = SlotButtons[slotName]
    if not btn then return end

    local item = EquippedGear[slotName]
    if item and item.icon then
        btn.icon:SetTexture(item.icon)
        btn.icon:SetVertexColor(1, 1, 1, 1)
        btn.icon:Show()
        btn.hasItem = true
    elseif btn.defaultIcon then
        btn.icon:SetTexture(btn.defaultIcon)
        btn.icon:SetVertexColor(0.28, 0.28, 0.32, 0.5)
        btn.icon:Show()
        btn.hasItem = false
    else
        btn.icon:Hide()
        btn.hasItem = false
    end

    HighlightActiveSlot()

    -- Enchant text
    local ench = EquippedEnchants[slotName]
    if btn.enchButton and btn.enchButton.text then
        if ench then
            local shortName = string.sub(ench.name, 1, 12)
            btn.enchButton.text:SetText("|cFF00FFCC" .. shortName .. "|r")
        else
            btn.enchButton.text:SetText("|cFF888888[Enchant]|r")
        end
    end

    -- Save to DB
    OctoBiSPlannerDB = OctoBiSPlannerDB or {}
    if not OctoBiSPlannerDB[CurrentProfile] then
        OctoBiSPlannerDB[CurrentProfile] = {}
    end
    OctoBiSPlannerDB[CurrentProfile].gear = EquippedGear
    OctoBiSPlannerDB[CurrentProfile].enchants = EquippedEnchants

    UpdateStatSummary()
end

local function UpdateBrowserList()
    if not ActiveSlot then return end

    local querySlot = ActiveSlot.name
    if querySlot == "FINGER1" or querySlot == "FINGER2" then querySlot = "FINGER" end
    if querySlot == "TRINKET1" or querySlot == "TRINKET2" then querySlot = "TRINKET" end

    local rawList = ItemDatabase[querySlot] or {}
    CurrentBrowserItems = {}

    local searchLower = string.lower(FilterSearchText or "")
    local isNonArmorSlot = (querySlot == "BACK" or querySlot == "NECK" or querySlot == "FINGER" or querySlot == "TRINKET" or querySlot == "SHIRT" or querySlot == "TABARD")

    for _, it in ipairs(rawList) do
        local matchArmor = isNonArmorSlot or (FilterArmor == "ALL") or (it.armorType == FilterArmor) or (it.weaponType == FilterArmor)
        if not matchArmor and FilterArmor ~= "ALL" and it.id then
            local _, _, _, _, _, gSubType = GetItemInfo(it.id)
            if gSubType and gSubType == FilterArmor then
                it.armorType = gSubType
                matchArmor = true
            end
        end

        local matchText = (searchLower == "") or (string.find(string.lower(it.name or ""), searchLower, 1, true) ~= nil)

        local effLvl = it.effLevel or GetEffectiveLevel(it)
        local matchLevel = MatchesLevelFilter(effLvl, it, FilterLevel)

        if matchArmor and matchText and matchLevel then
            table.insert(CurrentBrowserItems, it)
        end
    end
    if not ActiveSlot then return end

    local querySlot = ActiveSlot.name
    if querySlot == "FINGER1" or querySlot == "FINGER2" then querySlot = "FINGER" end
    if querySlot == "TRINKET1" or querySlot == "TRINKET2" then querySlot = "TRINKET" end

    local rawList = ItemDatabase[querySlot] or {}
    CurrentBrowserItems = {}

    local searchLower = string.lower(FilterSearchText or "")

    for _, it in ipairs(rawList) do
        local matchArmor = (FilterArmor == "ALL") or (it.armorType == FilterArmor) or (it.weaponType == FilterArmor)
        local matchText = (searchLower == "") or (string.find(string.lower(it.name or ""), searchLower, 1, true) ~= nil)

        local effLvl = it.effLevel or GetEffectiveLevel(it)
        local matchLevel = MatchesLevelFilter(effLvl, it, FilterLevel)

        if matchArmor and matchText and matchLevel then
            table.insert(CurrentBrowserItems, it)
        end
    end

    -- Sort according to SortMode safely
    pcall(table.sort, CurrentBrowserItems, function(a, b)
        local effA = (a and a.effLevel) or 0
        local effB = (b and b.effLevel) or 0
        local qa = (a and a.quality) or 0
        local qb = (b and b.quality) or 0
        local na = (a and a.name) or ""
        local nb = (b and b.name) or ""

        if SortMode == "LVL_ASC" then
            if effA ~= effB then
                if effA == 0 then return false end
                if effB == 0 then return true end
                return effA < effB
            end
            if qa ~= qb then return qa > qb end
            return na < nb
        elseif SortMode == "LVL_DESC" then
            if effA ~= effB then
                return effA > effB
            end
            if qa ~= qb then return qa > qb end
            return na < nb
        else -- "QUAL"
            if qa ~= qb then return qa > qb end
            if effA ~= effB then return effA > effB end
            return na < nb
        end
    end)

    local total = table.getn(CurrentBrowserItems)
    local maxPage = math.max(1, math.ceil(total / ROWS_PER_PAGE))
    if BrowserPage > maxPage then BrowserPage = maxPage end
    if BrowserPage < 1 then BrowserPage = 1 end

    if Planner and Planner.pageText then
        Planner.pageText:SetText(string.format("Page %d / %d  (%d items)", BrowserPage, maxPage, total))
    end

    local startIndex = (BrowserPage - 1) * ROWS_PER_PAGE
    for i = 1, ROWS_PER_PAGE do
        local row = BrowserRows[i]
        if row then
            local item = CurrentBrowserItems[startIndex + i]
            if item then
                row.item = item
                if type(item.icon) == "string" and item.icon ~= "" then
                    row.icon:SetTexture(item.icon)
                else
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                local qc = (item.quality and QUALITY_COLORS[item.quality]) or QUALITY_COLORS[1]

                -- Lazy cache update from GetItemInfo if item was generic
                if string.find(item.name or "", "^Item #") then
                    local gName, _, gQual, gMinLvl, _, _, _, _, gTex = GetItemInfo(item.id)
                    if gName and gName ~= "" then
                        item.name = gName
                        item.quality = gQual or item.quality
                        qc = QUALITY_COLORS[item.quality] or qc
                        if gMinLvl and type(gMinLvl) == "number" and gMinLvl > 0 then
                            item.reqLevel = gMinLvl
                            item.effLevel = gMinLvl
                        end
                        if gTex then item.icon = gTex; row.icon:SetTexture(gTex) end
                    end
                end

                local effLvl = item.effLevel or GetEffectiveLevel(item)
                local lvlText = ""
                local rLvl = tonumber(item.reqLevel) or 0
                local eff = tonumber(effLvl) or 0
                if rLvl > 0 then
                    lvlText = string.format(" |cFFFFD100[Req %d]|r", rLvl)
                elseif eff > 0 then
                    lvlText = string.format(" |cFFFFD100[Req %d]|r", eff)
                end

                row.name:SetText((item.name or "Item") .. lvlText)
                row.name:SetTextColor(qc[1], qc[2], qc[3])
                local typeStr = item.armorType or item.weaponType or "Item"
                row.sub:SetText(string.format("|cFF999999%s • %s|r", typeStr, item.source or "AtlasLoot"))
                row:SetBackdropBorderColor(qc[1], qc[2], qc[3], 0.7)
                row:Show()
            else
                row.item = nil
                row:Hide()
            end
        end
    end

    UpdateFilterButtons()
end

local function OpenSlotBrowser(slot)
    if not slot then return end
    ActiveSlot = slot
    local ok, err = pcall(IndexAtlasLootData)
    if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Index Error]:|r " .. tostring(err))
    end
    if Planner and Planner.browserTitle then
        Planner.browserTitle:SetText(string.format("Selecting: |cFFFFD100%s|r", slot.label or slot.name or "Slot"))
    end
    HighlightActiveSlot()
    BrowserPage = 1
    local uok, uerr = pcall(UpdateBrowserList)
    if not uok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Browser Error]:|r " .. tostring(uerr))
    end
    if Planner and Planner.browserPanel then
        Planner.browserPanel:Show()
    end
end

-- ----------------------------------------------------------------------------
-- Enchant Picker Menu
-- ----------------------------------------------------------------------------
local function OpenEnchantPicker(slot)
    if not enchMenuFrame then return end
    if not slot.enchant or not ENCHANTS[slot.enchant] then return end
    enchMenuFrame.targetSlot = slot.name
    local list = ENCHANTS[slot.enchant]

    for i = 1, 8 do
        local eb = enchMenuFrame.buttons[i]
        if list[i] then
            eb.enchData = list[i]
            eb.text:SetText(list[i].name)
            eb:Show()
        else
            eb:Hide()
        end
    end
    enchMenuFrame:SetHeight(math.min(220, table.getn(list) * 22 + 25))
    local btn = SlotButtons[slot.name]
    enchMenuFrame:ClearAllPoints()
    if slot.col == 2 then
        enchMenuFrame:SetPoint("TOPRIGHT", btn, "TOPLEFT", -6, 0)
    else
        enchMenuFrame:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, 0)
    end
    enchMenuFrame:Show()
end

-- ----------------------------------------------------------------------------
-- Create Main Interface Window
-- ----------------------------------------------------------------------------
local function BuildUI()
    if Planner.isBuilt then return end

    Planner:SetWidth(600)
    Planner:SetHeight(396)
    Planner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Planner:SetFrameStrata("HIGH")
    Planner:SetToplevel(true)
    Planner:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    Planner:SetBackdropColor(0.04, 0.05, 0.08, 0.82)
    Planner:SetBackdropBorderColor(0.18, 0.55, 0.85, 0.85)
    local curScale = (OctoBiSPlannerDB and OctoBiSPlannerDB.scale) or 0.85
    Planner:SetScale(curScale)
    Planner:EnableMouse(true)
    Planner:SetMovable(true)
    Planner:RegisterForDrag("LeftButton")
    Planner:SetScript("OnDragStart", function() this:StartMoving() end)
    Planner:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    Planner:Hide()

    -- Title Bar (Modern Sleek Smoked Header)
    local titleBg = Planner:CreateTexture(nil, "BACKGROUND")
    titleBg:SetPoint("TOPLEFT", Planner, "TOPLEFT", 6, -6)
    titleBg:SetPoint("TOPRIGHT", Planner, "TOPRIGHT", -6, -6)
    titleBg:SetHeight(24)
    titleBg:SetTexture(0.08, 0.12, 0.18, 0.85)

    local titleLine = Planner:CreateTexture(nil, "ARTWORK")
    titleLine:SetPoint("TOPLEFT", titleBg, "BOTTOMLEFT", 0, 0)
    titleLine:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT", 0, 0)
    titleLine:SetHeight(1)
    titleLine:SetTexture(0.2, 0.6, 0.9, 0.8)

    local titleText = Planner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBg, "LEFT", 10, 0)
    titleText:SetText("|cFF00E5FFOctoBiS Planner|r |cFF888888• Virtual Gear & BiS Builder|r")

    -- Close Button
    local closeBtn = CreateFrame("Button", "OctoBiSPlannerCloseBtn", Planner, "UIPanelCloseButton")
    closeBtn:SetWidth(22)
    closeBtn:SetHeight(22)
    closeBtn:SetPoint("TOPRIGHT", Planner, "TOPRIGHT", -5, -6)
    closeBtn:SetScript("OnClick", function() Planner:Hide() end)

    -- ------------------------------------------------------------------------
    -- 1. LEFT PANEL: Paperdoll Slots (Columns 1 & 2)
    -- ------------------------------------------------------------------------
    local dollFrame = CreateFrame("Frame", "OctoBiSDollFrame", Planner)
    dollFrame:SetWidth(116)
    dollFrame:SetHeight(346)
    dollFrame:SetPoint("TOPLEFT", Planner, "TOPLEFT", 10, -36)

    for _, slot in ipairs(SLOTS) do
        local btn = CreateFrame("Button", "OctoBiSSlot_" .. slot.name, dollFrame)
        btn:SetWidth(32)
        btn:SetHeight(32)
        btn.slotData = slot
        btn:EnableMouse(true)
        btn:SetFrameLevel(dollFrame:GetFrameLevel() + 2)

        btn.defaultIcon = slot.icon
        btn.enchantCategory = slot.enchant

        if slot.col == 1 then
            btn:SetPoint("TOPLEFT", dollFrame, "TOPLEFT", 4, -((slot.row - 1) * 37))
        elseif slot.col == 2 then
            btn:SetPoint("TOPLEFT", dollFrame, "TOPLEFT", 76, -((slot.row - 1) * 37))
        elseif slot.col == 3 then
            -- Bottom weapons row
            btn:SetPoint("TOPLEFT", dollFrame, "TOPLEFT", 4 + ((slot.row - 1) * 36), -298)
        end

        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropColor(0.06, 0.07, 0.1, 0.9)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.7)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon
        if slot.icon then
            icon:SetTexture(slot.icon)
            icon:SetVertexColor(0.28, 0.28, 0.32, 0.5)
            icon:Show()
        else
            icon:Hide()
        end

        -- Dedicated Enchant Button under slot
        if slot.enchant then
            local enchBtn = CreateFrame("Button", "OctoBiSEnchBtn_" .. slot.name, dollFrame)
            enchBtn:SetWidth(34)
            enchBtn:SetHeight(9)
            enchBtn:SetPoint("TOP", btn, "BOTTOM", 0, 0)
            enchBtn:EnableMouse(true)
            enchBtn.slotData = slot

            local enchTxt = enchBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            enchTxt:SetPoint("CENTER", enchBtn, "CENTER", 0, 0)
            if STANDARD_TEXT_FONT then
                enchTxt:SetFont(STANDARD_TEXT_FONT, 8, "")
            end
            enchTxt:SetText("|cFF777777[ench]|r")
            enchBtn.text = enchTxt

            enchBtn:SetScript("OnClick", function()
                local s = this.slotData
                if s then OpenEnchantPicker(s) end
            end)
            enchBtn:SetScript("OnEnter", function()
                local s = this.slotData
                if not s then return end
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.label .. " Enchant")
                GameTooltip:AddLine("|cFF00FFCCClick to pick an enchant for this slot.|r")
                GameTooltip:Show()
            end)
            enchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn.enchButton = enchBtn
        end

        -- Slot Button Clicks
        btn.slotData = slot
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function()
            local s = this.slotData
            if not s then return end
            if arg1 == "RightButton" then
                -- Clear slot
                EquippedGear[s.name] = nil
                EquippedEnchants[s.name] = nil
                RefreshSlotDisplay(s.name)
            else
                if IsShiftKeyDown() and s.enchant then
                    OpenEnchantPicker(s)
                else
                    OpenSlotBrowser(s)
                end
            end
        end)

        btn:SetScript("OnEnter", function()
            local s = this.slotData
            if not s then return end
            local it = EquippedGear[s.name]
            if it then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. it.id .. ":0:0:0")
                local ench = EquippedEnchants[s.name]
                if ench then
                    GameTooltip:AddLine("Enchant: |cFF00FFCC" .. ench.name .. "|r")
                end
                GameTooltip:AddLine("|cFF888888<Right-Click to Clear Slot>|r")
                if s.enchant then
                    GameTooltip:AddLine("|cFF00FFCC<Shift-Click to Pick Enchant>|r")
                end
                GameTooltip:Show()
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.label)
                GameTooltip:AddLine("|cFF00FFCC<Left-Click to Search Items>|r")
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        SlotButtons[slot.name] = btn
    end

    -- ------------------------------------------------------------------------
    -- 2. MIDDLE PANEL: Item Browser & Search
    -- ------------------------------------------------------------------------
    local browser = CreateFrame("Frame", "OctoBiSBrowserFrame", Planner)
    browser:SetWidth(292)
    browser:SetHeight(346)
    browser:SetPoint("TOPLEFT", dollFrame, "TOPRIGHT", 6, 0)
    browser:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    browser:SetBackdropColor(0.04, 0.05, 0.07, 0.65)
    browser:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.6)
    Planner.browserPanel = browser

    local bTitle = browser:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bTitle:SetPoint("TOPLEFT", browser, "TOPLEFT", 8, -6)
    bTitle:SetText("Item Browser")
    Planner.browserTitle = bTitle

    -- Search Box
    local searchBox = CreateFrame("EditBox", "OctoBiSSearchEdit", browser, "InputBoxTemplate")
    searchBox:SetWidth(100)
    searchBox:SetHeight(18)
    searchBox:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -8, -5)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function()
        FilterSearchText = this:GetText()
        BrowserPage = 1
        UpdateBrowserList()
    end)
    searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    local searchLabel = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", searchBox, "LEFT", -4, 0)
    searchLabel:SetText("Search:")

    -- Filter Tabs (Line 2: Armor: ALL, Plate, Mail, Leather, Cloth)
    local armorFilters = {
        { name = "ALL", width = 32 },
        { name = "Plate", width = 40 },
        { name = "Mail", width = 36 },
        { name = "Leather", width = 46 },
        { name = "Cloth", width = 38 },
    }
    local curX = 8
    for _, af in ipairs(armorFilters) do
        local fBtn = CreateFrame("Button", nil, browser)
        fBtn:SetWidth(af.width)
        fBtn:SetHeight(16)
        fBtn:SetPoint("TOPLEFT", browser, "TOPLEFT", curX, -25)
        curX = curX + af.width + 3
        fBtn:SetFrameLevel(browser:GetFrameLevel() + 5)
        fBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        fBtn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
        fBtn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
        fBtn:EnableMouse(true)
        fBtn:RegisterForClicks("LeftButtonUp")

        local txt = fBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER", fBtn, "CENTER", 0, 0)
        txt:SetText(af.name)
        fBtn.text = txt
        fBtn.filterVal = af.name
        fBtn:SetScript("OnClick", function()
            FilterArmor = this.filterVal
            BrowserPage = 1
            if not ActiveSlot then ActiveSlot = SLOTS[1] end
            UpdateBrowserList()
        end)
        fBtn:SetScript("OnEnter", function()
            this:SetBackdropBorderColor(0.4, 0.8, 1.0, 1.0)
        end)
        fBtn:SetScript("OnLeave", function()
            UpdateFilterButtons()
        end)
        ArmorButtons[af.name] = fBtn
    end

    -- Level Filter Tabs (Line 3: ALL, 40+, 40-49, 50-59, 60)
    local levelFilters = {
        { name = "ALL", width = 28 },
        { name = "40+", width = 30 },
        { name = "40-49", width = 38 },
        { name = "50-59", width = 38 },
        { name = "60", width = 26 },
    }
    curX = 8
    for _, lf in ipairs(levelFilters) do
        local lBtn = CreateFrame("Button", nil, browser)
        lBtn:SetWidth(lf.width)
        lBtn:SetHeight(16)
        lBtn:SetPoint("TOPLEFT", browser, "TOPLEFT", curX, -44)
        curX = curX + lf.width + 3
        lBtn:SetFrameLevel(browser:GetFrameLevel() + 5)
        lBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        lBtn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
        lBtn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
        lBtn:EnableMouse(true)
        lBtn:RegisterForClicks("LeftButtonUp")

        local txt = lBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER", lBtn, "CENTER", 0, 0)
        txt:SetText(lf.name)
        lBtn.text = txt
        lBtn.filterVal = lf.name
        lBtn:SetScript("OnClick", function()
            FilterLevel = this.filterVal
            BrowserPage = 1
            if not ActiveSlot then ActiveSlot = SLOTS[1] end
            UpdateBrowserList()
        end)
        lBtn:SetScript("OnEnter", function()
            this:SetBackdropBorderColor(0.4, 0.8, 1.0, 1.0)
        end)
        lBtn:SetScript("OnLeave", function()
            UpdateFilterButtons()
        end)
        LevelButtons[lf.name] = lBtn
    end

    -- Sort Toggle Button (Line 3 Right)
    local sortBtn = CreateFrame("Button", nil, browser)
    sortBtn:SetWidth(84)
    sortBtn:SetHeight(16)
    sortBtn:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -8, -44)
    sortBtn:SetFrameLevel(browser:GetFrameLevel() + 5)
    sortBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    sortBtn:SetBackdropColor(0.12, 0.16, 0.22, 0.9)
    sortBtn:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.8)
    sortBtn:EnableMouse(true)
    sortBtn:RegisterForClicks("LeftButtonUp")

    local sTxt = sortBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sTxt:SetPoint("CENTER", sortBtn, "CENTER", 0, 0)
    sTxt:SetText("|cFFFFD100Sort: Lvl ▲|r")
    sortBtn.text = sTxt
    sortBtn:SetScript("OnClick", function()
        if SortMode == "LVL_ASC" then
            SortMode = "LVL_DESC"
        elseif SortMode == "LVL_DESC" then
            SortMode = "QUAL"
        else
            SortMode = "LVL_ASC"
        end
        BrowserPage = 1
        if not ActiveSlot then ActiveSlot = SLOTS[1] end
        UpdateBrowserList()
    end)
    sortBtn:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.4, 0.8, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort Order")
        GameTooltip:AddLine("Click to cycle between:", 1, 1, 1)
        GameTooltip:AddLine("• |cFFFFD100Sort: Lvl ▲|r (Level ascending - level 40 first)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• |cFFFFD100Sort: Lvl ▼|r (Level descending - level 60 first)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• |cFFFFD100Sort: Qual|r (Quality - Epics first)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        UpdateFilterButtons()
    end)
    SortButtonRef = sortBtn

    -- Browser Rows (7 rows)
    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", "OctoBiSRow_" .. i, browser)
        row:SetWidth(276)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", browser, "TOPLEFT", 8, -64 - ((i - 1) * 35))
        row:SetFrameLevel(browser:GetFrameLevel() + 3)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        row:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.7)

        local rIcon = row:CreateTexture(nil, "ARTWORK")
        rIcon:SetWidth(24)
        rIcon:SetHeight(24)
        rIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
        rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = rIcon

        local rName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rName:SetPoint("TOPLEFT", rIcon, "TOPRIGHT", 6, 0)
        rName:SetJustifyH("LEFT")
        rName:SetText("")
        row.name = rName

        local rSub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rSub:SetPoint("BOTTOMLEFT", rIcon, "BOTTOMRIGHT", 6, 1)
        rSub:SetJustifyH("LEFT")
        rSub:SetText("")
        row.sub = rSub

        row:SetScript("OnClick", function()
            if this.item and ActiveSlot then
                EquippedGear[ActiveSlot.name] = this.item
                RefreshSlotDisplay(ActiveSlot.name)
            end
        end)

        row:SetScript("OnEnter", function()
            this:SetBackdropColor(0.2, 0.25, 0.35, 0.9)
            if this.item then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. this.item.id .. ":0:0:0")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            this:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            GameTooltip:Hide()
        end)

        row:Hide()
        BrowserRows[i] = row
    end

    -- Pagination controls
    local prevBtn = CreateFrame("Button", nil, browser, "UIPanelButtonTemplate")
    prevBtn:SetWidth(48)
    prevBtn:SetHeight(18)
    prevBtn:SetPoint("BOTTOMLEFT", browser, "BOTTOMLEFT", 8, 6)
    prevBtn:SetText("Prev")
    prevBtn:SetScript("OnClick", function()
        BrowserPage = math.max(1, BrowserPage - 1)
        UpdateBrowserList()
    end)

    local nextBtn = CreateFrame("Button", nil, browser, "UIPanelButtonTemplate")
    nextBtn:SetWidth(48)
    nextBtn:SetHeight(18)
    nextBtn:SetPoint("BOTTOMRIGHT", browser, "BOTTOMRIGHT", -8, 6)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function()
        BrowserPage = BrowserPage + 1
        UpdateBrowserList()
    end)

    local pTxt = browser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pTxt:SetPoint("CENTER", browser, "BOTTOM", 0, 15)
    pTxt:SetText("Page 1 / 1")
    Planner.pageText = pTxt

    -- ------------------------------------------------------------------------
    -- 3. RIGHT PANEL: Live Stat Summary & Gear Sets
    -- ------------------------------------------------------------------------
    local statPanel = CreateFrame("Frame", "OctoBiSStatPanel", Planner)
    statPanel:SetWidth(156)
    statPanel:SetHeight(346)
    statPanel:SetPoint("TOPLEFT", browser, "TOPRIGHT", 6, 0)
    statPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    statPanel:SetBackdropColor(0.04, 0.05, 0.07, 0.65)
    statPanel:SetBackdropBorderColor(0.2, 0.35, 0.5, 0.6)

    local sTitle = statPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sTitle:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -6)
    sTitle:SetText("|cFFFFD100Total Stats|r")

    local function MakeStat(xOff, yOff)
        local fs = statPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", statPanel, "TOPLEFT", xOff, yOff)
        fs:SetJustifyH("LEFT")
        return fs
    end

    -- 2 Columns of stats
    StatLabels.str = MakeStat(8, -22)
    StatLabels.agi = MakeStat(8, -34)
    StatLabels.sta = MakeStat(8, -46)
    StatLabels.int = MakeStat(8, -58)
    StatLabels.spi = MakeStat(8, -70)

    StatLabels.armor = MakeStat(78, -22)
    StatLabels.ap    = MakeStat(78, -34)
    StatLabels.hit   = MakeStat(78, -46)
    StatLabels.crit  = MakeStat(78, -58)
    StatLabels.def   = MakeStat(78, -70)

    local line1 = statPanel:CreateTexture(nil, "ARTWORK")
    line1:SetWidth(140) line1:SetHeight(1) line1:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -82)
    line1:SetTexture(0.3, 0.45, 0.6, 0.6)

    StatLabels.dodge = MakeStat(8, -85)
    StatLabels.parry = MakeStat(78, -85)
    StatLabels.block = MakeStat(8, -97)
    StatLabels.bv    = MakeStat(78, -97)

    local line2 = statPanel:CreateTexture(nil, "ARTWORK")
    line2:SetWidth(140) line2:SetHeight(1) line2:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -109)
    line2:SetTexture(0.3, 0.45, 0.6, 0.6)

    StatLabels.sp   = MakeStat(8, -112)
    StatLabels.heal = MakeStat(78, -112)
    StatLabels.mp5  = MakeStat(8, -124)

    local line3 = statPanel:CreateTexture(nil, "ARTWORK")
    line3:SetWidth(140) line3:SetHeight(1) line3:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -137)
    line3:SetTexture(0.3, 0.45, 0.6, 0.8)

    -- ------------------------------------------------------------------------
    -- Gear Set Manager (Save / Load 5 Profiles)
    -- ------------------------------------------------------------------------
    local ActiveSetSlot = 1
    local SetSlotButtons = {}
    local SetNameBox = nil

    local function GetPlayerKey()
        local name = UnitName("player") or "Player"
        local realm = GetRealmName() or "Realm"
        return name .. " - " .. realm
    end

    UpdateSetUI = function()
        OctoBiSPlannerDB = OctoBiSPlannerDB or {}
        OctoBiSPlannerDB.sets = OctoBiSPlannerDB.sets or {}
        local pKey = GetPlayerKey()
        OctoBiSPlannerDB.sets[pKey] = OctoBiSPlannerDB.sets[pKey] or {}
        local sets = OctoBiSPlannerDB.sets[pKey]

        for i = 1, 5 do
            local btn = SetSlotButtons[i]
            if btn then
                local setData = sets[i]
                if i == ActiveSetSlot then
                    btn:SetBackdropBorderColor(0.2, 0.8, 1.0, 1.0)
                    btn:SetBackdropColor(0.18, 0.35, 0.6, 0.95)
                    btn.text:SetText("|cFFFFD100" .. i .. "|r")
                elseif setData then
                    btn:SetBackdropBorderColor(0.2, 0.7, 0.4, 0.9)
                    btn:SetBackdropColor(0.1, 0.2, 0.14, 0.8)
                    btn.text:SetText("|cFF33FF66" .. i .. "|r")
                else
                    btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
                    btn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
                    btn.text:SetText("|cFF888888" .. i .. "|r")
                end
            end
        end

        if SetNameBox then
            local curSet = sets[ActiveSetSlot]
            if curSet and curSet.name and curSet.name ~= "" then
                SetNameBox:SetText(curSet.name)
            else
                SetNameBox:SetText("Set " .. ActiveSetSlot)
            end
        end
    end

    local function SaveActiveSet()
        local pKey = GetPlayerKey()
        OctoBiSPlannerDB = OctoBiSPlannerDB or {}
        OctoBiSPlannerDB.sets = OctoBiSPlannerDB.sets or {}
        OctoBiSPlannerDB.sets[pKey] = OctoBiSPlannerDB.sets[pKey] or {}

        local name = (SetNameBox and SetNameBox:GetText()) or ("Set " .. ActiveSetSlot)
        if name == "" then name = "Set " .. ActiveSetSlot end

        local gClone = {}
        for k, v in pairs(EquippedGear) do
            gClone[k] = { id = v.id, name = v.name, quality = v.quality, icon = v.icon, source = v.source, desc = v.desc, armorType = v.armorType, weaponType = v.weaponType }
        end
        local eClone = {}
        for k, v in pairs(EquippedEnchants) do
            eClone[k] = v
        end

        OctoBiSPlannerDB.sets[pKey][ActiveSetSlot] = {
            name = name,
            gear = gClone,
            enchants = eClone,
        }

        UpdateSetUI()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCC[OctoBiS Planner]|r Saved set '|cFFFFD100%s|r' to Slot %d.", name, ActiveSetSlot))
    end

    local function LoadActiveSet()
        local pKey = GetPlayerKey()
        OctoBiSPlannerDB = OctoBiSPlannerDB or {}
        OctoBiSPlannerDB.sets = OctoBiSPlannerDB.sets or {}
        local sets = OctoBiSPlannerDB.sets[pKey] or {}
        local setData = sets[ActiveSetSlot]

        if not setData or not setData.gear then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF4444[OctoBiS Planner]|r Slot %d is empty. Save a set first!", ActiveSetSlot))
            return
        end

        EquippedGear = {}
        for k, v in pairs(setData.gear) do
            EquippedGear[k] = v
        end

        EquippedEnchants = {}
        if setData.enchants then
            for k, v in pairs(setData.enchants) do
                EquippedEnchants[k] = v
            end
        end

        for _, s in ipairs(SLOTS) do
            RefreshSlotDisplay(s.name)
        end
        UpdateStatSummary()

        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCC[OctoBiS Planner]|r Loaded gear set '|cFFFFD100%s|r' (Slot %d).", setData.name or ("Set " .. ActiveSetSlot), ActiveSetSlot))
    end

    local function ClearActiveSet()
        local pKey = GetPlayerKey()
        if OctoBiSPlannerDB and OctoBiSPlannerDB.sets and OctoBiSPlannerDB.sets[pKey] then
            OctoBiSPlannerDB.sets[pKey][ActiveSetSlot] = nil
        end
        UpdateSetUI()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFCC[OctoBiS Planner]|r Cleared saved set for Slot %d.", ActiveSetSlot))
    end

    local setHdr = statPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    setHdr:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -141)
    setHdr:SetText("|cFFFFD100Saved Sets (1-5):|r")

    -- 5 Slot Buttons [1] [2] [3] [4] [5]
    local curSetX = 8
    for i = 1, 5 do
        local sBtn = CreateFrame("Button", "OctoBiSSetSlotBtn_" .. i, statPanel)
        sBtn:SetWidth(26)
        sBtn:SetHeight(18)
        sBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", curSetX, -156)
        curSetX = curSetX + 28
        sBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        sBtn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
        sBtn:EnableMouse(true)
        sBtn:RegisterForClicks("LeftButtonUp")

        local stxt = sBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        stxt:SetPoint("CENTER", sBtn, "CENTER", 0, 0)
        stxt:SetText(tostring(i))
        sBtn.text = stxt
        sBtn.slotIndex = i

        sBtn:SetScript("OnClick", function()
            ActiveSetSlot = this.slotIndex
            UpdateSetUI()
        end)
        sBtn:SetScript("OnEnter", function()
            local pKey = GetPlayerKey()
            local sets = (OctoBiSPlannerDB and OctoBiSPlannerDB.sets and OctoBiSPlannerDB.sets[pKey]) or {}
            local sData = sets[this.slotIndex]
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format("Set Slot %d", this.slotIndex), 1, 0.85, 0.1)
            if sData and sData.name then
                GameTooltip:AddLine("Name: |cFFFFFFFF" .. sData.name .. "|r")
                GameTooltip:AddLine("|cFF33FF66<Click to Select, then Load>|r")
            else
                GameTooltip:AddLine("|cFF888888(Empty Slot)|r")
            end
            GameTooltip:Show()
        end)
        sBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        SetSlotButtons[i] = sBtn
    end

    -- Set Name EditBox
    local setBox = CreateFrame("EditBox", "OctoBiSSetNameEdit", statPanel, "InputBoxTemplate")
    setBox:SetWidth(138)
    setBox:SetHeight(18)
    setBox:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 14, -177)
    setBox:SetAutoFocus(false)
    setBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    setBox:SetScript("OnEnterPressed", function() this:ClearFocus(); SaveActiveSet() end)
    SetNameBox = setBox

    -- Save & Load buttons
    local saveBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    saveBtn:SetWidth(68) saveBtn:SetHeight(18)
    saveBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -198)
    saveBtn:SetText("Save Set")
    saveBtn:SetScript("OnClick", SaveActiveSet)

    local loadBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    loadBtn:SetWidth(68) loadBtn:SetHeight(18)
    loadBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 80, -198)
    loadBtn:SetText("Load Set")
    loadBtn:SetScript("OnClick", LoadActiveSet)

    local clrSetBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    clrSetBtn:SetWidth(140) clrSetBtn:SetHeight(16)
    clrSetBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -218)
    clrSetBtn:SetText("Delete Set")
    clrSetBtn:SetScript("OnClick", ClearActiveSet)

    local line4 = statPanel:CreateTexture(nil, "ARTWORK")
    line4:SetWidth(140) line4:SetHeight(1) line4:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -238)
    line4:SetTexture(0.3, 0.45, 0.6, 0.6)

    -- Quick Action Buttons
    local impBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    impBtn:SetWidth(140) impBtn:SetHeight(18)
    impBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -243)
    impBtn:SetText("Import Current")
    impBtn:SetScript("OnClick", function()
        for _, s in ipairs(SLOTS) do
            local slotBlizzName = INV_SLOT_MAP[s.name]
            if slotBlizzName then
                local invSlot, _ = GetInventorySlotInfo(slotBlizzName)
                if invSlot then
                    local itemLink = GetInventoryItemLink("player", invSlot)
                    if itemLink then
                        local _, _, itemID = string.find(itemLink, "item:(%d+)")
                        if itemID then
                            local name, _, quality, _, _, _, _, _, icon = GetItemInfo(itemID)
                            EquippedGear[s.name] = {
                                id = tonumber(itemID),
                                name = name or "Equipped Item",
                                quality = quality or 1,
                                icon = icon or s.icon,
                                source = "Currently Equipped"
                            }
                        end
                    end
                end
            end
            RefreshSlotDisplay(s.name)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCC[OctoBiS Planner]|r Imported current equipped gear.")
    end)

    local clrBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    clrBtn:SetWidth(140) clrBtn:SetHeight(18)
    clrBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -263)
    clrBtn:SetText("Clear Equips")
    clrBtn:SetScript("OnClick", function()
        EquippedGear = {}
        EquippedEnchants = {}
        for _, s in ipairs(SLOTS) do RefreshSlotDisplay(s.name) end
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCC[OctoBiS Planner]|r Cleared all slots.")
    end)

    local shareBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    shareBtn:SetWidth(140) shareBtn:SetHeight(18)
    shareBtn:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -283)
    shareBtn:SetText("Share in Chat")
    shareBtn:SetScript("OnClick", function()
        local links = {}
        for _, s in ipairs(SLOTS) do
            local it = EquippedGear[s.name]
            if it then
                local _, link = GetItemInfo(it.id)
                if link then
                    table.insert(links, string.format("[%s: %s]", s.label, link))
                end
            end
        end
        if table.getn(links) > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[OctoBiS Build]:|r")
            local batch = {}
            for i, lk in ipairs(links) do
                table.insert(batch, lk)
                if math.mod(i, 4) == 0 or i == table.getn(links) then
                    DEFAULT_CHAT_FRAME:AddMessage(" " .. table.concat(batch, " "))
                    batch = {}
                end
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Planner]:|r No items equipped to share.")
        end
    end)

    -- Deferred ticker to refresh stats once server returns uncached item info
    local statTicker = 0
    Planner:SetScript("OnUpdate", function()
        statTicker = statTicker + arg1
        if statTicker >= 0.4 then
            statTicker = 0
            if PendingStatUpdate and Planner:IsShown() then
                UpdateStatSummary()
            end
        end
    end)

    UpdateSetUI()

    -- ------------------------------------------------------------------------
    -- 4. Enchant Selection Menu (Global Frame)
    -- ------------------------------------------------------------------------
    local enchMenu = CreateFrame("Frame", "OctoBiSEnchantMenu", Planner)
    enchMenu:SetWidth(220)
    enchMenu:SetHeight(180)
    enchMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    enchMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    enchMenu:SetBackdropBorderColor(0, 0.8, 1, 1)
    enchMenu:SetFrameStrata("TOOLTIP")
    enchMenu:EnableMouse(true)
    enchMenu:Hide()

    local enchClose = CreateFrame("Button", nil, enchMenu, "UIPanelCloseButton")
    enchClose:SetWidth(18) enchClose:SetHeight(18)
    enchClose:SetPoint("TOPRIGHT", enchMenu, "TOPRIGHT", -2, -2)
    enchClose:SetScript("OnClick", function() enchMenu:Hide() end)

    enchMenu.buttons = {}
    for i = 1, 8 do
        local eb = CreateFrame("Button", nil, enchMenu)
        eb:SetWidth(200) eb:SetHeight(18)
        eb:SetPoint("TOPLEFT", enchMenu, "TOPLEFT", 8, -12 - ((i - 1) * 20))
        local eTxt = eb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eTxt:SetPoint("LEFT", eb, "LEFT", 4, 0)
        eb.text = eTxt
        eb:SetScript("OnClick", function()
            if this.enchData and enchMenu.targetSlot then
                EquippedEnchants[enchMenu.targetSlot] = this.enchData
                RefreshSlotDisplay(enchMenu.targetSlot)
            end
            enchMenu:Hide()
        end)
        enchMenu.buttons[i] = eb
    end
    enchMenuFrame = enchMenu

    -- Restore saved profile if available
    if OctoBiSPlannerDB and OctoBiSPlannerDB[CurrentProfile] then
        if OctoBiSPlannerDB[CurrentProfile].gear then
            EquippedGear = OctoBiSPlannerDB[CurrentProfile].gear
        end
        if OctoBiSPlannerDB[CurrentProfile].enchants then
            EquippedEnchants = OctoBiSPlannerDB[CurrentProfile].enchants
        end
    end

    for _, s in ipairs(SLOTS) do
        RefreshSlotDisplay(s.name)
    end

    Planner.isBuilt = true
end

-- ----------------------------------------------------------------------------
-- Toggle Function & Slash Commands
-- ----------------------------------------------------------------------------
function OctoBiSPlanner_Toggle()
    OctoBiSPlannerDB = OctoBiSPlannerDB or {}
    if not OctoBiSPlannerDB[CurrentProfile] then
        OctoBiSPlannerDB[CurrentProfile] = { gear = {}, enchants = {} }
    end

    if not Planner.isBuilt then
        local ok, err = pcall(BuildUI)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Build Error]:|r " .. tostring(err))
            return
        end
    end
    if Planner:IsShown() then
        Planner:Hide()
    else
        local ok, err = pcall(IndexAtlasLootData)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Index Error]:|r " .. tostring(err))
        end
        Planner:ClearAllPoints()
        if CharacterFrame and CharacterFrame:IsShown() then
            Planner:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 15, 0)
        else
            Planner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        Planner:Show()
        UpdateStatSummary()
        if UpdateSetUI then UpdateSetUI() end
        if not ActiveSlot then
            OpenSlotBrowser(SLOTS[1])
        else
            OpenSlotBrowser(ActiveSlot)
        end
    end
end

SLASH_OCTOBIS1 = "/bis"
SLASH_OCTOBIS2 = "/gearplanner"
SLASH_OCTOBIS3 = "/octobis"
SlashCmdList["OCTOBIS"] = function(msg)
    local ok, err = pcall(OctoBiSPlanner_Toggle)
    if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[OctoBiS Error]:|r " .. tostring(err))
    end
end

SLASH_OCTOBISCALE1 = "/biscale"
SLASH_OCTOBISCALE2 = "/bisscale"
SlashCmdList["OCTOBISCALE"] = function(msg)
    local s = tonumber(msg)
    if s and s >= 0.4 and s <= 1.5 then
        OctoBiSPlannerDB = OctoBiSPlannerDB or {}
        OctoBiSPlannerDB.scale = s
        if Planner then
            Planner:SetScale(s)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[OctoBiS Planner]|r Scale set to |cffffd100" .. s .. "|r.")
    else
        local cur = (OctoBiSPlannerDB and OctoBiSPlannerDB.scale) or 0.85
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[OctoBiS Planner]|r Current scale is |cffffd100" .. cur .. "|r. Use |cff00ffcc/biscale <0.4-1.5>|r (e.g. |cffffd100/biscale 0.75|r).")
    end
end

-- ----------------------------------------------------------------------------
-- Character Frame Integration (Tab + Button + Minimap)
-- ----------------------------------------------------------------------------
local function SetupCharacterIntegration()
    if not CharacterFrame then return end

    -- 1. Create PaperDoll frame button
    if PaperDollFrame and not _G["PaperDollBiSPlannerBtn"] then
        local btn = CreateFrame("Button", "PaperDollBiSPlannerBtn", PaperDollFrame, "UIPanelButtonTemplate")
        btn:SetWidth(94)
        btn:SetHeight(22)
        btn:SetPoint("TOPRIGHT", PaperDollFrame, "TOPRIGHT", -38, -42)
        btn:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 10)
        btn:SetText("BiS Planner")
        btn:SetScript("OnClick", function()
            OctoBiSPlanner_Toggle()
        end)
        btn:Show()
    end

    -- 2. Create bottom Tab on CharacterFrame
    local tab = _G["CharacterFrameTabBiS"]
    if not tab then
        tab = CreateFrame("Button", "CharacterFrameTabBiS", CharacterFrame, "CharacterFrameTabButtonTemplate")
        if not tab then
            tab = CreateFrame("Button", "CharacterFrameTabBiS", CharacterFrame, "TabButtonTemplate")
        end
        if tab then
            tab:SetID(6)
            tab:SetText("BiS Planner")
            tab:SetFrameLevel(CharacterFrame:GetFrameLevel() + 2)
            if PanelTemplates_TabResize then
                PanelTemplates_TabResize(0, tab)
            end
            tab:SetScript("OnClick", function()
                OctoBiSPlanner_Toggle()
            end)
            tab:Show()
        end
    end

    -- 3. Dynamically position tab after the rightmost shown tab
    if tab then
        local lastVisible = nil
        for i = 1, 5 do
            local t = _G["CharacterFrameTab" .. i]
            if t and t:IsShown() and t ~= tab then
                lastVisible = t
            end
        end

        tab:ClearAllPoints()
        if lastVisible then
            tab:SetPoint("LEFT", lastVisible, "RIGHT", -16, 0)
        else
            local anchor = _G["CharacterFrameTab5"] or _G["CharacterFrameTab4"] or _G["CharacterFrameTab1"]
            if anchor then
                tab:SetPoint("LEFT", anchor, "RIGHT", -16, 0)
            else
                tab:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 15, -30)
            end
        end
        tab:Show()
    end
end

-- Hook CharacterFrame show & tab click events safely for Vanilla 1.12.1
local orig_ToggleCharacter = ToggleCharacter
ToggleCharacter = function(tab)
    if orig_ToggleCharacter then orig_ToggleCharacter(tab) end
    SetupCharacterIntegration()
end

local orig_CharacterFrameTab_OnClick = CharacterFrameTab_OnClick
CharacterFrameTab_OnClick = function()
    if orig_CharacterFrameTab_OnClick then orig_CharacterFrameTab_OnClick() end
    SetupCharacterIntegration()
end

if CharacterFrame then
    local orig_CharacterFrame_OnShow = CharacterFrame:GetScript("OnShow")
    CharacterFrame:SetScript("OnShow", function()
        if orig_CharacterFrame_OnShow then orig_CharacterFrame_OnShow() end
        SetupCharacterIntegration()
    end)
end

-- Minimap Icon
local mmBtn = CreateFrame("Button", "OctoBiSMinimapBtn", Minimap)
mmBtn:SetWidth(31)
mmBtn:SetHeight(31)
mmBtn:SetFrameStrata("LOW")
mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmIcon = mmBtn:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\INV_Helmet_06")
mmIcon:SetWidth(20)
mmIcon:SetHeight(20)
mmIcon:SetPoint("CENTER", mmBtn, "CENTER", 0, 0)
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local mmBorder = mmBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetWidth(52)
mmBorder:SetHeight(52)
mmBorder:SetPoint("TOPLEFT", mmBtn, "TOPLEFT", 0, 0)

local rad = 2.8
local x = math.cos(rad) * 80
local y = math.sin(rad) * 80
mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)

mmBtn:RegisterForClicks("LeftButtonUp")
mmBtn:SetScript("OnClick", function()
    OctoBiSPlanner_Toggle()
end)
mmBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("OctoBiS Planner", 1, 1, 1)
    GameTooltip:AddLine("Click to open virtual gear planner & BiS builder.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff888888Slash command: /bis|r", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local hookFrame = CreateFrame("Frame", "OctoBiSHookFrame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:RegisterEvent("VARIABLES_LOADED")

hookFrame:SetScript("OnEvent", function()
    OctoBiSPlannerDB = OctoBiSPlannerDB or {}
    if not OctoBiSPlannerDB[CurrentProfile] then
        OctoBiSPlannerDB[CurrentProfile] = { gear = {}, enchants = {} }
    end

    if event == "VARIABLES_LOADED" or event == "PLAYER_ENTERING_WORLD" then
        if not Planner.isBuilt then
            BuildUI()
        end
        SetupCharacterIntegration()

        if event == "PLAYER_ENTERING_WORLD" and not Planner.loadedAnnounced then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffcc[OctoBiS Planner]|r loaded! Open via Character tab, top button, minimap icon, or |cffffd100/bis|r.")
            Planner.loadedAnnounced = true
        end
    end
end)
