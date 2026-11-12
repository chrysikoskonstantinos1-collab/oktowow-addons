MBB_Version = GetAddOnMetadata("MBB", "Version") or "0.508";
MBB_DebugFlag = 0;
MBB_DragFlag = 0;
MBB_ShowTimeout = -1;
MBB_Buttons = {};
MBB_Exclude = {};
MBB_DragPos ={
	["orig"] = {},
	["start"] = {}
};
MBB_DefaultOptions = {
	["ButtonPos"] = {-18, -100},
	["AttachToMinimap"] = 1,
	["CollapseTimeout"] = 0,
	["ExpandDirection"] = 1, -- 1 = Expand Left
	["MaxButtonsPerLine"] = 12,
	["AltExpandDirection"] = 4,
	["Scale"] = 100,
	["Version"] = MBB_Version
};

MBB_Include = {
	"DPSMate_MiniMap",
	"AutoLFM_MinimapButton",
	"AtlasCFMMinimapButton",
	"AtlasLootMinimapButton",
	"OctoVuhDoMinimapBtn",
	"RaidSynergyMinimapBtn",
	"WIM_IconFrameButton",
	"OutfitterMinimapButton",
	"ShaguDPSMinimap",
	"ShaguScoreMinimap",
	"KLHTM_MinimapButton",
	"SW_IconFrame",
	"SuperMacroIconFrame",
	"BCC_MinimapButton",
	"HunterSwingTimerMinimap",
	"BagshuiMinimapButton",
};

MBB_Ignore = {
	"MiniMapTrackingFrame",
	"MiniMapMeetingStoneFrame",
	"MiniMapMailFrame",
	"MiniMapBattlefieldFrame",
	"MiniMapPing",
	"MinimapBackdrop",
	"MinimapZoomIn",
	"MinimapZoomOut",
	"BookOfTracksFrame",
	"GatherNote",
	"FishingExtravaganzaMini",
	"MiniNotePOI",
	"RecipeRadarMinimapIcon",
	"FWGMinimapPOI",
	"MBB_MinimapButtonFrame",
	"QuestieNote",
	"MetaMap",
	"LootLinkMinimapButton",
	"TimeManagerClockButton",
	"pfMiniMapPin",
	"Clock",
	"MinimapClock",
	"AtlasCFMButtonFrame",
	"AtlasLootMinimapButtonFrame",
	"WIM_IconFrame",
	"AutoLFM_MinimapContainer",
	"PetFoodBarFrame",
};

MBB_IgnoreSize = {
	"AM_MinimapButton",
	"STC_HealthstoneButton",
	"STC_ShardButton",
	"STC_SoulstoneButton",
	"STC_SpellstoneButton",
	"STC_FirestoneButton",
};

local function CloneTable(t)
	local new = {};
	local i, v = next(t, nil);
	while i do
		if type(v)=="table" then 
			v=CloneTable(v);
		end 
		new[i] = v;
		i, v = next(t, i);
	end
	return new;
end

local function RestoreMinimapClock()
	local clk = getglobal("Clock") or getglobal("MinimapClock")
	if clk then
		clk:ClearAllPoints()
		clk:SetPoint("BOTTOM", MinimapCluster or Minimap, "BOTTOM", 8, 18)
		clk:SetWidth(50)
		clk:SetHeight(23)
		clk:Show()
	end
end

MBB_ExtraSize = {
	["GathererMinimapButton"] = function()
		if GathererMinimapButton and GathererMinimapButton.mask then
			GathererMinimapButton.mask:SetHeight(31);
			GathererMinimapButton.mask:SetWidth(31);
		end
	end,
	["WIM_IconFrame"] = function()
		if WIM_IconFrameButton then
			WIM_IconFrameButton:SetScale(1);
		end
	end,
	["MonkeyBuddyIconButton"] = function()
		if MonkeyBuddyIconButton then
			MonkeyBuddyIconButton:SetHeight(33);
			MonkeyBuddyIconButton:SetWidth(33);
		end
	end,
	["DPSMate_MiniMap"] = function()
		if DPSMate_MiniMap then
			DPSMate_MiniMap:SetScale(((MBB_Options and MBB_Options.Scale) or 100) / 100);
		end
	end
};

