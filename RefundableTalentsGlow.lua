local ADDON_NAME = ...
RefundableTalentsGlowDB = RefundableTalentsGlowDB or {}

local DB = RefundableTalentsGlowDB
local AceGUI = LibStub("AceGUI-3.0")
if DB.enabled == nil then DB.enabled = true end

-- Defaults
if type(DB.glowTexture) ~= "string" or DB.glowTexture == "" then
	DB.glowTexture = "Interface\\Buttons\\UI-ActionButton-Border"
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
	local setting = DB.glowTexture or "Interface\\Buttons\\UI-ActionButton-Border"

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
	tex:SetVertexColor(tonumber(c.r) or 0.2, tonumber(c.g) or 1.0, tonumber(c.b) or 0.2, tonumber(c.a) or 1.0)
end

local function EnsureGlow(button)
	if button.__RTGGlow then
		ApplyGlowStyle(button.__RTGGlow)
		return button.__RTGGlow
	end

	-- Subtle border glow (green) + pulse animation
	local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
	ApplyGlowStyle(glow)
	glow:Hide()

	local function SizeGlow()
		local w = (button.GetWidth and button:GetWidth()) or 36
		local h = (button.GetHeight and button:GetHeight()) or 36
		glow:SetSize(w * 1.85, h * 1.85)
		glow:SetPoint("CENTER", button, "CENTER", 0, 0)
	end
	SizeGlow()

	if button.HookScript then
		button:HookScript("OnSizeChanged", SizeGlow)
	end

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
	button.__RTGGlowAG = ag
	return glow
end

local function SetGlowing(button, shouldGlow)
	local glow = EnsureGlow(button)
	local ag = button.__RTGGlowAG
	if shouldGlow then
		glow:Show()
		if ag and not ag:IsPlaying() then ag:Play() end
	else
		if ag and ag:IsPlaying() then ag:Stop() end
		glow:Hide()
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

	-- Common roots for the talent UI (varies by build)
	if _G.ClassTalentFrame then
		table.insert(roots, _G.ClassTalentFrame)
	end
	if _G.PlayerSpellsFrame then
		table.insert(roots, _G.PlayerSpellsFrame)
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

local function HookRoot(root)
	if not root or root.__RTGHooked or not root.HookScript then return end
	root.__RTGHooked = true

	root:HookScript("OnShow", function()
		StartBurstRefresh()
		CreateToggleButton(root)
	end)

	root:HookScript("OnHide", function()
		StopBurstRefresh()
		-- Hide the config panel when the talent frame closes
		if RTG_ConfigPanel then
			RTG_ConfigPanel:Hide()
		end
	end)
end

local function HookAllRoots()
	for _, root in ipairs(GetTalentRoots()) do
		HookRoot(root)
	end
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

		-- Stop once we hooked something, or after 20 tries (~10s)
		local hookedAny = false
		for _, root in ipairs(GetTalentRoots()) do
			if root and root.__RTGHooked then
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
	{ name = "Action Button Border (default)", value = "Interface\\Buttons\\UI-ActionButton-Border", blend = "ADD" },
	{ name = "Quickslot Border", value = "Interface\\Buttons\\UI-Quickslot2", blend = "ADD" },
	{ name = "Button Outline", value = "Interface\\Buttons\\UI-Button-Outline", blend = "ADD" },

	-- Atlases (fixes sprite-sheet issues like "many boxes")
	{ name = "Icon Alert Ants", value = "atlas:IconAlertAnts", blend = "ADD", fallback = "Interface\\SpellActivationOverlay\\IconAlertAnts" },
	{ name = "Azerite Power Ring", value = "atlas:AzeritePowerRing", blend = "ADD", fallback = "Interface\\Azerite\\AzeritePowerRing" },
}

local RTG_ConfigPanel   -- raw WoW frame (outer shell, parented to talent frame)
local RTG_ConfigGroup   -- AceGUI SimpleGroup (embedded inside shell)
local RTG_ToggleButton  -- gear icon button on talent frame

-- Widget references for RefreshConfigValues
local RTG_ColorPicker, RTG_OpacitySlider, RTG_TextureDropdown

PopulateConfigWidgets = function(group)
	-- Glow Color picker (RGB only, no alpha)
	local colorPicker = AceGUI:Create("ColorPicker")
	colorPicker:SetLabel("Glow Color")
	colorPicker:SetHasAlpha(false)
	colorPicker:SetFullWidth(true)
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
	group:AddChild(colorPicker)
	RTG_ColorPicker = colorPicker

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
		UpdateAllGlowStyles()
		RequestUpdate()
	end)
	group:AddChild(opacitySlider)
	RTG_OpacitySlider = opacitySlider

	-- Glow Texture dropdown
	local textureDropdown = AceGUI:Create("Dropdown")
	textureDropdown:SetLabel("Glow Texture")
	textureDropdown:SetFullWidth(true)

	local dropdownList = {}
	for _, opt in ipairs(RTG_TEXTURES) do
		dropdownList[opt.value] = opt.name
	end
	textureDropdown:SetList(dropdownList)
	textureDropdown:SetValue(DB.glowTexture or "Interface\\Buttons\\UI-ActionButton-Border")
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
		RTG_TextureDropdown:SetValue(DB.glowTexture or "Interface\\Buttons\\UI-ActionButton-Border")
	end
end

CreateToggleButton = function(root)
	if RTG_ToggleButton then return end

	local btn = CreateFrame("Button", nil, root)
	btn:SetSize(22, 22)
	btn:SetFrameStrata("HIGH")
	btn:SetFrameLevel((root.GetFrameLevel and root:GetFrameLevel() or 0) + 200)

	btn:SetPoint("TOPRIGHT", root, "TOPRIGHT", -30, -4)

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

	-- Outer shell: raw WoW frame parented to talent frame root
	local shell = CreateFrame("Frame", "RTG_ConfigPanel", root, "BackdropTemplate")
	shell:SetSize(240, 300)
	shell:SetPoint("TOPLEFT", root, "TOPRIGHT", 2, 0)
	shell:SetFrameStrata("HIGH")
	shell:SetClampedToScreen(true)
	shell:EnableMouse(true)

	shell:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	shell:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
	shell:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

	-- Title
	local title = shell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", shell, "TOP", 0, -10)
	title:SetText("RTG Settings")

	-- Inner AceGUI container
	local group = AceGUI:Create("SimpleGroup")
	group:SetLayout("List")

	-- Reparent AceGUI container frame into the shell
	local groupFrame = group.frame
	groupFrame:SetParent(shell)
	groupFrame:ClearAllPoints()
	groupFrame:SetPoint("TOPLEFT", shell, "TOPLEFT", 15, -35)
	groupFrame:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -15, 15)
	groupFrame:SetFrameStrata("HIGH")
	groupFrame:Show()

	-- Populate widgets
	PopulateConfigWidgets(group)

	RTG_ConfigPanel = shell
	RTG_ConfigGroup = group

	shell:Hide()
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
