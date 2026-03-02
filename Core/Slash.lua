local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local Constants = NS.Constants

local SeverityLabelToValue = {
    low = Constants.SeverityLow,
    medium = Constants.SeverityMedium,
    high = Constants.SeverityHigh,
}

local SeverityValueToLabel = {
    [Constants.SeverityLow] = "Low",
    [Constants.SeverityMedium] = "Medium",
    [Constants.SeverityHigh] = "High",
}

local function SplitCommand(input)
    input = input or ""
    local command, remainder = input:match("^%s*(%S+)%s*(.-)%s*$")
    return command and command:lower() or "", remainder or ""
end

local function ParseOptionalNumber(value)
    if not value or value == "" then
        return nil
    end
    return tonumber(value)
end

function CooldownTimeline:InitializeSlashCommands()
    self:RegisterChatCommand("cdtl", "HandleSlashCommand")
end

function CooldownTimeline:HandleSlashCommand(input)
    local command, remainder = SplitCommand(input)

    if command == "" or command == "config" or command == "open" then
        self:OpenSettingsPanel()
        return
    end

    if command == "add" then
        self:CommandAddSpell(remainder)
        return
    end

    if command == "remove" or command == "rm" or command == "del" then
        self:CommandRemoveSpell(remainder)
        return
    end

    if command == "list" then
        self:CommandListSpells()
        return
    end

    if command == "test" then
        self:AddTestTimelineEvent(ParseOptionalNumber(remainder))
        return
    end

    self:Print("CooldownTimeline commands: /cdtl config, /cdtl add <spellID|link>, /cdtl remove <spellID>, /cdtl list, /cdtl test [seconds]")
end

function CooldownTimeline:CommandAddSpell(inputToken)
    local currentSpecID = self:GetCurrentSpecID()
    if not currentSpecID then
        self:Print("CooldownTimeline: no active specialization detected.")
        return
    end

    local rawSpellID = NS.ParseSpellIdentifier(inputToken)
    if not rawSpellID then
        self:Print("CooldownTimeline: provide a spell ID or spell link.")
        return
    end

    if not C_Spell.DoesSpellExist(rawSpellID) then
        self:Print(("CooldownTimeline: spell %d does not exist."):format(rawSpellID))
        return
    end

    local baseSpellID = self:GetResolvedBaseSpellID(rawSpellID)
    local config = self:EnsureTrackedSpell(baseSpellID, currentSpecID)
    if not config then
        self:Print("CooldownTimeline: could not add tracked spell.")
        return
    end

    local spellName = C_Spell.GetSpellName(baseSpellID) or ("Spell " .. baseSpellID)
    self:Print(("CooldownTimeline: tracking %s (%d) for spec %d."):format(spellName, baseSpellID, currentSpecID))
    self:RefreshSettingsPanel()
end

function CooldownTimeline:CommandRemoveSpell(inputToken)
    local currentSpecID = self:GetCurrentSpecID()
    if not currentSpecID then
        self:Print("CooldownTimeline: no active specialization detected.")
        return
    end

    local rawSpellID = NS.ParseSpellIdentifier(inputToken)
    if not rawSpellID then
        self:Print("CooldownTimeline: provide a spell ID to remove.")
        return
    end

    local baseSpellID = self:GetResolvedBaseSpellID(rawSpellID)
    local removed = self:RemoveTrackedSpell(baseSpellID, currentSpecID)
    self:CancelOwnedEventForSpell(baseSpellID, "manual_remove")

    if removed then
        self:Print(("CooldownTimeline: removed tracked spell %d from spec %d."):format(baseSpellID, currentSpecID))
    else
        self:Print(("CooldownTimeline: spell %d was not tracked for spec %d."):format(baseSpellID, currentSpecID))
    end

    self:RefreshSettingsPanel()
end

function CooldownTimeline:CommandListSpells()
    local currentSpecID = self:GetCurrentSpecID()
    if not currentSpecID then
        self:Print("CooldownTimeline: no active specialization detected.")
        return
    end

    local spellRows = {}
    for baseSpellID, spellConfig in self:IterateTrackedSpells(currentSpecID) do
        local spellName = C_Spell.GetSpellName(baseSpellID) or ("Spell " .. baseSpellID)
        local enabledText = spellConfig.enabled == false and "off" or "on"
        local overrideText = spellConfig.cooldownOverrideSec and ("override=" .. tostring(spellConfig.cooldownOverrideSec)) or "override=auto"
        local severityText = SeverityValueToLabel[self:NormalizeSeverity(spellConfig.severity)] or "Medium"
        local customText = NS.Trim(spellConfig.customLabel or "")
        if customText ~= "" then
            customText = (" label=%q"):format(customText)
        end

        spellRows[#spellRows + 1] = {
            sort = baseSpellID,
            text = (" - %s (%d) [%s, %s, severity=%s%s]"):format(
                spellName,
                baseSpellID,
                enabledText,
                overrideText,
                severityText,
                customText
            ),
        }
    end

    table.sort(spellRows, function(a, b)
        return a.sort < b.sort
    end)

    if #spellRows == 0 then
        self:Print(("CooldownTimeline: no tracked spells for spec %d."):format(currentSpecID))
        return
    end

    self:Print(("CooldownTimeline: tracked spells for spec %d:"):format(currentSpecID))
    for _, row in ipairs(spellRows) do
        self:Print(row.text)
    end
end

function CooldownTimeline:SetTrackedSpellSeverity(baseSpellID, severityValue)
    local spellConfig = self:GetTrackedSpellConfig(baseSpellID)
    if not spellConfig then
        return
    end
    spellConfig.severity = self:NormalizeSeverity(severityValue)
end

function CooldownTimeline:CycleTrackedSpellSeverity(baseSpellID)
    local spellConfig = self:GetTrackedSpellConfig(baseSpellID)
    if not spellConfig then
        return
    end

    local currentSeverity = self:NormalizeSeverity(spellConfig.severity)
    local nextSeverity = Constants.SeverityMedium
    if currentSeverity == Constants.SeverityLow then
        nextSeverity = Constants.SeverityMedium
    elseif currentSeverity == Constants.SeverityMedium then
        nextSeverity = Constants.SeverityHigh
    else
        nextSeverity = Constants.SeverityLow
    end

    spellConfig.severity = nextSeverity
end

function CooldownTimeline:GetTrackedSpellSeverityLabel(baseSpellID)
    local spellConfig = self:GetTrackedSpellConfig(baseSpellID)
    if not spellConfig then
        return "Medium"
    end
    return SeverityValueToLabel[self:NormalizeSeverity(spellConfig.severity)] or "Medium"
end
