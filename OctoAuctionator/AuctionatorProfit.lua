local addonName, addonTable = "Auctionator", AtrNS;
local zc = addonTable and addonTable.zc or {};

----------------------------------------------------------------------
-- Global Data & SavedVariables
----------------------------------------------------------------------
AUCTIONATOR_HISTORICAL_DB = AUCTIONATOR_HISTORICAL_DB or {}
AUCTIONATOR_SAVED_RECIPES = AUCTIONATOR_SAVED_RECIPES or {}
AUCTIONATOR_IGNORED_RECIPES = AUCTIONATOR_IGNORED_RECIPES or {}
AUCTIONATOR_AUTO_OPEN_ADVISOR = (AUCTIONATOR_AUTO_OPEN_ADVISOR == nil) and true or AUCTIONATOR_AUTO_OPEN_ADVISOR
AUCTIONATOR_WATCHLIST = AUCTIONATOR_WATCHLIST or {
	"Iron Ore", "Iron Bar", "Heavy Stone", "Heavy Grinding Stone",
	"Solid Stone", "Solid Grinding Stone", "Mithril Ore", "Mithril Bar",
	"Silk Cloth", "Mageweave Cloth", "Elemental Earth", "Elemental Fire",
	"Grave Moss", "Fadeleaf", "Free Action Potion", "Savory Deviate Delight",
	"Gold Bar", "Steel Bar"
}
AUCTIONATOR_SNIPE_MIN_PROFIT = AUCTIONATOR_SNIPE_MIN_PROFIT or 2000 -- Default: 20 silver (2000 copper)
AUCTIONATOR_SNIPE_MIN_DISCOUNT = AUCTIONATOR_SNIPE_MIN_DISCOUNT or 20 -- Default: 20%
AUCTIONATOR_CRAFT_ONLY_PROFITABLE = (AUCTIONATOR_CRAFT_ONLY_PROFITABLE == nil) and true or AUCTIONATOR_CRAFT_ONLY_PROFITABLE

-- Fixed Vendor Reagents (in copper) - items bought from NPC trade vendors
local VENDOR_REAGENTS = {
	["Weak Flux"] = 20, ["Strong Flux"] = 2000, ["Heavy Stock"] = 200,
	["Solid Stock"] = 1000, ["Coal"] = 500, ["Coarse Thread"] = 10,
	["Fine Thread"] = 100, ["Silken Thread"] = 500, ["Heavy Silken Thread"] = 2000,
	["Rune Thread"] = 5000, ["Gray Dye"] = 25, ["Bleach"] = 25,
	["Black Dye"] = 100, ["Red Dye"] = 100, ["Blue Dye"] = 100,
	["Yellow Dye"] = 100, ["Green Dye"] = 100, ["Purple Dye"] = 250,
	["Salt"] = 10, ["Empty Vial"] = 4, ["Leaded Vial"] = 30,
	["Crystal Vial"] = 400, ["Imbued Vial"] = 1600, ["Soothing Spices"] = 16,
	["Hot Spices"] = 20, ["Refreshing Spring Water"] = 25, ["Simple Wood"] = 38,
	["Star Wood"] = 500, ["Simple Grinder"] = 500, ["Jeweler's Kit"] = 800,
	["Mild Spices"] = 10,
}

-- Curated high-velocity market commodities for fast targeted sniping (15-20s scan)
local CURATED_SNIPE_TARGETS = {
	-- High Velocity Metals & Stones
	"Copper Bar", "Bronze Bar", "Iron Ore", "Iron Bar", "Heavy Stone", "Heavy Grinding Stone",
	"Steel Bar", "Gold Bar", "Mithril Ore", "Mithril Bar", "Solid Stone", "Solid Grinding Stone",
	"Truesilver Bar", "Thorium Ore", "Thorium Bar", "Dense Stone", "Dense Grinding Stone",
	"Arcanite Bar", "Silver Bar",

	-- High Velocity Cloth
	"Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth", "Felcloth", "Mooncloth",

	-- High Velocity Leather & Hides
	"Medium Leather", "Heavy Leather", "Thick Leather", "Rugged Leather", "Cured Rugged Hide",

	-- High Velocity Herbs
	"Swiftthistle", "Briarthorn", "Bruiseweed", "Wild Steelbloom", "Grave Moss", "Kingsblood",
	"Fadeleaf", "Goldthorn", "Liferoot", "Khadgar's Whisker", "Firebloom", "Purple Lotus",
	"Blindweed", "Ghost Mushroom", "Gromsblood", "Dreamfoil", "Black Lotus",

	-- Elementals & Gems
	"Elemental Earth", "Elemental Fire", "Elemental Water", "Elemental Air",
	"Essence of Fire", "Essence of Water", "Essence of Earth", "Essence of Undeath",
	"Lesser Moonstone", "Jade", "Citrine", "Star Ruby", "Aquamarine", "Large Opal", "Righteous Orb",

	-- High Demand Potions & Consumables
	"Free Action Potion", "Greater Healing Potion", "Superior Healing Potion", "Major Healing Potion",
	"Greater Mana Potion", "Superior Mana Potion", "Major Mana Potion", "Elixir of Giants",
	"Elixir of Fortitude", "Elixir of the Mongoose", "Elixir of Greater Agility", "Greater Stoneshield Potion",
	"Savory Deviate Delight",

	-- Popular Trade Recipes
	"Recipe: Savory Deviate Delight", "Recipe: Free Action Potion", "Recipe: Elixir of Ogre's Strength",
	"Recipe: Greater Stoneshield Potion", "Recipe: Greater Nature Protection Potion", "Recipe: Greater Fire Protection Potion",
	"Plans: Steel Weapon Chain", "Plans: Iron Counterweight", "Plans: Mithril Spurs"
}

----------------------------------------------------------------------
-- Historical Price Tracking & Data Freshness
----------------------------------------------------------------------
function Atr_RecordItemNoListings(itemName)
	if not itemName or itemName == "" then return end
	if not AUCTIONATOR_HISTORICAL_DB then AUCTIONATOR_HISTORICAL_DB = {} end
	local key = string.lower(itemName)
	local entry = AUCTIONATOR_HISTORICAL_DB[key]
	if entry then
		entry.current = 0
		entry.noListings = true
		entry.lastScan = time()
	end
end

function Atr_RecordHistoricalPrice(itemName, newPrice)
	if not itemName or not newPrice or newPrice <= 0 then return end
	if not AUCTIONATOR_HISTORICAL_DB then AUCTIONATOR_HISTORICAL_DB = {} end

	local key = string.lower(itemName)
	local now = time()
	local entry = AUCTIONATOR_HISTORICAL_DB[key]

	if not entry then
		entry = {
			name = itemName,
			current = newPrice,
			prev = newPrice,
			trend = 0,
			trendPct = 0,
			min = newPrice,
			max = newPrice,
			avg = newPrice,
			seenCount = 1,
			lastScan = now,
			noListings = nil,
			history = { { t = now, p = newPrice } }
		}
		AUCTIONATOR_HISTORICAL_DB[key] = entry
	else
		entry.noListings = nil
		-- Update trend if price changed or at least 30 mins since last recorded
		if entry.current ~= newPrice or (now - (entry.lastScan or 0) >= 1800) then
			-- Anti-Troll Clamp: If price is > 4x established average, don't let it distort the market average
			local clampedPrice = newPrice
			if entry.seenCount >= 3 and entry.avg > 0 and newPrice > (entry.avg * 4) then
				clampedPrice = entry.avg * 2 -- cap inflation
			end

			entry.prev = entry.current
			entry.current = newPrice
			entry.trend = newPrice - entry.prev
			if entry.prev > 0 then
				entry.trendPct = math.floor(((newPrice - entry.prev) / entry.prev) * 100)
			else
				entry.trendPct = 0
			end
			if newPrice < (entry.min or newPrice) then entry.min = newPrice end
			if newPrice > (entry.max or newPrice) then entry.max = newPrice end
			entry.seenCount = (entry.seenCount or 1) + 1
			entry.avg = math.floor(((entry.avg * (entry.seenCount - 1)) + clampedPrice) / entry.seenCount)
			entry.lastScan = now

			if not entry.history then entry.history = {} end
			table.insert(entry.history, { t = now, p = newPrice })
			if table.getn(entry.history) > 12 then
				table.remove(entry.history, 1)
			end
		end
	end
end

function Atr_GetHistoricalData(itemName)
	if not itemName or not AUCTIONATOR_HISTORICAL_DB then return nil end
	return AUCTIONATOR_HISTORICAL_DB[string.lower(itemName)]
end

function Atr_GetFreshnessText(lastScanTime, isLive)
	if isLive then return "|cff00ff00[Live]|r" end
	if not lastScanTime or lastScanTime == 0 then return "|cff888888[No Data]|r" end
	local ageSec = time() - lastScanTime
	if ageSec < 300 then
		return "|cff00ff00[<5m]|r"
	elseif ageSec < 3600 then
		local m = math.floor(ageSec / 60)
		return string.format("|cff00ffff[%dm ago]|r", m)
	elseif ageSec < 86400 then
		local h = math.floor(ageSec / 3600)
		return string.format("|cffffcc00[%dh ago]|r", h)
	else
		local d = math.floor(ageSec / 86400)
		return string.format("|cffff4444[%dd ago]|r", d)
	end
end

function Atr_MigrateExistingScanDB()
	if not gAtr_ScanDB then return end
	if not AUCTIONATOR_HISTORICAL_DB then AUCTIONATOR_HISTORICAL_DB = {} end

	local migrated = 0
	local now = time()
	for itemName, price in pairs(gAtr_ScanDB) do
		if type(price) == "number" and price > 0 then
			local key = string.lower(itemName)
			if not AUCTIONATOR_HISTORICAL_DB[key] then
				AUCTIONATOR_HISTORICAL_DB[key] = {
					name = itemName,
					current = price,
					prev = price,
					trend = 0,
					trendPct = 0,
					min = price,
					max = price,
					avg = price,
					seenCount = 1,
					lastScan = now,
					history = { { t = now, p = price } }
				}
				migrated = migrated + 1
			end
		end
	end
	if migrated > 0 and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[Auctionator Advisor]|r Migrated %d historical price entries.", migrated))
	end