MBB_CallBack = {
	["RecipeRadarMinimapButton"] = function()
		if RecipeRadar_MinimapButton_UpdatePosition then
			RecipeRadar_MinimapButton_UpdatePosition();
		end
	end
};

function MBB_SafeHasScript(frame, scriptType)
	if not frame then return false end
	if frame.HasScript then
		local ok, res = pcall(frame.HasScript, frame, scriptType)
		if ok and res then return true end
	end
	if frame.GetScript then
		local ok, handler = pcall(frame.GetScript, frame, scriptType)
		return ok and (handler ~= nil)
	end
	return false
end

local _rescanned = false;
local _starttime = 0;
local _rescan_count = 0;

function MBB_OnLoad()
	this:RegisterEvent("VARIABLES_LOADED");
	this:RegisterEvent("ADDON_LOADED");
	this:RegisterEvent("PLAYER_ENTERING_WORLD");
	SLASH_MBB1 = "/mbb";
	SlashCmdList["MBB"] = MBB_SlashHandler;
end

function MBB_SlashHandler(cmd)
	cmd = string.lower(cmd or "");
	if( cmd == "rescan" or cmd == "gather" ) then
		MBB_GatherIcons();
		MBB_SetButtonPosition();
		RestoreMinimapClock();
		MBB_Print("MBB: Minimap buttons gathered into bag.");
	elseif( cmd == "restore" or cmd == "ungather" or cmd == "all" ) then
		MBB_RestoreAllButtons();
		RestoreMinimapClock();
	elseif( cmd == "reset" or cmd == "reset position" ) then
		MBB_ResetPosition();
		RestoreMinimapClock();
		MBB_Print("MBB: Position reset to Minimap edge.");
	elseif( cmd == "buttons" ) then
		MBB_Print("MBB Buttons (" .. table.getn(MBB_Buttons) .. "):");
		for i,name in ipairs(MBB_Buttons) do
			MBB_Print("  " .. name);
		end
	elseif( string.sub(cmd, 1, 6) == "debug " ) then
		local iStart, iEnd, sFrame = string.find(cmd, "debug (.+)");
		local hasClick, hasMouseUp, hasMouseDown, hasEnter, hasLeave = MBB_TestFrame(sFrame);
		MBB_Debug("Frame: " .. tostring(sFrame));
		MBB_Debug("  has OnClick: " .. tostring(hasClick));
		MBB_Debug("  has OnMouseUp: " .. tostring(hasMouseUp));
		MBB_Debug("  has OnMouseDown: " .. tostring(hasMouseDown));
		MBB_Debug("  has OnEnter: " .. tostring(hasEnter));
		MBB_Debug("  has OnLeave: " .. tostring(hasLeave));
	elseif( cmd == "reset all" ) then
		MBB_Options = CloneTable(MBB_DefaultOptions);
		for i=1,table.getn(MBB_Exclude) do
			MBB_AddButton(MBB_Exclude[1]);
		end
		MBB_SetPositions();
		MBB_ResetPosition();
		RestoreMinimapClock();
	else
		MBB_Print("MBB v" .. tostring(MBB_Version) .. ":");
		MBB_Print("  Left-click the bag button to expand/collapse your buttons.");
		MBB_Print("  Right-click the bag button to open options.");
		MBB_Print("  /mbb restore - Return all buttons back around the minimap circle.");
		MBB_Print("  /mbb gather - Gather all minimap buttons into the bag.");
		MBB_Print("  /mbb reset - Reset the bag button back to the minimap border.");
	end
end

function MBB_TestFrame(name)
	local hasClick = false;
	local hasMouseUp = false;
	local hasMouseDown = false;
	local hasEnter = false;
	local hasLeave = false;
	local frame = getglobal(name);
	
	if( frame ) then
		if MBB_SafeHasScript(frame, "OnClick") then hasClick = true end
		if MBB_SafeHasScript(frame, "OnMouseUp") then hasMouseUp = true end
		if MBB_SafeHasScript(frame, "OnMouseDown") then hasMouseDown = true end
		if MBB_SafeHasScript(frame, "OnEnter") then hasEnter = true end
		if MBB_SafeHasScript(frame, "OnLeave") then hasLeave = true end
	end
	
	return hasClick, hasMouseUp, hasMouseDown, hasEnter, hasLeave;
