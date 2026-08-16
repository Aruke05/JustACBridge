local Registry = _G.JustACBridgeRecommendationSources
if not Registry then
    return
end

local SpellQueue
local ActionBarScanner
local BlizzardAPI
local BurstInjectionEngine
local SpellDB
local JustACAddon

local Source = {
    name = "JustAC",
}

function Source.Initialize()
    local libStub = _G.LibStub
    if not libStub then
        return false, "LibStub unavailable"
    end
    SpellQueue = libStub("JustAC-SpellQueue", true)
    ActionBarScanner = libStub("JustAC-ActionBarScanner", true)
    BlizzardAPI = libStub("JustAC-BlizzardAPI", true)
    BurstInjectionEngine = libStub("JustAC-BurstInjectionEngine", true)
    SpellDB = libStub("JustAC-SpellDB", true)
    local aceAddon = libStub("AceAddon-3.0", true)
    JustACAddon = aceAddon and aceAddon:GetAddon("JustAssistedCombat", true)
    return SpellQueue ~= nil, "JustAC-SpellQueue unavailable"
end

function Source.IsAvailable()
    return SpellQueue ~= nil
end

function Source.GetQueue()
    return SpellQueue.GetCurrentSpellQueue()
end

function Source.GetSpellHotkey(spellID)
    return ActionBarScanner and ActionBarScanner.GetSpellHotkey
        and ActionBarScanner.GetSpellHotkey(spellID) or ""
end

function Source.GetItemHotkey(itemID)
    return ActionBarScanner and ActionBarScanner.GetItemHotkey
        and ActionBarScanner.GetItemHotkey(itemID) or ""
end

function Source.GetDisplaySpellID(spellID)
    return BlizzardAPI and BlizzardAPI.GetDisplaySpellID
        and BlizzardAPI.GetDisplaySpellID(spellID) or spellID
end

-- The Assisted Combat queue may return the base action-bar spell while a
-- talent replacement is active.  Dynamic action-bar transforms (for example
-- Arcane Blast -> Prismatic Bolt) are authoritative first; when none exists,
-- fall back to JustAC's separate talent-override resolver (for example
-- Arcane Explosion -> Arcane Pulse).
function Source.GetEffectiveSpellID(spellID)
    local displayID = Source.GetDisplaySpellID(spellID)
    if displayID and displayID ~= 0 and displayID ~= spellID then
        return displayID
    end
    return BlizzardAPI and BlizzardAPI.ResolveSpellID
        and BlizzardAPI.ResolveSpellID(spellID) or spellID
end

function Source.IsSpellUsable(spellID)
    return not BlizzardAPI or not BlizzardAPI.IsSpellUsable
        or BlizzardAPI.IsSpellUsable(spellID)
end

function Source.IsSpellProcced(spellID)
    return BlizzardAPI and BlizzardAPI.IsSpellProcced
        and BlizzardAPI.IsSpellProcced(spellID) or false
end

function Source.IsChanneled(spellID)
    return SpellDB and SpellDB.IsChanneled
        and SpellDB.IsChanneled(spellID) or false
end

function Source.IsConfirmedOutOfRange(spellID)
    return SpellQueue and SpellQueue.IsConfirmedOutOfRange
        and SpellQueue.IsConfirmedOutOfRange(spellID) or false
end

function Source.IsTargetWithin(yards)
    if not SpellDB or not SpellDB.IsTargetWithin then
        return nil
    end
    return SpellDB.IsTargetWithin(yards)
end

function Source.GetHighlightCastSpell()
    return BlizzardAPI and BlizzardAPI.GetHighlightCastSpell
        and BlizzardAPI.GetHighlightCastSpell() or nil
end

function Source.GetDetectedBurstTriggers()
    return BurstInjectionEngine and BurstInjectionEngine.GetDetectedTriggers and JustACAddon
        and BurstInjectionEngine.GetDetectedTriggers(JustACAddon) or {}
end

function Source.GetEngagedEnemyCount()
    return BlizzardAPI and BlizzardAPI.GetEngagedEnemyCount
        and BlizzardAPI.GetEngagedEnemyCount() or 0
end

function Source.IsTargetBoss()
    if UnitClassification and UnitClassification("target") == "worldboss" then
        return true
    end
    if BlizzardAPI and BlizzardAPI.SafeUnitIsUnit then
        for index = 1, 5 do
            if BlizzardAPI.SafeUnitIsUnit("target", "boss" .. index, false) then
                return true
            end
        end
    end
    return false
end

Registry.Register("justac", Source)
