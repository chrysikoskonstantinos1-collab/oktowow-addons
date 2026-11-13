
local addonName, addonTable = "Auctionator", AtrNS; 
local zc = addonTable.zc;

KM_NULL_STATE	= 0;
KM_PREQUERY		= 1;
KM_INQUERY		= 2;
KM_POSTQUERY	= 3;
KM_ANALYZING	= 4;
KM_SETTINGSORT	= 5;

local AUCTION_CLASS_WEAPON = 1;
local AUCTION_CLASS_ARMOR  = 2;

local gAllScans = {};

local BIGNUM = 999999999999;

local ATR_SORTBY_NAME_ASC = 0;
local ATR_SORTBY_NAME_DES = 1;
local ATR_SORTBY_PRICE_ASC = 2;
local ATR_SORTBY_PRICE_DES = 3;

-----------------------------------------

AtrScan = {};
AtrScan.__index = AtrScan;

-----------------------------------------

AtrSearch = {};
AtrSearch.__index = AtrSearch;

-----------------------------------------

function Atr_NewSearch (itemName, exact, rescanThreshold, callback)

	local srch = {};
	setmetatable (srch, AtrSearch);
	srch:Init (itemName, exact, rescanThreshold, callback);

	return srch;
end

-----------------------------------------

function AtrSearch:Init (searchText, exact, rescanThreshold, callback)

	if (searchText == nil) then
		searchText = "";
	end

	self.origSearchText = searchText;
	
	if (not exact) then
		if (zc.StringStartsWith (searchText, "\"") and zc.StringEndsWith (searchText, "\"")) then
			searchText = string.sub (searchText, 2, string.len(searchText)-1);
			exact = true;
		end
	end		

	self.searchText			= searchText;
	self.exact				= exact;
	self.processing_state	= KM_NULL_STATE
	self.current_page		= -1
	self.items				= {};
	self.query				= Atr_NewQuery();
	self.sortedScans		= nil;
	self.sortHow			= ATR_SORTBY_PRICE_ASC;
	self.callback			= callback;
	
	if (exact) then	

		if (rescanThreshold and rescanThreshold > 0) then
			local scan = Atr_FindScan (searchText);
			if (scan and (time() - scan.whenScanned) <= rescanThreshold) then
				self.items[searchText] = scan;
			end
		end
		
		if (not self.items[searchText]) then		
			self.items[searchText] = Atr_FindScanAndInit (searchText);
		end
		
	end
	
end

-----------------------------------------

function Atr_FindScanAndInit (itemName)

	return Atr_FindScan (itemName, true);
end

-----------------------------------------

function Atr_FindScan (itemName, init)

	if (itemName == nil or itemName == "") then
		itemName = "nil";
	end

	local itemNameLC = string.lower (itemName);

	if (gAllScans[itemNameLC] == nil) then

		local scn = {};
		setmetatable (scn, AtrScan);
		scn:Init (itemName);

		gAllScans[itemNameLC] = scn;
	elseif (init) then
		gAllScans[itemNameLC]:Init (itemName);
	end
	
	return gAllScans[itemNameLC];
end

-----------------------------------------

function Atr_ClearScanCache ()

--	zc.msg_red ("Clearing Scan Cache");

	for a,v in pairs (gAllScans) do
		if (a ~= "nil") then
			gAllScans[a] = nil;
		end
	end

end

-----------------------------------------

function AtrScan:Init (itemName)
	self.itemName			= itemName;
	self.itemLink			= nil;
	self.scanData			= {};
	self.sortedData			= {};
	self.whenScanned		= 0;
	self.lowprices			= {BIGNUM, BIGNUM, BIGNUM};
	self.absoluteBest		= nil;
	self.itemClass			= 0;
	self.itemSubclass		= 0;
	self.yourBestPrice		= nil;
	self.yourWorstPrice		= nil;
	self.numYourSingletons	= 0;
	self.itemTextColor 		= { 1.0, 1.0, 1.0 };
	self.searchWasExact		= false;
	
	self:UpdateItemLink (Atr_GetItemLink (itemName));
end

-----------------------------------------

function AtrScan:UpdateItemLink (itemLink)

	self.itemLink = itemLink;
	
	if (itemLink) then
	
		Atr_AddToItemLinkCache (self.itemName, itemLink);

		local _, _, quality, _, _, sType, sSubType = Atr_GetItemInfo (itemLink);

		self.itemQuality	= quality;
		self.itemClass		= Atr_ItemType2AuctionClass (sType);
		self.itemSubclass	= Atr_SubType2AuctionSubclass (self.itemClass, sSubType);	

		self.itemTextColor = { 1.0, 1.0, 1.0 };

		if (quality == 0)	then	self.itemTextColor = { 0.6, 0.6, 0.6 };	end
		if (quality == 2)	then	self.itemTextColor = { 0.2, 1.0, 0.0 };	end
		if (quality == 3)	then	self.itemTextColor = { 0.0, 0.5, 1.0 };	end
		if (quality == 4)	then	self.itemTextColor = { 0.7, 0.3, 1.0 };	end
	end

end


-----------------------------------------

function AtrSearch:NumScans()

	if (self.sortedScans) then
		return getn(self.sortedScans);
	end

	local count = 0;
	for name,scn in pairs (self.items) do
		count = count + 1;
	end

	return count;
end

-----------------------------------------

function AtrSearch:NumSortedScans()

	if (self.sortedScans) then
		return getn(self.sortedScans);
	end

	return 0;
end

-----------------------------------------

function AtrSearch:GetFirstScan()

	if (self.sortedScans) then
		return self.sortedScans[1];
	end

	for name,scn in pairs (self.items) do
		return scn;
	end
	
	return nil;

end


-----------------------------------------

function AtrSearch:Start ()

	if (self.searchText == "") then
		return;
	end
	
	if (self:IsCompoundSearch (self.searchText)) then
			
		local _, itemClass = self:ParseCompoundSearch (self.searchText);
	
		if (itemClass == 0) then
			Atr_Error_Display (ZT("The first part of this compound\n\nsearch is not a valid category."));
			return;
		end
	end
	
	self.processing_state = KM_SETTINGSORT;
	
	Atr_SortAuctionClearSort ("list");

	BrowseName:SetText (self.searchText);		-- not necessary but nice when user switches to Browse tab

	self.current_page		= 0;
	self.processing_state	= KM_PREQUERY;

	self:Continue();
	
end

-----------------------------------------

function AtrSearch:Abort ()

	if (self.processing_state == KM_NULL_STATE) then
		return;
	end

	self.processing_state = KM_NULL_STATE;
	self:Init();
end

-----------------------------------------

function AtrSearch:CheckForDuplicatePage ()

	local isDup = self.query:CheckForDuplicatePage(self.current_page);

	if (isDup) then
--		zc.msg_red ("DUPLICATE PAGE FOUND: ", "  current_page: ", self.current_page, "  numDupPages: ", self.query.numDupPages);

		self.current_page	= self.current_page - 1;   -- requery the page
		
		self.processing_state = KM_PREQUERY;
	end
		
	return isDup;
end


-----------------------------------------

function AtrSearch:AnalyzeResultsPage()

	self.processing_state = KM_ANALYZING;

	if (self.query.numDupPages > 10) then 	 -- hopefully this will never happen but need check to avoid looping
		return true;						 -- done
	end


	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	self.totalPages = math.ceil (totalAuctions / 50);

	if (self.current_page == 1 and totalAuctions > 2000) then -- give Blizz servers a break
		Atr_Error_Display (ZT("Too many results\n\nPlease narrow your search"));
		return true;  -- done
	end

	if (totalAuctions >= 50) then
		Atr_SetMessage (string.format (ZT("Scanning auctions: page %d"), self.current_page).." / "..self.totalPages);
	end

	-- analyze

	local numNilOwners = 0;

	if (numBatchAuctions > 0) then

		local x;

		for x = 1, numBatchAuctions do

			local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", x);

			if (owner == nil) then
				numNilOwners = numNilOwners + 1;
			end
			
			local exactMatch = zc.StringSame (name, self.searchText);

			if (exactMatch or not self.exact) then

				if (self.items[name] == nil) then
					self.items[name] = Atr_FindScanAndInit (name);
				end
				
				local curpage = (tonumber(self.current_page)-1);

				local scn = self.items[name];

				scn:AddScanItem (name, count, buyoutPrice, owner, 1, curpage);
				
				if (scn.itemLink == nil or self.itemClass == nil) then
					scn:UpdateItemLink (GetAuctionItemLink("list", x));
				end

				if (self.callback) then
					self.callback (x, numBatchAuctions, count, buyoutPrice, owner);
				end
				
			end
		end
	end
	
	local done = (numBatchAuctions < 50);

	if (not done) then
		self.processing_state = KM_PREQUERY;
	end
	
	return done;
