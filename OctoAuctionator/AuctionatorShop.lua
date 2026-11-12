
local addonName, addonTable = "Auctionator", AtrNS; 
local zc = addonTable.zc;

-----------------------------------------

Atr_SList = {};
Atr_SList.__index = Atr_SList;

local SLITEMS_NUM_LINES = 15;

local gCurrentSList;

-----------------------------------------

local PRO_SHOPPING_LISTS = {
	{
		name = "BS: Consumables & Rods",
		items = {
			"Iron Shield Spike", "Mithril Shield Spike", "Thorium Shield Spike",
			"Iron Counterweight", "Steel Weapon Chain",
			"Coarse Sharpening Stone", "Heavy Sharpening Stone", "Solid Sharpening Stone", "Dense Sharpening Stone",
			"Coarse Grinding Stone", "Heavy Grinding Stone", "Solid Grinding Stone", "Dense Grinding Stone",
			"Silver Rod", "Golden Rod", "Truesilver Rod", "Arcanite Rod",
			"Golden Skeleton Key", "Truesilver Skeleton Key", "Arcanite Skeleton Key",
		}
	},
	{
		name = "BS: Crafted Gear",
		items = {
			"Golden Scale Shoulders", "Golden Scale Boots", "Golden Scale Coif", "Golden Scale Bracers",
			"Shining Silver Breastplate", "Iron Belt Buckle", "Deadly Bronze Poniard",
			"Big Bronze Knife", "Moonsteel Broadsword", "Massive Iron Axe",
			"Green Iron Hauberk", "Green Iron Bracers", "Green Iron Shoulders", "Green Iron Boots", "Green Iron Helm",
			"Steel Breastplate", "Ornate Mithril Pants", "Ornate Mithril Gloves", "Ornate Mithril Shoulder",
			"Imperial Plate Chestpiece", "Imperial Plate Helm", "Imperial Plate Shoulders",
			"Imperial Plate Legguards", "Imperial Plate Boots", "Imperial Plate Bracers", "Imperial Plate Belt",
			"Thorium Armor", "Thorium Belt", "Thorium Bracers", "Thorium Boots",
			"Thorium Helm", "Thorium Leggings", "Dark Iron Pulverizer", "Dark Iron Mail",
			"Dark Iron Bracers", "Helm of the Great Chief", "Dawnbringer Shoulders",
		}
	},
	{
		name = "BS: Ores, Bars & Stones",
		items = {
			"Copper Ore", "Copper Bar", "Tin Ore", "Tin Bar", "Bronze Bar",
			"Silver Ore", "Silver Bar", "Iron Ore", "Iron Bar", "Steel Bar",
			"Gold Ore", "Gold Bar", "Mithril Ore", "Mithril Bar",
			"Truesilver Ore", "Truesilver Bar", "Thorium Ore", "Thorium Bar",
			"Dark Iron Ore", "Dark Iron Bar", "Arcanite Bar",
			"Rough Stone", "Coarse Stone", "Heavy Stone", "Solid Stone", "Dense Stone",
		}
	},
	{
		name = "Flips: High-Demand Materials",
		items = {
			"Elemental Earth", "Elemental Fire", "Elemental Water", "Elemental Air",
			"Essence of Earth", "Essence of Fire", "Essence of Water", "Essence of Air",
			"Essence of Undeath", "Living Essence",
			"Core of Earth", "Heart of Fire", "Globe of Water", "Breath of Wind",
			"Arcane Crystal", "Righteous Orb", "Larval Acid", "Black Lotus",
			"Blood of the Mountain", "Dark Rune", "Demonic Rune",
		}
	},
	{
		name = "Flips: Cloth, Leather & Gems",
		items = {
			"Linen Cloth", "Wool Cloth", "Silk Cloth", "Mageweave Cloth", "Runecloth",
			"Felcloth", "Mooncloth",
			"Light Leather", "Medium Leather", "Heavy Leather", "Thick Leather",
			"Rugged Leather", "Cured Rugged Hide", "Devilsaur Leather",
			"Malachite", "Tigerseye", "Shadowgem", "Moss Agate", "Lesser Moonstone",
			"Jade", "Citrine", "Aquamarine", "Star Ruby", "Large Opal", "Blue Sapphire",
			"Huge Emerald", "Azerothian Diamond", "Black Vitriol",
		}
	},
	{
		name = "Flips: Potions, Elixirs & Herbs",
		items = {
			"Free Action Potion", "Living Action Potion", "Swiftness Potion",
			"Limited Immunity Potion", "Greater Stoneshield Potion",
			"Elixir of the Mongoose", "Elixir of Giants", "Elixir of Greater Agility",
			"Greater Arcane Elixir", "Major Healing Potion", "Major Mana Potion",
			"Shadow Oil", "Frost Oil", "Fire Oil", "Blackmouth Oil",
			"Oily Blackmouth", "Firefin Snapper",
			"Grave Moss", "Fadeleaf", "Ghost Mushroom", "Blindweed", "Gromsblood",
			"Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Wildvine",
		}
	},
	{
		name = "Flips: Twink & World BoE Epics",
		items = {
			"Shadowfang", "Assassin's Blade", "Feet of the Lynx", "Fang of the Mystics",
			"Blackvenom Blade", "Staff of Jordan", "Bow of Searing Arrows", "Duskbringer",
			"Underworld Band", "Freezing Band", "Krol Blade", "Kang the Decapitator",
			"Flurry Axe", "Nightblade", "Skullflame Shield", "Stockade Pauldrons",
			"Edgemaster's Handguards", "Warden Staff", "Gut Ripper", "Alcor's Sunrazor",
			"Fiery War Axe",
		}
	},
	{
		name = "Flips: Valuable Recipes & Plans",
		items = {
			"Formula: Enchant Weapon - Crusader", "Formula: Enchant Weapon - Healing Power",
			"Formula: Enchant Weapon - Spell Power", "Formula: Enchant Weapon - Lifestealing",
			"Formula: Enchant 2H Weapon - Agility",
			"Recipe: Elixir of Giant Growth", "Recipe: Free Action Potion",
			"Recipe: Greater Fire Protection Potion", "Recipe: Greater Nature Protection Potion",
			"Recipe: Greater Shadow Protection Potion", "Recipe: Greater Arcane Protection Potion",
			"Recipe: Major Mana Potion", "Recipe: Savory Deviate Delight",
			"Recipe: Flask of the Titans", "Recipe: Flask of Supreme Power",
			"Recipe: Flask of Distilled Wisdom",
			"Plans: Iron Counterweight", "Plans: Golden Scale Shoulders",
			"Plans: Moonsteel Broadsword", "Plans: Mithril Shield Spike",
			"Plans: Thorium Shield Spike", "Plans: Stronghold Gauntlets",
			"Plans: Titanic Leggings", "Plans: Helm of the Great Chief",
			"Pattern: Devilsaur Gauntlets", "Pattern: Devilsaur Leggings",
			"Pattern: Hide of the Wild", "Pattern: Robe of the Archmage",
			"Pattern: Robe of the Void", "Schematic: Discombobulator Ray",
			"Schematic: Spellpower Goggles Xtreme",
		}
	},
};