end

function Atr_GetMaterialCost(itemName)
	if not itemName or itemName == "" then return 0 end
	if VENDOR_REAGENTS[itemName] then
		return VENDOR_REAGENTS[itemName]
	end
	if gAtr_ScanDB and gAtr_ScanDB[itemName] and gAtr_ScanDB[itemName] > 0 then
		return gAtr_ScanDB[itemName]
	end
	local hist = Atr_GetHistoricalData(itemName)
	if hist then
		if hist.noListings then return 0 end
		if hist.current and hist.current > 0 then return hist.current end
		if hist.avg and hist.avg > 0 then return hist.avg end
		if hist.prev and hist.prev > 0 then return hist.prev end
	end
	if Atr_GetAuctionPrice then
		local ap = Atr_GetAuctionPrice(itemName)
		if ap and ap > 0 then return ap end
	end
	return 0
end

----------------------------------------------------------------------
-- Item Resolution & Icon/Stats Cache (1.12.1 + AtlasLoot Bridge)
----------------------------------------------------------------------
local AtlasIndex = nil

local function Atr_BuildAtlasIndex()
	if AtlasIndex then return end
	AtlasIndex = {}
	if not AtlasLoot_Data then return end

	local tables = {
		"AtlasLootCrafting",
		"AtlasLootItems",
		"AtlasLootWBItems",
		"AtlasLootSetItems",
		"AtlasLootRepItems",
		"AtlasLootBGItems",
		"AtlasLootGeneralPvPItems",
		"AtlasLootWorldEvents",
	}

	for _, tblName in ipairs(tables) do
		local ds = AtlasLoot_Data[tblName]
		if type(ds) == "table" then
			for _, section in pairs(ds) do
				if type(section) == "table" then
					for _, entry in ipairs(section) do
						if type(entry) == "table" and entry[2] and entry[3] then
							local rawName = entry[3]
							if type(rawName) == "string" and rawName ~= "" then
								local _, _, qStr = string.find(rawName, "=q(%d)=")
								local clean = string.gsub(rawName, "=q%d=", "")
								clean = string.gsub(clean, "=ds=", "")
								clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
								local lowerName = string.lower(clean)

								if not AtlasIndex[lowerName] then
									local icon = entry[2]
									if type(icon) == "string" and icon ~= "" then
										if not string.find(icon, "\\") then
											icon = "Interface\\Icons\\" .. icon
										end
									else
										icon = nil
									end

									local itemID = entry[1]
									local realID = (type(itemID) == "number" and itemID > 0) and itemID or nil
									if not realID and type(itemID) == "string" then
										local _, _, num = string.find(itemID, "^(%d+)$")
										if num then realID = tonumber(num) end
									end

									AtlasIndex[lowerName] = {
										name = clean,
										icon = icon,
										quality = qStr and tonumber(qStr) or 1,
										id = realID,
										link = realID and string.format("item:%d:0:0:0", realID) or nil
									}
								end
							end
						end
					end
				end
			end
		end
	end
end

function Atr_ResolveItem(nameOrLink)
	if not nameOrLink or nameOrLink == "" then
		return nil, nil, nil, nil
	end

	-- 1. Try Atr_GetItemInfo if available (from Compat.lua)
	if Atr_GetItemInfo then
		local name, link, quality, ilevel, minLevel, itemType, subType, stack, equip, texture = Atr_GetItemInfo(nameOrLink)
		if texture or link then
			return name, link, quality, texture
		end
	end

	-- 2. Try native 1.12.1 GetItemInfo (identifier can be name, itemID, or link)
	local a, b, c, d, e, f, g, h, i, j = GetItemInfo(nameOrLink)
	if a then
		local link = b
		local quality = c
		local texture = (type(e) == "string") and i or (j or i)
		return a, link, quality, texture
	end

	-- 3. If nameOrLink contains "item:ID", try explicit "item:ID:0:0:0"
	if type(nameOrLink) == "string" then
		local _, _, id = string.find(nameOrLink, "item:(%d+)")
		if id then
			local a, b, c, d, e, f, g, h, i, j = GetItemInfo("item:" .. id .. ":0:0:0")
			if a then
				local link = b
				local quality = c
				local texture = (type(e) == "string") and i or (j or i)
				return a, link, quality, texture
			end
		end
	end

	-- 4. Check AtlasLoot index fallback
	Atr_BuildAtlasIndex()
	if AtlasIndex and type(nameOrLink) == "string" then
		local clean = string.gsub(nameOrLink, "|c%x%x%x%x%x%x%x%x", "")
		clean = string.gsub(clean, "|r", "")
		clean = string.gsub(clean, "%[", "")
		clean = string.gsub(clean, "%]", "")
		clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
		local hit = AtlasIndex[string.lower(clean)]
		if hit then
			if hit.id then
				local a, b, c, d, e, f, g, h, i, j = GetItemInfo("item:" .. hit.id .. ":0:0:0")
				if a then
					local texture = (type(e) == "string") and i or (j or i)
					return a, b, c, texture or hit.icon
				end
			end
			return hit.name, hit.link, hit.quality, hit.icon
		end
	end

	-- 5. Check AUCTIONATOR_SAVED_RECIPES cache
	if AUCTIONATOR_SAVED_RECIPES and type(nameOrLink) == "string" then
		for _, charRecipes in pairs(AUCTIONATOR_SAVED_RECIPES) do
			if type(charRecipes) == "table" and charRecipes[nameOrLink] then
				local cr = charRecipes[nameOrLink]
				if cr.icon or cr.link then
					return cr.name, cr.link, nil, cr.icon
				end
			end
		end
	end

	return nil, nil, nil, nil
end

----------------------------------------------------------------------
-- Profession Recipe Learning & Crafting Profit Engine
----------------------------------------------------------------------
local isScanningTradeSkill = false
local function ScanOpenTradeSkill()
	if isScanningTradeSkill then return end
	if not GetNumTradeSkills then return end
	local numSkills = GetNumTradeSkills()
	if not numSkills or numSkills <= 0 then return end

	isScanningTradeSkill = true

	local pName = UnitName("player") or "Player"
	if not AUCTIONATOR_SAVED_RECIPES then
		AUCTIONATOR_SAVED_RECIPES = {}
	end
	if not AUCTIONATOR_SAVED_RECIPES[pName] then
		AUCTIONATOR_SAVED_RECIPES[pName] = {}
	end

	local skillHeader = (GetTradeSkillLine and GetTradeSkillLine()) or "Profession"
	local newlyLearned = 0

	pcall(function()
		for i = 1, numSkills do
			local skillName, skillType = GetTradeSkillInfo(i)
			if skillType and skillType ~= "header" and skillName then
				local itemLink = GetTradeSkillItemLink(i)
				local skillIcon = (GetTradeSkillIcon and GetTradeSkillIcon(i)) or nil
				local minMade, maxMade = GetTradeSkillNumMade(i)
				local avgMade = ((minMade or 1) + (maxMade or 1)) / 2
				local numReagents = GetTradeSkillNumReagents(i) or 0

				local reagents = {}
				if type(numReagents) == "number" and numReagents > 0 then
					for r = 1, numReagents do
						local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
						if rName then
							table.insert(reagents, { name = rName, count = rCount or 1 })
						end
					end
				end

				if not skillIcon or string.find(skillIcon, "INV_Misc_QuestionMark") then
					local _, resLink, _, resIcon = Atr_ResolveItem(itemLink or skillName)
					if resIcon and not string.find(resIcon, "INV_Misc_QuestionMark") then
						skillIcon = resIcon
					end
					if not itemLink and resLink then
						itemLink = resLink
					end
				end

				if skillName and itemLink and Atr_RememberItemLink then
					Atr_RememberItemLink(skillName, itemLink)
				end

				if not AUCTIONATOR_SAVED_RECIPES[pName][skillName] then
					newlyLearned = newlyLearned + 1
				end

				AUCTIONATOR_SAVED_RECIPES[pName][skillName] = {
					name = skillName,
					profession = skillHeader,
					link = itemLink,
					icon = skillIcon,
					avgMade = avgMade,
					reagents = reagents
				}
			end
		end
	end)

	isScanningTradeSkill = false

	if newlyLearned > 0 and DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Auctionator Advisor]|r Learned " .. newlyLearned .. " new recipes for " .. skillHeader .. ".")
	end
end

function Atr_GetNumIgnoredRecipes()
	local pName = UnitName("player") or "Player"
	local ignored = AUCTIONATOR_IGNORED_RECIPES and AUCTIONATOR_IGNORED_RECIPES[pName]
	if not ignored then return 0 end
	local count = 0
	for _ in pairs(ignored) do count = count + 1 end
	return count
end

function Atr_RestoreIgnoredRecipes()
	local pName = UnitName("player") or "Player"
	if AUCTIONATOR_IGNORED_RECIPES then
		AUCTIONATOR_IGNORED_RECIPES[pName] = {}
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Auctionator Advisor]|r Restored all hidden recipes to the profit list.")
	end
	Atr_RefreshProfitUI()
end

function Atr_CalculateRecipeProfits()
	local pName = UnitName("player") or "Player"
	local recipes = AUCTIONATOR_SAVED_RECIPES[pName]
	if not recipes then return {} end

	local ignored = (AUCTIONATOR_IGNORED_RECIPES and AUCTIONATOR_IGNORED_RECIPES[pName]) or {}
	local results = {}

	for name, rec in pairs(recipes) do
		if not ignored[name] then
			local craftCost = 0
			local hasAllPrices = true

			for _, reg in ipairs(rec.reagents) do
				local cost = Atr_GetMaterialCost(reg.name)
				if cost == 0 then
					hasAllPrices = false
				end
				craftCost = craftCost + (cost * (reg.count or 1))
			end

			local prodName = rec.name
			if rec.link then
				local _, _, linkItem = string.find(rec.link, "%[(.+)%]")
				if linkItem and linkItem ~= "" then
					prodName = linkItem
				end
			end
			if string.find(rec.name, "^Smelt ") then
				prodName = string.gsub(rec.name, "^Smelt ", "") .. " Bar"
			end

			local sellPrice = Atr_GetMaterialCost(prodName)
			local hist = Atr_GetHistoricalData(prodName)
			local hasListings = (sellPrice > 0) and (not hist or not hist.noListings)

			local netRevenue = 0
			local profit = 0
			local margin = 0

			if hasListings and craftCost > 0 then
				netRevenue = math.floor((sellPrice * (rec.avgMade or 1)) * 0.95) -- 5% AH cut
				profit = netRevenue - craftCost
				margin = math.floor((profit / craftCost) * 100)
			end

			table.insert(results, {
				name = rec.name,
				productName = prodName,
				profession = rec.profession or "Profession",
				link = rec.link,
				icon = rec.icon,
				avgMade = rec.avgMade or 1,
				craftCost = craftCost,
				sellPrice = sellPrice,
				netRevenue = netRevenue,
				profit = profit,
				margin = margin,
				hasAllPrices = hasAllPrices,
				hasListings = hasListings,
				lastScan = hist and hist.lastScan,
				reagents = rec.reagents
			})
		end
	end

	-- Sort: highest profit first
	table.sort(results, function(a, b)
		if a.hasListings ~= b.hasListings then
			return a.hasListings
		end
		return (a.profit or 0) > (b.profit or 0)
	end)

	return results
