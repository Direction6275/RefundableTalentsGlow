local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local Constants = NS.Constants

local C_EncounterTimeline = C_EncounterTimeline
local C_Timer = C_Timer
local C_Spell = C_Spell

local UPDATE_PERIOD_SEC = 0.05
local MAX_LANES = 3
local LANE_SPACING = 20
local OVERLAY_ICON_SIZE = 35

local function BuildQuerySpellIDs(baseSpellID, trackedSpellID)
    local queryIDs = {}

    if NS.IsReadableNumber(trackedSpellID) and trackedSpellID > 0 then
        queryIDs[#queryIDs + 1] = trackedSpellID
    end

    if NS.IsReadableNumber(baseSpellID) and baseSpellID > 0 and baseSpellID ~= trackedSpellID then
        queryIDs[#queryIDs + 1] = baseSpellID
    end

    return queryIDs
end

local function GetRemainingFromCooldownInfo(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return nil
    end

    if not NS.IsReadableNumber(cooldownInfo.startTime) or not NS.IsReadableNumber(cooldownInfo.duration) then
        return nil
    end

    if cooldownInfo.duration <= 0 or cooldownInfo.startTime <= 0 then
        return 0
    end

    if cooldownInfo.isOnGCD == true and cooldownInfo.duration <= Constants.GCDThresholdSec then
        return 0
    end

    local remaining = (cooldownInfo.startTime + cooldownInfo.duration) - GetTime()
    if remaining <= 0 then
        return 0
    end

    return remaining
end

local function SetOrientedPoint(region, orientation, point, relativeTo, relativePoint, x, y)
    local translatedPoint = orientation:GetTranslatedPointName(point)
    local translatedRelativePoint = orientation:GetTranslatedPointName(relativePoint)
    local offsetX, offsetY = orientation:GetOrientedOffsets(x, y)
    region:SetPoint(translatedPoint, relativeTo, translatedRelativePoint, offsetX, offsetY)
end

function CooldownTimeline:InitializeOverlayRenderer()
    self.overlayRuntime = {
        container = nil,
        iconPips = {},
        trackPips = {},
        eventFrameManagerStub = {
            DetachEventFrame = function() end,
            ReleaseEventFrame = function() end,
        },
        ticker = nil,
    }
end

function CooldownTimeline:EnsureOverlayContainer(trackView)
    local overlay = self.overlayRuntime
    if not overlay then
        return nil
    end

    local container = overlay.container
    if not container then
        container = CreateFrame("Frame", ADDON_NAME .. "PipOverlay", trackView)
        container:SetFrameStrata("HIGH")
        overlay.container = container
    end

    if container:GetParent() ~= trackView then
        container:SetParent(trackView)
    end

    container:ClearAllPoints()
    container:SetAllPoints(trackView)

    local desiredLevel = (trackView:GetFrameLevel() or 1) + 50
    if container:GetFrameLevel() ~= desiredLevel then
        container:SetFrameLevel(desiredLevel)
    end

    return container
end

function CooldownTimeline:AcquireOverlayIconPip(index)
    local overlay = self.overlayRuntime
    if not overlay or not overlay.container then
        return nil
    end

    local pip = overlay.iconPips[index]
    if pip then
        return pip
    end

    pip = CreateFrame("Frame", nil, overlay.container, "EncounterTimelineEventIconTemplate")
    pip:SetSize(OVERLAY_ICON_SIZE, OVERLAY_ICON_SIZE)
    pip:EnableMouse(false)

    overlay.iconPips[index] = pip
    return pip
end

function CooldownTimeline:AcquireOverlayTrackPip(index)
    local overlay = self.overlayRuntime
    if not overlay or not overlay.container then
        return nil
    end

    local pip = overlay.trackPips[index]
    if pip then
        return pip
    end

    pip = CreateFrame("Frame", nil, overlay.container, "EncounterTimelineTrackEventTemplate")
    pip:SetSize(OVERLAY_ICON_SIZE, OVERLAY_ICON_SIZE)
    pip:EnableMouse(false)

    overlay.trackPips[index] = pip
    return pip
end

local function HideUnusedFramePool(framePool, usedCount)
    if type(framePool) ~= "table" then
        return
    end

    for index = usedCount + 1, #framePool do
        framePool[index]:Hide()
    end
end

function CooldownTimeline:HideUnusedOverlayPips(usedIconCount, usedTrackCount)
    local overlay = self.overlayRuntime
    if not overlay then
        return
    end

    usedIconCount = usedIconCount or 0
    usedTrackCount = usedTrackCount or 0

    HideUnusedFramePool(overlay.iconPips, usedIconCount)
    HideUnusedFramePool(overlay.trackPips, usedTrackCount)
end

function CooldownTimeline:GetOverlayRemaining(activeEntry)
    if type(activeEntry) ~= "table" then
        return nil
    end

    if C_EncounterTimeline and C_EncounterTimeline.GetEventTimeRemaining and NS.IsReadableNumber(activeEntry.eventID) then
        local remainingFromAPI = C_EncounterTimeline.GetEventTimeRemaining(activeEntry.eventID)
        if NS.IsReadableNumber(remainingFromAPI) then
            return remainingFromAPI
        end
    end

    if NS.IsReadableNumber(activeEntry.expectedEndTime) then
        local remainingFromPrediction = activeEntry.expectedEndTime - GetTime()
        if remainingFromPrediction > 0 then
            return remainingFromPrediction
        end
        return 0
    end

    return nil
end

function CooldownTimeline:GetOverlayLiveRemaining(baseSpellID, trackedSpellID)
    local querySpellIDs = BuildQuerySpellIDs(baseSpellID, trackedSpellID)

    if C_Spell and C_Spell.GetSpellCharges then
        for _, querySpellID in ipairs(querySpellIDs) do
            local chargeInfo = C_Spell.GetSpellCharges(querySpellID)
            if type(chargeInfo) == "table" and NS.IsReadableNumber(chargeInfo.maxCharges) and chargeInfo.maxCharges > 0 then
                if NS.IsReadableNumber(chargeInfo.currentCharges) then
                    if chargeInfo.currentCharges > 0 then
                        return 0
                    end

                    if chargeInfo.currentCharges == 0 and NS.IsReadableNumber(chargeInfo.cooldownStartTime) and NS.IsReadableNumber(chargeInfo.cooldownDuration) then
                        local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
                        if remaining > 0 then
                            return remaining
                        end
                        return 0
                    end
                end
            end
        end
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        for _, querySpellID in ipairs(querySpellIDs) do
            local cooldownInfo = C_Spell.GetSpellCooldown(querySpellID)
            local remaining = GetRemainingFromCooldownInfo(cooldownInfo)
            if NS.IsReadableNumber(remaining) then
                if remaining <= 0 then
                    return 0
                end
                return remaining
            end
        end
    end

    return 0
end

function CooldownTimeline:BuildOverlayEvent(baseSpellID, activeEntry, spellConfig)
    if baseSpellID > 0 and (not spellConfig or spellConfig.enabled == false) then
        return nil
    end

    local trackedSpellID = baseSpellID
    if type(activeEntry) == "table" and NS.IsReadableNumber(activeEntry.trackedSpellID) and activeEntry.trackedSpellID > 0 then
        trackedSpellID = activeEntry.trackedSpellID
    end

    local iconFileID = C_Spell and C_Spell.GetSpellTexture and select(1, C_Spell.GetSpellTexture(trackedSpellID))
    if not NS.IsReadableNumber(iconFileID) then
        iconFileID = Constants.DefaultIconFileID
    end

    local remaining = nil
    local eventID = nil
    if type(activeEntry) == "table" then
        eventID = activeEntry.eventID
        remaining = self:GetOverlayRemaining(activeEntry)
    end

    if not NS.IsReadableNumber(remaining) then
        remaining = self:GetOverlayLiveRemaining(baseSpellID, trackedSpellID)
    end

    if not NS.IsReadableNumber(remaining) then
        return nil
    end

    if remaining < 0 then
        remaining = 0
    end

    return {
        baseSpellID = baseSpellID,
        eventID = eventID,
        remaining = remaining,
        severity = self:NormalizeSeverity(spellConfig and spellConfig.severity or Constants.SeverityMedium),
        iconFileID = iconFileID,
    }
end

function CooldownTimeline:CollectOverlayEvents()
    local events = {}

    if not self.runtime then
        return events
    end

    local seenBaseSpellIDs = {}

    for baseSpellID, activeEntry in pairs(self.runtime.activeByBaseSpellID) do
        local spellConfig = nil

        if baseSpellID > 0 then
            spellConfig = self:GetTrackedSpellConfig(baseSpellID)
            seenBaseSpellIDs[baseSpellID] = true
        end

        local eventData = self:BuildOverlayEvent(baseSpellID, activeEntry, spellConfig)
        if eventData then
            events[#events + 1] = eventData
        end
    end

    local currentSpecID = self:GetCurrentSpecID()
    if currentSpecID then
        for baseSpellID, spellConfig in self:IterateTrackedSpells(currentSpecID) do
            if spellConfig.enabled ~= false and not seenBaseSpellIDs[baseSpellID] then
                local eventData = self:BuildOverlayEvent(baseSpellID, nil, spellConfig)
                if eventData then
                    events[#events + 1] = eventData
                end
            end
        end
    end

    table.sort(events, function(a, b)
        if a.remaining == b.remaining then
            return a.baseSpellID < b.baseSpellID
        end
        return a.remaining < b.remaining
    end)

    return events
end

function CooldownTimeline:CalculateOverlayOffset(trackView, eventData)
    if type(eventData) ~= "table" or not NS.IsReadableNumber(eventData.remaining) then
        return nil
    end

    if trackView.CalculateOffsetForDuration then
        local offset = trackView:CalculateOffsetForDuration(eventData.remaining)
        if NS.IsReadableNumber(offset) then
            return offset
        end
    end

    if C_EncounterTimeline and C_EncounterTimeline.GetEventTrack and trackView.CalculateEventOffset and NS.IsReadableNumber(eventData.eventID) then
        local track, trackSortIndex = C_EncounterTimeline.GetEventTrack(eventData.eventID)
        if NS.IsReadableNumber(track) then
            local sortIndex = NS.IsReadableNumber(trackSortIndex) and trackSortIndex or 1
            local offset = trackView:CalculateEventOffset(track, sortIndex, eventData.remaining)
            if NS.IsReadableNumber(offset) then
                return offset
            end
        end
    end

    return nil
end

function CooldownTimeline:GetOverlayNativeEventSnapshot(eventID)
    if not C_EncounterTimeline or not NS.IsReadableNumber(eventID) then
        return nil
    end

    if not C_EncounterTimeline.GetEventInfo
        or not C_EncounterTimeline.GetEventTimer
        or not C_EncounterTimeline.GetEventState
        or not C_EncounterTimeline.GetEventTrack
    then
        return nil
    end

    local eventInfo = C_EncounterTimeline.GetEventInfo(eventID)
    local eventTimer = C_EncounterTimeline.GetEventTimer(eventID)
    local eventState = C_EncounterTimeline.GetEventState(eventID)
    local eventTrack, eventTrackSortIndex = C_EncounterTimeline.GetEventTrack(eventID)
    local eventBlocked = C_EncounterTimeline.IsEventBlocked and (C_EncounterTimeline.IsEventBlocked(eventID) == true) or false
    local eventTrackType = C_EncounterTimeline.GetTrackType and C_EncounterTimeline.GetTrackType(eventTrack) or nil

    if type(eventInfo) ~= "table"
        or not eventTimer
        or type(eventTimer.GetRemainingDuration) ~= "function"
        or not NS.IsReadableNumber(eventTrack)
    then
        return nil
    end

    if Enum and Enum.EncounterTimelineTrack and eventTrack == Enum.EncounterTimelineTrack.Indeterminate then
        return nil
    end

    if Enum and Enum.EncounterTimelineTrackType and eventTrackType == Enum.EncounterTimelineTrackType.Hidden then
        return nil
    end

    return {
        eventID = eventID,
        eventInfo = eventInfo,
        eventTimer = eventTimer,
        eventState = eventState,
        eventTrack = eventTrack,
        eventTrackSortIndex = eventTrackSortIndex,
        eventBlocked = eventBlocked,
        eventTrackType = eventTrackType,
    }
end

function CooldownTimeline:ApplyTrackViewSettingsToOverlayTrackPip(pip, trackView, orientation, crossAxisOffset)
    if not pip or not trackView then
        return
    end

    pip:SetTrackLayoutManager(trackView)
    pip:SetCrossAxisOffset(crossAxisOffset)
    pip:SetTrackOrientation(orientation)

    if trackView.ShouldFlipHorizontally then
        pip:SetFlipHorizontally(trackView:ShouldFlipHorizontally())
    end

    if trackView.GetIconScale then
        local iconScale = trackView:GetIconScale()
        if NS.IsReadableNumber(iconScale) and iconScale > 0 then
            pip:SetIconScale(iconScale)
        end
    end

    if trackView.GetIndicatorIconMask then
        pip:SetIndicatorIconMask(trackView:GetIndicatorIconMask())
    end

    if trackView.ShouldShowCountdown then
        pip:SetShowCountdown(trackView:ShouldShowCountdown())
    end

    if trackView.ShouldShowText then
        pip:SetShowText(trackView:ShouldShowText())
    end

    if trackView.GetTooltipAnchor then
        pip:SetTooltipAnchor(trackView:GetTooltipAnchor())
    end

    if trackView.GetHighlightTime then
        local highlightTime = trackView:GetHighlightTime()
        if NS.IsReadableNumber(highlightTime) then
            pip:SetHighlightTime(highlightTime)
        end
    end
end

function CooldownTimeline:RenderOverlayTrackPip(index, container, trackView, orientation, crossAxisOffset, eventData)
    if not NS.IsReadableNumber(eventData and eventData.eventID) then
        return false
    end

    local snapshot = self:GetOverlayNativeEventSnapshot(eventData.eventID)
    if not snapshot then
        return false
    end

    local pip = self:AcquireOverlayTrackPip(index)
    if not pip then
        return false
    end

    if pip.SetEventFrameManager and self.overlayRuntime and self.overlayRuntime.eventFrameManagerStub then
        pip:SetEventFrameManager(self.overlayRuntime.eventFrameManagerStub)
    end

    self:ApplyTrackViewSettingsToOverlayTrackPip(pip, trackView, orientation, crossAxisOffset)

    local frameLevel = (trackView:GetFrameLevel() or 1) + 1
    if pip:GetFrameLevel() ~= frameLevel then
        pip:SetFrameLevel(frameLevel)
    end

    pip:ClearAllPoints()
    pip:SetPoint("CENTER", container, orientation:GetStartPoint(), 0, 0)

    if pip.overlayEventID ~= snapshot.eventID then
        pip:SetEventID(snapshot.eventID)
        pip:Init(
            snapshot.eventInfo,
            snapshot.eventTimer,
            snapshot.eventState,
            snapshot.eventTrack,
            snapshot.eventTrackSortIndex,
            snapshot.eventBlocked
        )
        pip.overlayEventID = snapshot.eventID
    else
        pip:SetEventState(snapshot.eventState)
        pip:SetEventTrack(snapshot.eventTrack, snapshot.eventTrackSortIndex)
        pip:SetEventBlocked(snapshot.eventBlocked)
    end

    pip:Show()
    return true
end

function CooldownTimeline:RenderOverlayIconPip(index, container, trackView, orientation, crossAxisOffset, eventData, iconScale)
    local offset = self:CalculateOverlayOffset(trackView, eventData)
    if not NS.IsReadableNumber(offset) then
        return false
    end

    local pip = self:AcquireOverlayIconPip(index)
    if not pip then
        return false
    end

    pip:SetScale(iconScale)

    if pip.SetIcon then
        pip:SetIcon(eventData.iconFileID)
    elseif pip.IconTexture then
        pip.IconTexture:SetTexture(eventData.iconFileID)
    end

    if pip.SetPaused then
        pip:SetPaused(false)
    end
    if pip.SetQueued then
        pip:SetQueued(false)
    end
    if pip.SetDeadlyEffect then
        pip:SetDeadlyEffect(eventData.severity == Constants.SeverityHigh)
    end

    pip:ClearAllPoints()
    SetOrientedPoint(pip, orientation, "CENTER", container, "START", offset, crossAxisOffset)
    pip:Show()

    return true
end

function CooldownTimeline:RefreshOverlayRenderer()
    local overlay = self.overlayRuntime
    if not overlay then
        return
    end

    if not self:IsTimelineOperational() then
        if overlay.container then
            overlay.container:Hide()
        end
        self:HideUnusedOverlayPips(0)
        return
    end

    local timelineFrame = EncounterTimeline
    local trackView = nil
    if timelineFrame and timelineFrame.GetTrackView then
        trackView = timelineFrame:GetTrackView()
    end
    if not trackView and timelineFrame then
        trackView = timelineFrame.TrackView
    end
    if not trackView or not trackView:IsShown() then
        if overlay.container then
            overlay.container:Hide()
        end
        self:HideUnusedOverlayPips(0)
        return
    end

    local orientation = trackView.GetTrackOrientation and trackView:GetTrackOrientation()
    if not orientation or type(orientation.GetTranslatedPointName) ~= "function" or type(orientation.GetOrientedOffsets) ~= "function" then
        if overlay.container then
            overlay.container:Hide()
        end
        self:HideUnusedOverlayPips(0)
        return
    end

    local container = self:EnsureOverlayContainer(trackView)
    if not container then
        return
    end
    container:Show()

    local baseCrossAxisOffset = 0
    if trackView.GetCrossAxisOffset then
        local value = trackView:GetCrossAxisOffset()
        if NS.IsReadableNumber(value) then
            baseCrossAxisOffset = value
        end
    end

    local events = self:CollectOverlayEvents()
    local visibleIconPips = 0
    local visibleTrackPips = 0
    local visibleOverlayCount = 0
    local iconScale = 1
    if trackView.GetIconScale then
        local value = trackView:GetIconScale()
        if NS.IsReadableNumber(value) and value > 0 then
            iconScale = value
        end
    end

    for _, eventData in ipairs(events) do
        local laneCycleIndex = visibleOverlayCount % MAX_LANES
        local laneOffsetIndex = 0
        if laneCycleIndex == 1 then
            laneOffsetIndex = 1
        elseif laneCycleIndex == 2 then
            laneOffsetIndex = -1
        end
        local laneCrossAxisOffset = baseCrossAxisOffset + (laneOffsetIndex * LANE_SPACING)

        local rendered = false
        if NS.IsReadableNumber(eventData.eventID) then
            rendered = self:RenderOverlayTrackPip(visibleTrackPips + 1, container, trackView, orientation, laneCrossAxisOffset, eventData)
            if rendered then
                visibleTrackPips = visibleTrackPips + 1
            end
        end

        if not rendered then
            rendered = self:RenderOverlayIconPip(visibleIconPips + 1, container, trackView, orientation, laneCrossAxisOffset, eventData, iconScale)
            if rendered then
                visibleIconPips = visibleIconPips + 1
            end
        end

        if rendered then
            visibleOverlayCount = visibleOverlayCount + 1
        end
    end

    self:HideUnusedOverlayPips(visibleIconPips, visibleTrackPips)
end

function CooldownTimeline:StartOverlayRenderer()
    local overlay = self.overlayRuntime
    if not overlay or overlay.ticker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    overlay.ticker = C_Timer.NewTicker(UPDATE_PERIOD_SEC, function()
        CooldownTimeline:RefreshOverlayRenderer()
    end)

    self:RefreshOverlayRenderer()
end

function CooldownTimeline:StopOverlayRenderer()
    local overlay = self.overlayRuntime
    if not overlay then
        return
    end

    if overlay.ticker then
        overlay.ticker:Cancel()
        overlay.ticker = nil
    end

    if overlay.container then
        overlay.container:Hide()
    end

    self:HideUnusedOverlayPips(0)
end