end

function MBB_OnEvent()
	if(event == "ADDON_LOADED" and (arg1 == "Squeenix" or arg1 == "MBB")) then
		MBB_SetButtonPosition();
	end
	if ( event == "VARIABLES_LOADED" ) then
		if ( MBB_Options == nil or MBB_Options["Version"] ~= MBB_Version)  then
			MBB_Options = CloneTable(MBB_DefaultOptions);
		end
		MBB_Options.AttachToMinimap = 1;
		MBB_Options.ExpandDirection = 1; -- Force Left expansion
		if not MBB_Options.ButtonPos or (math.abs(MBB_Options.ButtonPos[1] or 0) > 100 or math.abs(MBB_Options.ButtonPos[2] or 0) > 200) then
			MBB_Options.ButtonPos = {-18, -100};
		end
		MBB_SetButtonPosition();
		RestoreMinimapClock();
	end
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		if MBB_Options then
			MBB_Options.AttachToMinimap = 1;
			MBB_Options.ExpandDirection = 1;
			if not MBB_Options.ButtonPos or (math.abs(MBB_Options.ButtonPos[1] or 0) > 100 or math.abs(MBB_Options.ButtonPos[2] or 0) > 200) then
				MBB_Options.ButtonPos = {-18, -100};
			end
			MBB_SetButtonPosition();
		end
		RestoreMinimapClock();
		_starttime = GetTime();
		_rescan_count = 0;
	end
end

function MBB_GatherIcons()
	local children = {Minimap:GetChildren()};
	local additional = {MinimapBackdrop:GetChildren()};
	for _,child in ipairs(additional) do
		table.insert(children, child);
	end
	for _,child in ipairs(MBB_Include) do
		local frame = getglobal(child);
		if( frame ) then
			table.insert(children, frame);
		end
	end
	
	for _,child in ipairs(children) do
		if( child and child:GetName() ) then
			local cName = child:GetName();
			local ignore = false;
			for _, needle in ipairs(MBB_Ignore) do
				if( string.find(cName, needle) ) then
					ignore = true;
					break;
				end
			end
			if( not ignore ) then
				-- If child is not a Button, look for a button subchild
				if( child:GetObjectType() ~= "Button" ) then
					for _, subchild in ipairs({child:GetChildren()}) do
						if( subchild and subchild:GetName() and subchild:GetObjectType() == "Button" ) then
							local subName = subchild:GetName();
							local subIgnore = false;
							for _, needle in ipairs(MBB_Ignore) do
								if string.find(subName, needle) then subIgnore = true; break; end
							end
							if not subIgnore then
								child = subchild;
								cName = subName;
								break;
							end
						end
					end
				end
				
				-- Only add actual Buttons
				if( child:GetObjectType() == "Button" ) then
					local hasClick, hasMouseUp, hasMouseDown = MBB_TestFrame(cName);
					if( hasClick or hasMouseUp or hasMouseDown ) then
						if( not MBB_IsExcluded(cName) ) then
							MBB_PrepareButton(cName);
							MBB_AddButton(cName);
						end
					end
				end
			end
		end
	end
	
	MBB_SetPositions();
	RestoreMinimapClock();
end

