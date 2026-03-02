local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local Constants = NS.Constants

local DEFAULTS = {
    profile = {
        schemaVersion = Constants.SchemaVersion,
        readyLingerSeconds = 0,
        previewTimelineInConfig = false,
        specs = {},
    },
}

local function EnsureType(value, expectedType, fallback)
    if type(value) ~= expectedType then
        return fallback
    end
    return value
end

local function NormalizeSeverity(rawValue)
    if rawValue == Constants.SeverityLow or rawValue == Constants.SeverityMedium or rawValue == Constants.SeverityHigh then
        return rawValue
    end
    return Constants.SeverityMedium
end

function CooldownTimeline:InitializeDB()
    self.db = LibStub("AceDB-3.0"):New("CooldownTimelineDB", DEFAULTS, true)
    self:MigrateDBIfNeeded()
end

function CooldownTimeline:MigrateDBIfNeeded()
    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    profile.schemaVersion = EnsureType(profile.schemaVersion, "number", 0)
    profile.readyLingerSeconds = EnsureType(profile.readyLingerSeconds, "number", 0)
    profile.readyLingerSeconds = NS.Clamp(profile.readyLingerSeconds, 0, 5)
    profile.previewTimelineInConfig = (profile.previewTimelineInConfig == true)
    profile.specs = EnsureType(profile.specs, "table", {})

    for _, specData in pairs(profile.specs) do
        specData.spells = EnsureType(specData.spells, "table", {})
        for spellID, spellConfig in pairs(specData.spells) do
            local numericSpellID = tonumber(spellID)
            if not numericSpellID or numericSpellID <= 0 then
                specData.spells[spellID] = nil
            else
                spellConfig.enabled = (spellConfig.enabled ~= false)
                spellConfig.customLabel = EnsureType(spellConfig.customLabel, "string", "")
                spellConfig.cooldownOverrideSec = EnsureType(spellConfig.cooldownOverrideSec, "number", nil)
                spellConfig.severity = NormalizeSeverity(spellConfig.severity)
                spellConfig.lastKnownDurationSec = EnsureType(spellConfig.lastKnownDurationSec, "number", nil)
            end
        end
    end

    profile.schemaVersion = Constants.SchemaVersion
end

function CooldownTimeline:GetReadyLingerSeconds()
    return self.db.profile.readyLingerSeconds or 0
end

function CooldownTimeline:SetReadyLingerSeconds(value)
    local numberValue = tonumber(value)
    if not numberValue then
        return
    end

    self.db.profile.readyLingerSeconds = NS.Clamp(numberValue, 0, 5)
end

function CooldownTimeline:IsTimelinePreviewInConfigEnabled()
    return self.db.profile.previewTimelineInConfig == true
end

function CooldownTimeline:SetTimelinePreviewInConfigEnabled(enabled)
    self.db.profile.previewTimelineInConfig = (enabled == true)
    self:UpdateConfigPreviewState("settings_toggle")
end

function CooldownTimeline:GetSpecTable(specID)
    if not specID then
        return nil
    end

    local specs = self.db.profile.specs
    local specTable = specs[specID]
    if not specTable then
        specTable = { spells = {} }
        specs[specID] = specTable
    end

    specTable.spells = specTable.spells or {}
    return specTable
end

function CooldownTimeline:GetCurrentSpecTable()
    return self:GetSpecTable(self:GetCurrentSpecID())
end

function CooldownTimeline:GetTrackedSpellConfig(baseSpellID, specID)
    if not baseSpellID then
        return nil
    end

    local tableForSpec = self:GetSpecTable(specID or self:GetCurrentSpecID())
    if not tableForSpec then
        return nil
    end

    return tableForSpec.spells[baseSpellID]
end

function CooldownTimeline:SetTrackedSpellConfig(baseSpellID, config, specID)
    if not baseSpellID or type(config) ~= "table" then
        return
    end

    local tableForSpec = self:GetSpecTable(specID or self:GetCurrentSpecID())
    if not tableForSpec then
        return
    end

    local existing = tableForSpec.spells[baseSpellID] or self:BuildDefaultSpellConfig()
    existing.enabled = (config.enabled ~= false)
    existing.customLabel = NS.Trim(config.customLabel or "")
    existing.cooldownOverrideSec = tonumber(config.cooldownOverrideSec)
    existing.severity = NormalizeSeverity(config.severity)
    existing.lastKnownDurationSec = tonumber(config.lastKnownDurationSec)
    tableForSpec.spells[baseSpellID] = existing
end

function CooldownTimeline:EnsureTrackedSpell(baseSpellID, specID)
    local tableForSpec = self:GetSpecTable(specID or self:GetCurrentSpecID())
    if not tableForSpec then
        return nil
    end

    local config = tableForSpec.spells[baseSpellID]
    if not config then
        config = self:BuildDefaultSpellConfig()
        tableForSpec.spells[baseSpellID] = config
    end

    return config
end

function CooldownTimeline:RemoveTrackedSpell(baseSpellID, specID)
    local tableForSpec = self:GetSpecTable(specID or self:GetCurrentSpecID())
    if not tableForSpec then
        return false
    end

    if tableForSpec.spells[baseSpellID] then
        tableForSpec.spells[baseSpellID] = nil
        return true
    end

    return false
end

function CooldownTimeline:IterateTrackedSpells(specID)
    local tableForSpec = self:GetSpecTable(specID or self:GetCurrentSpecID())
    if not tableForSpec then
        return function() return nil end
    end
    return pairs(tableForSpec.spells)
end