end

----------------------------------------------------------------------
-- Live AH Deal & Sniping Engine
----------------------------------------------------------------------
gAtr_LiveScanDeals = {}
local gAtr_LiveSeenKeys = {}

function Atr_ClearLiveScanDeals()
	gAtr_LiveScanDeals = {}
	gAtr_LiveSeenKeys = {}
end

function Atr_GetItemSnipeCategory(name, quality)
	if not name or name == "" then return "MATS" end

	-- 1. Check GetItemInfo API if cached (100% accurate classification in Vanilla 1.12)
	local gName, gLink, gQuality, gMinLevel, gType, gSubType, gStack, gEquipLoc = GetItemInfo(name)
	if gType then
		if gType == "Armor" or gType == "Weapon" then
			return "GEAR"
		elseif gType == "Recipe" then
			return "RECIPES"
		elseif gEquipLoc and gEquipLoc ~= "" and gEquipLoc ~= "INVTYPE_NON_EQUIP" then
			return "GEAR"
		end
	end

	local lName = string.lower(name)

	-- 2. Check Recipes keywords
	if string.find(lName, "recipe") or string.find(lName, "plans") or string.find(lName, "schematic") or
	   string.find(lName, "pattern") or string.find(lName, "formula") or string.find(lName, "manual") or
	   string.find(lName, "grimoire") or string.find(lName, "tome") or string.find(lName, "book") then
		return "RECIPES"
	end

	-- 3. Comprehensive Armor & Weapon Keywords (handles all Vanilla BoE naming conventions)
	local isGear = false
	if (quality == nil or quality >= 1) then
		if string.find(lName, "pauldrons") or string.find(lName, "spaulders") or string.find(lName, "mantle") or
		   string.find(lName, "epaulets") or string.find(lName, "amice") or string.find(lName, "shoulder") or
		   string.find(lName, "helm") or string.find(lName, "crown") or string.find(lName, "circlet") or
		   string.find(lName, "coif") or string.find(lName, "cowl") or string.find(lName, "cap") or
		   string.find(lName, "headband") or string.find(lName, "mask") or string.find(lName, "monocle") or
		   string.find(lName, "visor") or string.find(lName, "goggles") or string.find(lName, "headdress") or
		   string.find(lName, "breastplate") or string.find(lName, "chestpiece") or string.find(lName, "cuirass") or
		   string.find(lName, "hauberk") or string.find(lName, "tunic") or string.find(lName, "vest") or
		   string.find(lName, "robe") or string.find(lName, "vestment") or string.find(lName, "doublet") or
		   string.find(lName, "raiment") or string.find(lName, "armor") or string.find(lName, "jerkin") or
		   string.find(lName, "bracers") or string.find(lName, "wristguards") or string.find(lName, "cuffs") or
		   string.find(lName, "armwraps") or string.find(lName, "armguards") or string.find(lName, "bindings") or
		   string.find(lName, "bands") or string.find(lName, "wristbands") or
		   string.find(lName, "gloves") or string.find(lName, "gauntlets") or string.find(lName, "handguards") or
		   string.find(lName, "grips") or string.find(lName, "mitts") or string.find(lName, "handwraps") or
		   string.find(lName, "belt") or string.find(lName, "girdle") or string.find(lName, "cinch") or
		   string.find(lName, "sash") or string.find(lName, "cord") or string.find(lName, "clasp") or string.find(lName, "waistband") or
		   string.find(lName, "leggings") or string.find(lName, "legguards") or string.find(lName, "pants") or
		   string.find(lName, "trousers") or string.find(lName, "breeches") or string.find(lName, "kilt") or
		   string.find(lName, "skirt") or string.find(lName, "greaves") or
		   string.find(lName, "boots") or string.find(lName, "sabatons") or string.find(lName, "moccasins") or
		   string.find(lName, "footwraps") or string.find(lName, "shoes") or string.find(lName, "striders") or
		   string.find(lName, "slippers") or
		   string.find(lName, "cloak") or string.find(lName, "cape") or string.find(lName, "drape") or
		   string.find(lName, "shroud") or string.find(lName, "shawl") or
		   string.find(lName, "ring") or string.find(lName, "band") or string.find(lName, "loop") or
		   string.find(lName, "signet") or string.find(lName, "seal") or
		   string.find(lName, "necklace") or string.find(lName, "choker") or string.find(lName, "collar") or
		   string.find(lName, "amulet") or string.find(lName, "medallion") or string.find(lName, "pendant") or
		   string.find(lName, "chain") or string.find(lName, "talisman") or
		   string.find(lName, "shield") or string.find(lName, "buckler") or string.find(lName, "targe") or string.find(lName, "defender") or
		   string.find(lName, "sword") or string.find(lName, "blade") or string.find(lName, "scimitar") or
		   string.find(lName, "rapier") or string.find(lName, "saber") or string.find(lName, "claymore") or
		   string.find(lName, "broadsword") or string.find(lName, "falchion") or string.find(lName, "cutlass") or string.find(lName, "edge") or
		   string.find(lName, "axe") or string.find(lName, "cleaver") or string.find(lName, "chopper") or
		   string.find(lName, "hatchet") or string.find(lName, "battleaxe") or string.find(lName, "waraxe") or
		   string.find(lName, "mace") or string.find(lName, "club") or string.find(lName, "hammer") or
		   string.find(lName, "cudgel") or string.find(lName, "maul") or string.find(lName, "flail") or
		   string.find(lName, "scepter") or string.find(lName, "warhammer") or
		   string.find(lName, "dagger") or string.find(lName, "dirk") or string.find(lName, "stiletto") or
		   string.find(lName, "knife") or string.find(lName, "kris") or string.find(lName, "toothpick") or
		   string.find(lName, "shank") or string.find(lName, "piercer") or
		   string.find(lName, "bow") or string.find(lName, "longbow") or string.find(lName, "shortbow") or
		   string.find(lName, "gun") or string.find(lName, "rifle") or string.find(lName, "musket") or
		   string.find(lName, "blunderbuss") or string.find(lName, "shotgun") or string.find(lName, "crossbow") or string.find(lName, "arbalest") or
		   string.find(lName, "staff") or string.find(lName, "pole") or string.find(lName, "stave") or
		   string.find(lName, "rod") or string.find(lName, "spire") or
		   string.find(lName, "polearm") or string.find(lName, "halberd") or string.find(lName, "spear") or
		   string.find(lName, "pike") or string.find(lName, "lance") or string.find(lName, "trident") or
		   string.find(lName, "wand") or string.find(lName, "baton") then
			isGear = true
		end
	end

	if isGear then
		return "GEAR"
	end

	return "MATS"
end

function Atr_CheckLiveScanDeal(name, itemPrice, buyoutPrice, count, quality, level)
	if not name or name == "" or not itemPrice or itemPrice <= 0 then return end
	-- Ignore vendor-purchased reagents & gray vendor trash
	if VENDOR_REAGENTS[name] then return end
	if quality and quality < 1 then return end

	local key = string.lower(name)
	local hist = Atr_GetHistoricalData(name)
	local avgPrice = (hist and hist.avg and hist.avg > 0 and hist.avg) or (hist and hist.prev and hist.prev > 0 and hist.prev) or 0
	local seenCount = (hist and hist.seenCount) or 0

	-- Category determination
	local category = Atr_GetItemSnipeCategory(name, quality)

	-- Instant BoE snipe fallback if no prior history
	local isInstantSnipe = false
	if quality and quality == 4 and itemPrice <= 200000 then -- Epic BoE under 20g
		isInstantSnipe = true
		if avgPrice == 0 then avgPrice = 500000 end
	elseif quality and quality == 3 and itemPrice <= 20000 then -- Rare BoE under 2g
		isInstantSnipe = true
		if avgPrice == 0 then avgPrice = 50000 end
	end

	local minProfit = AUCTIONATOR_SNIPE_MIN_PROFIT or 2000
	local minDiscount = AUCTIONATOR_SNIPE_MIN_DISCOUNT or 20

	if avgPrice > 0 and (seenCount >= 1 or isInstantSnipe) and itemPrice < avgPrice then
		local expectedNet = math.floor(avgPrice * 0.95)
		local netProfit = expectedNet - itemPrice
		local discountPct = math.floor(((avgPrice - itemPrice) / avgPrice) * 100)

		if (discountPct >= minDiscount and netProfit >= minProfit) or isInstantSnipe then
			local dealType, tag, tagColor, priority
			if netProfit >= 20000 or (quality and quality >= 4) then
				dealType = "EPIC_SNIPE"
				tag = "[EPIC SNIPE]"
				tagColor = "|cffa335ee" -- Epic purple
				priority = 1
			elseif netProfit >= 5000 or (quality and quality == 3) then
				dealType = "GREAT_FLIP"
				tag = "[GREAT FLIP]"
				tagColor = "|cff0070dd" -- Rare blue
				priority = 2
			else
				dealType = "GOOD_FLIP"
				tag = "[FLIP]"
				tagColor = "|cff1eff00" -- Uncommon green
				priority = 3
			end

			local dealEntry = {
				name = name,
				category = category,
				dealType = dealType,
				tag = tag,
				tagColor = tagColor,
				priority = priority,
				curPrice = itemPrice,
				avgPrice = avgPrice,
				netProfit = netProfit,
				discountPct = discountPct,
				seenCount = seenCount,
				isLive = true,
				lastScan = time()
			}

			if gAtr_LiveSeenKeys[key] then
				local idx = gAtr_LiveSeenKeys[key]
				if gAtr_LiveScanDeals[idx] and itemPrice < gAtr_LiveScanDeals[idx].curPrice then
					gAtr_LiveScanDeals[idx] = dealEntry
				end
			else
				table.insert(gAtr_LiveScanDeals, dealEntry)
				gAtr_LiveSeenKeys[key] = table.getn(gAtr_LiveScanDeals)
			end
		end
	end
