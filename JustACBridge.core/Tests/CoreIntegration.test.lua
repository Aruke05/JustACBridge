-- Lightweight WoW-runtime integration smoke test.
-- Run from repository root with a Lua-compatible CLI.

local now = 100
local speed = 0
local speedSecret = false
local auraSecret = false
local secretAuraValue = {}
local eventFrame
local namedFrames = {}
local soundCount = 0
local voiceCount = 0
local spokenVoiceID
local spokenText
local scheduledTimers = {}
local reloadCount = 0
local inCombat = false
local classFile = "DEATHKNIGHT"
local specIndex = 3
local testQueue = { 43265, 47541 }
local testPreserveQueue
local burstTriggers = {}
local burstCues = {}
local highlightSpellID
local targetWithin5
local cooldownSpellID
local cooldownEndsAt = 0
local effectiveSpellOverrides = {}
local unlearnedSpells = {}
local unusableSpells = {}
local unboundSpells = {}
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
    [1241462] = 2000, -- Arcane Pulse (12.1 talent replacement)
}
local channeledSpells = {
    [12051] = true, -- Evocation
    [5143] = true,  -- Arcane Missiles
}

local function makeWidget()
    local widget = {}
    local methods = {
        CreateTexture = function() return makeWidget() end,
        CreateFontString = function(self)
            local child = makeWidget()
            self.lastFontString = child
            return child
        end,
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
    GetVoiceOptionID = function() return 999 end,
}
C_VoiceChat = {
    GetTtsVoices = function() return { { voiceID = 7, name = "Test Voice" } } end,
    SpeakText = function(voiceID, text)
        spokenVoiceID = voiceID
        spokenText = text
        voiceCount = voiceCount + 1
    end,
}
C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        scheduledTimers[#scheduledTimers + 1] = timer
        return timer
    end,
    After = function(_, callback) callback() end,
}

function CreateFrame(_, name)
    local frame = makeWidget()
    if not eventFrame then eventFrame = frame end
    if name then namedFrames[name] = frame end
    return frame
end
function UnitClass() return classFile, classFile end
function GetSpecialization() return specIndex end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function GetUnitSpeed() return speed end
function UnitAffectingCombat() return inCombat end
function GetTime() return now end
function time() return 100000 end
function IsPlayerSpell(id) return unlearnedSpells[id] ~= true end
function issecretvalue(value)
    return (speedSecret and value == speed)
        or (auraSecret and value == secretAuraValue)
end
function PlaySound() soundCount = soundCount + 1 end
function ReloadUI() reloadCount = reloadCount + 1 end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/JustAC.lua")

assert(JustACBridgeRecommendationSources.Register("test", {
    name = "Test Source",
    GetQueue = function() return testQueue end,
    GetPreserveQueue = function() return testPreserveQueue or testQueue end,
    GetSpellHotkey = function(id)
        if unboundSpells[id] then return nil end
        return id == 43265 and "1" or "2"
    end,
    GetDisplaySpellID = function(id) return id end,
    GetEffectiveSpellID = function(id) return effectiveSpellOverrides[id] or id end,
    IsSpellUsable = function(id) return unusableSpells[id] ~= true end,
    IsSpellOnCooldown = function(id)
        return id == cooldownSpellID and cooldownEndsAt > now
    end,
    IsSpellProcced = function() return false end,
    IsChanneled = function(id) return channeledSpells[id] == true end,
    IsConfirmedOutOfRange = function() return false end,
    IsBurstCue = function(id) return burstCues[id] == true end,
    GetHighlightCastSpell = function() return highlightSpellID end,
    IsTargetWithin = function(yards)
        if yards == 5 then return targetWithin5 end
        return nil
    end,
    GetDetectedBurstTriggers = function() return burstTriggers end,
}))

-- DK-owned sources remain available only as explicit experimental choices.
-- Auto mode must resolve every DK specialization through JustAC; because this
-- harness intentionally has no usable JustAC runtime, selection then falls
-- through to the first available test source rather than either DK mock.
for _, sourceID in ipairs({ "frostdk121", "unholydk121" }) do
    assert(JustACBridgeRecommendationSources.Register(sourceID, {
        name = sourceID,
        GetQueue = function() return { 999999 } end,
    }))