end

-----------------------------------------

function AtrScan:AddScanItem (name, stackSize, buyoutPrice, owner, numAuctions, curpage)

	local sd = {};
	local i;

	if (numAuctions == nil) then
		numAuctions = 1;
	end

	for i = 1, numAuctions do
		sd["stackSize"]		= stackSize;
		sd["buyoutPrice"]	= buyoutPrice;
		sd["owner"]			= owner;
		sd["pagenum"]		= curpage;

		tinsert (self.scanData, sd);
		
		local itemPrice = math.floor (buyoutPrice / stackSize);

		Atr_AddToLowPrices (self.lowprices, itemPrice);
	end

end


-----------------------------------------

function AtrScan:AddSDXToScan (price, owner, volume)	-- helper function for AddExternalDataToScan

	local sd = {};

	if (price and price > 0) then
		sd["stackSize"]		= 1;
		sd["buyoutPrice"]	= price;
		sd["owner"]			= owner;

		if (volume) then
			sd["volume"] = volume;
		end

		tinsert (self.scanData, sd);
	end
	
end

-----------------------------------------

function AtrScan:AddExternalDataToScan ()

	if (self.itemLink == nil) then
		return;
	end

	-- Wowecon

	if (Wowecon and Wowecon.API) then
	
		local priceG, volG = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.GLOBAL_PRICE)
		local priceS, volS = Wowecon.API.GetAuctionPrice_ByLink (self.itemLink, Wowecon.API.SERVER_PRICE)

		self:AddSDXToScan (priceG, "__wowEconG", volG);
		self:AddSDXToScan (priceS, "__wowEconS", volS);
		
	end
	
	-- GoingPrice Wowhead
	
	local id = zc.ItemIDfromLink (self.itemLink);
	
	id = tonumber(id);

	if (GoingPrice_Wowhead_Data and GoingPrice_Wowhead_Data[id] and GoingPrice_Wowhead_SV._index) then
		local index = GoingPrice_Wowhead_SV._index["Buyout price"];

		if (index ~= nil) then
			local price = GoingPrice_Wowhead_Data[id][index];
		
			self:AddSDXToScan (price, "__wowHead");
		end
	end

	-- GoingPrice Allakhazam
	
	if (GoingPrice_Allakhazam_Data and GoingPrice_Allakhazam_Data[id] and GoingPrice_Allakhazam_SV._index) then
		local index = GoingPrice_Allakhazam_SV._index["Median"];

		if (index ~= nil) then
			local price = GoingPrice_Allakhazam_Data[id][index];
		
			self:AddSDXToScan (price, "__allakhazam");
		end
	end

	-- most recent historical price
	
	local price = Atr_Process_Historydata();
	if (price ~= nil) then
		self:AddSDXToScan (price, "__atrLast");
	end

end

-----------------------------------------

function AtrScan:SubtractScanItem (name, stackSize, buyoutPrice)

	local sd;
	local i;

	for i,sd in ipairs (self.scanData) do
		
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice) then
			
			tremove (self.scanData, i);
			return;
		end
	end

end

-----------------------------------------

function AtrSearch:IsCompoundSearch (searchString)
	
	return zc.StringContains (searchString, ">");
end

-----------------------------------------

function AtrSearch:ParseCompoundSearch (searchString)

	local tbl	= { Atr_strsplit (">", searchString) };
	
	local queryString	= "";
	local itemClass		= 0;
	local itemSubclass	= 0;
	local minLevel		= nil;
	local maxLevel		= nil;
	local prevWasItemClass;
	local n;
	
	for n = 1,getn(tbl) do
		local s = tbl[n];

		local handled = false;

		if (not handled and tonumber(s)) then
			if (minLevel == nil) then
				minLevel = tonumber(s);
			elseif (maxLevel == nil) then
				maxLevel = tonumber(s);
			end
			
			handled = true;
			prevWasItemClass = false;
		end
		
		if (not handled and prevWasItemClass and itemSubclass == 0) then
			itemSubclass = Atr_SubType2AuctionSubclass (itemClass, s);
			if (itemSubclass > 0) then
				handled = true;
				prevWasItemClass = false;
			end
		end
		
		if (not handled and itemClass == 0) then
			itemClass = Atr_ItemType2AuctionClass (s);
			if (itemClass > 0) then
				prevWasItemClass = true;
				handled = true;
			end
		end
		
		if (not handled) then
			queryString = s;
			handled = true;
		end
	end	

	return queryString, itemClass, itemSubclass, minLevel, maxLevel;
end

-----------------------------------------

function AtrSearch:Continue()

	if (Atr_CanSendAuctionQuery ()) then

		self.processing_state = KM_IN_QUERY;

		local queryString = self.searchText;

		queryString = zc.UTF8_Truncate (queryString,63);	-- attempting to reduce number of disconnects

--	zc.md (queryString.."  page:"..self.current_page);
		
		local itemClass		= 0;
		local itemSubclass	= 0;
		local minLevel		= nil;
		local maxLevel		= nil;
		
		-- (the 3.x port narrowed exact searches by item class here; a plain name query is the safest on 1.12)

		if (self:IsCompoundSearch(queryString)) then
		
			queryString, itemClass, itemSubclass, minLevel, maxLevel = self:ParseCompoundSearch (queryString);
		
		end

		Atr_QueryAuctionItems (queryString, minLevel, maxLevel, nil, itemClass, itemSubclass, self.current_page, nil, nil);

		self.query_sent_when	= gAtr_ptime;
		self.namesWaitStart		= nil;
		self.processing_state	= KM_POSTQUERY;
		self.current_page		= self.current_page + 1;
	end

end

-----------------------------------------

local gSortScansBy;

-----------------------------------------

local function Atr_SortScans (x, y)

	if (gSortScansBy == ATR_SORTBY_NAME_ASC) then		return string.lower (x.itemName) < string.lower (y.itemName);	end
	if (gSortScansBy == ATR_SORTBY_NAME_DES) then		return string.lower (x.itemName) > string.lower (y.itemName);	end

	local xprice = 0;
	local yprice = 0;
	
	if (x.absoluteBest) then	xprice = zc.round(x.absoluteBest.buyoutPrice/x.absoluteBest.stackSize);		end;
	if (y.absoluteBest) then	yprice = zc.round(y.absoluteBest.buyoutPrice/y.absoluteBest.stackSize);		end;
	
	if (gSortScansBy == ATR_SORTBY_PRICE_ASC) then		return xprice < yprice;		end
	if (gSortScansBy == ATR_SORTBY_PRICE_DES) then		return xprice > yprice;		end

end

-----------------------------------------

function AtrSearch:Finish()

	local finishTime = time();
	
	self.processing_state	= KM_NULL_STATE;
	self.current_page		= -1;
	self.query_sent_when	= nil;
	
	self.sortedScans = nil;
	
	local wasExactSearch = (self:NumScans() == 1);		-- search returned only 1 item
	
	local x = 1;
	self.sortedScans = {};
	
	for name,scn in pairs (self.items) do
	
		self.sortedScans[x] = scn;
		x = x + 1;
		
		scn.whenScanned		= finishTime;
		scn.searchWasExact	= wasExactSearch;

		scn:CondenseAndSort ();

		-- update the fullscan DB
		
		local newprice = Atr_CalcNewDBprice (scn.itemName, scn.lowprices);
		
		if (newprice > 0) then
			local q = scn.itemQuality or 1; local minQual = AUCTIONATOR_SCAN_MINLEVEL or 1; if (q + 1 >= minQual) then if (gAtr_ScanDB == nil) then Atr_InitScanDB(); end if (gAtr_ScanDB) then gAtr_ScanDB[scn.itemName] = newprice; end if Atr_RecordHistoricalPrice then Atr_RecordHistoricalPrice(scn.itemName, newprice); end end



		end
	end
	
	Atr_ClearBrowseListings();
	
	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
	
end

-----------------------------------------

-- 1.12 port: show what has been found so far while the remaining pages are still coming in

function AtrSearch:UpdatePartial()

	local single = (self:NumScans() == 1);
	local x = 1;

	self.sortedScans = {};

	for name,scn in pairs (self.items) do
		self.sortedScans[x] = scn;
		x = x + 1;
		scn.searchWasExact = single;
		scn:CondenseAndSort ();
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:IsActive()
	return (self.processing_state ~= KM_NULL_STATE);
