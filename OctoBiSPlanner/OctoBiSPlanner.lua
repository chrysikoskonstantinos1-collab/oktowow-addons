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

-- ----------------------------------------------------------------------------
-- Tooltip Scanner for Accurate Item Stats
-- ----------------------------------------------------------------------------
local scanner = CreateFrame("GameTooltip", "OctoBiSScannerTooltip", UIParent, "GameTooltipTemplate")
scanner:SetOwner(UIParent, "ANCHOR_NONE")

local function ScanItemStats(itemID)
    if not itemID or itemID <= 0 then return {} end
    scanner:ClearLines()
    scanner:SetHyperlink("item:" .. itemID .. ":0:0:0")

    local stats = {
        str = 0, agi = 0, sta = 0, int = 0, spi = 0, armor = 0,
        ap = 0, hit = 0, crit = 0,
        defense = 0, dodge = 0, parry = 0, block = 0, blockValue = 0,
        spellDmg = 0, healing = 0, mp5 = 0,
    }

    for i = 1, 30 do
        local line = _G["OctoBiSScannerTooltipTextLeft" .. i]
        if line and line:IsShown() then
            local text = line:GetText()
            if text then
                local _, _, v = string.find(text, "(%d+) Strength")
                if v then stats.str = stats.str + tonumber(v) end

                _, _, v = string.find(text, "(%d+) Agility")
                if v then stats.agi = stats.agi + tonumber(v) end

                _, _, v = string.find(text, "(%d+) Stamina")
                if v then stats.sta = stats.sta + tonumber(v) end

                _, _, v = string.find(text, "(%d+) Intellect")
                if v then stats.int = stats.int + tonumber(v) end

                _, _, v = string.find(text, "(%d+) Spirit")
                if v then stats.spi = stats.spi + tonumber(v) end

                _, _, v = string.find(text, "^(%d+) Armor")
                if v then stats.armor = stats.armor + tonumber(v) end

                _, _, v = string.find(text, "chance to hit by (%d+)%%")
                if v then stats.hit = stats.hit + tonumber(v) end

                _, _, v = string.find(text, "critical strike by (%d+)%%")
                if v then stats.crit = stats.crit + tonumber(v) end

                _, _, v = string.find(text, "%+(%d+) Attack Power")
                if not v then _, _, v = string.find(text, "attack power by (%d+)") end
                if v then stats.ap = stats.ap + tonumber(v) end

                _, _, v = string.find(text, "defense by (%d+)")
                if not v then _, _, v = string.find(text, "%+(%d+) Defense") end
                if v then stats.defense = stats.defense + tonumber(v) end

                _, _, v = string.find(text, "dodge an attack by (%d+)%%")
                if v then stats.dodge = stats.dodge + tonumber(v) end

                _, _, v = string.find(text, "parry an attack by (%d+)%%")
                if v then stats.parry = stats.parry + tonumber(v) end

                _, _, v = string.find(text, "block attacks with a shield by (%d+)%%")
                if v then stats.block = stats.block + tonumber(v) end

                _, _, v = string.find(text, "block value of your shield by (%d+)")
                if v then stats.blockValue = stats.blockValue + tonumber(v) end

                _, _, v = string.find(text, "damage and healing done by magical spells and effects by up to (%d+)")
                if v then
                    stats.spellDmg = stats.spellDmg + tonumber(v)
                    stats.healing = stats.healing + tonumber(v)
                end

                _, _, v = string.find(text, "healing done by spells and effects by up to (%d+)")
                if v then stats.healing = stats.healing + tonumber(v) end

                _, _, v = string.find(text, "(%d+) mana per 5 sec")
                if v then stats.mp5 = stats.mp5 + tonumber(v) end
            end
        end
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

    local function ParseEntry(v, sourceName)
        if type(v) ~= "table" then return end

        -- If nested array: v[1] is a table, recursively parse (handles sets and crafting tables)
        if type(v[1]) == "table" then
            for _, subEntry in ipairs(v) do
                ParseEntry(subEntry, sourceName)
            end
            return
        end

        local itemID = v[1]
        if type(itemID) ~= "number" or itemID <= 0 then return end
        if seenItems[itemID] then return end

        local rawDesc = ""
        local rawName = ""
        local icon = "INV_Misc_QuestionMark"

        -- Support both 5-tuple {id, icon, name, desc, rate} and 2-tuple {id, desc}
        if type(v[4]) == "string" and string.find(v[4], "#") then
            rawDesc = v[4]
            rawName = (type(v[3]) == "string" and v[3]) or ""
            icon = (type(v[2]) == "string" and v[2]) or icon
        elseif type(v[2]) == "string" and string.find(v[2], "#") then
            rawDesc = v[2]
            rawName = (type(v[3]) == "string" and v[3]) or ""
            icon = (type(v[4]) == "string" and v[4]) or icon
        else
            rawDesc = (type(v[4]) == "string" and v[4]) or (type(v[2]) == "string" and v[2]) or ""
            rawName = (type(v[3]) == "string" and v[3]) or ""
            icon = (type(v[2]) == "string" and not string.find(v[2], "#") and v[2]) or icon
        end

        -- Extract Quality
        local _, _, qStr = string.find(rawName, "=q(%d)=")
        local quality = qStr and tonumber(qStr) or 1
        local cleanName = string.gsub(rawName, "=q%d=", "")
        cleanName = string.gsub(cleanName, "=ds=", "")

        -- Query GetItemInfo for missing details or fallback
        local gName, gLink, gQuality, gLevel, gMinLevel, gClass, gSubClass, _, gEquipLoc, gTexture = GetItemInfo(itemID)
        if cleanName == "" or cleanName == " " then
            if gName and gName ~= "" then
                cleanName = gName
                quality = gQuality or quality
            else
                cleanName = "Item #" .. itemID
            end
        end

        if (not icon or icon == "INV_Misc_QuestionMark" or icon == "") and gTexture then
            icon = gTexture
        end

        -- Extract Armor Type
        local armorType = nil
        if string.find(rawDesc, "#a4#") then armorType = "Plate"
        elseif string.find(rawDesc, "#a3#") then armorType = "Mail"
        elseif string.find(rawDesc, "#a2#") then armorType = "Leather"
        elseif string.find(rawDesc, "#a1#") then armorType = "Cloth"
        elseif gSubClass and (gSubClass == "Plate" or gSubClass == "Mail" or gSubClass == "Leather" or gSubClass == "Cloth") then
            armorType = gSubClass
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
        elseif string.find(rawDesc, "#w2#") or string.find(rawDesc, "#w3#") or string.find(rawDesc, "#w5#") or string.find(rawDesc, "#w11#") or string.find(rawDesc, "#w12#") then
            weaponType = "Ranged"
        end

        local fullIcon = icon
        if not string.find(fullIcon, "\\") then
            fullIcon = "Interface\\Icons\\" .. fullIcon
        end

        -- Source resolving
        local sourceKey = sourceName or "AtlasLoot"
        local sourceInfo = AtlasLoot_TableNames and (AtlasLoot_TableNames[sourceKey] or AtlasLoot_TableNames[string.gsub(sourceKey, "C$", "")])
        local cleanSource = sourceKey
        local sourceMinLvl = nil
        local sourceMaxLvl = nil

        if sourceInfo then
            local boss = sourceInfo[1] or ""
            local zone = sourceInfo[3] or sourceInfo[2] or ""
            boss = string.gsub(boss, "|c%x%x%x%x%x%x%x%x", "")
            boss = string.gsub(boss, "|r", "")
            zone = string.gsub(zone, "|c%x%x%x%x%x%x%x%x", "")
            zone = string.gsub(zone, "|r", "")

            local _, _, minL, maxL = string.find(zone, "%[(%d+)%-(%d+)%]")
            if minL and maxL then
                sourceMinLvl = tonumber(minL)
                sourceMaxLvl = tonumber(maxL)
            elseif string.find(zone, "%[RAID%]") then
                sourceMinLvl = 60
                sourceMaxLvl = 60
            end

            if boss ~= "" and zone ~= "" then
                cleanSource = zone .. " (" .. boss .. ")"
            elseif boss ~= "" then
                cleanSource = boss
            elseif zone ~= "" then
                cleanSource = zone
            end
        elseif AtlasLoot_Data and AtlasLoot_Data["AtlasLootSources"] and AtlasLoot_Data["AtlasLootSources"][itemID] then
            cleanSource = AtlasLoot_Data["AtlasLootSources"][itemID]
        end

        local itemReqLevel = (gMinLevel and gMinLevel > 0 and gMinLevel) or sourceMinLvl or 0
        local itemLvl = gLevel or (itemReqLevel > 0 and (itemReqLevel + 5)) or 0

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
            reqLevel = itemReqLevel,
            itemLevel = itemLvl,
        }

        seenItems[itemID] = true

        -- Map to slots
        if string.find(rawDesc, "#s1#") or gEquipLoc == "INVTYPE_HEAD" then table.insert(ItemDatabase.HEAD, itemObj) end
        if string.find(rawDesc, "#s2#") or gEquipLoc == "INVTYPE_NECK" then table.insert(ItemDatabase.NECK, itemObj) end
        if string.find(rawDesc, "#s3#") or gEquipLoc == "INVTYPE_SHOULDER" then table.insert(ItemDatabase.SHOULDER, itemObj) end
        if string.find(rawDesc, "#s4#") or gEquipLoc == "INVTYPE_CLOAK" then table.insert(ItemDatabase.BACK, itemObj) end
        if string.find(rawDesc, "#s5#") or gEquipLoc == "INVTYPE_CHEST" or gEquipLoc == "INVTYPE_ROBE" then table.insert(ItemDatabase.CHEST, itemObj) end
        if string.find(rawDesc, "#s6#") or gEquipLoc == "INVTYPE_BODY" then table.insert(ItemDatabase.SHIRT, itemObj) end
        if string.find(rawDesc, "#s7#") or gEquipLoc == "INVTYPE_TABARD" then table.insert(ItemDatabase.TABARD, itemObj) end
        if string.find(rawDesc, "#s8#") or gEquipLoc == "INVTYPE_WRIST" then table.insert(ItemDatabase.WRIST, itemObj) end
        if string.find(rawDesc, "#s9#") or gEquipLoc == "INVTYPE_HAND" then table.insert(ItemDatabase.HANDS, itemObj) end
        if string.find(rawDesc, "#s10#") or gEquipLoc == "INVTYPE_WAIST" then table.insert(ItemDatabase.WAIST, itemObj) end
        if string.find(rawDesc, "#s11#") or gEquipLoc == "INVTYPE_LEGS" then table.insert(ItemDatabase.LEGS, itemObj) end
        if string.find(rawDesc, "#s12#") or gEquipLoc == "INVTYPE_FEET" then table.insert(ItemDatabase.FEET, itemObj) end
        if string.find(rawDesc, "#s13#") or gEquipLoc == "INVTYPE_FINGER" then table.insert(ItemDatabase.FINGER, itemObj) end
        if string.find(rawDesc, "#s14#") or gEquipLoc == "INVTYPE_TRINKET" then table.insert(ItemDatabase.TRINKET, itemObj) end

        -- Weapons & Off-hands & Ranged
        if string.find(rawDesc, "#h1#") or string.find(rawDesc, "#h2#") or string.find(rawDesc, "#h3#") or gEquipLoc == "INVTYPE_WEAPON" or gEquipLoc == "INVTYPE_2HWEAPON" or gEquipLoc == "INVTYPE_WEAPONMAINHAND" then
            table.insert(ItemDatabase.MAINHAND, itemObj)
        end
        if string.find(rawDesc, "#h1#") or string.find(rawDesc, "#h4#") or string.find(rawDesc, "#w8#") or string.find(rawDesc, "#s15#") or gEquipLoc == "INVTYPE_WEAPON" or gEquipLoc == "INVTYPE_WEAPONOFFHAND" or gEquipLoc == "INVTYPE_SHIELD" or gEquipLoc == "INVTYPE_HOLDABLE" then
            table.insert(ItemDatabase.OFFHAND, itemObj)
        end
        if string.find(rawDesc, "#s16#") or string.find(rawDesc, "#w2#") or string.find(rawDesc, "#w3#") or string.find(rawDesc, "#w5#") or string.find(rawDesc, "#w11#") or string.find(rawDesc, "#w12#") or gEquipLoc == "INVTYPE_RANGED" or gEquipLoc == "INVTYPE_RANGEDRIGHT" or gEquipLoc == "INVTYPE_THROWN" or gEquipLoc == "INVTYPE_RELIC" then
            table.insert(ItemDatabase.RANGED, itemObj)
        end
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
                    for _, v in ipairs(data) do
                        ParseEntry(v, dataID)
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
local FilterLevel = "40+"
local SortMode = "LVL_ASC"
local FilterSearchText = ""
local CurrentBrowserItems = {}
local BrowserPage = 1
local ROWS_PER_PAGE = 7
local enchMenuFrame = nil