end

function Atr_GetFlipAnalysis(filterCategory)
	local allDeals = {}
	local counts = { ALL = 0, GEAR = 0, MATS = 0, RECIPES = 0 }
	local seen = {}
	local minProfit = AUCTIONATOR_SNIPE_MIN_PROFIT or 2000
	local minDiscount = AUCTIONATOR_SNIPE_MIN_DISCOUNT or 20

	-- 1. Ingest live scan deals from current session
	if gAtr_LiveScanDeals then
		for _, ld in ipairs(gAtr_LiveScanDeals) do
			if ld.name and ld.name ~= "" and ld.netProfit >= minProfit and ld.discountPct >= minDiscount then
				local k = string.lower(ld.name)
				if not seen[k] then
					seen[k] = true
					ld.category = Atr_GetItemSnipeCategory(ld.name, ld.quality)
					counts.ALL = counts.ALL + 1
					if counts[ld.category] then counts[ld.category] = counts[ld.category] + 1 end
					table.insert(allDeals, ld)
				end
			end
		end
	end

	-- 2. Check candidates from Watchlist, Curated Commodities & Player Recipes
	local function CheckCandidate(itemName)
		if not itemName or itemName == "" then return end
		if VENDOR_REAGENTS[itemName] then return end
		local key = string.lower(itemName)
		if seen[key] then return end

		local hist = Atr_GetHistoricalData(itemName)
		if not hist or (hist.seenCount or 0) < 2 then return end

		-- Hide stale historical listings (> 12 hours old) so old expired items never clutter live view
		if hist.lastScan and (time() - hist.lastScan > 43200) then return end

		local curPrice = Atr_GetMaterialCost(itemName)
		local avgPrice = hist.avg or 0
		if curPrice > 0 and avgPrice > 0 and curPrice < avgPrice then
			local expectedNet = math.floor(avgPrice * 0.95)
			local netProfit = expectedNet - curPrice
			local discountPct = math.floor(((avgPrice - curPrice) / avgPrice) * 100)

			if discountPct >= minDiscount and netProfit >= minProfit then
				seen[key] = true
				local category = Atr_GetItemSnipeCategory(itemName)

				local dealType, tag, tagColor, priority
				if netProfit >= 20000 then
					dealType = "EPIC_SNIPE"
					tag = "[EPIC SNIPE]"
					tagColor = "|cffa335ee"
					priority = 1
				elseif netProfit >= 5000 then
					dealType = "GREAT_FLIP"
					tag = "[GREAT FLIP]"
					tagColor = "|cff0070dd"
					priority = 2
				else
					dealType = "GOOD_FLIP"
					tag = "[FLIP]"
					tagColor = "|cff1eff00"
					priority = 3
				end

				counts.ALL = counts.ALL + 1
				if counts[category] then counts[category] = counts[category] + 1 end

				table.insert(allDeals, {
					name = itemName,
					category = category,
					dealType = dealType,
					tag = tag,
					tagColor = tagColor,
					priority = priority,
					curPrice = curPrice,
					avgPrice = avgPrice,
					netProfit = netProfit,
					discountPct = discountPct,
					seenCount = hist.seenCount,
					lastScan = hist.lastScan,
					isLive = false
				})
			end
		end
	end

	for _, item in ipairs(AUCTIONATOR_WATCHLIST) do
		CheckCandidate(item)
	end
	for _, item in ipairs(CURATED_SNIPE_TARGETS) do
		CheckCandidate(item)
	end
	local pName = UnitName("player") or "Player"
	if AUCTIONATOR_SAVED_RECIPES and AUCTIONATOR_SAVED_RECIPES[pName] then
		for _, rec in pairs(AUCTIONATOR_SAVED_RECIPES[pName]) do
			CheckCandidate(rec.name)
		end
	end

	-- Sort: Live scanned deals first, then priority (Epic -> Great -> Good), then netProfit descending
	table.sort(allDeals, function(a, b)
		local aLive = a.isLive and 1 or 0
		local bLive = b.isLive and 1 or 0
		if aLive ~= bLive then
			return aLive > bLive
		end
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return (a.netProfit or 0) > (b.netProfit or 0)
	end)

	-- Filter matching category
	local filtered = {}
	for _, d in ipairs(allDeals) do
		if not filterCategory or filterCategory == "ALL" or d.category == filterCategory then
			table.insert(filtered, d)
		end
	end

	return filtered, counts
end

----------------------------------------------------------------------
-- High-Speed Targeted Snipe Scan
----------------------------------------------------------------------
local snipeScanQueue = {}
local snipeScanTotal = 0
local snipeScanIndex = 1
local snipeScanRunning = false
local snipeScanPaused = false
local snipeScanSentAt = 0
local lastSnipeScanQueryTime = 0

local snipeDriver = CreateFrame("Frame", "AtrSnipeScanDriver")

function Atr_PauseSnipeScan()
	if not snipeScanRunning then return end
	snipeScanPaused = true
	snipeScanRunning = false
	snipeScanSentAt = 0

	local btnScan = getglobal("Atr_PBtnScan")
	if btnScan then btnScan:SetText("Resume Scan") end
	local btnStop = getglobal("Atr_PBtnStop")
	if btnStop then btnStop:Enable() end

	local sub = getglobal("Atr_ProfitSubTitle")
	if sub and snipeScanIndex <= snipeScanTotal then
		sub:SetText(string.format("|cffffaa00PAUSED (%d/%d):|r %s", snipeScanIndex, snipeScanTotal, snipeScanQueue[snipeScanIndex] or ""))
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffaa00[Sniper]|r Scan paused at %d/%d. You can search & buy items now!", snipeScanIndex, snipeScanTotal))
	end
	if Atr_RefreshProfitUI then Atr_RefreshProfitUI() end
end

function Atr_ResumeSnipeScan()
	if not AuctionFrame or not AuctionFrame:IsShown() then
		if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Sniper]|r Please open the Auction House first!") end
		return
	end
	if not snipeScanPaused or snipeScanIndex > snipeScanTotal then
		Atr_StartSnipeScan()
		return
	end

	snipeScanPaused = false
	snipeScanRunning = true
	snipeScanSentAt = 0
	lastSnipeScanQueryTime = GetTime()

	local btnScan = getglobal("Atr_PBtnScan")
	if btnScan then btnScan:SetText("Pause Scan") end
	local btnStop = getglobal("Atr_PBtnStop")
	if btnStop then btnStop:Enable() end

	local sub = getglobal("Atr_ProfitSubTitle")
	if sub and snipeScanIndex <= snipeScanTotal then
		sub:SetText(string.format("|cff00ffffScanning %d/%d:|r %s", snipeScanIndex, snipeScanTotal, snipeScanQueue[snipeScanIndex] or ""))
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[Sniper]|r Resuming scan from %d/%d...", snipeScanIndex, snipeScanTotal))
	end
end

function Atr_StopSnipeScan()
	snipeScanRunning = false
	snipeScanPaused = false
	snipeScanSentAt = 0
	snipeScanIndex = 1
	snipeScanTotal = 0
	snipeScanQueue = {}

	local btnScan = getglobal("Atr_PBtnScan")
	if btnScan then btnScan:SetText("Quick Snipe Scan") end
	local btnStop = getglobal("Atr_PBtnStop")
	if btnStop then btnStop:Disable() end

	local sub = getglobal("Atr_ProfitSubTitle")
	if sub then sub:SetText("Sniping - Crafting Profit - Watchlist") end

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Sniper]|r Scan stopped. All scanned prices kept.")
	end
	if Atr_RefreshProfitUI then Atr_RefreshProfitUI() end
end

function Atr_ToggleSnipeScan()
	if snipeScanRunning then
		Atr_PauseSnipeScan()
	elseif snipeScanPaused then
		Atr_ResumeSnipeScan()
	else
		Atr_StartSnipeScan()
	end
end

function Atr_StartSnipeScan()
	if snipeScanRunning then
		Atr_PauseSnipeScan()
		return
	end

	if not AuctionFrame or not AuctionFrame:IsShown() then
		if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Sniper]|r Please open the Auction House first!") end
		return
	end

	-- Build curated, high-velocity scan queue (Watchlist + Curated Targets + Player Profession Crafts)
	local unique = {}
	for _, item in ipairs(AUCTIONATOR_WATCHLIST) do
		unique[item] = true
	end
	for _, item in ipairs(CURATED_SNIPE_TARGETS) do
		unique[item] = true
	end
	local pName = UnitName("player") or "Player"
	if AUCTIONATOR_SAVED_RECIPES and AUCTIONATOR_SAVED_RECIPES[pName] then
		for _, rec in pairs(AUCTIONATOR_SAVED_RECIPES[pName]) do
			unique[rec.name] = true
			if rec.reagents then
				for _, r in ipairs(rec.reagents) do
					if not VENDOR_REAGENTS[r.name] then
						unique[r.name] = true
					end
				end
			end
		end
	end

	Atr_ClearLiveScanDeals()
	snipeScanQueue = {}
	for name, _ in pairs(unique) do
		table.insert(snipeScanQueue, name)
	end

	snipeScanTotal = table.getn(snipeScanQueue)
	snipeScanIndex = 1
	snipeScanRunning = true
	snipeScanPaused = false
	snipeScanSentAt = 0
	lastSnipeScanQueryTime = GetTime()

	local btnScan = getglobal("Atr_PBtnScan")
	if btnScan then btnScan:SetText("Pause Scan") end
	local btnStop = getglobal("Atr_PBtnStop")
	if btnStop then btnStop:Enable() end

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[Sniper]|r Scanning %d high-value commodities & watchlist (~15s)...", snipeScanTotal))
	end
