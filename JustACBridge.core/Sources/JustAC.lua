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
    if not BlizzardAPI or not BlizzardAPI.IsSpellUsable then return nil end
    local ok, usable = pcall(BlizzardAPI.IsSpellUsable, spellID)
    if ok and type(usable) == "boolean"
        and not (issecretvalue and issecretvalue(usable)) then return usable end
    return nil
end

-- Preserve the upstream queue API's semantics for existing consumers. Some
-- JustAC versions fail open (false) on missing DurationObjects; this wrapper
-- cannot turn that boolean back into evidence. New Frost injections therefore
-- require an additional strict, uncached policy predicate.
function Source.IsSpellOnCooldown(spellID)
    if not BlizzardAPI or not BlizzardAPI.IsSpellOnCooldown then
        return nil
    end
    local ok, onCooldown = pcall(BlizzardAPI.IsSpellOnCooldown, spellID)
    if ok and type(onCooldown) == "boolean"
        and not (issecretvalue and issecretvalue(onCooldown)) then return onCooldown end
    return nil
end

-- Secret-safe threshold query. The numeric remaining cooldown is intentionally
-- never read; the engine DurationObject is compared against a constant through
-- JustAC's curve helper and yields a plain boolean or nil. Its rounded/ramped
-- threshold must not be mistaken for an exact numeric resource/CD observation.
function Source.IsSpellCooldownRemainingAbove(spellID, seconds)
    if not (spellID and type(seconds) == "number" and seconds > 0
            and C_Spell and C_Spell.GetSpellCooldownDuration
            and BlizzardAPI and BlizzardAPI.IsDurationBelowSeconds) then
        return nil
    end
    local okDuration, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    if not okDuration or not duration then return nil end
    local okBelow, below = pcall(BlizzardAPI.IsDurationBelowSeconds, duration, seconds)
    if not okBelow or type(below) ~= "boolean"
        or (issecretvalue and issecretvalue(below)) then
        return nil
    end
    return not below
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

-- Stage G can deliberately place a called-for burst trigger at queue position
-- 2 while preserving Blizzard Assisted Combat's authoritative pick at position
-- 1. Expose that exact, source-owned signal so M5 can execute the cue instead
-- of treating it as an ordinary low-priority tail entry.
function Source.IsBurstCue(spellID)
    return SpellQueue and SpellQueue.IsBurstCue
        and SpellQueue.IsBurstCue(spellID) == true or false
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
