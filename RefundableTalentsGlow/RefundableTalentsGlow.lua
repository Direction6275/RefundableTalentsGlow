local ADDON_NAME = ...
RefundableTalentsGlowDB = RefundableTalentsGlowDB or {}

local DB = RefundableTalentsGlowDB
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

local function HookRoot(root)
	if not root or root.__RTGHooked or not root.HookScript then return end
	root.__RTGHooked = true

	root:HookScript("OnShow", function()
		StartBurstRefresh()
	end)

	root:HookScript("OnHide", function()
		StopBurstRefresh()
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
local RTG_ConfigFrame

RTG_TEXTURES = {
	{ name = "Action Button Border (default)", value = "Interface\\Buttons\\UI-ActionButton-Border", blend = "ADD" },
	{ name = "Quickslot Border", value = "Interface\\Buttons\\UI-Quickslot2", blend = "ADD" },
	{ name = "Button Outline", value = "Interface\\Buttons\\UI-Button-Outline", blend = "ADD" },

	-- Atlases (fixes sprite-sheet issues like "many boxes")
	{ name = "Icon Alert Ants", value = "atlas:IconAlertAnts", blend = "ADD", fallback = "Interface\\SpellActivationOverlay\\IconAlertAnts" },
	{ name = "Azerite Power Ring", value = "atlas:AzeritePowerRing", blend = "ADD", fallback = "Interface\\Azerite\\AzeritePowerRing" },
}

local function TextureNameForPath(path)
	for _, opt in ipairs(RTG_TEXTURES or {}) do
		if opt.value == path then return opt.name end
	end
	return path
end

local function OpenColorPicker()
	local c = DB.glowColor or { r = 0.2, g = 1.0, b = 0.2, a = 1.0 }
	local prevR, prevG, prevB, prevA = c.r or 0.2, c.g or 1.0, c.b or 0.2, c.a or 1.0

	local function Apply(r, g, b, a)
		DB.glowColor = DB.glowColor or {}
		DB.glowColor.r, DB.glowColor.g, DB.glowColor.b, DB.glowColor.a = r, g, b, a

		if RTG_ConfigFrame and RTG_ConfigFrame._swatch and RTG_ConfigFrame._swatch.tex then
			RTG_ConfigFrame._swatch.tex:SetColorTexture(r, g, b, 1)
		end

		UpdateAllGlowStyles()
		RequestUpdate()
	end

	-- Modern picker API (Retail)
	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		local info = {
			r = prevR,
			g = prevG,
			b = prevB,
			opacity = 1 - prevA,
			hasOpacity = true,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				local a = 1
				if OpacitySliderFrame and OpacitySliderFrame.GetValue then
					a = 1 - OpacitySliderFrame:GetValue()
				elseif ColorPickerFrame.opacity then
					a = 1 - ColorPickerFrame.opacity
				end
				Apply(r, g, b, a)
			end,
			opacityFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				local a = 1
				if OpacitySliderFrame and OpacitySliderFrame.GetValue then
					a = 1 - OpacitySliderFrame:GetValue()
				elseif ColorPickerFrame.opacity then
					a = 1 - ColorPickerFrame.opacity
				end
				Apply(r, g, b, a)
			end,
			cancelFunc = function()
				Apply(prevR, prevG, prevB, prevA)
			end,
		}
		ColorPickerFrame:SetupColorPickerAndShow(info)
		return
	end

	-- Legacy picker API fallback
	local function ColorCallback(restore)
		local r, g, b, a
		if restore then
			r, g, b, a = restore[1], restore[2], restore[3], restore[4]
		else
			r, g, b = ColorPickerFrame:GetColorRGB()
			a = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
		end
		Apply(r, g, b, a)
	end

	ColorPickerFrame.func = ColorCallback
	ColorPickerFrame.opacityFunc = ColorCallback
	ColorPickerFrame.cancelFunc = ColorCallback

	ColorPickerFrame.hasOpacity = true
	ColorPickerFrame.opacity = 1 - (prevA or 1)

	ColorPickerFrame:SetColorRGB(prevR, prevG, prevB)
	ColorPickerFrame.previousValues = { prevR, prevG, prevB, prevA }

	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

local function CreateConfigPanel()
	if RTG_ConfigFrame then return end

	local f = CreateFrame("Frame", "RefundableTalentsGlowConfigFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(380, 250)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	f.TitleText:SetText("Refundable Talents Glow")

	-- Enabled checkbox
	local enabled = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	enabled:SetPoint("TOPLEFT", 16, -40)
	enabled.text:SetText("Enable glow")
	enabled:SetChecked(DB.enabled == true)
	enabled:SetScript("OnClick", function(self)
		DB.enabled = self:GetChecked() == true
		RequestUpdate()
	end)

	-- Texture dropdown
	local texLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	texLabel:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -16)
	texLabel:SetText("Glow texture")

	local dd = CreateFrame("Frame", "RefundableTalentsGlowTextureDropdown", f, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", texLabel, "BOTTOMLEFT", -16, -6)

	local function SetTexture(path)
		DB.glowTexture = path
		UIDropDownMenu_SetSelectedValue(dd, path)
		UIDropDownMenu_SetText(dd, TextureNameForPath(path))
		UpdateAllGlowStyles()
		RequestUpdate()
	end

	UIDropDownMenu_Initialize(dd, function()
		for _, opt in ipairs(RTG_TEXTURES or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.name
			info.value = opt.value
			info.func = function() SetTexture(opt.value) end
			UIDropDownMenu_AddButton(info)
		end
	end)

	UIDropDownMenu_SetWidth(dd, 250)
	UIDropDownMenu_SetSelectedValue(dd, DB.glowTexture)
	UIDropDownMenu_SetText(dd, TextureNameForPath(DB.glowTexture))

	-- Color picker
	local colorLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	colorLabel:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 16, -18)
	colorLabel:SetText("Glow color")

	local colorBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	colorBtn:SetSize(130, 22)
	colorBtn:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -6)
	colorBtn:SetText("Choose color...")
	colorBtn:SetScript("OnClick", OpenColorPicker)

	local swatch = CreateFrame("Frame", nil, f, "BackdropTemplate")
	swatch:SetSize(18, 18)
	swatch:SetPoint("LEFT", colorBtn, "RIGHT", 10, 0)
	swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
	swatch.tex:SetAllPoints()

	do
		local c = DB.glowColor or {}
		swatch.tex:SetColorTexture(c.r or 0.2, c.g or 1.0, c.b or 0.2, 1)
	end

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 16, 14)
	hint:SetJustifyH("LEFT")
	hint:SetText("Use /rtg on | off | config\nChanges apply immediately while the talent UI is open.")

	f._swatch = swatch
	RTG_ConfigFrame = f
end

local function ToggleConfigPanel()
	CreateConfigPanel()
	if RTG_ConfigFrame:IsShown() then
		RTG_ConfigFrame:Hide()
	else
		-- Make sure we're above the talent UI
		local top = _G.ClassTalentFrame or _G.PlayerSpellsFrame
		if top and top.GetFrameLevel and RTG_ConfigFrame.SetFrameLevel then
			RTG_ConfigFrame:SetFrameLevel((top:GetFrameLevel() or 0) + 50)
		end
		RTG_ConfigFrame:Show()
		if RTG_ConfigFrame.Raise then RTG_ConfigFrame:Raise() end
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
	elseif msg == "config" then
		ToggleConfigPanel()
	elseif msg == "cfg" then
		ToggleConfigPanel()
	else
		print("|cff33ff99RTG|r commands: /rtg on | off | config | debug")
	end
end