end

local function ProcessSnipeScanPage()
	if not snipeScanRunning then return end
	local currentItem = snipeScanQueue[snipeScanIndex]
	if not currentItem then return end

	local numBatch = GetNumAuctionItems("list") or 0
	local lowestBuyout = 0

	for i = 1, numBatch do
		local name, _, count, quality, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", i)
		if name and string.lower(name) == string.lower(currentItem) and buyoutPrice and count and count > 0 then
			local unitPrice = math.floor(buyoutPrice / count)
			if unitPrice > 0 and (lowestBuyout == 0 or unitPrice < lowestBuyout) then
				lowestBuyout = unitPrice
			end
			-- Live deal check during scan
			Atr_CheckLiveScanDeal(name, unitPrice, buyoutPrice, count, quality, 40)
		end
	end

	if lowestBuyout > 0 then
		if gAtr_ScanDB then gAtr_ScanDB[currentItem] = lowestBuyout end
		Atr_RecordHistoricalPrice(currentItem, lowestBuyout)
	else
		Atr_RecordItemNoListings(currentItem)
	end

	snipeScanIndex = snipeScanIndex + 1
	snipeScanSentAt = 0

	local sub = getglobal("Atr_ProfitSubTitle")
	if sub and snipeScanRunning and snipeScanIndex <= snipeScanTotal then
		sub:SetText(string.format("|cff00ffffScanning %d/%d:|r %s", snipeScanIndex, snipeScanTotal, snipeScanQueue[snipeScanIndex] or ""))
	end

	-- Live Real-time UI refresh every 2 items so newly scanned prices and crafting profits update immediately
	if snipeScanRunning and (math.mod(snipeScanIndex, 2) == 0) then
		if Atr_RefreshProfitUI then Atr_RefreshProfitUI() end
	end

	if snipeScanIndex > snipeScanTotal then
		snipeScanRunning = false
		snipeScanPaused = false
		local btnScan = getglobal("Atr_PBtnScan")
		if btnScan then btnScan:SetText("Quick Snipe Scan") end
		local btnStop = getglobal("Atr_PBtnStop")
		if btnStop then btnStop:Disable() end
		if sub then sub:SetText("Sniping - Crafting Profit - Watchlist") end
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Sniper]|r Quick scan complete! New deals highlighted below.")
		end
		if Atr_RefreshProfitUI then Atr_RefreshProfitUI() end
	end
end

snipeDriver:SetScript("OnUpdate", function()
	if not snipeScanRunning or snipeScanPaused then return end
	if not AuctionFrame or not AuctionFrame:IsShown() then
		Atr_PauseSnipeScan()
		return
	end

	local now = GetTime()
	-- Timeout retry after 3.5s
	if snipeScanSentAt > 0 and (now - snipeScanSentAt > 3.5) then
		snipeScanSentAt = 0
	end

	-- Safe 350ms throttle between queries to avoid server kick
	if (now - (lastSnipeScanQueryTime or 0) < 0.35) then
		return
	end

	if snipeScanSentAt == 0 and Atr_CanSendAuctionQuery and Atr_CanSendAuctionQuery() then
		local currentItem = snipeScanQueue[snipeScanIndex]
		if currentItem then
			snipeScanSentAt = now
			lastSnipeScanQueryTime = now
			Atr_QueryAuctionItems(currentItem, nil, nil, 0, 0, 0, 0, 0, 0)
		else
			snipeScanRunning = false
		end
	end
end)

snipeDriver:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
snipeDriver:SetScript("OnEvent", function()
	if event == "AUCTION_ITEM_LIST_UPDATE" and snipeScanRunning and snipeScanSentAt > 0 then
		ProcessSnipeScanPage()
	end
end)

----------------------------------------------------------------------
-- Gold Advisor UI Window (Streamlined 3-Tab Interface)
----------------------------------------------------------------------
local profitFrame = nil
local currentTab = 1 -- 1 = Snipes & Deals, 2 = Crafting Profit, 3 = Watchlist
local currentFlipFilter = "ALL"
local currentCraftProfFilter = "ALL"
local selectedRecipeName = nil

function Atr_ProfitScroll_OnMouseWheel(delta)
	local bar = getglobal("Atr_ProfitScrollScrollBar")
	local sf = getglobal("Atr_ProfitScroll")
	if bar and sf then
		local cur = bar:GetValue() or 0
		local _, maxRange = bar:GetMinMaxValues()
		if not maxRange or maxRange <= 0 then
			maxRange = sf:GetVerticalScrollRange() or 0
		end
		local step = 45
		local newVal = cur
		if delta > 0 then
			newVal = math.max(cur - step, 0)
		else
			newVal = math.min(cur + step, maxRange)
		end
		bar:SetValue(newVal)
		sf:SetVerticalScroll(newVal)
	end
end

local QUALITY_COLORS = {
	[0] = { 0.6, 0.6, 0.6 },
	[1] = { 1.0, 1.0, 1.0 },
	[2] = { 0.12, 1.0, 0.0 },
	[3] = { 0.0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 },
	[5] = { 1.0, 0.5, 0.0 },
}

local linePool = {}
local activeLines = {}
local function AcquireLine(parent)
	local line = table.remove(linePool)
	if not line then
		line = CreateFrame("Button", nil, parent)
		line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		line:GetHighlightTexture():SetBlendMode("ADD")

		local icon = line:CreateTexture(nil, "ARTWORK")
		icon:SetWidth(26)
		icon:SetHeight(26)
		icon:SetPoint("LEFT", line, "LEFT", 4, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		line.icon = icon

		line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
		line.text:SetWidth(325)
		line.text:SetJustifyH("LEFT")

		line.sub = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		line.sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
		line.sub:SetWidth(325)
		line.sub:SetJustifyH("LEFT")
	end
	line:SetParent(parent)
	line:Show()
	table.insert(activeLines, line)
	return line
end

local function ReleaseAllLines()
	for _, l in ipairs(activeLines) do
		l:Hide()
		l:ClearAllPoints()
		if l.icon then l.icon:SetTexture(nil) end
		if l.border then l.border:Hide() end
		l:SetScript("OnClick", nil)
		l:SetScript("OnEnter", nil)
		l:SetScript("OnLeave", nil)
		table.insert(linePool, l)
	end
	activeLines = {}
end

local function NextLine(width, height)
	local content = getglobal("Atr_ProfitContent")
	local line = AcquireLine(content)
	line:SetWidth(width or 365)
	line:SetHeight(height or 34)
	return line
end

local function Atr_UpdateScrollState(maxHeight)
	local sf = getglobal("Atr_ProfitScroll")
	local content = getglobal("Atr_ProfitContent")
	local bar = getglobal("Atr_ProfitScrollScrollBar")
	if content and sf then
		local h = math.max(maxHeight or 100, 330)
		content:SetHeight(h)
		sf:UpdateScrollChildRect()

		local maxRange = h - sf:GetHeight()
		if maxRange < 0 then maxRange = 0 end
		if bar then
			bar:SetMinMaxValues(0, maxRange)
			local cur = bar:GetValue() or 0
			if cur > maxRange then
				bar:SetValue(maxRange)
				sf:SetVerticalScroll(maxRange)
			end
			if maxRange > 0 then
				bar:Show()
			else
				bar:Hide()
			end
		end
	end
end

function Atr_CreateProfitFrame()
	if profitFrame then return profitFrame end

	profitFrame = CreateFrame("Frame", "Atr_ProfitFrame", UIParent)
	profitFrame:SetWidth(415)
	profitFrame:SetHeight(470)
	profitFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -100)
	profitFrame:SetMovable(true)
	profitFrame:EnableMouse(true)
	profitFrame:RegisterForDrag("LeftButton")
	profitFrame:SetScript("OnDragStart", function() this:StartMoving() end)
	profitFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); this.userMoved = true end)
	profitFrame:SetFrameStrata("DIALOG")

	profitFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	})
	profitFrame:Hide()

	-- Title Bar
	local title = profitFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Auctionator - Gold & Profit Sniper")

	local subTitle = profitFrame:CreateFontString("Atr_ProfitSubTitle", "OVERLAY", "GameFontNormalSmall")
	subTitle:SetPoint("TOP", 0, -36)
	subTitle:SetText("Sniping - Crafting Profit - Watchlist")

	local function SwitchTab(tabIdx)
		currentTab = tabIdx
		local bar = getglobal("Atr_ProfitScrollScrollBar")
		if bar then bar:SetValue(0) end
		local sf = getglobal("Atr_ProfitScroll")
		if sf then sf:SetVerticalScroll(0) end
		Atr_RefreshProfitUI()
	end

	-- 3 Clean Wide Tabs (124px each)
	local tab1 = CreateFrame("Button", "Atr_PTab1", profitFrame, "UIPanelButtonTemplate")
	tab1:SetWidth(124); tab1:SetHeight(22); tab1:SetPoint("TOPLEFT", 16, -58); tab1:SetText("Snipes & Deals")
	tab1:SetScript("OnClick", function() SwitchTab(1) end)

	local tab2 = CreateFrame("Button", "Atr_PTab2", profitFrame, "UIPanelButtonTemplate")
	tab2:SetWidth(124); tab2:SetHeight(22); tab2:SetPoint("LEFT", tab1, "RIGHT", 4, 0); tab2:SetText("My Crafting")
	tab2:SetScript("OnClick", function() SwitchTab(2) end)

	local tab3 = CreateFrame("Button", "Atr_PTab3", profitFrame, "UIPanelButtonTemplate")
	tab3:SetWidth(124); tab3:SetHeight(22); tab3:SetPoint("LEFT", tab2, "RIGHT", 4, 0); tab3:SetText("Watchlist")
	tab3:SetScript("OnClick", function() SwitchTab(3) end)

	-- Content Scroll Area
	local scrollFrame = CreateFrame("ScrollFrame", "Atr_ProfitScroll", profitFrame, "UIPanelScrollFrameTemplate")
	scrollFrame:SetWidth(380)
	scrollFrame:SetHeight(330)
	scrollFrame:SetPoint("TOPLEFT", 16, -88)
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", function() Atr_ProfitScroll_OnMouseWheel(arg1) end)

	local content = CreateFrame("Frame", "Atr_ProfitContent", scrollFrame)
	content:SetWidth(370)
	content:SetHeight(800)
	content:EnableMouseWheel(true)
	content:SetScript("OnMouseWheel", function() Atr_ProfitScroll_OnMouseWheel(arg1) end)
	scrollFrame:SetScrollChild(content)

	local emptyText = content:CreateFontString("Atr_PEmptyText", "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("TOPLEFT", 10, -10)
	emptyText:SetWidth(350)
	emptyText:SetJustifyH("LEFT")
	emptyText:Hide()

	-- Bottom Buttons
	local btnScan = CreateFrame("Button", "Atr_PBtnScan", profitFrame, "UIPanelButtonTemplate")
	btnScan:SetWidth(125); btnScan:SetHeight(24); btnScan:SetPoint("BOTTOMLEFT", 14, 14); btnScan:SetText("Quick Snipe Scan")
	btnScan:SetScript("OnClick", function() Atr_ToggleSnipeScan() end)

	local btnStop = CreateFrame("Button", "Atr_PBtnStop", profitFrame, "UIPanelButtonTemplate")
	btnStop:SetWidth(65); btnStop:SetHeight(24); btnStop:SetPoint("LEFT", btnScan, "RIGHT", 4, 0); btnStop:SetText("Stop")
	btnStop:SetScript("OnClick", function() Atr_StopSnipeScan() end)
	btnStop:Disable()

	local btnLearn = CreateFrame("Button", "Atr_PBtnLearn", profitFrame, "UIPanelButtonTemplate")
	btnLearn:SetWidth(120); btnLearn:SetHeight(24); btnLearn:SetPoint("LEFT", btnStop, "RIGHT", 4, 0); btnLearn:SetText("Learn Recipes")
	btnLearn:SetScript("OnClick", function() ScanOpenTradeSkill(); Atr_RefreshProfitUI(); end)

	local btnClose = CreateFrame("Button", nil, profitFrame, "UIPanelButtonTemplate")
	btnClose:SetWidth(65); btnClose:SetHeight(24); btnClose:SetPoint("BOTTOMRIGHT", -14, 14); btnClose:SetText("Close")
	btnClose:SetScript("OnClick", function() profitFrame:Hide(); end)

	return profitFrame
end

function Atr_SearchItemLive(itemName)
	if not itemName or itemName == "" then return end
	if snipeScanRunning then
		Atr_PauseSnipeScan()
	end
	if AuctionFrame and AuctionFrame:IsShown() then
		if Atr_SelectPane then
			Atr_SelectPane(3) -- 3 = BUY_TAB
		end
		if Atr_Search_Box then
			Atr_Search_Box:SetText(itemName)
		end
		if Atr_Search_Onclick then
			Atr_Search_Onclick()
		end
		if DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Sniper]|r Searching AH for |cffffffff" .. itemName .. "|r (Scan paused).")
		end
	end