local ArmorButtons = {}
local LevelButtons = {}
local SortButtonRef = nil

local function GetEffectiveLevel(item)
    if not item then return 0 end
    if item.reqLevel and item.reqLevel > 0 then
        return item.reqLevel
    end
    local gName, _, gQual, gLevel, gMinLevel = GetItemInfo(item.id)
    if gMinLevel and gMinLevel > 0 then
        item.reqLevel = gMinLevel
        item.itemLevel = gLevel or gMinLevel
        return gMinLevel
    end
    if scanner then
        scanner:ClearLines()
        scanner:SetHyperlink("item:" .. item.id .. ":0:0:0")
        for i = 1, 10 do
            local line = _G["OctoBiSScannerTooltipTextLeft" .. i]
            if line and line:IsShown() then
                local txt = line:GetText()
                if txt then
                    local _, _, r = string.find(txt, "Requires Level (%d+)")
                    if r then
                        local rNum = tonumber(r)
                        item.reqLevel = rNum
                        return rNum
                    end
                end
            end
        end
    end
    if item.sourceMinLvl and item.sourceMinLvl > 0 then
        return item.sourceMinLvl
    end
    if item.itemLevel and item.itemLevel > 0 then
        return math.max(1, item.itemLevel - 5)
    end
    if gLevel and gLevel > 0 then
        item.itemLevel = gLevel
        return math.max(1, gLevel - 5)
    end
    return 0