end

-----------------------------------------
-- a purchase takes over the auction queries: ask for the page whose answer may get lost again later

function AtrSearch:Pause()

	if (self.processing_state == KM_POSTQUERY or self.processing_state == KM_IN_QUERY) then
		self.current_page		= self.current_page - 1;
		self.processing_state	= KM_PREQUERY;
	end

	self.namesWaitStart = nil;
end

-----------------------------------------

function AtrSearch:ClickPriceCol()

	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		self.sortHow = ATR_SORTBY_PRICE_DES;
	else
		self.sortHow = ATR_SORTBY_PRICE_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);

end

-----------------------------------------

function AtrSearch:ClickNameCol()

	if (self.sortHow == ATR_SORTBY_NAME_ASC) then
		self.sortHow = ATR_SORTBY_NAME_DES;
	else
		self.sortHow = ATR_SORTBY_NAME_ASC;
	end

	gSortScansBy = self.sortHow;
	table.sort (self.sortedScans, Atr_SortScans);
end

-----------------------------------------

function AtrSearch:UpdateArrows()

	Atr_Col1_Heading_ButtonArrow:Hide();
	Atr_Col3_Heading_ButtonArrow:Hide();
	
	if (self.sortHow == ATR_SORTBY_PRICE_ASC) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_PRICE_DES) then
		Atr_Col1_Heading_ButtonArrow:Show();
		Atr_Col1_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	elseif (self.sortHow == ATR_SORTBY_NAME_ASC) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 0, 1.0);
	elseif (self.sortHow == ATR_SORTBY_NAME_DES) then
		Atr_Col3_Heading_ButtonArrow:Show();
		Atr_Col3_Heading_ButtonArrow:SetTexCoord(0, 0.5625, 1.0, 0);
	end
end

-----------------------------------------

function Atr_ClearBrowseListings()

	-- the 3.x version fired a dummy query to empty the Browse list; on 1.12 that needs a busy wait, so we skip it

end

-----------------------------------------

function Atr_SortAuctionData (x, y)

	if (gAtr_PriceSortDesc) then
		return x.itemPrice > y.itemPrice;
	end

	return x.itemPrice < y.itemPrice;

end

-----------------------------------------

function AtrScan:CondenseAndSort ()

	----- Condense the scan data into a table that has only a single entry per stacksize/price combo

	self.sortedData	= {};

	local i,sd;
	local conddata = {};

	for i,sd in ipairs (self.scanData) do

		local ownerCode = "x";
		local dataType  = "n";		-- normal
		
		if (sd.owner == UnitName("player")) then
			ownerCode = "y";
--		elseif (Atr_IsMyToon (sd.owner)) then
--			ownerCode = sd.owner;
		elseif (sd.owner == "__wowEconG") then
			dataType = "eg";
		elseif (sd.owner == "__wowEconS") then
			dataType = "es";
		elseif (sd.owner == "__wowHead") then
			dataType = "h";
		elseif (sd.owner == "__allakhazam") then
			dataType = "k";
		elseif (sd.owner == "__atrLast") then
			dataType = "a";
		end

		local key = "_"..sd.stackSize.."_"..sd.buyoutPrice.."_"..ownerCode..dataType;

		if (conddata[key]) then
			conddata[key].count		= conddata[key].count + 1;
			conddata[key].minpage 	= zc.Min (conddata[key].minpage, sd.pagenum);
			conddata[key].maxpage 	= zc.Max (conddata[key].maxpage, sd.pagenum);
		else
			local data = {};

			data.stackSize 		= sd.stackSize;
			data.buyoutPrice	= sd.buyoutPrice;
			data.itemPrice		= sd.buyoutPrice / sd.stackSize;
			data.minpage		= sd.pagenum;
			data.maxpage		= sd.pagenum;
			data.count			= 1;
			data.type			= dataType;
			data.yours			= (ownerCode == "y");
			
			if (ownerCode ~= "x" and ownerCode ~= "y") then
				data.altname = ownerCode;
			end
			
			if (sd.volume) then
				data.volume = sd.volume;
			end
			
			conddata[key] = data;
		end

	end

	----- create a table of these entries

	local n = 1;

	local i, v;

	for i,v in pairs (conddata) do
		self.sortedData[n] = v;
		n = n + 1;
	end

	-- sort the table by itemPrice

	table.sort (self.sortedData, Atr_SortAuctionData);

	-- analyze and store some info about the data

	self:AnalyzeSortData ();

end

-----------------------------------------

function AtrScan:AnalyzeSortData ()

	self.absoluteBest			= nil;
	self.bestPrices				= {};		-- a table with one entry per stacksize that is the cheapest auction for that particular stacksize
	self.numMatches				= 0;
	self.numMatchesWithBuyout	= 0;
	self.hasStack				= false;
	self.yourBestPrice			= nil;
	self.yourWorstPrice			= nil;
	self.numYourSingletons		= 0;

	local j, sd;

	----- find the best price per stacksize and overall -----

	for j,sd in ipairs(self.sortedData) do

		if (sd.type == "n") then

			self.numMatches = self.numMatches + 1;

			if (sd.itemPrice > 0) then

				self.numMatchesWithBuyout = self.numMatchesWithBuyout + 1;

				if (self.bestPrices[sd.stackSize] == nil or self.bestPrices[sd.stackSize].itemPrice >= sd.itemPrice) then
					self.bestPrices[sd.stackSize] = sd;
				end

				if (self.absoluteBest == nil or self.absoluteBest.itemPrice > sd.itemPrice) then
					self.absoluteBest = sd;
				end
				
				if (sd.yours) then
					if (self.yourBestPrice == nil or self.yourBestPrice > sd.itemPrice) then
						self.yourBestPrice = sd.itemPrice;
					end
					
					if (self.yourWorstPrice == nil or self.yourWorstPrice < sd.itemPrice) then
						self.yourWorstPrice = sd.itemPrice;
					end
					
					if (sd.stackSize == 1) then
						self.numYourSingletons = self.numYourSingletons + sd.count;
					end
				end
			end

			if (sd.stackSize > 1) then
				self.hasStack = true;
			end
		end
	end
end

-----------------------------------------

function AtrScan:FindInSortedData (stackSize, buyoutPrice)
	local j = 1;
	for j = 1,getn(self.sortedData) do
		sd = self.sortedData[j];
		if (sd.stackSize == stackSize and sd.buyoutPrice == buyoutPrice and sd.yours) then
			return j;
		end
	end
	
	return 0;
end


-----------------------------------------

function AtrScan:FindMatchByStackSize (stackSize)

	local index = nil;

	local basedata = self.absoluteBest;

	if (self.bestPrices[stackSize]) then
		basedata = self.bestPrices[stackSize];
	end

	local numrows = getn(self.sortedData);

	local n;

	for n = 1,numrows do

		local data = self.sortedData[n];

		if (basedata and data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize and data.yours == basedata.yours) then
			index = n;
			break;
		end
	end

	return index;
	
end

-----------------------------------------

function AtrScan:FindMatchByYours ()

	local index = nil;

		local j;
	for j = 1,getn(self.sortedData) do
		local sd = self.sortedData[j];
		if (sd.yours and (index == nil or sd.itemPrice < self.sortedData[index].itemPrice)) then
			index = j;
		end
	end

	return index;

end

-----------------------------------------

function AtrScan:FindCheapest ()

	local index = nil;

		local j;
	for j = 1,getn(self.sortedData) do
		local sd = self.sortedData[j];
		if (sd.itemPrice > 0 and (index == nil or sd.itemPrice < self.sortedData[index].itemPrice)) then
			index = j;
		end
	end

	return index;

end


-----------------------------------------

function AtrScan:GetNumAvailable ()

	local num = 0;

	local j, data;
	for j = 1,getn(self.sortedData) do

		data = self.sortedData[j];
		num = num + (data.count * data.stackSize);
	end
	
	return num;
end

-----------------------------------------

function AtrScan:IsNil ()

	if (self.itemName == nil or self.itemName == "" or self.itemName == "nil") then
		return true;
	end
	
	return false;
end

-----------------------------------------

ATR_FS_NULL			= 0;
ATR_FS_STARTED		= 1;
ATR_FS_ANALYZING	= 2;
ATR_FS_CLEANING_UP	= 3;
ATR_FS_PAUSED		= 4;

gAtr_FullScanState = ATR_FS_NULL;


-----------------------------------------

