--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny / brian / Mewtiny
	License: MIT License
]]

-- DEBUG: Error catcher for "attempt to index a function value"
-- Remove this block once the error is identified
local _G = _G or getfenv(0)
local originalErrorHandler = geterrorhandler and geterrorhandler()
if seterrorhandler then
    seterrorhandler(function(msg)
        if msg and string.find(msg, "index a function value") then
            local trace = debugstack and debugstack(2, 20, 0) or "no stack available"
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[SCRM DEBUG] index function error:|r " .. tostring(msg))
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Stack:|r " .. tostring(trace))
        end
        if originalErrorHandler then
            return originalErrorHandler(msg)
        end
    end)
end

-- Setup to wrap our stuff in a table so we don't pollute the global environment
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids
CleveRoids.lastItemIndexTime = 0
CleveRoids.initializationTimer = nil
CleveRoids.isActionUpdateQueued = true
CleveRoids.lastEquipTime = CleveRoids.lastEquipTime or {}
CleveRoids.lastWeaponSwapTime = 0
CleveRoids.equipInProgress = false

-- PERFORMANCE: Event throttling to reduce spam from high-frequency events
CleveRoids.lastUnitAuraUpdate = 0
CleveRoids.lastUnitHealthUpdate = 0
CleveRoids.lastUnitPowerUpdate = 0
CleveRoids.EVENT_THROTTLE = 0.1  -- 100ms throttle for high-frequency events

CleveRoids.playerGuid = CleveRoids.GetGUID and CleveRoids.GetGUID('player') or (UnitGUID and UnitGUID('player')) or nil
CleveRoids.playerClass = UnitClassBase and UnitClassBase("player") or (UnitClass and ({UnitClass("player")})[2]) or nil

-- PERFORMANCE: Upvalues for frequently called global functions (avoid global lookups)
local GetTime = GetTime
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots
local GetItemInfo = GetItemInfo
local PickupContainerItem = PickupContainerItem
local PickupInventoryItem = PickupInventoryItem
local EquipCursorItem = EquipCursorItem
local CursorHasItem = CursorHasItem
local ClearCursor = ClearCursor
local TargetUnit = TargetUnit
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local tostring = tostring
local string_lower = string.lower
local string_gsub = string.gsub
local table_insert = table.insert
local table_getn = table.getn

-- Deferred stop-attack system (CheapShot pattern)
-- Stops autoattack and clears target. OnUpdate keeps clearing target while
-- autoattack is queued to prevent any swing from landing. No retarget.
local _DeferStopFrame = CreateFrame("Frame")
local _deferStopActive = false
local _deferStartTime = 0
local DEFER_STOP_TIMEOUT = 0.5

_DeferStopFrame:SetScript("OnUpdate", function()
    if not _deferStopActive then
        _DeferStopFrame:Hide()
        return
    end

    -- Timeout: stop polling
    if (GetTime() - _deferStartTime) >= DEFER_STOP_TIMEOUT then
        _deferStopActive = false
        _DeferStopFrame:Hide()
        return
    end

    -- While autoattack is queued, keep clearing target to prevent swings
    if not GetCurrentCastingInfo then
        _deferStopActive = false
        _DeferStopFrame:Hide()
        return
    end
    local _,_,_,_,_,_,autoattack = GetCurrentCastingInfo()
    if autoattack == 1 then
        if UnitExists("target") then
            ClearTarget()
        end
    else
        -- Autoattack stopped, done
        _deferStopActive = false
        _DeferStopFrame:Hide()
    end
end)
_DeferStopFrame:Hide()

function CleveRoids.DeferStopAttack()
    CleveRoids.CurrentSpell.autoAttack = false
    CleveRoids.CurrentSpell.autoAttackLock = false
    _deferStartTime = GetTime()
    -- Only toggle auto-attack OFF if it's currently active (avoid turning it ON)
    local attackSlot = CleveRoids.GetProxyActionSlot(CleveRoids.Localized.Attack)
    if attackSlot and CleveRoids.Hooks.IsCurrentAction(attackSlot) then
        AttackTarget()
    end
    ClearTarget()
    _deferStopActive = true
    _DeferStopFrame:Show()
end

-- PERFORMANCE: Module-level constant for boolean conditionals (avoid per-call table creation)
local BOOLEAN_CONDITIONALS = {
    combat = true,
    nocombat = true,
    stealth = true,
    nostealth = true,
    mounted = true,
    nomounted = true,
    standing = true,
    sitting = true,
    channeled = true,
    nochanneled = true,
    checkchanneled = true,
    checkcasting = true,
    dead = true,
    alive = true,
    help = true,
    harm = true,
    exists = true,
    party = true,
    raid = true,
    resting = true,
    noresting = true,
    isplayer = true,
    isnpc = true,
    mhimbue = true,
    nomhimbue = true,
    ohimbue = true,
    noohimbue = true,
    mhenchant = true,
    nomhenchant = true,
    ohenchant = true,
    noohenchant = true,
    locked = true,
    nolocked = true,
    indoors = true,
    noindoors = true,
    outdoors = true,
    nooutdoors = true,
    group = true,
    nogroup = true,
    moving = true,
    nomoving = true,
    stopattack = true,
    pet = true,
    nopet = true,
    pethappiness = true,
    nopethappiness = true,
    focus = true,
    nofocus = true,
    bg = true,
    nobg = true,
    -- Dispel-type conditionals (ClassicAPI C_UnitAuras)
    magic = true,
    nomagic = true,
    curse = true,
    nocurse = true,
    disease = true,
    nodisease = true,
    poison = true,
    nopoison = true,
    dispellable = true,
    nodispellable = true,
    magicbuff = true,
    nomagicbuff = true,
    dispellablebuff = true,
    nodispellablebuff = true,
}

local requirementCheckFrame = CreateFrame("Frame")
requirementCheckFrame:RegisterEvent("ADDON_LOADED")
requirementCheckFrame:SetScript("OnEvent", function()
    if arg1 ~= "SuperCleveRoidMacros" then return end

    -- Check requirements immediately when our addon loads
    local hasNampower = (IsSpellInRange ~= nil)
    local hasUnitXP = pcall(UnitXP, "nop", "nop")
    local hasNampower30 = hasNampower and CleveRoids.NampowerAPI
        and CleveRoids.NampowerAPI.HasMinimumVersion(3, 0, 0)
    local hasClassicAPI = CleveRoids.ClassicAPI and CleveRoids.ClassicAPI.IsAvailable()
    local hasClassicAPIMin = hasClassicAPI and CleveRoids.ClassicAPI.HasMinimumVersion(1, 18, 1)

    if not hasNampower30 or not hasUnitXP or not hasClassicAPI or not hasClassicAPIMin then
        -- Show warnings (don't disable — tearing down a partially-initialized addon causes hangs)
        if not hasNampower then
            CleveRoids.Print("|cFFFF9900WARNING:|r |cFF00FFFFAvitasia's Nampower v3.0.0+|r is required:")
            CleveRoids.Print("https://github.com/brues-code/nampower")
            CleveRoids.Print("Many features will be unavailable without Nampower.")
        elseif not hasNampower30 then
            local major, minor, patch = CleveRoids.NampowerAPI.GetVersion()
            CleveRoids.Print(format("|cFFFF9900WARNING:|r |cFF00FFFFNampower v3.0.0+|r is required (you have v%d.%d.%d):", major, minor, patch))
            CleveRoids.Print("https://github.com/brues-code/nampower")
            CleveRoids.Print("Some features may be unavailable with this version.")
        end
        if not hasUnitXP then
            CleveRoids.Print("|cFFFF9900WARNING:|r |cFF00FFFFKonaka's UnitXP_SP3|r is required:")
            CleveRoids.Print("https://codeberg.org/konaka/UnitXP_SP3")
        end
        if not hasClassicAPI then
            CleveRoids.Print("|cFFFF9900WARNING:|r |cFF00FFFFClassicAPI|r is required:")
            CleveRoids.Print("https://github.com/brues-code/ClassicAPI")
            CleveRoids.Print("Dispel-type and movement conditionals will be unavailable without it.")
        elseif not hasClassicAPIMin then
            local major, minor, patch = CleveRoids.ClassicAPI.GetVersion()
            CleveRoids.Print(format("|cFFFF9900WARNING:|r |cFF00FFFFClassicAPI v1.18.1+|r is required (you have v%d.%d.%d):", major, minor, patch))
            CleveRoids.Print("https://github.com/brues-code/ClassicAPI")
            CleveRoids.Print("The addon cannot finish loading on this version -- update ClassicAPI.")
        end
    end

    -- Requirements met - allow normal initialization
    CleveRoids.Print("|cFF4477FFSuperCleveR|r|cFFFFFFFFoid Macros|r |cFF00FF00Loaded|r - See the README.")

    -- Unregister this check frame
    this:UnregisterAllEvents()
end)

local SLOT_TO_INVID = {
    ["MainHandSlot"] = 16,
    ["SecondaryHandSlot"] = 17,
    ["RangedSlot"] = 18,
    ["HeadSlot"] = 1,
    ["NeckSlot"] = 2,
    ["ShoulderSlot"] = 3,
    ["ChestSlot"] = 5,
    ["WaistSlot"] = 6,
    ["LegsSlot"] = 7,
    ["FeetSlot"] = 8,
    ["WristSlot"] = 9,
    ["HandsSlot"] = 10,
    ["Finger0Slot"] = 11,
    ["Finger1Slot"] = 12,
    ["Trinket0Slot"] = 13,
    ["Trinket1Slot"] = 14,
    ["BackSlot"] = 15,
    ["ShirtSlot"] = 4,
    ["TabardSlot"] = 19,
}

local function GetInventoryIdFromSlot(slotName)
    return SLOT_TO_INVID[slotName] or GetInventorySlotInfo(slotName)
end

-- Check if slot 18 is a relic (no GCD). Backed by CleveRoids.hasRelicSlot, cached
-- at PLAYER_LOGIN -- see the note there on why it can't be sampled on demand.
local function IsRelicSlot(slot)
    if slot ~= 18 then return false end
    return CleveRoids.hasRelicSlot or false
end

-- PERFORMANCE: Cache GetTime() result for cooldown checks within same frame
-- Slot 18 (relic/idol/libram/totem) has no GCD for Paladin/Druid/Shaman
local function IsSlotOnCooldown(slot, now)
    -- Relics have no GCD - skip cooldown check entirely
    if IsRelicSlot(slot) then
        return false
    end

    now = now or GetTime()
    local slotTime = CleveRoids.lastEquipTime[slot] or 0
    local globalTime = CleveRoids.lastGlobalEquipTime or 0

    return (now - slotTime) < CleveRoids.EQUIP_COOLDOWN or
           (now - globalTime) < CleveRoids.EQUIP_GLOBAL_COOLDOWN
end

-- PERFORMANCE: Consolidated cursor handling, fewer CursorHasItem() calls
local function PerformEquipSwap(item, inventoryId, useQueueScript)
    if not item or not inventoryId then return false end

    -- Check if in combat and swapping weapons
    -- Slot 18 is a ranged weapon for exactly the classes with no relic slot; for
    -- Paladin/Druid/Shaman it's an idol/libram/totem that can swap freely.
    local isWeapon = (inventoryId == 16 or inventoryId == 17)
    if inventoryId == 18 then
        isWeapon = not IsRelicSlot(inventoryId)
    end

    if isWeapon and UnitAffectingCombat("player") then
        -- Don't swap while casting
        if CleveRoids.GetPlayerCast() then
            return false
        end

        -- Check for on-swing spells if available (Nampower)
        if GetCurrentCastingInfo then
            local castId, _, _, casting, channeling, onswing = GetCurrentCastingInfo()

            if onswing == 1 then
                return false
            end

            -- If casting/channeling and QueueScript available, queue the swap for after cast
            if (casting == 1 or channeling == 1) and QueueScript and useQueueScript and item.name then
                local script = string.format('EquipItemByName("%s",%d)', item.name, inventoryId)
                QueueScript(script, 3)  -- Priority 3 = after queued spells
                return true
            end
        end
    end

    -- PERFORMANCE: Try EquipItemByName first if available (handles everything internally)
    if item.name and EquipItemByName then
        local ok = pcall(EquipItemByName, item.name, inventoryId)
        if ok then return true end
    end

    -- Fallback: Manual pickup and equip
    if item.bagID and item.slot then
        PickupContainerItem(item.bagID, item.slot)
    elseif item.inventoryID then
        PickupInventoryItem(item.inventoryID)
    else
        return false
    end

    -- Single cursor check after pickup attempt
    if not CursorHasItem() then
        return false
    end

    EquipCursorItem(inventoryId)
    local success = not CursorHasItem()
    ClearCursor()
    return success
end

-- PERFORMANCE: Get a queue entry from pool or create new
local function GetQueueEntry()
    local pool = CleveRoids.queueEntryPool
    local n = pool and table_getn(pool) or 0
    if n > 0 then
        local entry = pool[n]
        pool[n] = nil
        return entry
    end
    return {}
end

-- PERFORMANCE: Return entry to pool for reuse
local function ReleaseQueueEntry(entry)
    if not entry then return end
    -- Clear the entry (set to nil, don't create new table)
    entry.item = nil
    entry.slotName = nil
    entry.inventoryId = nil
    entry.queueTime = nil
    entry.retries = nil
    entry.maxRetries = nil
    entry.itemId = nil
    -- Add to pool (max 10 pooled entries)
    local pool = CleveRoids.queueEntryPool
    if table_getn(pool) < 10 then
        table_insert(pool, entry)
    end
end

-- PERFORMANCE: Swap-and-pop removal (O(1) instead of O(n))
local function RemoveQueueEntry(i)
    local queue = CleveRoids.equipmentQueue
    local n = CleveRoids.equipmentQueueLen
    local entry = queue[i]

    if i < n then
        queue[i] = queue[n]
    end
    queue[n] = nil
    CleveRoids.equipmentQueueLen = n - 1

    ReleaseQueueEntry(entry)
end

-- Queue equipment swap function
function CleveRoids.QueueEquipItem(item, slotName)
    if not item or not slotName then return false end

    local inventoryId = GetInventoryIdFromSlot(slotName)
    if not inventoryId then return false end

    local now = GetTime()
    local itemId = item.id

    -- PERFORMANCE: Check for duplicate queue entries before adding
    local queue = CleveRoids.equipmentQueue
    local queueLen = CleveRoids.equipmentQueueLen
    for i = 1, queueLen do
        local q = queue[i]
        if q and q.inventoryId == inventoryId and q.itemId == itemId then
            return false  -- Already queued
        end
    end

    -- Try immediate equip if not on cooldown (use QueueScript for smoother mid-cast swaps)
    if not IsSlotOnCooldown(inventoryId, now) then
        local success = PerformEquipSwap(item, inventoryId, true)

        if success then
            -- Don't set cooldowns for relic slots (no GCD)
            if not IsRelicSlot(inventoryId) then
                CleveRoids.lastEquipTime[inventoryId] = now
                CleveRoids.lastGlobalEquipTime = now
            end
            return true
        end
    end

    -- Queue for later using pooled entry
    local entry = GetQueueEntry()
    entry.item = item
    entry.slotName = slotName
    entry.inventoryId = inventoryId
    entry.queueTime = now
    entry.retries = 0
    entry.maxRetries = 5
    entry.itemId = itemId

    CleveRoids.equipmentQueueLen = queueLen + 1
    queue[CleveRoids.equipmentQueueLen] = entry

    -- PERFORMANCE: Start the queue processing frame
    if CleveRoids.equipQueueFrame then
        CleveRoids.equipQueueFrame:Show()
    end

    return false
end

-- PERFORMANCE: Process equipment queue (called from self-disabling frame)
function CleveRoids.ProcessEquipmentQueue()
    local queueLen = CleveRoids.equipmentQueueLen
    if queueLen == 0 then return end

    local now = GetTime()
    local queue = CleveRoids.equipmentQueue
    local i = 1

    while i <= CleveRoids.equipmentQueueLen do
        local queued = queue[i]

        -- Remove expired entries first (>10 seconds old)
        if (now - queued.queueTime) > 10 then
            RemoveQueueEntry(i)
            -- Don't increment i, we swapped in the last element
        elseif not IsSlotOnCooldown(queued.inventoryId, now) then
            -- Try to equip (use QueueScript for smoother mid-cast swaps)
            local success = PerformEquipSwap(queued.item, queued.inventoryId, true)

            if success then
                -- Don't set cooldowns for relic slots (no GCD)
                if not IsRelicSlot(queued.inventoryId) then
                    CleveRoids.lastEquipTime[queued.inventoryId] = now
                    CleveRoids.lastGlobalEquipTime = now
                end
                RemoveQueueEntry(i)
            else
                queued.retries = queued.retries + 1
                if queued.retries >= queued.maxRetries then
                    RemoveQueueEntry(i)
                else
                    i = i + 1
                end
            end
        else
            i = i + 1
        end
    end
end

-- PERFORMANCE: Self-disabling frame for queue processing with throttling
-- Only processes every EQUIP_QUEUE_INTERVAL instead of every frame
CleveRoids.EQUIP_QUEUE_INTERVAL = 0.1  -- 100ms between queue checks (was 50ms)
CleveRoids.equipQueueLastUpdate = 0
CleveRoids.equipQueueFrame = CreateFrame("Frame")
CleveRoids.equipQueueFrame:Hide()

-- PERFORMANCE: Upvalue for faster access in OnUpdate
local equipQueueFrame = CleveRoids.equipQueueFrame
local equipQueueInterval = CleveRoids.EQUIP_QUEUE_INTERVAL

equipQueueFrame:SetScript("OnUpdate", function()
    -- Prevent operations during shutdown (crash prevention)
    if CleveRoids.isShuttingDown then return end

    -- PERFORMANCE: Use arg1 (elapsed time) if available, otherwise GetTime()
    local elapsed = arg1
    if elapsed then
        CleveRoids.equipQueueLastUpdate = (CleveRoids.equipQueueLastUpdate or 0) + elapsed
        if CleveRoids.equipQueueLastUpdate < equipQueueInterval then
            return  -- Throttle: skip this frame
        end
        CleveRoids.equipQueueLastUpdate = 0
    else
        local now = GetTime()
        if (now - (CleveRoids.equipQueueLastUpdate or 0)) < equipQueueInterval then
            return
        end
        CleveRoids.equipQueueLastUpdate = now
    end

    CleveRoids.ProcessEquipmentQueue()
    if CleveRoids.equipmentQueueLen == 0 then
        this:Hide()
    end
end)

-- Improved DisableAddon function
function CleveRoids.DisableAddon(reason)
    -- Prevent multiple disable calls
    if CleveRoids.disabled then return end

    -- Mark state
    CleveRoids.disabled = true

    -- Hand macro display back to ClassicAPI's own #showtooltip parser before we go
    -- quiet, or every claimed macro would keep the last value we published.
    if CleveRoids.ReleaseDisplays then
        CleveRoids.ReleaseDisplays()
    end

    -- Stop main frame activity
    if CleveRoids.Frame then
        if CleveRoids.Frame.UnregisterAllEvents then
            CleveRoids.Frame:UnregisterAllEvents()
        end
        if CleveRoids.Frame.SetScript then
            CleveRoids.Frame:SetScript("OnEvent", nil)
            CleveRoids.Frame:SetScript("OnUpdate", nil)
        end
    end

    -- Neuter all slash commands
    if SlashCmdList then
        local disabledMsg = function()
            CleveRoids.Print("|cffff0000SuperCleveRoidMacros is disabled|r" ..
                (reason and (": " .. tostring(reason)) or ""))
        end

        SlashCmdList.CLEVEROID = disabledMsg
        SlashCmdList.CAST = disabledMsg
        SlashCmdList.USE = disabledMsg
        SlashCmdList.FEEDPET = disabledMsg
        SlashCmdList.EQUIP = disabledMsg
        SlashCmdList.EQUIPMH = disabledMsg
        SlashCmdList.EQUIPOH = disabledMsg
    end

    -- Try to disable for next login
    local addonName = "SuperCleveRoidMacros"
    if type(DisableAddOn) == "function" then
        pcall(DisableAddOn, addonName)
    end

    -- Final notice
    CleveRoids.Print("|cffff0000Disabled|r - " .. (reason or "Unknown reason"))
    CleveRoids.Print("Please install required dependencies and /reload")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:SetScript("OnEvent", function()
    if not CleveRoidMacros then CleveRoidMacros = {} end

    if type(CleveRoidMacros.realtime) ~= "number" then
        CleveRoidMacros.realtime = 0
    end

    if type(CleveRoidMacros.refresh) ~= "number" then
        CleveRoidMacros.refresh = 5
    end

    if type(CleveRoidMacros.macrocheck) ~= "number" then
        CleveRoidMacros.macrocheck = 1  -- enabled by default
    end

    -- The saved realtime setting is only readable now; the unit streams were
    -- registered at load assuming event-driven mode.
    CleveRoids.ApplyUnitStreamEvents()
end)

-- Queues a full update of all action bars.
-- This is called by game event handlers to avoid running heavy logic inside the event itself.
function CleveRoids.QueueActionUpdate()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.isActionUpdateQueued = true
    end
end

-- Count of `itemId` in *bags only* (not bank), matched by itemID throughout --
-- locale-independent, no hardcoded item names.
-- PERFORMANCE: uses the CleveRoids.Items cache (itemId -> name -> data) for an
-- O(1) lookup when available, falling back to a bag scan on a cache miss.
function CleveRoids.GetReagentCount(itemId)
  if not itemId then return 0 end

  local Items = CleveRoids.Items
  if Items then
    local itemName = Items[itemId]
    if itemName then
      local itemData = Items[itemName]
      if itemData and itemData.count and not itemData.inventoryID then
        -- Item is in bags (not equipped), return cached count
        return itemData.count
      end
    end
  end

  -- Slow path: scan bags by itemID (only on a cache miss)
  local total = 0
  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      -- Base itemID straight off the slot (no link string, no regex).
      if C_Container.GetContainerItemID(bag, slot) == itemId then
        local _, count = GetContainerItemInfo(bag, slot)
        total = total + (count or 0)
      end
    end
  end

  return total
end

-- Live bag scan for item count, bypassing Items cache to avoid stale counts
-- during bag moves (especially backpack ↔ other bag transitions)
function CleveRoids.GetLiveItemCount(itemName)
  if not itemName or itemName == "" then return 0 end
  -- Escape Lua pattern special chars in item name to avoid crashes
  local wantLower = string.lower(itemName)
  local total = 0
  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local id = C_Container.GetContainerItemID(bag, slot)
      if id then
        local name = C_Item.GetItemNameByID(id)
        if name and string.lower(name) == wantLower then
          local _, count = GetContainerItemInfo(bag, slot)
          total = total + (count or 0)
        end
      end
    end
  end
  return total
end

-- Power cost and (first) reagent for a spellbook slot, read from Spell.dbc via
-- ClassicAPI -- no GameTooltip scan, no locale-dependent string parsing. Pass
-- spellId to skip the slot->id resolution when the caller already has it.
--   cost:    C_Spell.GetSpellPowerCost returns the *effective* (talent-modified)
--            cost the engine actually charges -- matches the old tooltip value,
--            unlike GetSpellInfo().cost which is base-only.
--   reagent: C_Spell.GetSpellReagents returns { {itemID, count}, ... }; take the
--            first reagent's itemID (Spell.dbc covers reagent spells like Vanish).
-- Returns cost, reagentName (localized, for display), reagentId (for counting).
function CleveRoids.GetSpellCost(spellSlot, bookType, spellId)
  if not spellId then
    spellId = select(10, GetSpellInfo(spellSlot, bookType))
  end

  local cost = 0
  local reagent, reagentId

  if spellId then
    local costs = C_Spell.GetSpellPowerCost(spellId)
    if costs and costs[1] and costs[1].cost then
      cost = costs[1].cost
    end

    local reagents = C_Spell.GetSpellReagents(spellId)
    if reagents and reagents[1] and reagents[1].itemID then
      reagentId = reagents[1].itemID
      reagent = C_Item.GetItemNameByID(reagentId)
    end
  end

  return cost, (reagent and reagent ~= "" and tostring(reagent) or nil), reagentId
end

function CleveRoids.GetProxyActionSlot(slot)
    if not slot then return end
    return CleveRoids.actionSlots[slot] or CleveRoids.actionSlots[slot.."()"]
end

-- Resolves nested macro references for #showtooltip propagation
-- If an action is a {MacroName} reference and that macro has #showtooltip,
-- returns the inner macro's active action; otherwise returns nil
-- depth parameter prevents infinite recursion
function CleveRoids.ResolveNestedMacroActive(action, depth)
    if not action or not action.action then return nil end
    depth = depth or 0
    if depth > 5 then return nil end  -- prevent infinite recursion

    -- Check if this action is a macro reference {MacroName}
    local macroName = CleveRoids.GetMacroNameFromAction(action.action)
    if not macroName then return nil end

    -- Get or parse the inner macro
    local innerMacro = CleveRoids.GetMacro(macroName)
    if not innerMacro then
        innerMacro = CleveRoids.ParseMacro(macroName)
    end
    if not innerMacro or not innerMacro.actions then return nil end

    -- Check if inner macro has #showtooltip (indicated by having a tooltip or action list)
    if not innerMacro.actions.tooltip and table.getn(innerMacro.actions.list or {}) == 0 then
        return nil
    end

    -- Run TestForActiveAction on inner macro to get its current active
    CleveRoids.TestForActiveAction(innerMacro.actions)

    -- If inner macro has an active action, check if it's also a nested macro
    if innerMacro.actions.active then
        local deeperActive = CleveRoids.ResolveNestedMacroActive(innerMacro.actions.active, depth + 1)
        if deeperActive then
            return deeperActive
        end
        return innerMacro.actions.active
    end

    return nil
end

function CleveRoids.TestForActiveAction(actions)
    if not actions then return end
    local currentActive = actions.active
    local currentSequence = actions.sequence
    local hasActive = false
    local newActiveAction = nil
    local newSequence = nil
    local firstUnconditional = nil

    -- Use tooltip-only branch when:
    -- 1. #showtooltip has an explicit argument (explicitTooltip = true), OR
    -- 2. #showtooltip exists but action list is empty (bare "#showtooltip")
    -- This ensures explicit tooltips always show their icon/usability correctly.
    if actions.explicitTooltip and actions.tooltipList and table.getn(actions.tooltipList) > 0 then
        -- Multi-clause/conditional #showtooltip: evaluate clauses
        for _, action in ipairs(actions.tooltipList) do
            local result, passedClause = CleveRoids.TestAction(action.cmd, action.args)
            if result then
                hasActive = true
                newActiveAction = action
                if passedClause and passedClause ~= action.args then
                    local _, passedConds = CleveRoids.GetParsedMsg(passedClause)
                    action.activeConditionals = passedConds
                end
                break
            end
        end
        if not hasActive then
            newActiveAction = actions.tooltipList[table.getn(actions.tooltipList)]
            hasActive = (newActiveAction ~= nil)
        end
        if hasActive and newActiveAction then
            local macroName = CleveRoids.GetMacroNameFromAction(newActiveAction.action)
            if macroName then
                local resolved = CleveRoids.ResolveNestedMacroActive(newActiveAction, 0)
                if resolved then
                    newActiveAction = resolved
                else
                    hasActive = false
                    newActiveAction = nil
                end
            end
        end
    elseif actions.tooltip and (actions.explicitTooltip or table.getn(actions.list) == 0) then
        -- For explicit tooltips, directly use the tooltip as active action
        -- (actions.cmd/args are empty, so TestAction would fail)
        if actions.explicitTooltip then
            hasActive = true
            newActiveAction = actions.tooltip
        elseif CleveRoids.TestAction(actions.cmd or "", actions.args or "") then
            -- Bare #showtooltip (no arg) - validate with TestAction
            hasActive = true
            newActiveAction = actions.tooltip
        end

        -- Resolve nested macro references for #showtooltip propagation
        if hasActive and newActiveAction then
            local macroName = CleveRoids.GetMacroNameFromAction(actions.tooltip.action)
            if macroName then
                local resolved = CleveRoids.ResolveNestedMacroActive(actions.tooltip, 0)
                if resolved then
                    newActiveAction = resolved
                else
                    -- Inner macro didn't resolve - no active action
                    hasActive = false
                    newActiveAction = nil
                end
            end
        end
    else
        -- First pass: find first action with conditionals that passes
        for _, action in ipairs(actions.list) do
            local result, passedClause = CleveRoids.TestAction(action.cmd, action.args)

            -- Check if action has conditionals
            local _, conditionals = CleveRoids.GetParsedMsg(action.args)

            -- Skip this action for icon display if it has the '?' prefix
            -- Note: CleveRoids._ignoretooltip is a side-effect flag set by GetParsedMsg
            local shouldSkipForIcon = CleveRoids._ignoretooltip == 1

            -- break on first action that passes tests (unless it should be skipped for icon)
            if result and not shouldSkipForIcon then
                hasActive = true
                if action.sequence then
                    newSequence = action.sequence
                    newActiveAction = CleveRoids.GetCurrentSequenceAction(newSequence)
                    -- Check if current step is a stop step - if so, skip this sequence for icon
                    if newActiveAction and newActiveAction.action then
                        local stepLower = string.lower(CleveRoids.Trim(newActiveAction.action))
                        if stepLower == "nil" or stepLower == "null" or stepLower == "pass" or stepLower == "noop" then
                            hasActive = false
                            newActiveAction = nil
                            newSequence = nil
                        end
                    end
                    if not newActiveAction then hasActive = false end
                else
                    newActiveAction = action
                    -- Range/usable checks read the passing group's @unit, which for a
                    -- multi-group clause need not be group 1's (action.conditionals).
                    action.activeConditionals = nil
                    if passedClause and passedClause ~= action.args then
                        local _, passedConds = CleveRoids.GetParsedMsg(passedClause)
                        action.activeConditionals = passedConds
                    end
                    -- Resolve nested macro references for #showtooltip propagation
                    -- If inner macro doesn't resolve, continue to next action
                    local macroName = CleveRoids.GetMacroNameFromAction(action.action)
                    if macroName then
                        local resolved = CleveRoids.ResolveNestedMacroActive(action, 0)
                        if resolved then
                            newActiveAction = resolved
                        else
                            -- Inner macro didn't resolve - try next action
                            hasActive = false
                            newActiveAction = nil
                        end
                    end
                end
                if hasActive then break end
            end

            -- Track first unconditional non-macro action as fallback
            if not conditionals and not firstUnconditional and not shouldSkipForIcon then
                -- Don't use unresolvable macro refs as fallback
                local macroName = CleveRoids.GetMacroNameFromAction(action.action)
                if not macroName then
                    firstUnconditional = action
                end
            end
        end

        -- If no conditional action passed, use first unconditional action
        if not hasActive and firstUnconditional then
            hasActive = true
            newActiveAction = firstUnconditional
        end
    end

    -- If the active action has no texture (item wasn't in bags at parse time),
    -- resolve it now via live bag lookup so the icon updates immediately
    if newActiveAction and not newActiveAction.texture
       and not newActiveAction.spell and not newActiveAction.petSpell then
        local freshItem = CleveRoids.GetItem(newActiveAction.action)
        if freshItem and freshItem.texture then
            newActiveAction.item = freshItem
            newActiveAction.texture = freshItem.texture
            newActiveAction.type = newActiveAction.type or "item"
        end
    end

    local changed = false
    if currentActive ~= newActiveAction or currentSequence ~= newSequence then
        actions.active = newActiveAction
        actions.sequence = newSequence
        changed = true
    end

    if not hasActive then
        if actions.active ~= nil or actions.sequence ~= nil then
             actions.active = nil
             actions.sequence = nil
             changed = true
        end
        return changed
    end

    if actions.active then
        local previousUsable = actions.active.usable
        local previousOom = actions.active.oom
        local previousInRange = actions.active.inRange
        local previousRangeUnit = actions.active.rangeUnit

        -- The passing clause's @unit, which the button's range check aims at.
        -- nil aims it at the target.
        local conds = actions.active.activeConditionals or actions.active.conditionals
        local unit = conds and conds.target
        actions.active.rangeUnit = CleveRoids.ResolveRaidMarkUnit(unit) or unit

        if actions.active.spell then
            -- 1 in range, 0 out of range, -1 when the check does not apply (no unit,
            -- a rangeless spell, or a unit the spell cannot be cast at)
            actions.active.inRange = -1

            -- A rank entry is its own spell; a base entry stands for its highest rank
            local spell = actions.active.spell
            local spellId = (spell.rank and spell or spell.highest or spell).id
            local inRange = CleveRoids.ClassicAPI.IsSpellInRange(spellId, actions.active.rangeUnit or "target")
            if inRange ~= nil then
                actions.active.inRange = inRange and 1 or 0
            end

            -- Check if spell is usable first (handles forms, stances, and power type correctly)
            local isUsableBySpell, notEnoughPower = nil, nil
            if IsSpellUsable then
                -- pcall to handle spells not in spellbook (Nampower throws error)
                local ok, usable, oom = pcall(IsSpellUsable, actions.active.action)
                if ok then
                    isUsableBySpell, notEnoughPower = usable, oom
                end
            end

            -- For OOM check, use proper mana source
            if notEnoughPower ~= nil then
                -- Prefer IsSpellUsable result if available (Nampower)
                actions.active.oom = (notEnoughPower == 1)
            else
                -- Read caster mana directly for druids (the mana slot survives
                -- shapeshift, 0 = Enum.PowerType.Mana); other classes use their
                -- primary power. Replaces the SuperWoW UnitMana 2nd-return hack.
                local manaToCheck
                if CleveRoids.playerClass == "DRUID" then
                    manaToCheck = CleveRoids.ClassicAPI.UnitPower("player", 0)
                else
                    manaToCheck = CleveRoids.ClassicAPI.UnitPower("player")
                end

                actions.active.oom = (manaToCheck < actions.active.spell.cost)
            end

            local start, duration = 0, 0
            if actions.active.spell.spellSlot then
                start, duration = GetSpellCooldown(actions.active.spell.spellSlot, actions.active.spell.bookType)
            end
            local onCooldown = (start > 0 and duration > 0)

            if actions.active.isReactive then
                -- For Overpower, Revenge, Riposte: ONLY use combat log tracking
                local spellName = actions.active.action
                local useCombatLogOnly = (spellName == "Overpower" or spellName == "Revenge" or spellName == "Riposte")

                if useCombatLogOnly then
                    -- Only trust HasReactiveProc for these spells
                    local hasProc = CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc(spellName)
                    if hasProc then
                        -- Proc is active, show as usable if in range and have enough rage/mana
                        if actions.active.inRange ~= 0 and not actions.active.oom then
                            actions.active.usable = 1
                        elseif pfUI and pfUI.bars and actions.active.oom then
                            actions.active.usable = 2  -- pfUI: out of mana/rage
                        else
                            actions.active.usable = nil
                        end
                    else
                        -- No proc = not usable
                        actions.active.usable = nil
                    end
                    CleveRoids.DebugChanged("usable_" .. spellName,
                        string.format("|cff00ff00[UPDATE USABLE]|r %s: hasProc=%s, usable=%s",
                            spellName, tostring(hasProc), tostring(actions.active.usable)))
                else
                    -- For other reactive spells, use the original fallback logic
                    -- Check combat log-based proc tracking first (stance-independent)
                    if CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc(actions.active.action) then
                        -- Proc is active, show as usable if in range and have enough rage/mana
                        if actions.active.inRange ~= 0 and not actions.active.oom then
                            actions.active.usable = 1
                        elseif pfUI and pfUI.bars and actions.active.oom then
                            actions.active.usable = 2  -- pfUI: out of mana/rage
                        else
                            actions.active.usable = nil
                        end
                    -- Use Nampower's IsSpellUsable if available (stance-aware fallback)
                    elseif IsSpellUsable then
                        -- pcall to handle spells not in spellbook (Nampower throws error)
                        local ok, usable, oom = pcall(IsSpellUsable, actions.active.action)
                        if ok and usable == 1 and oom ~= 1 then
                            actions.active.usable = (pfUI and pfUI.bars) and nil or 1
                        else
                            actions.active.usable = nil
                        end
                        actions.active.oom = false
                    elseif not CleveRoids.IsReactiveUsable(actions.active.action) then
                        actions.active.oom = false
                        actions.active.usable = nil
                    else
                        actions.active.usable = (pfUI and pfUI.bars) and nil or 1
                    end
                end
            elseif isUsableBySpell == 1 and actions.active.inRange ~= 0 then
                -- Use IsUsableSpell result if available (handles forms/stances correctly)
                actions.active.usable = 1
            elseif isUsableBySpell == 0 then
                -- IsSpellUsable returned 0 = wrong stance/form, not enough power type, etc.
                actions.active.usable = nil
            elseif actions.active.inRange ~= 0 and not actions.active.oom then
                -- Fallback to mana check ONLY if IsSpellUsable not available
                actions.active.usable = 1

            -- pfUI:actionbar.lua -- update usable [out-of-range = 1, oom = 2, not-usable = 3, default = 0]
            elseif pfUI and pfUI.bars and actions.active.oom then
                actions.active.usable = 2
            else
                actions.active.usable = nil
            end

            -- Check if this is a toggled buff ability (Prowl, Shadowmeld) and darken if buff is active
            -- This must come AFTER all other usability checks to have final say
            -- PERFORMANCE: Cache normalized spell name on the action object to avoid gsub per-frame
            local spellName = actions.active._normalizedName
            if not spellName then
                spellName = string.gsub(actions.active.action, "%s*%(.-%)%s*$", "")
                spellName = string.gsub(spellName, "_", " ")
                actions.active._normalizedName = spellName
            end

            -- PERFORMANCE: Use cached lookup instead of creating table per-call
            if CleveRoids.IsToggledBuffAbility(spellName) then
                if CleveRoids.ValidatePlayerBuff(spellName) then
                    -- Buff is active, darken the icon like "wrong stance" (grayed out, not red)
                    actions.active.usable = nil
                    actions.active.oom = false  -- Make sure we don't show red tint
                end
            end
        else
            actions.active.inRange = 1
            actions.active.usable = 1
        end
        if actions.active.usable ~= previousUsable or
           actions.active.oom ~= previousOom or
           actions.active.inRange ~= previousInRange or
           actions.active.rangeUnit ~= previousRangeUnit then
            changed = true
            if CleveRoids.debug and actions.active.isReactive then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff00ff[STATE CHANGED]|r %s: usable %s->%s, will send ACTIONBAR_SLOT_CHANGED",
                        actions.active.action, tostring(previousUsable), tostring(actions.active.usable))
                )
            end
        end
    end
    return changed
end

--------------------------------------------------------------------------------
-- ClassicAPI macro display
--------------------------------------------------------------------------------

-- The value to hand C_Macro.SetMacroDisplay for an active action. The nested hop
-- mirrors the {MacroName} fallback the GameTooltip.SetAction override used: when
-- `action` is a macro reference, `action.macro` holds the inner macro's
-- #showtooltip action info (see CreateActionInfo), and `action.action` is the
-- literal "{Name}" text, which names no spell or item.
local function DisplayValueFor(action)
    if not action then return nil end
    if type(action.macro) == "table" and action.macro.action then
        return action.macro.action
    end
    return action.action
end

-- Last value and range unit handed to SetMacroDisplay, per macro index.
--
-- Publishing is NOT free. The client repaints every slot holding the macro through
-- its own notifier, and that comes back to us as ACTIONBAR_SLOT_CHANGED ->
-- ClearAction + IndexActionSlot -> TestForActiveAction -> publish. Publishing a value
-- that has not changed therefore re-indexes slots for nothing and feeds itself.
-- GetAction and IndexActionSlot both call in on paths that fire constantly, so the
-- no-op check below is what keeps that from turning into a churn loop.
local publishedDisplay = {}
local publishedUnit = {}

-- Publish one macro's resolved action. Nothing is re-evaluated for us, so this must
-- be called whenever the answer changes; the published value stands until replaced.
--
-- `false` is deliberate when there is no active action: it means "this macro is mine,
-- nothing matched" and shows the question mark. Skipping the call instead would hand
-- the macro back to ClassicAPI's own #showtooltip parser.
function CleveRoids.PublishDisplay(actions)
    if not CleveRoids.ClassicAPIMacroDisplay then return end
    local macroID = actions and actions.macroID
    if not macroID then return end  -- SuperMacro macros have no Blizzard index

    local active = actions.active
    local value = DisplayValueFor(active) or false
    local unit = active and active.rangeUnit
    if publishedDisplay[macroID] == value and publishedUnit[macroID] == unit then return end
    publishedDisplay[macroID] = value
    publishedUnit[macroID] = unit

    -- The client resolves the token again at every range check, so a new
    -- mouseover or focus needs no republish. SetMacroDisplay raises on a string
    -- that is not a token (an @Name target); that range stays on the target.
    if not IsUnitToken(unit) then unit = nil end
    C_Macro.SetMacroDisplay(macroID, value, unit)
end

-- Republish every parsed macro. Used after login and after a re-parse, since
-- ClassicAPI re-evaluates nothing for us. Covers macros that aren't on a bar too,
-- which is what keeps the macro window grid's icons correct.
function CleveRoids.PublishAllDisplays()
    if not CleveRoids.ClassicAPIMacroDisplay then return end
    -- Forget what we published so every macro republishes once. Callers reach here
    -- after login and after a re-parse, where a cached value could otherwise
    -- suppress the publish a freshly rebuilt macro still needs.
    publishedDisplay = {}
    publishedUnit = {}
    for _, macro in pairs(CleveRoids.Macros) do
        if type(macro) == "table" and macro.actions and macro.actions.macroID then
            CleveRoids.TestForActiveAction(macro.actions)
            CleveRoids.PublishDisplay(macro.actions)
        end
    end
end

-- Hand every macro back to ClassicAPI's own parser and stop claiming ownership.
function CleveRoids.ReleaseDisplays()
    if not CleveRoids.ClassicAPIMacroDisplay then return end
    -- Sweep the whole index space rather than the macros we know we published:
    -- PublishAllDisplays clears that record on every re-parse, so a macro claimed
    -- before one and gone after it would keep our last value forever. Releasing a
    -- slot we never claimed costs nothing, and this runs once.
    for i = 1, CleveRoids.MAX_MACRO_SLOTS do
        C_Macro.SetMacroDisplay(i, nil)
    end
    publishedDisplay = {}
    publishedUnit = {}
    CleveRoids.ClassicAPIMacroDisplay = false
end

-- PERFORMANCE: Static buffer references for hot path
local _actionsToSlotsBuffer = CleveRoids._actionsToSlotsBuffer
local _slotsBuffer = CleveRoids._slotsBuffer
local _actionsListBuffer = CleveRoids._actionsListBuffer

function CleveRoids.TestForAllActiveActions()
    -- PERFORMANCE: Reuse static buffers instead of creating new tables each call
    -- Group slots by their actions object to handle shared macro references
    local actionsToSlots = _actionsToSlotsBuffer
    local actionsList = _actionsListBuffer
    local actionsCount = 0

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local Actions = CleveRoids.Actions
    local slot, actions = next(Actions)
    while slot do
        if not actionsToSlots[actions] then
            -- Reuse or create slots array from pool
            local slots = _slotsBuffer[actions]
            if not slots then
                slots = {}
                _slotsBuffer[actions] = slots
            end
            slots[1] = slot
            slots._count = 1
            actionsToSlots[actions] = slots
            actionsCount = actionsCount + 1
            actionsList[actionsCount] = actions
        else
            local slots = actionsToSlots[actions]
            local count = slots._count + 1
            slots[count] = slot
            slots._count = count
        end
        slot, actions = next(Actions, slot)
    end

    -- Test each unique actions object once and send events to ALL slots that share it
    for i = 1, actionsCount do
        local actions = actionsList[i]
        local slots = actionsToSlots[actions]
        local stateChanged = CleveRoids.TestForActiveAction(actions)
        if stateChanged then
            -- Publishing repaints every slot holding this macro through the client's
            -- own notifier, so there is no per-slot fan-out to do here. It no-ops once
            -- ReleaseDisplays has handed the macros back.
            CleveRoids.PublishDisplay(actions)
        end
        -- Clear for reuse (reset count and clear buffer reference)
        for j = 1, slots._count do
            slots[j] = nil
        end
        slots._count = 0
        actionsToSlots[actions] = nil
        actionsList[i] = nil  -- Clear actionsList entry for reuse
    end
end

function CleveRoids.ClearAction(slot)
    if not CleveRoids.Actions[slot] then return end
    CleveRoids.Actions[slot].active = nil
    CleveRoids.Actions[slot] = nil
end

function CleveRoids.GetAction(slot)
    if not slot or not CleveRoids.ready then return end

    local actions = CleveRoids.Actions[slot]
    if actions then return actions end

    -- Identify the macro by its index via ClassicAPI's GetActionInfo so the
    -- slot is mapped without going through the macro name (no unique-name
    -- requirement for action-bar macros).
    local macro
    local kind, macroID = CleveRoids.ClassicAPI.GetActionInfo(slot)
    if kind == "macro" and macroID then
        macro = CleveRoids.GetMacroByIndex(macroID)
    end

    -- Fallback for SuperMacro (and anything GetActionInfo doesn't tag as a
    -- macro): resolve by name.
    if not macro then
        local text = GetActionText(slot)
        if text then
            macro = CleveRoids.GetMacro(text)
        end
    end

    if macro then
        actions = macro.actions
        CleveRoids.TestForActiveAction(actions)
        CleveRoids.PublishDisplay(actions)
        CleveRoids.Actions[slot] = actions
        CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
        return actions
    end
end

function CleveRoids.GetActiveAction(slot)
    local action = CleveRoids.GetAction(slot)
    return action and action.active
end

-- PERFORMANCE: Static buffer for arg backup
local _originalArgsBuffer = CleveRoids._originalArgsBuffer

-- Prebuilt global names. Building "arg" .. i inline cost a concatenation per
-- iteration, three ten-iteration loops per call, on a function that runs once per
-- action slot (up to 120 per full index).
local ARG_GLOBALS = {
    "arg1", "arg2", "arg3", "arg4", "arg5",
    "arg6", "arg7", "arg8", "arg9", "arg10",
}

-- Takes eventArg explicitly rather than `...`: in 1.12's Lua 5.0 a vararg function
-- allocates an `arg` table on every call, and every caller passes exactly one extra
-- value (the slot). The old arg.n fan-out below collapsed to a single case.
function CleveRoids.SendEventForAction(slot, event, eventArg)
    local old_this = this

    -- PERFORMANCE: Reuse static buffer instead of creating table each call
    local original_global_args = _originalArgsBuffer
    for i = 1, 10 do
        original_global_args[i] = _G[ARG_GLOBALS[i]]
    end

    _G.arg1 = eventArg
    for i = 2, 10 do
        _G[ARG_GLOBALS[i]] = nil
    end

    local button_to_call_event_on
    local page = floor((slot - 1) / NUM_ACTIONBAR_BUTTONS) + 1
    local pageSlot = slot - (page - 1) * NUM_ACTIONBAR_BUTTONS

    if slot >= 73 then
        button_to_call_event_on = _G["BonusActionButton" .. pageSlot]
    elseif slot >= 61 then
        button_to_call_event_on = _G["MultiBarBottomLeftButton" .. pageSlot]
    elseif slot >= 49 then
        button_to_call_event_on = _G["MultiBarBottomRightButton" .. pageSlot]
    elseif slot >= 37 then
        button_to_call_event_on = _G["MultiBarLeftButton" .. pageSlot]
    elseif slot >= 25 then
        button_to_call_event_on = _G["MultiBarRightButton" .. pageSlot]
    end

    if button_to_call_event_on then
        this = button_to_call_event_on
        ActionButton_OnEvent(event)
    end

    if page == CURRENT_ACTIONBAR_PAGE then
        local main_bar_button = _G["ActionButton" .. pageSlot]
        if main_bar_button and main_bar_button ~= button_to_call_event_on then
            this = main_bar_button
            ActionButton_OnEvent(event)
        elseif not button_to_call_event_on and main_bar_button then
             this = main_bar_button
             ActionButton_OnEvent(event)
        end
    end

    this = old_this

    for i = 1, 10 do
        _G[ARG_GLOBALS[i]] = original_global_args[i]
    end

    -- FIX: Skip addon handler calls during initial indexing to prevent 120 rapid calls
    if CleveRoids._suppressActionHandlers then
        return
    end

    local handlers = CleveRoids.actionEventHandlers
    for i = 1, table.getn(handlers) do
        handlers[i](slot, event, eventArg)
    end
end

-- Executes the given Macro's body
-- body: The Macro's body
-- Note on macro flags:
--   stopMacroFlag: Stops ALL remaining lines (propagates to parent macros)
--   skipMacroFlag: Stops only current macro (cleared on return, parent continues)
function CleveRoids.ExecuteMacroBody(body,inline)
    local lines = CleveRoids.splitString(body, "\n")
    if inline then lines = CleveRoids.splitString(body, "\\n"); end

    -- Save parent's stopMacroFlag state (in case we need to preserve it)
    local parentStopFlag = CleveRoids.stopMacroFlag

    -- Clear flags at start of this macro execution
    -- Note: We DON'T clear if parent already set stopMacroFlag (shouldn't execute at all)
    if not parentStopFlag then
        CleveRoids.stopMacroFlag = false
    end
    CleveRoids.skipMacroFlag = false  -- Always start fresh for skipmacro

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ffff[MacroRef]|r ExecuteMacroBody called with " .. table.getn(lines) .. " lines")
    end

    for k,v in pairs(lines) do
        local trimmed = CleveRoids.Trim(v)
        local cmdHandled = false

        -- Skip #showtooltip lines - they're only meaningful for action bar display,
        -- not for execution. This allows inner macros to have #showtooltip without
        -- causing issues when called from other macros.
        if string.find(trimmed, "^#showtooltip") then
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff888888[MacroRef]|r Skipping #showtooltip line in inner macro")
            end
            cmdHandled = true
        end

        -- IMPORTANT: Check for /nofirstaction BEFORE the stop flag check
        -- This allows /nofirstaction to clear the stopMacroFlag set by /firstaction
        local _, _, nofirstactionArgs = string.find(trimmed, "^/nofirstaction%s*(.*)")
        if nofirstactionArgs then
            -- Capture stopOnCastFlag BEFORE DoNoFirstAction clears it
            -- If it was true, stopMacroFlag was set by /firstaction, not /stopmacro
            local wasFirstActionActive = CleveRoids.stopOnCastFlag
            CleveRoids.DoNoFirstAction(nofirstactionArgs)
            -- Also clear stopMacroFlag if it was set by firstaction mechanism
            -- (but NOT if it was set by explicit /stopmacro)
            if wasFirstActionActive and CleveRoids.stopMacroFlag then
                -- stopOnCastFlag was true before we cleared it, and stopMacroFlag is set
                -- This means stopMacroFlag was set by the firstaction mechanism, clear it
                CleveRoids.stopMacroFlag = false
                if CleveRoids.macroRefDebug then
                    CleveRoids.Print("|cff00ff00[MacroRef]|r /nofirstaction cleared stopMacroFlag - resuming macro")
                end
            end
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff88ff88[MacroRef]|r Executing line " .. k .. ": " .. string.sub(v, 1, 60))
            end
            cmdHandled = true
        end

        -- Check both macro stop flags before each line (but skip if we just handled /nofirstaction)
        -- stopMacroFlag: stop this AND parent macros
        -- skipMacroFlag: stop only this macro (parent continues)
        if not cmdHandled and (CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag) then
            -- If stopOnCastFlag is true, the stop was caused by the firstaction mechanism
            -- Don't break the loop - just skip this line (allows /nofirstaction to be reached)
            if CleveRoids.stopOnCastFlag and CleveRoids.stopMacroFlag and not CleveRoids.skipMacroFlag then
                if CleveRoids.macroRefDebug then
                    CleveRoids.Print("|cffff8800[MacroRef]|r Skipping line " .. k .. " (firstaction mode)")
                end
                cmdHandled = true  -- Skip this line but continue loop to allow /nofirstaction
            else
                -- This is a /stopmacro or /skipmacro stop - actually break
                if CleveRoids.macroRefDebug then
                    local reason = CleveRoids.stopMacroFlag and "/stopmacro" or "/skipmacro"
                    CleveRoids.Print("|cffff8800[MacroRef]|r Stopped at line " .. k .. " due to " .. reason)
                end
                break
            end
        end

        if not cmdHandled then
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff88ff88[MacroRef]|r Executing line " .. k .. ": " .. string.sub(v, 1, 60))
            end

            -- IMPORTANT: Handle macro control commands directly to bypass Blizzard's built-in /stopmacro
            -- Blizzard intercepts bare /stopmacro before it reaches our SlashCmdList handler

            -- Check for /stopmacro (with or without conditionals)
            local _, _, stopmacroArgs = string.find(trimmed, "^/stopmacro%s*(.*)")
            if stopmacroArgs then
                CleveRoids.DoStopMacro(stopmacroArgs)
                cmdHandled = true
            end

            -- Check for /skipmacro (with or without conditionals)
            if not cmdHandled then
                local _, _, skipmacroArgs = string.find(trimmed, "^/skipmacro%s*(.*)")
                if skipmacroArgs then
                    CleveRoids.DoSkipMacro(skipmacroArgs)
                    cmdHandled = true
                end
            end

            -- Check for /firstaction (with or without conditionals)
            if not cmdHandled then
                local _, _, firstactionArgs = string.find(trimmed, "^/firstaction%s*(.*)")
                if firstactionArgs then
                    CleveRoids.DoFirstAction(firstactionArgs)
                    cmdHandled = true
                end
            end

            -- FIX: Handle /startattack directly - not a native vanilla WoW command
            -- Without SuperMacro, ChatEdit_SendText may not route addon slash commands properly
            if not cmdHandled then
                local _, _, startattackArgs = string.find(trimmed, "^/startattack%s*(.*)")
                if startattackArgs then
                    if SlashCmdList.STARTATTACK then
                        SlashCmdList.STARTATTACK(startattackArgs)
                    end
                    cmdHandled = true
                end
            end

            -- FIX: Handle /stopattack directly - not a native vanilla WoW command
            if not cmdHandled then
                local _, _, stopattackArgs = string.find(trimmed, "^/stopattack%s*(.*)")
                if stopattackArgs then
                    if SlashCmdList.STOPATTACK then
                        SlashCmdList.STOPATTACK(stopattackArgs)
                    end
                    cmdHandled = true
                end
            end

            -- Handle /equipshield and /equip2h directly (with conditional support)
            if not cmdHandled then
                local _, _, equipshieldArgs = string.find(trimmed, "^/equipshield%s*(.*)")
                if not equipshieldArgs then
                    _, _, equipshieldArgs = string.find(trimmed, "^/equipdef%s*(.*)")
                end
                if equipshieldArgs ~= nil then
                    if SlashCmdList.EQUIPSHIELD then
                        SlashCmdList.EQUIPSHIELD(equipshieldArgs)
                    end
                    cmdHandled = true
                else
                    local _, _, equip2hArgs = string.find(trimmed, "^/equip2h%s*(.*)")
                    if not equip2hArgs then
                        _, _, equip2hArgs = string.find(trimmed, "^/equip2%s*(.*)")
                    end
                    if equip2hArgs ~= nil then
                        if SlashCmdList.EQUIP2H then
                            SlashCmdList.EQUIP2H(equip2hArgs)
                        end
                        cmdHandled = true
                    end
                end
            end
        end

        -- For all other commands, run the line the way the engine runs a macro
        -- line: through FrameXML's hidden MacroEditBox (its EXECUTE_CHAT_LINE
        -- handler, mirrored). Using ChatFrameEditBox would write the line into
        -- the chat input history and clobber/hide whatever the user is typing.
        if not cmdHandled then
            local defaultEditBox = DEFAULT_CHAT_FRAME.editBox
            MacroEditBox.chatFrame = DEFAULT_CHAT_FRAME
            MacroEditBox.chatType = defaultEditBox.chatType
            MacroEditBox.tellTarget = defaultEditBox.tellTarget
            MacroEditBox.channelTarget = defaultEditBox.channelTarget
            MacroEditBox:SetText(v)
            ChatEdit_SendText(MacroEditBox)
        end
    end

    -- Clear skipMacroFlag after this macro completes (don't propagate to parent)
    -- stopMacroFlag is intentionally LEFT SET so it propagates up
    CleveRoids.skipMacroFlag = false

    return true
end

-- Attempts to execute a macro by the given name or index (Blizzard or Super tab)
-- Returns: true if something was executed, false otherwise
-- Supports: macro name (string), macro index (number or numeric string like "19")
-- Uses CleveRoids' own ExecuteMacroBody for processing (supports enhanced syntax)
function CleveRoids.ExecuteMacroByName(name)
    if not name or name == "" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cffff0000[MacroRef]|r ExecuteMacroByName called with empty name")
        end
        return false
    end

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ffff[MacroRef]|r ExecuteMacroByName called with: '" .. name .. "'")
    end

    local body
    local source = nil

    -- Check if input is a numeric index (e.g., "19" or 19)
    local numericIndex = tonumber(name)

    -- 1) Try Blizzard macro (by index or name)
    if numericIndex then
        -- Numeric index - get body directly (supports character macros 19-36)
        local _n, _tex, b = GetMacroInfo(numericIndex)
        if b and b ~= "" then
            body = b
            source = "Blizzard (index " .. numericIndex .. ")"
        end
    else
        -- String name - look up by name
        local id = GetMacroIndexByName(name)
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff888888[MacroRef]|r GetMacroIndexByName('" .. name .. "') = " .. tostring(id))
        end
        if id and id ~= 0 then
            local _n, _tex, b = GetMacroInfo(id)
            if b and b ~= "" then
                body = b
                source = "Blizzard (slot " .. id .. ")"
            end
        end
    end

    -- 2) SuperMacro's Super macros (by name only, not index)
    -- These are the 7000-char extended macros stored in SM_SUPER
    if not body and not numericIndex then
        if type(GetSuperMacroInfo) == "function" then
            local _n2, _t2, b2 = GetSuperMacroInfo(name)
            if b2 and b2 ~= "" then
                body = b2
                source = "SuperMacro"
            end
        end
    end

    -- 3) CRM cache fallback (by name only)
    if not body and not numericIndex then
        if type(CleveRoids.GetMacro) == "function" then
            local m = CleveRoids.GetMacro(name)
            if m and m.body and m.body ~= "" then
                body = m.body
                source = "CRM cache"
            end
        end
    end

    if not body or body == "" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cffff0000[MacroRef]|r Macro '" .. name .. "' not found in any source")
        end
        return false
    end

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ff00[MacroRef]|r Found macro '" .. name .. "' from " .. source)
    end

    -- Execute using CleveRoids' processor (supports conditionals, extended syntax)
    return CleveRoids.ExecuteMacroBody(body)
end

function CleveRoids.SetHelp(conditionals)
    if conditionals.harm then
        conditionals.help = false
    end
end

function CleveRoids.FixEmptyTarget(conditionals)
    if not conditionals.target then
        if UnitExists("target") then
            conditionals.target = "target"
        elseif GetCVar("autoSelfCast") == "1" and not conditionals.target == "help" then
            conditionals.target = "player"
        end
    end
    return false
end

-- Fixes the conditionals' target by targeting the target with the given name
-- conditionals: The conditionals containing the current target
-- name: The name of the player to target
-- hook: The target hook
-- returns: Whether or not we've changed the player's current target
function CleveRoids.FixEmptyTargetSetTarget(conditionals, name, hook)
    if not conditionals.target then
        hook(name)
        conditionals.target = "target"
        return true
    end
    return false
end

function CleveRoids.GetMacroNameFromAction(text)
    if string.sub(text, 1, 1) == "{" and string.sub(text, -1) == "}" then
        local name
        if string.sub(text, 2, 2) == "\"" and string.sub(text, -2, -2) == "\"" then
            return string.sub(text, 3, -3)
        else
            return string.sub(text, 2, -2)
        end
    end
end

function CleveRoids.CreateActionInfo(action, conditionals)
    local _, _, text = string.find(action, "!?%??~?(.*)")
    local spell = CleveRoids.GetSpell(text)
    local petSpell  -- Add this line
    local item, macroName, macro, macroTooltip, actionType, texture

    -- NEW: Check if the action is a slot number
    local slotId = tonumber(text)
    if slotId and slotId >= 1 and slotId <= 19 then
        actionType = "item"
        local itemTexture = GetInventoryItemTexture("player", slotId)
        if itemTexture then
            texture = itemTexture
        else
            texture = CleveRoids.unknownTexture
        end
    else
        -- Original logic for named items and spells
        if not spell then
            petSpell = CleveRoids.GetPetSpell(text)  -- Add this line
        end
        if not spell and not petSpell then  -- Modify this line
            item = CleveRoids.GetItem(text)
        end
        if not item and not petSpell then  -- Modify this line
            macroName = CleveRoids.GetMacroNameFromAction(text)
            macro = CleveRoids.GetMacro(macroName)
            macroTooltip = (macro and macro.actions) and macro.actions.tooltip
        end

        if spell then
            actionType = "spell"
            texture = spell.texture or CleveRoids.unknownTexture
        elseif petSpell then  -- Add this block
            actionType = "petspell"
            texture = petSpell.texture or CleveRoids.unknownTexture
        elseif item then
            actionType = "item"
            texture = (item and item.texture) or CleveRoids.unknownTexture
        elseif macro then
            actionType = "macro"
            texture = (macro.actions and macro.actions.tooltip and macro.actions.tooltip.texture)
                        or (macro and macro.texture)
                        or CleveRoids.unknownTexture
        end
    end

    local info = {
        action = text,
        item = item,
        spell = spell,
        petSpell = petSpell,  -- Add this line
        macro = macroTooltip,
        type = actionType,
        texture = texture,
        conditionals = conditionals,
    }

    return info
end

function CleveRoids.SplitCommandAndArgs(text)
    local _, _, cmd, args = string.find(text, "(/%w+%s?)(.*)")
    if cmd and args then
        cmd = CleveRoids.Trim(cmd)
        text = CleveRoids.Trim(args)
    end
    return cmd, args
end

function CleveRoids.ParseSequence(text)
    if not text or text == "" then return end

    -- normalize commas
    local args = string.gsub(text, "(%s*,%s*)", ",")

    -- optional [conditionals] block
    local _, condEnd, condBlock = string.find(args, "(%[.*%])")

    -- accept reset= anywhere; no trailing space required; strip it out once
    local _, _, resetVal = string.find(args, "[Rr][Ee][Ss][Ee][Tt]=([%w/]+)")
    if resetVal then
      args = string.gsub(args, "%s*[Rr][Ee][Ss][Ee][Tt]=[%w/]+%s*", " ", 1)
    end

    -- actions are what's left after any ] (if present)
    local actionSeq = CleveRoids.Trim((condEnd and string.sub(args, condEnd + 1)) or args)
    args = (condBlock or "") .. actionSeq
    if actionSeq == "" then return end

    local sequence = {
        index      = 1,
        reset      = {},
        status     = 0,
        lastUpdate = 0,
        args       = args,
        cond       = condBlock or "",  -- Store conditional block for evaluation in DoCastSequence
        list       = {},
        perTargetState = {},  -- [guid] = {index = N, lastUpdate = T} for reset=target
    }

    -- fill reset rules: seconds or flags (target/combat/alt/ctrl/shift)
    if resetVal then
        for _, rule in pairs(CleveRoids.Split(resetVal, "/")) do
            rule = string.lower(CleveRoids.Trim(rule))
            local secs = tonumber(rule)
            if secs and secs > 0 then
                sequence.reset.secs = secs
            else
                sequence.reset[rule] = true
            end
        end
    end

    -- build steps
    for _, a in ipairs(CleveRoids.Split(actionSeq, ",")) do
        local sa = CleveRoids.CreateActionInfo(CleveRoids.GetParsedMsg(a))
        table.insert(sequence.list, sa)
    end

    CleveRoids.Sequences[text] = sequence
    return sequence
end

-- Shared: build, parse, and cache a macro under `cacheKey`. For action-bar
-- macros the key is the Blizzard macro index (unique), so duplicate or blank
-- macro names no longer collide; SuperMacro macros (no index) are keyed by name.
-- macroID is the Blizzard index if known, else nil.
local function BuildMacro(cacheKey, macroID, name, texture, body)
    local macro = {
        id      = macroID,
        name    = name,
        texture = texture,
        body    = body,
        actions = {},
    }
    -- Back-reference so the update loop, which walks `actions` objects rather than
    -- macros, can name the macro to C_Macro.SetMacroDisplay. nil for SuperMacro
    -- macros, which have no Blizzard index and so cannot be published.
    macro.actions.macroID = macroID
    macro.actions.list = {}

    -- build a list of testable actions for the macro
    local hasShowTooltip = false
    local showTooltipHasArg = false

    for i, line in ipairs(CleveRoids.splitString(body, "\n")) do
        line = CleveRoids.Trim(line)
        local cmd, args = CleveRoids.SplitCommandAndArgs(line)

        -- check for #showtooltip on first line
        if i == 1 then
            local _, _, st, _, tt = string.find(line, "(#showtooltip)(%s?(.*))")

            if st then
                hasShowTooltip = true
                tt = CleveRoids.Trim(tt)

                -- #showtooltip with explicit item/spell/macro specified
                if tt ~= "" then
                    showTooltipHasArg = true
                    macro.actions.tooltipList = {}
                    for _, arg in ipairs(CleveRoids.splitStringIgnoringQuotes(tt)) do
                        -- Parse the arg to extract the spell name from any conditionals
                        local parsedArg = CleveRoids.GetParsedMsg(arg)
                        local action = CleveRoids.CreateActionInfo(parsedArg)
                        action.cmd = "/cast"
                        action.args = arg
                        action.isReactive = CleveRoids.reactiveSpells[action.action]
                        table.insert(macro.actions.tooltipList, action)
                    end
                    if table.getn(macro.actions.tooltipList) > 0 then
                        macro.actions.tooltip = macro.actions.tooltipList[1]
                    end
                end
                -- Continue parsing remaining lines for action list (needed for nested macro resolution)
            end
            -- No #showtooltip: still continue parsing to build action list for inner macro resolution
        else
            -- make sure we have a testable action
            if line ~= "" and args ~= "" and CleveRoids.dynamicCmds[cmd] then
                for _, arg in ipairs(CleveRoids.splitStringIgnoringQuotes(args)) do
                    local action = CleveRoids.CreateActionInfo(CleveRoids.GetParsedMsg(arg))

                    if cmd == "/castsequence" then
                        local sequence = CleveRoids.GetSequence(args)
                        if sequence then
                            action.sequence = sequence
                        end
                    end
                    action.cmd = cmd
                    action.args = arg
                    action.isReactive = CleveRoids.reactiveSpells[action.action]
                    table.insert(macro.actions.list, action)
                end
            end
        end
    end

    -- If #showtooltip was present but had no argument, use the first action as the tooltip
    if hasShowTooltip and not showTooltipHasArg and table.getn(macro.actions.list) > 0 then
        macro.actions.tooltip = macro.actions.list[1]
    end

    -- Store whether #showtooltip had an explicit argument (for icon fallback logic)
    macro.actions.explicitTooltip = showTooltipHasArg

    CleveRoids.Macros[cacheKey] = macro
    return macro
end

-- Parse a macro by its Blizzard macro index (1-36), caching by index. This is
-- the action-bar path: a slot's macro is identified by index via ClassicAPI's
-- GetActionInfo, so duplicate/blank macro names no longer collide.
function CleveRoids.ParseMacroByIndex(macroID)
    if not macroID or macroID == 0 then return end
    local name, texture, body = GetMacroInfo(macroID)
    if not texture or not body then return end
    return BuildMacro(macroID, macroID, name, texture, body)
end

-- Parse a macro by name (explicit {MacroName} / runmacro references, and
-- SuperMacro macros that have no Blizzard index). Resolves to the index path
-- when possible so the cache stays index-keyed.
function CleveRoids.ParseMacro(name)
    if not name then return end

    local macroID = GetMacroIndexByName(name)
    if macroID and macroID ~= 0 then
        return CleveRoids.ParseMacroByIndex(macroID)
    end

    -- SuperMacro has no Blizzard macro index; cache by name.
    if GetSuperMacroInfo then
        local _, texture, body = GetSuperMacroInfo(name)
        if texture and body then
            return BuildMacro(name, nil, name, texture, body)
        end
    end
end

function CleveRoids.ParseMsg(msg)
    if not msg then return end
    local conditionals = {}

    -- reset side flag for this parse
    CleveRoids._ignoretooltip = 0

    -- strip optional leading '?' and remember how many we stripped
    local ignorecount
    msg, ignorecount = string.gsub(CleveRoids.Trim(msg), "^%?", "")
    conditionals.ignoretooltip = ignorecount
    CleveRoids._ignoretooltip  = ignorecount

    -- Leading [group] blocks and the action after them. A clause with several
    -- groups (`[a][b] Spell`) parses here as group 1 plus the shared action:
    -- DoWithConditionals and TestAction expand such a clause into one-group
    -- variants before parsing, so the callers that do parse a multi-group
    -- clause directly only rely on the action and on conditionals being non-nil.
    local _, groups, restStart = CleveRoids.ScanBracketGroups(msg)
    local conditionBlock = nil
    if groups.n > 0 then
        conditionBlock = string.sub(groups[1], 2, -2)
    end

    -- split off flags/action after the groups (or from the start if there are none)
    local _, _, noSpam, cancelAura, action = string.find(
        groups.n > 0 and string.sub(msg, restStart) or msg,
        "^%s*(!?)(~?)([^!~]+.*)"
    )
    action = CleveRoids.Trim(action or "")

    -- Also check for ? at start of action (after conditional block)
    -- This handles "[cond] ?action" syntax where ? appears after conditionals
    if string.sub(action, 1, 1) == "?" then
        action = CleveRoids.Trim(string.sub(action, 2))
        conditionals.ignoretooltip = 1
        CleveRoids._ignoretooltip = 1
    end

    -- store the raw action for callers and strip trailing "(Rank X)" for comparisons
    conditionals.action = action
    action = CleveRoids.StripRank(action)

    -- IMPORTANT: if there's NO conditional block, return nil conditionals so
    -- DoWithConditionals will hit the {macroName} execution branch.
    if not conditionBlock then
        local hasFlag = (noSpam and noSpam ~= "") or (cancelAura and cancelAura ~= "")
        if hasFlag and action ~= "" then
            if noSpam ~= "" then
                -- ! prefix: handled at execution time via CastSpellNoToggle
                -- (see DoWithConditionals), no gate conditional needed.
                conditionals.noSpam = true
            end
            if cancelAura ~= "" then
                conditionals.cancelaura = action
            end
            return conditionals.action, conditionals
        end
        return conditionals.action, nil
    end

    -- With a condition block present, build out the conditionals table

    -- ! prefix with explicit conditionals: store as a flag for execution-time anti-toggle,
    -- rather than injecting an implicit conditional that gets AND'd with user conditions.
    -- The anti-toggle check happens in DoWithConditionals before CastSpellByName.
    if noSpam and noSpam ~= "" then
        conditionals.noSpam = true
    end
    if cancelAura and cancelAura ~= "" then
        conditionals.cancelaura = action
    end

    -- Set the action's target to @unitid if found (e.g., @mouseover)
    local _, _, target = string.find(conditionBlock, "(@[^%s,]+)")
    if target then
        conditionBlock = CleveRoids.Trim(string.gsub(conditionBlock, target, ""))
        conditionals.target = string.sub(target, 2)
    end

    if conditionBlock and conditionals.action then
        -- Split the conditional block by comma or space
        local condGroupsList
        if string.find(conditionBlock, ",") then
            condGroupsList = CleveRoids.splitStringIgnoringQuotes(conditionBlock, ",")
        else
            local _, numColons = string.gsub(conditionBlock, ":", "")
            if numColons <= 1 then
                condGroupsList = { conditionBlock }
            else
                condGroupsList = CleveRoids.splitStringIgnoringQuotes(conditionBlock, {",", " "})
            end
        end
        for _, conditionGroups in condGroupsList do
            if conditionGroups ~= "" then
                -- Split conditional groups by colon (rejoin extra parts for multi-part args
                -- e.g., distance:30:facing>1 → condition="distance", args="30:facing>1")
                local conditionGroup = CleveRoids.splitStringIgnoringQuotes(conditionGroups, ":")
                local condition = conditionGroup[1]
                -- Rewrite deprecated names (e.g. mouseuse -> cursor) so old macros
                -- keep working and only the current keyword exists downstream.
                condition = CleveRoids.conditionalAliases[condition] or condition
                local args = conditionGroup[2]
                for _cgi = 3, table.getn(conditionGroup) do
                    args = (args or "") .. ":" .. conditionGroup[_cgi]
                end

                -- No args → the action is the implicit argument
                if not args or args == "" then
                    if not conditionals[condition] then
                        -- PERFORMANCE: Use module-level constant instead of creating table per-call
                        if BOOLEAN_CONDITIONALS[condition] then
                            conditionals[condition] = true
                        else
                            conditionals[condition] = conditionals.action
                            -- Create first group for non-boolean conditionals
                            if not conditionals._groups then
                                conditionals._groups = {}
                            end
                            conditionals._groups[condition] = { { values = { conditionals.action }, n = 1, operator = "OR" }, n = 1 }
                        end
                    else
                        -- existing code for when conditionals[condition] already exists
                        if type(conditionals[condition]) ~= "table" then
                            conditionals[condition] = { conditionals[condition] }
                        end
                        table.insert(conditionals[condition], conditionals.action)

                        -- Multiple instances of same conditional = AND logic
                        if not conditionals._operators then
                            conditionals._operators = {}
                        end
                        conditionals._operators[condition] = "AND"

                        -- Add new group for this instance
                        if not conditionals._groups then
                            conditionals._groups = {}
                        end
                        if not conditionals._groups[condition] then
                            conditionals._groups[condition] = { n = 0 }
                        end
                        local grp = conditionals._groups[condition]
                        local newEntry = { values = { conditionals.action }, n = 1, operator = "OR" }
                        grp.n = grp.n + 1
                        grp[grp.n] = newEntry
                    end
                else
                    -- Has args. Ensure the key's value is a table and add new arguments.
                    -- Track if this conditional already existed (repeated via comma)
                    local conditionAlreadyExists = conditionals[condition] ~= nil

                    if not conditionals[condition] then
                        conditionals[condition] = {}
                    elseif type(conditionals[condition]) ~= "table" then
                        conditionals[condition] = { conditionals[condition] }
                    end

                    -- Detect which separator is used: / (OR) or & (AND)
                    -- Initialize metadata tables if needed
                    if not conditionals._operators then
                        conditionals._operators = {}
                    end
                    if not conditionals._groups then
                        conditionals._groups = {}
                    end

                    -- Check which separator is present in the CURRENT args
                    local hasSlash = string.find(args, "/")
                    local hasAmpersand = string.find(args, "&")

                    -- Detect if & is part of a multi-comparison pattern (e.g., >0&<10)
                    -- Pattern: operator+number followed by & (with optional whitespace) followed by operator
                    -- IMPORTANT: Only whitespace allowed around &, NOT letters (to distinguish from Rip>3&Rake>3)
                    local isMultiComparison = hasAmpersand and string.find(args, "[>~=<]+%d+%.?%d*%s*&%s*[>~=<]")

                    local separator = "/"
                    local operatorType = "OR"

                    if hasAmpersand and not hasSlash and not isMultiComparison then
                        separator = "&"
                        operatorType = "AND"
                    elseif hasAmpersand and hasSlash then
                        -- Both separators present - default to / (OR) and warn
                        -- Could add a warning here in the future
                        separator = "/"
                        operatorType = "OR"
                    end

                    -- Store the operator type for this conditional (for backwards compat)
                    -- Note: when groups exist, Multi/NegatedMulti will use per-group operators
                    conditionals._operators[condition] = operatorType

                    -- Create a new group for this conditional instance
                    -- Structure: { values = { ... }, operator = "OR" or "AND" }
                    if not conditionals._groups[condition] then
                        conditionals._groups[condition] = { n = 0 }
                    end
                    local currentGroup = { values = {}, n = 0, operator = operatorType }
                    local grp = conditionals._groups[condition]
                    grp.n = grp.n + 1
                    grp[grp.n] = currentGroup

                    -- Split args by the determined separator
                    for _, arg_item in CleveRoids.splitString(args, separator) do
                        local processed_arg = CleveRoids.Trim(arg_item)

                        processed_arg = string.gsub(processed_arg, '"', "")
                        processed_arg = string.gsub(processed_arg, "_", " ")
                        processed_arg = CleveRoids.Trim(processed_arg)

                        -- normalize "name#N" → "name=#N" and "#N" → "=#N"
                        local arg_for_find = processed_arg
                        arg_for_find = string.gsub(arg_for_find, "^#(%d+)$", "=#%1")
                        arg_for_find = string.gsub(arg_for_find, "([^>~=<]+)#(%d+)", "%1=#%2")

                        -- accept decimals too; capture name/op/amount
                        local _, _, name, operator, amount = string.find(arg_for_find, "([^>~=<]*)([>~=<]+)(#?%d*%.?%d+)")

                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                                "|cffff9900[Parse]|r cond=%s arg='%s' find='%s' name=%s op=%s amt=%s",
                                tostring(condition), tostring(processed_arg), tostring(arg_for_find),
                                tostring(name), tostring(operator), tostring(amount)
                            ))
                        end

                        if not operator or not amount then
                            -- No operator found, treat as simple string argument
                            table.insert(conditionals[condition], processed_arg)
                            currentGroup.n = currentGroup.n + 1
                            currentGroup.values[currentGroup.n] = processed_arg
                        else
                            local name_to_use = (name and name ~= "") and name or conditionals.action
                            local final_amount_str, num_replacements = string.gsub(amount, "#", "")
                            local should_check_stacks = (num_replacements == 1)

                            -- SPECIAL HANDLING FOR CONDITIONALS WITH MULTIPLE COMPARISONS
                            -- Detect if this conditional has multiple operators
                            -- Example: "ap>1800/<2200" or "Recently_Bandaged>0&<10" or "health>50&<80"
                            -- Works with ANY conditional that supports numeric operators
                            -- Pattern: only whitespace or separators allowed between comparisons, NOT letters
                            if string.find(processed_arg, "[>~=<]+%d+%.?%d*%s*[/&]%s*[>~=<]") then
                                -- This arg has multiple comparisons, parse them all
                                local stat_name = name_to_use
                                local comparisons = {}

                                -- Extract all operator+number pairs
                                -- Pattern matches operator followed by optional decimal number
                                for op, num in string.gfind(processed_arg, "([>~=<]+)(#?%d*%.?%d+)") do
                                    local clean_num = string.gsub(num, "#", "")
                                    local check_stacks = (string.find(num, "#") ~= nil)
                                    table.insert(comparisons, {
                                        operator = op,
                                        amount = tonumber(clean_num),
                                        checkStacks = check_stacks
                                    })
                                end

                                if table.getn(comparisons) > 0 then
                                    local entry = {
                                        name = CleveRoids.Trim(stat_name),
                                        comparisons = comparisons  -- Store all comparisons
                                    }
                                    table.insert(conditionals[condition], entry)
                                    currentGroup.n = currentGroup.n + 1
                                    currentGroup.values[currentGroup.n] = entry
                                else
                                    -- Fallback to single comparison if parsing failed
                                    local entry = {
                                        name = CleveRoids.Trim(name_to_use),
                                        operator = operator,
                                        amount = tonumber(final_amount_str),
                                        checkStacks = should_check_stacks
                                    }
                                    table.insert(conditionals[condition], entry)
                                    currentGroup.n = currentGroup.n + 1
                                    currentGroup.values[currentGroup.n] = entry
                                end
                            else
                                -- Normal single-comparison conditional (existing behavior)
                                local entry = {
                                    name = CleveRoids.Trim(name_to_use),
                                    operator = operator,
                                    amount = tonumber(final_amount_str),
                                    checkStacks = should_check_stacks
                                }
                                table.insert(conditionals[condition], entry)
                                currentGroup.n = currentGroup.n + 1
                                currentGroup.values[currentGroup.n] = entry
                            end
                        end
                    end
                end
            end
        end
        return conditionals.action, conditionals
    end
end


-- Get previously parsed or parse, store and return
function CleveRoids.GetParsedMsg(msg)
    if not msg then return end

    -- PERFORMANCE: Check cache first before doing string operations
    local cached = CleveRoids.ParsedMsg[msg]
    if cached then
        -- Use cached ignoretooltip value (already computed during first parse)
        CleveRoids._ignoretooltip = cached.ignoretooltip or 0
        return cached.action, cached.conditionals
    end

    -- Only compute ignoretooltip for new messages (not cache hits)
    -- PERFORMANCE: Use string.sub for simple prefix check instead of gsub
    local trimmed = CleveRoids.Trim(msg)
    local ignorecount = (string.sub(trimmed, 1, 1) == "?") and 1 or 0
    CleveRoids._ignoretooltip = ignorecount

    local action, conditionals = CleveRoids.ParseMsg(msg)
    -- Use ParseMsg's final _ignoretooltip value for cache, not the pre-computed one.
    -- ParseMsg may detect ? after conditional blocks (e.g., "[cond] ?action")
    -- which the prefix check above would miss.
    local finalIgnore = CleveRoids._ignoretooltip
    CleveRoids.ParsedMsg[msg] = {
        action         = action,
        conditionals   = conditionals,
        ignoretooltip  = finalIgnore,
    }
    return action, conditionals
end


function CleveRoids.GetMacro(name)
    return CleveRoids.Macros[name] or CleveRoids.ParseMacro(name)
end

-- Get a parsed macro by its Blizzard macro index (1-36). Used by the action-bar
-- path so macros are identified by slot/index rather than name.
function CleveRoids.GetMacroByIndex(macroID)
    if not macroID then return end
    return CleveRoids.Macros[macroID] or CleveRoids.ParseMacroByIndex(macroID)
end

function CleveRoids.GetSequence(args)
    return CleveRoids.Sequences[args] or CleveRoids.ParseSequence(args)
end

function CleveRoids.GetCurrentSequenceAction(sequence)
    return sequence.list[sequence.index]
end

function CleveRoids.ResetSequence(sequence)
    -- Save the GUID before clearing it
    local targetGuid = sequence.lastTargetGuid

    sequence.index = 1
    sequence.lastTargetGuid = nil  -- Clear stored GUID so next use captures fresh target

    -- Also reset per-target state for current target if tracking
    if sequence.reset and sequence.reset.target and targetGuid then
        if sequence.perTargetState then
            sequence.perTargetState[targetGuid] = nil
        end
    end
end

function CleveRoids.AdvanceSequence(sequence)
    if sequence.index < table.getn(sequence.list) then
        -- Not at the end yet, just advance normally
        local oldIndex = sequence.index
        sequence.index = sequence.index + 1

        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
              "|cff00ff00[Sequence Advanced]|r %d -> %d (of %d)",
              oldIndex, sequence.index, table.getn(sequence.list)
            ))
        end

        -- Sync per-target state if tracking by target
        if sequence.reset and sequence.reset.target and sequence.lastTargetGuid then
            sequence.perTargetState = sequence.perTargetState or {}
            sequence.perTargetState[sequence.lastTargetGuid] = {
                index = sequence.index,
                lastUpdate = GetTime(),
            }
        end
    else
        -- Sequence completed all steps - always wrap back to step 1.
        -- reset=secs/target/combat only apply as mid-sequence idle resets
        -- (matching standard WoW castsequence behavior).
        CleveRoids.ResetSequence(sequence)
    end
end

function CleveRoids.TestAction(cmd, args)
    -- `[a][b] Spell`: first passing group wins. The second return names the
    -- clause that passed so the display path can read that group's @unit.
    local variants = CleveRoids.ExpandBracketGroups(args)
    if variants then
        for i = 1, variants.n do
            local r, passed = CleveRoids.TestAction(cmd, variants[i])
            if r then return r, passed end
        end
        return
    end

    local msg, conditionals = CleveRoids.GetParsedMsg(args)

    -- Nil-safe guards
    local hasShowTooltip = (type(msg) == "string") and string.find(msg, "#showtooltip")
    local ignoreTooltip  = ((type(conditionals) == "table") and (conditionals.ignoretooltip == 1))
                           or (CleveRoids._ignoretooltip == 1)

    -- If the line is explicitly ignored for tooltip (via '?'),
    -- or it is a '#showtooltip' token, do not contribute icon/tooltip.
    if hasShowTooltip or ignoreTooltip then
        CleveRoids._ignoretooltip = 0 -- clear for next parse
        return
    end

    -- No [] block → return a testable token so the UI can pick a texture
    if not conditionals then
        if not msg or msg == "" then
            return
        else
            return CleveRoids.GetMacroNameFromAction(msg) or msg
        end
    end

    local origTarget = conditionals.target
    if cmd == "" or not CleveRoids.dynamicCmds[cmd] then
        return
    end

    -- No focus set: the clause fails quietly, exactly as the cast path does,
    -- so display and execution agree.
    if (conditionals.target == "focus" or conditionals.target == "focustarget")
       and not UnitExists("focus") then
        return
    end

    if conditionals.target == "mouseover" then
        if not CleveRoids.IsValidTarget("mouseover", conditionals.help) then
            return false
        end
    end

    -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
    if conditionals.target then
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(conditionals.target)
        if resolvedMark then conditionals.target = resolvedMark end
    end

    CleveRoids.FixEmptyTarget(conditionals)

    -- Flag for tooltip evaluation. CountEnemiesMatching skips expensive
    -- nameplate scan and known-enemy cache, using only target + unit tokens.
    CleveRoids._isTestingAction = true

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local k, v = next(conditionals)
    while k do
        if not CleveRoids.ignoreKeywords[k] then
            if not CleveRoids.Keywords[k] or not CleveRoids.Keywords[k](conditionals) then
                CleveRoids._isTestingAction = false
                conditionals.target = origTarget
                return
            end
        end
        k, v = next(conditionals, k)
    end

    CleveRoids._isTestingAction = false
    conditionals.target = origTarget
    return CleveRoids.GetMacroNameFromAction(msg) or msg, args
end

function CleveRoids.DoWithConditionals(msg, hook, fixEmptyTargetFunc, targetBeforeAction, action)
    -- Ensure TestAction flag is cleared for actual execution (safety net for error recovery)
    CleveRoids._isTestingAction = false

    -- Check macro stop flags (skip non-control commands when flag is set)
    -- This enables /stopmacro, /skipmacro, /firstaction, /nofirstaction to work without SuperMacro for vanilla macros
    if (CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag) and action ~= "STOPMACRO" and action ~= "SKIPMACRO" and action ~= "FIRSTACTION" and action ~= "NOFIRSTACTION" then
        return false
    end

    -- `[a][b] Spell`: try each group as its own clause, first pass wins -- the
    -- same walk DoCast makes over `[a] Spell; [b] Spell`.
    local variants = CleveRoids.ExpandBracketGroups(msg)
    if variants then
        for i = 1, variants.n do
            local r = CleveRoids.DoWithConditionals(variants[i], hook, fixEmptyTargetFunc, targetBeforeAction, action)
            if r then return r end
        end
        return false
    end

    local msg, conditionals = CleveRoids.GetParsedMsg(msg)

    -- Debug: Log parsed msg and action type
    if CleveRoids.equipDebugLog and action and action ~= CastSpellByName then
        CleveRoids.Print("|cff888888[EquipLog] DoWithConditionals: parsed msg='" .. tostring(msg) .. "' action=" .. tostring(action) .. "|r")
    end

    -- No conditionals. Just exit.
    if not conditionals then
        if not msg then -- if not even an empty string
            return false
        else
            if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
                if string.sub(msg, 2, 2) == "\"" and string.sub(msg, -2, -2) == "\"" then
                    return CleveRoids.ExecuteMacroBody(string.sub(msg, 3, -3), true)
                else
                    return CleveRoids.ExecuteMacroByName(string.sub(msg, 2, -2))
                end
            end

            -- Handle STOPMACRO/SKIPMACRO/FIRSTACTION/NOFIRSTACTION without conditionals (bare command)
            if action == "STOPMACRO" then
                CleveRoids.stopMacroFlag = true
                return true
            elseif action == "SKIPMACRO" then
                CleveRoids.skipMacroFlag = true
                return true
            elseif action == "FIRSTACTION" then
                CleveRoids.stopOnCastFlag = true
                return true
            elseif action == "NOFIRSTACTION" then
                -- Clear flags - same logic as DoNoFirstAction
                local wasFirstActionActive = CleveRoids.stopOnCastFlag
                CleveRoids.stopOnCastFlag = false
                if wasFirstActionActive and CleveRoids.stopMacroFlag then
                    CleveRoids.stopMacroFlag = false
                end
                return true
            end

            if hook then
                hook(msg)
            end
            return true
        end
    end

    if conditionals.cancelaura then
        if CleveRoids.CancelAura(conditionals.cancelaura) then
            return true
        end
    end

    local origTarget = conditionals.target
    if conditionals.target == "mouseover" then
        if UnitExists("mouseover") then
            conditionals.target = "mouseover"
        elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
            conditionals.target = CleveRoids.mouseoverUnit
        else
            conditionals.target = "mouseover"
        end
    end

    local needRetarget = false
    if fixEmptyTargetFunc then
        needRetarget = fixEmptyTargetFunc(conditionals, msg, hook)
    end

    -- CleveRoids.SetHelp(conditionals)

    -- No focus set: fail the clause quietly so `[@focus,...] X; X` and
    -- `[@focus][] X` fall through like @mouseover does, instead of announcing
    -- "Invalid target" on the way past.
    if (conditionals.target == "focus" or conditionals.target == "focustarget")
       and not UnitExists("focus") then
        return false
    end

    -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
    if conditionals.target then
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(conditionals.target)
        if resolvedMark then conditionals.target = resolvedMark end
    end

    -- Handle [multiscan:priority] - scan enemies and find best target
    -- Must be processed BEFORE the Keywords loop since it sets conditionals.target
    -- Pass origTarget so @unit syntax makes that unit exempt from combat check
    if conditionals.multiscan then
        local scanResult = CleveRoids.ResolveMultiscanTarget(conditionals, origTarget)
        if not scanResult then
            -- No valid target found - fail this conditional line (try next)
            conditionals.target = origTarget
            return false
        end
        -- Set target to the found GUID for soft-casting via SuperWoW or Nampower v2.37+
        conditionals.target = scanResult
        -- Don't need to retarget since we're using GUID directly
        needRetarget = false
    end

    for k, v in pairs(conditionals) do
        if not CleveRoids.ignoreKeywords[k] then
            local result = CleveRoids.Keywords[k] and CleveRoids.Keywords[k](conditionals)
            -- Debug logging for equipped conditional when equipDebugLog is enabled
            if CleveRoids.equipDebugLog and (k == "equipped" or k == "noequipped") then
                local valStr = type(v) == "table" and table.concat(v, ", ") or tostring(v)
                CleveRoids.Print("|cff888888[EquipLog] Conditional [" .. k .. ":" .. valStr .. "] = " ..
                    (result and "|cff00ff00PASS|r" or "|cffff0000FAIL|r") .. "|r")
            end
            -- Debug logging for macro reference debug
            if CleveRoids.macroRefDebug then
                local valStr = (v == true) and "" or (type(v) == "table" and table.concat(v, ", ") or tostring(v))
                CleveRoids.Print("|cff888888[MacroRef]|r [" .. k .. (valStr ~= "" and (":" .. valStr) or "") .. "] = " ..
                    (result and "|cff00ff00PASS|r" or "|cffff0000FAIL|r"))
            end
            if not result then
                if needRetarget then
                    TargetLastTarget()
                    needRetarget = false
                end
                conditionals.target = origTarget
                return false
            end
        end
    end

    if conditionals.target ~= nil and targetBeforeAction and not (action == CastSpellByName and (CleveRoids.hasSuperwow or CleveRoids.hasCastSpellByNameUnitToken)) then
        if not UnitIsUnit("target", conditionals.target) then
            if SpellIsTargeting() then
                SpellStopCasting()
            end
            TargetUnit(conditionals.target)
            needRetarget = true
        else
             if needRetarget then needRetarget = false end
        end
    elseif needRetarget then
        TargetLastTarget()
        needRetarget = false
    end

    if action == "STOPMACRO" then
        -- Set flag to stop subsequent lines in current macro AND parent macros
        CleveRoids.stopMacroFlag = true
        return true
    elseif action == "SKIPMACRO" then
        -- Set flag to skip remaining lines in current submacro only
        CleveRoids.skipMacroFlag = true
        return true
    elseif action == "FIRSTACTION" then
        -- Set flag to stop on first successful cast/use
        CleveRoids.stopOnCastFlag = true
        return true
    elseif action == "NOFIRSTACTION" then
        -- Clear flags to re-enable multi-queue behavior
        -- Also clear stopMacroFlag if it was set by the firstaction mechanism
        local wasFirstActionActive = CleveRoids.stopOnCastFlag
        CleveRoids.stopOnCastFlag = false
        if wasFirstActionActive and CleveRoids.stopMacroFlag then
            CleveRoids.stopMacroFlag = false
        end
        return true
    end

    local result = true
    if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff00ffff[MacroRef]|r Detected macro reference: " .. msg)
        end
        if string.sub(msg, 2, 2) == "\"" and string.sub(msg, -2,-2) == "\"" then
            result = CleveRoids.ExecuteMacroBody(string.sub(msg, 3, -3), true)
        else
            result = CleveRoids.ExecuteMacroByName(string.sub(msg, 2, -2))
        end
    elseif msg == "" or msg == nil then
        -- Empty action (conditionals passed but no spell to cast)
        -- For non-spell actions (pet commands, etc.), still execute the action
        if CleveRoids.equipDebugLog and action and action ~= CastSpellByName then
            CleveRoids.Print("|cffff8800[EquipLog] Empty msg branch - calling action() with no args|r")
        end
        if action and action ~= CastSpellByName then
            action()
            result = true
        else
            result = false
        end
    else
        local castMsg = msg
        -- FLEXIBLY check for any rank text like "(Rank 9)" before adding the highest rank
        -- Use specific "(Rank" check instead of any parentheses, so spells like
        -- "Faerie Fire (Feral)" still get their rank appended automatically
        if action == CastSpellByName and not string.find(msg, "%(Rank") then
            local sp = CleveRoids.GetSpell(msg)
            local rank = sp and (sp.rank or (sp.highest and sp.highest.rank))
            if rank and rank ~= "" then
                castMsg = msg .. "(" .. rank .. ")"
            end
        end
        if conditionals.cursor then
            -- [cursor]: place a ground-target spell/item at the cursor via
            -- ClassicAPI (no AoE-reticle click). Both functions fall back to a
            -- normal cast/use for non-ground actions.
            if action == CastSpellByName then
                local sp = CleveRoids.GetSpell(msg)
                local spellId = sp and sp.id
                if not spellId and GetSpellIdForName then
                    spellId = GetSpellIdForName(castMsg)
                end
                if spellId then
                    C_Spell.CastAtCursor(spellId)
                else
                    CastSpellByName(castMsg)
                end
            else
                C_Item.UseAtCursor(msg)
            end
        elseif action == CastSpellByName then
            if msg == CleveRoids.Localized.Attack and (conditionals.noSpam or conditionals.checkchanneled) then
                -- Melee Attack toggle: use the non-toggling AttackTarget (CastSpellNoToggle
                -- covers auto-repeat + self-auras, not the melee swing).
                AttackTarget()
            elseif conditionals.noSpam then
                -- ! prefix anti-spam. CastSpellNoToggle handles engine toggles
                -- (auto-repeat Shoot/Auto Shot/Wand, forms/stances/aspects/seals):
                -- it no-ops when already active instead of toggling off. It only
                -- covers true toggle auras, though, so also skip re-applying an
                -- already-active regular self-buff (e.g. Mark of the Wild, Renew).
                if CleveRoids.ValidatePlayerBuff(msg) then
                    result = false
                else
                    CastSpellNoToggle(castMsg)
                end
            elseif (CleveRoids.hasSuperwow or CleveRoids.hasCastSpellByNameUnitToken) and conditionals.target and origTarget then
                CastSpellByName(castMsg, conditionals.target)
            else
                CastSpellByName(castMsg)
            end
        else
            -- For other actions like item use etc. Pass the resolved unit token so
            -- item-use can target it directly (DoUse -> C_Item.UseItemByName); action
            -- closures that only take (msg) simply ignore the extra arg.
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff00ff00[EquipLog] Calling action('" .. tostring(msg) .. "')|r")
            end
            action(msg, conditionals.target)
        end
    end

    if needRetarget then
        TargetLastTarget()
    end

    -- [stopattack]: Deferred to OnUpdate (next frame) using CheapShot pattern.
    -- AttackTarget()+ClearTarget() on first frame, enforce clear for 0.2s,
    -- then retarget via stored GUID.
    if conditionals.stopattack then
        CleveRoids.DeferStopAttack()
    end

    conditionals.target = origTarget
    return result
end

function CleveRoids.DoCast(msg)
    if CleveRoids.ChannelTimeDebug then
        if msg and string.find(msg, "Arcane") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[/cast BUTTON PRESS]|r " .. msg)
        end
    end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = parts[i]
        if CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.CAST_SlashCmd, CleveRoids.FixEmptyTarget, false, CastSpellByName) then
            -- If /firstaction was used, stop macro evaluation after first successful cast
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- Resolve unit for /pfcast: mouseover → GetMouseFocus label+id → mouseoverUnit → target → player
-- Mirrors pfUI's own unit resolution order so /pfcast conditionals evaluate against the same unit
-- that pfUI would cast on.
local function ResolvePfCastUnit()
    if UnitExists("mouseover") then
        return "mouseover"
    end
    local frame = GetMouseFocus and GetMouseFocus()
    if frame and frame.label and frame.id then
        return frame.label .. frame.id
    elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
        return CleveRoids.mouseoverUnit
    elseif UnitExists("target") then
        return "target"
    elseif GetCVar and GetCVar("autoSelfCast") == "1" then
        return "player"
    end
    return nil
end

-- One /pfcast clause. If conditionals are present but no explicit @unit, inject the
-- pfUI-resolved unit so all conditionals ([help], [nodebuff:X], etc.) evaluate against
-- the same unit pfUI would cast on, and the final CastSpellByName gets the correct
-- unit token. Module-level to avoid a closure per call.
local function PfCastClause(v)
    if string.find(v, "%[") and not string.find(v, "@") then
        local unit = ResolvePfCastUnit()
        if unit then
            v = string.gsub(v, "%[", "[@" .. unit .. ",", 1)
        end
    end
    return CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.PFCAST_SlashCmd, CleveRoids.FixEmptyTarget, false, CastSpellByName)
end

-- /pfcast with CleveRoids conditionals: evaluate conditionals then cast via pfUI's mouseover chain.
-- Called from the SlashCmdList.PFCAST hook (set up by Extensions/Mouseover/pfUI.lua after pfUI loads).
function CleveRoids.DoPfCast(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        -- Expand `[a][b] Spell` here rather than leaving it to DoWithConditionals so
        -- every group without its own @unit gets the injection, not just the first.
        local variants = CleveRoids.ExpandBracketGroups(parts[i])
        local handled
        if variants then
            for j = 1, variants.n do
                handled = PfCastClause(variants[j])
                if handled then break end
            end
        else
            handled = PfCastClause(parts[i])
        end
        if handled then
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- PERFORMANCE: Module-level pet cast action to avoid closure allocation per call
local function _petCastAction(spellName)
    local petSpell = CleveRoids.GetPetSpell(spellName)
    if petSpell and petSpell.slot then
        CastPetAction(petSpell.slot)
        return true
    end
    return false
end

function CleveRoids.DoCastPet(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = parts[i]
        if CleveRoids.DoWithConditionals(v, _petCastAction, CleveRoids.FixEmptyTarget, false, _petCastAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoTarget(msg)
    -- Check macro stop flags
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then
        return false
    end

    -- Conditional /target takes `;` clauses and `[a][b]` groups like /cast does:
    -- the first clause or group that finds a unit wins. A single-group clause
    -- falls through to the resolution below.
    if msg and string.find(msg, "%[") then
        local parts = CleveRoids.splitStringIgnoringQuotes(msg)
        local n = table.getn(parts)
        if n > 1 then
            for i = 1, n do
                if CleveRoids.DoTarget(parts[i]) then return true end
            end
            return false
        end
        local variants = CleveRoids.ExpandBracketGroups(parts[1])
        if variants then
            for i = 1, variants.n do
                if CleveRoids.DoTarget(variants[i]) then return true end
            end
            return false
        end
    end

    local action, conditionals = CleveRoids.GetParsedMsg(msg)

    if action ~= "" or type(conditionals) ~= "table" or not next(conditionals) then
        CleveRoids.Hooks.TARGET_SlashCmd(msg)
        return true
    end

    local function IsGuidValid(unitTok, conds)
        if not unitTok or not UnitExists(unitTok) or CleveRoids.IsUnitDeadOrGhost(unitTok) then
            return false
        end
        local orig = conds.target
        conds.target = unitTok
        local ok = true
        for k, _ in pairs(conds) do
            if not CleveRoids.ignoreKeywords[k] then
                local fn = CleveRoids.Keywords[k]
                if not fn or not fn(conds) then ok = false; break end
            end
        end
        conds.target = orig
        return ok
    end

    -- Save original target GUID for potential restoration (SuperWoW returns GUID as 2nd value)
    local originalTargetGuid = CleveRoids.GetGUID("target")

    -- Handle [multiscan:priority] - use ResolveMultiscanTarget for enemy scanning
    -- ResolveMultiscanTarget handles its own target save/restore internally
    if conditionals.multiscan then
        local scanResult = CleveRoids.ResolveMultiscanTarget(conditionals, conditionals.target)
        if scanResult then
            TargetUnit(scanResult)
            return true
        end
        -- No match found - restore original target if scanning changed it
        if originalTargetGuid and UnitExists(originalTargetGuid) then
            TargetUnit(originalTargetGuid)
        elseif not originalTargetGuid then
            ClearTarget()
        end
        return false
    end

    -- Track if an explicit target was specified via @unit syntax
    local explicitTarget = conditionals.target

    do
        local unitTok = conditionals.target

        if unitTok == "mouseover" then
            if UnitExists("mouseover") then
                unitTok = "mouseover"
            elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
                unitTok = CleveRoids.mouseoverUnit
            elseif pfUI and pfUI.uf and pfUI.uf.mouseover and pfUI.uf.mouseover.unit
               and UnitExists(pfUI.uf.mouseover.unit) then
                unitTok = pfUI.uf.mouseover.unit
            else
                unitTok = nil
            end
        end

        -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(unitTok)
        if resolvedMark then unitTok = resolvedMark end

        if unitTok and UnitExists(unitTok) and IsGuidValid(unitTok, conditionals) then
            TargetUnit(unitTok)
            return true
        end

        -- If an explicit target was specified via @unit syntax but doesn't exist or isn't valid,
        -- return false instead of falling through to candidate search.
        -- This ensures "/target [@mouseover,harm,alive]" does nothing when mouse is over empty ground.
        if explicitTarget then
            return false
        end
    end

    if UnitExists("target") and IsGuidValid("target", conditionals) then
        return true
    end

    local candidates = {}
    local wantsHelp = conditionals.help
    local wantsHarm = conditionals.harm

    local function addCandidate(unitId)
        if not UnitExists(unitId) then return end

        if wantsHelp and not UnitCanAssist("player", unitId) then return end

        if wantsHarm and not UnitCanAttack("player", unitId) then return end

        table.insert(candidates, { unitId = unitId })
    end

    addCandidate("mouseover")

    addCandidate("target")

    if not wantsHarm then
        table.insert(candidates, { unitId = "player" })
    end

    addCandidate("pet")

    for i = 1, 4 do
        addCandidate("party"..i)
        addCandidate("partypet"..i)
        addCandidate("party"..i.."target")
    end

    for i = 1, 40 do
        addCandidate("raid"..i)
        addCandidate("raidpet"..i)
        addCandidate("raid"..i.."target")
    end

    addCandidate("targettarget")
    addCandidate("targettargettarget")

    addCandidate("pettarget")

    addCandidate("focus")
    addCandidate("focustarget")

    -- Visible nameplates as targeting candidates, via ClassicAPI's nameplateN
    -- unit tokens -- no SuperWoW WorldFrame child-walk / GUID scrape, and covers
    -- default vanilla nameplates too. Slots are sparse (a removed plate leaves
    -- its slot vacant until reused), so scan the full range rather than breaking
    -- on the first gap; UnitExists returns false cleanly for a free/out-of-range
    -- slot.
    for i = 1, 40 do
        local plate = "nameplate" .. i
        if UnitExists(plate) then
            addCandidate(plate)
        end
    end

    for _, c in ipairs(candidates) do
        if IsGuidValid(c.unitId, conditionals) then
            TargetUnit(c.unitId)
            return true
        end
    end

    -- UnitXP 3D enemy scanning: cycles through enemies in world space (no nameplate required)
    -- This is the most powerful scan - finds enemies by line of sight and distance
    -- Always enabled unless explicitly looking for friendlies only ([help] without [harm])
    -- UnitXP only finds enemies, so this is safe for any /target with conditionals
    local wantsFriendlyOnly = wantsHelp and not wantsHarm
    if not wantsFriendlyOnly and CleveRoids.hasUnitXP then
        -- Try nearestEnemy first - most common case and most efficient
        local found = UnitXP("target", "nearestEnemy")
        if found and UnitExists("target") and IsGuidValid("target", conditionals) then
            return true
        end

        -- Determine scan mode: use distance-priority for melee conditionals
        local wantsMelee = conditionals.meleerange or conditionals.nomeleerange
        local scanMode = wantsMelee and "nextEnemyConsideringDistance" or "nextEnemyInCycle"

        local seenGuids = {}
        local firstGuid = nil
        local maxIterations = 50  -- Safety limit

        for i = 1, maxIterations do
            found = UnitXP("target", scanMode)
            if not found then break end

            local currentGuid = CleveRoids.GetGUID("target")
            if not currentGuid then break end

            -- Check if we've cycled back to start
            if firstGuid == nil then
                firstGuid = currentGuid
            elseif currentGuid == firstGuid then
                break  -- Completed full cycle
            end

            -- Skip already-seen targets
            if not seenGuids[currentGuid] then
                seenGuids[currentGuid] = true

                -- Test this target against all conditionals
                if IsGuidValid("target", conditionals) then
                    return true  -- Found matching target
                end
            end
        end

        -- No match found via UnitXP scan - restore original target if we had one
        if originalTargetGuid and UnitExists(originalTargetGuid) then
            TargetUnit(originalTargetGuid)
        elseif not originalTargetGuid then
            ClearTarget()
        end
    end

    -- TargetNearestEnemy() fallback: cycles through enemies via tab-targeting
    -- Finds enemy players that UnitXP may miss (e.g. [class:Rogue harm])
    if not wantsFriendlyOnly then
        TargetNearestEnemy()
        if UnitExists("target") then
            local firstGuid2 = CleveRoids.GetGUID("target")
            if firstGuid2 then
                if IsGuidValid("target", conditionals) then
                    return true
                end

                for i = 1, 50 do
                    TargetNearestEnemy()
                    if not UnitExists("target") then break end

                    local guid = CleveRoids.GetGUID("target")
                    if not guid or guid == firstGuid2 then break end

                    if IsGuidValid("target", conditionals) then
                        return true
                    end
                end
            end
        end

        -- No match found - restore original target
        if originalTargetGuid and UnitExists(originalTargetGuid) then
            TargetUnit(originalTargetGuid)
        elseif not originalTargetGuid then
            ClearTarget()
        end
    end

    -- No matching target found after all scans - restore and fail
    if originalTargetGuid and UnitExists(originalTargetGuid) then
        TargetUnit(originalTargetGuid)
    elseif not originalTargetGuid then
        ClearTarget()
    end
    return false
end

-- Attempts to attack a unit by a set of conditionals
-- msg: The raw message intercepted from a /petattack command
function CleveRoids.DoPetAction(action, msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], action, CleveRoids.FixEmptyTarget, true, action) then
            return true
        end
    end
    return false
end

-- PERFORMANCE: Module-level action to avoid closure allocation per call
local function _startAttackAction()
    if not UnitExists("target") or CleveRoids.IsUnitDead("target") then TargetNearestEnemy() end
    -- Ground truth is the real action-bar state, NOT the cached autoAttack flag.
    -- The flag can drift stale-true (e.g. set optimistically after AttackTarget below,
    -- or a target dying without PLAYER_LEAVE_COMBAT firing), which would make us wrongly
    -- believe we're already swinging and skip the attack. Use the ORIGINAL API here:
    -- the overridden global IsCurrentAction just echoes the cached flag for the attack
    -- slot, so it can't detect drift. Fall back to the flag only if the slot is unknown.
    local isAttacking = CleveRoids.CurrentSpell.autoAttack
    local slot = CleveRoids.GetProxyActionSlot(CleveRoids.Localized.Attack)
    if slot then
        isAttacking = CleveRoids.Hooks.IsCurrentAction(slot) and true or false
        CleveRoids.CurrentSpell.autoAttack = isAttacking
    end
    if not isAttacking and not CleveRoids.CurrentSpell.autoAttackLock and UnitExists("target") and UnitCanAttack("player", "target") then
        CleveRoids.CurrentSpell.autoAttackLock = true
        CleveRoids.autoAttackLockElapsed = GetTime()
        AttackTarget()
        -- FIX: Immediately set autoAttack flag so subsequent macro lines know attack started
        -- Don't wait for PLAYER_ENTER_COMBAT event which has a delay
        CleveRoids.CurrentSpell.autoAttack = true
        -- FIX: Queue icon update so action bars reflect the new state
        if CleveRoidMacros and CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- Attempts to conditionally start an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStartAttack(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        -- We pass 'nil' for the hook, so DoWithConditionals does nothing if it fails to parse conditionals.
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _startAttackAction) then
            return true
        end
    end
    return false
end

-- Stop channeling on the next tick (nampower v2.18+), behind /stopchanneling.
-- The underlying API no-ops in two cases and a command that does nothing
-- without saying why reads as broken, so each gets a one-shot warning -- the
-- same treatment the [rooted] conditional gives a too-old nampower.
local _stopChannelingWarned = {}
local function warnStopChanneling(key, reason)
    if _stopChannelingWarned[key] then return end
    _stopChannelingWarned[key] = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r /stopchanneling "
        .. reason .. ".", 1, 0.5, 0.5)
end

function CleveRoids.StopChanneling()
    local API = CleveRoids.NampowerAPI

    -- Nothing was sent: nampower is absent or predates ChannelStopCastingNextTick.
    if not API.StopChannelNextTick() then
        warnStopChanneling("version", "requires Nampower v2.18.0 or newer")
        return false
    end

    -- The call went through, but nampower only acts on it while channel
    -- queueing is on, so the channel would run to completion regardless.
    if not API.IsQueueingEnabled("channeling") then
        warnStopChanneling("setting", "requires Nampower's NP_QueueChannelingSpells setting to be enabled")
        return false
    end

    return true
end

-- PERFORMANCE: Module-level actions to avoid closure allocation per call
local function _stopAttackAction()
    CleveRoids.DeferStopAttack()
end

local function _stopCastingAction()
    SpellStopCasting()
end

local function _stopChannelingAction()
    CleveRoids.StopChanneling()
end

-- Attempts to conditionally stop an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopAttack(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _stopAttackAction) then
            return true
        end
    end
    return false
end

-- Attempts to conditionally stop casting. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopCasting(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _stopCastingAction) then
            return true
        end
    end
    return false
end

-- Attempts to conditionally interrupt channeling. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopChanneling(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _stopChannelingAction) then
            return true
        end
    end
    return false
end

local function _clearTargetAction()
    ClearTarget()
end

-- Attempts to conditionally clear target. Returns false if no conditionals are found.
function CleveRoids.DoConditionalClearTarget(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _clearTargetAction) then
            return true
        end
    end
    return false
end

-- Resolve an EQUIPPED inventory slot (1-19) holding the item, or nil.
-- C_Item.UseItemByName only searches bags, so equipped-only items (trinkets,
-- weapons) must be fired via their slot. Prefer nampower's fast lookup; fall
-- back to a manual scan for clients without FindPlayerItemSlot (< v2.18).
local function FindEquippedItemSlot(msg, itemId)
    local API = CleveRoids.NampowerAPI
    if type(API) == "table" and API.FindItemFast then
        local info = API.FindItemFast(itemId or msg)
        if info and info.inventoryID then return info.inventoryID end
        -- Found only in bags (or not at all) -> not an equipped-only item.
        if info then return nil end
    end
    -- Fallback scan of equipped slots by ID or name, read straight from each
    -- slot via ClassicAPI (GetInventoryItemID / C_Item.GetItemNameByID) -- no
    -- link string built, no "item:"/"|h[..]|h" parse. Slots are 1-19.
    local wantLower = (not itemId) and string_lower(msg) or nil
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            if itemId then
                if id == itemId then return slot end
            else
                local nm = C_Item.GetItemNameByID(id)
                if nm and string_lower(nm) == wantLower then return slot end
            end
        end
    end
    return nil
end

-- Attempts to use an item by a set of conditionals
-- Also checks if a condition is a spell so that you can mix item and spell use
-- msg: The raw message intercepted from a /use command
function CleveRoids.DoUse(msg)
    -- Check macro stop flags
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then
        return false
    end

    local handled = false

    local action = function(msg, unit)
        -- Defensive: make sure we are not in "split stack" mode and nothing is on the cursor
        if type(CloseStackSplitFrame) == "function" then CloseStackSplitFrame() end
        if CursorHasItem and CursorHasItem() then ClearCursor() end

        -- Only pass a cast target when it actually exists, so a stale @unit doesn't
        -- waste a consumable. Self-use items (potions/food/hearth) ignore it anyway.
        local useUnit = (unit and UnitExists(unit)) and unit or nil

        -- Direct equipped inventory slot ID (1-19): use it in place.
        local slotId = tonumber(msg)
        if slotId and slotId >= 1 and slotId <= 19 then
            ClearCursor() -- extra safety before using equipped items
            UseInventoryItem(slotId)
            return
        end

        -- Equipped items (trinkets, weapons) live outside bags, so C_Item.UseItemByName
        -- can't reach them. Fire an equipped match through its slot first.
        local invSlot = FindEquippedItemSlot(msg, slotId)
        if invSlot then
            ClearCursor()
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseInventoryItem(" .. invSlot .. ")|r")
            end
            UseInventoryItem(invSlot)
            return
        end

        -- Bag path: one ClassicAPI call finds the item in bags and dispatches by
        -- type (potion/food/scroll/on-use), honoring `useUnit` for targeted-spell
        -- items. itemIDs pass as numbers; names/links pass through unchanged.
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via C_Item.UseItemByName(" .. tostring(slotId or msg) .. ", " .. tostring(useUnit) .. ")|r")
        end
        C_Item.UseItemByName(slotId or msg, useUnit)
    end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], action, CleveRoids.FixEmptyTarget, false, action) then
            -- If /firstaction was used, stop macro evaluation after first successful use
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- Find an item in bags by name (ignoring equipped items)
-- Used to prefer bag copies over swapping from paired equipped slots
-- (e.g., dual-wielding the same weapon with /equipmh + /equipoh)
local function FindItemInBagsByName(itemName)
    if not itemName then return nil, nil end
    local lowerName = string_lower(itemName)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local name = C_Item.GetItemName({ bagID = bag, slotIndex = slot })
            if name and string_lower(name) == lowerName then
                return bag, slot
            end
        end
    end
    return nil, nil
end

function CleveRoids.EquipBagItem(msg, slotOrOffhand)
    if CleveRoids.equipDebugLog then
        CleveRoids.Print("|cff00ffff[EquipLog] EquipBagItem called: '" .. tostring(msg) .. "' slot=" .. tostring(slotOrOffhand) .. "|r")
    end

    if CleveRoids.equipInProgress then
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff0000[EquipLog] Equip already in progress, skipping|r")
        end
        return false
    end

    -- Accept slot number directly, or boolean for backward compatibility (false=16/MH, true=17/OH)
    local invslot
    if type(slotOrOffhand) == "number" then
        invslot = slotOrOffhand
    else
        invslot = slotOrOffhand and 17 or 16
    end
    local API = CleveRoids.NampowerAPI

    -- v2.18+: Use native fast lookup for item ID or name
    -- Guard against API being a function instead of table (addon conflict protection)
    if type(API) == "table" and type(API.features) == "table" and API.features.hasFindPlayerItemSlot then
        local searchTerm = msg
        local itemId = tonumber(msg)

        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cff888888[EquipLog] Searching for '" .. tostring(searchTerm) .. "' (slot " .. invslot .. ")|r")
        end

        -- Check if already equipped in target slot
        if API.IsItemInSlot(searchTerm, invslot) then
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff00ff00[EquipLog] '" .. tostring(searchTerm) .. "' already in slot " .. invslot .. "|r")
            end
            return true
        end

        -- Find the item (works with both ID and name)
        local itemInfo = API.FindItemFast(searchTerm)
        if CleveRoids.equipDebugLog then
            if itemInfo then
                CleveRoids.Print("|cff888888[EquipLog] FindItemFast found: invID=" .. tostring(itemInfo.inventoryID) .. " bag=" .. tostring(itemInfo.bagID) .. " slot=" .. tostring(itemInfo.slot) .. "|r")
            else
                CleveRoids.Print("|cffff8800[EquipLog] FindItemFast returned nil|r")
            end
        end
        if itemInfo then
            -- Already equipped in different slot - need to swap
            if itemInfo.inventoryID then
                if itemInfo.inventoryID == invslot then
                    return true  -- Already in correct slot
                end
                -- Before swapping from another equipped slot, check bags for another copy
                -- This handles dual-wielding the same weapon (e.g., /equipmh Scimitar + /equipoh Scimitar)
                local bagCopyBag, bagCopySlot = FindItemInBagsByName(itemInfo.name or searchTerm)
                if bagCopyBag then
                    ClearCursor()
                    PickupContainerItem(bagCopyBag, bagCopySlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.equipDebugLog then
                            CleveRoids.Print("|cff00ff00[EquipLog] Equipped bag copy of '" .. tostring(msg) .. "' from bag " .. bagCopyBag .. " slot " .. bagCopySlot .. " (preferred over swap)|r")
                        end
                        return true
                    end
                end
                -- No bag copy found - swap from equipped slot
                ClearCursor()
                PickupInventoryItem(itemInfo.inventoryID)
                if CursorHasItem and CursorHasItem() then
                    EquipCursorItem(invslot)
                    ClearCursor()
                    return true
                end
            elseif itemInfo.bagID and itemInfo.slot then
                -- In bag - equip to target slot
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slot)
                if CursorHasItem and CursorHasItem() then
                    EquipCursorItem(invslot)
                    ClearCursor()
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ff00[EquipLog] Equipped '" .. tostring(msg) .. "' from bag " .. itemInfo.bagID .. " slot " .. itemInfo.slot .. "|r")
                    end
                    return true
                end
            end
        end

        -- Item not found via v2.18 lookup - fall through to legacy path
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff8800[EquipLog] Item '" .. tostring(msg) .. "' not found via v2.18 FindPlayerItemSlot, trying legacy fallback|r")
            -- Debug: Try direct FindPlayerItemSlot call
            if FindPlayerItemSlot then
                local bag, slot = FindPlayerItemSlot(msg)
                CleveRoids.Print("|cff888888[EquipLog] Direct FindPlayerItemSlot('" .. msg .. "') = bag:" .. tostring(bag) .. " slot:" .. tostring(slot) .. "|r")
            end
        end
    end

    -- Fallback for older Nampower versions
    -- Try to interpret as item ID (numbers > 19)
    local itemId = tonumber(msg)
    if itemId and itemId > 19 then
        local itemName = nil
        if API and API.GetItemName then
            itemName = API.GetItemName(itemId)
        end
        if not itemName and GetItemInfo then
            itemName = GetItemInfo(itemId)
        end
        if itemName then
            msg = itemName
        else
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] Can't resolve item ID " .. tostring(itemId) .. "|r")
            end
            return false  -- Can't resolve item ID
        end
    end

    -- PERFORMANCE: Fast check if already equipped (single function call)
    if CleveRoids.IsItemEquipped and CleveRoids.IsItemEquipped(msg, invslot) then
        return true
    end

    -- Note what's currently in the target slot so we can invalidate its cache
    local oldSlotName = C_Item.GetItemName({ equipmentSlotIndex = invslot })

    -- Helper to invalidate displaced item's cache
    local function InvalidateDisplacedItem()
        if oldSlotName and CleveRoids.Items then
            CleveRoids.Items[oldSlotName] = nil
            CleveRoids.Items[string_lower(oldSlotName)] = nil
        end
    end

    -- Check if item is already equipped in the paired slot (swap case)
    -- EquipItemByName doesn't handle swapping equipped items, so we must do it manually
    -- Paired slots: trinkets (13<->14), weapons (16<->17), rings (11<->12)
    -- BUT: check bags first for another copy (e.g., dual-wielding same weapon)
    local pairedSlots = {[13] = 14, [14] = 13, [16] = 17, [17] = 16, [11] = 12, [12] = 11}
    local checkSlot = pairedSlots[invslot]
    if checkSlot then
        local slotItemName = C_Item.GetItemName({ equipmentSlotIndex = checkSlot })
        if slotItemName then
            if string_lower(slotItemName) == string_lower(msg) then
                -- Item found in paired slot - but prefer a bag copy if one exists
                local bagCopyBag, bagCopySlot = FindItemInBagsByName(msg)
                if bagCopyBag then
                    -- Bag copy available - equip from bag instead of swapping
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ffff[EquipLog] Found bag copy, equipping from bag " .. bagCopyBag .. " slot " .. bagCopySlot .. " instead of swapping from slot " .. checkSlot .. "|r")
                    end
                    ClearCursor()
                    PickupContainerItem(bagCopyBag, bagCopySlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.Items then
                            CleveRoids.Items[msg] = nil
                            CleveRoids.Items[string_lower(msg)] = nil
                        end
                        InvalidateDisplacedItem()
                        return true
                    end
                    ClearCursor()
                else
                    -- No bag copy - swap from paired slot
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ffff[EquipLog] Swapping from slot " .. checkSlot .. " to slot " .. invslot .. "|r")
                    end
                    ClearCursor()
                    PickupInventoryItem(checkSlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.Items then
                            CleveRoids.Items[msg] = nil
                            CleveRoids.Items[string_lower(msg)] = nil
                        end
                        InvalidateDisplacedItem()
                        return true
                    end
                    ClearCursor()
                end
            end
        end
    end

    -- PERFORMANCE: Try EquipItemByName for bag items (fast path)
    -- This is the fastest path - no item lookup, no cursor operations
    if EquipItemByName then
        local ok = pcall(EquipItemByName, msg, invslot)
        if ok then
            -- Verify the item actually landed in the target slot
            -- EquipItemByName may silently no-op for same-named items in paired slots
            -- (e.g., dual-wielding Scimitar: MH copy found first, "equipped" to same slot)
            local newName = C_Item.GetItemName({ equipmentSlotIndex = invslot })
            if newName and string_lower(newName) == string_lower(msg) then
                if CleveRoids.Items then
                    CleveRoids.Items[msg] = nil
                    CleveRoids.Items[string_lower(msg)] = nil
                end
                InvalidateDisplacedItem()
                return true
            end
            -- Verification failed - EquipItemByName didn't place item in target slot
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] EquipItemByName('" .. msg .. "', " .. invslot .. ") succeeded but item not in target slot, trying fallback|r")
            end
        end
    end

    -- PERFORMANCE: Use fast lookup first, fall back to full scan
    -- Full scan is now optimized with GetNameFromLink() instead of GetItemInfo()
    local item = CleveRoids.GetItemFast and CleveRoids.GetItemFast(msg)
    if not item then
        -- Try quick targeted scan (stops when found)
        item = CleveRoids.FindItemQuick and CleveRoids.FindItemQuick(msg)
    end
    if not item then
        -- Full scan fallback (now optimized, safe during combat)
        item = CleveRoids.GetItem(msg)
    end

    if not item or not item.name then
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff8800[EquipLog] Item '" .. tostring(msg) .. "' not found in bags or equipped|r")
        end
        return false
    end

    -- Already equipped check (by item ID from lookup)
    if item.inventoryID == invslot then
        return true
    end

    if not item.bagID and not item.inventoryID then
        return false
    end

    -- Try EquipItemByName with resolved name (in case msg was partial/different case)
    if item.name and EquipItemByName and item.name ~= msg then
        local ok = pcall(EquipItemByName, item.name, invslot)
        if ok then
            -- Verify the item actually landed in the target slot (same guard as above)
            local newName = C_Item.GetItemName({ equipmentSlotIndex = invslot })
            if newName then
                if string_lower(newName) == string_lower(item.name) then
                    if CleveRoids.Items then
                        CleveRoids.Items[item.name] = nil
                        CleveRoids.Items[string_lower(item.name)] = nil
                    end
                    InvalidateDisplacedItem()
                    return true
                end
            end
            -- Verification failed - fall through to manual cursor-based equip
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] EquipItemByName('" .. item.name .. "', " .. invslot .. ") succeeded but item not in target slot, trying manual fallback|r")
            end
        end
    end

    -- Fallback: Manual pickup and equip
    CleveRoids.equipInProgress = true

    -- PERFORMANCE: Single cursor check at start
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    end

    local pickupSuccess = false
    if item.bagID and item.slot then
        PickupContainerItem(item.bagID, item.slot)
        pickupSuccess = CursorHasItem and CursorHasItem()
    elseif item.inventoryID then
        PickupInventoryItem(item.inventoryID)
        pickupSuccess = CursorHasItem and CursorHasItem()
    end

    if not pickupSuccess then
        ClearCursor()
        CleveRoids.equipInProgress = false
        return false
    end

    -- Verify the cursor holds the item we meant to pick up. The bag can shift
    -- between the lookup and the pickup (item consumed/moved/reorganized), in
    -- which case we'd otherwise equip whatever landed on the cursor. Only abort
    -- on a definitive mismatch (false); nil = can't tell -> trust CursorHasItem.
    if item.id and CleveRoids.ClassicAPI.CursorHoldsItemID(item.id) == false then
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff8800[EquipLog] Cursor holds wrong item after pickup; aborting equip|r")
        end
        ClearCursor()
        CleveRoids.equipInProgress = false
        return false
    end

    EquipCursorItem(invslot)
    ClearCursor()

    if CleveRoids.Items and item.name then
        CleveRoids.Items[item.name] = nil
        CleveRoids.Items[string_lower(item.name)] = nil
    end
    InvalidateDisplacedItem()
    CleveRoids.equipInProgress = false
    return true
end

-- PERFORMANCE: Module-level actions to avoid closure allocation per call
local function _equipMainhandAction(msg)
    return CleveRoids.EquipBagItem(msg, false)
end

local function _equipOffhandAction(msg)
    return CleveRoids.EquipBagItem(msg, true)
end

local function _equipTrinket1Action(msg)
    return CleveRoids.EquipBagItem(msg, 13)
end

local function _equipTrinket2Action(msg)
    return CleveRoids.EquipBagItem(msg, 14)
end

local function _equipRing1Action(msg)
    return CleveRoids.EquipBagItem(msg, 11)
end

local function _equipRing2Action(msg)
    return CleveRoids.EquipBagItem(msg, 12)
end

local function _cancelFormAction()
    CancelShapeshiftForm()
end

function CleveRoids.DoEquipMainhand(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipMainhandAction, CleveRoids.FixEmptyTarget, false, _equipMainhandAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipOffhand(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipOffhandAction, CleveRoids.FixEmptyTarget, false, _equipOffhandAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipTrinket1(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipTrinket1Action, CleveRoids.FixEmptyTarget, false, _equipTrinket1Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipTrinket2(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipTrinket2Action, CleveRoids.FixEmptyTarget, false, _equipTrinket2Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipRing1(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipRing1Action, CleveRoids.FixEmptyTarget, false, _equipRing1Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipRing2(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipRing2Action, CleveRoids.FixEmptyTarget, false, _equipRing2Action) then
            return true
        end
    end
    return false
end

-- Equip a ClassicAPI equipment set by name. msg is the resolved set name (after
-- conditional parsing). ClassicAPI's own /equipset is a bare
-- GetEquipmentSetID -> UseEquipmentSet with no conditional support; routing it
-- through DoWithConditionals adds [combat]/[mod]/@unit/etc. and ";"-separated
-- fallthrough (first set whose conditionals pass wins). Nil-guarded so a client
-- without the EquipmentSet API just no-ops instead of erroring.
local function _equipSetAction(msg)
    if not msg or msg == "" then return false end
    if type(C_EquipmentSet) ~= "table" then return false end
    local setID = C_EquipmentSet.GetEquipmentSetID(msg)
    if not setID then return false end
    C_EquipmentSet.UseEquipmentSet(setID)
    return true
end

function CleveRoids.DoEquipSet(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipSetAction, CleveRoids.FixEmptyTarget, false, _equipSetAction) then
            return true
        end
    end
    return false
end

-- /equip: equip a bag item into the slot the engine picks from its inventory
-- type. Using the item instead (DoUse) only casts its on-use spell, so gear
-- without one, like a Fishing Pole, never moved. An item already worn is left
-- alone. itemIDs pass as numbers; names/links pass through unchanged.
local function _equipAction(msg)
    C_Item.EquipItemByName(tonumber(msg) or msg)
end

function CleveRoids.DoEquip(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], _equipAction, CleveRoids.FixEmptyTarget, false, _equipAction) then
            -- If /firstaction was used, stop macro evaluation after the first equip
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

function CleveRoids.DoCancelForm(msg)
    local handled
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        handled = false
        if CleveRoids.DoWithConditionals(parts[i], _cancelFormAction, CleveRoids.FixEmptyTarget, false, _cancelFormAction) then
            handled = true
            break
        end
    end

    if handled == nil then
        _cancelFormAction()
    end

    return handled
end

CleveRoids.DoUnshift = CleveRoids.DoCancelForm

function CleveRoids.DoRetarget()
    if UnitName("target") == nil
        or UnitHealth("target") == 0
        or not UnitCanAttack("player", "target")
    then
        ClearTarget()
        TargetNearestEnemy()
    end
end

-- Attempts to stop macro (stops ALL remaining lines including parent macros)
function CleveRoids.DoStopMacro(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, nil, false, "STOPMACRO") then
            return true
        end
    end
    return false
end

-- Attempts to skip remaining lines in current submacro ONLY (returns to parent)
function CleveRoids.DoSkipMacro(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, nil, false, "SKIPMACRO") then
            return true
        end
    end
    return false
end

-- Enables "stop on first successful cast" mode for the rest of the macro
-- When set, successful /cast or /use commands will set stopMacroFlag automatically
-- This allows priority-based macro evaluation: first matching cast wins
-- Example usage:
--   /firstaction
--   /cast [myrawpower:>48] Shred
--   /cast [myrawpower:>40] Claw
-- In this case, if Shred casts, Claw will NOT be queued
function CleveRoids.DoFirstAction(msg)
    -- Check if there are conditionals
    if msg and CleveRoids.Trim(msg) ~= "" then
        -- Has conditionals - use DoWithConditionals to evaluate them
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], nil, nil, false, "FIRSTACTION") then
                return true
            end
        end
        return false
    else
        -- No conditionals - just set the flag
        CleveRoids.stopOnCastFlag = true
        return true
    end
end

-- Disables "stop on first successful cast" mode, re-enabling multi-queue behavior
-- Use this to restore normal evaluation after /firstaction
-- Example usage:
--   /firstaction
--   /cast [myrawpower:>48] Shred      -- Priority section
--   /cast [myrawpower:>40] Claw
--   /nofirstaction
--   /cast Tiger's Fury                -- Can queue alongside above
--   /startattack
function CleveRoids.DoNoFirstAction(msg)
    -- Check if there are conditionals
    if msg and CleveRoids.Trim(msg) ~= "" then
        -- Has conditionals - use DoWithConditionals to evaluate them
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], nil, nil, false, "NOFIRSTACTION") then
                return true
            end
        end
        return false
    else
        -- No conditionals - clear the flags
        -- Capture stopOnCastFlag BEFORE clearing it to know if firstaction was active
        local wasFirstActionActive = CleveRoids.stopOnCastFlag
        CleveRoids.stopOnCastFlag = false
        -- Also clear stopMacroFlag if it was set by the firstaction mechanism
        -- (stopOnCastFlag being true means firstaction mode caused stopMacroFlag to be set)
        if wasFirstActionActive and CleveRoids.stopMacroFlag then
            CleveRoids.stopMacroFlag = false
        end
        return true
    end
end

function CleveRoids.DoCastSequence(sequence)
  if type(sequence) == "string" then
    sequence = CleveRoids.GetSequence(sequence)
    if not sequence then return end
  end

  if CleveRoids.currentSequence and not CleveRoids.CheckSpellCast("player") then
    CleveRoids.currentSequence = nil
  elseif CleveRoids.currentSequence then
    return
  end

  -- If sequence is complete, don't execute - let macro continue to next line
  if sequence.complete then
    return
  end

  if sequence.index > 1 and sequence.reset then
    for k,_ in pairs(sequence.reset) do
      if CleveRoids.kmods[k] and CleveRoids.kmods[k]() then
        CleveRoids.ResetSequence(sequence)
        break
      end
    end
  end

  local active = CleveRoids.GetCurrentSequenceAction(sequence)
  if not (active and active.action) then return end

  -- Debug: Show sequence state
  if CleveRoids.debug then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff00ffff[Sequence]|r Step %d/%d: '%s'",
      sequence.index, table.getn(sequence.list), active.action
    ))
  end

  -- Check for stop steps - does nothing, allows macro to fall through
  -- Sequence stays on this step until a reset condition fires (target/combat/time/modifier)
  -- Usage: /castsequence reset=target Sunder Armor, nil
  local actionLower = string.lower(CleveRoids.Trim(active.action))
  if actionLower == "nil" or actionLower == "null" or actionLower == "pass" or actionLower == "noop" then
    sequence.lastUpdate = GetTime()
    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Sequence]|r Hit stop step, falling through")
    end
    -- Don't cast anything, just return - allows macro to continue to next line
    return
  end

  sequence.lastUpdate = GetTime()

  -- Capture target GUID for reset=target (only resets on NEW target, not same target)
  if sequence.reset and sequence.reset.target and UnitExists("target") then
    local targetGuid = CleveRoids.GetGUID("target")
    sequence.lastTargetGuid = targetGuid
  end

  local prevSeq = CleveRoids.currentSequence
  CleveRoids.currentSequence = sequence

  local actionText = (sequence.cond or "") .. active.action
  local resolvedText, conds = CleveRoids.GetParsedMsg(actionText)

  -- Check if this is a macro execution {macroname}
  local macroName = CleveRoids.GetMacroNameFromAction(active.action)
  if macroName then
    -- Execute the macro
    local success = CleveRoids.ExecuteMacroByName(macroName)
    if not success then
      CleveRoids.currentSequence = prevSeq
    end
    return
  end

  local function cast_by_name(msg)
    msg = msg or ""
    -- Check specifically for "(Rank" to allow spells like "Faerie Fire (Feral)"
    -- to still get their rank appended automatically
    if not string.find(msg, "%(Rank") then
      local sp = CleveRoids.GetSpell(msg)
      local r  = (sp and sp.rank) or (sp and sp.highest and sp.highest.rank)
      if r and r ~= "" then msg = msg .. "(" .. r .. ")" end
    end
    -- Let Nampower DLL handle queuing natively via its CastSpellByName hook
    CastSpellByName(msg)
    return true
  end

  local attempted = false
  if not conds then
    attempted = cast_by_name(resolvedText or active.action)
  else
    local final = CleveRoids.DoWithConditionals(actionText, nil, CleveRoids.FixEmptyTarget, false, CastSpellByName)
    if final then
      -- DoWithConditionals returns true (boolean) when it already cast the spell,
      -- or a string spell name when conditionals were skipped. Only call cast_by_name
      -- if we got a string back (spell wasn't cast yet).
      if type(final) == "string" then
        attempted = cast_by_name(final)
      else
        attempted = true  -- Spell was already cast inside DoWithConditionals
      end
    end
  end

  if not attempted then
    CleveRoids.currentSequence = prevSeq
  end
end

CleveRoids.DoConditionalCancelAura = function(msg)
  -- Check stopmacro flag
  if CleveRoids.stopMacroFlag then return false end

  local s = CleveRoids.Trim(msg or "")
  if s == "" then return false end

  -- No conditionals? cancel immediately.
  if not string.find(s, "%[") then
    return CleveRoids.CancelAura(s)
  end

  -- Has conditionals? Let the framework evaluate them, then run CancelAura.
  return CleveRoids.DoWithConditionals(s, nil, CleveRoids.FixEmptyTarget, false, CleveRoids.CancelAura) or false
end

-- PERFORMANCE: Separate periodic cleanup timer (runs every 5 seconds instead of every frame)
CleveRoids.lastCleanupTime = 0
CleveRoids.CLEANUP_INTERVAL = 5  -- Run cleanup every 5 seconds

-- PERFORMANCE: Upvalues for OnUpdate hot path
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local pairs = pairs
local next = next
local IsAltKeyDown = IsAltKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown

-- PERFORMANCE: Module-level constants (avoid re-creation per frame)
local SEQUENCE_STALE_TIME = 300  -- 5 minutes

function CleveRoids.OnUpdate(self)
    -- PERFORMANCE: Local alias for global namespace (saves ~80+ global lookups per frame)
    local CR = CleveRoids
    local CRM = CleveRoidMacros

    -- Prevent SuperWoW API calls during shutdown (crash prevention)
    if CR.isShuttingDown then return end

    -- Clear macro stop flags at the start of each frame
    -- This ensures /stopmacro and /skipmacro only affect commands in the same frame (same macro execution)
    -- Without SuperMacro, this is necessary because we can't hook into macro line execution
    if CR.stopMacroFlag then
        CR.stopMacroFlag = false
    end
    if CR.skipMacroFlag then
        CR.skipMacroFlag = false
    end
    if CR.stopOnCastFlag then
        CR.stopOnCastFlag = false
    end

    -- PERFORMANCE: Single GetTime() call per frame
    local time = GetTime()

    -- Coalesced macro/spell/action-bar rebuild (armed by UPDATE_MACROS,
    -- SPELLS_CHANGED and PLAYER_LOGIN). Debounced so the login burst -
    -- SPELLS_CHANGED fires several times as the spellbook populates - collapses
    -- into a single rebuild. Runs even before `ready` so spells/talents are
    -- indexed before the init timer's first action-bar pass; RebuildMacros
    -- itself skips the 120-slot action-bar rebuild until ready.
    if CR.macroRebuildTime and time >= CR.macroRebuildTime then
        CR.macroRebuildTime = nil
        CR.RebuildMacros()
    end

    -- PERFORMANCE: Early exit if not ready (before any other checks)
    if not CR.ready then
        -- Handle initialization timer only when not ready
        if CR.initializationTimer and time >= CR.initializationTimer then
            CR.initializationTimer = nil
            CR.IndexItems()

            -- FIX: Set ready=true BEFORE IndexActionBars so GetAction() works
            -- IndexActionSlot calls GetAction() which has an early-exit if ready=false,
            -- preventing TestForActiveAction from populating actions.active
            CR.ready = true

            -- FIX: Suppress action event handlers during initial indexing
            -- IndexActionBars sends ACTIONBAR_SLOT_CHANGED for each slot which triggers
            -- addon handlers (pfUI, Bongos). 120 rapid calls can cause issues.
            CR._suppressActionHandlers = true
            CR.IndexActionBars()
            CR._suppressActionHandlers = false

            CR.TestForAllActiveActions()

            -- First publish of the session. Deferred to here rather than done at
            -- load because SetMacroDisplay returns false until the player exists
            -- in the world.
            CR.PublishAllDisplays()

            CR.lastUpdate = time

            -- FIX: Force refresh ALL Blizzard action buttons after initialization
            -- Blizzard queries IsUsableAction during login before we're ready,
            -- caching the wrong state. We must force a re-query for all buttons.
            -- SKIP for pfUI users - pfUI handles its own button updates and this
            -- would trigger 120 rapid handler calls causing issues.
            if not (pfUI and pfUI.bars) then
                for slot = 1, 120 do
                    if CR.Actions[slot] then
                        CR.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
                    end
                end
            end
        end
        return
    end

    -- Coalesced re-index after async item data arrives (GET_ITEM_INFO_RECEIVED).
    -- ClassicAPI warms the item cache asynchronously, so items that were still
    -- uncached during an earlier index pass land here once their
    -- SMSG_ITEM_QUERY_SINGLE response resolves. Bursts are debounced into one
    -- re-index via CR.itemInfoReindexTime (armed by the event handler).
    if CR.itemInfoReindexTime and time >= CR.itemInfoReindexTime then
        CR.itemInfoReindexTime = nil
        -- In combat: drop it; PLAYER_LEAVE_COMBAT does a full re-index once safe.
        if not UnitAffectingCombat("player") then
            CR.lastItemIndexTime = GetTime()
            CR.IndexItems()
            CR.Actions = {}
            CR.Macros = {}
            CR.IndexActionBars()
        end
    end

    -- PERFORMANCE: Cache refresh rate calculation (avoid per-frame division)
    local refreshRate = CR.cachedRefreshRate
    if not refreshRate then
        refreshRate = 1 / (CRM.refresh or 5)
        CR.cachedRefreshRate = refreshRate
    end

    -- PERFORMANCE: Throttle check FIRST - skip most work on non-throttled frames
    local lastUpdate = CR.lastUpdate or 0
    local bypassThrottle = CR.isActionUpdateQueued and CRM.realtime == 0
    local shouldUpdate = bypassThrottle or (time - lastUpdate) >= refreshRate

    if not shouldUpdate then
        return  -- Early exit for non-throttled frames
    end

    CR.lastUpdate = time

    -- LeafVillageAchievements/Legends also hook SendChatMessage and can bump ours
    -- off the top of the chain (orphaning it / decorating #showtooltip). Reclaim
    -- the top when they're present so #showtooltip stays filtered.
    if not CR._watchChatHooks then
        CR._watchChatHooks = (C_AddOns.IsAddOnLoaded("LeafVillageAchievements")
                or C_AddOns.IsAddOnLoaded("LeafVillageLegends"))
    end
    if CR._watchChatHooks then
        CR.EnsureSendChatMessageHook()
    end

    -- PERFORMANCE: Check for expired reactive procs only if we have any
    -- Use statically allocated removal buffer to avoid per-frame allocation
    local reactiveProcs = CR.reactiveProcs
    if reactiveProcs then
        local hasExpiredProc = false
        local toRemove = CR._procRemovalBuffer
        local removeCount = 0

        -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
        local spellName, procData = next(reactiveProcs)
        while spellName do
            if procData and procData.expiry and time >= procData.expiry then
                removeCount = removeCount + 1
                toRemove[removeCount] = spellName
                hasExpiredProc = true
            end
            spellName, procData = next(reactiveProcs, spellName)
        end

        -- Remove expired procs using indexed array (no pairs() overhead)
        for i = 1, removeCount do
            reactiveProcs[toRemove[i]] = nil
            toRemove[i] = nil  -- Clear for next use
        end

        -- If any proc expired, immediately update all actions
        if hasExpiredProc then
            CR.TestForAllActiveActions()
            CR.isActionUpdateQueued = false
        end
    end
    -- PERFORMANCE: Check for modifier key state changes (no events for these in vanilla WoW)
    -- Only queue update if modifier state actually changed - avoids full TestForAllActiveActions
    -- Nampower v2.41+ fires KEY_DOWN/KEY_UP for all keys including modifiers, so skip polling
    if not CR.NampowerAPI.features.hasKeyEvents then
        local altDown = IsAltKeyDown()
        local shiftDown = IsShiftKeyDown()
        local ctrlDown = IsControlKeyDown()

        if altDown ~= CR._lastAltDown or
           shiftDown ~= CR._lastShiftDown or
           ctrlDown ~= CR._lastCtrlDown then
            CR._lastAltDown = altDown
            CR._lastShiftDown = shiftDown
            CR._lastCtrlDown = ctrlDown
            -- Modifier changed - queue update in event-driven mode, or just mark for realtime
            if CRM.realtime == 0 then
                CR.isActionUpdateQueued = true
            end
        end
    end

    -- A totem's timer runs down with nothing behind it: PLAYER_TOTEM_UPDATE fires
    -- when a slot changes hands, never as one counts toward zero, so a
    -- [totem:X<N] icon would hold the answer from its last refresh until some
    -- unrelated event queued another. Unlike an aura, there is no ambient event
    -- stream to ride -- UNIT_AURA is what quietly keeps [mybuff:X<N] honest -- so
    -- a re-test once a second while any totem timer runs is the whole mechanism.
    -- Only the icon is at stake: the click path evaluates conditionals live.
    -- Realtime mode re-tests everything each tick and needs none of this.
    if CRM.realtime == 0 and time >= (CR.nextTotemPoll or 0) then
        CR.nextTotemPoll = time + 1
        if CR.AnyTotemTimerRunning() then
            CR.isActionUpdateQueued = true
        end
    end

    -- Check the saved variable to decide which update mode to use.
    if CRM.realtime == 1 then
        -- Realtime Mode: Force an update on every throttled tick for maximum responsiveness.
        CR.TestForAllActiveActions()
    else
        -- Event-Driven Mode (Default): Only update if a relevant game event has queued it.
        if CR.isActionUpdateQueued then
            CR.TestForAllActiveActions()
            CR.isActionUpdateQueued = false
        end
    end

    -- The rest of this function handles time-based logic that must always run.
    if CR.CurrentSpell.autoAttackLock and (time - CR.autoAttackLockElapsed) > refreshRate then
        CR.CurrentSpell.autoAttackLock = false
        CR.autoAttackLockElapsed = nil
    end

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local Sequences = CR.Sequences
    local seqKey, sequence = next(Sequences)
    while seqKey do
        if sequence.index > 1 and sequence.reset.secs and (time - (sequence.lastUpdate or 0)) >= sequence.reset.secs then
            CR.ResetSequence(sequence)
        end
        seqKey, sequence = next(Sequences, seqKey)
    end

    -- PERFORMANCE OPTIMIZATION: Run memory cleanup less frequently (every 5 seconds instead of every frame)
    -- This reduces CPU usage while maintaining effective memory management
    if (time - CR.lastCleanupTime) >= CR.CLEANUP_INTERVAL then
        CR.lastCleanupTime = time

        -- MEMORY: Clear spell name caches every 60 seconds (12 cleanup cycles)
        CR._spellCacheCleanupCounter = (CR._spellCacheCleanupCounter or 0) + 1
        if CR._spellCacheCleanupCounter >= 12 then
            CR._spellCacheCleanupCounter = 0
            if CR.ClearSpellNameCaches then
                CR.ClearSpellNameCaches()
            end
            if CR.ClearStripRankCache then
                CR.ClearStripRankCache()
            end
        end

        -- MEMORY: Clean up stale perTargetState entries in sequences (older than 5 minutes)
        -- This prevents memory bloat from tracking many targets over time
        -- PERFORMANCE: Use next() instead of pairs() to avoid iterator closure allocation
        local seqKey2, seq2 = next(CR.Sequences)
        while seqKey2 do
            if seq2.perTargetState then
                local ptGuid, ptState = next(seq2.perTargetState)
                while ptGuid do
                    local nextPtGuid = next(seq2.perTargetState, ptGuid)
                    if ptState.lastUpdate and (time - ptState.lastUpdate) > SEQUENCE_STALE_TIME then
                        seq2.perTargetState[ptGuid] = nil
                    end
                    ptGuid = nextPtGuid
                    ptState = nextPtGuid and seq2.perTargetState[nextPtGuid]
                end
            end
            seqKey2, seq2 = next(CR.Sequences, seqKey2)
        end
    end
end

-- Not a display override: this invalidates our per-slot caches when an action is
-- dragged off a slot, so it stays regardless of who draws the button.
CleveRoids.Hooks.PickupAction = PickupAction
function PickupAction(slot)
    if not slot then return end
    CleveRoids.ClearAction(slot)
    CleveRoids.ClearSlot(CleveRoids.actionSlots, slot)
    CleveRoids.ClearAction(CleveRoids.reactiveSlots, slot)
    return CleveRoids.Hooks.PickupAction(slot)
end

-- These two aliases outlived the overrides they were saved for: ClassicAPI now
-- draws the buttons, but callers still need the unmodified globals, which is all
-- these names are now. IsReactiveUsable (Conditionals.lua) reads the raw usable
-- state of a proxy slot; DeferStopAttack and the auto-attack drift check read the
-- true current-action state, which the old override could not report because it
-- only echoed our cached flag.
CleveRoids.Hooks.OriginalIsUsableAction = IsUsableAction
CleveRoids.Hooks.IsCurrentAction = IsCurrentAction

local function IsAutoAttackSpell(spell)
    if not spell then return false end
    if C_Spell and C_Spell.IsAutoAttackSpell and spell.id then
        return C_Spell.IsAutoAttackSpell(spell.id)
    end
    if C_SpellBook and C_SpellBook.IsAutoAttackSpellBookItem and spell.spellSlot then
        return C_SpellBook.IsAutoAttackSpellBookItem(spell.spellSlot, spell.bookType)
    end
    return false
end
CleveRoids.IsAutoAttackSpell = IsAutoAttackSpell

-- ============================================================================
-- RunMacro Hook - Use our own macro execution system
-- ============================================================================
-- This allows /stopmacro, /skipmacro, /firstaction to work across parent/child
-- macro boundaries without requiring SuperMacro addon.
--
-- When SuperMacro is installed, its RunLine hook takes precedence for extended
-- macro features. This hook handles vanilla Blizzard macros.
-- ============================================================================
if not CleveRoids.RunMacroHooked then
    CleveRoids.Hooks.RunMacro = RunMacro

    function RunMacro(indexOrName)
        -- Skip if SuperMacro is handling macro execution (it has its own hooks)
        if CleveRoids.SM_RunLineHooked then
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Resolve macro index
        local macroIndex
        if type(indexOrName) == "number" then
            macroIndex = indexOrName
        elseif type(indexOrName) == "string" then
            -- Could be a name or a numeric string
            local num = tonumber(indexOrName)
            if num then
                macroIndex = num
            else
                macroIndex = GetMacroIndexByName(indexOrName)
            end
        end

        if not macroIndex or macroIndex == 0 then
            -- Fallback to original if we can't resolve
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Get macro body
        local name, icon, body = GetMacroInfo(macroIndex)
        if not body or body == "" then
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Clear macro flags at the start of top-level macro execution
        CleveRoids.stopMacroFlag = false
        CleveRoids.skipMacroFlag = false
        -- Note: stopOnCastFlag is intentionally NOT cleared here - it persists
        -- within a frame and is cleared by OnUpdate

        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff00ff00[RunMacro Hook]|r Executing macro '" .. (name or macroIndex) .. "' via CleveRoids")
        end

        -- Execute through our system
        CleveRoids.ExecuteMacroBody(body)

        -- Don't call original - we've handled it
        return
    end

    CleveRoids.RunMacroHooked = true
end

-- This single frame drives the addon's event loop and OnUpdate. (Spell cost /
-- reagent lookups now read Spell.dbc directly via ClassicAPI -- no tooltip scan.)
CleveRoids.Frame = CreateFrame("Frame")

CleveRoids.Frame:SetScript("OnUpdate", CleveRoids.OnUpdate)
-- Declared with no parameters on purpose. In 1.12's Lua 5.0 a function written
-- `function(...)` builds a fresh `arg` table on every single call, and this fires
-- for all ~48 registered events -- including the UNIT_HEALTH / UNIT_AURA /
-- UNIT_*_GUID power streams, which tick continuously for every unit in range. That
-- was a table per event, purely as garbage: the handler reads the event globals
-- (event, this, arg1..arg10), never the vararg.
CleveRoids.Frame:SetScript("OnEvent", function()
    CleveRoids.Frame[event](this,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10)
end)

-- == SHUTDOWN PROTECTION ==
-- Flag to prevent SuperWoW API calls during logout (crash prevention)
CleveRoids.isShuttingDown = false

-- == CORE EVENT REGISTRATION ==
CleveRoids.Frame:RegisterEvent("PLAYER_LOGIN")
CleveRoids.Frame:RegisterEvent("ADDON_LOADED")
CleveRoids.Frame:RegisterEvent("PLAYER_LOGOUT")
CleveRoids.Frame:RegisterEvent("PLAYER_LEAVING_WORLD")
CleveRoids.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
CleveRoids.Frame:RegisterEvent("UPDATE_MACROS")
CleveRoids.Frame:RegisterEvent("SPELLS_CHANGED")
CleveRoids.Frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
CleveRoids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
CleveRoids.Frame:RegisterEvent("BAG_UPDATE_DELAYED")
CleveRoids.Frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
CleveRoids.Frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
CleveRoids.Frame:RegisterEvent("UNIT_PET")
CleveRoids.Frame:RegisterEvent("UNIT_HAPPINESS")

-- == STATE CHANGE EVENT REGISTRATION (for performance) ==
CleveRoids.Frame:RegisterEvent("PLAYER_TARGET_CHANGED")
CleveRoids.Frame:RegisterEvent("PLAYER_FOCUS_CHANGED") -- For focus addons
CleveRoids.Frame:RegisterEvent("PLAYER_ENTER_COMBAT")  -- Auto-attack started
CleveRoids.Frame:RegisterEvent("PLAYER_LEAVE_COMBAT")  -- Auto-attack stopped
CleveRoids.Frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entered actual combat (has threat)
CleveRoids.Frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Left actual combat (no threat)
CleveRoids.Frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
CleveRoids.Frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
CleveRoids.Frame:RegisterEvent("PLAYER_STARTED_MOVING")
-- ClassicAPI loss-of-control (school-interrupt lockout) for [locked]/[nolocked].
CleveRoids.Frame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
CleveRoids.Frame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
-- The unit state streams that drive icon refresh: GUID events when Nampower
-- provides them (v2.39+, one event per unit change rather than one per token),
-- else the stock per-token events. These cannot become RegisterUnitEvent calls
-- -- the handlers ignore the unit and refresh every macro, because a conditional
-- may name any unit ([@party3,hp:<50], @focus, @mouseover), so narrowing the
-- token set would leave those icons stale.
local unitStreamEvents
if CleveRoids.NampowerAPI.features.hasUnitGuidEvents then
    unitStreamEvents = { "UNIT_AURA_GUID", "UNIT_HEALTH_GUID", "UNIT_MANA_GUID", "UNIT_RAGE_GUID", "UNIT_ENERGY_GUID" }
else
    unitStreamEvents = { "UNIT_AURA", "UNIT_HEALTH", "UNIT_POWER" }
end

-- They do fire continuously for every unit in range, and in realtime mode their
-- handlers do nothing at all: the OnUpdate refreshes on every throttled tick and
-- QueueActionUpdate no-ops. Rather than pay a Lua dispatch per event to return
-- early, drop the registrations entirely while realtime is on. Re-applied at
-- VARIABLES_LOADED (when the saved value is first known) and whenever
-- `/cleveroid realtime` flips it.
function CleveRoids.ApplyUnitStreamEvents()
    local eventDriven = not CleveRoidMacros or CleveRoidMacros.realtime == 0
    for i = 1, table.getn(unitStreamEvents) do
        if eventDriven then
            CleveRoids.Frame:RegisterEvent(unitStreamEvents[i])
        else
            CleveRoids.Frame:UnregisterEvent(unitStreamEvents[i])
        end
    end
end
CleveRoids.ApplyUnitStreamEvents()
if QueueSpellByName then
    CleveRoids.Frame:RegisterEvent("SPELL_QUEUE_EVENT")
end
CleveRoids.Frame:RegisterEvent("START_AUTOREPEAT_SPELL")
CleveRoids.Frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_SENT")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_START")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_STOP")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
CleveRoids.Frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

-- Nampower v2.41+: keyboard input events for [keydown:X] conditional
if CleveRoids.NampowerAPI.features.hasKeyEvents then
    CleveRoids.Frame:RegisterEvent("KEY_DOWN")
    CleveRoids.Frame:RegisterEvent("KEY_UP")
end

-- ClassicAPI totem-bar tracking, for [totem:X] icon refresh. Ungated, unlike the
-- Nampower features above: it long predates the ClassicAPI floor the addon
-- already refuses to run below.
CleveRoids.Frame:RegisterEvent("PLAYER_TOTEM_UPDATE")

-- NOTE: SuperMacro hook installation is handled by Compatibility/SuperMacro.lua
-- which has the complete implementation including the INTERCEPT path for all commands

function CleveRoids.Frame:UNIT_PET()
    if arg1 == "player" then
        CleveRoids.IndexPetSpells()
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:UNIT_HAPPINESS()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- Handle shutdown to prevent SuperWoW API crashes during logout
function CleveRoids.Frame:PLAYER_LOGOUT()
    CleveRoids.isShuttingDown = true
    this:UnregisterAllEvents()
    this:SetScript("OnUpdate", nil)
    this:SetScript("OnEvent", nil)
    -- Cancel periodic C_Timer tickers
    if CleveRoids._cleanupTicker then
        CleveRoids._cleanupTicker:Cancel()
    end
    if CleveRoids._auraCleanupTicker then
        CleveRoids._auraCleanupTicker:Cancel()
    end
end

function CleveRoids.Frame:PLAYER_LEAVING_WORLD()
    -- FIX: Only set loading flag, don't unregister events
    -- PLAYER_LEAVING_WORLD fires for both logout AND zone transitions
    -- We need to stay alive for zone transitions; PLAYER_LOGOUT handles actual logout
    CleveRoids.isLoading = true
end

-- FIX: Handle zone transitions (instance entry, etc.)
-- Refresh action button state after loading screen completes
function CleveRoids.Frame:PLAYER_ENTERING_WORLD()
    CleveRoids.isLoading = false

    -- Skip if not yet initialized
    if not CleveRoids.ready then return end

    -- Refresh all action states after zone transition
    CleveRoids.TestForAllActiveActions()

    -- FIX: Force Blizzard buttons to re-query IsUsableAction
    -- Loading screen causes UI rebuild which can cache stale button states
    -- SKIP for pfUI users - pfUI handles its own button updates
    if not (pfUI and pfUI.bars) then
        for slot = 1, 120 do
            if CleveRoids.Actions[slot] then
                CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
            end
        end
    end
end

-- Simplified PLAYER_LOGIN - requirements already checked
function CleveRoids.Frame:PLAYER_LOGIN()
    -- Skip if already disabled
    if CleveRoids.disabled then return end

    _, CleveRoids.playerClass = UnitClass("player")

    CleveRoids.hasRelicSlot = UnitHasRelicSlot("player") and true or false

    CleveRoids.IndexSpells()
    CleveRoids.IndexPetSpells()
    CleveRoids.initializationTimer = GetTime() + 1.5

    -- Guarantee a full index (talents + macros + action bars) even if
    -- UPDATE_MACROS / SPELLS_CHANGED happen not to fire before the init timer.
    -- Coalesces with those events' arming; RebuildMacros runs once for the burst.
    CleveRoids.macroRebuildTime = GetTime() + 0.3

    -- PERFORMANCE: Initialize event-driven cache states
    CleveRoids._cachedPlayerInCombat = UnitAffectingCombat("player") and true or false
end

function CleveRoids.Frame:ADDON_LOADED(addon)
    -- keep your existing init for CRM:
    if addon == "CleveRoidMacros" or addon == "SuperCleveRoidMacros" then
        CleveRoids.InitializeExtensions()
    end
    -- NOTE: SuperMacro hook installation is handled by Compatibility/SuperMacro.lua
end

-- Cast events (ClassicAPI UNIT_SPELLCAST_*). The cast state itself is read on
-- demand from ClassicAPI (CleveRoids.GetPlayerCast, CheckSpellCast); these
-- handlers only refresh the action buttons and advance a /castsequence.

-- A cast started, stopped or failed: re-test the buttons now for the player,
-- and queue an update for another unit (its cast feeds [casting]).
local function OnCastChanged(self, unit)
    if unit == "player" then
        CleveRoids.TestForAllActiveActions()
    elseif CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
CleveRoids.Frame.UNIT_SPELLCAST_START = OnCastChanged
CleveRoids.Frame.UNIT_SPELLCAST_STOP = OnCastChanged
CleveRoids.Frame.UNIT_SPELLCAST_FAILED = OnCastChanged
CleveRoids.Frame.UNIT_SPELLCAST_INTERRUPTED = OnCastChanged
CleveRoids.Frame.UNIT_SPELLCAST_CHANNEL_START = OnCastChanged
CleveRoids.Frame.UNIT_SPELLCAST_CHANNEL_STOP = OnCastChanged

-- Whether spellID is the step the running /castsequence is waiting on
local function IsCurrentSequenceSpell(spellID)
    local active = CleveRoids.currentSequence
        and CleveRoids.GetCurrentSequenceAction(CleveRoids.currentSequence)
    if not (active and active.action) then return false end
    local name = C_Spell.GetSpellName(spellID)
    if not name then return false end
    if active.action == name then return true end
    local rank = C_Spell.GetSpellSubtext(spellID)
    return rank and rank ~= "" and active.action == name .. "(" .. rank .. ")"
end

-- The player's spell went off: advance the /castsequence waiting on it. A cast
-- that fails leaves the sequence on its step; DoCastSequence drops the stale
-- currentSequence on the next press and retries.
function CleveRoids.Frame:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit == "player" and IsCurrentSequenceSpell(spellID) then
        CleveRoids.currentSequence.lastUpdate = GetTime()
        CleveRoids.AdvanceSequence(CleveRoids.currentSequence)
        CleveRoids.currentSequence = nil
    end
    OnCastChanged(self, unit)
end

-- The player's cast left the client
function CleveRoids.Frame:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    CleveRoids.sentCasts[spellID] = GetTime()
end

-- PLAYER_ENTER_COMBAT/PLAYER_LEAVE_COMBAT are for AUTO-ATTACK state (not actual combat)
function CleveRoids.Frame:PLAYER_ENTER_COMBAT()
    CleveRoids.CurrentSpell.autoAttack = true
    CleveRoids.CurrentSpell.autoAttackLock = false
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_LEAVE_COMBAT()
    CleveRoids.CurrentSpell.autoAttack = false
    CleveRoids.CurrentSpell.autoAttackLock = false

    -- Full re-index after combat to refresh any items/bags that were skipped
    -- during combat for performance. Use a slight delay to avoid spam.
    local now = GetTime()
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 0.5 then
        CleveRoids.lastItemIndexTime = now
        CleveRoids.IndexItems()
        CleveRoids.Actions = {}
        CleveRoids.Macros = {}
        CleveRoids.IndexActionBars()
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- PLAYER_REGEN_DISABLED/PLAYER_REGEN_ENABLED are for ACTUAL combat state (threat/aggro)
-- These events track what UnitAffectingCombat("player") reports
function CleveRoids.Frame:PLAYER_REGEN_DISABLED()
    -- PERFORMANCE: Cache actual combat state for event-driven [combat]/[nocombat] conditionals
    CleveRoids._cachedPlayerInCombat = true
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_REGEN_ENABLED()
    -- PERFORMANCE: Cache actual combat state for event-driven [combat]/[nocombat] conditionals
    CleveRoids._cachedPlayerInCombat = false

    -- Reset any sequence with reset=combat that has progressed past the first step
    -- Uses PLAYER_REGEN_ENABLED (actual combat ends) instead of PLAYER_LEAVE_COMBAT (auto-attack stops)
    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.index > 1 and sequence.reset and sequence.reset.combat then
            CleveRoids.ResetSequence(sequence)
        end
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- Movement -> [moving]/[nomoving] icon refresh.
-- PLAYER_STARTED_MOVING is reliable; PLAYER_STOPPED_MOVING is not (key-release
-- based, misses geometry/click-to-move/root/knockback stops). So STARTED flips
-- the icon to "moving" and starts a bounded poll; the poll detects the real
-- stop from IsPlayerMoving() (the signal [moving] uses), refreshes once, and
-- shuts itself off. Only runs while actually moving, so no idle cost.
local MOVE_POLL_INTERVAL = 0.1
local moveTicker = nil

local function StopMovePoll()
    if moveTicker then
        moveTicker:Cancel()
        moveTicker = nil
    end
end

local function StartMovePoll()
    if moveTicker then return end  -- already polling this movement
    moveTicker = C_Timer.NewTicker(MOVE_POLL_INTERVAL, function()
        if CleveRoids.isShuttingDown then
            StopMovePoll()
            return
        end
        if not CleveRoids.IsPlayerMoving() then
            -- Movement actually ended -- repaint [moving]/[nomoving] icons, stop polling.
            StopMovePoll()
            if CleveRoidMacros.realtime == 0 then
                CleveRoids.QueueActionUpdate()
            end
        end
    end)
end

function CleveRoids.Frame:PLAYER_STARTED_MOVING()
    -- Started moving: flip to the [moving] icon now...
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
    -- ...and watch for the (unreliable-event) stop ourselves.
    StartMovePoll()
end

function CleveRoids.Frame:PLAYER_TARGET_CHANGED()
    CleveRoids.CurrentSpell.autoAttack = false
    CleveRoids.CurrentSpell.autoAttackLock = false

    -- Clear resist state when target changes
    CleveRoids.ClearResistState()

    -- Handle sequences with reset=target - save/restore per-target state
    -- Instead of resetting, we remember each target's progress in the sequence
    local currentGuid = nil
    if UnitExists("target") then
        currentGuid = CleveRoids.GetGUID("target")
    end

    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.reset and sequence.reset.target then
            local oldGuid = sequence.lastTargetGuid

            -- Only process if target actually changed
            if oldGuid ~= currentGuid then
                -- Save current state for the old target (if we had one and progressed)
                if oldGuid and sequence.index > 1 then
                    sequence.perTargetState = sequence.perTargetState or {}
                    sequence.perTargetState[oldGuid] = {
                        index = sequence.index,
                        lastUpdate = sequence.lastUpdate,
                    }
                end

                -- Restore state for the new target (or start fresh)
                if currentGuid and sequence.perTargetState and sequence.perTargetState[currentGuid] then
                    -- Restore saved state for this target
                    local saved = sequence.perTargetState[currentGuid]
                    sequence.index = saved.index
                    sequence.lastUpdate = saved.lastUpdate
                else
                    -- New target we haven't seen - start at step 1
                    sequence.index = 1
                end

                -- Update the current target GUID
                sequence.lastTargetGuid = currentGuid
            end
        end
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- Full rebuild of the macro/spell/talent/action-bar index. Invoked from the
-- update loop when macroRebuildTime elapses (armed by UPDATE_MACROS /
-- SPELLS_CHANGED / PLAYER_LOGIN), never inline from an event - so a burst of
-- those events collapses into one rebuild.
function CleveRoids.RebuildMacros()
    CleveRoids.currentSequence = nil
    CleveRoids.ParsedMsg = {}
    CleveRoids.ExpandedGroups = {}
    CleveRoids.Macros = {}
    CleveRoids.Actions = {}
    CleveRoids.Sequences = {}

    CleveRoids.IndexSpells()
    CleveRoids.IndexTalents()
    CleveRoids.IndexPetSpells()

    -- Action-bar indexing is wasted before `ready` (GetAction early-returns
    -- while not ready), and the +1.5s init timer rebuilds the bars once anyway.
    -- Skipping it here keeps the pre-ready login rebuilds from fanning 120 slot
    -- updates out to Blizzard/pfUI/Bongos buttons.
    if CleveRoids.ready then
        CleveRoids.IndexActionBars()
        -- Macros were re-parsed above, so every published value is stale. Covers
        -- macros that aren't on a bar, which IndexActionBars never visits.
        CleveRoids.PublishAllDisplays()
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:UPDATE_MACROS()
    -- Debounce: collapse bursts (login, rapid macro edits) into one rebuild.
    CleveRoids.macroRebuildTime = GetTime() + 0.3
end

function CleveRoids.Frame:SPELLS_CHANGED()
    -- Defer the heavy rebuild.
    CleveRoids.macroRebuildTime = GetTime() + 0.3
    if CleveRoids.IndexTalents then
        CleveRoids.IndexTalents()
    end
end

function CleveRoids.Frame:CHARACTER_POINTS_CHANGED()
    if CleveRoids.IndexTalents then
        CleveRoids.IndexTalents()
    end
end

function CleveRoids.Frame:ACTIONBAR_SLOT_CHANGED()
    CleveRoids.ClearAction(arg1)
    CleveRoids.IndexActionSlot(arg1)
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- ClassicAPI fires GET_ITEM_INFO_RECEIVED when an async item-cache fill lands
-- (the hooked GetItemInfo auto-warms on a miss). It fires for EVERY fill in the
-- game though - quest DB scans, AH sweeps, chat-link hovers, inspects - so we
-- ignore anything not in pendingItemInfo (items we own that missed the last
-- index pass). That check is O(1) and keeps unrelated bursts free.
function CleveRoids.Frame:GET_ITEM_INFO_RECEIVED()
    local pending = CleveRoids.pendingItemInfo
    if not (pending and pending[arg1]) then return end
    -- Skip during combat; PLAYER_LEAVE_COMBAT re-indexes once it's safe.
    if UnitAffectingCombat("player") then return end
    -- Arm once per burst; the update loop clears it after re-indexing. Later
    -- arrivals re-arm it, guaranteeing the final resolved state is captured.
    if not CleveRoids.itemInfoReindexTime then
        CleveRoids.itemInfoReindexTime = GetTime() + 0.5
    end
end

function CleveRoids.Frame:BAG_UPDATE_DELAYED()
    -- In combat: Skip expensive indexing but still queue icon update
    -- so conditionals like [inbag] re-evaluate (they use live bag APIs)
    if UnitAffectingCombat("player") then
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
        return
    end

    -- Out of combat: Full indexing with throttle
    local now = GetTime()
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 1.0 then
        CleveRoids.lastItemIndexTime = now
        CleveRoids.IndexItems()

        -- Rebuild action bars so item-dependent macro resolution refreshes.
        -- Skipped before `ready` (GetAction early-returns; the +1.5s init timer
        -- builds the bars), which keeps bag-fill events during login from firing
        -- a full 120-slot rebuild each time.
        if CleveRoids.ready then
            CleveRoids.Actions = {}
            CleveRoids.Macros = {}
            CleveRoids.IndexActionBars()
        end
    end

    -- Always queue icon update so conditionals like [inbag] re-evaluate
    -- even when full indexing is throttled (they use live bag APIs)
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_EQUIPMENT_CHANGED()
    -- arg1 = inventory slot that changed, arg2 = hasCurrent (slot now holds an item)
    local slot, hasCurrent = arg1, arg2

    -- In combat: skip the slot reindex to avoid lag during rapid gear swapping.
    -- [equipped] reads live engine state (C_Item.IsEquippedItem) so it stays
    -- correct regardless; the Items table self-heals on the next BAG_UPDATE.
    if UnitAffectingCombat("player") then
        return
    end

    -- Out of combat: reindex only the one slot that changed (the bag side of any
    -- swap is covered by BAG_UPDATE_DELAYED). No action-bar rebuild is needed -
    -- gear swaps don't change what's on the bars; QueueActionUpdate re-evaluates
    -- [equipped:...] icons/conditionals.
    CleveRoids.IndexEquipSlot(slot, hasCurrent)

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:START_AUTOREPEAT_SPELL()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:STOP_AUTOREPEAT_SPELL()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- Generic event handlers that just queue an update
function CleveRoids.Frame:PLAYER_FOCUS_CHANGED()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
-- School-interrupt lockout applied/changed -> refresh [locked]/[nolocked] icons.
function CleveRoids.Frame:LOSS_OF_CONTROL_ADDED()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
CleveRoids.Frame.LOSS_OF_CONTROL_UPDATE = CleveRoids.Frame.LOSS_OF_CONTROL_ADDED
function CleveRoids.Frame:UPDATE_SHAPESHIFT_FORM()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:SPELL_UPDATE_COOLDOWN()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end

    -- COOLDOWN FIX: Explicitly update cooldowns on all managed action buttons
    -- This ensures cooldowns display correctly even when the active action hasn't changed
    CleveRoids.UpdateAllManagedCooldowns()
end

-- Helper function to notify addon handlers about cooldown updates.
-- Blizzard's own buttons need nothing from us: ActionButton_OnEvent reads the stock
-- action-bar functions, which resolve through the value published with
-- C_Macro.SetMacroDisplay. This exists only for third-party bars that keep their own
-- cooldown frames -- Bongos does; pfUI's handler ignores the event outright.
--
-- Runs on every SPELL_UPDATE_COOLDOWN (so every GCD and cooldown tick) and touches
-- every managed slot, up to 120. Keep the per-slot work here and in the registered
-- handlers allocation-free.
CleveRoids.cooldownDebugLogged = {}

function CleveRoids.UpdateAllManagedCooldowns()
    local Actions = CleveRoids.Actions
    if not Actions then return end

    local handlers = CleveRoids.actionEventHandlers
    local handlerCount = handlers and table.getn(handlers) or 0
    if handlerCount == 0 then return end

    local slot, actions = next(Actions)
    while slot do
        if actions then
            for i = 1, handlerCount do
                handlers[i](slot, "ACTIONBAR_UPDATE_COOLDOWN")
            end
        end
        slot, actions = next(Actions, slot)
    end
end
-- PERFORMANCE OPTIMIZATION: Throttled event handlers to reduce CPU spam
-- UNIT_AURA can fire dozens of times per second during combat
-- 100ms throttle reduces calls by 90%+ while maintaining responsiveness
function CleveRoids.Frame:UNIT_AURA()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitAuraUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitAuraUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
function CleveRoids.Frame:UNIT_HEALTH()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitHealthUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitHealthUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
function CleveRoids.Frame:UNIT_POWER()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitPowerUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitPowerUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- GUID event handlers (v2.39+): fire once per unit state change instead of per-token
function CleveRoids.Frame:UNIT_AURA_GUID()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitAuraUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitAuraUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
function CleveRoids.Frame:UNIT_HEALTH_GUID()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitHealthUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitHealthUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
-- All power GUID events share the same handler
local function OnPowerGuidEvent()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitPowerUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitPowerUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
CleveRoids.Frame.UNIT_MANA_GUID = OnPowerGuidEvent
CleveRoids.Frame.UNIT_RAGE_GUID = OnPowerGuidEvent
CleveRoids.Frame.UNIT_ENERGY_GUID = OnPowerGuidEvent

function CleveRoids.Frame:SPELL_QUEUE_EVENT()
    if event == "SPELL_QUEUE_EVENT" then
        local eventCode = arg1
        local spellId = arg2

        local NORMAL_QUEUED = 2
        local NON_GCD_QUEUED = 4
        local ON_SWING_QUEUED = 0
        local NORMAL_QUEUE_POPPED = 3
        local NON_GCD_QUEUE_POPPED = 5
        local ON_SWING_QUEUE_POPPED = 1

        if eventCode == NORMAL_QUEUED or eventCode == NON_GCD_QUEUED or eventCode == ON_SWING_QUEUED then
            CleveRoids.queuedSpell = {
                spellId = spellId,
                queueType = eventCode,
                queueTime = GetTime()
            }
            local name = C_Spell.GetSpellName(spellId)
            if name then
                CleveRoids.queuedSpell.spellName = name
            end
            CleveRoids.QueueActionUpdate()
        elseif eventCode == NORMAL_QUEUE_POPPED or eventCode == NON_GCD_QUEUE_POPPED or eventCode == ON_SWING_QUEUE_POPPED then
            CleveRoids.queuedSpell = nil
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- Nampower v2.41+: KEY_DOWN/KEY_UP events
-- arg1=keyCode (int), arg2=metaKeyState (Shift=1,Ctrl=2,Alt=4), arg3=repeat, arg4=time
-- Meta key codes (0=Shift, 1=Ctrl, 2=Alt) are skipped — they are already tracked via IsXKeyDown()
function CleveRoids.Frame:KEY_DOWN()
    local keyCode = arg1
    if keyCode == 0 or keyCode == 1 or keyCode == 2 then return end
    CleveRoids._keyState[keyCode] = true
    CleveRoids.isActionUpdateQueued = true
end

function CleveRoids.Frame:KEY_UP()
    local keyCode = arg1
    if keyCode == 0 or keyCode == 1 or keyCode == 2 then return end
    CleveRoids._keyState[keyCode] = nil
    CleveRoids.isActionUpdateQueued = true
end

-- ClassicAPI PLAYER_TOTEM_UPDATE: arg1 = the slot (1 Fire .. 4 Air) whose totem
-- was dropped, expired, killed or recalled. The slot goes unread and every macro
-- is refreshed: a [totem:X] macro may name any slot, and [nototem:X] flips on any
-- of them.
function CleveRoids.Frame:PLAYER_TOTEM_UPDATE()
    CleveRoids.QueueActionUpdate()
end

-- Base SendChatMessage captured at first hook; used to break a hook cycle.
local baseSendChatMessage = SendChatMessage
local sendingChatMessage = false

-- Swallow #showtooltip lines Blizzard's macro executor sends to chat.
local function CleveRoids_SendChatMessage(msg, ...)
    if msg and string.find(msg, "^#showtooltip") then
        return
    end
    if sendingChatMessage then
        -- Re-entered via a hook cycle; go straight to base to avoid recursion.
        return baseSendChatMessage(msg, unpack(arg))
    end
    sendingChatMessage = true
    local ok, err = pcall(CleveRoids.Hooks.SendChatMessage, msg, unpack(arg))
    sendingChatMessage = false
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- Reassert our filter as the outermost SendChatMessage hook (no-op if already on
-- top). See the OnUpdate caller for why this is needed.
function CleveRoids.EnsureSendChatMessageHook()
    if SendChatMessage ~= CleveRoids_SendChatMessage then
        CleveRoids.Hooks.SendChatMessage = SendChatMessage
        SendChatMessage = CleveRoids_SendChatMessage
    end
end

CleveRoids.EnsureSendChatMessageHook()

CleveRoids.RegisterActionEventHandler = function(fn)
    if type(fn) == "function" then
        table.insert(CleveRoids.actionEventHandlers, fn)
    end
end

CleveRoids.RegisterMouseOverResolver = function(fn)
    if type(fn) == "function" then
        table.insert(CleveRoids.mouseOverResolvers, fn)
    end
end

CleverMacro = true

SLASH_CLEVEROID1 = "/cleveroid"
SLASH_CLEVEROID2 = "/cleveroidmacros"
SlashCmdList["CLEVEROID"] = function(msg)
    if type(msg) ~= "string" then
        msg = ""
    end
    local cmd, val, val2
    local s, e, a, b, c = string.find(msg, "^(%S*)%s*(%S*)%s*(.*)$")
    if a then cmd = a else cmd = "" end
    if b then val = b else val = "" end
    if c then val2 = c else val2 = "" end

    -- No command: show current value and available commands
    if cmd == "" then
        CleveRoids.Print("Current Settings:")
        DEFAULT_CHAT_FRAME:AddMessage("realtime (force fast updates, CPU intensive) = " .. CleveRoidMacros.realtime .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage("refresh (updates per second) = " .. CleveRoidMacros.refresh .. " (Default: 5)")
        DEFAULT_CHAT_FRAME:AddMessage("macrocheck (syntax checker) = " .. CleveRoidMacros.macrocheck .. " (Default: 1)")
        DEFAULT_CHAT_FRAME:AddMessage("debug (show learning messages) = " .. (CleveRoids.debug and "1" or "0") .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        CleveRoids.Print("Available Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid realtime 0 or 1 - Force realtime updates")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid refresh X - Set refresh rate (1-10 updates/sec)")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid macrocheck 0 or 1 - Enable/disable macro syntax checker")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid debug [0|1] - Toggle learning debug messages")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Spell Schools:|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Immunity Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listimmune [school] - List immunity data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addimmune "<NPC>" <school> [buff] - Add immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeimmune "<NPC>" <school> - Remove immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearimmune [school] - Clear immunity data')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00CC Immunity Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listccimmune [type] - List CC immunity data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addccimmune "<NPC>" <type> [buff] - Add CC immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeccimmune "<NPC>" <type> - Remove CC immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearccimmune [type] - Clear CC immunity data')
        DEFAULT_CHAT_FRAME:AddMessage("  CC types: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Talents:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid talenttabs - Show talent tab IDs for your class')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listtab <tab> - List all talents in a tab with their IDs')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid talents - Show current talent ranks')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Debuff Tracking Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid debuffdebug [spell] - Debug debuff tracking on target')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00pfUI Tank Integration:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid tankdebug - Debug tank targeting conditionals')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00All-Caster Aura Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid auradebug - Debug buff/debuff time tracking from all casters')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Overflow Buff Frame:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid overflowframe [on|off] - Enable/disable player overflow buff frame (default: off)')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid overflowtest - Toggle overflow buff frame test mode')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid overflowreset - Reset overflow frame positions to defaults')
        return
    end

    -- realtime
    if cmd == "realtime" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoidMacros.realtime = num
            -- The unit streams are only worth receiving in event-driven mode.
            CleveRoids.ApplyUnitStreamEvents()
            CleveRoids.Print("realtime set to " .. num)
        else
            CleveRoids.Print("Usage: /cleveroid realtime 0 or 1 - Force realtime updates rather than event based updates (Default: 0. 1 = on, increases CPU load.)")
            CleveRoids.Print("Current realtime = " .. tostring(CleveRoidMacros.realtime))
        end
        return
    end

    -- refresh
    if cmd == "refresh" then
        local num = tonumber(val)
        if num and num >= 1 and num <= 10 then
            CleveRoidMacros.refresh = num
            CleveRoids.cachedRefreshRate = nil  -- Invalidate cached rate
            CleveRoids.Print("refresh set to " .. num .. " times per second")
        else
            CleveRoids.Print("Usage: /cleveroid refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)")
            CleveRoids.Print("Current refresh = " .. tostring(CleveRoidMacros.refresh) .. " times per second")
        end
        return
    end

    -- macrocheck
    if cmd == "macrocheck" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoidMacros.macrocheck = num
            if num == 1 then
                CleveRoids.Print("Macro syntax checker |cff00ff00enabled|r")
            else
                CleveRoids.Print("Macro syntax checker |cffff0000disabled|r (reload UI to take effect)")
            end
        else
            CleveRoids.Print("Usage: /cleveroid macrocheck 0 or 1 - Enable/disable macro syntax checker (Default: 1)")
            CleveRoids.Print("Current macrocheck = " .. tostring(CleveRoidMacros.macrocheck))
        end
        return
    end

    -- debug (toggle learning messages)
    if cmd == "debug" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoids.debug = (num == 1)
            CleveRoids.Print("debug set to " .. num)
        else
            CleveRoids.debug = not CleveRoids.debug
            CleveRoids.Print("debug " .. (CleveRoids.debug and "enabled" or "disabled"))
        end
        -- Clear keyed debug state so messages re-fire when debug is re-enabled
        CleveRoids._lastDebugState = {}
        return
    end

    -- listimmune (list immunity data)
    if cmd == "listimmune" or cmd == "immunelist" then
        CleveRoids.ListImmunities(val ~= "" and val or nil)
        return
    end

    -- clearimmune (clear immunity data)
    if cmd == "clearimmune" then
        CleveRoids.ClearImmunities(val ~= "" and val or nil)
        return
    end

    -- addimmune (manually add immunity)
    if cmd == "addimmune" then
        -- Parse: /cleveroid addimmune <NPC Name> <school> [buff]
        -- Example: /cleveroid addimmune "Golemagg the Incinerator" fire
        -- Example: /cleveroid addimmune Vaelastrasz fire "Burning Adrenaline"
        local npcName, school, buffName = nil, nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, rest = string.find(msg, '^addimmune%s+"([^"]+)"%s*(.*)$')
        if quotedNpc then
            npcName = quotedNpc
            -- Parse school and optional buff from rest
            local _, _, sch, buff = string.find(rest, "^(%S+)%s*(.*)$")
            school = sch
            if buff and buff ~= "" then
                -- Check if buff is quoted
                local _, _, quotedBuff = string.find(buff, '^"([^"]+)"$')
                buffName = quotedBuff or buff
            end
        else
            -- No quoted NPC, use simple parsing
            npcName = val
            school = val2
        end

        CleveRoids.AddImmunity(npcName, school, buffName)
        return
    end

    -- removeimmune (manually remove immunity)
    if cmd == "removeimmune" then
        -- Parse: /cleveroid removeimmune <NPC Name> <school>
        local npcName, school = nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, sch = string.find(msg, '^removeimmune%s+"([^"]+)"%s*(%S*)$')
        if quotedNpc then
            npcName = quotedNpc
            school = sch
        else
            npcName = val
            school = val2
        end

        CleveRoids.RemoveImmunity(npcName, school)
        return
    end

    -- ========== CC IMMUNITY COMMANDS ==========

    -- listccimmune (list CC immunity data)
    if cmd == "listccimmune" or cmd == "ccimmunelist" then
        CleveRoids.ListCCImmunities(val ~= "" and val or nil)
        return
    end

    -- clearccimmune (clear CC immunity data)
    if cmd == "clearccimmune" then
        CleveRoids.ClearCCImmunities(val ~= "" and val or nil)
        return
    end

    -- addccimmune (manually add CC immunity)
    if cmd == "addccimmune" then
        -- Parse: /cleveroid addccimmune <NPC Name> <cctype> [buff]
        -- Example: /cleveroid addccimmune "Stone Guardian" stun
        -- Example: /cleveroid addccimmune "Boss Name" fear "Enrage"
        local npcName, ccType, buffName = nil, nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, rest = string.find(msg, '^addccimmune%s+"([^"]+)"%s*(.*)$')
        if quotedNpc then
            npcName = quotedNpc
            -- Parse ccType and optional buff from rest
            local _, _, cct, buff = string.find(rest, "^(%S+)%s*(.*)$")
            ccType = cct
            if buff and buff ~= "" then
                -- Check if buff is quoted
                local _, _, quotedBuff = string.find(buff, '^"([^"]+)"$')
                buffName = quotedBuff or buff
            end
        else
            -- No quoted NPC, use simple parsing
            npcName = val
            ccType = val2
        end

        CleveRoids.AddCCImmunity(npcName, ccType, buffName)
        return
    end

    -- removeccimmune (manually remove CC immunity)
    if cmd == "removeccimmune" then
        -- Parse: /cleveroid removeccimmune <NPC Name> <cctype>
        local npcName, ccType = nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, cct = string.find(msg, '^removeccimmune%s+"([^"]+)"%s*(%S*)$')
        if quotedNpc then
            npcName = quotedNpc
            ccType = cct
        else
            npcName = val
            ccType = val2
        end

        CleveRoids.RemoveCCImmunityCommand(npcName, ccType)
        return
    end

    -- talenttabs (show talent tab IDs)
    if cmd == "talenttabs" or cmd == "tabs" then
        CleveRoids.Print("=== Talent Tabs ===")
        for i = 1, GetNumTalentTabs() do
            local name, _, pointsSpent = GetTalentTabInfo(i)
            CleveRoids.Print("Tab " .. i .. ": " .. name .. " (" .. pointsSpent .. " points)")
        end
        return
    end

    -- listtab (show all talents in a specific tab with their IDs)
    if cmd == "listtab" or cmd == "tab" then
        local tabNum = tonumber(val)
        if not tabNum or tabNum < 1 or tabNum > GetNumTalentTabs() then
            CleveRoids.Print("Usage: /cleveroid listtab <tab number>")
            CleveRoids.Print("Example: /cleveroid listtab 2")
            CleveRoids.Print("Use /cleveroid talenttabs to see your tab numbers")
            return
        end

        local tabName = GetTalentTabInfo(tabNum)
        CleveRoids.Print("=== " .. tabName .. " (Tab " .. tabNum .. ") ===")

        local numTalents = GetNumTalents(tabNum)
        for i = 1, numTalents do
            local name, _, _, _, rank, maxRank = GetTalentInfo(tabNum, i)
            if name then
                local rankText = rank .. "/" .. maxRank
                CleveRoids.Print("ID " .. i .. ": " .. name .. " [" .. rankText .. "]")
            end
        end
        return
    end

    -- talents (show current talent ranks)
    if cmd == "talents" or cmd == "talent" then
        CleveRoids.Print("=== Current Talents ===")

        -- Ensure talents are indexed
        if not CleveRoids.Talents or table.getn(CleveRoids.Talents) == 0 then
            if CleveRoids.IndexTalents then
                CleveRoids.IndexTalents()
            end
        end

        local count = 0
        for name, rank in pairs(CleveRoids.Talents) do
            if type(name) == "string" and tonumber(rank) and tonumber(rank) > 0 then
                CleveRoids.Print(name .. ": Rank " .. rank)
                count = count + 1
            end
        end

        if count == 0 then
            CleveRoids.Print("No talents learned yet!")
        else
            CleveRoids.Print("Total: " .. count .. " talents")
        end
        return
    end

    -- debuffdebug (debug debuff tracking on target)
    if cmd == "debuffdebug" or cmd == "debuff" or cmd == "trackdebug" then
        local searchName = val
        if val2 and val2 ~= "" then
            searchName = val .. " " .. val2
        end
        -- Strip underscores and quotes
        if searchName and searchName ~= "" then
            searchName = string.gsub(searchName, "_", " ")
            searchName = string.gsub(searchName, '"', "")
        end

        CleveRoids.Print("|cff88ff88=== Debuff Tracking Debug ===|r")

        local guid = CleveRoids.GetGUID("target")
        if not guid then
            CleveRoids.Print("|cffff0000No target selected!|r")
            return
        end

        local targetName = UnitName("target") or "Unknown"
        CleveRoids.Print("Target: " .. targetName .. " (GUID: " .. tostring(guid) .. ")")

        -- The target's debuffs as the conditionals see them (C_UnitAuras)
        CleveRoids.Print(" ")
        CleveRoids.Print("|cff00ff00=== Debuffs (C_UnitAuras) ===|r")
        local i = 1
        while true do
            local name, _, count, _, _, expirationTime, source, _, _, spellId =
                C_UnitAuras.UnitAura("target", i, "HARMFUL")
            if not name then break end
            local timeStr = (expirationTime and expirationTime > 0)
                and string.format("%.1fs left", expirationTime - GetTime()) or "no timer"
            CleveRoids.Print(string.format("  [%d] %s: %s (stacks: %d, caster: %s)",
                spellId or 0, name, timeStr, count or 0, tostring(source)))
            i = i + 1
        end
        if i == 1 then
            CleveRoids.Print("  (no debuffs)")
        end

        -- If a specific debuff name was provided, test the conditional
        if searchName and searchName ~= "" then
            CleveRoids.Print(" ")
            CleveRoids.Print("|cff00ff00=== Testing [debuff:\"" .. searchName .. "\"] ===|r")

            local result = CleveRoids.ValidateUnitDebuff("target", { name = searchName })
            CleveRoids.Print("ValidateUnitDebuff(target, {name='" .. searchName .. "'}): " ..
                (result and "|cff00ff00true|r" or "|cffff0000false|r"))

            local resultTime = CleveRoids.ValidateUnitDebuff("target", { name = searchName, operator = "<", amount = 99999 })
            CleveRoids.Print("ValidateUnitDebuff(target, {name='" .. searchName .. "', operator='<', amount=99999}): " ..
                (resultTime and "|cff00ff00true|r" or "|cffff0000false|r"))
        end

        return
    end

    -- tankdebug (debug pfUI tank integration)
    if cmd == "tankdebug" then
        CleveRoids.Print("=== Tank Debug ===")

        -- Check pfUI availability
        if not CleveRoids.HasPfUITanks() then
            CleveRoids.Print("|cffff0000pfUI tank system not available!|r")
            CleveRoids.Print("  pfUI loaded: " .. tostring(type(pfUI) == "table"))
            CleveRoids.Print("  pfUI_config: " .. tostring(type(pfUI_config) == "table"))
            return
        end

        CleveRoids.Print("|cff00ff00pfUI tank system available|r")

        -- List raid frame tanks
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Raid Frame Tanks (right-click toggle):|r")
        local raidTankCount = 0
        if type(pfUI) == "table" and type(pfUI.uf) == "table" and
           type(pfUI.uf.raid) == "table" and type(pfUI.uf.raid.tankrole) == "table" then
            for name, isTank in pairs(pfUI.uf.raid.tankrole) do
                if isTank then
                    CleveRoids.Print("  - " .. name)
                    raidTankCount = raidTankCount + 1
                end
            end
        end
        if raidTankCount == 0 then
            CleveRoids.Print("  (none)")
        end

        -- List nameplate off-tank names
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Nameplate Off-Tank Names (config setting):|r")
        local npTankCount = 0
        if type(pfUI_config) == "table" and type(pfUI_config.nameplates) == "table" then
            local list = pfUI_config.nameplates.combatofftanks or ""
            if list ~= "" then
                CleveRoids.Print("  Raw setting: \"" .. list .. "\"")
                -- pfUI uses # as separator
                for name in string.gfind(list, "[^#]+") do
                    name = string.gsub(name, "^%s*(.-)%s*$", "%1") -- trim
                    if name ~= "" then
                        CleveRoids.Print("  - " .. name .. " (lowercase: " .. string.lower(name) .. ")")
                        npTankCount = npTankCount + 1
                    end
                end
            end
        end
        if npTankCount == 0 then
            CleveRoids.Print("  (none)")
        end

        -- Check current target
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Current Target Check:|r")
        if not UnitExists("target") then
            CleveRoids.Print("  No target selected")
        else
            local targetName = UnitName("target") or "Unknown"
            CleveRoids.Print("  Your target: " .. targetName)

            if UnitExists("targettarget") then
                local ttName = UnitName("targettarget") or "Unknown"
                CleveRoids.Print("  Target's target: " .. ttName)
                local isTank = CleveRoids.IsPlayerTank(ttName)
                if isTank then
                    CleveRoids.Print("  |cff00ff00" .. ttName .. " IS marked as tank|r")
                else
                    CleveRoids.Print("  |cffff8800" .. ttName .. " is NOT marked as tank|r")
                    CleveRoids.Print("  (lowercase check: " .. string.lower(ttName) .. ")")
                end
            else
                CleveRoids.Print("  Target's target: (none)")
            end

            -- Test the conditional functions
            CleveRoids.Print(" ")
            CleveRoids.Print("|cffffaa00Conditional Results:|r")
            local isTargetingTank = CleveRoids.IsTargetingAnyTank("target")
            CleveRoids.Print("  IsTargetingAnyTank('target'): " .. tostring(isTargetingTank))
            CleveRoids.Print("  [targeting:tank] would be: " .. tostring(isTargetingTank))
            CleveRoids.Print("  [notargeting:tank] would be: " .. tostring(not isTargetingTank))
        end

        return
    end

    -- auradebug (debug all-caster aura tracking)
    if cmd == "auradebug" or cmd == "bufftracking" then
        CleveRoids.Print("=== All-Caster Aura Tracking Debug ===")

        -- Check CVar status
        local auraCastEnabled = GetCVar("NP_EnableAuraCastEvents")
        if auraCastEnabled == "1" then
            CleveRoids.Print("|cff00ff00NP_EnableAuraCastEvents = 1 (ENABLED)|r")
        else
            CleveRoids.Print("|cffff0000NP_EnableAuraCastEvents = " .. tostring(auraCastEnabled) .. " (DISABLED)|r")
            CleveRoids.Print("  Enable with: |cff00ffff/run SetCVar(\"NP_EnableAuraCastEvents\", \"1\")|r")
            CleveRoids.Print("  Then /reload")
        end

        -- Check Nampower version
        local API = CleveRoids.NampowerAPI
        if API and API.features then
            CleveRoids.Print("Nampower hasAuraCastEvents: " .. tostring(API.features.hasAuraCastEvents))
        else
            CleveRoids.Print("|cffff0000Nampower API not available|r")
        end

        -- Show tracking data for current target/mouseover
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Tracked Auras:|r")
        local trackingCount = 0
        local now = GetTime()
        local backingTable = CleveRoids.AllCasterAuraTracking or {}
        for targetGuid, spellNames in pairs(backingTable) do
            local unitName = nil
            -- Try to find unit name for this GUID (use pcall to handle invalid units like "focus")
            for _, testUnit in ipairs({"target", "mouseover", "party1", "party2", "party3", "party4"}) do
                local ok, exists, testGuid = pcall(function() return UnitExists(testUnit) end)
                if ok and exists then
                    _, testGuid = UnitExists(testUnit)
                    if testGuid == targetGuid then
                        unitName = UnitName(testUnit)
                        break
                    end
                end
            end

            for spellName, casters in pairs(spellNames) do
                for casterGuid, auraData in pairs(casters) do
                    local startTime = isPfUI and auraData.startTime or auraData.start
                    if startTime and auraData.duration then
                        local remaining = auraData.duration + startTime - now
                        if remaining > 0 then
                            local display = unitName or (string.sub(targetGuid, 1, 16) .. "...")
                            CleveRoids.Print(string.format("  %s on %s: %.1fs left (caster: %s)",
                                spellName, display, remaining, string.sub(tostring(casterGuid), 1, 16)))
                            trackingCount = trackingCount + 1
                        end
                    end
                end
            end
        end
        if trackingCount == 0 then
            CleveRoids.Print("  (no auras currently tracked)")
        end

        -- Check specific target
        if UnitExists("target") then
            CleveRoids.Print(" ")
            CleveRoids.Print("|cffffaa00Target Buff Check:|r")
            local targetGuid = CleveRoids.GetGUID("target")
            CleveRoids.Print("  Target GUID: " .. tostring(targetGuid))
            local targetData = CleveRoids.GetAuraTrackingData(targetGuid)
            if targetData then
                local count = 0
                for _, casters in pairs(targetData) do
                    for _ in pairs(casters) do count = count + 1 end
                end
                CleveRoids.Print("  Tracked aura entries on target: " .. count)
            else
                CleveRoids.Print("  |cffff9900No tracking data for this target|r")
            end
        end

        return
    end

    -- overflowframe (enable/disable player overflow buff frame)
    if cmd == "overflowframe" then
        CleveRoidMacros = CleveRoidMacros or {}
        if val == "on" or val == "1" then
            CleveRoidMacros.overflowPlayerEnabled = true
            CleveRoids.Print("Player overflow buff frame |cff00ff00enabled|r")
        elseif val == "off" or val == "0" then
            CleveRoidMacros.overflowPlayerEnabled = false
            CleveRoids.Print("Player overflow buff frame |cffff0000disabled|r")
        else
            CleveRoidMacros.overflowPlayerEnabled = not CleveRoidMacros.overflowPlayerEnabled
            if CleveRoidMacros.overflowPlayerEnabled then
                CleveRoids.Print("Player overflow buff frame |cff00ff00enabled|r")
            else
                CleveRoids.Print("Player overflow buff frame |cffff0000disabled|r")
            end
        end
        if CleveRoids.RebuildOverflowFrame then
            CleveRoids.RebuildOverflowFrame()
        end
        return
    end

    -- overflowtest (toggle overflow buff frame test mode)
    if cmd == "overflowtest" then
        if CleveRoids.ToggleOverflowTest then
            CleveRoids.ToggleOverflowTest()
        else
            CleveRoids.Print("|cffff0000OverflowBuffFrame extension not loaded|r")
        end
        return
    end

    -- overflowreset (reset frame positions to defaults)
    if cmd == "overflowreset" then
        if CleveRoids.ResetOverflowFramePositions then
            CleveRoids.ResetOverflowFramePositions()
        else
            CleveRoids.Print("|cffff0000OverflowBuffFrame extension not loaded|r")
        end
        return
    end

    -- Delegate to extension console handlers (chain pattern)
    if CleveRoids.HandleConsoleCommand then
        CleveRoids.HandleConsoleCommand(msg)
        return
    end

    -- Unknown command fallback
    CleveRoids.Print("Usage:")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid - Show current settings")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid realtime 0 or 1 - Force realtime updates (Default: 0. 1 = on, increases CPU load)")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid refresh X - Set refresh rate (1 to 10 updates per second. Default: 5)")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid debug [0|1] - Toggle learning debug messages")
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Immunity Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listimmune [school] - List immunity data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addimmune "<NPC>" <school> [buff] - Add immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeimmune "<NPC>" <school> - Remove immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearimmune [school] - Clear immunity data')
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00CC Immunity Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listccimmune [type] - List CC immunity data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addccimmune "<NPC>" <type> [buff] - Add CC immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeccimmune "<NPC>" <type> - Remove CC immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearccimmune [type] - Clear CC immunity data')
end

SLASH_CLEAREQUIPQUEUE1 = "/clearequipqueue"
SlashCmdList.CLEAREQUIPQUEUE = function()
    -- Release all entries back to pool
    for i = 1, CleveRoids.equipmentQueueLen do
        local entry = CleveRoids.equipmentQueue[i]
        if entry then
            CleveRoids.equipmentQueue[i] = nil
            -- Return to pool if space available
            if table.getn(CleveRoids.queueEntryPool) < 10 then
                entry.item = nil
                entry.slotName = nil
                entry.inventoryId = nil
                table.insert(CleveRoids.queueEntryPool, entry)
            end
        end
    end
    CleveRoids.equipmentQueueLen = 0
    if CleveRoids.equipQueueFrame then
        CleveRoids.equipQueueFrame:Hide()
    end
    CleveRoids.Print("Equipment queue cleared")
end

SLASH_EQUIPQUEUESTATUS1 = "/equipqueuestatus"
SlashCmdList.EQUIPQUEUESTATUS = function()
    local count = CleveRoids.equipmentQueueLen
    CleveRoids.Print("Equipment queue has " .. count .. " pending items")

    for i = 1, count do
        local entry = CleveRoids.equipmentQueue[i]
        if entry then
            local itemName = (entry.item and entry.item.name) or "Unknown"
            local slotName = entry.slotName or "Unknown"
            local retries = entry.retries or 0
            CleveRoids.Print(i .. ". " .. itemName .. " -> " .. slotName .. " (retries: " .. retries .. ")")
        end
    end
end

local TOOL_NAMES = {
    ["blacksmith hammer"] = true,
    ["mining pick"] = true,
    ["skinning knife"] = true,
    ["arclight spanner"] = true,
    ["gyromatic micro-adjustor"] = true,
    ["bladed pickaxe"] = true,
    ["flint and tinder"] = true,
    ["strong fishing pole"] = true,
    ["big iron fishing pole"] = true,
    ["fishing pole"] = true,
}

local function GetItemEquipData(link)
    if not link then return nil end
    local _, _, idStr = string.find(link, "item:(%d+)")
    if not idStr then return nil end
    local itemId = tonumber(idStr)
    if not itemId then return nil end

    -- GetItemInfo: 1=name, 2=link, 3=quality, 4=reqLevel, 5=itemType, 6=subType, 7=stack, 8=equipLoc
    local name, _, quality, reqLevel, _, _, _, equipLoc = GetItemInfo(itemId)
    if name and TOOL_NAMES[string.lower(name)] then return nil end

    -- Ignore items requiring a higher level than the player
    local playerLevel = UnitLevel("player") or 1
    local lvl = tonumber(reqLevel) or 0
    if lvl > playerLevel then return nil end

    if CleveRoids.NampowerAPI and CleveRoids.NampowerAPI.GetItemInventoryType then
        local invType = CleveRoids.NampowerAPI.GetItemInventoryType(itemId)
        if invType == 14 then equipLoc = "INVTYPE_SHIELD"
        elseif invType == 13 or invType == 21 then equipLoc = "INVTYPE_WEAPON"
        elseif invType == 17 then equipLoc = "INVTYPE_2HWEAPON"
        end
    end

    if not equipLoc then return nil end
    local q = tonumber(quality) or 0
    local lvl = tonumber(reqLevel) or 0
    local score = (q * 1000) + (lvl * 10)
    return equipLoc, score, name
end

local function CleveRoids_DoEquipShield()
    -- 1. Find the BEST 1H Weapon in bags (replaces 2H so Shield can be equipped)
    local link16 = GetInventoryItemLink("player", 16)
    local loc16 = GetItemEquipData(link16)
    local has1H = (loc16 == "INVTYPE_WEAPON" or loc16 == "INVTYPE_WEAPONMAINHAND")
    if not has1H then
        local bestBag, bestSlot, bestScore = nil, nil, -1
        for b = 0, 4 do
            for s = 1, GetContainerNumSlots(b) do
                local link = GetContainerItemLink(b, s)
                if link then
                    local loc, score = GetItemEquipData(link)
                    if (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND") and score > bestScore then
                        bestScore = score
                        bestBag = b
                        bestSlot = s
                    end
                end
            end
        end
        if bestBag and bestSlot then
            ClearCursor()
            PickupContainerItem(bestBag, bestSlot)
            if CursorHasItem() then
                PickupInventoryItem(16)
                if CursorHasItem() then PickupContainerItem(bestBag, bestSlot) end
            end
            ClearCursor()
        end
    end

    -- If still holding a 2H weapon (e.g. no 1H weapon was in bags), unequip 2H so Shield can be worn
    local cur16 = GetInventoryItemLink("player", 16)
    if cur16 and GetItemEquipData(cur16) == "INVTYPE_2HWEAPON" then
        for b = 0, 4 do
            for s = 1, GetContainerNumSlots(b) do
                if not GetContainerItemLink(b, s) then
                    ClearCursor()
                    PickupInventoryItem(16)
                    if CursorHasItem() then PickupContainerItem(b, s) end
                    ClearCursor()
                    break
                end
            end
            if not CursorHasItem() and not GetInventoryItemLink("player", 16) then break end
        end
    end

    -- 2. Find the BEST Shield in bags (highest quality / level)
    local link17 = GetInventoryItemLink("player", 17)
    local loc17 = GetItemEquipData(link17)
    local hasShield = (loc17 == "INVTYPE_SHIELD")
    if not hasShield then
        local bestBag, bestSlot, bestScore = nil, nil, -1
        for b = 0, 4 do
            for s = 1, GetContainerNumSlots(b) do
                local link = GetContainerItemLink(b, s)
                if link then
                    local loc, score = GetItemEquipData(link)
                    if loc == "INVTYPE_SHIELD" and score > bestScore then
                        bestScore = score
                        bestBag = b
                        bestSlot = s
                    end
                end
            end
        end
        if bestBag and bestSlot then
            ClearCursor()
            PickupContainerItem(bestBag, bestSlot)
            if CursorHasItem() then
                PickupInventoryItem(17)
                if CursorHasItem() then PickupContainerItem(bestBag, bestSlot) end
            end
            ClearCursor()
        end
    end
end

SLASH_EQUIPSHIELD1 = "/equipshield"
SLASH_EQUIPSHIELD2 = "/equipdef"
SlashCmdList.EQUIPSHIELD = function(msg)
    if msg and msg ~= "" and string.gsub(msg, "%s+", "") ~= "" then
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], CleveRoids_DoEquipShield, CleveRoids.FixEmptyTarget, false, CleveRoids_DoEquipShield) then
                return
            end
        end
    else
        CleveRoids_DoEquipShield()
    end
end

local function CleveRoids_DoEquip2H()
    -- 1. Find the best 2H weapon in bags
    local bestBag, bestSlot, bestScore = nil, nil, -1
    for b = 0, 4 do
        for s = 1, GetContainerNumSlots(b) do
            local link = GetContainerItemLink(b, s)
            if link then
                local loc, score = GetItemEquipData(link)
                if loc == "INVTYPE_2HWEAPON" and score > bestScore then
                    bestScore = score
                    bestBag = b
                    bestSlot = s
                end
            end
        end
    end

    local link16 = GetInventoryItemLink("player", 16)
    local loc16, curScore16 = GetItemEquipData(link16)
    local has2H = (loc16 == "INVTYPE_2HWEAPON")
    local link17 = GetInventoryItemLink("player", 17)

    -- If already holding the best 2H weapon and off-hand is empty, nothing to do
    if has2H and not link17 and (bestScore <= (curScore16 or 0)) then
        return
    end

    -- 2. If off-hand (slot 17) holds a shield or item, it MUST be removed to bags first!
    -- In WoW 1.12.1, holding anything in off-hand blocks equipping a two-handed weapon.
    if link17 then
        for b = 0, 4 do
            for s = 1, GetContainerNumSlots(b) do
                if not GetContainerItemLink(b, s) then
                    ClearCursor()
                    PickupInventoryItem(17)
                    if CursorHasItem() then PickupContainerItem(b, s) end
                    ClearCursor()
                    break
                end
            end
            if not CursorHasItem() and not GetInventoryItemLink("player", 17) then break end
        end
    end

    -- 3. Equip the best 2H weapon from bag into main-hand slot 16
    if bestBag and bestSlot then
        ClearCursor()
        PickupContainerItem(bestBag, bestSlot)
        if CursorHasItem() then
            PickupInventoryItem(16)
            if CursorHasItem() then PickupContainerItem(bestBag, bestSlot) end
        end
        ClearCursor()
    end
end

SLASH_EQUIP2H1 = "/equip2h"
SLASH_EQUIP2H2 = "/equip2"
SlashCmdList.EQUIP2H = function(msg)
    if msg and msg ~= "" and string.gsub(msg, "%s+", "") ~= "" then
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], CleveRoids_DoEquip2H, CleveRoids.FixEmptyTarget, false, CleveRoids_DoEquip2H) then
                return
            end
        end
    else
        CleveRoids_DoEquip2H()
    end
end

-- ============================================================================
-- Warrior Combat HUD: Rage Bar + 2H Slam Swing Timer + Latency + Auto Delay
-- Includes Minimap Button and Settings Menu with Size & Audio controls!
-- ============================================================================
local function InitWarriorCombatHUD()
    local _, englishClass = UnitClass("player")
    if englishClass ~= "WARRIOR" then return end

    if _G["CleveRoidWarriorHUD"] then return end

    -- HUD Container Frame (holds all bars together)
    local hud = CreateFrame("Frame", "CleveRoidWarriorHUD", UIParent)
    hud:SetWidth(190)
    hud:SetHeight(24)
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)

    -- Restore saved position and scale
    local curScale = (CleveRoidMacros and CleveRoidMacros.WarriorHUDScale) or 1.0
    hud:SetScale(curScale)

    local savedPos = CleveRoidMacros and CleveRoidMacros.WarriorHUDPos
    if savedPos and savedPos.point then
        hud:SetPoint(savedPos.point, UIParent, savedPos.relPoint, savedPos.x, savedPos.y)
    else
        hud:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
    end

    local isUnlocked = false

    -- Shift + Left Click Drag (or whenever Unlocked)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function()
        if IsShiftKeyDown() or isUnlocked then
            this:StartMoving()
            this.isMoving = true
        end
    end)
    hud:SetScript("OnDragStop", function()
        if this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            local point, _, relPoint, x, y = this:GetPoint()
            if CleveRoidMacros then
                CleveRoidMacros.WarriorHUDPos = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end
    end)

    hud:EnableMouseWheel(true)
    hud:SetScript("OnMouseWheel", function()
        if IsControlKeyDown() or isUnlocked then
            local delta = arg1
            curScale = curScale + (delta * 0.05)
            if curScale < 0.6 then curScale = 0.6 end
            if curScale > 2.0 then curScale = 2.0 end
            hud:SetScale(curScale)
            if CleveRoidMacros then CleveRoidMacros.WarriorHUDScale = curScale end
            if UpdateScaleDisplay then UpdateScaleDisplay() end
        end
    end)

    -- ------------------------------------------------------------------------
    -- Aura / Debuff Scanning Helpers (ClassicAPI C_UnitAuras + 1.12 Fallbacks)
    -- ------------------------------------------------------------------------
    local function ScanAura(unit, searchName, filter)
        if not UnitExists(unit) then return nil end
        local searchLower = string.lower(searchName)

        -- 1. Check ClassicAPI C_UnitAuras
        if C_UnitAuras and C_UnitAuras.UnitAura then
            for i = 1, 32 do
                local name, rank, count, debuffType, duration, expirationTime, source, _, _, spellId =
                    C_UnitAuras.UnitAura(unit, i, filter)
                if not name then break end
                if string.find(string.lower(name), searchLower) then
                    local rem = 0
                    if expirationTime and expirationTime > 0 then
                        rem = expirationTime - GetTime()
                        if rem < 0 then rem = 0 end
                    end
                    if (not duration or duration <= 0 or rem <= 0) and filter == "HARMFUL" then
                        local lib = (ShaguTweaks and ShaguTweaks.libdebuff) or (pfUI and pfUI.api and pfUI.api.libdebuff)
                        if lib and lib.UnitDebuff then
                            local eff, rk, tex, stk, dt, d, tl = lib:UnitDebuff(unit, i)
                            if d and d > 0 and tl and tl > 0 then
                                duration = d
                                rem = tl
                            end
                        end
                    end
                    return name, count or 1, duration or 0, rem, nil
                end
            end
        end

        -- 2. Check ShaguTweaks / pfUI libdebuff directly for enemy debuffs
        local lib = (ShaguTweaks and ShaguTweaks.libdebuff) or (pfUI and pfUI.api and pfUI.api.libdebuff)
        if lib and lib.UnitDebuff and filter == "HARMFUL" then
            for i = 1, 16 do
                local effect, rank, texture, stacks, dtype, duration, timeleft = lib:UnitDebuff(unit, i)
                if not texture then break end
                if effect and string.find(string.lower(effect), searchLower) then
                    local rem = (timeleft and timeleft > 0) and timeleft or 0
                    return effect, stacks or 1, duration or 0, rem, texture
                end
            end
        end

        -- 3. Fallback to standard 1.12 UnitDebuff / UnitBuff
        local maxSlots = (filter == "HARMFUL") and 16 or 32
        for i = 1, maxSlots do
            local tex, apps
            if filter == "HARMFUL" then
                tex, apps = UnitDebuff(unit, i)
            else
                tex, apps = UnitBuff(unit, i)
            end
            if not tex then break end
            if string.find(string.lower(tex), searchLower) then
                return searchName, apps or 1, 0, 0, tex
            end
        end
        return nil
    end

    -- ------------------------------------------------------------------------
    -- Alignment Grid ("Fence" / Graph Paper Overlay)
    -- Subtle pixel grid across the screen to align icons and bars with precision
    -- ------------------------------------------------------------------------
    local gridOverlay = CreateFrame("Frame", "CleveRoidAlignGrid", UIParent)
    gridOverlay:SetAllPoints(UIParent)
    gridOverlay:SetFrameStrata("BACKGROUND")
    gridOverlay:Hide()

    local showGrid = true
    local gridStep = 32

    -- Center crosshairs (Red, 2px wide)
    local vCenter = gridOverlay:CreateTexture(nil, "BACKGROUND")
    vCenter:SetWidth(2)
    vCenter:SetHeight(2000)
    vCenter:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    vCenter:SetTexture(1, 0.25, 0.2, 0.8)

    local hCenter = gridOverlay:CreateTexture(nil, "BACKGROUND")
    hCenter:SetHeight(2)
    hCenter:SetWidth(2500)
    hCenter:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    hCenter:SetTexture(1, 0.25, 0.2, 0.8)

    -- Grid lines extending outward from center in 32px increments
    for x = -512, 512, gridStep do
        if x ~= 0 then
            local vLine = gridOverlay:CreateTexture(nil, "BACKGROUND")
            vLine:SetWidth(1)
            vLine:SetHeight(2000)
            vLine:SetPoint("CENTER", UIParent, "CENTER", x, 0)
            vLine:SetTexture(0.2, 0.6, 1.0, 0.22)
        end
    end

    for y = -384, 384, gridStep do
        if y ~= 0 then
            local hLine = gridOverlay:CreateTexture(nil, "BACKGROUND")
            hLine:SetHeight(1)
            hLine:SetWidth(2500)
            hLine:SetPoint("CENTER", UIParent, "CENTER", 0, y)
            hLine:SetTexture(0.2, 0.6, 1.0, 0.22)
        end
    end

    local function UpdateGridVisibility()
        if isUnlocked and showGrid then
            gridOverlay:Show()
        else
            gridOverlay:Hide()
        end
    end

    -- ------------------------------------------------------------------------
    -- Movable & Resizable Element Setup Helper
    -- Supports: Shift+Drag to move, MouseWheel to resize, Right-Click to reset!
    -- ------------------------------------------------------------------------
    local function MakeElementMovable(frame, key, defX, defY, defW, defH, isSquare)
        frame.isSquare = (isSquare == true or defW == defH)
        frame.defaultWidth = defW or 26
        frame.defaultHeight = defH or 26

        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)

        local saved = CleveRoidMacros and CleveRoidMacros.WarriorIconPositions and CleveRoidMacros.WarriorIconPositions[key]
        local w = (saved and saved.width) or defW or 26
        local h = (saved and saved.height) or defH or 26

        -- Sanitize any distorted aspect ratios from previous resizing bug:
        if frame.isSquare and (w ~= h or w > 72 or h > 72) then
            w = defW or 26
            h = defH or 26
            if saved then
                saved.width = w
                saved.height = h
            end
        end

        frame:SetWidth(w)
        frame:SetHeight(h)

        if saved and saved.point then
            frame:ClearAllPoints()
            frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
        else
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", defX, defY)
        end

        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function()
            if IsShiftKeyDown() or isUnlocked then
                this:StartMoving()
                this.isMoving = true
            end
        end)
        frame:SetScript("OnDragStop", function()
            if this.isMoving then
                this:StopMovingOrSizing()
                this.isMoving = false
                local pt, _, relPt, x, y = this:GetPoint()
                if CleveRoidMacros then
                    if not CleveRoidMacros.WarriorIconPositions then CleveRoidMacros.WarriorIconPositions = {} end
                    if not CleveRoidMacros.WarriorIconPositions[key] then CleveRoidMacros.WarriorIconPositions[key] = {} end
                    CleveRoidMacros.WarriorIconPositions[key].point = pt
                    CleveRoidMacros.WarriorIconPositions[key].relPoint = relPt
                    CleveRoidMacros.WarriorIconPositions[key].x = x
                    CleveRoidMacros.WarriorIconPositions[key].y = y
                end
            end
        end)

        -- Right-click while unlocked resets this single element's size to default!
        frame:SetScript("OnMouseUp", function()
            if arg1 == "RightButton" and isUnlocked then
                local dw = this.defaultWidth or 26
                local dh = this.defaultHeight or 26
                this:SetWidth(dw)
                this:SetHeight(dh)
                if CleveRoidMacros and CleveRoidMacros.WarriorIconPositions and CleveRoidMacros.WarriorIconPositions[key] then
                    CleveRoidMacros.WarriorIconPositions[key].width = dw
                    CleveRoidMacros.WarriorIconPositions[key].height = dh
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r Reset " .. key .. " size to default (" .. dw .. "x" .. dh .. ").")
            end
        end)

        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function()
            if IsControlKeyDown() or isUnlocked then
                local delta = arg1
                if this.isSquare then
                    -- STRICT SQUARE ICON: Always preserves perfect 1:1 aspect ratio!
                    local cur = this:GetWidth()
                    local newSize = math.floor(cur + (delta * 3) + 0.5)
                    if newSize < 16 then newSize = 16 end
                    if newSize > 72 then newSize = 72 end
                    this:SetWidth(newSize)
                    this:SetHeight(newSize)
                    if CleveRoidMacros then
                        if not CleveRoidMacros.WarriorIconPositions then CleveRoidMacros.WarriorIconPositions = {} end
                        if not CleveRoidMacros.WarriorIconPositions[key] then CleveRoidMacros.WarriorIconPositions[key] = {} end
                        CleveRoidMacros.WarriorIconPositions[key].width = newSize
                        CleveRoidMacros.WarriorIconPositions[key].height = newSize
                    end
                else
                    -- BAR: Horizontal timer bar
                    local curW = this:GetWidth()
                    local newW = math.floor(curW + (delta * 10) + 0.5)
                    if newW < 100 then newW = 100 end
                    if newW > 350 then newW = 350 end
                    local curH = this:GetHeight()
                    local newH = math.floor(curH + (delta * 2) + 0.5)
                    if newH < 8 then newH = 8 end
                    if newH > 32 then newH = 32 end
                    this:SetWidth(newW)
                    this:SetHeight(newH)
                    if CleveRoidMacros then
                        if not CleveRoidMacros.WarriorIconPositions then CleveRoidMacros.WarriorIconPositions = {} end
                        if not CleveRoidMacros.WarriorIconPositions[key] then CleveRoidMacros.WarriorIconPositions[key] = {} end
                        CleveRoidMacros.WarriorIconPositions[key].width = newW
                        CleveRoidMacros.WarriorIconPositions[key].height = newH
                    end
                end
            end
        end)
    end

    -- ------------------------------------------------------------------------
    -- Individual Movable & Resizable Aura Icons (Parented to UIParent!)
    -- ------------------------------------------------------------------------
    local function CreateAuraIcon(key, iconTex, defX, defY)
        local frame = CreateFrame("Frame", "CleveRoidAura_" .. key, UIParent)
        frame:SetFrameStrata("MEDIUM")

        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame)
        bg:SetTexture(0, 0, 0, 0.8)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        icon:SetTexture(iconTex)
        frame.icon = icon

        frame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

        local timerText = frame:CreateFontString(nil, "OVERLAY")
        timerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        timerText:SetPoint("TOP", frame, "TOP", 0, 0)
        timerText:SetTextColor(1, 1, 1, 1)
        frame.timerText = timerText

        local stackText = frame:CreateFontString(nil, "OVERLAY")
        stackText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        stackText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        stackText:SetTextColor(1, 1, 0.2, 1)
        frame.stackText = stackText

        MakeElementMovable(frame, key, defX, defY, 26, 26, true)
        return frame
    end

    local sunderIcon   = CreateAuraIcon("sunder", "Interface\\Icons\\Ability_Warrior_Sunder", -72, -75)
    local hamIcon      = CreateAuraIcon("hamstring", "Interface\\Icons\\Ability_ShockWave", -36, -75)
    local msIcon       = CreateAuraIcon("ms", "Interface\\Icons\\Ability_Warrior_SavageBlow", 0, -75)
    local opIcon       = CreateAuraIcon("overpower", "Interface\\Icons\\Ability_MeleeDamage", 36, -75)
    local revIcon      = CreateAuraIcon("revenge", "Interface\\Icons\\Ability_Warrior_Revenge", 36, -110)
    local demoIcon     = CreateAuraIcon("demo", "Interface\\Icons\\Ability_Warrior_WarCry", -36, -110)
    local tcIcon       = CreateAuraIcon("thunderclap", "Interface\\Icons\\Spell_Nature_ThunderClap", 0, -110)
    local bsIcon       = CreateAuraIcon("battleshout", "Interface\\Icons\\Ability_Warrior_BattleShout", 72, -75)
    local rendAuraIcon = CreateAuraIcon("rend_icon", "Interface\\Icons\\Ability_Gouge", 108, -75)

    -- Overpower & Revenge Proc Tracking
    local opActive = false
    local opExpires = 0
    local revActive = false
    local revExpires = 0

    -- Rend Internal Tick & Duration Tracking
    local rendStartTime = 0
    local lastRendTickTime = 0
    local rendActiveOnTarget = false

    -- ------------------------------------------------------------------------
    -- Individual Movable & Resizable Rend Timer Bar
    -- ------------------------------------------------------------------------
    local rendBar = CreateFrame("StatusBar", "CleveRoidAura_Rend", UIParent)
    rendBar:SetFrameStrata("MEDIUM")
    rendBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rendBar:SetStatusBarColor(0.85, 0.12, 0.15, 1.0)
    rendBar:SetMinMaxValues(0, 1)
    rendBar:SetValue(0)

    local rendBg = rendBar:CreateTexture(nil, "BACKGROUND")
    rendBg:SetAllPoints(rendBar)
    rendBg:SetTexture(0, 0, 0, 0.6)

    rendBar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    rendBar:SetBackdropBorderColor(0.3, 0.1, 0.1, 0.8)

    local rendBarIcon = rendBar:CreateTexture(nil, "OVERLAY")
    rendBarIcon:SetWidth(12)
    rendBarIcon:SetHeight(12)
    rendBarIcon:SetPoint("LEFT", rendBar, "LEFT", 1, 0)
    rendBarIcon:SetTexture("Interface\\Icons\\Ability_Gouge")

    local rendLabel = rendBar:CreateFontString(nil, "OVERLAY")
    rendLabel:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    rendLabel:SetPoint("LEFT", rendBarIcon, "RIGHT", 3, 0)
    rendLabel:SetTextColor(1, 0.8, 0.8, 1)
    rendLabel:SetText("Rend")

    local rendTimerText = rendBar:CreateFontString(nil, "OVERLAY")
    rendTimerText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    rendTimerText:SetPoint("RIGHT", rendBar, "RIGHT", -3, 0)
    rendTimerText:SetTextColor(1, 1, 1, 1)

    local rendTicks = {}
    for i = 1, 7 do
        local tick = rendBar:CreateTexture(nil, "OVERLAY")
        tick:SetWidth(1)
        tick:SetHeight(10)
        tick:SetTexture(1, 0.9, 0.2, 0.5)
        tick:Hide()
        rendTicks[i] = tick
    end

    MakeElementMovable(rendBar, "rend", 0, -100, 190, 12, false)

    local showDebuffs = true
    if CleveRoidMacros and CleveRoidMacros.WarriorHUDDebuffs ~= nil then
        showDebuffs = CleveRoidMacros.WarriorHUDDebuffs
    end

    local showCDs = true
    if CleveRoidMacros and CleveRoidMacros.WarriorHUDCDs ~= nil then
        showCDs = CleveRoidMacros.WarriorHUDCDs
    end

    -- ------------------------------------------------------------------------
    -- 0c. Major Warrior Cooldown Tracker (DEF & OFF)
    -- Displays active buff durations, cooldown sweeps, and "CD IS BACK" highlights
    -- ------------------------------------------------------------------------
    local DEF_SPELLS = {
        { name = "Shield Wall",        icon = "Interface\\Icons\\Ability_Warrior_ShieldWall",    buff = "Shield Wall" },
        { name = "Last Stand",         icon = "Interface\\Icons\\Spell_Holy_AshesToAshes",      buff = "Last Stand" },
        { name = "Retaliation",        icon = "Interface\\Icons\\Ability_Warrior_Challange",     buff = "Retaliation" },
        { name = "Shield Block",       icon = "Interface\\Icons\\Ability_Defend",               buff = "Shield Block" },
        { name = "Intimidating Shout", icon = "Interface\\Icons\\Ability_GolemThunderClap",     buff = nil },
    }

    local OFF_SPELLS = {
        { name = "Death Wish",         icon = "Interface\\Icons\\Spell_Shadow_DeathPact",       buff = "Death Wish" },
        { name = "Sweeping Strikes",   icon = "Interface\\Icons\\Ability_Rogue_SliceDice",      buff = "Sweeping Strikes" },
        { name = "Berserker Rage",     icon = "Interface\\Icons\\Spell_Nature_AncestralGuardian",buff = "Berserker Rage" },
        { name = "Bloodrage",          icon = "Interface\\Icons\\Ability_Racial_BloodRage",     buff = "Bloodrage" },
        { name = "Recklessness",       icon = "Interface\\Icons\\Ability_CriticalStrike",       buff = "Recklessness" },
    }

    local defRow, offRow, LayoutCDGroup, ApplyCDGroupScale, UpdateCDScaleDisplay

    local function CreateCDGroup(groupKey, titleText, labelColor, defX, defY, spells)
        local row = CreateFrame("Frame", "CleveRoidCD_" .. groupKey, UIParent)
        row:SetWidth(140)
        row:SetHeight(28)
        row:SetFrameStrata("MEDIUM")

        row.buttons = {}
        for i, s in ipairs(spells) do
            local btn = CreateFrame("Button", nil, row)
            local btnKey = "cd_" .. groupKey .. "_" .. i
            btn:SetWidth(26)
            btn:SetHeight(26)
            btn:SetPoint("LEFT", row, "LEFT", (i - 1) * 28, 0)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            bg:SetTexture(0, 0, 0, 0.8)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            icon:SetTexture(s.icon)
            btn.icon = icon

            btn:SetBackdrop({
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

            local txt = btn:CreateFontString(nil, "OVERLAY")
            txt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
            txt:SetTextColor(1, 1, 1, 1)
            btn.timerText = txt

            btn.spellInfo = s
            btn.spellName = s.name
            btn.groupKey = groupKey
            btn.btnIndex = i

            btn:EnableMouse(true)
            btn:EnableMouseWheel(true)
            btn:RegisterForDrag("LeftButton")
            btn:RegisterForClicks("RightButtonUp")

            btn:SetScript("OnDragStart", function()
                if IsShiftKeyDown() or isUnlocked then
                    row:StartMoving()
                    row.isMoving = true
                end
            end)
            btn:SetScript("OnDragStop", function()
                if row.isMoving then
                    row:StopMovingOrSizing()
                    row.isMoving = false
                    local pt, _, relPt, x, y = row:GetPoint()
                    if CleveRoidMacros then
                        if not CleveRoidMacros.WarriorIconPositions then CleveRoidMacros.WarriorIconPositions = {} end
                        if not CleveRoidMacros.WarriorIconPositions[groupKey] then CleveRoidMacros.WarriorIconPositions[groupKey] = {} end
                        CleveRoidMacros.WarriorIconPositions[groupKey].point = pt
                        CleveRoidMacros.WarriorIconPositions[groupKey].relPt = relPt
                        CleveRoidMacros.WarriorIconPositions[groupKey].x = x
                        CleveRoidMacros.WarriorIconPositions[groupKey].y = y
                    end
                end
            end)

            btn:SetScript("OnMouseWheel", function()
                if IsControlKeyDown() or isUnlocked then
                    local delta = arg1
                    local cur = this:GetWidth()
                    local newSize = math.floor(cur + (delta * 2) + 0.5)
                    if newSize < 14 then newSize = 14 end
                    if newSize > 64 then newSize = 64 end

                    if CleveRoidMacros then
                        if not CleveRoidMacros.WarriorIconPositions then CleveRoidMacros.WarriorIconPositions = {} end
                        if not CleveRoidMacros.WarriorIconPositions[btnKey] then CleveRoidMacros.WarriorIconPositions[btnKey] = {} end
                        CleveRoidMacros.WarriorIconPositions[btnKey].width = newSize
                        CleveRoidMacros.WarriorIconPositions[btnKey].height = newSize
                    end
                    if LayoutCDGroup then LayoutCDGroup(row, groupKey) end
                end
            end)

            btn:SetScript("OnClick", function()
                if arg1 == "RightButton" and isUnlocked then
                    if CleveRoidMacros and CleveRoidMacros.WarriorIconPositions and CleveRoidMacros.WarriorIconPositions[btnKey] then
                        CleveRoidMacros.WarriorIconPositions[btnKey].width = nil
                        CleveRoidMacros.WarriorIconPositions[btnKey].height = nil
                    end
                    if LayoutCDGroup then LayoutCDGroup(row, groupKey) end
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r Reset " .. s.name .. " size to group default.")
                end
            end)

            btn:SetScript("OnEnter", function()
                if isUnlocked then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText(s.name, 1, 1, 1)
                    GameTooltip:AddLine("Scroll Wheel: Resize icon individually", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("Right-Click: Reset to group size", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("Shift+Drag: Move group row", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row.buttons[i] = btn
        end

        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function()
            if IsControlKeyDown() or isUnlocked then
                local delta = arg1
                local cur = (CleveRoidMacros and CleveRoidMacros.WarriorCDScale) or 1.0
                local nextS = cur + (delta * 0.05)
                if nextS < 0.5 then nextS = 0.5 end
                if nextS > 2.0 then nextS = 2.0 end
                if CleveRoidMacros then CleveRoidMacros.WarriorCDScale = nextS end
                if ApplyCDGroupScale then ApplyCDGroupScale() end
                if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
            end
        end)

        MakeElementMovable(row, groupKey, defX, defY, 140, 28, false)
        return row
    end

    LayoutCDGroup = function(row, groupKey)
        if not row or not row.buttons then return end
        local cdScale = (CleveRoidMacros and CleveRoidMacros.WarriorCDScale) or 1.0
        local baseSize = math.floor(26 * cdScale + 0.5)
        if baseSize < 14 then baseSize = 14 end
        if baseSize > 64 then baseSize = 64 end

        local curX = 0
        local maxH = baseSize

        for i, btn in ipairs(row.buttons) do
            local btnKey = "cd_" .. groupKey .. "_" .. i
            local saved = CleveRoidMacros and CleveRoidMacros.WarriorIconPositions and CleveRoidMacros.WarriorIconPositions[btnKey]
            local btnW = (saved and saved.width) or baseSize
            local btnH = (saved and saved.height) or btnW
            btn:SetWidth(btnW)
            btn:SetHeight(btnH)

            local fontSize = math.max(8, math.floor(btnH * 0.36 + 0.5))
            btn.timerText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

            btn:ClearAllPoints()
            btn:SetPoint("LEFT", row, "LEFT", curX, 0)

            curX = curX + btnW + 2
            if btnH > maxH then maxH = btnH end
        end

        local totalW = (curX > 2) and (curX - 2) or 20
        row:SetWidth(totalW)
        row:SetHeight(maxH)
    end

    ApplyCDGroupScale = function()
        if defRow then LayoutCDGroup(defRow, "def") end
        if offRow then LayoutCDGroup(offRow, "off") end
    end

    defRow = CreateCDGroup("def", "DEF", { 0.35, 0.75, 1.0 }, -215, -75, DEF_SPELLS)
    offRow = CreateCDGroup("off", "OFF", { 1.0, 0.35, 0.25 }, -215, -112, OFF_SPELLS)
    ApplyCDGroupScale()

    local spellBookSlots = {}
    local function FindSpellSlot(name)
        if spellBookSlots[name] then return spellBookSlots[name] end
        for i = 1, 120 do
            local spName = GetSpellName(i, BOOKTYPE_SPELL)
            if not spName then break end
            if string.find(string.lower(spName), string.lower(name)) then
                spellBookSlots[name] = i
                return i
            end
        end
        return nil
    end

    local function UpdateCDGroupDisplay(row, spells, isDef)
        if not showCDs then
            row:Hide()
            return
        end
        row:Show()

        if isUnlocked then
            for i, btn in ipairs(row.buttons) do
                btn:Show()
                if i == 1 then
                    -- Active preview
                    btn.icon:SetAlpha(1.0)
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    btn:SetBackdropBorderColor(0.2, 1.0, 0.3, 1)
                    btn.timerText:SetText("10")
                    btn.timerText:SetTextColor(1, 1, 0.2, 1)
                elseif i == 2 then
                    -- CD preview (heavily dimmed down)
                    btn.icon:SetAlpha(0.18)
                    btn.icon:SetVertexColor(0.35, 0.35, 0.35)
                    btn:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                    btn.timerText:SetText("8m")
                    btn.timerText:SetTextColor(1, 1, 1, 1)
                else
                    -- Ready preview
                    btn.icon:SetAlpha(1.0)
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    local bc = isDef and { 0.2, 0.8, 1.0, 0.9 } or { 1.0, 0.4, 0.2, 0.9 }
                    btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
                    btn.timerText:SetText("")
                end
            end
            return
        end

        for i, btn in ipairs(row.buttons) do
            local s = btn.spellInfo
            local slot = FindSpellSlot(s.name)

            -- 1. Check if ACTIVE buff on player
            local bName, _, _, bRem = nil, 0, 0, 0
            if s.buff then
                bName, _, _, bRem = ScanAura("player", s.buff, "HELPFUL")
            end

            if bName then
                -- Buff is currently ACTIVE!
                btn:Show()
                btn.icon:SetAlpha(1.0)
                btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                btn:SetBackdropBorderColor(0.2, 1.0, 0.3, 1.0) -- Vibrant green glowing border!
                btn.timerText:SetTextColor(1, 1, 0.2, 1)
                btn.timerText:SetText(bRem > 0 and (bRem > 9.9 and string.format("%ds", math.ceil(bRem)) or string.format("%.1f", bRem)) or "UP")
            elseif slot then
                -- 2. Check Cooldown
                local start, duration = GetSpellCooldown(slot, BOOKTYPE_SPELL)
                if start and duration and duration > 2.0 then
                    local rem = (start + duration) - GetTime()
                    if rem > 0 then
                        -- On COOLDOWN! Heavily dimmed down and desaturated
                        btn:Show()
                        btn.icon:SetAlpha(0.18)
                        btn.icon:SetVertexColor(0.35, 0.35, 0.35)
                        btn:SetBackdropBorderColor(0.20, 0.20, 0.20, 0.8)
                        btn.timerText:SetTextColor(1, 1, 1, 1)
                        btn.timerText:SetText(rem > 60 and string.format("%dm", math.ceil(rem / 60)) or string.format("%ds", math.ceil(rem)))
                    else
                        -- Off Cooldown (READY!)
                        btn:Show()
                        btn.icon:SetAlpha(1.0)
                        btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                        local bc = isDef and { 0.2, 0.8, 1.0, 0.9 } or { 1.0, 0.4, 0.2, 0.9 }
                        btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
                        btn.timerText:SetText("")
                    end
                else
                    -- READY / AVAILABLE TO USE! ("GOT MY CDS BACK")
                    btn:Show()
                    btn.icon:SetAlpha(1.0)
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    local bc = isDef and { 0.2, 0.8, 1.0, 0.9 } or { 1.0, 0.4, 0.2, 0.9 }
                    btn:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4])
                    btn.timerText:SetText("")
                end
            else
                -- Talent not learned, hide icon
                btn:Hide()
            end
        end
    end

    local function UpdateWarriorCDs()
        UpdateCDGroupDisplay(defRow, DEF_SPELLS, true)
        UpdateCDGroupDisplay(offRow, OFF_SPELLS, false)
    end

    local function UpdateAuras()
        if not showDebuffs then
            sunderIcon:Hide()
            hamIcon:Hide()
            msIcon:Hide()
            opIcon:Hide()
            revIcon:Hide()
            demoIcon:Hide()
            tcIcon:Hide()
            bsIcon:Hide()
            rendAuraIcon:Hide()
            rendBar:Hide()
            return
        end

        -- Unlock / Move / Resize preview mode!
        if isUnlocked then
            sunderIcon:Show(); sunderIcon.icon:SetAlpha(1); sunderIcon:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
            sunderIcon.timerText:SetText("28"); sunderIcon.stackText:SetText("5"); sunderIcon.stackText:SetTextColor(0.2, 1, 0.2, 1)

            hamIcon:Show(); hamIcon.icon:SetAlpha(1); hamIcon:SetBackdropBorderColor(1, 0.5, 0.1, 1)
            hamIcon.timerText:SetText("15")

            msIcon:Show(); msIcon.icon:SetAlpha(1); msIcon:SetBackdropBorderColor(0.9, 0.1, 0.1, 1)
            msIcon.timerText:SetText("10")

            opIcon:Show(); opIcon.icon:SetAlpha(1); opIcon:SetBackdropBorderColor(1, 0.85, 0, 1)
            opIcon.timerText:SetText("5.0"); opIcon.stackText:SetText("OP"); opIcon.stackText:SetTextColor(1, 0.9, 0.2, 1)

            revIcon:Show(); revIcon.icon:SetAlpha(1); revIcon:SetBackdropBorderColor(1, 0.65, 0, 1)
            revIcon.timerText:SetText("5.0"); revIcon.stackText:SetText("REV"); revIcon.stackText:SetTextColor(1, 0.85, 0.2, 1)

            demoIcon:Show(); demoIcon.icon:SetAlpha(1); demoIcon:SetBackdropBorderColor(0.2, 0.75, 0.95, 1)
            demoIcon.timerText:SetText("30"); demoIcon.stackText:SetText("")

            tcIcon:Show(); tcIcon.icon:SetAlpha(1); tcIcon:SetBackdropBorderColor(0.3, 0.55, 1.0, 1)
            tcIcon.timerText:SetText("20"); tcIcon.stackText:SetText("")

            bsIcon:Show(); bsIcon.icon:SetAlpha(1); bsIcon:SetBackdropBorderColor(0.2, 0.6, 1.0, 1)
            bsIcon.timerText:SetText("2m")

            rendAuraIcon:Show(); rendAuraIcon.icon:SetAlpha(1); rendAuraIcon:SetBackdropBorderColor(0.85, 0.15, 0.15, 1)
            rendAuraIcon.timerText:SetText("18"); rendAuraIcon.stackText:SetText("2.4"); rendAuraIcon.stackText:SetTextColor(1, 0.8, 0.2, 1)

            rendBar:Show(); rendBar:SetMinMaxValues(0, 21); rendBar:SetValue(14)
            rendTimerText:SetText("14.0s [2.0s] (5)")
            for i = 1, 7 do
                if i < 7 then
                    local tickTime = i * 3.0
                    local posX = (tickTime / 21) * (rendBar:GetWidth() - 16) + 14
                    rendTicks[i]:SetPoint("LEFT", rendBar, "LEFT", posX, 0)
                    rendTicks[i]:Show()
                else
                    rendTicks[i]:Hide()
                end
            end
            return
        end

        bsIcon:Show()

        local now = GetTime()

        -- 1. Sunder Armor (only visible when present on target)
        local sName, sApps, sDur, sRem = ScanAura("target", "Sunder", "HARMFUL")
        if sName then
            sunderIcon:Show()
            sunderIcon.icon:SetAlpha(1.0)
            sunderIcon.icon:Show()
            sunderIcon:SetBackdropBorderColor(0.2, 0.8, 0.2, 0.8)
            sunderIcon.timerText:SetText(sRem > 0 and string.format("%d", math.ceil(sRem)) or "")
            sunderIcon.stackText:SetText(tostring(sApps or 1))
            if sApps >= 5 then
                sunderIcon.stackText:SetTextColor(0.2, 1, 0.2, 1) -- Bright green at 5 stacks!
            elseif sApps >= 3 then
                sunderIcon.stackText:SetTextColor(1, 1, 0.2, 1)
            else
                sunderIcon.stackText:SetTextColor(1, 0.5, 0.2, 1)
            end
        else
            sunderIcon:Hide()
        end

        -- 2. Hamstring (only visible when present on target)
        local hName, _, _, hRem = ScanAura("target", "Hamstring", "HARMFUL")
        if hName then
            hamIcon:Show()
            hamIcon.icon:SetAlpha(1.0)
            hamIcon.icon:Show()
            hamIcon:SetBackdropBorderColor(1, 0.5, 0.1, 0.8)
            hamIcon.timerText:SetText(hRem > 0 and string.format("%d", math.ceil(hRem)) or "")
        else
            hamIcon:Hide()
        end

        -- 3. Mortal Strike (only visible when present on target)
        local msName, _, _, msRem = ScanAura("target", "Mortal Strike", "HARMFUL")
        if msName then
            msIcon:Show()
            msIcon.icon:SetAlpha(1.0)
            msIcon.icon:Show()
            msIcon:SetBackdropBorderColor(0.9, 0.1, 0.1, 0.8)
            msIcon.timerText:SetText(msRem > 0 and string.format("%d", math.ceil(msRem)) or "")
        else
            msIcon:Hide()
        end

        -- 4. Overpower Proc (only visible when usable / enemy dodged)
        if opActive and now < opExpires then
            local rem = opExpires - now
            opIcon:Show()
            opIcon.icon:SetAlpha(1.0)
            opIcon.icon:Show()
            opIcon:SetBackdropBorderColor(1, 0.85, 0, 1) -- Golden glowing border!
            opIcon.timerText:SetText(string.format("%.1f", rem))
            opIcon.stackText:SetText("OP")
            opIcon.stackText:SetTextColor(1, 0.9, 0.2, 1)
        else
            opActive = false
            opIcon:Hide()
        end

        -- 4b. Revenge Proc (only visible when usable / block, dodge, or parry occurred)
        local hasRevProc = (revActive and now < revExpires)
        if not hasRevProc and CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc("Revenge") then
            hasRevProc = true
            if CleveRoids.reactiveProcs and CleveRoids.reactiveProcs["Revenge"] and CleveRoids.reactiveProcs["Revenge"].expiry then
                revExpires = CleveRoids.reactiveProcs["Revenge"].expiry
            else
                revExpires = now + 5.0
            end
        end

        if hasRevProc and now < revExpires then
            local rem = revExpires - now
            revIcon:Show()
            revIcon.icon:SetAlpha(1.0)
            revIcon.icon:Show()
            revIcon:SetBackdropBorderColor(1, 0.65, 0, 1) -- Fiery amber/gold glowing border!
            revIcon.timerText:SetText(string.format("%.1f", rem))
            revIcon.stackText:SetText("REV")
            revIcon.stackText:SetTextColor(1, 0.85, 0.2, 1)
        else
            revActive = false
            revIcon:Hide()
        end

        -- 4c. Demoralizing Shout (target debuff / missing alert in combat)
        local demoName, _, _, demoRem = ScanAura("target", "Demoralizing Shout", "HARMFUL")
        if demoName then
            demoIcon:Show()
            demoIcon.icon:SetAlpha(1.0)
            demoIcon.icon:Show()
            demoIcon:SetBackdropBorderColor(0.2, 0.75, 0.95, 0.85) -- Cyan debuff border
            demoIcon.timerText:SetText(demoRem > 0 and string.format("%d", math.ceil(demoRem)) or "")
            demoIcon.stackText:SetText("")
        elseif UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") and UnitAffectingCombat("player") then
            -- Missing alert in combat!
            demoIcon:Show()
            demoIcon.icon:SetAlpha(0.65)
            demoIcon.icon:Show()
            demoIcon:SetBackdropBorderColor(1, 0.2, 0.2, 0.9) -- Red warning border
            demoIcon.timerText:SetText("|cffff2020!|r")
            demoIcon.stackText:SetText("")
        else
            demoIcon:Hide()
        end

        -- 4d. Thunder Clap (target debuff / missing alert in combat)
        local tcName, _, _, tcRem = ScanAura("target", "Thunder Clap", "HARMFUL")
        if tcName then
            tcIcon:Show()
            tcIcon.icon:SetAlpha(1.0)
            tcIcon.icon:Show()
            tcIcon:SetBackdropBorderColor(0.3, 0.55, 1.0, 0.85) -- Electric blue border
            tcIcon.timerText:SetText(tcRem > 0 and string.format("%d", math.ceil(tcRem)) or "")
            tcIcon.stackText:SetText("")
        elseif UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") and UnitAffectingCombat("player") then
            -- Missing alert in combat!
            tcIcon:Show()
            tcIcon.icon:SetAlpha(0.65)
            tcIcon.icon:Show()
            tcIcon:SetBackdropBorderColor(1, 0.45, 0.1, 0.9) -- Orange/red warning border
            tcIcon.timerText:SetText("|cffff8020!|r")
            tcIcon.stackText:SetText("")
        else
            tcIcon:Hide()
        end

        -- 5. Battle Shout
        local bsName, _, bsDur, bsRem = ScanAura("player", "Battle Shout", "HELPFUL")
        if bsName then
            bsIcon.icon:SetAlpha(1.0)
            bsIcon:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.8)
            if bsRem > 60 then
                bsIcon.timerText:SetText(string.format("%dm", math.floor(bsRem / 60)))
            elseif bsRem > 0 then
                bsIcon.timerText:SetText(string.format("%d", math.ceil(bsRem)))
            else
                bsIcon.timerText:SetText("")
            end
        else
            -- Battle Shout MISSING alert: red pulsing border!
            bsIcon.icon:SetAlpha(0.8)
            bsIcon:SetBackdropBorderColor(1, 0.1, 0.1, 1)
            bsIcon.timerText:SetText("|cffff2020!|r")
        end

        -- 6. Rend Aura Icon (like Hamstring, Sunder, Mortal Strike) & Accurate 3s Bleed Ticks
        local rName, _, rDur, rRem = ScanAura("target", "Rend", "HARMFUL")
        if rName then
            local nowTime = GetTime()
            if not rendActiveOnTarget then
                rendActiveOnTarget = true
                rendStartTime = nowTime
                lastRendTickTime = nowTime
            end

            -- Determine total duration and remaining seconds
            local totalDuration = (rDur and rDur > 0) and rDur or 21.0
            local remTime = (rRem and rRem > 0) and rRem or (totalDuration - (nowTime - rendStartTime))
            if remTime < 0 then remTime = 0 end

            -- Calculate exact countdown to the next 3-second damage tick
            local nextTick = 3.0
            if lastRendTickTime > 0 then
                local sinceTick = nowTime - lastRendTickTime
                if sinceTick < 3.0 then
                    nextTick = 3.0 - sinceTick
                else
                    nextTick = remTime % 3.0
                end
            else
                nextTick = remTime % 3.0
            end
            if nextTick <= 0.05 then nextTick = 3.0 end

            local ticksRemaining = math.ceil(remTime / 3.0)

            -- 6a. Rend Aura Icon: square icon, shows remaining duration & next tick countdown
            rendAuraIcon:Show()
            rendAuraIcon.icon:SetAlpha(1.0)
            rendAuraIcon.icon:Show()
            rendAuraIcon:SetBackdropBorderColor(0.85, 0.15, 0.15, 0.85)
            rendAuraIcon.timerText:SetText(remTime > 0 and string.format("%d", math.ceil(remTime)) or "")
            rendAuraIcon.stackText:SetText(string.format("%.1f", nextTick))
            rendAuraIcon.stackText:SetTextColor(1, 0.85, 0.2, 1)

            -- 6b. Rend Progress Bar with synchronized 3s tick countdown
            rendBar:Show()
            rendBar:SetMinMaxValues(0, totalDuration)
            rendBar:SetValue(remTime)
            rendTimerText:SetText(string.format("%.1fs [%.1fs] (%d)", remTime, nextTick, ticksRemaining))

            local barW = rendBar:GetWidth() or 190
            local numTicks = math.floor(totalDuration / 3.0)
            for i = 1, 7 do
                if i < numTicks then
                    local tickPos = ((i * 3.0) / totalDuration) * (barW - 16) + 14
                    rendTicks[i]:SetPoint("LEFT", rendBar, "LEFT", tickPos, 0)
                    rendTicks[i]:Show()
                else
                    rendTicks[i]:Hide()
                end
            end
        else
            rendActiveOnTarget = false
            rendAuraIcon:Hide()
            rendBar:Hide()
        end
    end

    -- ------------------------------------------------------------------------
    -- 1. Slam Auto Delay & Status Text (top of swing bar)
    -- ------------------------------------------------------------------------
    local slamDelayText = hud:CreateFontString(nil, "OVERLAY")
    slamDelayText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    slamDelayText:SetPoint("BOTTOMRIGHT", hud, "TOPRIGHT", -2, 2)
    slamDelayText:SetTextColor(1, 1, 1, 1)
    slamDelayText:SetText("[0.00]")

    local slamStatusText = hud:CreateFontString(nil, "OVERLAY")
    slamStatusText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    slamStatusText:SetPoint("BOTTOMLEFT", hud, "TOPLEFT", 2, 2)
    slamStatusText:SetTextColor(0.2, 0.9, 0.3, 1)
    slamStatusText:SetText("Slam: 2/2 (-0.5s)")

    -- ------------------------------------------------------------------------
    -- 2. Top Bar: Weapon Swing Progress Bar (Green) + Latency + Safe Slam Marker
    -- ------------------------------------------------------------------------
    local swingBar = CreateFrame("StatusBar", nil, hud)
    swingBar:SetWidth(190)
    swingBar:SetHeight(10)
    swingBar:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    swingBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    swingBar:SetStatusBarColor(0.1, 0.85, 0.2, 1.0)
    swingBar:SetMinMaxValues(0, 1)
    swingBar:SetValue(0)

    local swingBg = swingBar:CreateTexture(nil, "BACKGROUND")
    swingBg:SetAllPoints(swingBar)
    swingBg:SetTexture(0, 0, 0, 0.6)

    swingBar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    swingBar:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    -- Red Danger Overlay Zone (from the Clip line to the right edge)
    local slamDangerZone = swingBar:CreateTexture(nil, "ARTWORK")
    slamDangerZone:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    slamDangerZone:SetVertexColor(0.9, 0.1, 0.1, 0.40)
    slamDangerZone:Hide()

    -- Prominent Gold/Red Safe Slam Cut-off Line on the green bar
    local slamSafeMarker = swingBar:CreateTexture(nil, "OVERLAY")
    slamSafeMarker:SetWidth(2)
    slamSafeMarker:SetHeight(16) -- Protrudes 3px above & below bar
    slamSafeMarker:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    slamSafeMarker:SetVertexColor(1.0, 0.95, 0.2, 1.0) -- Vibrant Gold/Yellow
    slamSafeMarker:SetPoint("CENTER", swingBar, "LEFT", 90, 0)
    slamSafeMarker:Hide()

    -- Small "CLIP" text label floating right above the line
    local slamClipLabel = swingBar:CreateFontString(nil, "OVERLAY")
    slamClipLabel:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    slamClipLabel:SetPoint("BOTTOM", slamSafeMarker, "TOP", 0, 1)
    slamClipLabel:SetTextColor(1, 0.3, 0.3, 1)
    slamClipLabel:SetText("CLIP")
    slamClipLabel:Hide()

    -- Dedicated Slam Cast Bar (shows exact cast progress & countdown)
    local slamCastBar = CreateFrame("StatusBar", nil, hud)
    slamCastBar:SetWidth(190)
    slamCastBar:SetHeight(12)
    slamCastBar:SetPoint("BOTTOMLEFT", hud, "TOPLEFT", 0, 16)
    slamCastBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    slamCastBar:SetStatusBarColor(0.2, 0.75, 1.0, 1.0)
    slamCastBar:SetMinMaxValues(0, 1)
    slamCastBar:SetValue(0)
    slamCastBar:Hide()

    local slamCastBg = slamCastBar:CreateTexture(nil, "BACKGROUND")
    slamCastBg:SetAllPoints(slamCastBar)
    slamCastBg:SetTexture(0, 0, 0, 0.75)

    slamCastBar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    slamCastBar:SetBackdropBorderColor(0.2, 0.7, 1.0, 0.9)

    local slamCastLabel = slamCastBar:CreateFontString(nil, "OVERLAY")
    slamCastLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    slamCastLabel:SetPoint("LEFT", slamCastBar, "LEFT", 4, 0)
    slamCastLabel:SetTextColor(1, 0.85, 0.3, 1)
    slamCastLabel:SetText("Slam (2/2)")

    local slamCastTimerText = slamCastBar:CreateFontString(nil, "OVERLAY")
    slamCastTimerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    slamCastTimerText:SetPoint("RIGHT", slamCastBar, "RIGHT", -4, 0)
    slamCastTimerText:SetTextColor(1, 1, 1, 1)
    slamCastTimerText:SetText("0.0 / 2.0s")

    -- Red Latency Zone on the right edge
    local latencyZone = swingBar:CreateTexture(nil, "OVERLAY")
    latencyZone:SetTexture(0.9, 0.15, 0.15, 0.65)
    latencyZone:SetPoint("TOPRIGHT", swingBar, "TOPRIGHT", -1, -1)
    latencyZone:SetPoint("BOTTOMRIGHT", swingBar, "BOTTOMRIGHT", -1, 1)
    latencyZone:SetWidth(16)

    -- ------------------------------------------------------------------------
    -- 3. Middle Bar: Main-Hand Timer (Red) with "Main-Hand" & Times (1.1 / 2.8)
    -- ------------------------------------------------------------------------
    local mhBar = CreateFrame("StatusBar", nil, hud)
    mhBar:SetWidth(190)
    mhBar:SetHeight(12)
    mhBar:SetPoint("TOPLEFT", swingBar, "BOTTOMLEFT", 0, -2)
    mhBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    mhBar:SetStatusBarColor(0.85, 0.15, 0.15, 1.0)
    mhBar:SetMinMaxValues(0, 1)
    mhBar:SetValue(0)

    local mhBg = mhBar:CreateTexture(nil, "BACKGROUND")
    mhBg:SetAllPoints(mhBar)
    mhBg:SetTexture(0, 0, 0, 0.6)

    mhBar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    mhBar:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

    local mhLabel = mhBar:CreateFontString(nil, "OVERLAY")
    mhLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    mhLabel:SetPoint("LEFT", mhBar, "LEFT", 4, 0)
    mhLabel:SetTextColor(1, 0.85, 0.3, 1)
    mhLabel:SetText("Main-Hand")

    local mhTimerText = mhBar:CreateFontString(nil, "OVERLAY")
    mhTimerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    mhTimerText:SetPoint("RIGHT", mhBar, "RIGHT", -4, 0)
    mhTimerText:SetTextColor(1, 1, 1, 1)
    mhTimerText:SetText("0.0 / 0.0")

    -- ------------------------------------------------------------------------
    -- 4. Warrior Rage Bar (Crimson) - Independent Movable & Resizable Bar!
    -- ------------------------------------------------------------------------
    local rageBar = CreateFrame("StatusBar", "CleveRoidWarriorRageBar", UIParent)
    rageBar:SetFrameStrata("MEDIUM")
    rageBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rageBar:SetStatusBarColor(0.78, 0.12, 0.2, 1.0)
    rageBar:SetMinMaxValues(0, 100)
    rageBar:SetValue(UnitMana("player") or 0)

    local rageBg = rageBar:CreateTexture(nil, "BACKGROUND")
    rageBg:SetAllPoints(rageBar)
    rageBg:SetTexture(0, 0, 0, 0.6)

    rageBar:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    rageBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local rageText = rageBar:CreateFontString(nil, "OVERLAY")
    rageText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    rageText:SetPoint("CENTER", rageBar, "CENTER", 0, 0)
    rageText:SetTextColor(1, 1, 1, 1)
    rageText:SetText(tostring(UnitMana("player") or 0))

    MakeElementMovable(rageBar, "ragebar", 0, -146, 190, 14, false)

    -- ------------------------------------------------------------------------
    -- State & Swing Logic (Auto-adapts to 1H vs 2H weapon!)
    -- ------------------------------------------------------------------------
    local swingActive = false
    local swingStart = 0
    local swingDuration = 2.8
    local pingPlayed = false
    local is2H = false
    local audioPing = true
    local slamCasting = false
    local slamCastStart = 0
    local slamCastDuration = 1.98 -- Base 2.5s - 0.5s (Improved Slam 2/2) = 1.98s
    local slamHideTime = nil
    if CleveRoidMacros and CleveRoidMacros.WarriorHUDAudio ~= nil then
        audioPing = CleveRoidMacros.WarriorHUDAudio
    end

    local function UpdateHUDVisibility()
        if CleveRoidMacros and CleveRoidMacros.WarriorHUDVisible == false then
            hud:Hide()
            return
        end

        if isUnlocked then
            hud:Show()
            return
        end

        local inCombat = UnitAffectingCombat("player") or swingActive or slamCasting
        if inCombat then
            hud:Show()
        else
            hud:Hide()
        end
    end

    local function UpdateWeaponMode()
        local link16 = GetInventoryItemLink("player", 16)
        local loc16 = GetItemEquipData(link16)
        is2H = (loc16 == "INVTYPE_2HWEAPON")

        if is2H then
            -- 2-Hander equipped: Show Slam bar and delay counter
            slamDelayText:Show()
            slamStatusText:Show()
            swingBar:Show()
            mhBar:ClearAllPoints()
            mhBar:SetPoint("TOPLEFT", swingBar, "BOTTOMLEFT", 0, -2)
            hud:SetHeight(24)
        else
            -- 1-Hander / Shield / Dual-Wield equipped: Hide Slam bar and counter, mute ping!
            slamDelayText:Hide()
            slamStatusText:Hide()
            slamSafeMarker:Hide()
            slamDangerZone:Hide()
            slamClipLabel:Hide()
            slamCastBar:Hide()
            swingBar:Hide()
            mhBar:ClearAllPoints()
            mhBar:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
            hud:SetHeight(12)
        end
    end

    local function TriggerSwing(durationOverride)
        local mhSpeed = UnitAttackSpeed("player")
        if not mhSpeed or mhSpeed <= 0 then mhSpeed = 2.8 end
        swingDuration = (durationOverride and durationOverride > 0) and durationOverride or mhSpeed
        swingStart = GetTime()
        swingActive = true
        pingPlayed = false
        UpdateHUDVisibility()

        -- Update latency zone width (only used when in 2H mode)
        if is2H then
            local _, _, latency = GetNetStats()
            local latSec = (latency and latency > 0) and (latency / 1000) or 0.05
            local latWidth = (latSec / swingDuration) * 190
            if latWidth < 6 then latWidth = 6 end
            if latWidth > 60 then latWidth = 60 end
            latencyZone:SetWidth(latWidth)
        end
    end

    local function StopSwing()
        swingActive = false
        swingBar:SetValue(0)
        mhBar:SetValue(0)
        mhTimerText:SetText(string.format("0.0 / %.1f", swingDuration))
        UpdateHUDVisibility()
    end

    local function UpdateRageDisplay()
        UpdateAuras()
        local curRage = UnitMana("player") or 0
        local maxRage = UnitManaMax("player") or 100
        if maxRage <= 0 then maxRage = 100 end
        rageBar:SetMinMaxValues(0, maxRage)
        if isUnlocked and curRage == 0 then
            rageBar:SetValue(65)
            rageText:SetText("65")
            rageBar:SetBackdropBorderColor(0.8, 0.2, 0.2, 1.0)
        else
            rageBar:SetValue(curRage)
            rageText:SetText(tostring(curRage))
            rageBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
        end
    end

    -- Event Listener Frame
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_RAGE")
    eventFrame:RegisterEvent("UNIT_MAXRAGE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
    eventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SWING")
    eventFrame:RegisterEvent("STOP_AUTOATTACK")
    eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    eventFrame:RegisterEvent("SPELLCAST_START")
    eventFrame:RegisterEvent("SPELLCAST_STOP")
    eventFrame:RegisterEvent("SPELLCAST_FAILED")
    eventFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    eventFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
    eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
    eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

    eventFrame:SetScript("OnEvent", function()
        if event == "UNIT_RAGE" or event == "UNIT_MAXRAGE" then
            if arg1 == "player" then UpdateRageDisplay()
        UpdateAuras() end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            UpdateWeaponMode()
            UpdateRageDisplay()
        UpdateAuras()
        elseif event == "PLAYER_SWING" then
            if arg2 == 0 or arg2 == nil then -- Main hand swing
                TriggerSwing(arg1)
            end
        elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
            if arg1 then
                local lowerMsg = string.lower(arg1)
                if string.find(lowerMsg, "block") or string.find(lowerMsg, "dodge") or string.find(lowerMsg, "parry") then
                    revActive = true
                    revExpires = GetTime() + 5.0
                    UpdateAuras()
                end
            end
        elseif event == "CHAT_MSG_COMBAT_SELF_MISSES" then
            if arg1 and string.find(string.lower(arg1), "dodge") then
                opActive = true
                opExpires = GetTime() + 5.0
                UpdateAuras()
            end
            TriggerSwing()
        elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
            if arg1 then
                local lowerMsg = string.lower(arg1)
                if string.find(lowerMsg, "dodge") then
                    opActive = true
                    opExpires = GetTime() + 5.0
                    UpdateAuras()
                elseif string.find(lowerMsg, "overpower") then
                    opActive = false
                    UpdateAuras()
                elseif string.find(lowerMsg, "revenge") then
                    revActive = false
                    UpdateAuras()
                elseif string.find(lowerMsg, "rend") then
                    rendStartTime = GetTime()
                    lastRendTickTime = GetTime()
                    rendActiveOnTarget = true
                    UpdateAuras()
                end
            end
        elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
            if arg1 and string.find(string.lower(arg1), "rend") then
                lastRendTickTime = GetTime()
                UpdateAuras()
            end
        elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
            TriggerSwing()
        elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_AURA" then
            UpdateAuras()
        elseif event == "STOP_AUTOATTACK" then
            StopSwing()
        elseif event == "UNIT_ATTACK_SPEED" then
            if arg1 == "player" then
                local mhSpeed = UnitAttackSpeed("player")
                if mhSpeed and mhSpeed > 0 then swingDuration = mhSpeed end
            end
        elseif event == "SPELLCAST_START" or event == "UNIT_SPELLCAST_START" then
            local spellName = arg1
            local durationMs = arg2
            if event == "UNIT_SPELLCAST_START" then
                if arg1 ~= "player" then return end
                spellName = arg4 or arg2
            end
            if not spellName and C_Spell and C_Spell.UnitCastingInfo then
                spellName = C_Spell.UnitCastingInfo("player")
            end
            if spellName and string.find(string.lower(spellName), "overpower") then
                opActive = false
                UpdateAuras()
            end
            if spellName and string.find(string.lower(spellName), "revenge") then
                revActive = false
                UpdateAuras()
            end
            if is2H and spellName and string.find(string.lower(spellName), "slam") then
                local now = GetTime()
                slamCasting = true
                slamCastStart = now
                if durationMs and type(durationMs) == "number" and durationMs > 0 then
                    slamCastDuration = durationMs / 1000
                else
                    slamCastDuration = 1.98 -- 2/2 Improved Slam: 1.98s ~ 2.0s
                end
                slamCastBar:SetMinMaxValues(0, slamCastDuration)
                slamCastBar:SetValue(0)
                slamCastBar:SetStatusBarColor(0.2, 0.75, 1.0, 1.0)
                slamCastLabel:SetText(string.format("Slam 2/2 (%.2fs)", slamCastDuration))
                slamCastTimerText:SetText(string.format("0.0 / %.2fs", slamCastDuration))
                slamCastBar:Show()

                local reactionDelay = now - swingStart
                if reactionDelay < 0 then reactionDelay = 0 end

                local finishTime = now + slamCastDuration
                local swingEndTime = swingStart + swingDuration
                local projectedDelay = finishTime - swingEndTime

                if projectedDelay <= 0.05 then
                    slamStatusText:SetText("|cff20ff20Slam: Safe (+0.00s delay)|r")
                    slamDelayText:SetText(string.format("|cff20ff20[Delay: %.2fs]|r", reactionDelay))
                else
                    slamStatusText:SetText(string.format("|cffff4040Clips swing by +%.2fs!|r", projectedDelay))
                    slamDelayText:SetText(string.format("|cffff4040[Delay: %.2fs]|r", reactionDelay))
                end
                UpdateHUDVisibility()
            end
        elseif event == "SPELLCAST_STOP" then
            if slamCasting then
                slamCasting = false
                local now = GetTime()
                local actualCast = now - slamCastStart
                local swingEndTime = swingStart + swingDuration
                local actualDelay = now - swingEndTime

                if actualDelay <= 0.05 then
                    slamCastBar:SetStatusBarColor(0.1, 0.9, 0.2, 1.0)
                    slamStatusText:SetText(string.format("|cff20ff20Slam %.2fs: Clean (+0.00s)|r", actualCast))
                else
                    slamCastBar:SetStatusBarColor(0.95, 0.2, 0.2, 1.0)
                    slamStatusText:SetText(string.format("|cffff4040Slam %.2fs: Delayed +%.2fs|r", actualCast, actualDelay))
                end
                slamCastTimerText:SetText(string.format("%.2fs Done", actualCast))
                slamHideTime = now + 1.2
            end
        elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
            if slamCasting then
                slamCasting = false
                slamCastBar:SetStatusBarColor(0.8, 0.2, 0.2, 1.0)
                slamStatusText:SetText("|cffff2020Slam Interrupted!|r")
                slamHideTime = GetTime() + 1.0
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateWeaponMode()
            UpdateRageDisplay()
            UpdateAuras()
            UpdateHUDVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            UpdateRageDisplay()
            UpdateAuras()
            StopSwing()
            UpdateHUDVisibility()
        elseif event == "PLAYER_ENTER_COMBAT" then
            UpdateHUDVisibility()
        elseif event == "PLAYER_LEAVE_COMBAT" then
            StopSwing()
            UpdateHUDVisibility()
        end
    end)

    -- Dedicated ticker for Rage, Auras, and Cooldowns (runs continuously regardless of hud combat visibility)
    local hudTicker = CreateFrame("Frame")
    hudTicker:SetScript("OnUpdate", function()
        UpdateRageDisplay()
        UpdateAuras()
        UpdateWarriorCDs()
    end)

    -- Ticker for weapon swing and slam progress bar animation (active when hud is shown)
    hud:SetScript("OnUpdate", function()
        local now = GetTime()

        -- Update Slam Cast Bar progress
        if slamCasting then
            local castElapsed = now - slamCastStart
            if castElapsed > slamCastDuration then castElapsed = slamCastDuration end
            slamCastBar:SetValue(castElapsed)
            slamCastTimerText:SetText(string.format("%.2f / %.2fs", castElapsed, slamCastDuration))
        elseif slamHideTime and now > slamHideTime then
            slamCastBar:Hide()
            slamHideTime = nil
        end

        if swingActive and swingDuration > 0 then
            local elapsed = now - swingStart
            local remaining = swingDuration - elapsed

            if remaining <= 0 then
                if is2H then swingBar:SetValue(1) end
                mhBar:SetValue(0)
                mhTimerText:SetText(string.format("0.0 / %.1f", swingDuration))
                swingActive = false
                UpdateHUDVisibility()
            else
                if is2H then
                    local progress = elapsed / swingDuration
                    if progress > 1 then progress = 1 elseif progress < 0 then progress = 0 end
                    swingBar:SetMinMaxValues(0, swingDuration)
                    swingBar:SetValue(elapsed)

                    -- Position the Gold Safe Slam Cut-off Line & Red Danger Zone on swingBar
                    local safeTime = swingDuration - slamCastDuration
                    if safeTime > 0 then
                        local safePos = (safeTime / swingDuration) * 190
                        slamSafeMarker:ClearAllPoints()
                        slamSafeMarker:SetPoint("CENTER", swingBar, "LEFT", safePos, 0)
                        slamSafeMarker:Show()
                        slamClipLabel:Show()

                        -- Shade danger zone from the line to the right edge
                        slamDangerZone:ClearAllPoints()
                        slamDangerZone:SetPoint("TOPLEFT", swingBar, "LEFT", safePos, 5)
                        slamDangerZone:SetPoint("BOTTOMRIGHT", swingBar, "BOTTOMRIGHT", 0, 0)
                        slamDangerZone:Show()

                        -- Live Safe Zone text while swinging (when not casting)
                        if not slamCasting then
                            if elapsed <= safeTime then
                                slamStatusText:SetText(string.format("|cff20ff20Slam Safe: %.1fs left|r", safeTime - elapsed))
                            else
                                slamStatusText:SetText(string.format("|cffff3030IN CLIP ZONE (+%.2fs)|r", elapsed - safeTime))
                            end
                        end
                    else
                        slamSafeMarker:Hide()
                        slamDangerZone:Hide()
                        slamClipLabel:Hide()
                        if not slamCasting then
                            slamStatusText:SetText("|cffff4040Weapon too fast for Slam!|r")
                        end
                    end
                end

                -- Swing timer FILLS from left to right like slam timer!
                mhBar:SetMinMaxValues(0, swingDuration)
                mhBar:SetValue(elapsed)
                mhTimerText:SetText(string.format("%.1f / %.1f", elapsed, swingDuration))

                -- Audio ping: ONLY fires when is2H is true! (Muted on 1H swords/axes/maces)
                if is2H and audioPing and not pingPlayed and remaining <= 0.08 then
                    pingPlayed = true
                    PlaySoundFile("Sound\\Doodad\\BellTollNightElf.wav")
                end
            end
        end
    end)

    UpdateWeaponMode()

    -- ------------------------------------------------------------------------
    -- 5. Settings Menu Popup Frame
    -- ------------------------------------------------------------------------
    local menu = CreateFrame("Frame", "CleveRoidWarriorHUDMenu", UIParent)
    menu:SetWidth(206)
    menu:SetHeight(345)
    menu:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    menu:SetMovable(true)
    menu:EnableMouse(true)
    menu:RegisterForDrag("LeftButton")
    menu:SetScript("OnDragStart", function() this:StartMoving() end)
    menu:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    menu:Hide()

    local menuTitle = menu:CreateFontString(nil, "OVERLAY")
    menuTitle:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    menuTitle:SetPoint("TOP", menu, "TOP", 0, -10)
    menuTitle:SetTextColor(1, 0.85, 0.2, 1)
    menuTitle:SetText("Warrior Combat HUD")

    -- Close Button [X]
    local closeBtn = CreateFrame("Button", nil, menu, "UIPanelCloseButton")
    closeBtn:SetWidth(24)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() menu:Hide() end)

    -- Tab System Header: [Settings]  [Dungeon Prep]
    local tabSettings = CreateFrame("Button", "CleveRoidHUDTab1", menu, "UIPanelButtonTemplate")
    tabSettings:SetWidth(88)
    tabSettings:SetHeight(20)
    tabSettings:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -26)
    tabSettings:SetText("|cff20ff20Settings|r")

    local tabPrep = CreateFrame("Button", "CleveRoidHUDTab2", menu, "UIPanelButtonTemplate")
    tabPrep:SetWidth(94)
    tabPrep:SetHeight(20)
    tabPrep:SetPoint("LEFT", tabSettings, "RIGHT", 4, 0)
    tabPrep:SetText("Dungeon Prep")

    local settingsPanel = CreateFrame("Frame", nil, menu)
    settingsPanel:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -48)
    settingsPanel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)

    local prepPanel = CreateFrame("Frame", nil, menu)
    prepPanel:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -48)
    prepPanel:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
    prepPanel:Hide()

    -- ------------------------------------------------------------------------
    -- TAB 1: Settings Panel Controls
    -- ------------------------------------------------------------------------

    -- 1. Show/Hide Toggle Button
    local toggleHudBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    toggleHudBtn:SetWidth(174)
    toggleHudBtn:SetHeight(20)
    toggleHudBtn:SetPoint("TOP", settingsPanel, "TOP", 0, 0)
    local function UpdateToggleHudText()
        if hud:IsShown() then
            toggleHudBtn:SetText("HUD: |cff20ff20Visible|r")
        else
            toggleHudBtn:SetText("HUD: |cffff4040Hidden|r")
        end
    end
    toggleHudBtn:SetScript("OnClick", function()
        if hud:IsShown() then
            hud:Hide()
            rageBar:Hide()
            if CleveRoidMacros then CleveRoidMacros.WarriorHUDVisible = false end
        else
            hud:Show()
            rageBar:Show()
            UpdateRageDisplay()
            UpdateAuras()
            if CleveRoidMacros then CleveRoidMacros.WarriorHUDVisible = true end
        end
        UpdateToggleHudText()
    end)

    -- 2. Sound Ping Toggle Button
    local soundBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    soundBtn:SetWidth(174)
    soundBtn:SetHeight(20)
    soundBtn:SetPoint("TOP", toggleHudBtn, "BOTTOM", 0, -4)
    local function UpdateSoundBtnText()
        if audioPing then
            soundBtn:SetText("Slam Ping: |cff20ff20ON|r")
        else
            soundBtn:SetText("Slam Ping: |cffff4040OFF|r")
        end
    end
    soundBtn:SetScript("OnClick", function()
        audioPing = not audioPing
        if CleveRoidMacros then CleveRoidMacros.WarriorHUDAudio = audioPing end
        UpdateSoundBtnText()
    end)

    -- 3. Debuffs Tracker Toggle Button
    local debuffBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    debuffBtn:SetWidth(174)
    debuffBtn:SetHeight(20)
    debuffBtn:SetPoint("TOP", soundBtn, "BOTTOM", 0, -4)
    local function UpdateDebuffBtnText()
        if showDebuffs then
            debuffBtn:SetText("Debuff Tracker: |cff20ff20ON|r")
        else
            debuffBtn:SetText("Debuff Tracker: |cffff4040OFF|r")
        end
    end
    debuffBtn:SetScript("OnClick", function()
        showDebuffs = not showDebuffs
        if CleveRoidMacros then CleveRoidMacros.WarriorHUDDebuffs = showDebuffs end
        UpdateDebuffBtnText()
        UpdateAuras()
    end)

    -- 4a. HUD Size Controls: [-]  [ 100% ]  [+]
    local incSizeBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    incSizeBtn:SetWidth(22)
    incSizeBtn:SetHeight(18)
    incSizeBtn:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", -16, -74)
    incSizeBtn:SetText("+")

    local sizeValText = settingsPanel:CreateFontString(nil, "OVERLAY")
    sizeValText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    sizeValText:SetWidth(36)
    sizeValText:SetJustifyH("CENTER")
    sizeValText:SetPoint("RIGHT", incSizeBtn, "LEFT", -4, 0)
    sizeValText:SetTextColor(1, 0.85, 0.2, 1)

    local function UpdateScaleDisplay()
        sizeValText:SetText(string.format("%d%%", math.floor(curScale * 100 + 0.5)))
    end

    local decSizeBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    decSizeBtn:SetWidth(22)
    decSizeBtn:SetHeight(18)
    decSizeBtn:SetPoint("RIGHT", sizeValText, "LEFT", -4, 0)
    decSizeBtn:SetText("-")

    local sizeLabel = settingsPanel:CreateFontString(nil, "OVERLAY")
    sizeLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
    sizeLabel:SetWidth(80)
    sizeLabel:SetJustifyH("LEFT")
    sizeLabel:SetPoint("RIGHT", decSizeBtn, "LEFT", -6, 0)
    sizeLabel:SetTextColor(1, 1, 1, 1)
    sizeLabel:SetText("HUD Size:")

    decSizeBtn:SetScript("OnClick", function()
        curScale = curScale - 0.1
        if curScale < 0.6 then curScale = 0.6 end
        hud:SetScale(curScale)
        if CleveRoidMacros then CleveRoidMacros.WarriorHUDScale = curScale end
        UpdateScaleDisplay()
    end)

    incSizeBtn:SetScript("OnClick", function()
        curScale = curScale + 0.1
        if curScale > 2.0 then curScale = 2.0 end
        hud:SetScale(curScale)
        if CleveRoidMacros then CleveRoidMacros.WarriorHUDScale = curScale end
        UpdateScaleDisplay()
    end)

    -- 4b. Extra Action Bars Size: [-]  [ 100% ]  [+]
    local incExtraBarBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    incExtraBarBtn:SetWidth(22)
    incExtraBarBtn:SetHeight(18)
    incExtraBarBtn:SetPoint("TOPRIGHT", incSizeBtn, "BOTTOMRIGHT", 0, -4)
    incExtraBarBtn:SetText("+")

    local extraBarValText = settingsPanel:CreateFontString(nil, "OVERLAY")
    extraBarValText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    extraBarValText:SetWidth(36)
    extraBarValText:SetJustifyH("CENTER")
    extraBarValText:SetPoint("RIGHT", incExtraBarBtn, "LEFT", -4, 0)
    extraBarValText:SetTextColor(0.2, 1, 0.4, 1)

    local function UpdateExtraBarScaleDisplay()
        local s = 1.0
        if CleveRoids_GetExtraBarScale then
            s = CleveRoids_GetExtraBarScale()
        elseif CleveRoidMacros and CleveRoidMacros.ExtraBarScale then
            s = CleveRoidMacros.ExtraBarScale
        end
        extraBarValText:SetText(string.format("%d%%", math.floor(s * 100 + 0.5)))
    end

    local decExtraBarBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    decExtraBarBtn:SetWidth(22)
    decExtraBarBtn:SetHeight(18)
    decExtraBarBtn:SetPoint("RIGHT", extraBarValText, "LEFT", -4, 0)
    decExtraBarBtn:SetText("-")

    local extraBarLabel = settingsPanel:CreateFontString(nil, "OVERLAY")
    extraBarLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
    extraBarLabel:SetWidth(80)
    extraBarLabel:SetJustifyH("LEFT")
    extraBarLabel:SetPoint("RIGHT", decExtraBarBtn, "LEFT", -6, 0)
    extraBarLabel:SetTextColor(1, 1, 1, 1)
    extraBarLabel:SetText("Extra Bars:")

    decExtraBarBtn:SetScript("OnClick", function()
        local cur = CleveRoids_GetExtraBarScale and CleveRoids_GetExtraBarScale() or 1.0
        local nextS = cur - 0.05
        if CleveRoids_SetExtraBarScale then CleveRoids_SetExtraBarScale(nextS) end
        UpdateExtraBarScaleDisplay()
    end)

    incExtraBarBtn:SetScript("OnClick", function()
        local cur = CleveRoids_GetExtraBarScale and CleveRoids_GetExtraBarScale() or 1.0
        local nextS = cur + 0.05
        if CleveRoids_SetExtraBarScale then CleveRoids_SetExtraBarScale(nextS) end
        UpdateExtraBarScaleDisplay()
    end)

    -- 4c. Main Bottom Action Bars Size: [-]  [ 100% ]  [+]
    local incMainBarBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    incMainBarBtn:SetWidth(22)
    incMainBarBtn:SetHeight(18)
    incMainBarBtn:SetPoint("TOPRIGHT", incExtraBarBtn, "BOTTOMRIGHT", 0, -4)
    incMainBarBtn:SetText("+")

    local mainBarValText = settingsPanel:CreateFontString(nil, "OVERLAY")
    mainBarValText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    mainBarValText:SetWidth(36)
    mainBarValText:SetJustifyH("CENTER")
    mainBarValText:SetPoint("RIGHT", incMainBarBtn, "LEFT", -4, 0)
    mainBarValText:SetTextColor(0.4, 0.8, 1.0, 1)

    local function UpdateMainBarScaleDisplay()
        local s = 1.0
        if CleveRoids_GetMainBarScale then
            s = CleveRoids_GetMainBarScale()
        elseif CleveRoidMacros and CleveRoidMacros.MainBarScale then
            s = CleveRoidMacros.MainBarScale
        end
        mainBarValText:SetText(string.format("%d%%", math.floor(s * 100 + 0.5)))
    end

    local decMainBarBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    decMainBarBtn:SetWidth(22)
    decMainBarBtn:SetHeight(18)
    decMainBarBtn:SetPoint("RIGHT", mainBarValText, "LEFT", -4, 0)
    decMainBarBtn:SetText("-")

    local mainBarLabel = settingsPanel:CreateFontString(nil, "OVERLAY")
    mainBarLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
    mainBarLabel:SetWidth(80)
    mainBarLabel:SetJustifyH("LEFT")
    mainBarLabel:SetPoint("RIGHT", decMainBarBtn, "LEFT", -6, 0)
    mainBarLabel:SetTextColor(1, 1, 1, 1)
    mainBarLabel:SetText("Main Bars:")

    decMainBarBtn:SetScript("OnClick", function()
        local cur = CleveRoids_GetMainBarScale and CleveRoids_GetMainBarScale() or 1.0
        local nextS = cur - 0.05
        if CleveRoids_SetMainBarScale then CleveRoids_SetMainBarScale(nextS) end
        UpdateMainBarScaleDisplay()
    end)

    incMainBarBtn:SetScript("OnClick", function()
        local cur = CleveRoids_GetMainBarScale and CleveRoids_GetMainBarScale() or 1.0
        local nextS = cur + 0.05
        if CleveRoids_SetMainBarScale then CleveRoids_SetMainBarScale(nextS) end
        UpdateMainBarScaleDisplay()
    end)

    -- 4d. Warrior CDs Size (Group): [-]  [ 100% ]  [+]
    local incCDBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    incCDBtn:SetWidth(22)
    incCDBtn:SetHeight(18)
    incCDBtn:SetPoint("TOPRIGHT", incMainBarBtn, "BOTTOMRIGHT", 0, -4)
    incCDBtn:SetText("+")

    local cdValText = settingsPanel:CreateFontString(nil, "OVERLAY")
    cdValText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    cdValText:SetWidth(36)
    cdValText:SetJustifyH("CENTER")
    cdValText:SetPoint("RIGHT", incCDBtn, "LEFT", -4, 0)
    cdValText:SetTextColor(1.0, 0.5, 0.2, 1)

    UpdateCDScaleDisplay = function()
        local s = (CleveRoidMacros and CleveRoidMacros.WarriorCDScale) or 1.0
        cdValText:SetText(string.format("%d%%", math.floor(s * 100 + 0.5)))
    end

    local decCDBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    decCDBtn:SetWidth(22)
    decCDBtn:SetHeight(18)
    decCDBtn:SetPoint("RIGHT", cdValText, "LEFT", -4, 0)
    decCDBtn:SetText("-")

    local cdLabel = settingsPanel:CreateFontString(nil, "OVERLAY")
    cdLabel:SetFont("Fonts\\FRIZQT__.TTF", 10)
    cdLabel:SetWidth(80)
    cdLabel:SetJustifyH("LEFT")
    cdLabel:SetPoint("RIGHT", decCDBtn, "LEFT", -6, 0)
    cdLabel:SetTextColor(1, 1, 1, 1)
    cdLabel:SetText("CD Icons:")

    decCDBtn:SetScript("OnClick", function()
        local cur = (CleveRoidMacros and CleveRoidMacros.WarriorCDScale) or 1.0
        local nextS = cur - 0.05
        if nextS < 0.5 then nextS = 0.5 end
        if CleveRoidMacros then CleveRoidMacros.WarriorCDScale = nextS end
        if ApplyCDGroupScale then ApplyCDGroupScale() end
        if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
    end)

    incCDBtn:SetScript("OnClick", function()
        local cur = (CleveRoidMacros and CleveRoidMacros.WarriorCDScale) or 1.0
        local nextS = cur + 0.05
        if nextS > 2.0 then nextS = 2.0 end
        if CleveRoidMacros then CleveRoidMacros.WarriorCDScale = nextS end
        if ApplyCDGroupScale then ApplyCDGroupScale() end
        if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
    end)

    -- 5. Lock / Unlock Toggle Button (allows dragging/resizing individual icons!)
    local lockBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    lockBtn:SetWidth(174)
    lockBtn:SetHeight(20)
    lockBtn:SetPoint("TOP", settingsPanel, "TOP", 0, -164)
    local function UpdateLockBtnText()
        if isUnlocked then
            lockBtn:SetText("|cffffff00LOCK Icons & Bars|r")
        else
            lockBtn:SetText("Unlock to Move/Size")
        end
    end
    UpdateLockBtnText()
    lockBtn:SetScript("OnClick", function()
        isUnlocked = not isUnlocked
        UpdateLockBtnText()
        UpdateGridVisibility()
        UpdateAuras()
        UpdateWarriorCDs()
        UpdateHUDVisibility()
        if isUnlocked then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r UNLOCKED! Drag any icon to move. Scroll Mouse Wheel to resize. Right-click an icon to reset its size. Click Lock when done.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r LOCKED and positions saved!")
        end
    end)

    -- 6. Alignment Grid ("Fence") Toggle Button
    local gridBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    gridBtn:SetWidth(174)
    gridBtn:SetHeight(20)
    gridBtn:SetPoint("TOP", lockBtn, "BOTTOM", 0, -4)
    local function UpdateGridBtnText()
        if showGrid then
            gridBtn:SetText("Align Grid: |cff20ff20ON|r")
        else
            gridBtn:SetText("Align Grid: |cffff4040OFF|r")
        end
    end
    UpdateGridBtnText()
    gridBtn:SetScript("OnClick", function()
        showGrid = not showGrid
        UpdateGridBtnText()
        UpdateGridVisibility()
    end)

    -- 6b. Top Action Bar Mouseover Fade Toggle Button
    local fadeBarBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    fadeBarBtn:SetWidth(174)
    fadeBarBtn:SetHeight(20)
    fadeBarBtn:SetPoint("TOP", gridBtn, "BOTTOM", 0, -4)
    local function UpdateFadeBarBtnText()
        local isEnabled = CleveRoids_GetTopBarMouseover and CleveRoids_GetTopBarMouseover() or false
        if isEnabled then
            fadeBarBtn:SetText("Top Bar Fade: |cff20ff20ON|r")
        else
            fadeBarBtn:SetText("Top Bar Fade: |cffff4040OFF|r")
        end
    end
    UpdateFadeBarBtnText()
    fadeBarBtn:SetScript("OnClick", function()
        local cur = CleveRoids_GetTopBarMouseover and CleveRoids_GetTopBarMouseover() or false
        local nextState = not cur
        if CleveRoids_SetTopBarMouseover then CleveRoids_SetTopBarMouseover(nextState) end
        UpdateFadeBarBtnText()
    end)

    -- 7. Reset SIZES Only Button (Restores original 26x26 sizes while preserving your positions!)
    local resetSizesBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    resetSizesBtn:SetWidth(174)
    resetSizesBtn:SetHeight(20)
    resetSizesBtn:SetPoint("TOP", fadeBarBtn, "BOTTOM", 0, -4)
    resetSizesBtn:SetText("Reset All Sizes")
    resetSizesBtn:SetScript("OnClick", function()
        curScale = 1.0
        hud:SetScale(1.0)
        sunderIcon:SetWidth(26); sunderIcon:SetHeight(26)
        hamIcon:SetWidth(26);    hamIcon:SetHeight(26)
        msIcon:SetWidth(26);     msIcon:SetHeight(26)
        opIcon:SetWidth(26);     opIcon:SetHeight(26)
        revIcon:SetWidth(26);    revIcon:SetHeight(26)
        demoIcon:SetWidth(26);   demoIcon:SetHeight(26)
        tcIcon:SetWidth(26);     tcIcon:SetHeight(26)
        bsIcon:SetWidth(26);     bsIcon:SetHeight(26)
        rendAuraIcon:SetWidth(26); rendAuraIcon:SetHeight(26)
        rendBar:SetWidth(190);     rendBar:SetHeight(12)
        rageBar:SetWidth(190);   rageBar:SetHeight(14)
        defRow:SetWidth(140);    defRow:SetHeight(28)
        offRow:SetWidth(140);    offRow:SetHeight(28)

        if CleveRoidMacros then
            CleveRoidMacros.WarriorHUDScale = 1.0
            CleveRoidMacros.WarriorCDScale = 1.0
            if CleveRoidMacros.WarriorIconPositions then
                for _, pos in pairs(CleveRoidMacros.WarriorIconPositions) do
                    if type(pos) == "table" then
                        pos.width = nil
                        pos.height = nil
                    end
                end
            end
        end
        if ApplyCDGroupScale then ApplyCDGroupScale() end
        UpdateScaleDisplay()
        UpdateExtraBarScaleDisplay()
        UpdateMainBarScaleDisplay()
        if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
        UpdateAuras()
        UpdateWarriorCDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r All icon and bar sizes reset to standard dimensions!")
    end)

    -- 8. Reset Position & Size Button (Factory Reset)
    local resetBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
    resetBtn:SetWidth(174)
    resetBtn:SetHeight(20)
    resetBtn:SetPoint("TOP", resetSizesBtn, "BOTTOM", 0, -4)
    resetBtn:SetText("Reset All (Pos & Size)")
    resetBtn:SetScript("OnClick", function()
        hud:ClearAllPoints()
        hud:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
        curScale = 1.0
        hud:SetScale(curScale)

        sunderIcon:ClearAllPoints(); sunderIcon:SetPoint("CENTER", UIParent, "CENTER", -72, -75); sunderIcon:SetWidth(26); sunderIcon:SetHeight(26)
        hamIcon:ClearAllPoints();    hamIcon:SetPoint("CENTER", UIParent, "CENTER", -36, -75); hamIcon:SetWidth(26); hamIcon:SetHeight(26)
        msIcon:ClearAllPoints();     msIcon:SetPoint("CENTER", UIParent, "CENTER", 0, -75);   msIcon:SetWidth(26); msIcon:SetHeight(26)
        opIcon:ClearAllPoints();     opIcon:SetPoint("CENTER", UIParent, "CENTER", 36, -75);  opIcon:SetWidth(26); opIcon:SetHeight(26)
        revIcon:ClearAllPoints();    revIcon:SetPoint("CENTER", UIParent, "CENTER", 36, -110); revIcon:SetWidth(26); revIcon:SetHeight(26)
        demoIcon:ClearAllPoints();   demoIcon:SetPoint("CENTER", UIParent, "CENTER", -36, -110); demoIcon:SetWidth(26); demoIcon:SetHeight(26)
        tcIcon:ClearAllPoints();     tcIcon:SetPoint("CENTER", UIParent, "CENTER", 0, -110);   tcIcon:SetWidth(26); tcIcon:SetHeight(26)
        bsIcon:ClearAllPoints();     bsIcon:SetPoint("CENTER", UIParent, "CENTER", 72, -75);   bsIcon:SetWidth(26); bsIcon:SetHeight(26)
        rendAuraIcon:ClearAllPoints(); rendAuraIcon:SetPoint("CENTER", UIParent, "CENTER", 108, -75); rendAuraIcon:SetWidth(26); rendAuraIcon:SetHeight(26)
        rendBar:ClearAllPoints();      rendBar:SetPoint("CENTER", UIParent, "CENTER", 0, -100);  rendBar:SetWidth(190); rendBar:SetHeight(12)
        rageBar:ClearAllPoints();    rageBar:SetPoint("CENTER", UIParent, "CENTER", 0, -146); rageBar:SetWidth(190); rageBar:SetHeight(14)
        defRow:ClearAllPoints();     defRow:SetPoint("CENTER", UIParent, "CENTER", -215, -75); defRow:SetWidth(140); defRow:SetHeight(28)
        offRow:ClearAllPoints();     offRow:SetPoint("CENTER", UIParent, "CENTER", -215, -112); offRow:SetWidth(140); offRow:SetHeight(28)

        if CleveRoidMacros then
            CleveRoidMacros.WarriorHUDPos = nil
            CleveRoidMacros.WarriorHUDScale = 1.0
            CleveRoidMacros.WarriorCDScale = 1.0
            CleveRoidMacros.WarriorIconPositions = nil
        end
        if ApplyCDGroupScale then ApplyCDGroupScale() end
        UpdateScaleDisplay()
        UpdateExtraBarScaleDisplay()
        UpdateMainBarScaleDisplay()
        if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
        UpdateAuras()
        UpdateWarriorCDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r Reset all bars and icons to default.")
    end)

    -- ------------------------------------------------------------------------
    -- TAB 2: Dungeon & Raid Prep (Consumables: 40-50, 50-60)
    -- ------------------------------------------------------------------------
    local CONSUMABLES_DB = {
        [1] = {
            name = "Level 40-50 (ZF, Maraudon, ST, BRD)",
            items = {
                { name = "Monster Omelet", icon = "Interface\\Icons\\INV_Egg_02", cat = "Food", desc = "+12 Stamina & Spirit for 15m", buff = "Well Fed" },
                { name = "Roast Raptor", icon = "Interface\\Icons\\INV_Misc_MonsterMeat_01", cat = "Food", desc = "+12 Stamina & Spirit for 15m", buff = "Well Fed" },
                { name = "Dragonbreath Chili", icon = "Interface\\Icons\\Spell_Fire_Fire", cat = "Food", desc = "Proc Fire damage on melee hits (10m)", buff = "Dragonbreath Chili" },
                { name = "Elixir of Giants", icon = "Interface\\Icons\\INV_Potion_61", cat = "Battle", desc = "+25 Strength for 1 hour (Lvl 38)", buff = "Elixir of Giants" },
                { name = "Elixir of Greater Agility", icon = "Interface\\Icons\\INV_Potion_93", cat = "Battle", desc = "+25 Agility for 1 hour (Lvl 38)", buff = "Elixir of Greater Agility" },
                { name = "Elixir of Ogre's Strength", icon = "Interface\\Icons\\INV_Potion_45", cat = "Battle", desc = "+8 Strength for 1 hour (Lvl 20)", buff = "Elixir of Ogre's Strength" },
                { name = "Elixir of Fortitude", icon = "Interface\\Icons\\INV_Potion_43", cat = "Guardian", desc = "+120 Max Health for 1 hour (Lvl 25)", buff = "Elixir of Fortitude" },
                { name = "Elixir of Greater Defense", icon = "Interface\\Icons\\INV_Potion_86", cat = "Guardian", desc = "+150 Armor for 1 hour (Lvl 29)", buff = "Elixir of Greater Defense" },
                { name = "Solid Sharpening Stone", icon = "Interface\\Icons\\INV_Stone_SharpeningStone_04", cat = "Weapon", desc = "+6 Weapon Damage for 30m (Lvl 35)", buff = "Sharpened" },
                { name = "Solid Weightstone", icon = "Interface\\Icons\\INV_Stone_WeightStone_04", cat = "Weapon", desc = "+6 Blunt Damage for 30m (Lvl 35)", buff = "Weightstone" },
                { name = "Greater Healing Potion", icon = "Interface\\Icons\\INV_Potion_52", cat = "Potion", desc = "Restores 455 to 585 Health (Lvl 35)" },
                { name = "Great Rage Potion", icon = "Interface\\Icons\\INV_Potion_41", cat = "Potion", desc = "Rage +20-40, +30 Strength for 20s", buff = "Great Rage" },
                { name = "Free Action Potion", icon = "Interface\\Icons\\INV_Potion_04", cat = "Potion", desc = "Immune to Stun & Slow for 30s", buff = "Free Action" },
                { name = "Magic Resistance Potion", icon = "Interface\\Icons\\INV_Potion_16", cat = "Potion", desc = "+50 All Magic Resist for 3m (Lvl 32)", buff = "Magic Resistance" },
                { name = "Fire Protection Potion", icon = "Interface\\Icons\\INV_Potion_24", cat = "Protection", desc = "Absorbs 975 to 1625 Fire damage", buff = "Fire Protection" },
                { name = "Nature Protection Potion", icon = "Interface\\Icons\\INV_Potion_22", cat = "Protection", desc = "Absorbs 975 to 1625 Nature damage (Mara/ST)", buff = "Nature Protection" },
                { name = "Shadow Protection Potion", icon = "Interface\\Icons\\INV_Potion_23", cat = "Protection", desc = "Absorbs 675 to 1125 Shadow damage", buff = "Shadow Protection" },
                { name = "Scroll of Strength III", icon = "Interface\\Icons\\INV_Scroll_02", cat = "Scroll", desc = "+13 Strength for 30m", buff = "Strength" },
                { name = "Scroll of Agility III", icon = "Interface\\Icons\\INV_Scroll_02", cat = "Scroll", desc = "+13 Agility for 30m", buff = "Agility" },
                { name = "Scroll of Stamina III", icon = "Interface\\Icons\\INV_Scroll_07", cat = "Scroll", desc = "+13 Stamina for 30m", buff = "Stamina" },
            }
        },
        [2] = {
            name = "Level 50-60 (BRD, LBRS, UBRS, Strat, Scholo, Raids)",
            items = {
                { name = "Smoked Desert Dumplings", icon = "Interface\\Icons\\INV_Misc_Food_64", cat = "Food", desc = "+20 Strength for 15m (Lvl 45)", buff = "Well Fed" },
                { name = "Grilled Squid", icon = "Interface\\Icons\\INV_Misc_Fish_13", cat = "Food", desc = "+10 Agility for 10m (Lvl 35)", buff = "Well Fed" },
                { name = "Blessed Sunfruit", icon = "Interface\\Icons\\INV_Misc_Food_09", cat = "Food", desc = "+10 Strength for 10m (Lvl 45)", buff = "Strength of the Sun" },
                { name = "Dirge's Kickin' Chimaerok Chops", icon = "Interface\\Icons\\INV_Misc_Food_65", cat = "Food", desc = "+25 Stamina for 15m (Lvl 55)", buff = "Well Fed" },
                { name = "Dragonbreath Chili", icon = "Interface\\Icons\\Spell_Fire_Fire", cat = "Food", desc = "Proc Fire damage on melee hits (10m)", buff = "Dragonbreath Chili" },
                { name = "Elixir of the Mongoose", icon = "Interface\\Icons\\INV_Potion_32", cat = "Battle", desc = "+25 Agility & 2% Crit for 1 hr (Lvl 46)", buff = "Elixir of the Mongoose" },
                { name = "Elixir of Giants", icon = "Interface\\Icons\\INV_Potion_61", cat = "Battle", desc = "+25 Strength for 1 hour (Lvl 38)", buff = "Elixir of Giants" },
                { name = "Winterfall Firewater", icon = "Interface\\Icons\\INV_Potion_92", cat = "Battle", desc = "+35 Melee Attack Power for 20m (Lvl 45)", buff = "Winterfall Firewater" },
                { name = "Juju Power", icon = "Interface\\Icons\\INV_Misc_MonsterScales_11", cat = "Battle", desc = "+30 Strength for 30m (Lvl 55)", buff = "Juju Power" },
                { name = "Juju Might", icon = "Interface\\Icons\\INV_Misc_MonsterScales_07", cat = "Battle", desc = "+40 Attack Power for 10m (Lvl 55)", buff = "Juju Might" },
                { name = "Elixir of Superior Defense", icon = "Interface\\Icons\\INV_Potion_66", cat = "Guardian", desc = "+450 Armor for 1 hour (Lvl 43)", buff = "Elixir of Superior Defense" },
                { name = "Elixir of Fortitude", icon = "Interface\\Icons\\INV_Potion_43", cat = "Guardian", desc = "+120 Max Health for 1 hour (Lvl 25)", buff = "Elixir of Fortitude" },
                { name = "Gift of Arthas", icon = "Interface\\Icons\\INV_Potion_28", cat = "Guardian", desc = "+10 Shadow Resist, attackers take +8 phys dmg", buff = "Gift of Arthas" },
                { name = "Flask of the Titans", icon = "Interface\\Icons\\INV_Potion_62", cat = "Flask", desc = "+1200 Max Health for 2 hours (Persists through death)", buff = "Flask of the Titans" },
                { name = "Elemental Sharpening Stone", icon = "Interface\\Icons\\INV_Stone_02", cat = "Weapon", desc = "+2% Melee Critical Strike for 30m (Lvl 50)", buff = "Sharpened" },
                { name = "Dense Sharpening Stone", icon = "Interface\\Icons\\INV_Stone_SharpeningStone_05", cat = "Weapon", desc = "+8 Weapon Damage for 30m (Lvl 50)", buff = "Sharpened" },
                { name = "Dense Weightstone", icon = "Interface\\Icons\\INV_Stone_WeightStone_05", cat = "Weapon", desc = "+8 Blunt Damage for 30m (Lvl 50)", buff = "Weightstone" },
                { name = "Major Healing Potion", icon = "Interface\\Icons\\INV_Potion_54", cat = "Potion", desc = "Restores 1050 to 1750 Health (Lvl 45)" },
                { name = "Mighty Rage Potion", icon = "Interface\\Icons\\INV_Potion_41", cat = "Potion", desc = "Rage +45-75, +60 Strength for 20s (Lvl 46)", buff = "Mighty Rage" },
                { name = "Free Action Potion", icon = "Interface\\Icons\\INV_Potion_04", cat = "Potion", desc = "Immune to Stun & Slow for 30s", buff = "Free Action" },
                { name = "Restorative Potion", icon = "Interface\\Icons\\INV_Potion_01", cat = "Potion", desc = "Dispels 1 magic, curse, poison, disease every 5s", buff = "Restorative Potion" },
                { name = "Living Action Potion", icon = "Interface\\Icons\\INV_Potion_07", cat = "Potion", desc = "Breaks and immune to stuns/movement slows for 5s", buff = "Living Action" },
                { name = "Whipper Root Tuber", icon = "Interface\\Icons\\INV_Misc_Food_55", cat = "Health", desc = "Restores 700 to 900 Health (Separate CD from potions)" },
                { name = "Greater Fire Protection Potion", icon = "Interface\\Icons\\INV_Potion_24", cat = "Protection", desc = "Absorbs 1950 to 3250 Fire damage (MC/Ony)", buff = "Fire Protection" },
                { name = "Greater Nature Protection Potion", icon = "Interface\\Icons\\INV_Potion_22", cat = "Protection", desc = "Absorbs 1950 to 3250 Nature damage (AQ/Strat)", buff = "Nature Protection" },
                { name = "Greater Shadow Protection Potion", icon = "Interface\\Icons\\INV_Potion_23", cat = "Protection", desc = "Absorbs 1950 to 3250 Shadow damage (Scholo/Strat)", buff = "Shadow Protection" },
                { name = "Greater Frost Protection Potion", icon = "Interface\\Icons\\INV_Potion_20", cat = "Protection", desc = "Absorbs 1950 to 3250 Frost damage (Naxx)", buff = "Frost Protection" },
                { name = "Scroll of Strength IV", icon = "Interface\\Icons\\INV_Scroll_02", cat = "Scroll", desc = "+17 Strength for 30m", buff = "Strength" },
                { name = "Scroll of Agility IV", icon = "Interface\\Icons\\INV_Scroll_02", cat = "Scroll", desc = "+17 Agility for 30m", buff = "Agility" },
                { name = "Scroll of Stamina IV", icon = "Interface\\Icons\\INV_Scroll_07", cat = "Scroll", desc = "+17 Stamina for 30m", buff = "Stamina" },
            }
        }
    }

    local activeBracket = 2 -- Default to 50-60
    local prepRows = {}

    local function CountItemInBags(itemName)
        local total = 0
        local target = string.lower(itemName)
        for bag = 0, 4 do
            local size = GetContainerNumSlots(bag)
            if size and size > 0 then
                for slot = 1, size do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        local _, _, name = string.find(link, "%[(.+)%]")
                        if name and string.lower(name) == target then
                            local _, count = GetContainerItemInfo(bag, slot)
                            total = total + (count or 1)
                        end
                    end
                end
            end
        end
        return total
    end

    local function CheckPlayerHasBuff(buffName)
        if not buffName then return false end
        local target = string.lower(buffName)
        if C_UnitAuras and C_UnitAuras.UnitAura then
            for i = 1, 32 do
                local name = C_UnitAuras.UnitAura("player", i, "HELPFUL")
                if not name then break end
                if string.find(string.lower(name), target) then return true end
            end
        end
        if not CleveRoidPrepTip then
            CreateFrame("GameTooltip", "CleveRoidPrepTip", UIParent, "GameTooltipTemplate")
            CleveRoidPrepTip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        for i = 1, 32 do
            CleveRoidPrepTip:ClearLines()
            CleveRoidPrepTip:SetUnitBuff("player", i)
            local line = CleveRoidPrepTipTextLeft1 and CleveRoidPrepTipTextLeft1:GetText()
            if not line then break end
            if string.find(string.lower(line), target) then return true end
        end
        return false
    end

    local function ConsumeItemFromBags(itemName)
        local target = string.lower(itemName)
        for bag = 0, 4 do
            local size = GetContainerNumSlots(bag)
            if size and size > 0 then
                for slot = 1, size do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        local _, _, name = string.find(link, "%[(.+)%]")
                        if name and string.lower(name) == target then
                            UseContainerItem(bag, slot)
                            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Dungeon Prep:|r Used " .. name)
                            return true
                        end
                    end
                end
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Dungeon Prep:|r " .. itemName .. " not found in bags!")
        return false
    end

    -- Bracket selection buttons
    local btnBracket1 = CreateFrame("Button", nil, prepPanel, "UIPanelButtonTemplate")
    btnBracket1:SetWidth(148)
    btnBracket1:SetHeight(22)
    btnBracket1:SetPoint("TOPLEFT", prepPanel, "TOPLEFT", 12, 0)
    btnBracket1:SetText("Lvl 40-50 Bracket")

    local btnBracket2 = CreateFrame("Button", nil, prepPanel, "UIPanelButtonTemplate")
    btnBracket2:SetWidth(148)
    btnBracket2:SetHeight(22)
    btnBracket2:SetPoint("LEFT", btnBracket1, "RIGHT", 8, 0)
    btnBracket2:SetText("Lvl 50-60 Bracket")

    local prepSubText = prepPanel:CreateFontString(nil, "OVERLAY")
    prepSubText:SetFont("Fonts\\FRIZQT__.TTF", 9)
    prepSubText:SetPoint("TOPLEFT", btnBracket1, "BOTTOMLEFT", 2, -4)
    prepSubText:SetTextColor(0.8, 0.8, 0.8, 1)
    prepSubText:SetText("Left-Click any row to consume item from your bags.")

    -- ScrollFrame for consumables
    local prepScroll = CreateFrame("ScrollFrame", "CleveRoidPrepScrollFrame", prepPanel, "FauxScrollFrameTemplate")
    prepScroll:SetWidth(285)
    prepScroll:SetHeight(315)
    prepScroll:SetPoint("TOPLEFT", prepPanel, "TOPLEFT", 12, -42)

    local function RefreshPrepUI()
        local data = CONSUMABLES_DB[activeBracket]
        if not data then return end

        if activeBracket == 1 then
            btnBracket1:SetText("|cff20ff20[ Lvl 40-50 ]|r")
            btnBracket2:SetText("Lvl 50-60 Bracket")
        else
            btnBracket1:SetText("Lvl 40-50 Bracket")
            btnBracket2:SetText("|cff20ff20[ Lvl 50-60 ]|r")
        end

        local items = data.items
        local totalItems = table.getn(items)
        FauxScrollFrame_Update(prepScroll, totalItems, 9, 35)
        local offset = FauxScrollFrame_GetOffset(prepScroll)

        for i = 1, 9 do
            local idx = offset + i
            local row = prepRows[i]
            if idx <= totalItems then
                local item = items[idx]
                row.itemData = item
                row.iconTexture:SetTexture(item.icon)
                row.nameText:SetText(item.name)
                row.descText:SetText(string.format("|cff88bbff[%s]|r %s", item.cat, item.desc))

                local count = CountItemInBags(item.name)
                if count > 0 then
                    row.bagText:SetText(string.format("|cff20ff20x%d in Bags|r", count))
                else
                    row.bagText:SetText("|cffff50500 in Bags|r")
                end

                if item.buff then
                    local active = CheckPlayerHasBuff(item.buff)
                    if active then
                        row.buffText:SetText("|cff20ff20[ACTIVE]|r")
                    else
                        row.buffText:SetText("|cff777777[MISSING]|r")
                    end
                else
                    row.buffText:SetText("")
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    btnBracket1:SetScript("OnClick", function()
        activeBracket = 1
        RefreshPrepUI()
    end)
    btnBracket2:SetScript("OnClick", function()
        activeBracket = 2
        RefreshPrepUI()
    end)

    prepScroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(35, RefreshPrepUI)
    end)

    -- Create 9 item display rows
    for i = 1, 9 do
        local row = CreateFrame("Button", nil, prepPanel)
        row:SetWidth(290)
        row:SetHeight(34)
        if i == 1 then
            row:SetPoint("TOPLEFT", prepScroll, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", prepRows[i - 1], "BOTTOMLEFT", 0, -1)
        end

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetTexture(0.12, 0.12, 0.15, (math.mod(i, 2) == 0) and 0.45 or 0.25)
        row.bg = bg

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetAlpha(0.2)

        local icon = CreateFrame("Button", nil, row)
        icon:SetWidth(26)
        icon:SetHeight(26)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        local iconTex = icon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints(icon)
        row.iconTexture = iconTex

        local iconBorder = icon:CreateTexture(nil, "OVERLAY")
        iconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        iconBorder:SetBlendMode("ADD")
        iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -6, 6)
        iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -6)

        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
        nameText:SetTextColor(1, 0.85, 0.2, 1)
        row.nameText = nameText

        local descText = row:CreateFontString(nil, "OVERLAY")
        descText:SetFont("Fonts\\FRIZQT__.TTF", 8)
        descText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
        descText:SetTextColor(0.75, 0.75, 0.75, 1)
        row.descText = descText

        local bagText = row:CreateFontString(nil, "OVERLAY")
        bagText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        bagText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
        row.bagText = bagText

        local buffText = row:CreateFontString(nil, "OVERLAY")
        buffText:SetFont("Fonts\\FRIZQT__.TTF", 8)
        buffText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
        row.buffText = buffText

        row:SetScript("OnClick", function()
            if this.itemData then
                ConsumeItemFromBags(this.itemData.name)
                RefreshPrepUI()
            end
        end)

        row:SetScript("OnEnter", function()
            if not this.itemData then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine(this.itemData.name, 1, 0.85, 0.2)
            GameTooltip:AddLine(string.format("Category: |cff20ff20%s|r", this.itemData.cat), 1, 1, 1)
            GameTooltip:AddLine(this.itemData.desc, 0.8, 0.8, 0.8, 1)
            local c = CountItemInBags(this.itemData.name)
            if c > 0 then
                GameTooltip:AddLine(string.format("You have |cff20ff20%d|r in your bags. (Left-Click to use)", c), 0.2, 1, 0.2)
            else
                GameTooltip:AddLine("Not currently in your bags.", 1, 0.3, 0.3)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        prepRows[i] = row
    end

    -- Tab Switcher
    local function SwitchTab(tabIdx)
        currentTab = tabIdx
        if currentTab == 1 then
            menu:SetWidth(206)
            menu:SetHeight(345)
            menuTitle:SetText("Warrior Combat HUD")
            tabSettings:SetText("|cff20ff20Settings|r")
            tabPrep:SetText("Dungeon Prep")
            prepPanel:Hide()
            settingsPanel:Show()
            UpdateToggleHudText()
            UpdateSoundBtnText()
            UpdateDebuffBtnText()
            UpdateLockBtnText()
            UpdateGridBtnText()
            UpdateFadeBarBtnText()
            UpdateScaleDisplay()
            UpdateExtraBarScaleDisplay()
            UpdateMainBarScaleDisplay()
            if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
        else
            menu:SetWidth(335)
            menu:SetHeight(430)
            menuTitle:SetText("Dungeon & Raid Consumables")
            tabSettings:SetText("Settings")
            tabPrep:SetText("|cff20ff20Dungeon Prep|r")
            settingsPanel:Hide()
            prepPanel:Show()
            RefreshPrepUI()
        end
    end

    tabSettings:SetScript("OnClick", function() SwitchTab(1) end)
    tabPrep:SetScript("OnClick", function() SwitchTab(2) end)

    local function RefreshMenu()
        if currentTab == 1 then
            UpdateToggleHudText()
            UpdateSoundBtnText()
            UpdateDebuffBtnText()
            UpdateLockBtnText()
            UpdateGridBtnText()
            UpdateFadeBarBtnText()
            UpdateScaleDisplay()
            UpdateExtraBarScaleDisplay()
            UpdateMainBarScaleDisplay()
            if UpdateCDScaleDisplay then UpdateCDScaleDisplay() end
        else
            RefreshPrepUI()
        end
    end

    -- ------------------------------------------------------------------------
    -- 6. Minimap Button (Circular, Draggable around Minimap)
    -- ------------------------------------------------------------------------
    local mmBtn = CreateFrame("Button", "CleveRoidWarriorMinimapBtn", Minimap)
    mmBtn:SetWidth(32)
    mmBtn:SetHeight(32)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetFrameLevel(8)

    local mmIcon = mmBtn:CreateTexture(nil, "BACKGROUND")
    mmIcon:SetWidth(20)
    mmIcon:SetHeight(20)
    mmIcon:SetPoint("CENTER", mmBtn, "CENTER", 0, 0)
    mmIcon:SetTexture("Interface\\Icons\\Ability_Warrior_DecisiveStrike")

    local mmBorder = mmBtn:CreateTexture(nil, "OVERLAY")
    mmBorder:SetWidth(52)
    mmBorder:SetHeight(52)
    mmBorder:SetPoint("TOPLEFT", mmBtn, "TOPLEFT", 0, 0)
    mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local mmHighlight = mmBtn:CreateTexture(nil, "HIGHLIGHT")
    mmHighlight:SetWidth(32)
    mmHighlight:SetHeight(32)
    mmHighlight:SetPoint("CENTER", mmBtn, "CENTER", 0, 0)
    mmHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mmHighlight:SetBlendMode("ADD")

    local mmAngle = (CleveRoidMacros and CleveRoidMacros.MinimapAngle) or 3.4
    local function UpdateMinimapPos(angle)
        local rad = 80
        local x = math.cos(angle) * rad
        local y = math.sin(angle) * rad
        mmBtn:ClearAllPoints()
        mmBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    UpdateMinimapPos(mmAngle)

    mmBtn:RegisterForDrag("LeftButton")
    mmBtn:SetScript("OnDragStart", function() this.isDragging = true end)
    mmBtn:SetScript("OnDragStop", function() this.isDragging = false end)
    mmBtn:SetScript("OnUpdate", function()
        if this.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.atan2(cy - my, cx - mx)
            UpdateMinimapPos(angle)
            if CleveRoidMacros then CleveRoidMacros.MinimapAngle = angle end
        end
    end)

    mmBtn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            audioPing = not audioPing
            if CleveRoidMacros then CleveRoidMacros.WarriorHUDAudio = audioPing end
            local state = audioPing and "|cff20ff20ON|r" or "|cffff4040OFF|r"
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warrior HUD:|r Slam Audio Ping is now " .. state)
            RefreshMenu()
        else
            if menu:IsShown() then
                menu:Hide()
            else
                RefreshMenu()
                menu:Show()
            end
        end
    end)
    mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    mmBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffff4040Warrior Combat HUD|r")
        GameTooltip:AddLine("|cffffffffLeft-Click:|r Open Settings (Size/Sound/Toggles)", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("|cffffffffRight-Click:|r Toggle Audio Ping (ON/OFF)", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("|cffffffffDrag Button:|r Move around Minimap", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("|cffffffffShift + Drag HUD:|r Move HUD on screen", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Slash Commands: /hud or /rb or /swing
    SLASH_CLEVEROID_HUD1 = "/hud"
    SLASH_CLEVEROID_HUD2 = "/swing"
    SLASH_CLEVEROID_HUD3 = "/rb"
    SLASH_CLEVEROID_HUD4 = "/ragebar"
    SLASH_CLEVEROID_HUD5 = "/clever"
    SlashCmdList.CLEVEROID_HUD = function(msg)
        RefreshMenu()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end

    if CleveRoidMacros and CleveRoidMacros.WarriorHUDVisible == false then
        hud:Hide()
        rageBar:Hide()
    else
        UpdateRageDisplay()
        UpdateAuras()
        rageBar:Show()
        UpdateHUDVisibility()
    end
end

local warriorHudInitFrame = CreateFrame("Frame")
warriorHudInitFrame:RegisterEvent("PLAYER_LOGIN")
warriorHudInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
warriorHudInitFrame:SetScript("OnEvent", function()
    InitWarriorCombatHUD()
end)

-- Apply temporary weapon enchants (poisons, oils, sharpening stones, etc.)
-- Usage: /applymain [conditionals] ItemName
-- Usage: /applyoff [conditionals] ItemName
-- Example: /applymain [nomhimbue] Instant Poison
-- Example: /applyoff [combat] Crippling Poison

local function FindItemInBags(itemName)
    -- Require a non-empty item name to prevent matching everything
    if not itemName or itemName == "" then
        return nil
    end

    local searchName = string.lower(itemName)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                local foundName = C_Item.GetItemNameByID(id)
                if foundName and string.find(string.lower(foundName), searchName, 1, true) then
                    return bag, slot, foundName
                end
            end
        end
    end
    return nil
end

function CleveRoids.DoFeedPet(msg)
    -- Check macro stop flags
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then
        return false
    end

    local action = function(itemName)
        -- Defensive: make sure we are not in "split stack" mode and nothing is on the cursor
        if type(CloseStackSplitFrame) == "function" then CloseStackSplitFrame() end
        if CursorHasItem and CursorHasItem() then ClearCursor() end

        local _, isHunterPet = HasPetUI()
        if not isHunterPet or not UnitExists("pet") or UnitHealth("pet") <= 0 then
            return false
        end

        local bag, bagSlot = FindItemInBags(itemName)
        if not bag then
            CleveRoids.Print("Item not found: " .. itemName)
            return false
        end

        local feedPet = C_Spell.GetSpellName(6991) or "Feed Pet"
        CastSpellByName(feedPet)

        -- Only apply the food if Feed Pet actually entered item-targeting mode.
        if SpellIsTargeting and not SpellIsTargeting() then
            return false
        end

        PickupContainerItem(bag, bagSlot)
        return true
    end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], action, CleveRoids.FixEmptyTarget, false, action) then
            -- If /firstaction was used, stop macro evaluation after first successful feed
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

function CleveRoids.DoApply(hand, msg)
    local weaponSlots = {
        ["main"] = 16,
        ["off"] = 17,
    }

    local slot = weaponSlots[hand]
    if not slot then
        CleveRoids.Print("Invalid hand: " .. tostring(hand))
        return false
    end

    local action = function(itemName)
        local bag, bagSlot, foundName = FindItemInBags(itemName)
        if not bag then
            CleveRoids.Print("Item not found: " .. itemName)
            return false
        end

        -- Apply the item to the weapon
        UseContainerItem(bag, bagSlot)
        PickupInventoryItem(slot)
        ReplaceEnchant()
        ClearCursor()
        return true
    end

    local handled = false
    for _, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            -- If /firstaction was used, stop macro evaluation after first successful apply
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            handled = true
            break
        end
    end
    return handled
end

SLASH_FEEDPET1 = "/feedpet"
SlashCmdList.FEEDPET = function(msg)
    -- Require an item name argument
    if not msg or msg == "" or string.gsub(msg, "%s+", "") == "" then
        CleveRoids.Print("Usage: /feedpet [conditionals] ItemName")
        return
    end
    CleveRoids.DoFeedPet(msg)
end

SLASH_APPLYMAIN1 = "/applymain"
SlashCmdList.APPLYMAIN = function(msg)
    -- Require an item name argument
    if not msg or msg == "" or string.gsub(msg, "%s+", "") == "" then
        CleveRoids.Print("Usage: /applymain [conditionals] ItemName")
        return
    end
    CleveRoids.DoApply("main", msg)
end

SLASH_APPLYOFF1 = "/applyoff"
SlashCmdList.APPLYOFF = function(msg)
    -- Require an item name argument
    if not msg or msg == "" or string.gsub(msg, "%s+", "") == "" then
        CleveRoids.Print("Usage: /applyoff [conditionals] ItemName")
        return
    end
    CleveRoids.DoApply("off", msg)
end

-- =========================================================================
-- TANK STATS CALCULATOR (/tankstats, /defcap)
-- Calculates Defense Cap (440) and 102.4% Uncrushable Combat Table vs Lv 63 Boss
-- =========================================================================
local function PrintTankStats()
    local playerLvl = UnitLevel("player") or 60
    local baseDef, modDef = UnitDefense("player")
    baseDef = baseDef or (playerLvl * 5)
    modDef = modDef or 0
    local totalDef = baseDef + modDef
    local defOver = totalDef - (playerLvl * 5)

    -- Level 63 raid boss has +3 levels over a Level 60 player
    local bossLvl = 63
    local lvlDiff = bossLvl - playerLvl
    if lvlDiff < 0 then lvlDiff = 0 end

    -- Boss base crit = 5.0% + (lvlDiff * 0.2%) = 5.6%
    -- Defense needed: 5.6% / 0.04% = 140 defense above base (440 total at lv 60)
    local defNeeded = 140
    local defCap = (playerLvl * 5) + defNeeded
    local critReduction = defOver * 0.04
    local bossCritChance = (5.0 + (lvlDiff * 0.2)) - critReduction
    if bossCritChance < 0 then bossCritChance = 0 end

    local dodge = GetDodgeChance and GetDodgeChance() or 0
    local parry = GetParryChance and GetParryChance() or 0
    local block = GetBlockChance and GetBlockChance() or 0
    local miss = 5.0 + (defOver * 0.04)

    local sheetTotal = miss + dodge + parry + block
    local sheetWithSB = sheetTotal + 75.0

    -- Effective avoidance vs Level 63 boss (each penalized by lvlDiff * 0.2% = 0.6%)
    local bossPenalty = lvlDiff * 0.2 -- 0.6%
    local effMiss = math.max(0, miss - bossPenalty)
    local effDodge = math.max(0, dodge - bossPenalty)
    local effParry = math.max(0, parry - bossPenalty)
    local effBlock = math.max(0, block - bossPenalty)
    local effTotal = effMiss + effDodge + effParry + effBlock
    local effWithSB = effTotal + 75.0

    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100========== [TANK DEFENSE & AVOIDANCE STATS] ==========|r")
    local defColor = totalDef >= defCap and "|cFF00FF00" or "|cFFFF4444"
    local defStatus = totalDef >= defCap and "[CRIT IMMUNE!]" or string.format("[Need +%d Def]", defCap - totalDef)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFFDefense Skill:|r %s%d / %d|r  %s%s|r (Boss Crit Chance: %.2f%%)", defColor, totalDef, defCap, defColor, defStatus, bossCritChance))

    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFFCharacter Sheet:|r Miss: |cFF00FFCC%.2f%%|r | Dodge: |cFF00FFCC%.2f%%|r | Parry: |cFF00FFCC%.2f%%|r | Block: |cFF00FFCC%.2f%%|r", miss, dodge, parry, block))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFFSheet Passive Avoidance:|r |cFFFFFF00%.2f%%|r  (Target: |cFFFFFFFF>= 27.40%%|r to be Crush Immune with Shield Block)", sheetTotal))

    local crushColor = sheetWithSB >= 102.4 and "|cFF00FF00" or "|cFFFF4444"
    local crushStatus = sheetWithSB >= 102.4 and "[CRUSH IMMUNE with Shield Block!]" or string.format("[Need +%.2f%% more avoidance]", 102.4 - sheetWithSB)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFFWith Shield Block (+75%%):|r %s%.2f%% / 102.40%%|r  %s%s|r", crushColor, sheetWithSB, crushColor, crushStatus))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFF888888(Vs Lv63 Boss: Miss: %.2f%%, Dodge: %.2f%%, Parry: %.2f%%, Block: %.2f%% -> Total: %.2f%% / 100%%)|r", effMiss, effDodge, effParry, effBlock, effWithSB))
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100=======================================================|r")
end

SLASH_TANKSTATS1 = "/tankstats"
SLASH_TANKSTATS2 = "/defcap"
SlashCmdList.TANKSTATS = function()
    PrintTankStats()
end

SLASH_PROTTALENTS1 = "/prottalents"
SlashCmdList.PROTTALENTS = function()
    local num = GetNumTalents and GetNumTalents(3) or 0
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100========== [PROTECTION TALENTS ON OKTOWOW] ==========|r")
    for i = 1, num do
        local name, icon, tier, col, cur, max = GetTalentInfo(3, i)
        if name then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFFFFRow %d, Col %d:|r |cFF00FFCC%s|r (Max: %d)", tier, col, name, max))
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100=======================================================|r")
end









