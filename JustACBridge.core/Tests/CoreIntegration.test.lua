dofile("JustACBridge.core/Framework/ActionSequence.lua")
dofile("JustACBridge.core/Framework/TargetLease.lua")
dofile("JustACBridge.core/Framework/ResourcePreparation.lua")
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
local movementFallbackProofs = {}
local movementFallbackProofThrows = false
local highlightSpellID
local targetWithin5
local cooldownSpellID
local cooldownEndsAt = 0
local unknownCooldownSpells = {}
local unknownCooldownThresholdSpells = {}
local effectiveSpellOverrides = {}
local unlearnedSpells = {}
local unusableSpells = {}
local unboundSpells = {}
local targetGUID = "Creature-0-0-0-0-100-0000000001"
local targetExists = true
local targetAttackable = true
local targetDead = false
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
        CreateTexture = function(self)
            local child = makeWidget()
            self.textures = rawget(self, "textures") or {}
            self.textures[#self.textures + 1] = child
            return child
        end,
        SetColorTexture = function(self, r) self.bit = r end,
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
        SetCooldownFromDurationObject = function(self, duration)
            self.shown = duration.active
        end,
        SetCooldown = function(self) self.shown = false end,
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
    GetSpellCooldownDuration = function(id)
        if id == cooldownSpellID and cooldownEndsAt > now then
            return { remaining = cooldownEndsAt - now }
        end
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
function UnitExists(unit) return unit == "target" and targetExists end
function UnitCanAttack(_, unit) return unit == "target" and targetAttackable end
function UnitIsDeadOrGhost(unit) return unit == "target" and targetDead end
function UnitGUID(unit) return unit == "target" and targetExists and targetGUID or nil end
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
        if unboundSpells[id] then return "" end
        return id == 43265 and "1" or "2"
    end,
    GetDisplaySpellID = function(id) return id end,
    GetEffectiveSpellID = function(id) return effectiveSpellOverrides[id] or id end,
    IsSpellUsable = function(id) return unusableSpells[id] ~= true end,
    IsSpellUsableStrict = function(id)
        return JustACBridgeRecommendationSources.Get("justac", false).IsSpellUsableStrict(id)
    end,
    IsSpellOnCooldown = function(id)
        if unknownCooldownSpells[id] then return nil end
        return id == cooldownSpellID and cooldownEndsAt > now
    end,
    IsSpellCooldownRemainingAbove = function(id, seconds)
        if unknownCooldownThresholdSpells[id] then return nil end
        if unknownCooldownSpells[id] then return nil end
        if id ~= cooldownSpellID or cooldownEndsAt <= now then return false end
        return cooldownEndsAt - now >= seconds
    end,
    IsSpellProcced = function() return false end,
    IsChanneled = function(id) return channeledSpells[id] == true end,
    IsConfirmedOutOfRange = function() return false end,
    IsBurstCue = function(id) return burstCues[id] == true end,
    IsMovementFallbackAllowed = function(id)
        if movementFallbackProofThrows then error("movement proof unavailable") end
        return movementFallbackProofs[id], movementFallbackProofs[id] == true
            and "test-proof" or "test-not-proven"
    end,
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

-- Hunter 12.1 sources are automatic for all three specializations.
for _, sourceID in ipairs({
    "bmhunter121", "mmhunter121", "survivalhunter121",
}) do
    assert(JustACBridgeRecommendationSources.Register(sourceID, {
        name = sourceID,
        GetQueue = function() return testQueue end,
        GetPreserveQueue = function() return testQueue end,
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
dofile("JustACBridge.core/Policies/Hunter.lua")
dofile("JustACBridge.core/Policies/Hunter/BeastMastery.lua")
dofile("JustACBridge.core/Policies/Hunter/Marksmanship.lua")
dofile("JustACBridge.core/Policies/Hunter/Survival.lua")
dofile("JustACBridge.core/Trackers/GroundEffects.lua")
dofile("JustACBridge.core/Trackers/CooldownReady.lua")
dofile("JustACBridge.core/Framework/QueueTiming.lua")
dofile("JustACBridge.core/JustACBridge.lua")

eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(JustACBridge.GetRecommendationSource().id == "test")

-- Input timing must not change either recommendation, reservations or source.
-- Read the current CVar each frame, including a change while the gate remains
-- closed (it must still reach diagnostics/SavedVariables).
do
    local originalTime = now
    local firstID = JustACBridgeExport.first.spellID
    local secondID = JustACBridgeExport.reserveBurst.spellID
    assert(firstID == 43265 and secondID == 47541)
    local function checkPixel(ready, busyMask)
        local cells = namedFrames.JustACBridgePixelFrame.textures
        assert(#cells == 576)
        local bytes = {}
        for i = 1, 72 do
            local value = 0
            for bit = 1, 8 do value = value * 2 + cells[(i-1)*8 + bit].bit end
            bytes[i] = value
        end
        assert(bytes[64] % 2 == (ready and 1 or 0))
        assert(bytes[4] == 3 and bytes[70] == 69 and bytes[72] == 68)
        if busyMask then assert(math.floor(bytes[7] / busyMask) % 2 == 1) end
        local a, b, c = 0, 0, 0
        for i = 1, 66 do
            a = (a + bytes[i]) % 255
            b = (b + a) % 255
            c = (c * 33 + bytes[i]) % 256
        end
        assert(bytes[67] == a and bytes[68] == b and bytes[69] == c)
    end
    local gameWindow = "400"
    C_CVar = { GetCVar = function() return gameWindow end }
    cooldownSpellID, cooldownEndsAt = 61304, 101
    now = 100.875 -- 125ms, outside old and new windows
    JustACBridge.Refresh()
    assert(not JustACBridgeExport.queueReady)
    assert(JustACBridgeExport.queueCommitWindowMs == 120)
    checkPixel(false)
    assert(JustACBridgeExport.gameSpellQueueWindowMs == 400)
    gameWindow = "80"
    JustACBridge.Refresh()
    assert(not JustACBridgeExport.queueReady)
    assert(JustACBridgeExport.queueCommitWindowMs == 80)
    assert(JustACBridgeExport.gameSpellQueueWindowMs == 80)
    now = 100.9 -- 100ms: used to send too early with game SQW=80
    JustACBridge.Refresh()
    assert(not JustACBridgeExport.queueReady)
    checkPixel(false)
    now = 100.925 -- 75ms: fits game SQW
    JustACBridge.Refresh()
    assert(JustACBridgeExport.queueReady)
    checkPixel(true)
    assert(JustACBridgeExport.first.spellID == firstID)
    assert(JustACBridgeExport.reserveBurst.spellID == secondID)
    -- A narrower gate does not relax an existing channel/cast busy flag.
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_START", "player", "cast-test", 30451)
    JustACBridge.Refresh()
    assert(JustACBridgeExport.isCasting and JustACBridgeExport.queueReady)
    checkPixel(true, 128)
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_STOP", "player", "cast-test", 30451)
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "channel-test", 5143)
    JustACBridge.Refresh()
    assert(JustACBridgeExport.isChanneling)
    checkPixel(true, 64)
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "channel-test", 5143)
    gameWindow = "0"
    JustACBridge.Refresh()
    assert(not JustACBridgeExport.queueReady and JustACBridgeExport.queueCommitWindowMs == 0)
    checkPixel(false)
    now = 101
    JustACBridge.Refresh()
    assert(JustACBridgeExport.queueReady)
    checkPixel(true)
    C_CVar, cooldownSpellID, cooldownEndsAt, now = nil, nil, 0, originalTime
    JustACBridge.Refresh()
    assert(JustACBridgeExport.queueCommitWindowMs == 120)
    assert(JustACBridgeExport.gameSpellQueueWindowMs == nil)
    assert(JustACBridgeExport.queueTimingReason == "cvar-unavailable")
end

classFile, specIndex = "DEATHKNIGHT", 2
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(JustACBridge.GetRecommendationSource().id == "test")
classFile, specIndex = "DEATHKNIGHT", 3
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(JustACBridge.GetRecommendationSource().id == "test")
for index, sourceID in ipairs({
    "bmhunter121", "mmhunter121", "survivalhunter121",
}) do
    classFile, specIndex = "HUNTER", index
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(JustACBridge.GetRecommendationSource().id == sourceID)
end
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
-- A source/JustAC queue that already ranks capped-Salvo Barrage first must be
-- consumed in that order; the core may not insert or promote Arcane Blast.
testQueue = { 44425, 5143, 30451 }
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
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
-- explicit untouched preserve queue. The policy-level Surge -> Touch sequence
-- gate applies even to source-owned and raw JustAC queues, exactly like the DK
-- Pillar -> Frostwyrm gate.
testQueue = { 321507, 30451 }
testPreserveQueue = { 44425 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-1", 365350)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)

-- Frost's target-epoch opt-in must NOT loosen Arcane's GUID-bound Touch.
do
    local originalGUID=UnitGUID
    auraSecret=true
    UnitGUID=function() return secretAuraValue end
    eventFrame.OnEvent(eventFrame,"UNIT_FLAGS","target")
    JustACBridge.Refresh()
    assert(JustACBridge.GetLosslessRecommendation().spellID==30451)
    UnitGUID=originalGUID; auraSecret=false
    eventFrame.OnEvent(eventFrame,"UNIT_SPELLCAST_SUCCEEDED","player","surge-readable",365350)
    JustACBridge.Refresh()
    assert(JustACBridge.GetLosslessRecommendation().spellID==321507)
end
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "touch-1", 321507)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-target-a", 365350)
targetGUID = "Creature-0-0-0-0-200-0000000002"
eventFrame.OnEvent(eventFrame, "PLAYER_TARGET_CHANGED")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
targetGUID = "Creature-0-0-0-0-100-0000000001"
eventFrame.OnEvent(eventFrame, "PLAYER_TARGET_CHANGED")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-same-guid-retarget", 365350)
eventFrame.OnEvent(eventFrame, "PLAYER_TARGET_CHANGED")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-target-death", 365350)
targetDead = true
eventFrame.OnEvent(eventFrame, "UNIT_HEALTH", "target")
targetDead = false
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-target-unattackable", 365350)
targetAttackable = false
eventFrame.OnEvent(eventFrame, "UNIT_FLAGS", "target")
targetAttackable = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-target-missing", 365350)
targetExists = false
eventFrame.OnEvent(eventFrame, "UNIT_FLAGS", "target")
targetExists = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-expiry", 365350)
now = now + 10.0
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetLosslessRecommendation().sequenceFallback == true)

-- Explicit reliability rule: any positively active Surge cooldown releases
-- Touch directly, regardless of remaining duration or threshold capability.
-- Conversely, a ready Surge still waits for an executable Touch.
cooldownSpellID, cooldownEndsAt = 365350, now + 4
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
cooldownEndsAt = now + 30.099
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
cooldownEndsAt = now + 40
unknownCooldownThresholdSpells[365350] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
unknownCooldownThresholdSpells[365350] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
testQueue = { 365350, 30451 }
cooldownSpellID, cooldownEndsAt = 321507, now + 30
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
cooldownSpellID, cooldownEndsAt = nil, 0
unboundSpells[321507] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
unboundSpells[321507] = nil
unknownCooldownSpells[321507] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
unknownCooldownSpells[321507] = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 365350)
-- The owned Arcane source exports its proven pair as Surge, Touch. If the core
-- then proves Surge unbound, it skips the leader and direct Touch remains
-- executable even when the original capped JustAC queue omitted it.
testQueue = { 365350, 321507, 30451 }
unboundSpells[365350] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507,
    "unbound Surge should release Touch, got "
        .. tostring(JustACBridge.GetLosslessRecommendation().spellID))
