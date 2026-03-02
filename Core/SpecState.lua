local ADDON_NAME, NS = ...
local CooldownTimeline = NS.Addon

local C_SpecializationInfo = C_SpecializationInfo

function CooldownTimeline:InitializeSpecState()
    self.currentSpecID = nil
end

function CooldownTimeline:GetCurrentSpecID()
    return self.currentSpecID
end

function CooldownTimeline:GetResolvedBaseSpellID(spellID)
    local numericID = tonumber(spellID)
    if not numericID then
        return nil
    end

    local baseSpellID = C_Spell.GetBaseSpell(numericID)
    if type(baseSpellID) == "number" and baseSpellID > 0 then
        return baseSpellID
    end

    return numericID
end

function CooldownTimeline:ResolveCurrentSpecID()
    if not C_SpecializationInfo or not C_SpecializationInfo.GetSpecialization then
        return nil
    end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex <= 0 then
        return nil
    end

    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if type(specID) == "number" and specID > 0 then
        return specID
    end

    return nil
end

function CooldownTimeline:RefreshCurrentSpecID()
    local previousSpecID = self.currentSpecID
    local currentSpecID = self:ResolveCurrentSpecID()
    self.currentSpecID = currentSpecID

    if previousSpecID ~= currentSpecID then
        self:CancelAllOwnedEvents("spec_changed")
        self:RefreshSettingsPanel()
    end
end

function CooldownTimeline:OnPlayerSpecializationChanged(_, unitTarget)
    if unitTarget ~= "player" then
        return
    end

    self:RefreshCurrentSpecID()
end