function Atr_InstallProShoppingLists (force)
	if (AUCTIONATOR_SHOPPING_LISTS == nil) then
		AUCTIONATOR_SHOPPING_LISTS = {};
		Atr_SList.create(ZT("Recent Searches"), true);
	end

	-- Remove obsolete WotLK sample list if present
	local num = getn(AUCTIONATOR_SHOPPING_LISTS);
	local x;
	for x = num, 1, -1 do
		if (AUCTIONATOR_SHOPPING_LISTS[x] and AUCTIONATOR_SHOPPING_LISTS[x].name == "Sample Shopping List #1") then
			table.remove(AUCTIONATOR_SHOPPING_LISTS, x);
		end
	end

	local d, i;
	for d = 1, getn(PRO_SHOPPING_LISTS) do
		local def = PRO_SHOPPING_LISTS[d];
		local existingIndex = 0;
		for x = 1, getn(AUCTIONATOR_SHOPPING_LISTS) do
			if (AUCTIONATOR_SHOPPING_LISTS[x].name == def.name) then
				existingIndex = x;
				break;
			end
		end

		if (force and existingIndex > 0) then
			table.remove(AUCTIONATOR_SHOPPING_LISTS, existingIndex);
			existingIndex = 0;
		end

		if (existingIndex == 0) then
			local slist = Atr_SList.create(def.name);
			for i = 1, getn(def.items) do
				slist:AddItem(def.items[i]);
			end
			slist.isSorted = true;
		end
	end

	table.sort(AUCTIONATOR_SHOPPING_LISTS, Atr_SortSlists);

	if (Atr_DropDownSL and UIDropDownMenu_Initialize) then
		UIDropDownMenu_Initialize(Atr_DropDownSL, Atr_DropDownSL_Initialize);
	end