unboundSpells[365350] = nil
testQueue = { 321507, 30451 }
unknownCooldownSpells[365350] = true
now = now + 10.0
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
now = now - 10.0
unknownCooldownSpells[365350] = nil
testPreserveQueue = nil

-- 12.1 Arcane M4 is the same live rotation as M5 minus the two reserved
-- cooldowns. After skipping Touch it must keep the owned Missiles action;
-- Arcane Explosion remains excluded from both outputs.
testQueue = { 321507, 5143, 30451, 153626, 1449, 44425 }
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "surge-2", 365350)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 321507)
assert(JustACBridge.GetLosslessRecommendation().offGCD == true)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 5143)
assert(JustACBridge.GetPreserveBurstRecommendation().offGCD == false)

-- Addon load/reload starts a fresh observed-stationary interval. Neither key
-- may export Orb until that initial interval reaches 0.8 complete seconds.
movementFallbackProofs[44425] = true
testQueue = { 153626, 44425 }
eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 0.79
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 0.01
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 153626)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 153626)

-- While moving, neither held key may guess the facing-dependent Orb. Both
-- skip it. After an ordinary stop both M5 and M4 require 0.8 continuous
-- stationary seconds.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
now = now + 0.79
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
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

-- Slipstream plus observable Clearcasting permits the Missiles channel while
-- moving. If combat hides the aura but Missiles is owned and currently usable,
-- Arcane gets one bounded probe; its first failed cast blocks further attempts
-- until movement really stops. A missing Slipstream never probes.
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
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 5143)

-- A STOP arriving while the blind probe is exported cancels that action
-- instance and exposes the next queue skill for one complete refresh. A new
-- stationary recommendation may then legitimately be Missiles again; it is
-- not confused with the cancelled moving probe even though the spell ID is
-- identical.
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)
assert(JustACBridge.GetLosslessRecommendation().movementProbe == false)
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)

-- If GetUnitSpeed becomes secret, a deferred STOP must not let the same blind
-- probe reappear on the following frames. Keep the next skill until the 250 ms
-- movement debounce resolves, then treat a same-ID stationary Missiles result
-- as a new recommendation instance.
speedSecret = true
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
now = now + 0.10
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
now = now + 0.16
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)
assert(JustACBridge.GetLosslessRecommendation().movementProbe == false)
speedSecret = false
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().movementProbe == true)
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "missiles-probe-1", 5143)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)

-- Exact positive evidence overrides a prior ambiguous probe failure.
playerAuras[263725] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)
playerAuras[263725] = nil
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "missiles-probe-2", 5143)
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
now = now + 0.13
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 5143)

-- Presence of Mind's player aura is sufficient and spell-specific evidence
-- that Arcane Blast is instant. Losing the aura must not promote a later
-- Barrage unless the source separately proves a real APL Barrage condition.
testQueue = { 30451, 44425 }
playerAuras[205025] = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 30451)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 30451)
playerAuras[205025] = nil
movementFallbackProofs[44425] = false
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
movementFallbackProofs[44425] = nil
playerAuras[205025] = secretAuraValue
auraSecret = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
auraSecret = false
playerAuras[205025] = nil
movementFallbackProofs[44425] = 1 -- truthy is not a strict proof boolean
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

-- Proof errors fail closed too. A positive proof releases both M5/M4 and is
-- carried on the exported row for diagnostics. Queue position 1 remains the
-- source's authoritative recommendation and never needs movement proof.
movementFallbackProofThrows = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
movementFallbackProofThrows = false
movementFallbackProofs[44425] = true
JustACBridge.Refresh()
local provenMovingBarrage = JustACBridge.GetLosslessRecommendation()
assert(provenMovingBarrage.spellID == 44425
    and provenMovingBarrage.movementFallbackProof == true
    and provenMovingBarrage.movementFallbackProofReason == "test-proof")
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)

local testSource = assert(JustACBridgeRecommendationSources.Get("test"))
local savedMovementProof = testSource.IsMovementFallbackAllowed
testSource.IsMovementFallbackAllowed = nil
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
testSource.IsMovementFallbackAllowed = savedMovementProof

movementFallbackProofs[44425] = false
burstCues[44425] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
burstCues[44425] = nil
testQueue = { 30451, 44425, 1295924 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 1295924)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 1295924)
testQueue = { 30451 }
highlightSpellID = 44425
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
highlightSpellID = nil
testQueue = { 44425, 30451 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
movementFallbackProofs[44425] = true
speed = 0
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")

-- The proof requirement is strictly movement-scoped. Stationary binding
-- fallback keeps the source queue semantics and does not consult this gate.
movementFallbackProofs[44425] = false
testQueue = { 30451, 44425 }
unboundSpells[30451] = true
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 44425)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 44425)
unboundSpells[30451] = nil
movementFallbackProofs[44425] = true

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
now = 101.5
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