end

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
dofile("JustACBridge.core/Trackers/CooldownReady.lua")
dofile("JustACBridge.core/JustACBridge.lua")

eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(JustACBridge.GetRecommendationSource().id == "test")
classFile, specIndex = "DEATHKNIGHT", 2
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(JustACBridge.GetRecommendationSource().id == "test")
classFile, specIndex = "DEATHKNIGHT", 3
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(JustACBridge.GetRecommendationSource().id == "test")
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
-- Opening the log before diagnostics have ever produced a line must display
-- an empty state rather than taking the length of a nil SavedVariables field.
SlashCmdList.JUSTACBRIDGE("debug")

-- A self-owned source may prepend a proven action which is not present on the
-- player's action bars. The desktop cannot execute an unbound primary, so it
-- must never consume M5; advance to a bound raw-queue action instead. This is
-- the exact failure mode seen when Frost selected Comet Storm (153595) while
-- the spell was not bound.
classFile, specIndex = "MAGE", 3
testQueue = { 153595, 30455 }
unboundSpells[153595] = true
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30455)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30455)
unboundSpells[153595] = nil

-- 12.1 Arcane owns an exact two-spell preserve set. Stale/custom JustAC Burst
-- Trigger entries (including ordinary Barrage) must not silently add more M4
-- holds. Evocation is not one of the two reserved actions, so both outputs
-- keep it; an explicit player override may still reserve it.
classFile, specIndex = "MAGE", 1
burstTriggers = { 12051, 44425 }
testQueue = { 12051, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 12051)
JustACBridgeDB.reserveOverrides.MAGE_1 = { include = { [12051] = true } }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
JustACBridgeDB.reserveOverrides.MAGE_1 = nil
burstTriggers = {}
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")

-- Prismatic Barrier is a deliberate M4-only defensive insertion. It may not
-- steal M5's damage GCD, and it is injected only while its live aura is
-- explicitly missing and the spell is currently usable.
playerAuras[235450] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 235450)
playerAuras[235450] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 12051)
playerAuras[235450] = nil
unusableSpells[235450] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 12051)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 12051)
unusableSpells[235450] = nil
playerAuras[235450] = {}

-- A custom M5 source may own a different queue, while M4 must consume its
-- explicit untouched preserve queue. The policy-level Touch -> Surge sequence
-- gate applies even to source-owned and raw JustAC queues, exactly like the DK
-- Pillar -> Frostwyrm gate.
testQueue = { 365350, 30451 }
testPreserveQueue = { 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "touch-1", 321507)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 365350)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-1", 365350)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)
testPreserveQueue = nil

-- 12.1 Arcane M4 is the same live rotation as M5 minus the two reserved
-- cooldowns. After skipping Touch it must keep the owned Missiles action;
-- Arcane Explosion remains excluded from both outputs.
testQueue = { 321507, 5143, 30451, 153626, 1449, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
assert(JustACBridge.GetLosslessRecommendation().offGCD == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 5143)
assert(JustACBridge.GetPreserveBurstRecommendation().offGCD == false)

-- Stationary Arcane M5 and M4 both allow Orb when no directional delay is
-- active.
testQueue = { 153626, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 153626)

-- While moving, neither held key may guess the facing-dependent Orb. Both
-- skip it. After an ordinary stop M5 resumes immediately, while M4 requires
-- two continuous stationary seconds.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 1.99
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 0.01
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 153626)

-- A server-confirmed Blink or either Shimmer form starts an independent
-- two-second Orb delay for both keys. This remains exact even if no ordinary
-- movement-stop transition is emitted by the teleport.
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "blink", 1953)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 1.99
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 0.01
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 153626)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "shimmer", 1294067)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 2.0
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 153626)
now = 100

-- Midnight 12.1 movement exceptions are allowed only while their exact live
-- requirements are observable. Slipstream plus Clearcasting permits the
-- Missiles channel while moving; either missing condition fails closed.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
testQueue = { 5143, 44425 }
playerAuras[263725] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 5143)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "moving-missiles", 5143)
assert(JustACBridge.GetPlayerCastState().channelBlocksInput == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "moving-missiles", 5143)
unlearnedSpells[236457] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
unlearnedSpells[236457] = nil
playerAuras[263725] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)