function MBB_PrepareButton(name)
	local frame = getglobal(name);
	if not frame or frame.mbb_prepared then return end
	frame.mbb_prepared = true;

	if( frame.RegisterForClicks ) then
		pcall(frame.RegisterForClicks, frame, "LeftButtonDown","RightButtonDown");
	end
	
	frame.isvisible = frame:IsVisible();
	frame.oshow = frame.Show;
	frame.Show = function(frame)
		frame.isvisible = true;
		if( not MBB_IsExcluded(frame:GetName()) ) then
			MBB_SetPositions();
		end
		if( MBB_IsExcluded(frame:GetName()) or (MBB_Buttons[1] and MBB_Buttons[1] ~= frame:GetName() and getglobal(MBB_Buttons[1]):IsVisible()) ) then
			frame.oshow(frame);
		end
	end
	frame.ohide = frame.Hide;
	frame.Hide = function(frame)
		frame.isvisible = false;
		frame.ohide(frame);
		if( not MBB_IsExcluded(frame:GetName()) ) then
			MBB_SetPositions();
		end
	end
	
	if( MBB_SafeHasScript(frame, "OnClick") ) then
		frame.oclick = frame:GetScript("OnClick");
		frame:SetScript("OnClick", function()
			if( arg1 and arg1 == "RightButton" and IsControlKeyDown() ) then
				local name = this:GetName();
				if( MBB_IsExcluded(name) ) then
					MBB_AddButton(name);
				else
					MBB_RestoreButton(name);
				end
				MBB_SetPositions();
			elseif( this.oclick ) then
				this.oclick();
			end
		end);
	elseif( MBB_SafeHasScript(frame, "OnMouseUp") ) then
		frame.omouseup = frame:GetScript("OnMouseUp");
		frame:SetScript("OnMouseUp", function()
			if( arg1 and arg1 == "RightButton" and IsControlKeyDown() ) then
				local name = this:GetName();
				if( MBB_IsExcluded(name) ) then
					MBB_AddButton(name);
				else
					MBB_RestoreButton(name);
				end
				MBB_SetPositions();
			elseif( this.omouseup ) then
				this.omouseup();
			end
		end);
	elseif( MBB_SafeHasScript(frame, "OnMouseDown") ) then
		frame.omousedown = frame:GetScript("OnMouseDown");
		frame:SetScript("OnMouseDown", function()
			if( arg1 and arg1 == "RightButton" and IsControlKeyDown() ) then
				local name = this:GetName();
				if( MBB_IsExcluded(name) ) then
					MBB_AddButton(name);
				else
					MBB_RestoreButton(name);
				end
				MBB_SetPositions();
			elseif( this.omousedown ) then
				this.omousedown();
			end
		end);
	end
	if( MBB_SafeHasScript(frame, "OnEnter") ) then
		frame.oenter = frame:GetScript("OnEnter");
		frame:SetScript("OnEnter", function()
			if( not MBB_IsExcluded(this:GetName()) ) then
				MBB_ShowTimeout = -1;
			end
			if( this.oenter ) then
				this.oenter();
			end
		end);
	end
	if( MBB_SafeHasScript(frame, "OnLeave") ) then
		frame.oleave = frame:GetScript("OnLeave");
		frame:SetScript("OnLeave", function()
			if( not MBB_IsExcluded(this:GetName()) ) then
				MBB_ShowTimeout = 0;
			end
			if( this.oleave ) then
				this.oleave();
			end
		end);
	end
	
	if MBB_CallBack[name] then
		local func = MBB_CallBack[name];
		pcall(func);
	end
end

function MBB_AddButton(name)
	local child = getglobal(name);
	if not child then return end
	if MBB_IsInArray(MBB_Buttons, name) then return end

	local show = false;
	if( MBB_Buttons[1] and MBB_Buttons[1] ~= name and getglobal(MBB_Buttons[1]):IsVisible() ) then
		show = true;
	end
	
	child.opoint = {child:GetPoint()};
	if( not child.opoint[1] ) then
		child.opoint = {"TOP", Minimap, "BOTTOM", 0, 0};
	end
	child.osize = {child:GetHeight(), child:GetWidth()};
	child.oclearallpoints = child.ClearAllPoints;
	child.ClearAllPoints = function() end;
	child.osetpoint = child.SetPoint;
	child.SetPoint = function() end;
	if( not show ) then
		child.ohide(child);
	end
	table.insert(MBB_Buttons, name);
	local i = MBB_IsInArray(MBB_Exclude, name);
	if( i ) then
		table.remove(MBB_Exclude, i);
	end
end

function MBB_IsExcluded(name)
	for _, needle in ipairs(MBB_Exclude) do
		if( needle == name ) then
			return true;
		end
	end
	return false;
end