-- Real core replay: all three CDs ready, but no Breath in the source queue.
-- Precombat must pool FIRST; no amount of repeated recommendation means success.
do
    local savedTime, savedCombat, savedGUID = now, inCombat, targetGUID
    local savedAPIs = { power = UnitPower, maxPower = UnitPowerMax,
        duration = C_Spell.GetSpellCooldownDuration, usable = C_Spell.IsSpellUsable,
        cost = C_Spell.GetSpellPowerCost, runes = GetRuneCooldown,
        debug = JustACBridgeDB.debugEnabled }
    JustACBridgeDB.debugEnabled = true
    local rp, maxRP, cds, remaining, cost = 42, 100, {}, {}, 35
    local runes, markCost, howlingCost, runeSecret, runeReadyBit = 6, 2, 1, false, false
    GetRuneCooldown = function(index)
        runeReadyBit=index<=runes
        return 0, 10, runeSecret and secretAuraValue or runeReadyBit
    end
    UnitPower = function() return rp end
    UnitPowerMax = function() return maxRP end
    C_Spell.GetSpellCooldownDuration = function(id)
        if unknownCooldownSpells[id] then return nil end
        return { active = cds[id] == true,
            GetRemainingDuration = function() return remaining[id] end }
    end
    C_Spell.GetSpellPowerCost = function(id)
        if id==439843 then return {{type=5,cost=markCost,minCost=markCost}} end
        if id==49020 then return {{type=5,cost=2,minCost=2}} end
        if id==49184 then return {{type=5,cost=howlingCost,minCost=howlingCost}} end
        return {{type=6,cost=cost,minCost=cost}}
    end
    C_Spell.IsSpellUsable = function(id)
        if id==439843 and runes<markCost then return false,true end
        if not issecretvalue(rp) and (id == 1249658 or id == 152279)
            and rp < 60 then return false, true end
        return unusableSpells[id] ~= true, false
    end
    local function event(name, id, unit)
        eventFrame.OnEvent(eventFrame, name, unit or "player", "frost-gate-test", id)
    end
    local function success(id, unit) event("UNIT_SPELLCAST_SUCCEEDED", id, unit) end
    local function reset()
        eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
        now, inCombat, rp, maxRP, cds = 100, false, 42, 100, {}
        remaining, cost = {}, 35
        runes, markCost, howlingCost, runeSecret = 6, 2, 1, false
        targetGUID, targetWithin5 = savedGUID, nil
        targetDead, targetAttackable, auraSecret = false, true, false
        cooldownSpellID, cooldownEndsAt = nil, 0
        for _, id in ipairs({439843,51271,1249658,279302,47568}) do
            unlearnedSpells[id], unboundSpells[id], unusableSpells[id] = nil, nil, nil
            unknownCooldownSpells[id], effectiveSpellOverrides[id] = nil, nil
        end
        testQueue = {51271,49143,439843,194913,279302,49998,47568,49020,49184}
    end
    local function selected(id)
        JustACBridge.Refresh()
        local actual = JustACBridge.GetLosslessRecommendation()
        assert((actual and actual.spellID) == id,
            "frost expected " .. tostring(id) .. " got " .. tostring(actual and actual.spellID))
        return actual
    end
    -- Mark's GCD must not delay the next ready off-GCD action. Replay both
    -- groups without advancing time, including the actual pixel permission
    -- consumed by M5 rather than only the sequence's timing budget.
    do
        local function checkClosedGCD(id, offGCD)
            local actual = selected(id)
            assert(actual and actual.offGCD == offGCD,
                "frost GCD permission for " .. tostring(id))
            assert(JustACBridgeExport.queueReady == false)
            assert(JustACBridgeExport.gcdRemainingMs == 1500)
            local cells, flags = namedFrames.JustACBridgePixelFrame.textures, 0
            for bit = 1, 8 do flags = flags * 2 + cells[504 + bit].bit end
            assert(flags % 2 == 0, "global GCD must remain closed")
            assert(math.floor(flags / 8) % 2 == (offGCD and 1 or 0))
            assert(math.floor(flags / 16) % 2 == 0, "M4 filler cannot bypass GCD")
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49143)
        end
        for _, small in ipairs({true, false}) do
            reset(); rp = small and 0 or 60
            if small then
                cds[1249658], cds[279302] = true, true
                remaining[1249658], remaining[279302] = 35, 35
            end
            cooldownSpellID, cooldownEndsAt = 61304, now + 1.5
            checkClosedGCD(439843, false)
            event("UNIT_SPELLCAST_FAILED", 439843); checkClosedGCD(439843, false)
            success(439843); cds[439843] = true
            unusableSpells[51271] = true; selected(nil)
            unusableSpells[51271] = nil
            unknownCooldownSpells[51271] = true; selected(nil)
            unknownCooldownSpells[51271] = nil
            checkClosedGCD(51271, true)
            event("UNIT_SPELLCAST_FAILED", 51271); checkClosedGCD(51271, true)
            success(51271); cds[51271] = true
            if small then checkClosedGCD(49143, false)
            else
                rp = 59; checkClosedGCD(47568, false)
                rp = 60; checkClosedGCD(1249658, true)
                event("UNIT_SPELLCAST_FAILED", 1249658); checkClosedGCD(1249658, true)
                success(1249658); cds[1249658] = true
                checkClosedGCD(279302, false) -- first Fury really uses the GCD
            end
        end
    end
    reset()
    assert(selected(47568).policyBurstGateReason:find("POOL_BREATH:rp-below-60",1,true)==1)
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49143)
    assert(#testQueue == 9 and testQueue[1] == 51271 and testQueue[2] == 49143)
    success(47568); selected(47568) -- no inferred resource gain; still no Pillar
    testQueue = {51271,49143,439843,279302,49020,49184}
    for _, amount in ipairs({42,52,59}) do rp = amount; selected(49020) end
    rp = 60; assert(selected(439843).policyBurstGateReason:find("EXPECT_MARK:ready:", 1, true) == 1)
    for _ = 1, 3 do selected(439843) end
    success(439843, "target"); selected(439843)
    success(439843); cds[439843] = true; selected(51271)
    success(51271); cds[51271] = true; selected(1249658)
    success(1249658); cds[1249658] = true; selected(279302)
    success(279302); cds[279302] = true; selected(46585)
    success(46585)
    -- Same-frame resource loss AFTER Pillar must not abandon the Breath window.
    reset(); rp = 60; selected(439843); success(439843); selected(51271)
    success(51271); cds[51271] = true; rp = 42; selected(47568)
    now = 101; rp = 60; selected(1249658); success(152279); selected(279302)
    -- Cooldown update before the event does not substitute for it or lose it.
    reset(); rp = 60; selected(439843); success(439843); selected(51271)
    cds[51271] = true; selected(nil); success(51271); selected(1249658)
    -- No hidden fallback may resurrect a burst or spender from an empty pool.
    reset(); testQueue = {51271,49143,439843,279302,194913,49998}; selected(nil)
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49143)
    -- Stop waiting at the actual 60 threshold, not at a full bar.
    for _, amount in ipairs({60,85,90,100}) do reset(); rp = amount; selected(439843) end
    -- One cooldown missing (e.g. Breath still 35 seconds away): normal queue.
    for _, id in ipairs({51271,1249658,279302}) do
        reset(); cds[id] = true; testQueue = {49143,49020}; selected(49143)
    end
    reset(); cds[1249658] = true; testQueue = {51271,49184}; selected(49184)
    success(51271); testQueue = {279302,49184}; selected(49184) -- manual Pillar cannot license half-group
    for _, flags in ipairs({unlearnedSpells,unboundSpells,unknownCooldownSpells}) do
        for _, id in ipairs({51271,1249658,279302}) do
            reset(); flags[id] = true; testQueue = {49143,49020}; selected(49143)
        end
    end
    for _, flags in ipairs({unlearnedSpells,unboundSpells}) do
        reset(); rp = 60
        flags[439843] = true; selected(49143)
    end
    -- Regression of the observed EXPECT_PILLAR_NO_MARK: a ready trio never
    -- authorizes skipping a learned/bound predecessor just because it is on CD.
    reset(); rp = 60; cds[439843] = true; selected(49143)
    testQueue = {51271,279302,47568,49184}; selected(47568)
    cds[439843] = false; selected(439843); success(439843); selected(51271)
    success(51271); selected(1249658); success(1249658); selected(279302)
    reset(); rp = 60; unusableSpells[439843] = true; selected(nil)
    unusableSpells[439843] = nil; selected(439843)
    reset(); effectiveSpellOverrides[279302] = 1265384
    testQueue = {279302,49184}; selected(1265384) -- recall source-owned
    reset(); testQueue = {1228433,49020}; selected(49020)
    -- A source's fail-open usability must not stand in for ownership/binding.
    local source = JustACBridgeRecommendationSources.Get("test")
    local originalKnown, originalHotkey = IsPlayerSpell, source.GetSpellHotkey
    for _, mode in ipairs({"nil", "secret", "throw"}) do
        reset(); rp = 60; auraSecret = true
        IsPlayerSpell = function(id)
            if id ~= 439843 then return originalKnown(id) end
            if mode == "throw" then error("unknown predecessor ownership") end
            if mode == "secret" then return secretAuraValue end
            return nil
        end
        selected(nil) -- unknown Mark is NOT an absent optional predecessor
        IsPlayerSpell = originalKnown
        source.GetSpellHotkey = function(id)
            if id ~= 439843 then return originalHotkey(id) end
            if mode == "throw" then error("unknown predecessor binding") end
            if mode == "secret" then return secretAuraValue end
            return nil
        end
        selected(nil)
        source.GetSpellHotkey = originalHotkey
        selected(439843); success(439843); selected(51271)
    end
    -- Positive ownership from either authoritative API works end to end,
    -- including the final common-core legality check for an injected action.
    reset(); rp = 60
    IsPlayerSpell = function(id) return id ~= 439843 and originalKnown(id) end
    local savedKnown = IsSpellKnown
    IsSpellKnown = function(id) return id == 439843 end
    selected(439843); success(439843); selected(51271)
    IsPlayerSpell, IsSpellKnown = originalKnown, savedKnown
    for _, mode in ipairs({"nil","secret","throw"}) do
        reset(); rp = 60; auraSecret = true; testQueue = {49143,49020}
        IsPlayerSpell = function(id)
            if id ~= 1249658 then return originalKnown(id) end
            if mode == "throw" then error("unknown ownership") end
            if mode == "secret" then return secretAuraValue end
            return nil
        end
        selected(49143); IsPlayerSpell = originalKnown
        source.GetSpellHotkey = function(id)
            if id ~= 1249658 then return originalHotkey(id) end
            if mode == "throw" then error("unknown binding") end
            if mode == "secret" then return secretAuraValue end
            return nil
        end
        selected(49143); source.GetSpellHotkey = originalHotkey
    end
    -- Fresh strict usability, not the upstream fail-open boolean.
    local originalUsable = C_Spell.IsSpellUsable
    for _, mode in ipairs({"missing","nil","secret","throw"}) do
        reset(); rp = 60; auraSecret = true
        if mode == "missing" then C_Spell.IsSpellUsable = nil
        else C_Spell.IsSpellUsable = function()
            if mode == "throw" then error("injected strict failure") end
            if mode == "secret" then return secretAuraValue, secretAuraValue end
            return nil
        end end
        selected(49143) -- cannot prove complete group usable: don't pre-pool
        C_Spell.IsSpellUsable = originalUsable; selected(439843)
    end
    reset(); rp, auraSecret = secretAuraValue, true; selected(439843)
    success(439843); selected(51271); success(51271); selected(1249658)
    success(1249658); selected(279302)
    -- Spammed M5 failures during GCD/resources must never skip Breath.
    for _, name in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED"}) do
        reset(); rp = 60; selected(439843); success(439843); selected(51271)
        success(51271); cds[51271] = true; selected(1249658)
        event(name,1249658); rp = 42; selected(47568)
        rp = 60; selected(1249658); success(1249658); selected(279302)
    end
    for _, name in ipairs({"PLAYER_TARGET_CHANGED","PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD","PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED"}) do
        reset(); rp = 60; selected(439843); success(439843); selected(51271)
        success(51271); cds[51271] = true; selected(1249658)
        eventFrame.OnEvent(eventFrame, name); testQueue = {49184}; selected(49184)
    end
    reset(); rp = 60; selected(439843); success(439843); selected(51271)
    success(51271); cds[51271] = true; now = 110
    testQueue = {49184}; selected(49184)
    reset(); rp = 60; selected(439843); success(439843); selected(51271)
    success(51271); cds[51271] = true; targetGUID = "changed-target"
    testQueue = {49184}; selected(49184); targetGUID = savedGUID; selected(49184)
    for _, invalid in ipairs({"dead", "unattackable"}) do
        reset(); rp = 60; selected(439843); success(439843); selected(51271)
        success(51271); cds[51271] = true
        targetDead, targetAttackable = invalid == "dead", invalid ~= "unattackable"
        testQueue = {49184}; selected(49184)
        targetDead, targetAttackable = false, true; selected(49184)
    end
    reset(); targetWithin5 = false; testQueue = {51271,47568,49184}; selected(49184)
    testQueue = {}; selected(nil)
    reset(); rp = 60; selected(439843); success(439843); selected(51271)
    success(51271); cds[51271] = true
    classFile, specIndex = "DEATHKNIGHT", 3
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    testQueue = {49184}; selected(49184)
    classFile, specIndex = "DEATHKNIGHT", 2
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    selected(49184)
    -- Near-window preparation must reach actual exported M5, retain source
    -- order, never inject burst/fallback, and leave M4 completely unchanged.
    local function upcoming()
        reset(); inCombat=true
        for _, id in ipairs({51271,1249658,279302}) do cds[id],remaining[id]=true,2 end
    end
    upcoming(); testQueue={49143,49020,49184}
    assert(selected(49020).policyBurstGateReason:find("PREP_BREATH_WITHIN_6S:",1,true)==1)
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
    for _, amount in ipairs({42,52,59,60,85,90,94.999}) do rp=amount; selected(49020) end
    rp=95; selected(49143); rp=94; selected(49020)
    rp=85; cost=25; selected(49143); cost=35; selected(49020)
    rp=100; cost=nil; selected(49020) -- unknown cost doesn't authorize spending
    cost=35; selected(49143)
    testQueue={51271,49143,439843,279302}; rp=42; selected(nil)
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
    testQueue={1249658,49143,49020}; rp=60; selected(49020)
    cds={}; selected(439843); success(439843); selected(51271)
    success(51271); selected(1249658); success(1249658); selected(279302)
    upcoming(); testQueue={49143,49020}; remaining[1249658]=35; selected(49143)
    testQueue={51271,49184}; cds[51271]=false; selected(49184)
    success(51271); testQueue={279302,49184}; cds[279302]=false; selected(49184)
    upcoming(); testQueue={49143,49020}; unknownCooldownSpells[1249658]=true; selected(49143)
    upcoming(); targetWithin5=false; testQueue={49143,49020}; selected(nil)
    testQueue={49143,49184}; selected(49184)
    upcoming(); testQueue={49143,49020}; selected(49020)
    remaining[1249658]=35; eventFrame.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED"); selected(49143)
    -- Same complete core pipeline when numeric RP/CD are opaque: use fresh
    -- native step predicates, never stringify/compare the hidden numbers.
    do
        local previousCurve,previousEnum,previousPercent=C_CurveUtil,Enum,UnitPowerPercent
        local previousDuration,previousPower=C_Spell.GetSpellCooldownDuration,UnitPower
        local previousGUID=UnitGUID
        local previousBinary=source.ReadBinaryPredicate
        local hiddenResult, curveBroken, adapterBroken=false,false,false
        Enum={LuaCurveType={Step=1}}
        C_CurveUtil={CreateCurve=function()
            local curve={points={}}
            function curve:SetType(t) assert(t==1) end
            function curve:AddPoint(x,y) self.points[#self.points+1]={x,y} end
            function curve:Evaluate(x)
                if curveBroken then return 37 end
                local value=0
                for _, point in ipairs(self.points) do if x>=point[1] then value=point[2] end end
                return value
            end
            return curve
        end}
        source.ReadBinaryPredicate=function(value)
            assert(rawequal(value,secretAuraValue))
            if adapterBroken then return nil end
            return hiddenResult
        end
        C_Spell.GetSpellCooldownDuration=function(id)
            return {active=cds[id]==true,
                GetRemainingDuration=function() return secretAuraValue end,
                EvaluateRemainingDuration=function(_,curve)
                    hiddenResult=curve:Evaluate(remaining[id] or 0)==100
                    return secretAuraValue
                end}
        end
        UnitPower=function() return secretAuraValue end
        UnitGUID=function() return secretAuraValue end
        UnitPowerPercent=function(_,powerType,unmodified,curve)
            assert(powerType==6 and unmodified==false)
            hiddenResult=curve:Evaluate(rp/maxRP)==100
            return secretAuraValue
        end
        upcoming(); auraSecret=true; testQueue={49143,49020}
        selected(49020); rp=95; selected(49143); rp=94.999; selected(49020)
        rp=60; selected(49020)
        remaining[1249658]=35; selected(49143) -- hidden CD is NOT always near
        remaining[1249658]=2; selected(49020)
        cds={}; selected(439843); success(439843); selected(51271)
        success(51271); selected(1249658); success(1249658); selected(279302)
        upcoming(); auraSecret=true; testQueue={49143,49020}; adapterBroken=true
        selected(49143) -- unknown horizon delegates, doesn't latch last prep
        adapterBroken=false
        upcoming(); auraSecret=true; rp=0; cds[51271]=false
        remaining[1249658],remaining[279302]=18,18
        testQueue={51271,1249658,279302,439843,49143,49020}; selected(49143)
        remaining[1249658]=35; selected(49143) -- one long is still NOT both long
        remaining[279302]=35; selected(439843); success(439843); selected(51271)
        success(51271); cds[51271]=true; selected(49143)
        -- All restricted values together: target GUID, CD, RP and rune
        -- readiness. Both independent native predicates must reach export.
        C_CurveUtil.EvaluateColorValueFromBoolean=function(value,yes,no)
            assert(yes==1 and no==0)
            if rawequal(value,secretAuraValue) then hiddenResult=runeReadyBit; return secretAuraValue end
            return value and yes or no
        end
        upcoming(); auraSecret=true; runeSecret=true; runes=2; rp=42
        testQueue={49020,49143,49184,47568}; selected(47568)
        runes=4; selected(49020)
        runes=2; rp=95; selected(49143)
        rp=60; cds={}; selected(439843); success(439843); runes=0
        selected(51271); success(51271); selected(1249658); success(1249658); selected(279302)
        -- Same handoff with opaque cooldowns/resources/GUID/runes: the native
        -- inclusive deadline is sufficient; no readable numeric duplicates.
        local originalHaste=GetHaste
        GetHaste=function() return 50 end
        upcoming(); auraSecret=true; runeSecret=true; runes=2; rp=60
        for _,id in ipairs({51271,1249658,279302}) do remaining[id]=1 end
        selected(439843); success(439843); cds[439843]=true; runes=0
        selected(nil) -- early Pillar cannot be bypassed by a filler
        cds[51271]=false; selected(51271); success(51271); cds[51271]=true
        selected(nil); cds[1249658]=false; selected(1249658); success(1249658)
        selected(nil); cds[279302]=false; selected(279302)
        GetHaste=originalHaste
        C_CurveUtil,Enum,UnitPowerPercent=previousCurve,previousEnum,previousPercent
        C_Spell.GetSpellCooldownDuration,UnitPower=previousDuration,previousPower
        UnitGUID=previousGUID
        source.ReadBinaryPredicate=previousBinary
    end
    -- Dungeon regression: hidden identity must not disable the whole gate.
    -- Unknown target VALIDITY must hold downstream burst, never fail open.
    do
        local originalGUID = UnitGUID
        for _, mode in ipairs({"secret", "nil", "throw", "missing"}) do
            reset(); auraSecret = true; rp = 42
            UnitGUID = mode ~= "missing" and function()
                if mode == "secret" then return secretAuraValue end
                if mode == "throw" then error("identity restricted") end
                return nil
            end or nil
            testQueue = {51271,279302,49143,49020}
            selected(49020)
            rp = 60; selected(439843); success(439843)
            eventFrame.OnEvent(eventFrame, "UNIT_HEALTH", "target")
            eventFrame.OnEvent(eventFrame, "UNIT_FLAGS", "target")
            selected(51271); success(51271); selected(1249658)
            success(1249658); selected(279302)
            UnitGUID = originalGUID
        end
        for _, name in ipairs({"UnitExists", "UnitCanAttack", "UnitIsDeadOrGhost"}) do
            local original = _G[name]
            for _, mode in ipairs({"secret", "nil", "throw", "missing"}) do
                reset(); auraSecret = true; rp = 60
                _G[name] = mode ~= "missing" and function()
                    if mode == "secret" then return secretAuraValue end
                    if mode == "throw" then error("validity restricted") end
                    return nil
                end or nil
                testQueue = {51271,279302,1249658,439843,49143,49020}
                selected(49020)
                testQueue = {51271,279302,1249658,439843,49143}; selected(nil)
                _G[name] = original
                selected(439843)
            end
        end
        -- Simultaneously hidden GUID, cooldown numbers and RP follows the
        -- engine affordability path; UNIT_HEALTH cannot wipe the receipt.
        reset(); auraSecret=true; rp=secretAuraValue
        UnitGUID=function() return secretAuraValue end
        selected(439843); success(439843)
        eventFrame.OnEvent(eventFrame,"UNIT_HEALTH","target"); selected(51271)
        success(51271); selected(1249658); success(1249658); selected(279302)
        -- Unknown target validity during an already-proposed player cast:
        -- hold downstream actions; accept ONLY its actual success event in
        -- the same epoch, then resume once validity is freshly proven.
        reset(); auraSecret=true; rp=60; selected(439843)
        local originalAttack=UnitCanAttack
        UnitCanAttack=function() return secretAuraValue end
        success(439843); cds[439843]=true
        eventFrame.OnEvent(eventFrame,"UNIT_FLAGS","target")
        testQueue={51271,279302,1249658,49143,49020}; selected(49020)
        UnitCanAttack=originalAttack; selected(51271)
        success(51271); selected(1249658)
        -- Actual target changes (including changing away and back), resets
        -- and explicit invalidity kill the epoch even though GUID is hidden.
        for _, name in ipairs({"PLAYER_TARGET_CHANGED","PLAYER_REGEN_ENABLED",
            "PLAYER_ENTERING_WORLD","PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED"}) do
            reset(); auraSecret=true; rp=60; selected(439843); success(439843)
            selected(51271); success(51271); cds[51271]=true; selected(1249658)
            eventFrame.OnEvent(eventFrame,name)
            eventFrame.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED")
            testQueue={49184}; selected(49184) -- no old BREATH receipt
            success(1249658); selected(49184)
        end
        for _, invalid in ipairs({"dead","friendly","absent"}) do
            reset(); auraSecret=true; rp=60; selected(439843); success(439843)
            selected(51271); success(51271); cds[51271]=true
            targetDead=invalid=="dead"; targetAttackable=invalid~="friendly"; targetExists=invalid~="absent"
            eventFrame.OnEvent(eventFrame,"UNIT_HEALTH","target")
            targetDead,targetAttackable,targetExists=false,true,true
            testQueue={49184}; selected(49184)
        end
        -- Empty WAIT is authoritative; M4 still reads the original source.
        reset(); auraSecret=true; rp=60
        UnitCanAttack=function() return secretAuraValue end
        testQueue={51271,279302,1249658,439843,49143}; selected(nil)
        assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
        UnitCanAttack=originalAttack
        -- Confirmed range remains authoritative, not overridden by the epoch.
        reset(); auraSecret=true; targetWithin5=false
        testQueue={51271,279302,49143}; selected(nil)
        testQueue={51271,49184}; selected(49184)
        UnitGUID=originalGUID
    end
    -- Long CDs on BOTH dragons: source can put Pillar first and omit Mark,
    -- yet the small window must wait and execute Mark -> Pillar without 60 RP.
    do
        local originalGUID=UnitGUID
        local function smallWindow()
            reset(); rp=0; inCombat=true; auraSecret=true
            UnitGUID=function() return secretAuraValue end
            cds[1249658],cds[279302]=true,true
            remaining[1249658],remaining[279302]=35,35
            testQueue={51271,279302,1249658,49143,49020}
        end
        smallWindow(); cds[439843]=true
        assert(selected(49143).policyBurstGateReason:find("WAIT_SMALL_MARK",1,true)==1)
        assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
        cds[439843]=false; cds[51271]=true; selected(49143)
        cds[51271]=false
        assert(selected(439843).policyBurstGateReason:find("SMALL_EXPECT_MARK",1,true)==1)
        event("UNIT_SPELLCAST_FAILED",439843); selected(439843)
        cds[439843]=true
        assert(selected(49143).policyBurstGateReason=="WAIT_SMALL_CAST_CONFIRM")
        success(439843); eventFrame.OnEvent(eventFrame,"UNIT_HEALTH","target")
        assert(selected(51271).policyBurstGateReason=="SMALL_EXPECT_PILLAR")
        event("UNIT_SPELLCAST_FAILED",51271); selected(51271)
        cds[51271]=true; selected(nil); success(51271); selected(49143)
        -- Empty filtered queue cannot invoke fallback or a source burst cue.
        smallWindow(); cds[439843]=true; testQueue={51271,279302,1249658,439843}; selected(nil)
        cds[439843]=false; selected(439843); success(439843); cds[439843]=true
        selected(51271)
        eventFrame.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED")
        selected(nil) -- changed target cannot reuse the previous Mark receipt
        cds[439843]=false; selected(439843); success(439843); selected(51271)
        success(51271); cds[51271]=true
        testQueue={49143,49020}; selected(49143)
        -- A later full window still starts by pooling, then the four steps.
        cds={}; rp=42; testQueue={51271,279302,1249658,49143,49020}; selected(49020)
        rp=60; selected(439843); success(439843); selected(51271)
        success(51271); selected(1249658); success(1249658); selected(279302)
        -- No interpretation of missing duration data as a long cooldown.
        smallWindow(); remaining[279302]=nil; testQueue={49143,49020}; selected(49143)
        assert(JustACBridge.GetLosslessRecommendation().policyBurstGate)
        UnitGUID=originalGUID
    end
    -- Mark's rune preparation from the real selector/export, with separate
    -- small/full group horizons and no M4 resource reservation.
    do
        local function markUpcoming(markSeconds,pillarSeconds)
            reset(); auraSecret=true; runes=2
            cds[1249658],cds[279302]=true,true
            remaining[1249658],remaining[279302]=35,35
            cds[439843],cds[51271]=markSeconds>0,pillarSeconds>0
            remaining[439843],remaining[51271]=markSeconds,pillarSeconds
            testQueue={51271,439843,49020,49184,49143,47568}
        end
        for _, pair in ipairs({{2,2},{0,2},{2,0}}) do
            markUpcoming(pair[1],pair[2])
            assert(selected(49143).policyBurstGateReason:find("PREP_MARK_WITHIN_6S:reserve=2",1,true))
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49020)
            runes=3; selected(49184); runes=4; selected(49020)
            runes=2; testQueue={49020,49184,51271,439843}; selected(nil)
        end
        markUpcoming(2,2); remaining[51271]=6; selected(49020)
        remaining[51271]=5.999999; selected(49143)
        remaining[51271]=35; selected(49020)
        markUpcoming(2,2); runes=1; howlingCost=0; selected(49184)
        howlingCost=1; selected(49143)
        cds[439843],cds[51271]=false,false; selected(49143) -- low-rune recovery, NOT all-M5 pause
        success(47568); selected(49143) -- no inferred resource grant
        runes=2; selected(439843); success(439843); cds[439843]=true; remaining[439843]=45
        runes=0; selected(51271)
        success(51271); cds[51271]=true; remaining[51271]=45; selected(49020) -- reserve ends on actual Mark success
        upcoming(); auraSecret=true; runes=2; rp=42
        testQueue={49020,49143,49184,47568}; selected(47568)
        assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49020)
        runes=4; selected(49020)
        runes=2; rp=95; selected(49143); rp=94.999; selected(47568)
        cds={}; runes=1; rp=60; selected(47568)
        howlingCost=0; selected(49184)
        howlingCost=1; runes=2; selected(439843); success(439843); runes=0
        selected(51271); success(51271); selected(1249658); success(1249658); selected(279302)
        -- The hidden readiness path uses current native boolean evaluation;
        -- no numeric rune counts, UnitPower(5), prior events, or UI bar cache.
        local originalCurve,originalBinary=C_CurveUtil,source.ReadBinaryPredicate
        local binaryBit,broken=false,false
        C_CurveUtil={EvaluateColorValueFromBoolean=function(value,yes,no)
            assert(yes==1 and no==0)
            if broken then return 0.5 end
            if rawequal(value,secretAuraValue) then binaryBit=runeReadyBit; return secretAuraValue end
            return value and yes or no
        end}
        source.ReadBinaryPredicate=function(value)
            assert(rawequal(value,secretAuraValue)); return binaryBit
        end
        markUpcoming(2,2); runeSecret=true; runes=4; selected(49020)
        runes=3; selected(49184); runes=2; selected(49143)
        runes=6; broken=true; selected(49143) -- broken engine cannot authorize a spender
        howlingCost=0; selected(49184) -- zero-cost needs no hidden resource comparison
        C_CurveUtil,source.ReadBinaryPredicate=originalCurve,originalBinary
        -- No preparation retained across target/phase/CD changes.
        markUpcoming(2,2); selected(49143)
        eventFrame.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED")
        remaining[439843]=35; selected(49020)
        markUpcoming(2,2); remaining[1249658]=18; selected(49020)
        remaining[1249658]=nil; selected(49020)
        markUpcoming(2,2); unboundSpells[439843]=true; selected(49020)
        markUpcoming(2,2); targetWithin5=false; selected(49184)
    end
    -- Latest user rule, through actual SELECT/export: both long (>18) may
    -- use the pair; any near/ready/unknown dragon holds ALL four burst IDs.
    for _, times in ipairs({{0,35},{35,0},{18,18},{18,35},{35,18},{17.999,17.999}}) do
        reset(); rp=60; auraSecret=true
        cds[1249658],cds[279302]=times[1]>0,times[2]>0
        remaining[1249658],remaining[279302]=times[1],times[2]
        testQueue={1249658,279302,51271,439843,49143,49020}
        selected(49143)
        assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
        testQueue={279302,1249658,51271,439843}; selected(nil)
        success(51271); playerAuras[51271]={}; selected(nil)
        playerAuras[51271]=nil -- a manual aura cannot license a half-group
    end
    reset(); rp=0; cds[1249658],cds[279302]=true,true
    remaining[1249658],remaining[279302]=18+2^-48,18+2^-48
    testQueue={51271,279302,1249658,49020}
    selected(439843); success(439843); selected(51271); success(51271)
    cds[51271]=true; selected(49020)
    -- Generic fail-closed ownership even if an opt-in selector disappears,
    -- returns nil, throws, or mistakenly returns unfiltered ordinary queue.
    do
        local definition=JustACBridgePolicyRegistry.classes.DEATHKNIGHT.specs[2].versions[1]
        local originalSelector=definition.selectLossless
        for _, mode in ipairs({"missing","nil","throw","queue"}) do
            reset(); rp=60; auraSecret=true
            definition.selectLossless=mode~="missing" and function(queue)
                if mode=="throw" then error("injected sequence gate failure") end
                if mode=="queue" then return {queue=queue,reason="bad-upstream-queue"} end
                return nil
            end or nil
            burstCues[51271],burstCues[1249658],burstCues[279302]=true,true,true
            eventFrame.OnEvent(eventFrame,"PLAYER_SPECIALIZATION_CHANGED","player")
            testQueue={51271,1249658,279302,439843,49143,49020}; selected(49143)
            testQueue={51271,1249658,279302,439843}; selected(nil)
            testQueue={}; selected(nil)
            testQueue={51271,1249658,439843,279302,49143}
            effectiveSpellOverrides[279302]=1265384; selected(1265384)
            effectiveSpellOverrides[279302]=nil
        end
        definition.selectLossless=originalSelector
        burstCues[51271],burstCues[1249658],burstCues[279302]=nil,nil,nil
        eventFrame.OnEvent(eventFrame,"PLAYER_SPECIALIZATION_CHANGED","player")
    end
    -- Generic mode isolation, including a future policy that does not opt in
    -- to Frost's preserveSourceQueueOnly flag. M4 must not copy an M5 generator
    -- selected by resource preparation, or skip the original first spender.
    do
        local definition=JustACBridgePolicyRegistry.classes.DEATHKNIGHT.specs[2].versions[1]
        local oldSelector,oldQueueOnly=definition.selectLossless,definition.preserveSourceQueueOnly
        local oldQueue,oldPreserve=source.GetQueue,source.GetPreserveQueue
        definition.preserveSourceQueueOnly=false
        source.GetPreserveQueue=nil
        for _, shape in ipairs({"action","filtered-queue","empty"}) do
            reset(); rp=42; testQueue={49143,49020}
            definition.selectLossless=function(q,context)
                assert(context.mode=="lossless")
                table.remove(q,1) -- a badly behaved policy cannot mutate M4's snapshot
                if shape=="action" then return {spellID=49020,reason="TEST_M5_PREPARATION"} end
                return {queue=shape=="empty" and {} or q,reason="TEST_M5_PREPARATION"}
            end
            eventFrame.OnEvent(eventFrame,"PLAYER_SPECIALIZATION_CHANGED","player")
            selected(shape~="empty" and 49020 or nil)
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
            assert(testQueue[1]==49143 and #testQueue==2)
        end
        -- The source may reuse one table between getters. Snapshot BEFORE the
        -- M4 getter runs so its update cannot retroactively alter the M5 queue.
        local shared={}
        source.GetQueue=function() shared[1],shared[2]=49143,49020; return shared end
        source.GetPreserveQueue=function() shared[1],shared[2]=49020,49143; return shared end
        definition.selectLossless=function(q,context)
            assert(context.mode=="lossless"); return {queue=q,reason="MODE_SNAPSHOT_TEST"}
        end
        eventFrame.OnEvent(eventFrame,"PLAYER_SPECIALIZATION_CHANGED","player")
        selected(49143); assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49020)
        definition.selectLossless,definition.preserveSourceQueueOnly=oldSelector,oldQueueOnly
        source.GetQueue,source.GetPreserveQueue=oldQueue,oldPreserve
        eventFrame.OnEvent(eventFrame,"PLAYER_SPECIALIZATION_CHANGED","player")
        -- Live-log shape: M5 removes both spenders while M4 uses the first
        -- ordinary action. If the SOURCE omits spenders, do not invent one.
        reset(); rp=42; runes=1; testQueue={51271,49143,49020,47568}
        selected(47568); assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
        testQueue={51271,49020}; runes=6
        selected(49020); assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49020)
    end
    -- End-to-end staggered start, including the GCD input commit window.
    -- Being 62.5ms before the opener may NOT queue a filler just because the
    -- successor is still (one GCD + 62.5ms) away at this frame.
    do
        local originalHaste=GetHaste
        local haste=50
        GetHaste=function() return haste end
        for _, small in ipairs({true,false}) do
            reset(); rp=small and 0 or 60
            testQueue={279302,1249658,51271,49143,49020,47568}
            cds[51271],remaining[51271]=true,1
            cds[1249658],cds[279302]=true,true
            remaining[1249658],remaining[279302]=small and 35 or 1,small and 35 or 1
            selected(439843)
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
            event("UNIT_SPELLCAST_FAILED",439843); selected(439843)
            success(439843); cds[439843]=true; selected(nil)
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID==49143)
            now=101; cds[51271]=false; selected(51271)
            success(51271); cds[51271]=true
            if small then selected(49143)
            else
                selected(nil); cds[1249658]=false; selected(1249658)
                event("UNIT_SPELLCAST_FAILED",1249658); selected(1249658)
                cds[1249658]=true; selected(nil); success(1249658)
                selected(nil); cds[279302]=false; selected(279302)
                success(279302); cds[279302]=true; selected(46585)
            end
        end
        reset(); rp=60; testQueue={49143,49020}
        for _,id in ipairs({51271,1249658,279302}) do cds[id],remaining[id]=true,1.0625 end
        selected(49020) -- without an active GCD, 1.0625 misses the 1s deadline
        cooldownSpellID,cooldownEndsAt=61304,now+0.0625
        selected(439843)
        for _,id in ipairs({51271,1249658,279302}) do remaining[id]=1.0635 end
        selected(49020) -- no arbitrary latency slack
        -- Empty upstream queue still has no priority over the ordered opener.
        testQueue={}; remaining[51271],remaining[1249658],remaining[279302]=1,1,1
        selected(439843); success(439843); cds[439843]=true; selected(nil)
        eventFrame.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED")
        cds[51271],cds[1249658],cds[279302]=false,false,false; selected(nil)
        -- Three actual-cooldown cycles without reset: full -> small -> full.
        reset(); testQueue={51271,279302,1249658,49143,49020}
        local ends={}
        local function tick(t)
            now=t
            for _,id in ipairs({439843,51271,1249658,279302}) do
                remaining[id]=math.max(0,(ends[id] or 0)-t); cds[id]=remaining[id]>0
            end
        end
        local function cast(id,cd)
            selected(id); success(id); ends[id]=now+cd; tick(now)
        end
        for round=0,2 do
            tick(100+45*round); rp=60; runes=6
            cast(439843,45); tick(101+45*round); cast(51271,45)
            if round%2==0 then cast(1249658,90); rp=0; cast(279302,90) end
        end
        GetHaste=originalHaste
    end
    -- Exported diagnostics distinguish the pool and each ordered next action.
    reset(); selected(47568); rp = 60; selected(439843); success(439843)
    selected(51271); success(51271); selected(1249658); success(1249658); selected(279302)
    eventFrame.OnEvent(eventFrame, "PLAYER_LOGOUT")
    for _, reason in ipairs({"SMALL_EXPECT_MARK","SMALL_EXPECT_PILLAR","PREP_BREATH_WITHIN_6S:","POOL_BREATH:rp-below-60","EXPECT_MARK","EXPECT_PILLAR","EXPECT_BREATH","EXPECT_FURY"}) do
        assert(JustACBridgeExport.debugLog:find("preparationReason=" .. reason, 1, true), reason)
    end
    reset()
    now, inCombat, targetGUID = savedTime, savedCombat, savedGUID
    UnitPower, UnitPowerMax = savedAPIs.power, savedAPIs.maxPower
    C_Spell.GetSpellCooldownDuration, C_Spell.IsSpellUsable = savedAPIs.duration, savedAPIs.usable
    C_Spell.GetSpellPowerCost = savedAPIs.cost
    GetRuneCooldown = savedAPIs.runes
    JustACBridgeDB.debugEnabled = savedAPIs.debug