function Atr_GetDBsize()

	local n = 0;
	local a,v;

	for a,v in pairs (gAtr_ScanDB) do
		n = n + 1;
	end
	
	return n;
end

-----------------------------------------

local gNumAdded, gNumUpdated;

-- The 1.12 client has no "get all" query, so a full scan walks every page of an empty query.
local gFS_page			= 0;
local gFS_pages			= 0;
local gFS_lowprices		= {};
local gFS_qualities		= {};
local gFS_numAuctions	= 0;
local gFS_waiting		= false;
local gFS_sentAt		= 0;
local gFS_startedAt	= 0;
local gFS_lastKeepAlive	= 0;
local gFS_lastPageTime	= 0;
local gFS_retryCount	= 0;
local gFS_lastLiveUIRefresh = 0;
local gFS_lastMiniBarRefresh = 0;
local gFS_elapsedBeforePause = 0;

-----------------------------------------

function Atr_FullScanStart(resume)

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		Atr_FullScanPause();
		return;
	end

	if (resume and gAtr_FullScanState == ATR_FS_PAUSED and gFS_page > 0) then
		gAtr_FullScanState = ATR_FS_STARTED;
		gFS_waiting = false;
		gFS_startedAt = GetTime() - (gFS_elapsedBeforePause or 0);
		gFS_lastKeepAlive = GetTime();
		gFS_lastPageTime = GetTime();
		gFS_retryCount = 0;
		Atr_FullScanStatus:SetText(string.format("Resuming scan at page %d / %d...", gFS_page + 1, gFS_pages or 0));
		if (DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[Auctionator]|r Resuming full scan at page %d / %d...", gFS_page + 1, gFS_pages or 0));
		end
		Atr_UpdateFullScanFrame();
		if (gAtr_ScanIsMinimized) then
			Atr_UpdateScanMiniBar();
		end
		return;
	end

	Atr_FullScanStatus:SetText (ZT("Scanning").."...");
	gAtr_FullScanState = ATR_FS_STARTED;

	gNumAdded = 0;
	gNumUpdated = 0;

	gFS_page		= 0;
	gFS_pages		= 0;
	gFS_lowprices	= {};
	gFS_qualities	= {};
	gFS_numAuctions	= 0;
	gFS_waiting		= false;
	gFS_startedAt	= GetTime();
	gFS_lastKeepAlive = GetTime();
	gFS_lastPageTime  = GetTime();
	gFS_retryCount    = 0;
	gFS_elapsedBeforePause = 0;

	if (Atr_ClearLiveScanDeals) then
		Atr_ClearLiveScanDeals();
	end

	Atr_FullScanResults:Hide();
	Atr_FullScanHTML:Show();
	Atr_UpdateFullScanFrame();
	if (gAtr_ScanIsMinimized) then
		Atr_UpdateScanMiniBar();
	end

end

-----------------------------------------

function Atr_FullScanPause()

	if (gAtr_FullScanState ~= ATR_FS_STARTED) then return; end

	gAtr_FullScanState = ATR_FS_PAUSED;
	gFS_waiting = false;
	gFS_elapsedBeforePause = GetTime() - (gFS_startedAt or GetTime());

	if (Atr_CancelAutoLogout) then Atr_CancelAutoLogout(); end
	Atr_FullScanStatus:SetText(string.format("|cffffcc00Scan paused at page %d / %d|r (prices saved)", gFS_page, gFS_pages or 0));
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffcc00[Auctionator]|r Full scan paused at page %d / %d. All prices up to page %d are saved. Click 'Resume' to continue or 'New Scan' to restart.", gFS_page, gFS_pages or 0, gFS_page));
	end

	Atr_UpdateFullScanFrame();
	if (gAtr_ScanIsMinimized) then
		Atr_UpdateScanMiniBar();
	end
	if (Atr_ProfitFrame and Atr_ProfitFrame:IsShown() and Atr_RefreshProfitUI) then
		Atr_RefreshProfitUI();
	end

end

-----------------------------------------

function Atr_FullScanAbort()

	gAtr_FullScanState = ATR_FS_NULL;
	gFS_waiting = false;
	gFS_lowprices = {};
	gFS_qualities = {};
	gFS_page = 0;
	gFS_pages = 0;

	if (Atr_CancelAutoLogout) then Atr_CancelAutoLogout(); end
	Atr_FullScanStatus:SetText (ZT("Scan stopped"));
	Atr_UpdateFullScanFrame();
	if (gAtr_ScanIsMinimized) then
		Atr_UpdateScanMiniBar();
	end
	if (Atr_RefreshProfitUI) then
		Atr_RefreshProfitUI();
	end

end

-----------------------------------------

function Atr_FullScanDone_OnClick()

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		Atr_FullScanPause();
	end

	if (Atr_CancelAutoLogout) then
		Atr_CancelAutoLogout();
	end

	Atr_FullScanFrame:Hide();

end

-----------------------------------------

function Atr_CalcNewDBprice (name, prices)
		
	if (prices[1] ~= BIGNUM) then
		return prices[1];
	end

	return 0;
	
end

-----------------------------------------

function Atr_AddToLowPrices (lowprices, itemPrice)
	
	if (itemPrice > 0) then
		if (itemPrice < lowprices[1]) then
			if (lowprices[1] < lowprices[2]) then
				lowprices[2] = lowprices[1];
			end
			lowprices[1] = itemPrice;
			return true;
		elseif (itemPrice < lowprices[2]) then
			lowprices[2] = itemPrice;
			return true;
		end
	end

	return false;
end




-----------------------------------------

local gScanDetails = {}

-----------------------------------------

function Atr_FullScanMoreDetails ()

	zc.msg (" ");
	zc.msg_atr (ZT("Auctions scanned")..": |cffffffff", gScanDetails.numBatchAuctions, " |r("..gScanDetails.totalItems, "items)");
	zc.msg_atr ("|cffa335ee   "..ZT("Epic items")..": |r",		gScanDetails.numEachQual[5]);
	zc.msg_atr ("|cff0070dd   "..ZT("Rare items")..": |r",		gScanDetails.numEachQual[4]);
	zc.msg_atr ("|cff1eff00   "..ZT("Uncommon items")..": |r",	gScanDetails.numEachQual[3]);
	zc.msg_atr ("|cffffffff   "..ZT("Common items")..": |r",		gScanDetails.numEachQual[2]);
	zc.msg_atr ("|cff9d9d9d   "..ZT("Poor items")..": |r",		gScanDetails.numEachQual[1]);
	
	
	if (gScanDetails.numRemoved[4] > 0) then		zc.msg_atr (ZT("Rare items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[4]);		end
	if (gScanDetails.numRemoved[3] > 0) then		zc.msg_atr (ZT("Uncommon items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[3]);		end
	if (gScanDetails.numRemoved[2] > 0) then		zc.msg_atr (ZT("Common items").." "..ZT("removed from database")..": |cffffffff",	gScanDetails.numRemoved[2]);		end
	if (gScanDetails.numRemoved[1] > 0) then		zc.msg_atr (ZT("Poor items").." "..ZT("removed from database")..": |cffffffff",		gScanDetails.numRemoved[1]);		end
	
	zc.msg_atr (ZT("Items added to database")..": |cffffffff", gScanDetails.gNumAdded);
	zc.msg_atr (ZT("Items updated in database")..": |cffffffff", gScanDetails.gNumUpdated);
	zc.msg_atr (ZT("Items ignored")..": |cffffffff", gScanDetails.totalItems - (gScanDetails.gNumAdded + gScanDetails.gNumUpdated));
	zc.msg (" ");
end

-----------------------------------------

function Atr_FullScanAnalyze()

	if (not gFS_waiting) then
		return;
	end

	gFS_waiting = false;

	local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

	gFS_pages = math.ceil (totalAuctions / 50);

	local x;

	for x = 1, numBatchAuctions do

		local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", x);

		if (name ~= nil and name ~= "") then

			gFS_qualities[name] = quality;

			if (buyoutPrice ~= nil and count ~= nil and count > 0) then

				local itemPrice = math.floor (buyoutPrice / count);

				if (itemPrice > 0) then
					if (not gFS_lowprices[name]) then
						gFS_lowprices[name] = {BIGNUM,BIGNUM,BIGNUM};		-- one extra for later
					end

					local isNewLow = Atr_AddToLowPrices (gFS_lowprices[name], itemPrice);
					if (isNewLow) then
						-- Progressive save: preserve prices immediately so no data is lost on stop or disconnect
						if (gAtr_ScanDB) then
							gAtr_ScanDB[name] = gFS_lowprices[name][1];
							if (Atr_RecordHistoricalPrice) then
								Atr_RecordHistoricalPrice(name, gFS_lowprices[name][1]);
							end
						end

						-- Live Flips & Snipes Priority Detection
						if (Atr_CheckLiveScanDeal) then
							Atr_CheckLiveScanDeal(name, itemPrice, buyoutPrice, count, quality, level);
						end
					end
				end
			end
		end
	end

	AUCTIONATOR_LAST_SCAN_TIME = time();
	gFS_numAuctions = gFS_numAuctions + numBatchAuctions;
	gFS_page = gFS_page + 1;
	gFS_lastPageTime = GetTime();
	gFS_retryCount = 0;

	if (math.mod(gFS_page, 20) == 0 and collectgarbage) then
		collectgarbage();
	end

	local elapsed = GetTime() - (gFS_startedAt or GetTime());
	local secPerPage = (gFS_page > 0) and (elapsed / gFS_page) or 5.0;
	local etaMin = math.ceil(((gFS_pages - gFS_page) * secPerPage) / 60);
	local flipCount = (gAtr_LiveScanDeals and table.getn(gAtr_LiveScanDeals)) or 0;
	local flipNotice = (flipCount > 0) and string.format(" | |cffa335ee%d Flips|r", flipCount) or "";
	Atr_FullScanStatus:SetText (string.format("%s %d / %d (~%dm)%s", ZT("Scanning"), gFS_page, gFS_pages, etaMin, flipNotice));

	if (gAtr_ScanIsMinimized) then
		Atr_UpdateScanMiniBar();
	end

	-- Live UI Feedback: Refresh Gold Advisor UI in real-time every 1.5s
	local now = GetTime();
	if (now - (gFS_lastLiveUIRefresh or 0) >= 1.5) then
		gFS_lastLiveUIRefresh = now;
		if (Atr_ProfitFrame and Atr_ProfitFrame:IsShown() and Atr_RefreshProfitUI) then
			Atr_RefreshProfitUI();
		end
	end

	if (gFS_page >= gFS_pages or numBatchAuctions == 0) then
		Atr_FullScanFinish();
	end

end

-----------------------------------------

function Atr_FullScanFinish()

	gAtr_FullScanState = ATR_FS_ANALYZING;

	Atr_FullScanStatus:SetText (ZT("Processing"));

	local numBatchAuctions = gFS_numAuctions;
	local lowprices = gFS_lowprices;
	local qualities = gFS_qualities;

	local numEachQual = {0, 0, 0, 0, 0, 0, 0, 0, 0};
	local totalItems = 0;
	local numRemoved = { 0, 0, 0, 0, 0, 0, 0, 0 };

	local name, prices;

	for name,prices in pairs (lowprices) do

		local newprice = Atr_CalcNewDBprice (name, prices);

		if (newprice > 0) then

			local qx = qualities[name] + 1;

			numEachQual[qx]	= numEachQual[qx] + 1;
			totalItems		= totalItems + 1;

			if (qx < AUCTIONATOR_SCAN_MINLEVEL and gAtr_ScanDB[name]) then
				numRemoved[qx] = numRemoved[qx] + 1;
				gAtr_ScanDB[name] = nil;
			end

			if (qx >= AUCTIONATOR_SCAN_MINLEVEL) then

				if (gAtr_ScanDB[name] == nil) then
					gNumAdded = gNumAdded + 1;
				else
					gNumUpdated = gNumUpdated + 1;
				end

				gAtr_ScanDB[name] = newprice;
				if Atr_RecordHistoricalPrice then Atr_RecordHistoricalPrice(name, newprice); end
			end
		end
	end

	gScanDetails.numBatchAuctions		= numBatchAuctions;
	gScanDetails.totalItems				= totalItems;
	gScanDetails.numEachQual			= numEachQual;
	gScanDetails.numRemoved				= numRemoved;
	gScanDetails.gNumAdded				= gNumAdded;
	gScanDetails.gNumUpdated			= gNumUpdated;

	Atr_FullScanMoreDetails();

	Atr_FullScanStartButton:Enable();
	Atr_FullScanDone:Enable();
	Atr_FullScanStatus:SetText (ZT("Scan complete"));

	Atr_FSR_scanned_count:SetText	(numBatchAuctions);
	Atr_FSR_added_count:SetText		(gNumAdded);
	Atr_FSR_updated_count:SetText	(gNumUpdated);
	Atr_FSR_ignored_count:SetText	(totalItems - (gNumAdded + gNumUpdated));

	Atr_FullScanHTML:Hide();
	Atr_FullScanResults:Show();

	Atr_FullScanResults:SetBackdropColor (0.3, 0.3, 0.4);

	AUCTIONATOR_LAST_SCAN_TIME = time();

	Atr_UpdateFullScanFrame ();

	PlaySound("AuctionWindowClose");

	gFS_lowprices = {};
	gFS_qualities = {};
	gAtr_FullScanState = ATR_FS_NULL;

	if (gAtr_ScanIsMinimized) then
		Atr_UpdateScanMiniBar();
	end

	if (AUCTIONATOR_FS_AUTOLOGOUT) then
		if (DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Auctionator]|r Full scan complete! All items recorded.");
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[Auctionator]|r Auto-Logout enabled: Logging out in 5 seconds to safely save database (click DONE or move to cancel)...");
		end
		Atr_StartAutoLogout(5);
	end
end

-----------------------------------------
-- Auto-Logout Engine (Safe Disconnect after Scan)
-----------------------------------------
local logoutDriver = CreateFrame("Frame", "AtrLogoutDriver");
local logoutRemaining = 0;
local logoutActive = false;
local intentionalLogout = false;

function Atr_IsAutoLogoutActive()
	return logoutActive or intentionalLogout;
end

function Atr_StartAutoLogout(delaySeconds)
	logoutRemaining = delaySeconds or 5;
	logoutActive = true;
	intentionalLogout = false;
end

function Atr_CancelAutoLogout()
	if (logoutActive or intentionalLogout) then
		logoutActive = false;
		intentionalLogout = false;
		local status = getglobal("Atr_FullScanStatus");
		if (status) then status:SetText(ZT("Scan complete")); end
		if (gAtr_ScanIsMinimized and gAtr_ScanMiniBar and gAtr_ScanMiniBar:IsShown()) then
			gAtr_ScanMiniBar.status:SetText("|cff00ff00Scan complete!|r Click Expand");
		end
		if (DEFAULT_CHAT_FRAME) then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00[Auctionator]|r Auto-logout cancelled.");
		end
	end
end

logoutDriver:SetScript("OnUpdate", function()
	if (not logoutActive) then return; end
	local elapsed = arg1 or 0.1;
	logoutRemaining = logoutRemaining - elapsed;

	local status = getglobal("Atr_FullScanStatus");
	if (status and status:IsShown()) then
		status:SetText(string.format("|cffffcc00Scan complete! Auto-logging out in %d...|r", math.max(1, math.ceil(logoutRemaining))));
	end
	if (gAtr_ScanIsMinimized and gAtr_ScanMiniBar and gAtr_ScanMiniBar:IsShown()) then
		gAtr_ScanMiniBar.status:SetText(string.format("|cffffcc00Auto-Logout in %ds...|r", math.max(1, math.ceil(logoutRemaining))));
	end

	if (logoutRemaining <= 0) then
		logoutActive = false;
		intentionalLogout = true;
		if (status) then status:SetText("Logging out to save data..."); end
		if (gAtr_ScanIsMinimized and gAtr_ScanMiniBar and gAtr_ScanMiniBar:IsShown()) then
			gAtr_ScanMiniBar.status:SetText("Logging out to save data...");
		end
		Logout();
	end
end);

-----------------------------------------

function auctionator_AuctionFrameBrowse_Update ()

	return auctionator_orig_AuctionFrameBrowse_Update ();

end

-----------------------------------------
-- Full Scan Minimization & Floating HUD
-----------------------------------------

gAtr_ScanIsMinimized = false;
local gAtr_OrigAuctionFrameUIPanel = nil;
local gAtr_OrigAuctionFramePoints = nil;
local gAtr_OrigAuctionFrameOnHide = nil;
local gAtr_OrigAuxFramePoints = nil;
local gAtr_OrigAuxFrameOnHide = nil;
local gAtr_ScanMiniBar = nil;

function Atr_CreateScanMiniBar()
	if (gAtr_ScanMiniBar) then return gAtr_ScanMiniBar; end

	local bar = CreateFrame("Button", "Atr_ScanMiniBar", UIParent);
	bar:SetWidth(350);
	bar:SetHeight(46);
	bar:SetFrameStrata("FULLSCREEN_DIALOG");
	bar:SetToplevel(true);
	bar:EnableMouse(true);
	bar:SetMovable(true);
	bar:SetClampedToScreen(true);
	bar:RegisterForDrag("LeftButton");
	bar:SetScript("OnDragStart", function() this:StartMoving(); end);
	bar:SetScript("OnDragStop", function()
		this:StopMovingOrSizing();
		local point, _, relPoint, xOfs, yOfs = this:GetPoint(1);
		AUCTIONATOR_MINIBAR_POS = { point = point, relPoint = relPoint, x = xOfs, y = yOfs };
	end);

	if (AUCTIONATOR_MINIBAR_POS and AUCTIONATOR_MINIBAR_POS.point) then
		bar:ClearAllPoints();
		bar:SetPoint(AUCTIONATOR_MINIBAR_POS.point, UIParent, AUCTIONATOR_MINIBAR_POS.relPoint or AUCTIONATOR_MINIBAR_POS.point, AUCTIONATOR_MINIBAR_POS.x or 0, AUCTIONATOR_MINIBAR_POS.y or -32);
	else
		bar:ClearAllPoints();
		bar:SetPoint("TOP", UIParent, "TOP", 0, -32);
	end

	-- Backdrop styling
	bar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	});
	bar:SetBackdropColor(0.06, 0.06, 0.10, 0.94);
	bar:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.95);

	-- Title
	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	title:SetPoint("TOPLEFT", bar, "TOPLEFT", 10, -8);
	title:SetText("|cffffd100[AH Scan]|r");
	bar.title = title;

	-- Status / Progress Text
	local status = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	status:SetPoint("LEFT", title, "RIGHT", 8, 0);
	status:SetPoint("RIGHT", bar, "RIGHT", -26, 0);
	status:SetJustifyH("LEFT");
	status:SetText("Scanning...");
	bar.status = status;

	-- Progress Bar
	local pbar = CreateFrame("StatusBar", "Atr_ScanMiniProgressBar", bar);
	pbar:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 10, 8);
	pbar:SetWidth(195);
	pbar:SetHeight(13);
	pbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	pbar:SetStatusBarColor(0.2, 0.7, 1.0, 0.95);
	pbar:SetMinMaxValues(0, 100);
	pbar:SetValue(0);

	local pbarBg = pbar:CreateTexture(nil, "BACKGROUND");
	pbarBg:SetAllPoints();
	pbarBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar");
	pbarBg:SetVertexColor(0.1, 0.1, 0.15, 0.7);

	local pbarText = pbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	pbarText:SetPoint("CENTER", pbar, "CENTER", 0, 0);
	pbarText:SetText("0%");
	bar.pbarText = pbarText;
	bar.pbar = pbar;

	-- Pause / Resume Button
	local pauseBtn = CreateFrame("Button", "Atr_ScanMiniPauseButton", bar, "UIPanelButtonTemplate");
	pauseBtn:SetWidth(60);
	pauseBtn:SetHeight(19);
	pauseBtn:SetPoint("LEFT", pbar, "RIGHT", 6, 0);
	pauseBtn:SetText("Pause");
	local pFont = pauseBtn:GetFontString();
	if (pFont and GameFontHighlightSmall and GameFontHighlightSmall.GetFont) then
		local fontName = GameFontHighlightSmall:GetFont();
		if (fontName) then pFont:SetFont(fontName, 10); end
	end
	pauseBtn:SetScript("OnClick", function()
		if (gAtr_FullScanState == ATR_FS_STARTED) then
			Atr_FullScanPause();
		elseif (gAtr_FullScanState == ATR_FS_PAUSED) then
			Atr_FullScanStart(true);
		end
		Atr_UpdateScanMiniBar();
	end);
	bar.pauseBtn = pauseBtn;

	-- Expand / Maximize Button
	local expandBtn = CreateFrame("Button", "Atr_ScanMiniExpandButton", bar, "UIPanelButtonTemplate");
	expandBtn:SetWidth(58);
	expandBtn:SetHeight(19);
	expandBtn:SetPoint("LEFT", pauseBtn, "RIGHT", 4, 0);
	expandBtn:SetText("Expand");
	local eFont = expandBtn:GetFontString();
	if (eFont and GameFontHighlightSmall and GameFontHighlightSmall.GetFont) then
		local fontName = GameFontHighlightSmall:GetFont();
		if (fontName) then eFont:SetFont(fontName, 10); end
	end
	expandBtn:SetScript("OnClick", function()
		Atr_RestoreScan();
	end);
	bar.expandBtn = expandBtn;

	-- Close Button (X in top right)
	local closeBtn = CreateFrame("Button", "Atr_ScanMiniCloseButton", bar, "UIPanelCloseButton");
	closeBtn:SetWidth(18);
	closeBtn:SetHeight(18);
	closeBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -2, -2);
	closeBtn:SetScript("OnClick", function()
		if (gAtr_FullScanState == ATR_FS_STARTED or gAtr_FullScanState == ATR_FS_PAUSED) then
			Atr_FullScanPause();
		end
		Atr_RestoreScan();
	end);
	bar.closeBtn = closeBtn;

	bar:Hide();
	gAtr_ScanMiniBar = bar;
	return bar;
