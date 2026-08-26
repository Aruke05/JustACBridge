-- Focused adversarial tests for Arcane 12.1 target credentials, the short
-- big-burn state machine and the independent Touch cooldown threshold.
-- This file uses only mocks; it never starts or connects to the game client.

local now = 100
local combat = true
local targetGUID = "Creature-0-0-0-0-100-0000000001"
local targetExists = true
local targetAttackable = true
local targetDead = false
local rawQueue = { 321507, 30451 }
local cooldowns = {}
local usable = {}
local readinessUnknown = {}
local surgeRemaining = 60
local durationThrows = false
local comparisonThrows = false
local sourceFrame

local known = {
    [30451] = true,
    [44425] = true,
    [5143] = true,
    [153626] = true,
    [321507] = true,
    [365350] = true,
    [448601] = true, -- Sunfury
}

function GetTime() return now end
function UnitAffectingCombat() return combat end
function UnitExists(unit) return unit == "target" and targetExists end
function UnitCanAttack(_, unit) return unit == "target" and targetAttackable end
function UnitIsDeadOrGhost(unit) return unit == "target" and targetDead end
function UnitGUID(unit) return unit == "target" and targetExists and targetGUID or nil end
function UnitClass() return "Mage", "MAGE" end
function GetSpecialization() return 1 end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function IsPlayerSpell(id) return known[id] == true end
function IsSpellKnown(id) return known[id] == true end
function issecretvalue() return false end

function CreateFrame()
    sourceFrame = {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function(self, _, callback) self.OnEvent = callback end,
    }
    return sourceFrame
end

C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return nil end,
}
C_Spell = {
    GetSpellCooldownDuration = function(id)
        if durationThrows then error("duration unavailable") end
        if id == 365350 and cooldowns[id] then
            return surgeRemaining == nil and nil or { remaining = surgeRemaining }
        end
    end,
}

local bapi = {
    IsSpellUsable = function(id)
        if readinessUnknown[id] then return nil end
        return usable[id] ~= false
    end,
    IsSpellOnCooldown = function(id)
        if readinessUnknown[id] then return nil end
        return cooldowns[id] == true
    end,
    GetAuraStackAtLeast = function() return false end,
    IsSpellProcced = function() return false end,
    GetClassResourcePoints = function() return 4, 4, "arcane_charges" end,
    GetDisplaySpellID = function(id) return id end,
    AreAurasSecret = function() return combat end,
    IsDurationBelowSeconds = function(duration, seconds)
        if comparisonThrows then error("comparison unavailable") end
        return duration.remaining < seconds
    end,
}
local spellQueue = {
    GetCurrentSpellQueue = function() return rawQueue end,
}
LibStub = function(name)
    if name == "JustAC-SpellQueue" then return spellQueue end
    if name == "JustAC-BlizzardAPI" then return bapi end
end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/Arcane121.lua")
local source = assert(JustACBridgeRecommendationSources.Get("arcane121"))
local STAGE = source._Test.burstStage

local function event(name, spellID)
    sourceFrame.OnEvent(sourceFrame, name, "player", "cast", spellID)
end

local function resetCombat()
    combat = false
    event("PLAYER_REGEN_ENABLED")
    now = now + 20
    targetGUID = "Creature-0-0-0-0-100-0000000001"
    targetExists, targetAttackable, targetDead = true, true, false
    cooldowns, usable, readinessUnknown = {}, {}, {}
    surgeRemaining = 60
    durationThrows, comparisonThrows = false, false
    rawQueue = { 321507, 30451 }
    known[365350] = true
    combat = true
    event("PLAYER_REGEN_DISABLED")
end

local function assertNoTouch(queue)
    for _, spellID in ipairs(queue) do assert(spellID ~= 321507) end
end

-- Merely asking for a recommendation never creates or advances a credential.
resetCombat()
local queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)
assert(source._Test.state.burstStage == nil)
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507
    and source._Test.state.burstStage == nil)
event("UNIT_SPELLCAST_FAILED", 365350)
assert(source._Test.state.burstStage == nil)

-- A successful Surge starts the exact one-step pair. Repeated refreshes and
-- reading the M4 source queue do not advance or reset it; the core later removes
-- both reserved cooldowns from M4.
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
assert(source._Test.state.burstStage == STAGE.EXPECT_TOUCH)
assert(source.GetQueue()[1] == 321507)
assert(source.GetQueue()[1] == 321507)
assert(source.GetPreserveQueue()[1] == 30451)
assert(source._Test.state.burstStage == STAGE.EXPECT_TOUCH)