end

-- Legacy ordering guard remains unchanged; 12.1 requires the full sequence
-- and cannot use a manually cast Pillar/aura as a Breath/Fury bypass.
local currentBuildInfo = GetBuildInfo
GetBuildInfo = function() return "12.0.0", "", "", 120007 end
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

GetBuildInfo = currentBuildInfo
eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
-- Frost M4 treats JustAC's actual queue as the only authority for ranged
-- movement filler. A queued Howling Blast passes through, but highlight/proc
-- data and the specialization fallback cannot invent one when it is absent.
testQueue = { 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

testQueue = { 51271, 49184 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation().spellID == 49184)
assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 49184)

highlightSpellID = 49184
testQueue = { 51271 }
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
assert(JustACBridge.GetPreserveBurstRecommendation() == nil)

testQueue = {}
JustACBridge.Refresh()
assert(JustACBridge.GetLosslessRecommendation() == nil)
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
assert(JustACBridge.GetLosslessRecommendation() == nil)

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

-- Legacy policies may explicitly opt into a bound final fallback. Midnight
-- 12.1 Frost/Unholy DK deliberately opt out for both outputs: an exhausted
-- authoritative queue is allowed to remain empty rather than inventing a
-- ranged filler merely to ensure that every held-key frame sends something.
local fallbackCases = {
    { class = "MAGE", spec = 2, spell = 2948 },
    { class = "MAGE", spec = 3, spell = 30455 },
    { class = "DEATHKNIGHT", spec = 1, spell = 50842 },
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
for _, spec in ipairs({ 2, 3 }) do
    classFile, specIndex = "DEATHKNIGHT", spec
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    testQueue = {}
    JustACBridge.Refresh()
    assert(JustACBridge.GetLosslessRecommendation() == nil)
    assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
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

-- A real queue entry must not be granted final-fallback immunity merely
-- because its spell appeared in an old specialization fallback list. Three
-- distinct failures suppress it normally; with no second action, output is
-- intentionally empty until the suppression window expires.
testQueue = { 47541 }
JustACBridge.Refresh()
for index = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player",
        "fallback-fail-" .. index, 47541)
