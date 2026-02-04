local ADDON_NAME = ...
RefundableTalentsGlowDB = RefundableTalentsGlowDB or {}

local DB = RefundableTalentsGlowDB
local AceGUI = LibStub("AceGUI-3.0")
if DB.enabled == nil then DB.enabled = true end

-- Defaults
if type(DB.glowTexture) ~= "string" or DB.glowTexture == "" then
	DB.glowTexture = "atlas:talents-node-square-greenglow"
end

-- Migrate older raw texture selections to atlas variants (prevents "many boxes" / invisible spritesheets)
if DB.glowTexture == "Interface\\SpellActivationOverlay\\IconAlertAnts" then
	DB.glowTexture = "atlas:IconAlertAnts"
end
if DB.glowTexture == "Interface\\Azerite\\AzeritePowerRing" then
	DB.glowTexture = "atlas:AzeritePowerRing"
end

if type(DB.glowColor) ~= "table" then
	DB.glowColor = { r = 0.2, g = 1.0, b = 0.2, a = 1.0 }
else
	DB.glowColor.r = tonumber(DB.glowColor.r) or 0.2
	DB.glowColor.g = tonumber(DB.glowColor.g) or 1.0
	DB.glowColor.b = tonumber(DB.glowColor.b) or 0.2
	DB.glowColor.a = tonumber(DB.glowColor.a) or 1.0
end


local function SafeCall(func, ...)
	local ok, res = pcall(func, ...)
	if ok then return res end
	return nil
end

local function GetActiveTalentConfigID()
	-- Retail talent trees use Trait configs; this returns the currently-selected spec's config.
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
		return C_ClassTalents.GetActiveConfigID()
	end
	return nil
end


local RTG_TEXTURES

local function ApplyGlowStyle(tex)
	-- tex is the glow texture object
	local setting = DB.glowTexture or "atlas:talents-node-square-greenglow"

	-- pick blend mode based on selection (default ADD)
	local blend = "ADD"
	for _, opt in ipairs(RTG_TEXTURES or {}) do
		if opt.value == setting and opt.blend then
			blend = opt.blend
			break
		end
	end
	if tex.SetBlendMode then
		tex:SetBlendMode(blend)
	end

	-- Atlas support (fixes sprite-sheet textures like IconAlertAnts)
	if type(setting) == "string" and setting:sub(1, 6) == "atlas:" then
		local atlas = setting:sub(7)
		local ok = false
		if tex.SetAtlas then
			ok = SafeCall(tex.SetAtlas, tex, atlas, false) and true or false
		end
		if not ok then
			-- fallback to a direct texture path if the atlas is missing on this build
			local fb
			for _, opt in ipairs(RTG_TEXTURES or {}) do
				if opt.value == setting then fb = opt.fallback break end
			end
			if fb then
				tex:SetTexture(fb)
				if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
			else
				tex:SetTexture(nil)
			end
		end
	else
		tex:SetTexture(setting)
		if tex.SetTexCoord then
			tex:SetTexCoord(0, 1, 0, 1)
		end
	end

	local c = DB.glowColor or {}
	tex:SetVertexColor(tonumber(c.r) or 0.2, tonumber(c.g) or 1.0, tonumber(c.b) or 0.2, 1)

	-- Opacity is controlled by the wrapper frame's alpha (multiplies with animation alpha)
	local wrapper = tex:GetParent()
	if wrapper and wrapper.__RTGIsWrapper then
		wrapper:SetAlpha(tonumber(c.a) or 1.0)
	end
end