-- Presence of Mind's player aura is sufficient and spell-specific evidence
-- that Arcane Blast is instant. Losing the aura immediately restores the
-- ordinary moving fallback without relying on an action-button glow.
testQueue = { 30451, 44425 }
playerAuras[205025] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30451)
playerAuras[205025] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
playerAuras[205025] = secretAuraValue
auraSecret = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
auraSecret = false
playerAuras[205025] = nil
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")

-- JustAC Stage G keeps Blizzard's primary action at position 1 and surfaces an
-- exact, called-for burst cue at position 2. M5 must honor that source-owned
-- signal rather than losing it behind the primary forever. M4 still excludes
-- the detected burst trigger and keeps the ordinary hold-safe action. During a
-- protected Missiles channel the cue may remain exported, but the protocol's
-- busy bit prevents the desktop from sending it; it remains selected after the
-- channel ends and is then executable.
burstTriggers = { 365350 }
burstCues[365350] = true
testQueue = { 30451, 365350, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "touch-cue", 321507)
JustACBridge.Refresh()
local surgeCue = JustACBridge.GetLosslessRecommendation()
assert(surgeCue.spellID == 365350 and surgeCue.sourceBurstCue == true
    and surgeCue.sourceQueueIndex == 2)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "missiles-2", 5143)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 365350)
assert(JustACBridge.GetPlayerCastState().channelBlocksInput == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "missiles-2", 5143)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 365350)
burstCues[365350] = nil
burstTriggers = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30451)

-- Arcane's explicit exception shares stationary hardcasts between M5 and M4.
testQueue = { 30451, 1449, 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30451)

-- Midnight 12.1 excludes Arcane Explosion from both automatic outputs. A
-- transient Assisted Combat primary with no later action leaves both empty;
-- manual casting is outside the Bridge and remains available.
testQueue = { 1449 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

-- Arcane Pulse replaces the Arcane Explosion action-bar button.  The 12.1
-- exclusion is deliberately matched against the effective spell, so a raw
-- Assisted Combat queue value of 1449 must not suppress the valid Pulse.  The
-- exported spell ID is also the effective one, preventing Windows M5 from
-- applying Arcane Explosion's 100 ms stability delay to Pulse.
effectiveSpellOverrides[1449] = 1241462
testQueue = { 1449, 44425 }
JustACBridge.Refresh()
local pulseLossless = JustACBridge.GetLosslessRecommendation()
local pulsePreserve = JustACBridge.GetPreserveBurstRecommendation()
assert(pulseLossless.spellID == 1241462 and pulseLossless.sourceSpellID == 1449)
assert(pulsePreserve.spellID == 1241462 and pulsePreserve.sourceSpellID == 1449)
effectiveSpellOverrides[1449] = nil

-- Prismatic Bolt dynamically upgrades Arcane Blast and is instant. Resolve
-- the active action before movement classification so M4 may use the proc,
-- while retaining the raw queue value for failure suppression/diagnostics.
effectiveSpellOverrides[30451] = 1295939
testQueue = { 30451 }
JustACBridge.Refresh()
local boltLossless = JustACBridge.GetLosslessRecommendation()
local boltPreserve = JustACBridge.GetPreserveBurstRecommendation()
assert(boltLossless.spellID == 1295939 and boltLossless.sourceSpellID == 30451)
assert(boltPreserve.spellID == 1295939 and boltPreserve.sourceSpellID == 30451)

-- Spellcast failures report the transformed ID. Suppression must still attach
-- to the raw queue entry, otherwise a failed instant Bolt would be retried
-- forever as Arcane Blast.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
for index = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player",
        "bolt-fail-" .. index, 1295939)
end
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
now = 101.1
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 1295939)
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
effectiveSpellOverrides[30451] = nil
now = 100