-- Failed unrelated actions and successful off-GCD observations do not advance
-- the sequence. Failure/interruption of a sequence action cancels it.
event("UNIT_SPELLCAST_FAILED", 30451)
assert(source._Test.state.burstStage == STAGE.EXPECT_TOUCH)
event("UNIT_SPELLCAST_SUCCEEDED", 1295132)
assert(source._Test.state.burstStage == STAGE.EXPECT_TOUCH)
event("UNIT_SPELLCAST_INTERRUPTED", 321507)
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.burstCancelReason:match("INTERRUPTED"))

-- Only authoritative successful casts complete the pair.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
assert(source._Test.state.burstStage == STAGE.EXPECT_TOUCH)
assert(source.GetQueue()[1] == 321507)
event("UNIT_SPELLCAST_SUCCEEDED", 321507)
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.burstCancelReason == "sequence-complete")

-- A wrong successful GCD cancels rather than silently skipping a stage.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
event("UNIT_SPELLCAST_SUCCEEDED", 30451)
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.burstCancelReason == "unexpected-success-30451")

-- Positively unusable and unknowable expected actions both fail closed during
-- the same refresh instead of leaving the machine stuck.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
usable[321507] = false
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)
assertNoTouch(queue)
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
readinessUnknown[321507] = true
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)
assert(source.GetDecisionTrace():match("readiness%-unknown"))

-- The total sequence window is valid immediately below ten seconds and
-- expires exactly at ten seconds.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
local startedAt = now
now = startedAt + 9.999
assert(source.GetQueue()[1] == 321507)
now = startedAt + 10
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.burstCancelReason == "sequence-timeout")

-- PLAYER_TARGET_CHANGED invalidates credentials unconditionally, including a
-- rapid clear/re-target that resolves to the same GUID. Returning to A after
-- switching to B cannot resurrect A's sequence.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.surgeCastAt == nil)
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
targetGUID = "Creature-0-0-0-0-200-0000000002"
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
targetGUID = "Creature-0-0-0-0-100-0000000001"
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)

-- Death, non-attackable targets, lost targets and Surge successes without a
-- valid target all invalidate the sequence.
for _, invalidation in ipairs({ "dead", "unattackable", "missing" }) do
    resetCombat()
    event("UNIT_SPELLCAST_SUCCEEDED", 365350)
    if invalidation == "dead" then targetDead = true
    elseif invalidation == "unattackable" then targetAttackable = false
    else targetExists = false end
    sourceFrame.OnEvent(sourceFrame, "UNIT_FLAGS", "target")
    assert(source._Test.state.burstStage == nil)
    assert(source._Test.state.surgeCastAt == nil)
end
resetCombat()
targetExists = false
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.burstCancelReason == "surge-succeeded-without-valid-target")

-- Direct Touch is the explicit M5 rule whenever Surge is positively not ready;
-- no prior Barrage/Bolt is required.
resetCombat()
cooldowns[365350] = true
queue = source.GetQueue()
assert(queue[1] == 321507)

-- Cooldown duration is intentionally irrelevant, including missing or throwing
-- DurationObject APIs.
for _, remaining in ipairs({ 0, 4, 30, 30.099, 30.1, 31, 60 }) do
    surgeRemaining = remaining
    assert(source.GetQueue()[1] == 321507)
end
surgeRemaining = nil
assert(source.GetQueue()[1] == 321507)
surgeRemaining, durationThrows = 60, true
assert(source.GetQueue()[1] == 321507)
durationThrows, comparisonThrows = false, true
assert(source.GetQueue()[1] == 321507)
comparisonThrows = false
readinessUnknown[365350] = true
assertNoTouch(source.GetQueue())

-- Positively absent or unusable Surge also releases Touch without any setup.
resetCombat()
known[365350] = false
assert(source.GetQueue()[1] == 321507)
resetCombat()
usable[365350] = false
assert(source.GetQueue()[1] == 321507)

-- Target mismatch/death still clears a pending Surge credential. Direct Touch
-- after that is a new current-target decision rather than resurrected evidence.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
targetGUID = "Creature-0-0-0-0-200-0000000002"
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
targetDead = true
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)

-- Combat end always resets target-bound and burst-stage state.
resetCombat()
event("UNIT_SPELLCAST_SUCCEEDED", 365350)
combat = false
event("PLAYER_REGEN_ENABLED")
assert(source._Test.state.burstStage == nil)
assert(source._Test.state.surgeCastAt == nil)
assert(source._Test.state.lastGCDSpellID == nil)

print("arcane 12.1 burst safety tests passed")