local function EnsureGlow(button)
	if button.__RTGGlow then
		ApplyGlowStyle(button.__RTGGlow)
		return button.__RTGGlow
	end

	-- Wrapper frame controls opacity via SetAlpha, independent of the pulse animation
	local wrapper = CreateFrame("Frame", nil, button)
	wrapper.__RTGIsWrapper = true
	wrapper:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 0) + 5)
	wrapper:SetAlpha(DB.glowColor and tonumber(DB.glowColor.a) or 1.0)

	local function SizeGlow()
		local w = (button.GetWidth and button:GetWidth()) or 36
		local h = (button.GetHeight and button:GetHeight()) or 36
		wrapper:SetSize(w * 1.85, h * 1.85)
		wrapper:SetPoint("CENTER", button, "CENTER", 0, 0)
	end
	SizeGlow()

	if button.HookScript then
		button:HookScript("OnSizeChanged", SizeGlow)
	end

	-- Glow texture inside wrapper
	local glow = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
	glow:SetAllPoints(wrapper)
	ApplyGlowStyle(glow)

	-- Pulse animation with fixed alpha values (wrapper alpha handles opacity)
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("REPEAT")

	local a1 = ag:CreateAnimation("Alpha")
	a1:SetFromAlpha(0.25)
	a1:SetToAlpha(0.9)
	a1:SetDuration(0.65)
	a1:SetOrder(1)

	local a2 = ag:CreateAnimation("Alpha")
	a2:SetFromAlpha(0.9)
	a2:SetToAlpha(0.25)
	a2:SetDuration(0.65)
	a2:SetOrder(2)

	button.__RTGGlow = glow
	button.__RTGGlowWrapper = wrapper
	button.__RTGGlowAG = ag
	wrapper:Hide()
	return glow
end

local function SetGlowing(button, shouldGlow)
	local glow = EnsureGlow(button)
	local wrapper = button.__RTGGlowWrapper
	local ag = button.__RTGGlowAG
	if shouldGlow then
		wrapper:Show()
		if ag and not ag:IsPlaying() then ag:Play() end
	else
		if ag and ag:IsPlaying() then ag:Stop() end
		wrapper:Hide()
	end
end

local function IsRefundableNode(configID, nodeID)
	-- "CanRefundRank" is the closest direct API for "right-click refundable right now".
	if not (C_Traits and C_Traits.CanRefundRank) then
		return false
	end
	return SafeCall(C_Traits.CanRefundRank, configID, nodeID) == true
end

local function GetTalentRoots()
	local roots = {}
	local seen = {}

	-- Legacy (Dragonflight): ClassTalentFrame was the talent tree itself
	if _G.ClassTalentFrame then
		table.insert(roots, _G.ClassTalentFrame)
		seen[_G.ClassTalentFrame] = true
	end

	-- TWW+: PlayerSpellsFrame is a tabbed container (Spec / Talents / SpellBook).
	-- Use TalentsFrame specifically so we never touch SpecFrame or its children,
	-- which avoids taint that breaks other addons' spec-switching buttons.
	local psf = _G.PlayerSpellsFrame
	if psf then
		local tf = psf.TalentsFrame
		if tf and not seen[tf] then
			table.insert(roots, tf)
		elseif not tf and not seen[psf] then
			-- Fallback in case TalentsFrame isn't available yet
			table.insert(roots, psf)
		end
	end

	return roots
end