end

function Atr_ShowScanMiniBar()
	local bar = Atr_CreateScanMiniBar();
	bar:Show();
	Atr_UpdateScanMiniBar();
end

function Atr_UpdateScanMiniBar()
	if (not gAtr_ScanMiniBar or not gAtr_ScanMiniBar:IsShown()) then return; end

	local totalPages = gFS_pages or 0;
	local curPage = gFS_page or 0;
	local pct = 0;
	if (totalPages > 0) then
		pct = math.min(100, math.floor((curPage / totalPages) * 100));
	end

	gAtr_ScanMiniBar.pbar:SetValue(pct);
	gAtr_ScanMiniBar.pbarText:SetText(string.format("%d%%", pct));

	local elapsed = GetTime() - (gFS_startedAt or GetTime());
	local secPerPage = (curPage > 0) and (elapsed / curPage) or 4.0;
	local etaMin = (totalPages > curPage) and math.ceil(((totalPages - curPage) * secPerPage) / 60) or 0;
	local flips = (gAtr_LiveScanDeals and table.getn(gAtr_LiveScanDeals)) or 0;
	local flipNotice = (flips > 0) and string.format(" | |cffa335ee%d Flips|r", flips) or "";

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		gAtr_ScanMiniBar.status:SetText(string.format("Page %d/%d (~%dm)%s", curPage, totalPages, etaMin, flipNotice));
		gAtr_ScanMiniBar.pauseBtn:SetText("Pause");
		gAtr_ScanMiniBar.pauseBtn:Enable();
		gAtr_ScanMiniBar.pbar:SetStatusBarColor(0.2, 0.7, 1.0, 0.95);
	elseif (gAtr_FullScanState == ATR_FS_PAUSED) then
		gAtr_ScanMiniBar.status:SetText(string.format("|cffffcc00Paused (p.%d/%d)|r", curPage, totalPages));
		gAtr_ScanMiniBar.pauseBtn:SetText("Resume");
		gAtr_ScanMiniBar.pauseBtn:Enable();
		gAtr_ScanMiniBar.pbar:SetStatusBarColor(1.0, 0.8, 0.2, 0.95);
	elseif (gAtr_FullScanState == ATR_FS_ANALYZING) then
		gAtr_ScanMiniBar.status:SetText("|cff00ff00Processing prices...|r");
		gAtr_ScanMiniBar.pauseBtn:Disable();
		gAtr_ScanMiniBar.pbar:SetStatusBarColor(0.2, 1.0, 0.4, 0.95);
	elseif (gAtr_FullScanState == ATR_FS_NULL and curPage > 0 and curPage >= totalPages) then
		gAtr_ScanMiniBar.status:SetText("|cff00ff00Scan complete!|r Click Expand");
		gAtr_ScanMiniBar.pbar:SetValue(100);
		gAtr_ScanMiniBar.pbarText:SetText("100%");
		gAtr_ScanMiniBar.pauseBtn:SetText("Done");
		gAtr_ScanMiniBar.pbar:SetStatusBarColor(0.2, 1.0, 0.4, 0.95);
	else
		gAtr_ScanMiniBar.status:SetText("Scan Idle");
		gAtr_ScanMiniBar.pauseBtn:SetText("Start");
		gAtr_ScanMiniBar.pbar:SetStatusBarColor(0.5, 0.5, 0.5, 0.95);
	end