end

function Atr_ShoppingListsInit ()

	local num = getn(AUCTIONATOR_SHOPPING_LISTS);
	local x;
	
	for x = 1,num do
		setmetatable (AUCTIONATOR_SHOPPING_LISTS[x], Atr_SList);
	end

	-- Automatically install pro shopping lists if not yet loaded
	local hasProList = false;
	for x = 1, num do
		if (AUCTIONATOR_SHOPPING_LISTS[x].name == "BS: Consumables & Rods") then
			hasProList = true;
			break;
		end
	end

	if (not hasProList) then
		Atr_InstallProShoppingLists(false);
	end
end

-----------------------------------------

function Atr_SList.create (name, isRecents)

	local slist = {};
	setmetatable (slist,Atr_SList);

	slist.name		= name;
	slist.items		= {};
	
	if (isRecents) then
		slist.isRecents = 1;
	end
	
	table.insert (AUCTIONATOR_SHOPPING_LISTS, slist);

	table.sort (AUCTIONATOR_SHOPPING_LISTS, Atr_SortSlists);
	
	return slist;
end


-----------------------------------------

function Atr_SortSlists (x, y)

	if (x.isRecents) then return true; end;
	if (y.isRecents) then return false; end;

	return (string.lower(x.name) < string.lower(y.name));

end

-----------------------------------------

function Atr_SList:AddItem (itemName)

	if (itemName == "" or itemName == nil) then
		return;
	end

	if (self.isRecents) then
		table.insert (self.items, 1, itemName);
		
		while (getn(self.items) > 50) do		-- max 50 items on recents list
			table.remove (self.items);
		end
	else
		table.insert (self.items, itemName);
		self.isSorted = false;
	end

	
end

-----------------------------------------

function Atr_SList:RemoveItem (itemName)

	local num = getn(self.items);
	local n;
	
	for n = 1,num do
		if (zc.StringSame (self.items[n], itemName)) then
			table.remove (self.items, n);
			return;
		end
	end

end

-----------------------------------------

function Atr_DisplaySlist ()
	if (gCurrentSList) then
		gCurrentSList:DisplayX ();
	end
end



-----------------------------------------

function sortSlist (x, y)

	return (string.lower(x) < string.lower(y));

end

-----------------------------------------

function Atr_SList:DisplayX ()

	gCurrentSList = self;

	local currentPane = Atr_GetCurrentPane();

	if (not (self.isRecents or self.isSorted)) then
		self.isSorted = true;
		table.sort (self.items, sortSlist);
	end


	local numrows = getn(self.items);

	local line;							-- 1 through NN of our window to scroll
	local dataOffset;					-- an index into our data calculated from the scroll offset

	FauxScrollFrame_Update (Atr_Hlist_ScrollFrame, numrows, SLITEMS_NUM_LINES, 16);

	for line = 1,SLITEMS_NUM_LINES do

		currentPane.hlistScrollOffset = FauxScrollFrame_GetOffset (Atr_Hlist_ScrollFrame);
		
		dataOffset = line + currentPane.hlistScrollOffset;

		local lineEntry = getglobal ("AuctionatorHEntry"..line);

		lineEntry:SetID(dataOffset);

		local slItem = self.items[dataOffset];
		
		if (dataOffset <= numrows and slItem) then

			local lineEntry_text = getglobal("AuctionatorHEntry"..line.."_EntryText");

			lineEntry_text:SetText		(Atr_AbbrevItemName (slItem));
			lineEntry_text:SetTextColor	(.6,.6,.6);

			if (currentPane.activeSearch.origSearchText ~= "" and zc.StringSame (slItem , currentPane.activeSearch.origSearchText)) then
				Atr_SetRowSelected (lineEntry, true);
			elseif (currentPane.activeSearch.searchText == "" and zc.StringSame (slItem , Atr_Search_Box:GetText())) then
				Atr_SetRowSelected (lineEntry, true);
			else
				Atr_SetRowSelected (lineEntry, false);
			end

			lineEntry:Show();
		else
			lineEntry:Hide();
		end
	end


end

-----------------------------------------