function MBB_RestoreButton(name)
	local button = getglobal(name);
	if not button then return end
	
	if button.oclearallpoints then
		button.oclearallpoints(button);
	end
	if button.osetpoint and button.opoint and button.opoint[1] then
		button.osetpoint(button, button.opoint[1], button.opoint[2], button.opoint[3], button.opoint[4], button.opoint[5]);
	end
	if button.osize and button.osize[1] then
		button:SetHeight(button.osize[1]);
		button:SetWidth(button.osize[2] or button.osize[1]);
	end
	if button.oclearallpoints then
		button.ClearAllPoints = button.oclearallpoints;
	end
	if button.osetpoint then
		button.SetPoint = button.osetpoint;
	end
	if (button.isvisible) then
		button.oshow(button);
	else
		button.ohide(button);
	end
	
	table.insert(MBB_Exclude, name);
	local i = MBB_IsInArray(MBB_Buttons, name);
	if( i ) then
		table.remove(MBB_Buttons, i);
	end
end

function MBB_RestoreAllButtons()
	while table.getn(MBB_Buttons) > 0 do
		MBB_RestoreButton(MBB_Buttons[1]);
	end
	RestoreMinimapClock();
	MBB_Print("MBB: All minimap buttons restored to their original positions.");
end

function MBB_SetPositions()
	local cols = {};
	local parent = MBB_MinimapButtonFrame;
	local prev = nil;
	local count = 0;
	
	for i, name in ipairs(MBB_Buttons) do
		local frame = getglobal(name);
		if( frame and frame.isvisible ) then
			count = count + 1;
			
			-- Uniform standard 32x32 button size
			frame:SetWidth(32);
			frame:SetHeight(32);
			
			if frame.oclearallpoints then
				frame.oclearallpoints(frame);
			else
				frame:ClearAllPoints();
			end
			
			-- Clean row extending LEFT from the bag button:
			-- Button 1 anchors RIGHT to MBB's LEFT with a 6px gap
			-- Subsequent buttons anchor RIGHT to previous button's LEFT with a 4px gap
			if count == 1 then
				if frame.osetpoint then
					frame.osetpoint(frame, "RIGHT", MBB_MinimapButtonFrame, "LEFT", -6, 0);
				else
					frame:SetPoint("RIGHT", MBB_MinimapButtonFrame, "LEFT", -6, 0);
				end
			else
				if frame.osetpoint then
					frame.osetpoint(frame, "RIGHT", prev, "LEFT", -4, 0);
				else
					frame:SetPoint("RIGHT", prev, "LEFT", -4, 0);
				end
			end
			
			prev = frame;
		end
	end
end

function MBB_OnClick(arg1)
	if( arg1 and arg1 == "RightButton" and IsControlKeyDown() ) then
		MBB_ResetPosition();
	elseif( arg1 and arg1 == "RightButton" ) then
		if MBB_OptionsFrame then
			MBB_OptionsFrame:Show();
		end
	else
		if( MBB_Buttons[1] and getglobal(MBB_Buttons[1]) and getglobal(MBB_Buttons[1]):IsVisible() ) then
			MBB_HideButtons();
		else
			for i,name in ipairs(MBB_Buttons) do
				local frame = getglobal(name);
				if frame and frame.isvisible then
					if frame.oshow then frame.oshow(frame); else frame:Show(); end
				end
			end
			MBB_SetPositions();
		end
	end
end

function MBB_OnMouseDown()
	if( arg1 and arg1 == "LeftButton" and ((MBB_Options and MBB_Options.AttachToMinimap) or 1) == 0 ) then
		MBB_MinimapButtonFrame:StartMoving();
	elseif( arg1 and arg1 == "LeftButton" and ((MBB_Options and MBB_Options.AttachToMinimap) or 1) == 1 ) then
		MBB_DragFlag = 1;
	end
end

function MBB_OnMouseUp()
	if( arg1 and arg1 == "LeftButton" ) then
		if( ((MBB_Options and MBB_Options.AttachToMinimap) or 1) == 0 ) then
			MBB_MinimapButtonFrame:StopMovingOrSizing();
			local cX, cY = MBB_MinimapButtonFrame:GetCenter();
			local sX, sY = UIParent:GetCenter();
			local scale = ((MBB_Options and MBB_Options.Scale) or 100) / 100;
			local xpos = (cX - sX) * UIParent:GetScale() / scale;
			local ypos = (cY - sY) * UIParent:GetScale() / scale;
			MBB_Options.ButtonPos = {xpos, ypos};
		end
		MBB_DragFlag = 0;
	end
