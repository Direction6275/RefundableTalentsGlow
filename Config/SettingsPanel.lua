local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local Constants = NS.Constants

local max = math.max
local floor = math.floor
local C_EncounterTimeline = C_EncounterTimeline
local C_InstanceEncounter = C_InstanceEncounter

local function GetSpecDisplayName()
    local specName = nil
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex and specIndex > 0 then
            local specID, name = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            if type(name) == "string" and name ~= "" then
                specName = name
            elseif type(specID) == "number" and specID > 0 then
                specName = tostring(specID)
            end
        end
    end

    return specName or "Unknown"
end

local function RoundHalf(value)
    return floor((value * 2) + 0.5) / 2
end

function CooldownTimeline:BuildSettingsPanel()
    local panel = self.settingsPanel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("CooldownTimeline")
    panel.titleText = title

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Overlay personal cooldowns onto Blizzard's encounter timeline.")
    panel.subtitleText = subtitle

    local specLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    specLabel:SetText("Current Spec: Unknown")
    panel.specLabel = specLabel

    local sliderName = ADDON_NAME .. "ReadyLingerSlider"
    local lingerSlider = CreateFrame("Slider", sliderName, panel, "OptionsSliderTemplate")
    lingerSlider:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 6, -28)
    lingerSlider:SetWidth(220)
    lingerSlider:SetMinMaxValues(0, 5)
    lingerSlider:SetValueStep(0.5)
    lingerSlider:SetObeyStepOnDrag(true)
    panel.lingerSlider = lingerSlider

    local sliderLabel = _G[sliderName .. "Text"]
    if sliderLabel then
        sliderLabel:SetText("Ready Linger (seconds)")
    end
    local sliderLow = _G[sliderName .. "Low"]
    if sliderLow then
        sliderLow:SetText("0")
    end
    local sliderHigh = _G[sliderName .. "High"]
    if sliderHigh then
        sliderHigh:SetText("5")
    end

    local lingerValueText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lingerValueText:SetPoint("LEFT", lingerSlider, "RIGHT", 12, 0)
    lingerValueText:SetText("0.0s")
    panel.lingerValueText = lingerValueText

    lingerSlider:SetScript("OnValueChanged", function(_, value)
        if panel.ignoreLingerSlider then
            return
        end

        local snapped = RoundHalf(value)
        if snapped ~= value then
            panel.ignoreLingerSlider = true
            lingerSlider:SetValue(snapped)
            panel.ignoreLingerSlider = false
            value = snapped
        end

        CooldownTimeline:SetReadyLingerSeconds(value)
        panel.lingerValueText:SetText(("%.1fs"):format(CooldownTimeline:GetReadyLingerSeconds()))
    end)

    local previewToggle = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    previewToggle:SetPoint("TOPLEFT", lingerSlider, "BOTTOMLEFT", -6, -6)
    panel.previewToggle = previewToggle

    local previewToggleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    previewToggleLabel:SetPoint("LEFT", previewToggle, "RIGHT", 4, 1)
    previewToggleLabel:SetText("Preview Timeline During Config")
    panel.previewToggleLabel = previewToggleLabel

    local previewStatusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    previewStatusText:SetPoint("TOPLEFT", previewToggleLabel, "BOTTOMLEFT", 0, -2)
    previewStatusText:SetText("")
    panel.previewStatusText = previewStatusText

    previewToggle:SetScript("OnClick", function(self)
        CooldownTimeline:SetTimelinePreviewInConfigEnabled(self:GetChecked() == true)
        CooldownTimeline:RefreshSettingsPanel()
    end)

    local addLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", previewStatusText, "BOTTOMLEFT", 0, -14)
    addLabel:SetText("Add Spell (ID or link):")
    panel.addLabel = addLabel

    local addInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addInput:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    addInput:SetSize(170, 24)
    addInput:SetAutoFocus(false)
    addInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    panel.addInput = addInput

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addButton:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
    addButton:SetSize(70, 24)
    addButton:SetText("Add")
    panel.addButton = addButton

    local function DoAddSpell()
        local text = addInput:GetText() or ""
        CooldownTimeline:CommandAddSpell(text)
        addInput:SetText("")
        addInput:ClearFocus()
    end

    addButton:SetScript("OnClick", DoAddSpell)
    addInput:SetScript("OnEnterPressed", DoAddSpell)

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -14)
    header:SetText("On    Spell                          Custom Label         Override   Severity   Remove")
    panel.headerText = header

    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "SpellScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 16)
    panel.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    panel.scrollContent = content

    panel.rows = {}