function Atr_SList:FindItemIndex (itemName)

	local num = getn(self.items);
	local n;
	
	for n = 1,num do
		if (zc.StringSame (itemName, self.items[n])) then
			return n;
		end
	end
	
	return 0;

end

-----------------------------------------

function Atr_SList:IsItemOnList (itemName)

	return (self:FindItemIndex(itemName) > 0);
	
end

-----------------------------------------

function Atr_Search_Onclick ()

	local currentPane = Atr_GetCurrentPane();

	local searchText = Atr_Search_Box:GetText();

	Atr_Search_Button:Disable();
	Atr_Buy1_Button:Disable();
	Atr_AddToSListButton:Disable();
	Atr_RemFromSListButton:Disable();
	
	Atr_ClearAll();
	
	currentPane:DoSearch (searchText);

	Atr_Process_Historydata ();
end

-----------------------------------------

function Atr_Shop_OnFinishScan ()
	
	local currentPane = Atr_GetCurrentPane();

	local searchText = currentPane.activeSearch.origSearchText;

	Atr_Search_Box:SetText (searchText);
	
	local recentsList = AUCTIONATOR_SHOPPING_LISTS[1];
	if (recentsList) then

		local isRecentsShown = (gCurrentSList == recentsList);
		
		local n = recentsList:FindItemIndex(searchText);

		if (n > 14 or (not isRecentsShown and n > 0)) then
			table.remove (recentsList.items, n);
		end
		
		n = recentsList:FindItemIndex(searchText);
		
		if (n == 0) then
			recentsList:AddItem (searchText);
		end
		
		if (isRecentsShown) then
			FauxScrollFrame_SetOffset (Atr_Hlist_ScrollFrame, 0);
		end
		
	end

	if (getn(currentPane.activeScan.sortedData) > 0 and not currentPane.pickKey) then
		currentPane.currIndex = 1;
	end

	-- Live update: capture lowest buyout from search results immediately into price databases
	if (currentPane and currentPane.activeScan and currentPane.activeScan.absoluteBest) then
		local bestPrice = math.floor(currentPane.activeScan.absoluteBest.itemPrice or 0);
		local iName = currentPane.activeScan.itemName;
		if (bestPrice > 0 and iName and iName ~= "") then
			if (gAtr_ScanDB == nil) then Atr_InitScanDB(); end
			if (gAtr_ScanDB) then gAtr_ScanDB[iName] = bestPrice; end
			if (Atr_RecordHistoricalPrice) then Atr_RecordHistoricalPrice(iName, bestPrice); end
		end
	end

	currentPane.UINeedsUpdate = true;
	
	Atr_Search_Button:Enable();
end


-----------------------------------------

function Atr_DropDownSL_OnLoad (self)
	UIDropDownMenu_Initialize(self, Atr_DropDownSL_Initialize);
	UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, 1);
	Atr_DropDownSL:Show();
end

-----------------------------------------

function Atr_DropDownSL_Initialize()

	local info = UIDropDownMenu_CreateInfo();

	local num = getn(AUCTIONATOR_SHOPPING_LISTS);
	local x;
	
	for x = 1,num do
	
		local slist = AUCTIONATOR_SHOPPING_LISTS[x];
		
		info.text = slist.name;
		info.value = x;
		info.func = Atr_DropDownSL_OnClick;
		info.checked = nil;
		info.owner = Atr_DropDownSL;

--		info.colorCode = nil;
		
--		if (slist.isRecents) then
--			info.colorCode = "|c00ffddaa";
--		end


		UIDropDownMenu_AddButton(info);

	end

end

-----------------------------------------

function Atr_DropDownSL_OnClick()

	UIDropDownMenu_SetSelectedValue(this.owner, this.value);

	gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[this.value];
	
	Atr_SetUINeedsUpdate();

end

-----------------------------------------

function Atr_SEntryOnClick ()

	local line			= this;
	local entryIndex	= line:GetID();

	local itemName = gCurrentSList.items[entryIndex];
	
	Atr_Search_Box:SetText (itemName);

	if (IsAltKeyDown()) then
		Atr_GetCurrentPane():ClearSearch();
		Atr_RemFromSListOnClick();
	else
		Atr_Search_Onclick ();
	end
	
	Atr_Shop_UpdateUI();

--	gCurrentSList:DisplayX();		-- for the highlight
end



-----------------------------------------