-- Death Grip is encounter utility rather than a damage action. A stale queue
-- or gap-closer injection must be skipped by both outputs on every DK spec;
-- pulling and enemy positioning always remain manual player decisions.
for _, case in ipairs({
    { spec = 1, fallback = 50842 },
    { spec = 2, fallback = 49184 },
    { spec = 3, fallback = 47541 },
}) do
    classFile, specIndex = "DEATHKNIGHT", case.spec
    testQueue = { 49576, case.fallback }
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    JustACBridge.Refresh()
    local lossless = JustACBridge.GetLosslessRecommendation()
    local preserve = JustACBridge.GetPreserveBurstRecommendation()
    assert(lossless.spellID == case.fallback and lossless.rotationFallback == true)
    assert(preserve.spellID == case.fallback)
end

classFile, specIndex = "DEATHKNIGHT", 2
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")

-- Frostwyrm's Fury is never allowed to precede Pillar of Frost. The strict
-- sequence gate uses successful player casts, not cooldown guesses. It also
-- consumes the proof after Fury and clears it when combat ends.
testQueue = { 279302, 51271, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 51271)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "pillar-1", 51271)
testQueue = { 279302, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 279302)

-- A successful Pillar must not become a permanent token. Once the conservative
-- 10-second event window expires and no live aura is observable, Fury waits
-- for the next Pillar instead of firing later in its cooldown cycle.
now = 110.1
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "pillar-1b", 51271)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 279302)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "wyrm-1", 279302)
JustACBridge.Refresh()
local raiseAfterWyrm = JustACBridge.GetLosslessRecommendation()
assert(raiseAfterWyrm.spellID == 46585
    and raiseAfterWyrm.policyCastFollowup == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "raise-1", 46585)

-- Chosen of Frostbrood changes the live button to the exact recall override.
-- That second release belongs wholly to JustAC and must bypass the first-cast
-- Pillar gate without using a guessed timer or inferred talent state.
effectiveSpellOverrides[279302] = 1265384
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 1265384)
assert(JustACBridge.GetLosslessRecommendation().sourceSpellID == 279302)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "recall-1", 1265384)

effectiveSpellOverrides[279302] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "pillar-2", 51271)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 279302)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "wyrm-2", 279302)
cooldownSpellID = 46585
cooldownEndsAt = now + 20
testQueue = { 49184 }
JustACBridge.Refresh()
local cooldownRaiseFallback = JustACBridge.GetLosslessRecommendation()
assert(cooldownRaiseFallback.spellID == 49184
    and cooldownRaiseFallback.policyCastFollowup ~= true)
cooldownSpellID = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetLosslessRecommendation().policyCastFollowup ~= true)
eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
now = 100

-- An explicitly observable live Pillar aura recovers the ordering proof after
-- reload/zone transitions; secret or missing aura data still fails closed.
testQueue = { 279302, 49184 }
playerAuras[51271] = secretAuraValue
auraSecret = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
auraSecret = false
playerAuras[51271] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 279302)
playerAuras[51271] = nil

-- Frost M4 treats JustAC's actual queue as the only authority for ranged
-- movement filler. A queued Howling Blast passes through, but highlight/proc
-- data and the specialization fallback cannot invent one when it is absent.
testQueue = { 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

testQueue = { 51271, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 51271)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

highlightSpellID = 49184
testQueue = { 51271 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 51271)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

testQueue = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetLosslessRecommendation().finalFallback == true)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

-- M5 uses the same "no JustAC Howling Blast, keep running" rule only after
-- JustAC's range probes positively prove that the target is beyond melee.
targetWithin5 = false
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

testQueue = { 51271, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

testQueue = { 196770 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

testQueue = { 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

testQueue = {}
targetWithin5 = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetLosslessRecommendation().finalFallback == true)

testQueue = { 196770 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 196770)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 196770)
targetWithin5 = nil
highlightSpellID = nil

-- Frost owns an exact M4 preserve set. Resource recovery and Raise Dead are
-- ordinary JustAC actions during a short tail, even if stale/custom JustAC
-- Burst Trigger settings still classify them as burst. The synchronized
-- Pillar/Breath/Fury/Reaper suite remains held for the next pull.
burstTriggers = { 47568, 46585, 196770 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
testQueue = { 47568, 196770, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 47568)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 47568)

testQueue = { 46585, 196770, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 46585)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 46585)

JustACBridgeDB.reserveOverrides.DEATHKNIGHT_2 = { include = { [46585] = true } }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 196770)
JustACBridgeDB.reserveOverrides.DEATHKNIGHT_2 = nil
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")