local function ForEachPotentialNodeButton(callback)
	local roots = GetTalentRoots()
	for _, root in ipairs(roots) do
		local stack = { root }
		local seen = {}

		while #stack > 0 do
			local frame = stack[#stack]
			stack[#stack] = nil

			if frame and not seen[frame] then
				seen[frame] = true

				-- Heuristic: Blizzard talent node buttons typically carry a numeric nodeID field.
				local nodeID = rawget(frame, "nodeID")
				if type(nodeID) == "number" then
					callback(frame, nodeID)
				end

				if frame.GetChildren then
					local children = { frame:GetChildren() }
					for i = 1, #children do
						stack[#stack + 1] = children[i]
					end
				end
			end
		end
	end
end

local function UpdateAllGlowStyles()
	-- Update any already-created glows that are currently reachable in the talent UI.
	ForEachPotentialNodeButton(function(btn)
		if btn.__RTGGlow then
			ApplyGlowStyle(btn.__RTGGlow)
		end
	end)
end

local function UpdateAllGlowOpacity()
	-- Lightweight update: only touches wrapper frame alpha, no texture operations.
	local opacity = DB.glowColor and tonumber(DB.glowColor.a) or 1.0
	ForEachPotentialNodeButton(function(btn)
		if btn.__RTGGlowWrapper then
			btn.__RTGGlowWrapper:SetAlpha(opacity)
		end
	end)
end

local pendingUpdate = false

local function UpdateHighlights()
	pendingUpdate = false

	if not DB.enabled then
		-- disable all glows currently created
		ForEachPotentialNodeButton(function(btn)
			if btn.__RTGGlow then
				SetGlowing(btn, false)
			end
		end)
		return
	end

	local configID = GetActiveTalentConfigID()
	if not configID then return end

	-- Only do work if the talent UI is actually shown.
	local anyRootShown = false
	for _, root in ipairs(GetTalentRoots()) do
		if root and root.IsShown and root:IsShown() then
			anyRootShown = true
			break
		end
	end
	if not anyRootShown then return end

	ForEachPotentialNodeButton(function(btn, nodeID)
		local refundable = IsRefundableNode(configID, nodeID)
		SetGlowing(btn, refundable)
	end)
end

local function RequestUpdate()
	if pendingUpdate then return end
	pendingUpdate = true
	-- Defer one frame so the UI has time to update node states.
	if C_Timer and C_Timer.After then
		C_Timer.After(0, UpdateHighlights)
	else
		UpdateHighlights()
	end
end

-- === "Burst refresh" on opening talents ===
-- When you open the talents pane, the node buttons may not have nodeIDs immediately.
-- A short ticker ensures we catch the fully-initialized UI without requiring you to click/refund.
local burstTicker = nil
local function StopBurstRefresh()
	if burstTicker and burstTicker.Cancel then
		burstTicker:Cancel()
	end
	burstTicker = nil
end

local function StartBurstRefresh()
	StopBurstRefresh()

	if not (C_Timer and C_Timer.NewTicker) then
		-- fallback
		RequestUpdate()
		return
	end

	local ticks = 0
	burstTicker = C_Timer.NewTicker(0.15, function()
		ticks = ticks + 1
		UpdateHighlights()
		-- ~2.25 seconds total; enough for the talent UI to fully build.
		if ticks >= 15 then
			StopBurstRefresh()
		end
	end)
end

-- Forward declarations for config panel functions
local CreateToggleButton, CreateConfigPanel, ToggleConfigPanel, PopulateConfigWidgets, RefreshConfigValues

-- Track hooked legacy frames (Dragonflight ClassTalentFrame only)
local hookedLegacyFrames = {}

local function HookLegacyRoot(root)
	if not root or hookedLegacyFrames[root] or not root.HookScript then return end
	hookedLegacyFrames[root] = true

	root:HookScript("OnShow", function()
		StartBurstRefresh()
		CreateToggleButton(root)
	end)

	root:HookScript("OnHide", function()
		StopBurstRefresh()
		if RTG_ConfigPanel then
			RTG_ConfigPanel:Hide()
		end
	end)
end

-- TWW+: Use EventRegistry callbacks instead of HookScript on TalentsFrame.
-- HookScript fires inside TabSystemTrackerMixin:SetTab's Show/Hide loop, which
-- taints the rest of the tab-switch execution and breaks other addons (e.g. TTT
-- spec-switching buttons seeing isInitialized as nil due to tainted reads).
local registeredEventCallbacks = false

local function SetupEventCallbacks()
	if registeredEventCallbacks then return end
	if not _G.PlayerSpellsFrame then return end
	if not EventRegistry then return end
	registeredEventCallbacks = true

	-- When a tab is selected, activate/deactivate based on whether it's the Talents tab
	EventRegistry:RegisterCallback("PlayerSpellsFrame.TabSet", function(_, frame, tabID)
		if frame and frame.talentTabID and tabID == frame.talentTabID then
			local tf = frame.TalentsFrame
			if tf then
				StartBurstRefresh()
				CreateToggleButton(tf)
			end
		else
			StopBurstRefresh()
			if RTG_ConfigPanel then
				RTG_ConfigPanel:Hide()
			end
		end
	end, "RTG_TabSet")

	-- When the frame reopens with Talents already the active tab, TabSet won't re-fire
	EventRegistry:RegisterCallback("PlayerSpellsFrame.OpenFrame", function()
		local psf = _G.PlayerSpellsFrame
		if psf and psf.TalentsFrame and psf.TalentsFrame:IsShown() then
			StartBurstRefresh()
			CreateToggleButton(psf.TalentsFrame)
		end
	end, "RTG_Open")

	-- When the entire frame closes
	EventRegistry:RegisterCallback("PlayerSpellsFrame.CloseFrame", function()
		StopBurstRefresh()
		if RTG_ConfigPanel then
			RTG_ConfigPanel:Hide()
		end
	end, "RTG_Close")
end

local function HookAllRoots()
	-- Legacy (Dragonflight): ClassTalentFrame is the talent tree itself, safe to HookScript
	if _G.ClassTalentFrame then
		HookLegacyRoot(_G.ClassTalentFrame)
	end

	-- TWW+: Use EventRegistry instead of HookScript to avoid taint
	SetupEventCallbacks()
end

-- Poll briefly to catch frames that are created after addon load.
local function StartHookPolling()
	if not (C_Timer and C_Timer.NewTicker) then
		HookAllRoots()
		return
	end

	local tries = 0
	local t = nil
	t = C_Timer.NewTicker(0.5, function()
		tries = tries + 1
		HookAllRoots()

		-- Stop once we've set up callbacks, or after 20 tries (~10s)
		local hookedAny = registeredEventCallbacks
		if not hookedAny then
			for _ in pairs(hookedLegacyFrames) do
				hookedAny = true
				break
			end
		end

		if hookedAny or tries >= 20 then
			if t and t.Cancel then t:Cancel() end
		end
	end)
end

-- Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

-- Talent system events (won't error if they never fire)
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("TRAIT_CONFIG_LIST_UPDATED")
f:RegisterEvent("TRAIT_NODE_CHANGED")
f:RegisterEvent("TRAIT_NODE_CHANGED_PARTIAL")
f:RegisterEvent("TRAIT_NODE_ENTRY_UPDATED")
f:RegisterEvent("TRAIT_TREE_CHANGED")
f:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		-- When the Blizzard UI modules load, hooks may become available.
		if arg1 == "Blizzard_ClassTalentUI" or arg1 == "Blizzard_PlayerSpells" then
			HookAllRoots()

			-- Safety net: if Blizzard_PlayerSpells loaded before C_SpecializationInfo was
			-- ready (e.g. during /reload), SpecFrame:OnLoad skips initialization and
			-- isInitialized stays nil.  Schedule a deferred re-check so SpecFrame can
			-- finish initializing once the spec system is actually ready.  This prevents
			-- "class talent data has not yet been loaded" errors from other addons that
			-- call ActivateSpecByIndex without first opening the Spec tab.
			if arg1 == "Blizzard_PlayerSpells" and C_Timer and C_Timer.After then
				C_Timer.After(1, function()
					local psf = _G.PlayerSpellsFrame
					if psf and psf.SpecFrame and not psf.SpecFrame.isInitialized then
						if C_SpecializationInfo and C_SpecializationInfo.IsInitialized
								and C_SpecializationInfo.IsInitialized() then
							psf.SpecFrame:UpdateSpecContents()
						end
					end
				end)
			end
		end
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		StartHookPolling()
		-- no return; we still want to request update for correctness
	end

	-- Any time the config or spec changes, refresh (if pane is open).
	RequestUpdate()
end)


-- === Config panel (/rtg config) ===

RTG_TEXTURES = {
	{ name = "Talent Node Glow (default)", value = "atlas:talents-node-square-greenglow", blend = "ADD" },
	{ name = "Action Button Border", value = "Interface\\Buttons\\UI-ActionButton-Border", blend = "ADD" },
	{ name = "Button Outline", value = "Interface\\Buttons\\UI-Button-Outline", blend = "ADD" },
	{ name = "Soulbind Ring Glow", value = "atlas:Soulbinds_Tree_Ring_Glow", blend = "ADD" },
	{ name = "Collections New Glow", value = "atlas:collections-newglow", blend = "ADD" },
	{ name = "Garrison Circle Glow", value = "atlas:GarrLanding-CircleGlow", blend = "ADD" },
}

local RTG_ConfigPanel   -- raw WoW frame (outer shell, parented to talent frame)
local RTG_ConfigGroup   -- AceGUI SimpleGroup (embedded inside shell)
local RTG_ToggleButton  -- gear icon button on talent frame

-- Widget references for RefreshConfigValues
local RTG_ColorPicker, RTG_OpacitySlider, RTG_TextureDropdown, RTG_EnabledToggle

PopulateConfigWidgets = function(group)
	-- Top row: Color picker + Enable toggle side by side
	local topRow = AceGUI:Create("SimpleGroup")
	topRow:SetLayout("Flow")
	topRow:SetFullWidth(true)

	-- Glow Color picker (RGB only, no alpha)
	local colorPicker = AceGUI:Create("ColorPicker")
	colorPicker:SetLabel("Glow Color")
	colorPicker:SetHasAlpha(false)
	colorPicker:SetRelativeWidth(0.5)
	local c = DB.glowColor or {}
	colorPicker:SetColor(c.r or 0.2, c.g or 1.0, c.b or 0.2)
	colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b)
		DB.glowColor = DB.glowColor or {}
		DB.glowColor.r, DB.glowColor.g, DB.glowColor.b = r, g, b
		UpdateAllGlowStyles()
		RequestUpdate()
	end)
	colorPicker:SetCallback("OnValueConfirmed", function(_, _, r, g, b)
		DB.glowColor = DB.glowColor or {}
		DB.glowColor.r, DB.glowColor.g, DB.glowColor.b = r, g, b
		UpdateAllGlowStyles()
		RequestUpdate()
	end)
	topRow:AddChild(colorPicker)
	RTG_ColorPicker = colorPicker

	-- Enable/Disable toggle
	local enabledToggle = AceGUI:Create("CheckBox")
	enabledToggle:SetLabel("Enable Glow")
	enabledToggle:SetRelativeWidth(0.5)
	enabledToggle:SetValue(DB.enabled == true)
	enabledToggle:SetCallback("OnValueChanged", function(_, _, val)
		DB.enabled = val
		RequestUpdate()
	end)
	topRow:AddChild(enabledToggle)
	RTG_EnabledToggle = enabledToggle

	group:AddChild(topRow)

	-- Glow Opacity slider
	local opacitySlider = AceGUI:Create("Slider")
	opacitySlider:SetLabel("Glow Opacity")
	opacitySlider:SetSliderValues(0, 1, 0.01)
	opacitySlider:SetIsPercent(true)
	opacitySlider:SetFullWidth(true)
	opacitySlider:SetValue(DB.glowColor and DB.glowColor.a or 1.0)
	opacitySlider:SetCallback("OnValueChanged", function(_, _, val)
		DB.glowColor = DB.glowColor or {}
		DB.glowColor.a = val
		UpdateAllGlowOpacity()
	end)
	group:AddChild(opacitySlider)
	RTG_OpacitySlider = opacitySlider

	-- Glow Texture dropdown
	local textureDropdown = AceGUI:Create("Dropdown")
	textureDropdown:SetLabel("Glow Texture")
	textureDropdown:SetFullWidth(true)

	local dropdownList = {}
	local dropdownOrder = {}
	for _, opt in ipairs(RTG_TEXTURES) do
		dropdownList[opt.value] = opt.name
		dropdownOrder[#dropdownOrder + 1] = opt.value
	end
	textureDropdown:SetList(dropdownList, dropdownOrder)
	textureDropdown:SetValue(DB.glowTexture or "atlas:talents-node-square-greenglow")
	textureDropdown:SetCallback("OnValueChanged", function(_, _, key)
		DB.glowTexture = key
		UpdateAllGlowStyles()
		RequestUpdate()
	end)
	group:AddChild(textureDropdown)
	RTG_TextureDropdown = textureDropdown
end

RefreshConfigValues = function()
	if RTG_ColorPicker then
		local c = DB.glowColor or {}
		RTG_ColorPicker:SetColor(c.r or 0.2, c.g or 1.0, c.b or 0.2)
	end
	if RTG_OpacitySlider then
		RTG_OpacitySlider:SetValue(DB.glowColor and DB.glowColor.a or 1.0)
	end
	if RTG_TextureDropdown then
		RTG_TextureDropdown:SetValue(DB.glowTexture or "atlas:talents-node-square-greenglow")
	end
	if RTG_EnabledToggle then
		RTG_EnabledToggle:SetValue(DB.enabled == true)
	end
end

CreateToggleButton = function(root)
	if RTG_ToggleButton then return end

	local btn = CreateFrame("Button", nil, root)
	btn:SetSize(22, 22)
	btn:SetFrameStrata("HIGH")
	btn:SetFrameLevel((root.GetFrameLevel and root:GetFrameLevel() or 0) + 200)

	-- Anchor to the outer PlayerSpellsFrame (title bar area) if available,
	-- but keep parented to TalentsFrame so the button hides with the tab.
	local anchor = (_G.PlayerSpellsFrame and root ~= _G.PlayerSpellsFrame)
		and _G.PlayerSpellsFrame or root
	btn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -30, -4)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER", btn, "CENTER", 0, 3)
	icon:SetSize(22, 22)
	icon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")

	local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetPoint("CENTER", btn, "CENTER", 0, 3)
	highlight:SetSize(22, 22)
	highlight:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
	highlight:SetBlendMode("ADD")

	btn:SetScript("OnClick", function()
		ToggleConfigPanel()
	end)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText("Refundable Talents Glow Settings")
		GameTooltip:Show()
	end)

	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	RTG_ToggleButton = btn
