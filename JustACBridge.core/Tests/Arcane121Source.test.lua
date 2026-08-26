-- Independent Arcane 12.1 source: exact decisions and JustAC fallback.

local now = 100
local combat = false
local hero = "sunfury"
local cooldowns = {}
local usable = {}
local lustrousOne
local lustrousTwo
local missilesProcced = false
local salvoStacks
local charges = 4
local displayBlast = 30451
local orbChargeReady = true
local targetGUID = "Creature-0-0-0-0-100-0000000001"
local targetExists = true
local targetAttackable = true
local targetDead = false
local surgeCooldownRemaining = 60
local knownSpells = {
    [30451] = true,
    [44425] = true,
    [5143] = true,
    [153626] = true,
    [321507] = true,
    [365350] = true,
    [1241462] = true,
}
local auraStacks = {}
local rawQueue = { 30451, 44425 }
local sourceFrame

function GetTime() return now end
function UnitAffectingCombat() return combat end
function UnitExists(unit) return unit == "target" and targetExists end
function UnitCanAttack(_, unit) return unit == "target" and targetAttackable end
function UnitIsDeadOrGhost(unit) return unit == "target" and targetDead end
function UnitGUID(unit) return unit == "target" and targetExists and targetGUID or nil end
function UnitClass() return "Mage", "MAGE" end
function GetSpecialization() return 1 end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function IsPlayerSpell(id)
    if id == 443739 then return hero == "spellslinger" end
    if id == 448601 then return hero == "sunfury" end
    return knownSpells[id] == true
end
function IsSpellKnown(id) return knownSpells[id] == true end

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
        if id == 365350 and cooldowns[id] == true then
            return { remaining = surgeCooldownRemaining }
        end
    end,
}

local bapi = {
    IsSpellUsable = function(id) return usable[id] ~= false end,
    IsSpellOnCooldown = function(id) return cooldowns[id] == true end,
    -- Charge-aware readiness stays true at 1/2 even though the recharge
    -- DurationObject (and therefore IsSpellOnCooldown) is active.
    IsSpellReady = function(id)
        if id == 153626 then return orbChargeReady end
        return cooldowns[id] ~= true
    end,
    GetAuraStackAtLeast = function(_, id, threshold)
        if id == 1295147 then
            if threshold == 1 then return lustrousOne end
            if threshold == 2 then return lustrousTwo end
        elseif id == 1242974 then
            return salvoStacks == nil and nil or salvoStacks >= threshold
        elseif auraStacks[id] ~= nil then
            return auraStacks[id] >= threshold
        end
    end,
    IsSpellProcced = function(id) return id == 5143 and missilesProcced end,
    GetClassResourcePoints = function() return charges, 4, "arcane_charges" end,
    GetDisplaySpellID = function(id) return id == 30451 and displayBlast or id end,
    AreAurasSecret = function() return combat end,
    IsDurationBelowSeconds = function(duration, seconds)
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

-- Precombat delegates to JustAC; the core pairing gate owns any raw Touch.
local queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("precombat%-delegate%-surge%-first"))
local preserve = source.GetPreserveQueue()
assert(preserve[1] == rawQueue[1])

-- M5's hard pair outranks the Spellslinger opening Orb. M4 still holds both
-- cooldowns and may execute that normal Orb action.
hero, combat = "spellslinger", true
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)
preserve = source.GetPreserveQueue()
assert(preserve[1] == 153626)
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 153626)
lustrousOne, lustrousTwo = nil, nil
usable[321507] = false
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(not source.GetDecisionTrace():match("cooldowns.arcane_surge"))
usable[321507] = true
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)
assert(source.GetDecisionTrace():match("touch%-ready%+hard%-pair"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
-- Reliability override: the M5 pair advances only on authoritative successful
-- casts and immediately recommends Touch after Surge. A lagging cooldown must
-- never export the same Surge instance twice.
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("expect%-touch"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 321507)

-- A Surge -> Touch credential belongs to exactly one hostile target. Switching
-- clears it permanently. Because Surge is now on cooldown, the new target may
-- independently receive the explicitly allowed direct Touch.
cooldowns[365350] = true
surgeCooldownRemaining = 60
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
targetGUID = "Creature-0-0-0-0-200-0000000002"
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
rawQueue = { 321507, 30451 }
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil and source._Test.state.surgeCastAt == nil)
assert(queue[1] == 321507)
targetGUID = "Creature-0-0-0-0-100-0000000001"
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
queue = source.GetQueue()
assert(queue[1] == 321507)
rawQueue = { 30451, 44425 }
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
targetDead = true
sourceFrame.OnEvent(sourceFrame, "UNIT_HEALTH", "target")
targetDead = false
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil and source._Test.state.surgeCastAt == nil)
assert(queue[1] == 321507)

sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
now = now + 10.1
queue = source.GetQueue()
assert(source._Test.state.burstStage == nil)
assert(not source.GetDecisionTrace():match("cooldowns.big_burst_sequence"))

-- M4 skips Surge but continues through the same owned normal priority instead
-- of dropping back to the raw JustAC head.
salvoStacks = 20
preserve = source.GetPreserveQueue()
assert(preserve[1] == 44425)
assert(source.GetDecisionTrace():match("spellslinger.arcane_barrage"))
salvoStacks = nil

-- The explicit reliability rule no longer lets Lustrous Gleam delay a ready
-- Surge/Touch pair.
cooldowns[365350] = false
now = now + 10.1
lustrousOne, lustrousTwo = true, false
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)
lustrousOne, lustrousTwo = true, true
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)

-- Whenever Surge is positively not ready, Touch releases directly. No prior
-- Barrage/Bolt and no cooldown-duration threshold are required.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
cooldowns[365350] = true
now = now + 10.1
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("surge%-cooldown%-direct"))

-- Remaining cooldown is intentionally irrelevant to the direct-Touch rule.
surgeCooldownRemaining = 4
queue = source.GetQueue()
assert(queue[1] == 321507)
surgeCooldownRemaining = nil
queue = source.GetQueue()
assert(queue[1] == 321507)
surgeCooldownRemaining = 60

-- Liquid Luster observations no longer gate the explicit pair.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1295132)
lustrousOne, lustrousTwo = nil, nil
cooldowns[365350] = false
queue = source.GetQueue()
assert(queue[1] == 365350 and queue[2] == 321507)

-- A fresh successful Surge re-arms the paired Touch branch.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
cooldowns[365350] = true
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("expect%-touch"))

-- M4 holds Touch too, then continues through the same owned normal priority.
salvoStacks = 20
preserve = source.GetPreserveQueue()
assert(preserve[1] == 44425)
assert(source.GetDecisionTrace():match("spellslinger.arcane_barrage"))
salvoStacks = nil

-- Sunfury's first normal rule is also owned when both proc and Salvo threshold
-- are exact; otherwise it delegates instead of treating unknown as false.
hero = "sunfury"
now = now + 20
source._Test.state.lastGCDSpellID = nil
cooldowns[365350] = true
cooldowns[321507] = true
missilesProcced, salvoStacks = true, 11
queue = source.GetQueue()
assert(queue[1] == 5143)
preserve = source.GetPreserveQueue()
assert(preserve[1] == 5143)
salvoStacks = nil
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("arcane%-salvo<12%-unknown"))

-- Regression: when JustAC has already put capped-Salvo Barrage ahead of both
-- available Missiles and Blast, an unknowable higher source predicate must not
-- rewrite that order. This is the exact live failure that previously spammed
-- Blast at 25 Salvo despite JustAC recommending Barrage.
rawQueue = { 44425, 5143, 30451 }
salvoStacks, charges, missilesProcced = 25, 4, true
cooldowns[321507], cooldowns[365350] = true, true
auraStacks[453413] = nil
source._Test.state.surgeCastAt = nil
queue = source.GetQueue()
assert(queue == rawQueue and queue[1] == 44425)
assert(source.GetDecisionTrace():match("fallback=true"))
preserve = source.GetPreserveQueue()
assert(preserve == rawQueue and preserve[1] == 44425)
assert(source.GetDecisionTrace():match("fallback=true"))

-- A positively unavailable Touch is an explicit legality deletion. Fallback
-- must preserve the exact relative order of every remaining JustAC action.
rawQueue = { 153626, 44425, 321507, 30451 }
salvoStacks = nil
queue = source.GetQueue()
assert(queue ~= rawQueue)
assert(queue[1] == 153626 and queue[2] == 44425 and queue[3] == 30451
    and queue[4] == nil)
assert(source.GetDecisionTrace():match("fallback=true"))
preserve = source.GetPreserveQueue()
-- Preserve-source output stays raw; the M4 core reserve/readiness gate owns
-- Touch deletion there.
assert(preserve == rawQueue)
assert(source.GetDecisionTrace():match("fallback=true"))