testQueue = { 51271, 152279, 1249658, 279302, 439843, 196770 }
JustACBridge.Refresh()
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 196770)
burstTriggers = {}
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")

-- Midnight 12.1 Unholy owns an exact Army + Dark Transformation preserve
-- set. Putrefy is rotational and must pass through from JustAC even if a stale
-- Burst Trigger still calls it (or removed legacy cooldowns) burst. Ground-
-- targeted Death and Decay remains excluded because M4 cannot aim it.
classFile, specIndex = "DEATHKNIGHT", 3
burstTriggers = { 207289, 49206, 288853, 390279, 1247378 }
testQueue = { 343294, 42650, 47541 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 343294)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 343294)

testQueue = { 42650, 1233448, 1247378, 43265, 47541 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 42650)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 1247378)

testQueue = { 207289, 49206, 288853, 390279, 1247378, 47541 }
JustACBridge.Refresh()
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 207289)
burstTriggers = {}
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")

classFile, specIndex = "MAGE", 1
testQueue = { 12051, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()

-- Live telemetry has not proved a reliable way to bind Overpowered Missiles
-- to the exact channel. The conservative 12.1 policy therefore protects every
-- Arcane Missiles cast instead of risking an incorrect early clip.
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "missiles-1", 5143)
assert(JustACBridge.GetPlayerCastState().channelBlocksInput == true)
-- Triggered START events must not reopen the bridge before the authoritative
-- channel stop arrives. This used to permit a held key to clip Missiles.
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_START", "player", "triggered-during-missiles", 999001)
local missilesAfterTriggeredStart = JustACBridge.GetPlayerCastState()
assert(missilesAfterTriggeredStart.isChanneling == true
    and missilesAfterTriggeredStart.channelSpellID == 5143
    and missilesAfterTriggeredStart.channelBlocksInput == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "missiles-1", 5143)

-- M5 keeps a bound specialization fallback when no normal recommendation
-- exists. Frost DK M4 deliberately opts out above because it is a literal
-- filtered JustAC queue and must not invent a ranged filler.
local fallbackCases = {
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
-- Arcane deliberately has no invented final fallback. With no source action
-- and no missing barrier maintenance, both outputs remain empty.
classFile, specIndex = "MAGE", 1
playerAuras[235450] = {}
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
testQueue = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
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
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 43265)
local dndCooldownRecord = JustACBridgeCooldownReadyTracker._Test.GetSpellRecord(43265)
assert(dndCooldownRecord and dndCooldownRecord.monitoring
    and #scheduledTimers == 1 and scheduledTimers[1].delay == 30)
JustACBridge.Refresh()
local active = JustACBridge.GetGroundEffects()
assert(#active == 1 and active[1].expiresAt == 110)
local fallback = JustACBridge.GetCurrentRecommendation()
assert(fallback.spellID == 47541 and fallback.groundFallback == true)

now = 110
eventFrame.OnUpdate(eventFrame, 0.1)
assert(#JustACBridge.GetGroundEffects() == 0)
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
assert(soundCount == 0)
assert(voiceCount == 0)

-- The old ten-second ground expiry is silent. The explicit 30-second recharge
-- timer owns the alert and does not depend on secret cooldown widget updates.
now = 130
scheduledTimers[1].callback()
eventFrame.OnUpdate(eventFrame, 0.01)
assert(soundCount == 1)
assert(voiceCount == 1)
assert(spokenVoiceID == 7)
assert(spokenText == "枯萎凋零1")
assert(namedFrames.JustACBridgeGroundAlertFrame.lastFontString.text == "枯萎凋零1")

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

-- /jacb flush must invoke ReloadUI synchronously from the slash-command
-- hardware-event context. A timer-delayed call silently failed in game and
-- left the diagnostic log only in memory.
SlashCmdList.JUSTACBRIDGE("debug on")
SlashCmdList.JUSTACBRIDGE("flush")
assert(reloadCount == 1)
assert(type(JustACBridgeExport.debugLog) == "string"
    and JustACBridgeExport.debugLog:find("DEBUG enabled=true", 1, true))

print("core integration tests passed")
