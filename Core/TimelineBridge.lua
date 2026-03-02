local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local C_EncounterTimeline = C_EncounterTimeline
local C_InstanceEncounter = C_InstanceEncounter
local C_Timer = C_Timer
local C_AddOns = C_AddOns

local function ClearTable(tableRef)
    for key in pairs(tableRef) do
        tableRef[key] = nil
    end
end

local function IsEditModeShown()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

local function EnsureEncounterTimelineUILoaded()
    if not C_AddOns or not C_AddOns.IsAddOnLoaded or not C_AddOns.LoadAddOn then
        return true
    end

    local _, isLoaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterTimeline")
    if isLoaded then
        return true
    end

    C_AddOns.LoadAddOn("Blizzard_EncounterTimeline")
    _, isLoaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterTimeline")
    return isLoaded == true
end

function CooldownTimeline:RefreshTimelineRuntimeState()
    if not self.runtime then
        return
    end

    if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
        self.runtime.encounterInProgress = C_InstanceEncounter.IsEncounterInProgress()
    else
        self.runtime.encounterInProgress = false
    end

    if C_EncounterTimeline and C_EncounterTimeline.GetViewType then
        local isTimelineView = (C_EncounterTimeline.GetViewType() == self:GetViewTypeTimeline())
        self.runtime.timelineViewActive = isTimelineView
    else
        self.runtime.timelineViewActive = false
    end
end

function CooldownTimeline:ShouldRunConfigPreview()
    if not self.runtime then
        return false
    end

    if not self:IsTimelinePreviewInConfigEnabled() then
        return false
    end

    if not self.settingsPanel or not self.settingsPanel:IsShown() then
        return false
    end

    if IsEditModeShown() then
        return false
    end

    if not C_EncounterTimeline or not C_InstanceEncounter then
        return false
    end

    if not C_EncounterTimeline.IsFeatureAvailable or not C_EncounterTimeline.IsFeatureAvailable() then
        return false
    end

    if not C_EncounterTimeline.IsFeatureEnabled or not C_EncounterTimeline.IsFeatureEnabled() then
        return false
    end

    if C_InstanceEncounter.IsEncounterInProgress and C_InstanceEncounter.IsEncounterInProgress() then
        return false
    end

    return true
end

function CooldownTimeline:StartConfigPreview(reason)
    if not self:ShouldRunConfigPreview() then
        return
    end

    if not EnsureEncounterTimelineUILoaded() then
        return
    end

    if self.runtime.configPreviewActive then
        return
    end

    local desiredViewType = self:GetViewTypeTimeline()
    local currentViewType = nil
    if C_EncounterTimeline.GetViewType then
        currentViewType = C_EncounterTimeline.GetViewType()
        self.runtime.configPreviewPreviousViewType = currentViewType
    end

    if C_EncounterTimeline.SetViewType then
        if currentViewType == desiredViewType and Enum and Enum.EncounterTimelineViewType and Enum.EncounterTimelineViewType.None ~= nil then
            C_EncounterTimeline.SetViewType(Enum.EncounterTimelineViewType.None)
        end
        C_EncounterTimeline.SetViewType(desiredViewType)
    end

    if C_EncounterTimeline.CancelEditModeEvents and not IsEditModeShown() then
        C_EncounterTimeline.CancelEditModeEvents()
    end

    if EncounterTimeline and EncounterTimeline.SetExplicitlyShown then
        EncounterTimeline:SetExplicitlyShown(true)
    end

    self.runtime.configPreviewActive = true
    self.runtime.timelineViewActive = true

    local function QueueEditModeEvents()
        if not self.runtime or not self.runtime.configPreviewActive then
            return
        end

        local loopTimerDuration = C_EncounterTimeline.AddEditModeEvents and C_EncounterTimeline.AddEditModeEvents()
        if NS.IsReadableNumber(loopTimerDuration) and loopTimerDuration > 0 then
            self.runtime.configPreviewLoopTimer = C_Timer.NewTimer(loopTimerDuration, QueueEditModeEvents)
        else
            self.runtime.configPreviewLoopTimer = C_Timer.NewTimer(10, QueueEditModeEvents)
        end
    end

    QueueEditModeEvents()
    self:RefreshTimelineRuntimeState()
end

function CooldownTimeline:StopConfigPreview(reason)
    if not self.runtime or not self.runtime.configPreviewActive then
        return
    end

    self.runtime.configPreviewActive = false

    if self.runtime.configPreviewLoopTimer then
        self.runtime.configPreviewLoopTimer:Cancel()
        self.runtime.configPreviewLoopTimer = nil
    end

    if C_EncounterTimeline and C_EncounterTimeline.CancelEditModeEvents and not IsEditModeShown() then
        C_EncounterTimeline.CancelEditModeEvents()
    end

    if EncounterTimeline and EncounterTimeline.SetExplicitlyShown then
        EncounterTimeline:SetExplicitlyShown(false)
    end

    if C_EncounterTimeline and C_EncounterTimeline.SetViewType and self.runtime.configPreviewPreviousViewType ~= nil then
        C_EncounterTimeline.SetViewType(self.runtime.configPreviewPreviousViewType)
    end

    self.runtime.configPreviewPreviousViewType = nil
    self:RefreshTimelineRuntimeState()

    if not C_InstanceEncounter or not C_InstanceEncounter.IsEncounterInProgress or not C_InstanceEncounter.IsEncounterInProgress() then
        self:CancelAllOwnedEvents("config_preview_stopped")
    end
