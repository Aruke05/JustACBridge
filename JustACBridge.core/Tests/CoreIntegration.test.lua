-- Lightweight WoW-runtime integration smoke test.
-- Run from repository root with a Lua-compatible CLI.

local now = 100
local speed = 0
local speedSecret = false
local eventFrame
local soundCount = 0
local voiceCount = 0
local classFile = "DEATHKNIGHT"
local specIndex = 3
local testQueue = { 43265, 47541 }
local burstTriggers = {}
local cooldownSpellID
local cooldownEndsAt = 0
local playerAuras = {
    [11426] = {},  -- Ice Barrier
    [235450] = {}, -- Prismatic Barrier
}
local spellCharges = {
    [11426] = 2,
    [235450] = 2,
}
local spellCastTimes = {
    [30451] = 2000, -- Arcane Blast
}
local channeledSpells = {
    [12051] = true, -- Evocation
    [5143] = true,  -- Arcane Missiles
}

local function makeWidget()
    local widget = {}
    local methods = {
        CreateTexture = function() return makeWidget() end,
        CreateFontString = function() return makeWidget() end,
        SetScript = function(self, name, callback) self[name] = callback end,
        GetEffectiveScale = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        IsShown = function(self) return self.shown ~= false end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetText = function(self, text) self.text = text end,
    }
    return setmetatable(widget, {
        __index = function(self, key)
            local method = methods[key] or function() end
            rawset(self, key, method)
            return method
        end,
    })
end

UIParent = makeWidget()
SlashCmdList = {}
C_Item = {
    GetItemNameByID = function(id) return "Item " .. id end,
    GetItemIconByID = function() return 134400 end,
}
C_Spell = {
    GetSpellInfo = function(id)
        return { name = "Spell " .. id, iconID = 134400, castTime = spellCastTimes[id] or 0 }
    end,
    GetSpellCooldown = function(id)
        if id ~= cooldownSpellID then
            return { startTime = 0, duration = 0, modRate = 1 }
        end
        return { startTime = cooldownEndsAt - 2, duration = 2, modRate = 1 }
    end,
    GetSpellCharges = function(id)
        local current = spellCharges[id]
        if current == nil then return nil end
        return {
            currentCharges = current,
            maxCharges = 2,
            cooldownStartTime = 0,
            cooldownDuration = 0,
            chargeModRate = 1,
        }
    end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return playerAuras[id] end,
}
C_TTSSettings = {
    GetVoiceOptionID = function() return 1 end,
}
C_VoiceChat = {
    SpeakText = function() voiceCount = voiceCount + 1 end,
}

function CreateFrame()
    local frame = makeWidget()
    if not eventFrame then eventFrame = frame end
    return frame
end
function UnitClass() return classFile, classFile end
function GetSpecialization() return specIndex end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function GetUnitSpeed() return speed end
function GetTime() return now end
function time() return 100000 end
function IsPlayerSpell() return true end
function issecretvalue(value) return speedSecret and value == speed end
function PlaySound() soundCount = soundCount + 1 end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/JustAC.lua")

assert(JustACBridgeRecommendationSources.Register("test", {
    name = "Test Source",
    GetQueue = function() return testQueue end,
    GetSpellHotkey = function(id) return id == 43265 and "1" or "2" end,
    GetDisplaySpellID = function(id) return id end,
    IsSpellUsable = function() return true end,
    IsSpellProcced = function() return false end,
    IsChanneled = function(id) return channeledSpells[id] == true end,
    IsConfirmedOutOfRange = function() return false end,
    GetDetectedBurstTriggers = function() return burstTriggers end,
}))

dofile("JustACBridge.core/Policies/Registry.lua")
dofile("JustACBridge.core/Policies/Mage.lua")
dofile("JustACBridge.core/Policies/Mage/Arcane.lua")
dofile("JustACBridge.core/Policies/Mage/Fire.lua")
dofile("JustACBridge.core/Policies/Mage/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Blood.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Unholy.lua")
dofile("JustACBridge.core/Trackers/GroundEffects.lua")
dofile("JustACBridge.core/JustACBridge.lua")

eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(JustACBridge.GetRecommendationSource().id == "test")
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)

-- Midnight removed Evocation's Siphon Storm setup role.  Even if an old
-- JustAC profile still detects it as a burst trigger, the 12.0 Arcane policy
-- must remove it from the burst set. M5 remains an exact first recommendation,
-- while the mechanics-safe M4 still rejects its stationary channel.
classFile, specIndex = "MAGE", 1
burstTriggers = { 12051 }
testQueue = { 12051, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
JustACBridgeDB.reserveOverrides.MAGE_1 = { include = { [12051] = true } }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
JustACBridgeDB.reserveOverrides.MAGE_1 = nil
burstTriggers = {}

-- Mage barriers are policy-driven maintenance actions rather than guessed
-- encounter timing. Exact aura absence promotes the ready, bound barrier to
-- both M5 and M4; an active aura leaves the JustAC order untouched.
playerAuras[235450] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 235450)
assert(JustACBridge.GetLosslessRecommendation().maintenanceBuff == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 235450)
playerAuras[235450] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)

-- Keep one charge for the player's manual defensive. If the absorb breaks
-- with only that reserved charge available, continue the ordinary queues.
playerAuras[235450] = nil
spellCharges[235450] = 1
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
spellCharges[235450] = 2
playerAuras[235450] = {}

-- M4 must remain safe to hold through movement/mechanics even during a
-- momentary stationary frame. It skips the reserved Touch, the Missiles
-- channel, the Arcane Blast hardcast and the facing-dependent Arcane Orb,
-- preserving JustAC's remaining order and selecting Arcane Explosion.
testQueue = { 321507, 5143, 30451, 153626, 1449, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 1449)