end

CreateConfigPanel = function(root)
	if RTG_ConfigPanel then return end

	-- AceGUI Window container (skinnable by UI addons)
	local window = AceGUI:Create("Window")
	window:SetTitle("RTG Settings")
	window:SetWidth(240)
	window:SetHeight(160)
	window:SetLayout("List")
	window:EnableResize(false)

	-- Reparent to talent frame root for auto-hide behavior
	local frame = window.frame
	frame:SetParent(root)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", root, "TOPRIGHT", 2, 0)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)

	-- Fix close button position after reparenting
	if window.closebutton then
		window.closebutton:ClearAllPoints()
		window.closebutton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	end

	-- Override close button to hide instead of releasing the widget
	window:SetCallback("OnClose", function(widget)
		widget.frame:Hide()
	end)

	-- Populate widgets directly into the window
	PopulateConfigWidgets(window)

	RTG_ConfigPanel = frame
	RTG_ConfigGroup = window

	frame:Hide()
end

ToggleConfigPanel = function()
	-- Find the visible talent frame root
	local root = nil
	for _, r in ipairs(GetTalentRoots()) do
		if r and r.IsShown and r:IsShown() then
			root = r
			break
		end
	end

	if not root then
		print("|cff33ff99RTG|r Open your talent tree first.")
		return
	end

	-- Lazy-create toggle button and panel
	CreateToggleButton(root)
	CreateConfigPanel(root)

	if RTG_ConfigPanel:IsShown() then
		RTG_ConfigPanel:Hide()
	else
		RefreshConfigValues()
		RTG_ConfigPanel:Show()
	end
end


-- Slash commands
SLASH_REFUNDABLETALENTSGLOW1 = "/rtg"
SlashCmdList["REFUNDABLETALENTSGLOW"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "on" then
		DB.enabled = true
		print("|cff33ff99RTG|r enabled")
		StartBurstRefresh()
	elseif msg == "off" then
		DB.enabled = false
		print("|cff33ff99RTG|r disabled")
		RequestUpdate()
	elseif msg == "debug" then
		DB.debug = not DB.debug
		print("|cff33ff99RTG|r debug:", DB.debug and "on" or "off")
	elseif msg == "config" or msg == "cfg" then
		ToggleConfigPanel()
	else
		print("|cff33ff99RTG|r commands: /rtg on | off | config | debug")
	end
end