end

function Atr_MinimizeScan()
	if (gAtr_ScanIsMinimized) then return; end
	gAtr_ScanIsMinimized = true;

	if (PlaySound) then PlaySound("igMiniMapZoomIn"); end

	-- 1. Hide the full scan dialog & mask
	if (Atr_FullScanFrame) then Atr_FullScanFrame:Hide(); end
	if (Atr_Mask) then Atr_Mask:Hide(); end
	if (Atr_ProfitFrame and Atr_ProfitFrame:IsShown()) then Atr_ProfitFrame:Hide(); end

	-- 2. Preserve & detach AuctionFrame from UIPanelWindows so crafting frames can open freely
	if (AuctionFrame and AuctionFrame:IsShown()) then
		if (UIPanelWindows and UIPanelWindows["AuctionFrame"]) then
			gAtr_OrigAuctionFrameUIPanel = UIPanelWindows["AuctionFrame"];
			UIPanelWindows["AuctionFrame"] = nil;
		end

		gAtr_OrigAuctionFrameOnHide = AuctionFrame:GetScript("OnHide");
		AuctionFrame:SetScript("OnHide", nil);

		gAtr_OrigAuctionFramePoints = {};
		local numPoints = AuctionFrame:GetNumPoints() or 0;
		for i = 1, numPoints do
			local point, relativeTo, relativePoint, xOfs, yOfs = AuctionFrame:GetPoint(i);
			table.insert(gAtr_OrigAuctionFramePoints, { point = point, relativeTo = relativeTo, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs });
		end

		AuctionFrame:ClearAllPoints();
		AuctionFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -6000, -6000);
		AuctionFrame:SetAlpha(0);
		AuctionFrame:EnableMouse(false);
	end

	-- Also handle aux-addon frame if active
	local auxFrame = getglobal("aux_frame");
	if (auxFrame and auxFrame:IsShown()) then
		gAtr_OrigAuxFrameOnHide = auxFrame:GetScript("OnHide");
		auxFrame:SetScript("OnHide", nil);

		gAtr_OrigAuxFramePoints = {};
		local numPoints = auxFrame:GetNumPoints() or 0;
		for i = 1, numPoints do
			local point, relativeTo, relativePoint, xOfs, yOfs = auxFrame:GetPoint(i);
			table.insert(gAtr_OrigAuxFramePoints, { point = point, relativeTo = relativeTo, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs });
		end

		auxFrame:ClearAllPoints();
		auxFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -6000, -6000);
		auxFrame:SetAlpha(0);
		auxFrame:EnableMouse(false);
	end

	-- 3. Show Mini-Bar HUD
	Atr_ShowScanMiniBar();

	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Auctionator]|r Scan minimized to floating HUD. Screen cleared for crafting and inventory!");
	end
