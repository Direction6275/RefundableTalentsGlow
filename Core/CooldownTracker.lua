local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local Constants = NS.Constants

local abs = math.abs
local max = math.max
local min = math.min
local tonumber = tonumber

local SeverityToName = {
    [Constants.SeverityLow] = "Low",
    [Constants.SeverityMedium] = "Medium",
    [Constants.SeverityHigh] = "High",
}

local function BuildQuerySpellIDs(baseSpellID, observedSpellID)
    local queryIDs = {}

    if NS.IsReadableNumber(observedSpellID) and observedSpellID > 0 then
        queryIDs[#queryIDs + 1] = observedSpellID
    end

    if NS.IsReadableNumber(baseSpellID) and baseSpellID > 0 and baseSpellID ~= observedSpellID then
        queryIDs[#queryIDs + 1] = baseSpellID
    end

    return queryIDs
end

function CooldownTimeline:GetSeverityName(severity)
    return SeverityToName[severity] or "Medium"
end

function CooldownTimeline:NormalizeSeverity(severity)
    if severity == Constants.SeverityLow or severity == Constants.SeverityMedium or severity == Constants.SeverityHigh then
        return severity
    end
    return Constants.SeverityMedium
end

function CooldownTimeline:IsGCDOnlyCooldown(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return false
    end

    if cooldownInfo.isOnGCD ~= true then
        return false
    end

    if not NS.IsReadableNumber(cooldownInfo.duration) then
        return false
    end

    return cooldownInfo.duration <= Constants.GCDThresholdSec
end

function CooldownTimeline:BuildTimelineEventRequest(baseSpellID, trackedSpellID, config, durationSec)
    local requestSpellID = baseSpellID
    if not C_Spell.DoesSpellExist(requestSpellID) and NS.IsReadableNumber(trackedSpellID) and C_Spell.DoesSpellExist(trackedSpellID) then
        requestSpellID = trackedSpellID
    end

    local iconFileID = select(1, C_Spell.GetSpellTexture(trackedSpellID or requestSpellID))
    if not NS.IsReadableNumber(iconFileID) then
        iconFileID = Constants.DefaultIconFileID
    end

    local eventSeverity = self:NormalizeSeverity(config and config.severity)
    local customLabel = config and NS.Trim(config.customLabel or "") or ""

    return {
        spellID = requestSpellID,
        iconFileID = iconFileID,
        duration = durationSec,
        maxQueueDuration = self:GetReadyLingerSeconds(),
        overrideName = customLabel,
        severity = eventSeverity,
        paused = false,
    }
end

function CooldownTimeline:NormalizeDuration(durationSec)
    if not NS.IsReadableNumber(durationSec) then
        return nil
    end

    local clamped = max(durationSec, Constants.MinDurationSec)
    return min(clamped, 600)
end

function CooldownTimeline:GetReadableRemainingFromCooldownInfo(cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return nil
    end

    if not NS.IsReadableNumber(cooldownInfo.startTime) or not NS.IsReadableNumber(cooldownInfo.duration) then
        return nil
    end

    if cooldownInfo.duration <= 0 or cooldownInfo.startTime <= 0 then
        return 0
    end

    if self:IsGCDOnlyCooldown(cooldownInfo) then
        return 0
    end

    local remaining = (cooldownInfo.startTime + cooldownInfo.duration) - GetTime()
    if remaining <= 0 then
        return 0
    end

    return remaining
end

function CooldownTimeline:ComputeTrackedDuration(baseSpellID, castSpellID, spellConfig)
    if not spellConfig or spellConfig.enabled == false then
        return nil
    end

    local querySpellIDs = BuildQuerySpellIDs(baseSpellID, castSpellID)
    local hasChargeSystem = false
    local hasChargeAvailable = false
    local pendingChargeRemaining = nil

    for _, querySpellID in ipairs(querySpellIDs) do
        local chargeInfo = C_Spell.GetSpellCharges(querySpellID)
        if type(chargeInfo) == "table" and NS.IsReadableNumber(chargeInfo.maxCharges) and chargeInfo.maxCharges > 0 then
            hasChargeSystem = true

            if NS.IsReadableNumber(chargeInfo.currentCharges) then
                if chargeInfo.currentCharges > 0 then
                    hasChargeAvailable = true
                elseif NS.IsReadableNumber(chargeInfo.cooldownStartTime) and NS.IsReadableNumber(chargeInfo.cooldownDuration) then
                    local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
                    if remaining > 0 and (not pendingChargeRemaining or remaining > pendingChargeRemaining) then
                        pendingChargeRemaining = remaining
                    end
                end
            end
        end
    end

    if hasChargeSystem then
        if hasChargeAvailable then
            return nil
        end
        if NS.IsReadableNumber(pendingChargeRemaining) and pendingChargeRemaining > 0 then
            return self:NormalizeDuration(pendingChargeRemaining), true, pendingChargeRemaining
        end
        return nil
    end

    for _, querySpellID in ipairs(querySpellIDs) do
        local cooldownInfo = C_Spell.GetSpellCooldown(querySpellID)
        local readableRemaining = self:GetReadableRemainingFromCooldownInfo(cooldownInfo)
        if NS.IsReadableNumber(readableRemaining) and readableRemaining > 0 then
            return self:NormalizeDuration(readableRemaining), false, readableRemaining
        end
    end

    local overrideSec = tonumber(spellConfig.cooldownOverrideSec)
    if overrideSec and overrideSec > 0 then
        return self:NormalizeDuration(overrideSec), false, nil
    end

    local lastKnown = tonumber(spellConfig.lastKnownDurationSec)
    if lastKnown and lastKnown > 0 then
        return self:NormalizeDuration(lastKnown), false, nil
    end

    return nil
end

function CooldownTimeline:QueueTrackedSpellEvent(baseSpellID, trackedSpellID, spellConfig, durationSec, isCharge)
    local normalizedDuration = self:NormalizeDuration(durationSec)
    if not normalizedDuration then
        return nil
    end

    local request = self:BuildTimelineEventRequest(baseSpellID, trackedSpellID, spellConfig, normalizedDuration)
    local meta = {
        trackedSpellID = trackedSpellID,
        expectedEndTime = GetTime() + normalizedDuration,
        isCharge = isCharge == true,
    }
    return self:AddOrReplaceOwnedEvent(baseSpellID, request, meta)
end

function CooldownTimeline:TryQueueSpellFromCast(spellID)
    if not self:IsTimelineOperational() then
        return
    end

    local baseSpellID = self:GetResolvedBaseSpellID(spellID)
    if not baseSpellID then
        return
    end

    self:TryQueueTrackedSpellByBaseSpellID(baseSpellID, spellID)
end

function CooldownTimeline:TryQueueTrackedSpellByBaseSpellID(baseSpellID, observedSpellID)
    if not self:IsTimelineOperational() then
        return
    end

    if not NS.IsReadableNumber(baseSpellID) or baseSpellID <= 0 then
        return
    end

    local spellConfig = self:GetTrackedSpellConfig(baseSpellID)
    if not spellConfig or spellConfig.enabled == false then
        return
    end

    local trackedSpellID = (NS.IsReadableNumber(observedSpellID) and observedSpellID > 0) and observedSpellID or baseSpellID
    local durationSec, isCharge, learnedDuration = self:ComputeTrackedDuration(baseSpellID, trackedSpellID, spellConfig)
    if not durationSec then
        return
    end

    if NS.IsReadableNumber(learnedDuration) and learnedDuration > 0 then
        spellConfig.lastKnownDurationSec = learnedDuration
    end

    self:QueueTrackedSpellEvent(baseSpellID, trackedSpellID, spellConfig, durationSec, isCharge)
end

function CooldownTimeline:OnUnitSpellcastSucceeded(_, unitTarget, castGUID, spellID, castBarID)
    if unitTarget ~= "player" then
        return
    end

    if not NS.IsReadableNumber(spellID) then
        return
    end

    self:TryQueueSpellFromCast(spellID)
end

function CooldownTimeline:GetReadableRemainingForReconcile(baseSpellID, trackedSpellID, isCharge)
    local spellID = trackedSpellID or baseSpellID

    if isCharge then
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if type(chargeInfo) ~= "table" then
            return nil
        end

        if not NS.IsReadableNumber(chargeInfo.currentCharges) then
            return nil
        end

        if chargeInfo.currentCharges > 0 then
            return 0
        end

        if not NS.IsReadableNumber(chargeInfo.cooldownStartTime) or not NS.IsReadableNumber(chargeInfo.cooldownDuration) then
            return nil
        end

        local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
        if remaining <= 0 then
            return 0
        end

        return remaining
    end

    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    return self:GetReadableRemainingFromCooldownInfo(cooldownInfo)
end

function CooldownTimeline:ReconcileTrackedSpell(baseSpellID)
    local active = self.runtime.activeByBaseSpellID[baseSpellID]
    if not active then
        return
    end

    local spellConfig = self:GetTrackedSpellConfig(baseSpellID)
    if not spellConfig or spellConfig.enabled == false then
        self:CancelOwnedEventForSpell(baseSpellID, "spell_untracked")
        return
    end

    local remaining = self:GetReadableRemainingForReconcile(baseSpellID, active.trackedSpellID, active.isCharge)
    if not NS.IsReadableNumber(remaining) then
        return
    end

    if remaining <= 0 then
        self:FinishOwnedEventForSpell(baseSpellID, "spell_ready")
        return
    end

    local predictedRemaining = max(0, active.expectedEndTime - GetTime())
    local drift = abs(predictedRemaining - remaining)

    if drift < Constants.DriftThresholdSec then
        return
    end

    local normalizedDuration = self:NormalizeDuration(remaining)
    if not normalizedDuration then
        return
    end

    if active.isCharge == false and NS.IsReadableNumber(remaining) and remaining > 0 then
        spellConfig.lastKnownDurationSec = remaining
    end

    self:QueueTrackedSpellEvent(baseSpellID, active.trackedSpellID, spellConfig, normalizedDuration, active.isCharge)
end

function CooldownTimeline:ReconcileActiveSpells(candidates)
    if not self:IsTimelineOperational() then
        return
    end

    if type(candidates) == "table" then
        for baseSpellID in pairs(candidates) do
            self:ReconcileTrackedSpell(baseSpellID)
        end
        return
    end

    for baseSpellID in pairs(self.runtime.activeByBaseSpellID) do
        self:ReconcileTrackedSpell(baseSpellID)
    end
end

function CooldownTimeline:OnSpellUpdateCooldown(_, spellID, baseSpellID, category, startRecoveryCategory)
    local candidates = {}

    if NS.IsReadableNumber(baseSpellID) and baseSpellID > 0 then
        candidates[self:GetResolvedBaseSpellID(baseSpellID)] = true
    end

    if NS.IsReadableNumber(spellID) and spellID > 0 then
        candidates[self:GetResolvedBaseSpellID(spellID)] = true
    end

    if next(candidates) then
        self:ReconcileActiveSpells(candidates)
    else
        self:ReconcileActiveSpells()
    end

    if not self:IsTimelineOperational() then
        return
    end

    local currentSpecID = self:GetCurrentSpecID()
    if not currentSpecID then
        return
    end

    if next(candidates) then
        for candidateBaseSpellID in pairs(candidates) do
            if not self.runtime.activeByBaseSpellID[candidateBaseSpellID] then
                self:TryQueueTrackedSpellByBaseSpellID(candidateBaseSpellID, candidateBaseSpellID)
            end
        end
        return
    end

    for trackedBaseSpellID, spellConfig in self:IterateTrackedSpells(currentSpecID) do
        if spellConfig.enabled ~= false and not self.runtime.activeByBaseSpellID[trackedBaseSpellID] then
            self:TryQueueTrackedSpellByBaseSpellID(trackedBaseSpellID, trackedBaseSpellID)
        end
    end
end

function CooldownTimeline:OnSpellUpdateCharges()
    local candidates = {}
    for baseSpellID, active in pairs(self.runtime.activeByBaseSpellID) do
        if active.isCharge then
            candidates[baseSpellID] = true
        end
    end

    if next(candidates) then
        self:ReconcileActiveSpells(candidates)
    end

    if not self:IsTimelineOperational() then
        return
    end

    local currentSpecID = self:GetCurrentSpecID()
    if not currentSpecID then
        return
    end

    for baseSpellID, spellConfig in self:IterateTrackedSpells(currentSpecID) do
        if spellConfig.enabled ~= false and not self.runtime.activeByBaseSpellID[baseSpellID] then
            local chargeInfo = C_Spell.GetSpellCharges(baseSpellID)
            if type(chargeInfo) == "table"
                and NS.IsReadableNumber(chargeInfo.maxCharges)
                and chargeInfo.maxCharges > 0
                and NS.IsReadableNumber(chargeInfo.currentCharges)
                and chargeInfo.currentCharges == 0
                and NS.IsReadableNumber(chargeInfo.cooldownStartTime)
                and NS.IsReadableNumber(chargeInfo.cooldownDuration)
            then
                local remaining = (chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration) - GetTime()
                local normalizedDuration = self:NormalizeDuration(remaining)
                if normalizedDuration then
                    self:QueueTrackedSpellEvent(baseSpellID, baseSpellID, spellConfig, normalizedDuration, true)
                end
            end
        end
    end
end

function CooldownTimeline:AddTestTimelineEvent(durationSec)
    if not self:IsTimelineOperational() then
        self:Print("CooldownTimeline: encounter timeline is not active.")
        return
    end

    local value = tonumber(durationSec) or 10
    value = NS.Clamp(value, 1, 90)

    local request = {
        spellID = 61304,
        iconFileID = select(1, C_Spell.GetSpellTexture(61304)) or Constants.DefaultIconFileID,
        duration = value,
        maxQueueDuration = self:GetReadyLingerSeconds(),
        overrideName = "CooldownTimeline Test",
        severity = Constants.SeverityMedium,
        paused = false,
    }

    local meta = {
        trackedSpellID = 61304,
        expectedEndTime = GetTime() + value,
        isCharge = false,
    }

    local eventID = self:AddOrReplaceOwnedEvent(Constants.TestEventKey, request, meta)
    if eventID then
        self:Print(("CooldownTimeline: added test event (ID %d) for %.1fs."):format(eventID, value))
    else
        self:Print("CooldownTimeline: failed to add test event.")
    end
end