end

function CooldownTimeline:AcquireSettingsRow(index)
    local panel = self.settingsPanel
    local row = panel.rows[index]
    if row then
        return row
    end

    local content = panel.scrollContent
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(24)
    row:SetWidth(760)

    local enableCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    enableCheck:SetPoint("LEFT", 0, 0)
    row.enableCheck = enableCheck

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0)
    icon:SetSize(18, 18)
    row.icon = icon

    local spellNameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    spellNameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    spellNameText:SetWidth(170)
    spellNameText:SetJustifyH("LEFT")
    row.spellNameText = spellNameText

    local customLabelBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    customLabelBox:SetPoint("LEFT", spellNameText, "RIGHT", 6, 0)
    customLabelBox:SetSize(140, 20)
    customLabelBox:SetAutoFocus(false)
    row.customLabelBox = customLabelBox

    local overrideBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    overrideBox:SetPoint("LEFT", customLabelBox, "RIGHT", 8, 0)
    overrideBox:SetSize(60, 20)
    overrideBox:SetAutoFocus(false)
    row.overrideBox = overrideBox

    local severityButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    severityButton:SetPoint("LEFT", overrideBox, "RIGHT", 8, 0)
    severityButton:SetSize(65, 20)
    row.severityButton = severityButton

    local removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    removeButton:SetPoint("LEFT", severityButton, "RIGHT", 12, 0)
    removeButton:SetSize(20, 20)
    row.removeButton = removeButton

    enableCheck:SetScript("OnClick", function(self)
        local spellConfig = CooldownTimeline:GetTrackedSpellConfig(row.baseSpellID)
        if not spellConfig then
            return
        end
        spellConfig.enabled = (self:GetChecked() == true)
        if spellConfig.enabled == false then
            CooldownTimeline:CancelOwnedEventForSpell(row.baseSpellID, "disabled_in_settings")
        end
    end)

    local function CommitCustomLabel()
        local spellConfig = CooldownTimeline:GetTrackedSpellConfig(row.baseSpellID)
        if not spellConfig then
            return
        end
        spellConfig.customLabel = NS.Trim(customLabelBox:GetText() or "")
    end

    customLabelBox:SetScript("OnEnterPressed", function(self)
        CommitCustomLabel()
        self:ClearFocus()
    end)
    customLabelBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    customLabelBox:SetScript("OnEditFocusLost", CommitCustomLabel)

    local function CommitOverride()
        local spellConfig = CooldownTimeline:GetTrackedSpellConfig(row.baseSpellID)
        if not spellConfig then
            return
        end

        local rawText = NS.Trim(overrideBox:GetText() or "")
        if rawText == "" then
            spellConfig.cooldownOverrideSec = nil
            return
        end

        local numeric = tonumber(rawText)
        if numeric and numeric > 0 then
            spellConfig.cooldownOverrideSec = numeric
        else
            overrideBox:SetText("")
            spellConfig.cooldownOverrideSec = nil
        end
    end

    overrideBox:SetScript("OnEnterPressed", function(self)
        CommitOverride()
        self:ClearFocus()
    end)
    overrideBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    overrideBox:SetScript("OnEditFocusLost", CommitOverride)

    severityButton:SetScript("OnClick", function()
        CooldownTimeline:CycleTrackedSpellSeverity(row.baseSpellID)
        CooldownTimeline:RefreshSettingsPanel()
    end)

    removeButton:SetScript("OnClick", function()
        CooldownTimeline:RemoveTrackedSpell(row.baseSpellID)
        CooldownTimeline:CancelOwnedEventForSpell(row.baseSpellID, "removed_in_settings")
        CooldownTimeline:RefreshSettingsPanel()
    end)

    panel.rows[index] = row
    return row
end