end

local function MatchesLevelFilter(effLvl, item, filter)
    if filter == "ALL" then return true end
    if filter == "40+" then
        if effLvl >= 40 then return true end
        if item.itemLevel and item.itemLevel >= 43 then return true end
        if item.sourceMinLvl and item.sourceMinLvl >= 38 then return true end
        return false
    elseif filter == "40-49" then
        if effLvl >= 40 and effLvl <= 49 then return true end
        if (effLvl == 0 or effLvl < 40) and item.sourceMinLvl and item.sourceMinLvl >= 38 and item.sourceMinLvl <= 49 then return true end
        return false
    elseif filter == "50-59" then
        if effLvl >= 50 and effLvl <= 59 then return true end
        if (effLvl == 0 or effLvl < 50) and item.sourceMinLvl and item.sourceMinLvl >= 50 and item.sourceMinLvl <= 59 then return true end
        return false
    elseif filter == "60" then
        if effLvl >= 60 then return true end
        if item.sourceMinLvl and item.sourceMinLvl >= 60 then return true end
        if item.itemLevel and item.itemLevel >= 65 then return true end
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

    -- 1. Sum up gear stats
    for slotName, item in pairs(EquippedGear) do
        if item and item.id then
            local s = ScanItemStats(item.id)
            for k, val in pairs(s) do
                if total[k] then total[k] = total[k] + val end
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

    -- Update Stat display labels
    if StatLabels.str then StatLabels.str:SetText(string.format("Strength: |cFFFFFFFF%d|r", total.str)) end
    if StatLabels.agi then StatLabels.agi:SetText(string.format("Agility: |cFFFFFFFF%d|r", total.agi)) end
    if StatLabels.sta then StatLabels.sta:SetText(string.format("Stamina: |cFFFFFFFF%d|r", total.sta)) end
    if StatLabels.armor then StatLabels.armor:SetText(string.format("Armor: |cFFFFFFFF%d|r", total.armor)) end
    if StatLabels.ap then StatLabels.ap:SetText(string.format("Attack Power: |cFFFFD100%d|r", total.ap + (total.str * 2))) end
    if StatLabels.hit then StatLabels.hit:SetText(string.format("Hit Rating: |cFF00FFCC+%d%%|r", total.hit)) end
    if StatLabels.crit then StatLabels.crit:SetText(string.format("Crit Bonus: |cFF00FFCC+%.1f%%|r", total.crit + (total.agi / 20))) end
    if StatLabels.def then StatLabels.def:SetText(string.format("Defense: |cFF00FFCC+%d|r", total.defense)) end
    if StatLabels.dodge then StatLabels.dodge:SetText(string.format("Dodge: |cFF00FFCC+%.1f%%|r", total.dodge + (total.agi / 20))) end
    if StatLabels.parry then StatLabels.parry:SetText(string.format("Parry: |cFF00FFCC+%d%%|r", total.parry)) end
    if StatLabels.block then StatLabels.block:SetText(string.format("Block: |cFF00FFCC+%d%%|r", total.block)) end
    if StatLabels.sp then StatLabels.sp:SetText(string.format("Spell Power: |cFFCC99FF+%d|r", total.spellDmg)) end
    if StatLabels.heal then StatLabels.heal:SetText(string.format("Bonus Heal: |cFF33FF66+%d|r", total.healing)) end