end

----------------------------------------------------------------------
-- Render / Refresh UI Logic
----------------------------------------------------------------------
function Atr_RefreshProfitUI()
	local frame = Atr_CreateProfitFrame()
	if not frame or not frame:IsShown() then return end

	-- Tab Buttons Highlight
	for i = 1, 3 do
		local tab = getglobal("Atr_PTab" .. i)
		if tab then
			if i == currentTab then
				tab:LockHighlight()
			else
				tab:UnlockHighlight()
			end
		end
	end

	-- Update Bottom Button States
	local btnScan = getglobal("Atr_PBtnScan")
	local btnStop = getglobal("Atr_PBtnStop")
	if btnScan and btnStop then
		if snipeScanRunning then
			btnScan:SetText("Pause Scan")
			btnStop:Enable()
		elseif snipeScanPaused then
			btnScan:SetText("Resume Scan")
			btnStop:Enable()
		else
			btnScan:SetText("Quick Snipe Scan")
			btnStop:Disable()
		end
	end

	ReleaseAllLines()

	local content = getglobal("Atr_ProfitContent")
	local emptyText = getglobal("Atr_PEmptyText")
	if emptyText then emptyText:Hide() end

	-- Hide persistent sub-widgets
	for i = 1, 10 do
		local b = getglobal("Atr_PFlipBtn_" .. i)
		if b then b:Hide() end
		local p = getglobal("Atr_PProfitPill_" .. i)
		if p then p:Hide() end
		local pb = getglobal("Atr_PProfBtn_" .. i)
		if pb then pb:Hide() end
	end
	local chkProf = getglobal("Atr_PCraftProfitableCheck")
	if chkProf then chkProf:Hide() end
	local ebWatch = getglobal("Atr_PWatchAddBox")
	if ebWatch then ebWatch:Hide() end
	local btnWatchAdd = getglobal("Atr_PWatchAddBtn")
	if btnWatchAdd then btnWatchAdd:Hide() end

	local yOffset = -4

	------------------------------------------------------------------
	-- TAB 1:  SNIPES & DEALS
	------------------------------------------------------------------
	if currentTab == 1 then
		local deals, counts = Atr_GetFlipAnalysis(currentFlipFilter)

		-- Row 1: Category Filter Buttons (4 buttons across, width 88 each)
		local catFilters = {
			{ id = "ALL", label = "All", count = counts.ALL },
			{ id = "GEAR", label = "BoE Gear", count = counts.GEAR },
			{ id = "MATS", label = "Materials", count = counts.MATS },
			{ id = "RECIPES", label = "Recipes", count = counts.RECIPES },
		}
		local catX = 0
		for idx, cf in ipairs(catFilters) do
			local btn = getglobal("Atr_PFlipBtn_" .. idx)
			if not btn then
				btn = CreateFrame("Button", "Atr_PFlipBtn_" .. idx, content, "UIPanelButtonTemplate")
				btn:SetHeight(20)
				btn:SetFrameLevel(content:GetFrameLevel() + 2)
			end
			btn:SetWidth(88)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", catX, yOffset)
			local txt = string.format("%s (%d)", cf.label, cf.count or 0)
			if currentFlipFilter == cf.id then
				btn:SetText("|cff00ff00[" .. txt .. "]|r")
			else
				btn:SetText(txt)
			end
			btn.filterId = cf.id
			btn:SetScript("OnClick", function()
				currentFlipFilter = this.filterId
				local bar = getglobal("Atr_ProfitScrollScrollBar")
				if bar then bar:SetValue(0) end
				local sf = getglobal("Atr_ProfitScroll")
				if sf then sf:SetVerticalScroll(0) end
				Atr_RefreshProfitUI()
			end)
			btn:Show()
			catX = catX + 90
		end
		yOffset = yOffset - 22

		-- Row 2: Minimum Profit Filter Pills (Adjustable for Level 36 silver/gold!)
		local profitPills = {
			{ value = 1000, label = "Min: 10s" },
			{ value = 2000, label = "20s" },
			{ value = 5000, label = "50s" },
			{ value = 10000, label = "1g" },
		}
		local pillX = 0
		for pIdx, pill in ipairs(profitPills) do
			local pBtn = getglobal("Atr_PProfitPill_" .. pIdx)
			if not pBtn then
				pBtn = CreateFrame("Button", "Atr_PProfitPill_" .. pIdx, content, "UIPanelButtonTemplate")
				pBtn:SetHeight(18)
				pBtn:SetFrameLevel(content:GetFrameLevel() + 2)
			end
			pBtn:SetWidth(88)
			pBtn:ClearAllPoints()
			pBtn:SetPoint("TOPLEFT", pillX, yOffset)
			if (AUCTIONATOR_SNIPE_MIN_PROFIT or 2000) == pill.value then
				pBtn:SetText("|cff00ffff[" .. pill.label .. "]|r")
			else
				pBtn:SetText(pill.label)
			end
			pBtn.profitVal = pill.value
			pBtn:SetScript("OnClick", function()
				AUCTIONATOR_SNIPE_MIN_PROFIT = this.profitVal
				local bar = getglobal("Atr_ProfitScrollScrollBar")
				if bar then bar:SetValue(0) end
				local sf = getglobal("Atr_ProfitScroll")
				if sf then sf:SetVerticalScroll(0) end
				Atr_RefreshProfitUI()
			end)
			pBtn:Show()
			pillX = pillX + 90
		end
		yOffset = yOffset - 24

		if table.getn(deals) == 0 then
			if emptyText then
				emptyText:SetText("|cffffcc00No deals matching your filter right now!|r\n\n1. Click '|cff00ffff Quick Snipe Scan|r' below (takes ~15s) to scan high-demand commodities & gear.\n2. When players post items below market price, they will appear here with live profits.\n\n|cff888888Tip: You can lower the Min Profit threshold above (e.g. 10s or 20s) to catch smaller flips.|r")
				emptyText:Show()
			end
		else
			for _, d in ipairs(deals) do
				local line = NextLine(360, 36)
				line:SetPoint("TOPLEFT", 0, yOffset)
				line.dealData = d
				line.searchTarget = d.name
				line:RegisterForClicks("LeftButtonUp", "RightButtonUp")

				local rName, link, quality, texture = Atr_ResolveItem(d.name)
				local icon = texture or d.icon
				if icon then
					line.icon:SetTexture(icon)
					line.icon:Show()
				else
					line.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
					line.icon:Show()
				end

				local nameColor = "|cffffffff"
				if quality and QUALITY_COLORS[quality] then
					local qc = QUALITY_COLORS[quality]
					nameColor = string.format("|cff%02x%02x%02x", qc[1]*255, qc[2]*255, qc[3]*255)
				end

				local freshStr = Atr_GetFreshnessText(d.lastScan, d.isLive)
				line.text:SetText(string.format("%s%s|r %s%s|r: %s  %s", d.tagColor, d.tag, nameColor, d.name, zc.priceToMoneyString(d.curPrice), freshStr))
				line.sub:SetText(string.format("Avg: %s  |cff00ff00Profit: +%s|r (-%d%%)  |cff888888(Click: Buy)|r", zc.priceToMoneyString(d.avgPrice), zc.priceToMoneyString(d.netProfit), d.discountPct))

				line:SetScript("OnEnter", function()
					local data = this.dealData
					if not data then return end
					GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
					local _, lk = Atr_ResolveItem(data.name)
					if lk then
						GameTooltip:SetHyperlink(lk)
					else
						GameTooltip:SetText(data.name, 1, 1, 1)
					end
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("|cffffd100[Sniper Deal Analysis]|r")
					GameTooltip:AddLine("Deal Rating: " .. data.tagColor .. data.tag, 1, 1, 1)
					GameTooltip:AddLine("Current Buyout: " .. zc.priceToMoneyString(data.curPrice), 1, 0.85, 0)
					GameTooltip:AddLine("Historical Market Avg: " .. zc.priceToMoneyString(data.avgPrice), 0.8, 0.8, 0.8)
					GameTooltip:AddLine(string.format("Discount: %d%% below market average", data.discountPct), 0, 1, 1)
					GameTooltip:AddLine("Estimated Net Resale Profit: " .. zc.priceToMoneyString(data.netProfit) .. " (after 5% AH fee)", 0, 1, 0)
					GameTooltip:AddLine("Historical Scans: " .. tostring(data.seenCount or 1), 0.6, 0.6, 0.6)
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("|cff00ff00Left-Click:|r Search & Buy on AH", 0.9, 0.9, 0.9)
					GameTooltip:AddLine("|cffffaa00Right-Click:|r Add to Watchlist", 0.9, 0.9, 0.9)
					GameTooltip:Show()
				end)
				line:SetScript("OnLeave", function() GameTooltip:Hide() end)
				line:SetScript("OnClick", function()
					local tName = this.searchTarget
					if arg1 == "RightButton" then
						local exists = false
						for _, w in ipairs(AUCTIONATOR_WATCHLIST) do
							if w == tName then exists = true; break end
						end
						if not exists then
							table.insert(AUCTIONATOR_WATCHLIST, tName)
							if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Sniper]|r Added '|cffffffff" .. tName .. "|r' to Watchlist.") end
						else
							if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[Sniper]|r '|cffffffff" .. tName .. "|r' is already on your Watchlist.") end
						end
						return
					end
					Atr_SearchItemLive(tName)
				end)

				yOffset = yOffset - 38
			end
		end

	------------------------------------------------------------------
	-- TAB 2:  MY CRAFTING PROFIT
	------------------------------------------------------------------
	elseif currentTab == 2 then
		local allRecipes = Atr_CalculateRecipeProfits()

		-- Checkbox: Show Profitable Only
		if not chkProf then
			chkProf = CreateFrame("CheckButton", "Atr_PCraftProfitableCheck", content, "UICheckButtonTemplate")
			chkProf:SetWidth(20); chkProf:SetHeight(20)
			local t = chkProf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", chkProf, "RIGHT", 4, 0)
			t:SetText("Only show profitable crafts (Margin > 0)")
			chkProf:SetScript("OnClick", function()
				AUCTIONATOR_CRAFT_ONLY_PROFITABLE = (this:GetChecked() == 1)
				local bar = getglobal("Atr_ProfitScrollScrollBar")
				if bar then bar:SetValue(0) end
				local sf = getglobal("Atr_ProfitScroll")
				if sf then sf:SetVerticalScroll(0) end
				Atr_RefreshProfitUI()
			end)
		end
		chkProf:ClearAllPoints()
		chkProf:SetPoint("TOPLEFT", 4, yOffset)
		chkProf:SetChecked(AUCTIONATOR_CRAFT_ONLY_PROFITABLE and 1 or 0)
		chkProf:Show()
		yOffset = yOffset - 24

		-- Find unique professions learned by player
		local profs = {}
		for _, r in ipairs(allRecipes) do
			if r.profession and not profs[r.profession] then
				profs[r.profession] = true
			end
		end

		local profList = { "ALL" }
		for pName, _ in pairs(profs) do
			table.insert(profList, pName)
		end

		if table.getn(profList) > 2 then
			local pX = 0
			for idx, pName in ipairs(profList) do
				local pb = getglobal("Atr_PProfBtn_" .. idx)
				if not pb then
					pb = CreateFrame("Button", "Atr_PProfBtn_" .. idx, content, "UIPanelButtonTemplate")
					pb:SetHeight(18)
					pb:SetFrameLevel(content:GetFrameLevel() + 2)
				end
				pb:SetWidth(100)
				pb:ClearAllPoints()
				pb:SetPoint("TOPLEFT", pX, yOffset)
				if currentCraftProfFilter == pName then
					pb:SetText("|cff00ff00[" .. pName .. "]|r")
				else
					pb:SetText(pName)
				end
				pb.profId = pName
				pb:SetScript("OnClick", function()
					currentCraftProfFilter = this.profId
					local bar = getglobal("Atr_ProfitScrollScrollBar")
					if bar then bar:SetValue(0) end
					local sf = getglobal("Atr_ProfitScroll")
					if sf then sf:SetVerticalScroll(0) end
					Atr_RefreshProfitUI()
				end)
				pb:Show()
				pX = pX + 104
			end
			yOffset = yOffset - 22
		end

		local filtered = {}
		for _, r in ipairs(allRecipes) do
			local matchProf = (currentCraftProfFilter == "ALL" or r.profession == currentCraftProfFilter)
			local matchProfit = (not AUCTIONATOR_CRAFT_ONLY_PROFITABLE) or (r.hasListings and r.profit > 0)
			if matchProf and matchProfit then
				table.insert(filtered, r)
			end
		end

		if table.getn(filtered) == 0 then
			if emptyText then
				emptyText:SetText("|cffffcc00No crafting recipes match your filter!|r\n\n1. Open your profession window (e.g. Cooking, Blacksmithing) and click '|cff00ffff Learn Recipes|r' below.\n2. Run '|cff00ffff Quick Snipe Scan|r' to update current material and product prices on the AH.\n3. Uncheck 'Only show profitable crafts' if you want to inspect unlisted or breaking-even recipes.")
				emptyText:Show()
			end
		else
			for _, rec in ipairs(filtered) do
				local line = NextLine(360, 36)
				line:SetPoint("TOPLEFT", 0, yOffset)
				line.recData = rec
				line.searchTarget = rec.productName or rec.name
				line:RegisterForClicks("LeftButtonUp", "RightButtonUp")

				local rName, link, quality, texture = Atr_ResolveItem(rec.link or rec.productName or rec.name)
				if not rec.link and link then rec.link = link end
				local icon = texture or rec.icon
				if not icon or string.find(icon, "INV_Misc_QuestionMark") then
					local _, _, _, fallbackIcon = Atr_ResolveItem(rec.productName or rec.name)
					if fallbackIcon and not string.find(fallbackIcon, "INV_Misc_QuestionMark") then
						icon = fallbackIcon
					end
				end

				if icon then
					line.icon:SetTexture(icon)
					line.icon:Show()
					if not rec.icon or string.find(rec.icon, "INV_Misc_QuestionMark") then
						rec.icon = icon
						local pName = UnitName("player") or "Player"
						if AUCTIONATOR_SAVED_RECIPES and AUCTIONATOR_SAVED_RECIPES[pName] and AUCTIONATOR_SAVED_RECIPES[pName][rec.name] then
							AUCTIONATOR_SAVED_RECIPES[pName][rec.name].icon = icon
						end
					end
				else
					line.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
					line.icon:Show()
				end

				local nameColor = "|cffffffff"
				if quality and QUALITY_COLORS[quality] then
					local qc = QUALITY_COLORS[quality]
					nameColor = string.format("|cff%02x%02x%02x", qc[1]*255, qc[2]*255, qc[3]*255)
				end

				local profitColor = (rec.profit > 0) and "|cff00ff00" or "|cffff4444"
				local marginStr = (rec.hasListings and rec.craftCost > 0) and string.format(" (%d%%)", rec.margin) or ""
				local profitStr = rec.hasListings and string.format("%s+%s%s|r", profitColor, zc.priceToMoneyString(rec.profit), marginStr) or "|cff888888(No AH Price)|r"

				line.text:SetText(string.format("%s%s|r  %s", nameColor, rec.name, profitStr))
				line.sub:SetText(string.format("Cost: %s  Sell: %s  |cff888888(Click: Search AH)|r", zc.priceToMoneyString(rec.craftCost), zc.priceToMoneyString(rec.sellPrice)))

				line:SetScript("OnEnter", function()
					local data = this.recData
					if not data then return end
					GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
					local targetLink = data.link
					if not targetLink then
						local _, lk = Atr_ResolveItem(data.productName or data.name)
						targetLink = lk
					end
					if targetLink then
						GameTooltip:SetHyperlink(targetLink)
					else
						GameTooltip:SetText(data.name, 1, 1, 1)
					end
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("|cffffd100[Crafting Profit Analysis]|r")
					GameTooltip:AddLine("Profession: " .. (data.profession or "Unknown"), 0.8, 0.8, 0.8)
					GameTooltip:AddLine("Total Crafting Cost: " .. zc.priceToMoneyString(data.craftCost), 1, 0.85, 0)
					GameTooltip:AddLine("Market Sale Price: " .. zc.priceToMoneyString(data.sellPrice), 1, 0.85, 0)
					if data.hasListings then
						GameTooltip:AddLine("Net Revenue (after 5% AH fee): " .. zc.priceToMoneyString(data.netRevenue), 0.9, 0.9, 0.9)
						GameTooltip:AddLine(string.format("Estimated Profit: %s (%d%% margin)", zc.priceToMoneyString(data.profit), data.margin), 0, 1, 0)
					end
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("Reagents:", 1, 0.8, 0)
					if data.reagents then
						for _, r in ipairs(data.reagents) do
							local unitCost = Atr_GetMaterialCost(r.name)
							local rTotal = unitCost * (r.count or 1)
							GameTooltip:AddLine(string.format("  x%d %s: %s", r.count or 1, r.name, zc.priceToMoneyString(rTotal)), 0.8, 0.8, 0.8)
						end
					end
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("|cff00ff00Left-Click:|r Search product on AH", 0.9, 0.9, 0.9)
					GameTooltip:AddLine("|cffffaa00Right-Click:|r Hide recipe from list", 0.9, 0.9, 0.9)
					GameTooltip:Show()
				end)
				line:SetScript("OnLeave", function() GameTooltip:Hide() end)
				line:SetScript("OnClick", function()
					local tName = this.searchTarget
					if arg1 == "RightButton" then
						local pName = UnitName("player") or "Player"
						if not AUCTIONATOR_IGNORED_RECIPES[pName] then AUCTIONATOR_IGNORED_RECIPES[pName] = {} end
						AUCTIONATOR_IGNORED_RECIPES[pName][this.recData.name] = true
						if DEFAULT_CHAT_FRAME then
							DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffaa00[Auctionator Advisor]|r Hidden '%s' (type '/atr advisor restore' to undo).", this.recData.name))
						end
						Atr_RefreshProfitUI()
						return
					end
					Atr_SearchItemLive(tName)
				end)

				yOffset = yOffset - 38
			end
		end

	------------------------------------------------------------------
	-- TAB 3:  WATCHLIST
	------------------------------------------------------------------
	elseif currentTab == 3 then
		-- Add Item EditBox + Button
		if not ebWatch then
			ebWatch = CreateFrame("EditBox", "Atr_PWatchAddBox", content, "InputBoxTemplate")
			ebWatch:SetWidth(250); ebWatch:SetHeight(20)
			ebWatch:SetAutoFocus(false)
			ebWatch:SetScript("OnEnterPressed", function()
				local txt = this:GetText()
				if txt and txt ~= "" then
					table.insert(AUCTIONATOR_WATCHLIST, txt)
					this:SetText("")
					this:ClearFocus()
					Atr_RefreshProfitUI()
				end
			end)
		end
		ebWatch:ClearAllPoints()
		ebWatch:SetPoint("TOPLEFT", 6, yOffset)
		ebWatch:Show()

		if not btnWatchAdd then
			btnWatchAdd = CreateFrame("Button", "Atr_PWatchAddBtn", content, "UIPanelButtonTemplate")
			btnWatchAdd:SetWidth(95); btnWatchAdd:SetHeight(20)
			btnWatchAdd:SetText("+ Add Item")
			btnWatchAdd:SetScript("OnClick", function()
				local box = getglobal("Atr_PWatchAddBox")
				if box then
					local txt = box:GetText()
					if txt and txt ~= "" then
						table.insert(AUCTIONATOR_WATCHLIST, txt)
						box:SetText("")
						box:ClearFocus()
						Atr_RefreshProfitUI()
					end
				end
			end)
		end
		btnWatchAdd:ClearAllPoints()
		btnWatchAdd:SetPoint("LEFT", ebWatch, "RIGHT", 8, 0)
		btnWatchAdd:Show()
		yOffset = yOffset - 28

		if table.getn(AUCTIONATOR_WATCHLIST) == 0 then
			if emptyText then
				emptyText:SetText("|cffffcc00Your Watchlist is empty!|r\n\n1. Type an item name in the box above and click '+ Add Item'.\n2. Or right-click any deal in the Snipes tab to watch it.\n3. The Watchlist is automatically tracked during ' Quick Snipe Scan'.")
				emptyText:Show()
			end
		else
			for idx, itemName in ipairs(AUCTIONATOR_WATCHLIST) do
				local curPrice = Atr_GetMaterialCost(itemName)
				local hist = Atr_GetHistoricalData(itemName)
				local line = NextLine(360, 36)
				line:SetPoint("TOPLEFT", 0, yOffset)
				line.searchTarget = itemName
				line.watchIdx = idx
				line:RegisterForClicks("LeftButtonUp", "RightButtonUp")

				local rName, link, quality, texture = Atr_ResolveItem(itemName)
				local icon = texture
				if icon then
					line.icon:SetTexture(icon)
					line.icon:Show()
				else
					line.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
					line.icon:Show()
				end

				local nameColor = "|cffffffff"
				if quality and QUALITY_COLORS[quality] then
					local qc = QUALITY_COLORS[quality]
					nameColor = string.format("|cff%02x%02x%02x", qc[1]*255, qc[2]*255, qc[3]*255)
				end

				local trendStr = "|cff888888(Stable)|r"
				if hist and hist.trend then
					if hist.trend > 0 then
						trendStr = string.format("|cff00ff00+ %d%%|r", hist.trendPct or 0)
					elseif hist.trend < 0 then
						trendStr = string.format("|cffff4444  %d%%|r", hist.trendPct or 0)
					end
				end

				local freshStr = Atr_GetFreshnessText(hist and hist.lastScan, false)
				line.text:SetText(string.format("%s%s|r: %s  %s  %s", nameColor, itemName, zc.priceToMoneyString(curPrice), trendStr, freshStr))
				if hist and hist.avg then
					line.sub:SetText(string.format("Avg: %s  |  Min: %s  Max: %s  |cff888888(Click: Search)|r", zc.priceToMoneyString(hist.avg), zc.priceToMoneyString(hist.min), zc.priceToMoneyString(hist.max)))
				else
					line.sub:SetText("Run Quick Snipe Scan to collect live price  |cff888888(Click: Search)|r")
				end

				line:SetScript("OnEnter", function()
					GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
					local _, lk = Atr_ResolveItem(this.searchTarget)
					if lk then
						GameTooltip:SetHyperlink(lk)
					else
						GameTooltip:SetText(this.searchTarget, 1, 1, 1)
					end
					GameTooltip:AddLine(" ", 1, 1, 1)
					GameTooltip:AddLine("|cff00ff00Left-Click:|r Search live on AH", 0.8, 0.8, 0.8)
					GameTooltip:AddLine("|cffff4444Right-Click:|r Remove from Watchlist", 0.8, 0.8, 0.8)
					GameTooltip:Show()
				end)
				line:SetScript("OnLeave", function() GameTooltip:Hide() end)
				line:SetScript("OnClick", function()
					local tName = this.searchTarget
					if arg1 == "RightButton" then
						for wIdx, wName in ipairs(AUCTIONATOR_WATCHLIST) do
							if wName == tName then
								table.remove(AUCTIONATOR_WATCHLIST, wIdx)
								break
							end
						end
						if DEFAULT_CHAT_FRAME then
							DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffaa00[Watchlist]|r Removed '|cffffffff%s|r'.", tName))
						end
						GameTooltip:Hide()
						Atr_RefreshProfitUI()
						return
					end
					Atr_SearchItemLive(tName)
				end)

				yOffset = yOffset - 38
			end
		end
	end

	Atr_UpdateScrollState(-yOffset + 40)