function CooldownTimeline:RefreshSettingsPanel()
    local panel = self.settingsPanel
    if not panel then
        return
    end

    local currentSpecID = self:GetCurrentSpecID()
    if currentSpecID then
        panel.specLabel:SetText(("Current Spec: %s (%d)"):format(GetSpecDisplayName(), currentSpecID))
    else
        panel.specLabel:SetText("Current Spec: Unknown")
    end

    panel.ignoreLingerSlider = true
    panel.lingerSlider:SetValue(self:GetReadyLingerSeconds())
    panel.ignoreLingerSlider = false
    panel.lingerValueText:SetText(("%.1fs"):format(self:GetReadyLingerSeconds()))

    local previewEnabled = self:IsTimelinePreviewInConfigEnabled()
    panel.previewToggle:SetChecked(previewEnabled)

    local previewStatus = "Preview is off."
    if not C_EncounterTimeline or not C_EncounterTimeline.IsFeatureAvailable or not C_EncounterTimeline.IsFeatureAvailable() then
        previewStatus = "Preview unavailable: encounter timeline feature not available."
    elseif not C_EncounterTimeline.IsFeatureEnabled or not C_EncounterTimeline.IsFeatureEnabled() then
        previewStatus = "Enable Encounter Timeline in game settings to use preview."
    elseif C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress and C_InstanceEncounter.IsEncounterInProgress() then
        previewStatus = "Preview pauses during active encounters."
    elseif EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        previewStatus = "Close Edit Mode to run config preview."
    elseif previewEnabled then
        previewStatus = "Preview active while this config panel is open."
    end
    panel.previewStatusText:SetText(previewStatus)

    local sortedSpellIDs = {}
    if currentSpecID then
        for spellID in self:IterateTrackedSpells(currentSpecID) do
            sortedSpellIDs[#sortedSpellIDs + 1] = spellID
        end
    end

    table.sort(sortedSpellIDs, function(a, b)
        return a < b
    end)

    for index, spellID in ipairs(sortedSpellIDs) do
        local row = self:AcquireSettingsRow(index)
        row.baseSpellID = spellID
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.scrollContent, "TOPLEFT", 0, -((index - 1) * 26))
        row:Show()

        local spellConfig = self:GetTrackedSpellConfig(spellID)
        local spellName = C_Spell.GetSpellName(spellID) or ("Spell " .. tostring(spellID))
        local iconFileID = select(1, C_Spell.GetSpellTexture(spellID)) or Constants.DefaultIconFileID

        row.enableCheck:SetChecked(spellConfig.enabled ~= false)
        row.icon:SetTexture(iconFileID)
        row.spellNameText:SetText(("%s (%d)"):format(spellName, spellID))
        row.customLabelBox:SetText(spellConfig.customLabel or "")
        row.overrideBox:SetText(spellConfig.cooldownOverrideSec and tostring(spellConfig.cooldownOverrideSec) or "")
        row.severityButton:SetText(self:GetTrackedSpellSeverityLabel(spellID))
    end

    for index = #sortedSpellIDs + 1, #panel.rows do
        panel.rows[index]:Hide()
    end

    panel.scrollContent:SetHeight(max(1, #sortedSpellIDs * 26))
    panel.scrollContent:SetWidth(max(1, panel.scrollFrame:GetWidth() - 20))
end

function CooldownTimeline:InitializeSettingsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        self:Print("CooldownTimeline: Settings API is unavailable.")
        return
    end

    local panel = CreateFrame("Frame", ADDON_NAME .. "SettingsPanel", UIParent)
    panel:Hide()

    self.settingsPanel = panel
    self:BuildSettingsPanel()

    panel:SetScript("OnShow", function()
        CooldownTimeline:RefreshSettingsPanel()
        CooldownTimeline:UpdateConfigPreviewState("settings_panel_show")
    end)
    panel:SetScript("OnHide", function()
        CooldownTimeline:UpdateConfigPreviewState("settings_panel_hide")
    end)

    local category, layout = Settings.RegisterCanvasLayoutCategory(panel, "CooldownTimeline")
    Settings.RegisterAddOnCategory(category)

    self.settingsCategory = category
    self.settingsCategoryID = category:GetID()
end

function CooldownTimeline:OpenSettingsPanel()
    if not self.settingsCategoryID then
        self:Print("CooldownTimeline: settings panel not available.")
        return
    end

    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
        C_SettingsUtil.OpenSettingsPanel(self.settingsCategoryID)
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategoryID)
    end
end