local function FinishCreateNewSList(text)

	local slist = Atr_SList.create(text);

	local num = getn(AUCTIONATOR_SHOPPING_LISTS);
	local n;
	
	for n = 1,num do
		if (AUCTIONATOR_SHOPPING_LISTS[n] == slist) then
			UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, n);
			UIDropDownMenu_SetText (text, Atr_DropDownSL);	-- needed to fix bug in UIDropDownMenu
			slist:DisplayX();
			Atr_SetUINeedsUpdate();
			break;
		end
	end
	

end

-----------------------------------------

StaticPopupDialogs["ATR_NEW_SHOPPING_LIST"] = {
	text = "",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnAccept = function()
		local text = getglobal(this:GetParent():GetName().."EditBox"):GetText();
		FinishCreateNewSList (text);
	end,
	EditBoxOnEnterPressed = function()
		local text = this:GetText();
		FinishCreateNewSList (text);
		this:GetParent():Hide();
	end,
	OnShow = function()
		getglobal(this:GetName().."EditBox"):SetText("");
		getglobal(this:GetName().."EditBox"):SetFocus();
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
};

-----------------------------------------

StaticPopupDialogs["ATR_DEL_SHOPPING_LIST"] = {
	text = "",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		local x;
		for x = 1,getn(AUCTIONATOR_SHOPPING_LISTS) do
			if (AUCTIONATOR_SHOPPING_LISTS[x] == gCurrentSList) then
				table.remove (AUCTIONATOR_SHOPPING_LISTS, x);
				gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[1];
				UIDropDownMenu_SetSelectedValue(Atr_DropDownSL, 1);
				UIDropDownMenu_SetText (gCurrentSList.name, Atr_DropDownSL);
				Atr_SetUINeedsUpdate();
				return;
			end
		end
	end,
	OnShow = function()
		local s = string.format (ZT("Really delete the shopping list %s ?"), ": \n\n"..gCurrentSList.name);

		getglobal(this:GetName().."Text"):SetText("\n"..s.."\n\n");
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
};

-----------------------------------------

function Atr_NewSlist_OnClick ()

	StaticPopupDialogs["ATR_NEW_SHOPPING_LIST"].text = ZT("Name for your new shopping list");

	StaticPopup_Show("ATR_NEW_SHOPPING_LIST");
	
end

-----------------------------------------

function Atr_DelSList_OnClick ()

	StaticPopup_Show("ATR_DEL_SHOPPING_LIST");
	
end



-----------------------------------------

function Atr_AddToSListOnClick ()

	local currentPane = Atr_GetCurrentPane();

	if (gCurrentSList) then
		if (getn(gCurrentSList.items) >= 50) then
			Atr_Error_Text:SetText (string.format (ZT("You may have no more than\n\n%d items on a shopping list."), 50));
			Atr_Error_Frame.withMask = 1;
			Atr_Error_Frame:Show ();
		else		
			gCurrentSList:AddItem (Atr_Search_Box:GetText());
			Atr_SetUINeedsUpdate();
		end
	end

end

-----------------------------------------

function Atr_RemFromSListOnClick ()

	local currentPane = Atr_GetCurrentPane();

	if (gCurrentSList) then
		gCurrentSList:RemoveItem (Atr_Search_Box:GetText());
		Atr_SetUINeedsUpdate();

	end

end


-----------------------------------------

function Atr_Shop_UpdateUI ()

	local currentPane = Atr_GetCurrentPane();

	Atr_AddToSListButton:Disable();
	Atr_RemFromSListButton:Disable();
	Atr_DelSListButton:Disable();
	
	if (gCurrentSList == nil) then
		gCurrentSList = AUCTIONATOR_SHOPPING_LISTS[1];
	end

	if (gCurrentSList) then
		gCurrentSList:DisplayX ();
	
		local iName = Atr_Search_Box:GetText();

		if (gCurrentSList:IsItemOnList (iName)) then
			Atr_RemFromSListButton:Enable();
		elseif (iName ~= "" and iName ~= nil and gCurrentSList ~= AUCTIONATOR_SHOPPING_LISTS[1]) then		-- hack
			Atr_AddToSListButton:Enable();
		end
		
		if (gCurrentSList ~= AUCTIONATOR_SHOPPING_LISTS[1]) then
			Atr_DelSListButton:Enable();
		end
		
	end
	
	if (currentPane.activeSearch:NumScans() > 1 and not currentPane:IsScanEmpty()) then
		Atr_Back_Button:Show();
	else
		Atr_Back_Button:Hide();
	end
	
end