end

function CooldownTimeline:UpdateConfigPreviewState(reason)
    if self:ShouldRunConfigPreview() then
        self:StartConfigPreview(reason)
    else
        self:StopConfigPreview(reason)
    end
end

function CooldownTimeline:IsTimelineOperational()
    if not C_EncounterTimeline or not C_InstanceEncounter then
        return false
    end

    if not C_EncounterTimeline.IsFeatureAvailable or not C_EncounterTimeline.IsFeatureAvailable() then
        return false
    end

    if not C_EncounterTimeline.IsFeatureEnabled or not C_EncounterTimeline.IsFeatureEnabled() then
        return false
    end

    if not C_EncounterTimeline.GetViewType or C_EncounterTimeline.GetViewType() ~= self:GetViewTypeTimeline() then
        return false
    end

    if not self.runtime.timelineViewActive then
        return false
    end

    if self.runtime.configPreviewActive then
        return true
    end

    if not C_InstanceEncounter.IsEncounterInProgress or not C_InstanceEncounter.IsEncounterInProgress() then
        return false
    end

    if not C_InstanceEncounter.ShouldShowTimelineForEncounter or not C_InstanceEncounter.ShouldShowTimelineForEncounter() then
        return false
    end

    return true
end

function CooldownTimeline:CancelOwnedEventForSpell(baseSpellID, reason)
    local active = self.runtime.activeByBaseSpellID[baseSpellID]
    if not active then
        return
    end

    local eventID = active.eventID
    self.runtime.activeByBaseSpellID[baseSpellID] = nil
    self.runtime.eventMetaByEventID[eventID] = nil

    if C_EncounterTimeline and eventID then
        C_EncounterTimeline.CancelScriptEvent(eventID)
    end
end

function CooldownTimeline:FinishOwnedEventForSpell(baseSpellID, reason)
    local active = self.runtime.activeByBaseSpellID[baseSpellID]
    if not active then
        return
    end

    local eventID = active.eventID
    self.runtime.activeByBaseSpellID[baseSpellID] = nil
    self.runtime.eventMetaByEventID[eventID] = nil

    if C_EncounterTimeline and eventID then
        C_EncounterTimeline.FinishScriptEvent(eventID)
    end
end

function CooldownTimeline:CancelAllOwnedEvents(reason)
    if not self.runtime then
        return
    end

    local activeByBaseSpellID = self.runtime.activeByBaseSpellID
    for baseSpellID in pairs(activeByBaseSpellID) do
        self:CancelOwnedEventForSpell(baseSpellID, reason)
    end

    ClearTable(self.runtime.eventMetaByEventID)
end

function CooldownTimeline:AddOrReplaceOwnedEvent(baseSpellID, eventRequest, meta)
    if not self:IsTimelineOperational() then
        return nil
    end

    if type(eventRequest) ~= "table" then
        return nil
    end

    self:CancelOwnedEventForSpell(baseSpellID, "replace_event")

    local eventID = C_EncounterTimeline.AddScriptEvent(eventRequest)
    if not eventID or eventID <= 0 then
        return nil
    end

    local entry = {
        eventID = eventID,
        trackedSpellID = meta and meta.trackedSpellID or eventRequest.spellID,
        expectedEndTime = meta and meta.expectedEndTime or (GetTime() + eventRequest.duration),
        isCharge = meta and meta.isCharge or false,
        lastDurationSec = eventRequest.duration,
    }

    self.runtime.activeByBaseSpellID[baseSpellID] = entry
    self.runtime.eventMetaByEventID[eventID] = {
        baseSpellID = baseSpellID,
    }

    return eventID
end

function CooldownTimeline:OnPlayerEnteringWorld()
    self:RefreshCurrentSpecID()
    self:RefreshTimelineRuntimeState()
    if not self:IsTimelineOperational() then
        self:CancelAllOwnedEvents("player_entering_world")
    end
    self:RefreshSettingsPanel()
    self:UpdateConfigPreviewState("player_entering_world")
end

function CooldownTimeline:OnEncounterStateChanged(_, isInProgress)
    self.runtime.encounterInProgress = (isInProgress == true)
    if self.runtime.encounterInProgress then
        self:CancelAllOwnedEvents("encounter_started")
    else
        self:CancelAllOwnedEvents("encounter_ended")
    end
    self:UpdateConfigPreviewState("encounter_state_changed")
end

function CooldownTimeline:OnEncounterTimelineViewActivated(_, viewType)
    if viewType == self:GetViewTypeTimeline() then
        self.runtime.timelineViewActive = true
    end
end

function CooldownTimeline:OnEncounterTimelineViewDeactivated(_, viewType)
    if viewType == self:GetViewTypeTimeline() then
        self.runtime.timelineViewActive = false
        self:CancelAllOwnedEvents("timeline_view_deactivated")
    end
    self:UpdateConfigPreviewState("timeline_view_deactivated")
end

function CooldownTimeline:OnEncounterTimelineStateUpdated()
    self:RefreshTimelineRuntimeState()
    if not self:IsTimelineOperational() then
        self:CancelAllOwnedEvents("timeline_state_updated")
    end
    self:UpdateConfigPreviewState("timeline_state_updated")
end