end

function Atr_EnsureAHProfitButton()
	if not AuctionFrame then return end
	local btn = getglobal("Atr_AH_ProfitButton")
	if not btn then
		btn = CreateFrame("Button", "Atr_AH_ProfitButton", AuctionFrame, "UIPanelButtonTemplate")
		btn:SetWidth(88)
		btn:SetHeight(18)
		btn:SetText("Gold Advisor")
		btn:SetFrameLevel(AuctionFrame:GetFrameLevel() + 5)
		btn:SetScript("OnClick", function()
			Atr_ToggleProfitFrame()
		end)
	end
	btn:ClearAllPoints()
	if AuctionFrameCloseButton then
		btn:SetPoint("RIGHT", AuctionFrameCloseButton, "LEFT", -4, 0)
	else
		btn:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -38, -14)
	end
	btn:Show()
end

function Atr_ToggleProfitFrame(param)
	if param then
		param = string.lower(param)
		if param == "restore" or param == "unhide" then
			Atr_RestoreIgnoredRecipes()
			return
		elseif param == "reset" then
			local f = Atr_CreateProfitFrame()
			f.userMoved = nil
			f:ClearAllPoints()
			if AuctionFrame and AuctionFrame:IsShown() then
				f:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 10, -10)
			else
				f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -100)
			end
			f:Show()
			Atr_RefreshProfitUI()
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Auctionator Advisor]|r Position reset.")
			end
			return
		elseif param == "auto" then
			AUCTIONATOR_AUTO_OPEN_ADVISOR = not AUCTIONATOR_AUTO_OPEN_ADVISOR
			local state = AUCTIONATOR_AUTO_OPEN_ADVISOR and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r"
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Auctionator Advisor]|r Auto-open with Auction House: " .. state)
			end
			return
		end
	end

	local frame = Atr_CreateProfitFrame()
	if frame:IsShown() then
		frame:Hide()
	else
		if not frame.userMoved and AuctionFrame and AuctionFrame:IsShown() then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 10, -10)
		end
		frame:Show()
		Atr_RefreshProfitUI()
	end