-- A fallback without Touch must be the original table and original order; the
-- source may not inject Blast when JustAC omitted it.
rawQueue = { 5143, 44425, 1449, 153626 }
queue = source.GetQueue()
assert(queue == rawQueue)
assert(queue[1] == 5143 and queue[2] == 44425 and queue[3] == 1449
    and queue[4] == 153626)
preserve = source.GetPreserveQueue()
assert(preserve == rawQueue)
rawQueue = { 30451, 44425 }

-- A usable/cooldown result alone must never export an action the character
-- does not positively own.
knownSpells[30451] = false
rawQueue = { 44425, 1449 }
queue = source.GetQueue()
assert(queue == rawQueue and queue[1] == 44425)
knownSpells[30451] = true
rawQueue = { 30451, 44425 }

-- Normal-list branches are source-owned whenever every higher predicate is
-- false or a target-count-independent OR branch is true.
hero = "spellslinger"
missilesProcced, salvoStacks, charges = false, 20, 4
queue = source.GetQueue()
assert(queue[1] == 44425)

assert(source.GetDecisionTrace():match("four%-charges%+salvo%-threshold"))

salvoStacks, charges, missilesProcced = 10, 2, true
queue = source.GetQueue()
assert(queue[1] == 5143)
assert(source.GetDecisionTrace():match("spellslinger.arcane_missiles"))

salvoStacks, charges, missilesProcced = 0, 4, false
cooldowns[153626], orbChargeReady = true, false
queue = source.GetQueue()
assert(queue[1] == 30451)
assert(source.GetDecisionTrace():match("spellslinger.arcane_blast"))

hero = "sunfury"
cooldowns[153626] = false
auraStacks[453413] = 1
queue = source.GetQueue()
assert(queue[1] == 44425)
assert(source.GetDecisionTrace():match("arcane%-soul"))

-- Capped Salvo is an independent Sunfury Barrage branch. It does not require
-- Clearcasting when four charges and the exact Surge timing gate are proven.
auraStacks[453413] = nil
salvoStacks, charges, missilesProcced = 25, 4, false
cooldowns[321507], cooldowns[365350] = true, true
source._Test.state.lastGCDSpellID = nil
source._Test.state.surgeCastAt = now
queue = source.GetQueue()
assert(queue[1] == 44425)
assert(source.GetDecisionTrace():match("four%-charges%+salvo=25"))

-- Regression: Arcane Orb is a multi-charge spell. At 1/2 its recharge duration
-- is active, but the remaining charge must still be treated as castable.
hero = "spellslinger"
source._Test.state.orbCastAt = now -- skip the once-per-combat opening line
rawQueue = { 30451, 44425 }
charges, salvoStacks, missilesProcced = 2, 0, false
cooldowns[365350], cooldowns[321507] = true, true
cooldowns[153626], orbChargeReady = true, true
queue = source.GetQueue()
assert(queue[1] == 153626)
assert(source.GetDecisionTrace():match("spellslinger.arcane_orb"))
preserve = source.GetPreserveQueue()
assert(preserve[1] == 153626)

-- At 0/2 the charge-aware reader is false, so the source must not inject Orb.
orbChargeReady = false
queue = source.GetQueue()
assert(queue[1] ~= 153626)
preserve = source.GetPreserveQueue()
assert(preserve[1] ~= 153626)

-- An unreadable charge state is unknown, not false and not a guessed cast.
orbChargeReady = nil
queue = source.GetQueue()
assert(queue == rawQueue)
assert(source.GetDecisionTrace():match("orb%-readiness%-unknown"))

-- Sunfury uses the same charge-aware evidence: one remaining Orb is castable
-- when Arcane Charges need rebuilding, while 0/2 and unknown never inject it.
hero, charges, orbChargeReady = "sunfury", 0, true
queue = source.GetQueue()
assert(queue[1] == 153626)
assert(source.GetDecisionTrace():match("sunfury.arcane_orb"))
orbChargeReady = false
queue = source.GetQueue()
assert(queue[1] ~= 153626)
orbChargeReady = nil
queue = source.GetQueue()
assert(queue == rawQueue)
assert(source.GetDecisionTrace():match("orb%-readiness%-unknown"))

print("arcane 12.1 source tests passed")