end

function Atr_RestoreScan()
	if (not gAtr_ScanIsMinimized) then return; end
	gAtr_ScanIsMinimized = false;

	if (PlaySound) then PlaySound("igMiniMapZoomOut"); end

	-- 1. Restore UIPanelWindows registration
	if (UIPanelWindows) then
		if (gAtr_OrigAuctionFrameUIPanel) then
			UIPanelWindows["AuctionFrame"] = gAtr_OrigAuctionFrameUIPanel;
			gAtr_OrigAuctionFrameUIPanel = nil;
		else
			UIPanelWindows["AuctionFrame"] = { area = "doublewide", pushable = 0 };
		end
	end

	-- 2. Restore AuctionFrame position & visibility
	if (AuctionFrame and AuctionFrame:IsShown()) then
		AuctionFrame:ClearAllPoints();
		if (gAtr_OrigAuctionFramePoints and table.getn(gAtr_OrigAuctionFramePoints) > 0) then
			for _, pt in ipairs(gAtr_OrigAuctionFramePoints) do
				AuctionFrame:SetPoint(pt.point, pt.relativeTo, pt.relativePoint, pt.xOfs, pt.yOfs);
			end
		else
			AuctionFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104);
		end
		AuctionFrame:SetAlpha(1);
		AuctionFrame:EnableMouse(true);
		if (gAtr_OrigAuctionFrameOnHide) then
			AuctionFrame:SetScript("OnHide", gAtr_OrigAuctionFrameOnHide);
			gAtr_OrigAuctionFrameOnHide = nil;
		end
	end

	-- Restore aux_frame if needed
	local auxFrame = getglobal("aux_frame");
	if (auxFrame and auxFrame:IsShown()) then
		auxFrame:ClearAllPoints();
		if (gAtr_OrigAuxFramePoints and table.getn(gAtr_OrigAuxFramePoints) > 0) then
			for _, pt in ipairs(gAtr_OrigAuxFramePoints) do
				auxFrame:SetPoint(pt.point, pt.relativeTo, pt.relativePoint, pt.xOfs, pt.yOfs);
			end
		else
			auxFrame:SetPoint("LEFT", 100, 0);
		end
		auxFrame:SetAlpha(1);
		auxFrame:EnableMouse(true);
		if (gAtr_OrigAuxFrameOnHide) then
			auxFrame:SetScript("OnHide", gAtr_OrigAuxFrameOnHide);
			gAtr_OrigAuxFrameOnHide = nil;
		end
	end

	-- 3. Hide Mini-Bar HUD
	if (gAtr_ScanMiniBar) then
		gAtr_ScanMiniBar:Hide();
	end

	-- 4. Re-show FullScan dialog & mask
	if (Atr_FullScanFrame) then
		Atr_FullScanFrame:Show();
		Atr_UpdateFullScanFrame();
	end
end

function Atr_ToggleMinimizeScan()
	if (gAtr_ScanIsMinimized) then
		Atr_RestoreScan();
	else
		if (gAtr_FullScanState == ATR_FS_NULL) then
			Atr_FullScanStart(false);
		end
		Atr_MinimizeScan();
	end
end

-----------------------------------------

function Atr_ShowFullScanFrame()

	if (gAtr_ScanIsMinimized) then
		Atr_RestoreScan();
		return;
	end

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();

	Atr_FullScanFrame:Show();
	Atr_FullScanFrame:SetBackdropColor(0,0,0,100);
	
	Atr_UpdateFullScanFrame();
	Atr_FullScanStatus:SetText ("");

	if (AUCTIONATOR_FS_AUTOLOGOUT == nil) then
		AUCTIONATOR_FS_AUTOLOGOUT = true;
	end

	local chk = getglobal("Atr_FullScanLogoutCheck");
	if (not chk and Atr_FullScanFrame) then
		chk = CreateFrame("CheckButton", "Atr_FullScanLogoutCheck", Atr_FullScanFrame, "UICheckButtonTemplate");
		chk:SetWidth(22); chk:SetHeight(22);
		chk:SetPoint("BOTTOMLEFT", Atr_FullScanFrame, "BOTTOMLEFT", 24, 12);
		local txt = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		txt:SetPoint("LEFT", chk, "RIGHT", 4, 0);
		txt:SetText("Auto-Disconnect / Logout when scan completes (safely saves data)");
		chk:SetScript("OnClick", function()
			AUCTIONATOR_FS_AUTOLOGOUT = (this:GetChecked() == 1);
			local pChk = getglobal("Atr_PAutoLogoutCheck");
			if (pChk) then pChk:SetChecked(AUCTIONATOR_FS_AUTOLOGOUT and 1 or 0); end
			if (DEFAULT_CHAT_FRAME) then
				local s = AUCTIONATOR_FS_AUTOLOGOUT and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r";
				DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Auctionator]|r Auto-Logout on scan complete: " .. s);
			end
		end);
	end
	if (chk) then
		chk:SetChecked(AUCTIONATOR_FS_AUTOLOGOUT and 1 or 0);
	end

	local expText = "<html><body>"
					.."<p>"
					..ZT("Scanning is entirely optional.")
					.."<br/><br/>"
					..ZT("SCAN_EXPLANATION")
					.."</p>"
					.."</body></html>"
					;



	Atr_FullScanHTML:SetText (expText);
	Atr_FullScanHTML:SetSpacing (3);

	if (Atr_FullScanStartButton) then
		Atr_FullScanStartButton:SetScript("OnClick", function()
			if (gAtr_FullScanState == ATR_FS_STARTED) then
				Atr_FullScanPause();
			elseif (gAtr_FullScanState == ATR_FS_PAUSED) then
				Atr_FullScanStart(true);
			else
				Atr_FullScanStart(false);
			end
		end);
	end

	if (Atr_FullScanDone) then
		Atr_FullScanDone:SetScript("OnClick", function()
			Atr_FullScanDone_OnClick();
		end);
	end