end

SLASH_ATRPROFIT1 = "/profit"
SLASH_ATRPROFIT2 = "/advisor"
SLASH_ATRPROFIT3 = "/sniper"
SlashCmdList["ATRPROFIT"] = function(msg)
	Atr_ToggleProfitFrame(msg)
end

----------------------------------------------------------------------
-- Auto-Open Events & Lifecycle
----------------------------------------------------------------------
local tsDelayFrame = CreateFrame("Frame")
tsDelayFrame:Hide()
local tsDelayTimer = 0
tsDelayFrame:SetScript("OnUpdate", function()
	tsDelayTimer = tsDelayTimer - arg1
	if tsDelayTimer <= 0 then
		tsDelayFrame:Hide()
		if TradeSkillFrame and TradeSkillFrame:IsVisible() then
			ScanOpenTradeSkill()
		end
	end
end)

local eventFrame = CreateFrame("Frame", "AtrProfitEvents")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		Atr_MigrateExistingScanDB()
	elseif event == "TRADE_SKILL_SHOW" then
		tsDelayTimer = 0.8
		tsDelayFrame:Show()
	elseif event == "AUCTION_HOUSE_SHOW" then
		Atr_MigrateExistingScanDB()
		Atr_EnsureAHProfitButton()
		if AUCTIONATOR_AUTO_OPEN_ADVISOR ~= false then
			local frame = Atr_CreateProfitFrame()
			if not frame.userMoved and AuctionFrame then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 10, -10)
			end
			if not frame:IsShown() then
				frame:Show()
				Atr_RefreshProfitUI()
			end
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if profitFrame and profitFrame:IsShown() then
			profitFrame:Hide()
		end
	end
end)