end

local function RefreshSlotDisplay(slotName)
    local btn = SlotButtons[slotName]
    if not btn then return end

    local item = EquippedGear[slotName]
    if item and item.icon then
        btn.icon:SetTexture(item.icon)
        btn.icon:SetVertexColor(1, 1, 1, 1)
        btn.icon:Show()
        local qc = QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]
        btn:SetBackdropBorderColor(qc[1], qc[2], qc[3], 1)
        btn.hasItem = true
    elseif btn.defaultIcon then
        btn.icon:SetTexture(btn.defaultIcon)
        btn.icon:SetVertexColor(0.28, 0.28, 0.32, 0.5)
        btn.icon:Show()
        btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.7)
        btn.hasItem = false
    else
        btn.icon:Hide()
        btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.7)
        btn.hasItem = false
    end

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

    for _, it in ipairs(rawList) do
        local matchArmor = (FilterArmor == "ALL") or (it.armorType == FilterArmor) or (it.weaponType == FilterArmor)
        local matchText = (searchLower == "") or (string.find(string.lower(it.name or ""), searchLower, 1, true) ~= nil)

        local effLvl = GetEffectiveLevel(it)
        local matchLevel = MatchesLevelFilter(effLvl, it, FilterLevel)

        if matchArmor and matchText and matchLevel then
            table.insert(CurrentBrowserItems, it)
        end
    end

    -- Sort according to SortMode
    table.sort(CurrentBrowserItems, function(a, b)
        local effA = GetEffectiveLevel(a)
        local effB = GetEffectiveLevel(b)
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

    Planner.pageText:SetText(string.format("Page %d / %d  (%d items)", BrowserPage, maxPage, total))

    local startIndex = (BrowserPage - 1) * ROWS_PER_PAGE
    for i = 1, ROWS_PER_PAGE do
        local row = BrowserRows[i]
        local item = CurrentBrowserItems[startIndex + i]
        if item then
            row.item = item
            row.icon:SetTexture(item.icon)
            local qc = QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]

            -- Lazy cache update from GetItemInfo if item was generic
            if string.find(item.name, "^Item #") then
                local gName, _, gQual, gLvl, gMinLvl, _, _, _, _, gTex = GetItemInfo(item.id)
                if gName then
                    item.name = gName
                    item.quality = gQual or item.quality
                    qc = QUALITY_COLORS[item.quality] or qc
                    if gMinLvl and gMinLvl > 0 then item.reqLevel = gMinLvl end
                    if gLvl and gLvl > 0 then item.itemLevel = gLvl end
                    if gTex then item.icon = gTex; row.icon:SetTexture(gTex) end
                end
            end

            local effLvl = GetEffectiveLevel(item)
            local lvlText = ""
            if item.reqLevel and item.reqLevel > 0 then
                lvlText = string.format(" |cFFFFD100[Req %d]|r", item.reqLevel)
            elseif item.itemLevel and item.itemLevel > 0 then
                lvlText = string.format(" |cFF88BBFF[iLvl %d]|r", item.itemLevel)
            elseif effLvl > 0 then
                lvlText = string.format(" |cFFFFD100[Req %d]|r", effLvl)
            end

            row.name:SetText(item.name .. lvlText)
            row.name:SetTextColor(qc[1], qc[2], qc[3])
            local typeStr = item.armorType or item.weaponType or "Item"
            row.sub:SetText(string.format("|cFF999999%s • %s|r", typeStr, item.source))
            row:SetBackdropBorderColor(qc[1], qc[2], qc[3], 0.7)
            row:Show()
        else
            row.item = nil
            row:Hide()
        end
    end

    UpdateFilterButtons()