end

-----------------------------------------

function Atr_UpdateFullScanFrame()

	Atr_FullScanDBsize:SetText (Atr_GetDBsize());

	if (AUCTIONATOR_LAST_SCAN_TIME) then
		Atr_FullScanDBwhen:SetText (date ("%A, %B %d at %I:%M %p", AUCTIONATOR_LAST_SCAN_TIME));
	else
		Atr_FullScanDBwhen:SetText (ZT("Never"));
	end

	Atr_FullScanNext:SetText(ZT("Now"));

	local restartBtn = getglobal("Atr_FullScanRestartButton");
	if (not restartBtn and Atr_FullScanFrame and Atr_FullScanStartButton) then
		restartBtn = CreateFrame("Button", "Atr_FullScanRestartButton", Atr_FullScanFrame, "UIPanelButtonTemplate");
		restartBtn:SetWidth(95);
		restartBtn:SetHeight(22);
		restartBtn:SetPoint("RIGHT", Atr_FullScanStartButton, "LEFT", -4, 0);
		restartBtn:SetText("New Scan");
		restartBtn:SetScript("OnClick", function()
			Atr_FullScanStart(false);
		end);
	end

	local minTitleBtn = getglobal("Atr_FullScanMinTitleButton");
	if (not minTitleBtn and Atr_FullScanFrame) then
		minTitleBtn = CreateFrame("Button", "Atr_FullScanMinTitleButton", Atr_FullScanFrame, "UIPanelButtonTemplate");
		minTitleBtn:SetWidth(20);
		minTitleBtn:SetHeight(20);
		minTitleBtn:SetPoint("TOPRIGHT", Atr_FullScanFrame, "TOPRIGHT", -12, -12);
		minTitleBtn:SetText("_");
		minTitleBtn:SetScript("OnClick", function()
			Atr_MinimizeScan();
		end);
		minTitleBtn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
			GameTooltip:SetText("Minimize Scan", 1, 1, 1);
			GameTooltip:AddLine("Minimizes the scan to a small floating HUD bar.", 0.8, 0.8, 0.8, 1);
			GameTooltip:AddLine("Allows crafting, opening bags, and moving freely while scan continues in the background.", 0, 1, 0, 1);
			GameTooltip:Show();
		end);
		minTitleBtn:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
	end

	local minBtn = getglobal("Atr_FullScanMinimizeButton");
	if (not minBtn and Atr_FullScanFrame and Atr_FullScanStartButton) then
		minBtn = CreateFrame("Button", "Atr_FullScanMinimizeButton", Atr_FullScanFrame, "UIPanelButtonTemplate");
		minBtn:SetWidth(85);
		minBtn:SetHeight(22);
		minBtn:SetText("Minimize");
		minBtn:SetScript("OnClick", function()
			if (gAtr_FullScanState == ATR_FS_NULL) then
				Atr_FullScanStart(false);
			end
			Atr_MinimizeScan();
		end);
		minBtn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_TOP");
			GameTooltip:SetText("Minimize Scan to HUD", 1, 1, 1);
			GameTooltip:AddLine("Shrinks the scan to a compact progress bar so you can craft items, manage inventory, and interact with the game while the Auction House is scanned.", 0.8, 0.8, 0.8, 1);
			GameTooltip:Show();
		end);
		minBtn:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
	end

	if (minBtn) then
		minBtn:ClearAllPoints();
		if (restartBtn and restartBtn:IsShown()) then
			minBtn:SetPoint("RIGHT", restartBtn, "LEFT", -4, 0);
		elseif (Atr_FullScanStartButton) then
			minBtn:SetPoint("RIGHT", Atr_FullScanStartButton, "LEFT", -4, 0);
		end
	end

	if (gAtr_FullScanState == ATR_FS_STARTED) then
		Atr_FullScanStartButton:SetText("Pause Scan");
		Atr_FullScanStartButton:Enable();
		if (restartBtn) then restartBtn:Hide(); end
	elseif (gAtr_FullScanState == ATR_FS_PAUSED) then
		Atr_FullScanStartButton:SetText(string.format("Resume (p.%d)", gFS_page + 1));
		Atr_FullScanStartButton:Enable();
		if (restartBtn) then restartBtn:Show(); end
	else
		Atr_FullScanStartButton:SetText(ZT("Start Scanning"));
		Atr_FullScanStartButton:Enable();
		if (restartBtn) then restartBtn:Hide(); end
	end
end

-----------------------------------------

function Atr_FullScanFrameIdle()

	local now = GetTime();

	if (gAtr_ScanIsMinimized and (now - (gFS_lastMiniBarRefresh or 0) >= 0.5)) then
		gFS_lastMiniBarRefresh = now;
		Atr_UpdateScanMiniBar();
	end

	-- Anti-Disconnect / Anti-AFK Keepalive: prevents server AFK and client idle timeout during scan or paused scan
	if (gAtr_FullScanState == ATR_FS_STARTED or gAtr_FullScanState == ATR_FS_PAUSED) then
		if (now - gFS_lastKeepAlive > 15) then
			gFS_lastKeepAlive = now;
			-- Cancel any client-side camping or logout countdown
			if (CancelLogout) then
				CancelLogout();
			end
			if (StaticPopup_Hide) then
				StaticPopup_Hide("CAMP");
			end
			-- Clear AFK flag if set
			if (UnitIsAFK and UnitIsAFK("player")) then
				if (SlashCmdList and SlashCmdList["AFK"]) then
					SlashCmdList["AFK"]("");
				elseif (SendChatMessage) then
					SendChatMessage("", "AFK");
				end
			end
		end
	end

	if (gAtr_FullScanState == ATR_FS_STARTED) then

		local isAHOpen = (AuctionFrame and AuctionFrame:IsShown()) or (aux_frame and aux_frame:IsShown()) or gAtr_ScanIsMinimized;
		if (not isAHOpen) then
			Atr_FullScanPause();
			return;
		end

		-- Retry or advance stalled page after 9 seconds
		if (gFS_waiting and now - gFS_sentAt > 9.0) then
			gFS_retryCount = (gFS_retryCount or 0) + 1;
			if (gFS_retryCount > 2) then
				-- Skip stalled page after 2 retries so scan never hangs
				gFS_page = gFS_page + 1;
				gFS_retryCount = 0;
			end
			gFS_waiting = false;
		end

		-- Safe 350ms throttle between pages to prevent server packet kicks
		-- If CanSendAuctionQuery is false for more than 7 seconds, force continue so scan never hangs
		local canQuery = Atr_CanSendAuctionQuery() or (now - (gFS_lastPageTime or 0) >= 7.0);
		local minPageDelay = 0.35;
		if (not gFS_waiting and (now - (gFS_lastPageTime or 0) >= minPageDelay) and canQuery) then
			gFS_waiting = true;
			gFS_sentAt = now;
			Atr_QueryAuctionItems ("", nil, nil, 0, 0, 0, gFS_page, 0, 0);
		end
	end

end


-----------------------------------------
-- Event Listener: Abort Idle Camping Logout while a Scan is in Progress
-----------------------------------------
local atrCampingKeeper = CreateFrame("Frame", "AtrScanCampingKeeper");
atrCampingKeeper:RegisterEvent("PLAYER_CAMPING");
atrCampingKeeper:SetScript("OnEvent", function()
	if (event == "PLAYER_CAMPING") then
		-- Do NOT cancel intentional logout initiated when scan completes!
		if (Atr_IsAutoLogoutActive and Atr_IsAutoLogoutActive()) then
			return;
		end

		local scanActive = (gAtr_FullScanState == ATR_FS_STARTED) or (gAtr_FullScanState == ATR_FS_PAUSED) or (Atr_IsFastScanRunning and Atr_IsFastScanRunning());
		local ahActive = (AuctionFrame and AuctionFrame:IsShown()) or (Atr_ProfitFrame and Atr_ProfitFrame:IsShown()) or (Atr_FullScanFrame and Atr_FullScanFrame:IsShown());
		if (scanActive or ahActive) then
			if (CancelLogout) then
				CancelLogout();
			end
			if (StaticPopup_Hide) then
				StaticPopup_Hide("CAMP");
			end
			if (DEFAULT_CHAT_FRAME) then
				DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Auctionator]|r Prevented idle timeout during scan / AH session.");
			end
		end
	end
end);