-- Orb remains available to M5 for manual aiming but never leaks into M4.
testQueue = { 153626, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)

-- The shortcut that normally copies a non-reserved M5 action into M4 must not
-- leak a stationary hardcast into the hold-safe action.
testQueue = { 30451, 1449, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 1449)

-- Death Grip is encounter utility rather than a Frost damage action. A stale
-- queue/gap-closer injection must be skipped by both exported actions.
classFile, specIndex = "DEATHKNIGHT", 2
testQueue = { 49576, 49184 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
local frostLossless = JustACBridge.GetLosslessRecommendation()
local frostPreserve = JustACBridge.GetPreserveBurstRecommendation()
assert(frostLossless.spellID == 49184 and frostLossless.rotationFallback == true)
assert(frostPreserve.spellID == 49184)

classFile, specIndex = "MAGE", 1
testQueue = { 12051, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()

-- Live telemetry has not proved a reliable way to bind Overpowered Missiles
-- to the exact channel. The conservative 12.1 policy therefore protects every
-- Arcane Missiles cast instead of risking an incorrect early clip.
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "missiles-1", 5143)
assert(JustACBridge.GetPlayerCastState().channelBlocksInput == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "missiles-1", 5143)

-- No normal recommendation must never leave either trigger empty.  This is a
-- core rule, not a Frost Mage exception: every independently maintained
-- class/spec policy must reach its own final fallback through the same path.
local fallbackCases = {
    { class = "MAGE", spec = 1, spell = 44425 },
    { class = "MAGE", spec = 2, spell = 2948 },
    { class = "MAGE", spec = 3, spell = 30455 },
    { class = "DEATHKNIGHT", spec = 1, spell = 50842 },
    { class = "DEATHKNIGHT", spec = 2, spell = 49184 },
    { class = "DEATHKNIGHT", spec = 3, spell = 47541 },
}
for _, case in ipairs(fallbackCases) do
    classFile, specIndex = case.class, case.spec
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    testQueue = {}
    JustACBridge.Refresh()
    local emptyQueueFallback = JustACBridge.GetCurrentRecommendation()
    assert(emptyQueueFallback.spellID == case.spell
        and emptyQueueFallback.finalFallback == true,
        ("final fallback failed for %s/%s: got %s")
            :format(case.class, case.spec, tostring(emptyQueueFallback.spellID)))
end
classFile, specIndex = "DEATHKNIGHT", 3
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
testQueue = { 43265, 47541 }
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)

-- Cooldown readiness is likewise a core selector rule for every class/spec.
-- A stale first queue entry must advance instead of being sent forever.
cooldownSpellID = 43265
cooldownEndsAt = now + 2
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 47541)
cooldownSpellID = nil
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 43265)
JustACBridge.Refresh()
local active = JustACBridge.GetGroundEffects()
assert(#active == 1 and active[1].expiresAt == 110)
local fallback = JustACBridge.GetCurrentRecommendation()
assert(fallback.spellID == 47541 and fallback.groundFallback == true)

now = 110
eventFrame.OnUpdate(eventFrame, 0.1)
assert(#JustACBridge.GetGroundEffects() == 0)
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
assert(soundCount == 1)
assert(voiceCount == 1)

-- A movement-safe recommendation can still be rejected by the game at cast
-- time.  Three rapid failures must temporarily advance both selectors instead
-- of hammering the same dead action forever.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
-- WoW may emit several FAILED events for one physical key pulse.  A shared
-- cast GUID represents one attempt and must not trip the circuit breaker.
for _ = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "same-cast", 43265)
end
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
now = 120
for index = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "cast-fail-" .. index, 43265)
end
JustACBridge.Refresh()
local failureFallback = JustACBridge.GetCurrentRecommendation()
assert(failureFallback.spellID == 47541 and failureFallback.failureFallback == true)

now = 121.1
JustACBridge.Refresh()
local restored = JustACBridge.GetCurrentRecommendation()
assert(restored.spellID == 43265,
    ("primary not restored: spell=%s failureFallback=%s")
        :format(tostring(restored.spellID), tostring(restored.failureFallback)))

-- A specialization's final fallback must never enter the failure circuit
-- breaker.  It has no safer action to advance to, so repeated game-side
-- failures must leave it selected as the normal queue action.
testQueue = { 47541 }
JustACBridge.Refresh()
for index = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player",
        "fallback-fail-" .. index, 47541)
end
JustACBridge.Refresh()
local finalFallback = JustACBridge.GetCurrentRecommendation()
assert(finalFallback.spellID == 47541
    and finalFallback.failureFallback ~= true
    and finalFallback.emergencyMovementFallback ~= true)
testQueue = { 43265, 47541 }

-- Midnight can report speed as secret and emit START/STOP movement events in
-- the same frame while a stationary channel resists movement.  Ray of Frost
-- is explicitly protected by the Frost policy and must not be clipped merely
-- because movement intent was reported during its channel.
classFile = "MAGE"
specIndex = 3
testQueue = { 30455 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
playerAuras[11426] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 11426)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 11426)
spellCharges[11426] = 1
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30455)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30455)
spellCharges[11426] = 2
playerAuras[11426] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30455)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30455)
speedSecret = true
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "channel-1", 205021)
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
local movingChannel = JustACBridge.GetPlayerCastState()
assert(movingChannel.isMoving == true and movingChannel.channelBlocksInput == true,
    ("Ray protection failed: moving=%s blocking=%s channel=%s")
        :format(tostring(movingChannel.isMoving), tostring(movingChannel.channelBlocksInput),
            tostring(movingChannel.channelSpellID)))

now = 121.2
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.IsPlayerMoving() == true)

now = 121.5
JustACBridge.Refresh()
assert(JustACBridge.IsPlayerMoving() == false)

print("core integration tests passed")