end
JustACBridge.Refresh()
local finalFallback = JustACBridge.GetCurrentRecommendation()
assert(finalFallback == nil)
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

-- End-to-end Sunfury Orb regression: real arcane121 -> real JustAC capability
-- adapter -> policy/core -> both exports, not a hand-built recommendation.
-- This isolated final block continues to use only the mock runtime above.
do
    now, speed, speedSecret, auraSecret = 2000, 0, false, false
    classFile, specIndex, inCombat = "MAGE", 1, true
    targetExists, targetAttackable, targetDead = true, true, false
    unlearnedSpells, unusableSpells, unboundSpells = {}, {}, {}
    effectiveSpellOverrides, burstTriggers, burstCues = {}, {}, {}
    cooldownSpellID, cooldownEndsAt = nil, 0
    -- Only Sunfury is owned; Pulse is deliberately absent to reproduce the
    -- old terminal-Blast path without a later unknown Pulse predicate.
    unlearnedSpells[443739], unlearnedSpells[1241462] = true, true
    playerAuras[235450] = {}
    testQueue = { 30451, 44425 }
    local arcaneCharges, orbReady, missilesProc = 1, true, false
    local api = {
        IsSpellUsable = function(id) return unusableSpells[id] ~= true end,
        IsSpellOnCooldown = function(id) return id == 365350 or id == 321507 end,
        IsSpellReady = function(id) return id == 153626 and orbReady end,
        GetClassResourcePoints = function() return arcaneCharges, 4, "arcane_charges" end,
        GetAuraStackAtLeast = function() return false end,
        IsSpellProcced = function(id) return id == 5143 and missilesProc end,
        GetDisplaySpellID = function(id) return id end,
        AreAurasSecret = function() return true end,
    }
    local scanner = {
        GetSpellHotkey = function(id)
            if unboundSpells[id] then return "" end
            return id == 153626 and "E" or "2"
        end,
    }
    local queueAPI = { GetCurrentSpellQueue = function() return testQueue end }
    LibStub = function(name)
        if name == "JustAC-BlizzardAPI" then return api end
        if name == "JustAC-ActionBarScanner" then return scanner end
        if name == "JustAC-SpellQueue" then return queueAPI end
        if name == "JustAC-SpellDB" then
            return { IsChanneled = function(id) return channeledSpells[id] == true end }
        end
    end
    dofile("JustACBridge.core/Sources/JustAC.lua")
    dofile("JustACBridge.core/Sources/Arcane121.lua")
    SlashCmdList.JUSTACBRIDGE("source auto")
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    eventFrame.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    local arcane = assert(JustACBridgeRecommendationSources.Get("arcane121"))
    assert(JustACBridge.GetRecommendationSource().id == "arcane121")

    local function assertExports(expected)
        JustACBridge.Refresh()
        for _, result in ipairs({ JustACBridgeExport.first, JustACBridgeExport.reserveBurst }) do
            assert(result and result.spellID == expected,
                "Sunfury core expected=" .. expected .. " got=" .. tostring(result and result.spellID))
            if expected == 153626 then assert(result.hotkey == "E") end
        end
        assert(JustACBridge.GetLosslessRecommendation().spellID == expected)
        assert(JustACBridge.GetPreserveBurstRecommendation().spellID == expected)
    end

    -- Even a newly proven source-owned Orb must observe the startup delay.
    assert(arcane.GetQueue()[1] == 153626, "low-charge source must select Orb before core filtering")
    assertExports(30451)
    now = now + 0.81
    for _, n in ipairs({ 0, 1, 2 }) do
        arcaneCharges = n
        assertExports(153626)
    end
    for _, n in ipairs({ 3, 4 }) do
        arcaneCharges = n
        assertExports(30451)
    end
    arcaneCharges = 2
    unboundSpells[153626] = true
    assertExports(30451)
    unboundSpells[153626], unlearnedSpells[153626] = nil, true
    assertExports(30451)
    unlearnedSpells[153626], unusableSpells[153626] = nil, true
    assertExports(30451)
    unusableSpells[153626], orbReady = nil, false
    assertExports(30451)
    orbReady = nil
    assertExports(30451)
    assert(arcane.GetQueue() == testQueue)
    orbReady = true
    assertExports(153626)

    -- A higher priority proc still wins, and any current Missiles channel
    -- keeps both protocol outputs busy even when Orb becomes the next action.
    missilesProc = true
    assertExports(5143)
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "orb-test-channel", 5143)
    missilesProc = false
    JustACBridge.Refresh()
    assert(JustACBridge.GetPlayerCastState().channelBlocksInput == true)
    local cells = namedFrames.JustACBridgePixelFrame.textures
    local flags = 0
    for bit = 1, 8 do flags = flags * 2 + cells[48 + bit].bit end
    assert(math.floor(flags / 64) % 2 == 1,
        "protected channel must set the shared input-blocking protocol bit")
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "orb-test-channel", 5143)
    assertExports(153626)
    assert(JustACBridge.GetPlayerCastState().channelBlocksInput == false)

    speed = 7
    eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
    JustACBridge.Refresh()
    assert(JustACBridge.GetLosslessRecommendation() == nil)
    assert(JustACBridge.GetPreserveBurstRecommendation() == nil)
    -- Neither unsafe Orb/Blast nor an unproven later Barrage may be sent.
    speed = 0
    eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
    assertExports(30451)
    now = now + 0.79
    assertExports(30451)
    now = now + 0.02
    assertExports(153626)
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "orb-test-blink", 1953)
    assertExports(30451)
    now = now + 1.99
    assertExports(30451)
    now = now + 0.02
    assertExports(153626)