end

local function OpenSlotBrowser(slot)
    ActiveSlot = slot
    IndexAtlasLootData()
    Planner.browserTitle:SetText(string.format("Selecting: |cFFFFD100%s|r", slot.label))
    BrowserPage = 1
    UpdateBrowserList()
    Planner.browserPanel:Show()
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

    Planner:SetWidth(580)
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

            local enchTxt = enchBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            enchTxt:SetPoint("CENTER", enchBtn, "CENTER", 0, 0)
            if STANDARD_TEXT_FONT then
                enchTxt:SetFont(STANDARD_TEXT_FONT, 8, "")
            end
            enchTxt:SetText("|cFF777777[ench]|r")
            enchBtn.text = enchTxt

            enchBtn:SetScript("OnClick", function()
                OpenEnchantPicker(slot)
            end)
            enchBtn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(slot.label .. " Enchant")
                GameTooltip:AddLine("|cFF00FFCCClick to pick an enchant for this slot.|r")
                GameTooltip:Show()
            end)
            enchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn.enchButton = enchBtn
        end

        -- Slot Button Clicks
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function()
            if arg1 == "RightButton" then
                -- Clear slot
                EquippedGear[slot.name] = nil
                EquippedEnchants[slot.name] = nil
                RefreshSlotDisplay(slot.name)
            else
                if IsShiftKeyDown() and slot.enchant then
                    OpenEnchantPicker(slot)
                else
                    OpenSlotBrowser(slot)
                end
            end
        end)

        btn:SetScript("OnEnter", function()
            local it = EquippedGear[slot.name]
            if it then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. it.id .. ":0:0:0")
                local ench = EquippedEnchants[slot.name]
                if ench then
                    GameTooltip:AddLine("Enchant: |cFF00FFCC" .. ench.name .. "|r")
                end
                GameTooltip:AddLine("|cFF888888<Right-Click to Clear Slot>|r")
                if slot.enchant then
                    GameTooltip:AddLine("|cFF00FFCC<Shift-Click to Pick Enchant>|r")
                end
                GameTooltip:Show()
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(slot.label)
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
        fBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        fBtn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
        local txt = fBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER", fBtn, "CENTER", 0, 0)
        txt:SetText(af.name)
        fBtn.text = txt
        local aName = af.name
        fBtn:SetScript("OnClick", function()
            FilterArmor = aName
            BrowserPage = 1
            UpdateBrowserList()
        end)
        ArmorButtons[aName] = fBtn
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
        lBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        lBtn:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
        local txt = lBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("CENTER", lBtn, "CENTER", 0, 0)
        txt:SetText(lf.name)
        lBtn.text = txt
        local lvlName = lf.name
        lBtn:SetScript("OnClick", function()
            FilterLevel = lvlName
            BrowserPage = 1
            UpdateBrowserList()
        end)
        LevelButtons[lvlName] = lBtn
    end

    -- Sort Toggle Button (Line 3 Right)
    local sortBtn = CreateFrame("Button", nil, browser)
    sortBtn:SetWidth(84)
    sortBtn:SetHeight(16)
    sortBtn:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -8, -44)
    sortBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    sortBtn:SetBackdropColor(0.12, 0.16, 0.22, 0.9)
    sortBtn:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.8)
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
        UpdateBrowserList()
    end)
    sortBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort Order")
        GameTooltip:AddLine("Click to cycle between:", 1, 1, 1)
        GameTooltip:AddLine("• |cFFFFD100Sort: Lvl ▲|r (Level ascending - level 40 first)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• |cFFFFD100Sort: Lvl ▼|r (Level descending - level 60 first)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• |cFFFFD100Sort: Qual|r (Quality - Epics first)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SortButtonRef = sortBtn

    -- Browser Rows (7 rows)
    for i = 1, ROWS_PER_PAGE do
        local row = CreateFrame("Button", "OctoBiSRow_" .. i, browser)
        row:SetWidth(276)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", browser, "TOPLEFT", 8, -64 - ((i - 1) * 35))
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

        local rIcon = row:CreateTexture(nil, "ARTWORK")
        rIcon:SetWidth(24)
        rIcon:SetHeight(24)
        rIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
        rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = rIcon

        local rName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rName:SetPoint("TOPLEFT", rIcon, "TOPRIGHT", 6, 0)
        rName:SetJustifyH("LEFT")
        rName:SetText("Item Name")
        row.name = rName

        local rSub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rSub:SetPoint("BOTTOMLEFT", rIcon, "BOTTOMRIGHT", 6, 1)
        rSub:SetJustifyH("LEFT")
        rSub:SetText("Source")
        row.sub = rSub

        row:SetScript("OnClick", function()
            if this.item and ActiveSlot then
                EquippedGear[ActiveSlot.name] = this.item
                RefreshSlotDisplay(ActiveSlot.name)
            end
        end)

        row:SetScript("OnEnter", function()
            if this.item then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. this.item.id .. ":0:0:0")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    -- 3. RIGHT PANEL: Live Stat Summary
    -- ------------------------------------------------------------------------
    local statPanel = CreateFrame("Frame", "OctoBiSStatPanel", Planner)
    statPanel:SetWidth(136)
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

    local function MakeStat(name, yOff)
        local fs = statPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, yOff)
        fs:SetJustifyH("LEFT")
        return fs
    end

    StatLabels.str = MakeStat("Strength", -22)
    StatLabels.agi = MakeStat("Agility", -35)
    StatLabels.sta = MakeStat("Stamina", -48)
    StatLabels.armor = MakeStat("Armor", -61)

    local line1 = statPanel:CreateTexture(nil, "ARTWORK")
    line1:SetWidth(120) line1:SetHeight(1) line1:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -75)
    line1:SetTexture(0.5, 0.5, 0.5, 0.8)

    StatLabels.ap = MakeStat("AP", -79)
    StatLabels.hit = MakeStat("Hit", -92)
    StatLabels.crit = MakeStat("Crit", -105)

    local line2 = statPanel:CreateTexture(nil, "ARTWORK")
    line2:SetWidth(120) line2:SetHeight(1) line2:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -119)
    line2:SetTexture(0.5, 0.5, 0.5, 0.8)

    StatLabels.def = MakeStat("Defense", -123)
    StatLabels.dodge = MakeStat("Dodge", -136)
    StatLabels.parry = MakeStat("Parry", -149)
    StatLabels.block = MakeStat("Block", -162)

    local line3 = statPanel:CreateTexture(nil, "ARTWORK")
    line3:SetWidth(120) line3:SetHeight(1) line3:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 8, -176)
    line3:SetTexture(0.5, 0.5, 0.5, 0.8)

    StatLabels.sp = MakeStat("SpellPower", -180)
    StatLabels.heal = MakeStat("Healing", -193)

    -- Quick Action Buttons
    local impBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    impBtn:SetWidth(120) impBtn:SetHeight(20)
    impBtn:SetPoint("BOTTOM", statPanel, "BOTTOM", 0, 52)
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
                            local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
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
    clrBtn:SetWidth(120) clrBtn:SetHeight(20)
    clrBtn:SetPoint("BOTTOM", statPanel, "BOTTOM", 0, 28)
    clrBtn:SetText("Clear All")
    clrBtn:SetScript("OnClick", function()
        EquippedGear = {}
        EquippedEnchants = {}
        for _, s in ipairs(SLOTS) do RefreshSlotDisplay(s.name) end
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFCC[OctoBiS Planner]|r Cleared all slots.")
    end)

    local shareBtn = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    shareBtn:SetWidth(120) shareBtn:SetHeight(20)
    shareBtn:SetPoint("BOTTOM", statPanel, "BOTTOM", 0, 4)
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
        BuildUI()
    end
    if Planner:IsShown() then
        Planner:Hide()
    else
        IndexAtlasLootData()
        Planner:ClearAllPoints()
        if CharacterFrame and CharacterFrame:IsShown() then
            Planner:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 15, 0)
        else
            Planner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        Planner:Show()
        UpdateStatSummary()
    end
end

SLASH_OCTOBIS1 = "/bis"
SLASH_OCTOBIS2 = "/gearplanner"
SLASH_OCTOBIS3 = "/octobis"
SlashCmdList["OCTOBIS"] = function(msg)
    OctoBiSPlanner_Toggle()
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