end

function MBB_HideButtons()
	MBB_ShowTimeout = -1;
	for i,name in ipairs(MBB_Buttons) do
		local frame = getglobal(name);
		if frame then
			if frame.ohide then frame.ohide(frame); else frame:Hide(); end
		end
	end
end

function MBB_OnUpdate(elapsed)
	if (_rescan_count < 3 and _starttime and (GetTime() - _starttime) > ((_rescan_count + 1) * 3)) then
		_rescan_count = _rescan_count + 1;
		MBB_GatherIcons();
		MBB_SetButtonPosition();
		RestoreMinimapClock();
	end
	
	if( MBB_DragFlag == 1 and ((MBB_Options and MBB_Options.AttachToMinimap) or 1) == 1 ) then
		local xpos,ypos = GetCursorPosition();
		local xmin,ymin,xm,ym = Minimap:GetLeft(), Minimap:GetBottom(), Minimap:GetRight(), Minimap:GetTop();
		local scale = Minimap:GetEffectiveScale();
		local xdelta, ydelta = (xm - xmin)/2*scale, (ym - ymin)/2*scale;
		
		xpos = xmin*scale - xpos + xdelta;
		ypos = ypos - ymin*scale - ydelta;

		local angle = math.deg(math.atan2(ypos, xpos));
		
		local x = math.cos(math.rad(angle)) * xdelta;
		local y = math.sin(math.rad(angle)) * ydelta;
		
		local sc = ((MBB_Options and MBB_Options.Scale) or 100) / 100;
		MBB_MinimapButtonFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", (xdelta-x)/sc - 17, (y-ydelta)/sc + 17);
	end
	
	if( MBB_Options and MBB_Options.CollapseTimeout and MBB_Options.CollapseTimeout ~= 0 ) then
		if( MBB_Buttons[1] and getglobal(MBB_Buttons[1]) ) then
			if( MBB_ShowTimeout >= MBB_Options.CollapseTimeout and getglobal(MBB_Buttons[1]):IsVisible() ) then
				MBB_HideButtons();
			end
		end
		if( MBB_ShowTimeout ~= -1 ) then
			MBB_ShowTimeout = MBB_ShowTimeout + elapsed;
		end
	end
end

function MBB_ResetPosition()
	if not MBB_Options then MBB_Options = CloneTable(MBB_DefaultOptions); end
	MBB_Options.ButtonPos = {-18, -100};
	MBB_Options.AttachToMinimap = 1;
	MBB_SetButtonPosition();
	RestoreMinimapClock();
end

function MBB_SetButtonPosition()
	if not MBB_Options then return end
	if not MBB_MinimapButtonFrame then return end
	MBB_MinimapButtonFrame:SetScale((((MBB_Options and MBB_Options.Scale) or 100) * (1/Minimap:GetEffectiveScale()))/100);
	if( ((MBB_Options and MBB_Options.AttachToMinimap) or 1) == 1 ) then
		MBB_MinimapButtonFrame:ClearAllPoints();
		MBB_MinimapButtonFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", MBB_Options.ButtonPos[1] or -18, MBB_Options.ButtonPos[2] or -100);
	else
		MBB_MinimapButtonFrame:ClearAllPoints();
		MBB_MinimapButtonFrame:SetPoint("CENTER", UIParent, "CENTER", MBB_Options.ButtonPos[1] or 0, MBB_Options.ButtonPos[2] or 0);
	end
end

function MBB_Debug(msg)
	if (MBB_DebugFlag == 1) then
		MBB_Print("MBB Debug : " .. tostring(msg));
	end
end

function MBB_IsInArray(array, needle)
	if(type(array) == "table") then
		for _, element in pairs(array) do
			if(element == needle) then
				return true;
			end
		end
	end
	return false;
end

function MBB_Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(tostring(msg), 0.2, 0.8, 0.8);
	end
end