end

-- Keep the user's BM preservation contract when merging the 12.1 sources.
-- M5 can still use both held skills; M4 chooses only safe source-queue entries.
do
    classFile, specIndex = "HUNTER", 1
    speed, speedSecret = 0, false
    testPreserveQueue, burstTriggers = nil, {}
    SlashCmdList.JUSTACBRIDGE("source test")
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    for _, testSpeed in ipairs({ 0, 7 }) do
        speed = testSpeed
        for _, spellID in ipairs({ 19574, 1264355, 1264359 }) do
            testQueue = { spellID, 19574, 1264355, 1264359, 34026 }
            JustACBridge.Refresh()
            assert(JustACBridge.GetLosslessRecommendation().spellID == spellID)
            assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 34026)
        end
    end
    speed = 0
    JustACBridgeDB.reserveOverrides.HUNTER_1 = {
        exclude = { [19574] = true, [1264355] = true, [1264359] = true },
    }
    eventFrame.OnEvent(eventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
    testQueue = { 19574, 1264355, 1264359, 34026 }
    JustACBridge.Refresh()
    assert(JustACBridge.GetLosslessRecommendation().spellID == 19574)
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 34026)
    testQueue = { 19574, 1264355, 1264359 }
    for _, spellID in ipairs({ 19574, 1264355, 1264359, 34026 }) do
        highlightSpellID = spellID
        JustACBridge.Refresh()
        assert(JustACBridge.GetLosslessRecommendation().spellID == 19574)
        assert(JustACBridge.GetPreserveBurstRecommendation() == nil,
            "source-queue-only M4 must not reintroduce a held or highlighted skill")
    end
    testQueue, highlightSpellID = { 34026 }, nil
    JustACBridge.Refresh()
    assert(JustACBridge.GetPreserveBurstRecommendation().spellID == 34026)
    JustACBridgeDB.reserveOverrides.HUNTER_1 = nil
end

print("core integration tests passed")
