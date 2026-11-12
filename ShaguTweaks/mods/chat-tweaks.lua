local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T
local scrollspeed = 1

local module = ShaguTweaks:register({
  title = T["Chat Tweaks"],
  description = T["Allows to scroll using the mouse wheel, enables sticky chat channels and repeats message on arrow up."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Social & Chat"],
  enabled = true,
})

local function ChatOnMouseWheel()
  if arg1 > 0 then
    if IsShiftKeyDown() then
      this:ScrollToTop()
    else
      for i=1, scrollspeed do
        this:ScrollUp()
      end
    end
  elseif arg1 < 0 then
    if IsShiftKeyDown() then
      this:ScrollToBottom()
    else
      for i=1, scrollspeed do
        this:ScrollDown()
      end
    end
  end
end

module.enable = function(self)
  -- enable sticky chat types
  ChatTypeInfo.WHISPER.sticky = 1
  ChatTypeInfo.OFFICER.sticky = 1
  ChatTypeInfo.RAID_WARNING.sticky = 1
  ChatTypeInfo.CHANNEL.sticky = 1

  -- repeat message without pressing <alt>
  ChatFrameEditBox:SetAltArrowKeyMode(false)

  for i=1, NUM_CHAT_WINDOWS do
    -- enable mouse wheel scrolling
    _G["ChatFrame" .. i]:EnableMouseWheel(true)
    _G["ChatFrame" .. i]:SetScript("OnMouseWheel", ChatOnMouseWheel)
  end

  -- Keep chat tabs permanently visible
  local function InitChatTab(i)
    local tab = _G["ChatFrame" .. i .. "Tab"]
    local frame = _G["ChatFrame" .. i]
    if not tab then return end

    tab.isChatTabLocked = true

    if not tab.hookedChatTabHide then
      tab.hookedChatTabHide = true
      tab.origChatTabHide = tab.Hide
      tab.Hide = function(self)
        local id = self:GetID()
        local cf = _G["ChatFrame" .. id]
        local _, _, _, _, _, _, shown = GetChatWindowInfo(id)
        if cf and (shown or cf:IsShown() or cf.isDocked) then
          return
        end
        return self:origChatTabHide()
      end
    end

    local _, _, _, _, _, _, shown = GetChatWindowInfo(i)
    if shown or (frame and (frame:IsShown() or frame.isDocked)) then
      if UIFrameFadeRemoveFrame then
        UIFrameFadeRemoveFrame(tab)
      end
      tab:Show()
      if frame and frame.isDocked and SELECTED_DOCK_FRAME and frame ~= SELECTED_DOCK_FRAME then
        tab:SetAlpha(0.6)
      else
        tab:SetAlpha(1.0)
      end
    end
  end

  -- Prevent UIFrameFade from fading out locked chat tabs
  if not ShaguTweaks.orig_UIFrameFade then
    ShaguTweaks.orig_UIFrameFade = UIFrameFade
    UIFrameFade = function(frame, fadeInfo)
      if frame and frame.isChatTabLocked and fadeInfo and (fadeInfo.mode == "OUT" or (fadeInfo.endAlpha and fadeInfo.endAlpha < 0.5)) then
        if UIFrameFadeRemoveFrame then
          UIFrameFadeRemoveFrame(frame)
        end
        frame:Show()
        return
      end
      return ShaguTweaks.orig_UIFrameFade(frame, fadeInfo)
    end
  end

  -- Prevent FCF_ChatTabFadeFinished from hiding locked chat tabs
  if not ShaguTweaks.orig_FCF_ChatTabFadeFinished then
    ShaguTweaks.orig_FCF_ChatTabFadeFinished = FCF_ChatTabFadeFinished
    FCF_ChatTabFadeFinished = function(chatTab, chatFrame)
      if chatTab and chatTab.isChatTabLocked then
        if UIFrameFadeRemoveFrame then
          UIFrameFadeRemoveFrame(chatTab)
        end
        chatTab:Show()
        if chatFrame and chatFrame.isDocked and SELECTED_DOCK_FRAME and chatFrame ~= SELECTED_DOCK_FRAME then
          chatTab:SetAlpha(0.6)
        else
          chatTab:SetAlpha(1.0)
        end
        if chatFrame then
          chatFrame.oldAlpha = nil
        end
        return
      end
      if ShaguTweaks.orig_FCF_ChatTabFadeFinished then
        return ShaguTweaks.orig_FCF_ChatTabFadeFinished(chatTab, chatFrame)
      end
    end
  end

  -- Hook FCF_OnUpdate to keep active tabs shown and manage hover alpha smoothly
  if not ShaguTweaks.orig_FCF_OnUpdate then
    ShaguTweaks.orig_FCF_OnUpdate = FCF_OnUpdate
    FCF_OnUpdate = function(elapsed)
      if ShaguTweaks.orig_FCF_OnUpdate then
        ShaguTweaks.orig_FCF_OnUpdate(elapsed)
      end
      for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        local frame = _G["ChatFrame" .. i]
        if tab and frame then
          local _, _, _, _, _, _, shown = GetChatWindowInfo(i)
          if shown or frame:IsShown() or frame.isDocked then
            if not tab:IsShown() then
              tab:Show()
            end
            if UIFrameFadeRemoveFrame then
              UIFrameFadeRemoveFrame(tab)
            end
            local isOver = MouseIsOver(tab)
            if (SELECTED_DOCK_FRAME and frame == SELECTED_DOCK_FRAME) or isOver or not frame.isDocked then
              if tab:GetAlpha() ~= 1.0 then
                tab:SetAlpha(1.0)
              end
            else
              if tab:GetAlpha() ~= 0.6 then
                tab:SetAlpha(0.6)
              end
            end
          end
        end
      end
    end
  end

  -- Hook dock/update functions
  local origFloatingChatFrame_Update = FloatingChatFrame_Update
  FloatingChatFrame_Update = function(id, onUpdateEvent)
    if origFloatingChatFrame_Update then
      origFloatingChatFrame_Update(id, onUpdateEvent)
    end
    for i = 1, NUM_CHAT_WINDOWS do
      InitChatTab(i)
    end
  end

  local origFCF_DockFrame = FCF_DockFrame
  FCF_DockFrame = function(frame, index, force)
    if origFCF_DockFrame then
      origFCF_DockFrame(frame, index, force)
    end
    for i = 1, NUM_CHAT_WINDOWS do
      InitChatTab(i)
    end
  end

  for i = 1, NUM_CHAT_WINDOWS do
    InitChatTab(i)
  end
end
