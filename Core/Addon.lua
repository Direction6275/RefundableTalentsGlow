local ADDON_NAME, NS = ...

local AceAddon = LibStub("AceAddon-3.0")
local CooldownTimeline = AceAddon:NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")

NS.Addon = CooldownTimeline
NS.ADDON_NAME = ADDON_NAME

local EnumEncounterTimelineViewType = Enum and Enum.EncounterTimelineViewType
local EnumEncounterEventSeverity = Enum and Enum.EncounterEventSeverity

NS.Constants = {
    SchemaVersion = 1,
    DriftThresholdSec = 0.35,
    GCDThresholdSec = 2.0,
    MinDurationSec = 0.05,
    DefaultIconFileID = 134400,
    TestEventKey = -9001,
    SeverityLow = EnumEncounterEventSeverity and EnumEncounterEventSeverity.Low or 0,
    SeverityMedium = EnumEncounterEventSeverity and EnumEncounterEventSeverity.Medium or 1,
    SeverityHigh = EnumEncounterEventSeverity and EnumEncounterEventSeverity.High or 2,
    ViewTypeTimeline = EnumEncounterTimelineViewType and EnumEncounterTimelineViewType.Timeline or 1,
}

local function Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s*(.-)%s*$", "%1"))
end

function NS.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

function NS.IsReadableNumber(value)
    return type(value) == "number" and not NS.IsSecretValue(value)
end

function NS.ParseSpellIdentifier(token)
    token = Trim(token)
    if token == "" then
        return nil
    end

    local directID = tonumber(token)
    if directID then
        return directID
    end

    local linkID = token:match("spell:(%d+)")
    if linkID then
        return tonumber(linkID)
    end

    return nil
end

function NS.Clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

function NS.Trim(value)
    return Trim(value)
end

function CooldownTimeline:BuildDefaultSpellConfig()
    return {
        enabled = true,
        customLabel = "",
        cooldownOverrideSec = nil,
        severity = NS.Constants.SeverityMedium,
        lastKnownDurationSec = nil,
    }
end

function CooldownTimeline:GetViewTypeTimeline()
    return NS.Constants.ViewTypeTimeline
end

function CooldownTimeline:InitializeRuntimeState()
    self.runtime = {
        timelineViewActive = false,
        encounterInProgress = false,
        configPreviewActive = false,
        configPreviewLoopTimer = nil,
        configPreviewPreviousViewType = nil,
        activeByBaseSpellID = {},
        eventMetaByEventID = {},
    }
end

function CooldownTimeline:OnInitialize()
    self:InitializeRuntimeState()
    self:InitializeDB()
    self:InitializeSpecState()
    self:InitializeOverlayRenderer()
    self:InitializeSettingsPanel()
    self:InitializeSlashCommands()
end

function CooldownTimeline:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecializationChanged")
    self:RegisterEvent("ENCOUNTER_STATE_CHANGED", "OnEncounterStateChanged")
    self:RegisterEvent("ENCOUNTER_TIMELINE_VIEW_ACTIVATED", "OnEncounterTimelineViewActivated")
    self:RegisterEvent("ENCOUNTER_TIMELINE_VIEW_DEACTIVATED", "OnEncounterTimelineViewDeactivated")
    self:RegisterEvent("ENCOUNTER_TIMELINE_STATE_UPDATED", "OnEncounterTimelineStateUpdated")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnSpellUpdateCharges")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellcastSucceeded")

    self:RefreshCurrentSpecID()
    self:RefreshTimelineRuntimeState()
    self:RefreshSettingsPanel()
    self:UpdateConfigPreviewState("addon_enabled")
    self:StartOverlayRenderer()
end

function CooldownTimeline:OnDisable()
    self:StopOverlayRenderer()
    self:StopConfigPreview("addon_disabled")
    self:CancelAllOwnedEvents("addon_disabled")
end
