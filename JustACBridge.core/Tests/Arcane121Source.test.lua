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

-- Precombat delegates to JustAC after the source removes any raw Touch. Surge
-- may lead; automatic Touch is emitted only by a proven in-combat branch.
local queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("precombat%-delegate%-surge%-first"))
local preserve = source.GetPreserveQueue()
assert(preserve[1] == rawQueue[1])

-- Spellslinger still owns one opening Orb. Surge is the first paired cooldown;
-- after its successful event, a confirmed Barrage/Bolt setup emits Touch.
hero, combat = "spellslinger", true
queue = source.GetQueue()
assert(queue[1] == 153626)
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
assert(queue[1] == 365350)
assert(source.GetDecisionTrace():match("before%-touch%+lustrous%-missing%-observed"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
-- The guide-owned big burn advances only on authoritative successful casts:
-- Surge -> Missiles -> Barrage -> Touch. A lagging cooldown must never export
-- the same Surge instance twice.
queue = source.GetQueue()
assert(queue[1] == 5143)
assert(source.GetDecisionTrace():match("expect%-missiles"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 5143)
queue = source.GetQueue()
assert(queue[1] == 44425)
assert(source.GetDecisionTrace():match("expect%-barrage"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("expect%-touch"))
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 321507)

-- A Barrage/Touch travel credential belongs to exactly one hostile target.
-- Switching away clears it permanently; returning to the old GUID cannot
-- resurrect the credential inside its former timing window.
cooldowns[365350] = true
surgeCooldownRemaining = 60
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
targetGUID = "Creature-0-0-0-0-200-0000000002"
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
rawQueue = { 321507, 30451 }
queue = source.GetQueue()
assert(queue[1] == 30451 and queue[2] == nil)
targetGUID = "Creature-0-0-0-0-100-0000000001"
sourceFrame.OnEvent(sourceFrame, "PLAYER_TARGET_CHANGED")
queue = source.GetQueue()
assert(queue[1] == 30451 and queue[2] == nil)
rawQueue = { 30451, 44425 }
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
targetDead = true
sourceFrame.OnEvent(sourceFrame, "UNIT_HEALTH", "target")
targetDead = false
queue = source.GetQueue()
assert(queue[1] ~= 321507)

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

-- Exactly one Gleam stack holds Surge; two stacks release it before Touch.
cooldowns[365350] = false
now = now + 10.1
lustrousOne, lustrousTwo = true, false
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("lustrous=1"))
lustrousOne, lustrousTwo = true, true
queue = source.GetQueue()
assert(queue[1] == 365350)

-- When Surge is safely far enough into its cooldown, a valid Barrage setup may
-- release the independent Touch without desynchronising the next big burn.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
cooldowns[365350] = true
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
now = now + 10.1
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("small%-touch%+surge%-remains>30"))

-- A boolean "Surge is on cooldown" is insufficient for the intermediate
-- Touch. When only four seconds remain it would desynchronise the next big
-- burn, so the source removes Touch and continues the normal list. Unknown
-- duration-threshold evidence also fails closed.
surgeCooldownRemaining = 4
queue = source.GetQueue()
assert(queue[1] ~= 321507)
surgeCooldownRemaining = nil
queue = source.GetQueue()
assert(queue[1] ~= 321507)
assert(source.GetDecisionTrace():match("small%-touch%-surge%-remains>30%-unknown"))
surgeCooldownRemaining = 60

-- If a Liquid Luster was observed but its combat stacks are secret, the
-- source does not guess and returns the exact JustAC fallback queue.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1295132)
lustrousOne, lustrousTwo = nil, nil
cooldowns[365350] = false
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("lustrous%-secret%-after%-potion"))

-- A fresh successful Surge re-arms the paired Touch branch.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
cooldowns[365350] = true
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("cooldowns.touch_of_the_magi"))

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
missilesProcced, salvoStacks = true, 11
queue = source.GetQueue()
assert(queue[1] == 5143)
preserve = source.GetPreserveQueue()
assert(preserve[1] == 5143)
salvoStacks = nil
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("arcane%-salvo<12%-unknown"))

-- When an unknown predicate delegates to JustAC, neither route may treat JustAC's
-- generic instant Barrage fallback as a proven stationary charge dump. Touch
-- is always stripped from raw fallback because it requires a target-bound
-- source credential; keep the remaining actions in order, but move an existing
-- Blast before the unproven Barrage for both routes. The core movement gate
-- remains responsible for skipping the hardcast back to Barrage while moving.
rawQueue = { 153626, 44425, 321507, 30451 }
queue = source.GetQueue()
assert(queue ~= rawQueue)
assert(queue[1] == 153626 and queue[2] == 30451 and queue[3] == 44425)
assert(queue[4] == nil)
assert(source.GetDecisionTrace():match("fallback=true"))
assert(source.GetDecisionTrace():match("conservativeFallback=blast%-before%-unproven%-barrage"))
preserve = source.GetPreserveQueue()
assert(preserve ~= rawQueue)
assert(preserve[1] == 153626 and preserve[2] == 30451 and preserve[3] == 44425)
assert(preserve[4] == nil)
assert(source.GetDecisionTrace():match("fallback=true"))
assert(source.GetDecisionTrace():match("conservativeFallback=blast%-before%-unproven%-barrage"))

-- The live JustAC queue is capped and frequently omits Blast entirely while
-- still exposing generic Barrage. In that exact degraded shape, add only the
-- known baseline filler immediately before Barrage; do not invent any proc,
-- cooldown or aura-dependent action.
rawQueue = { 5143, 44425, 1449, 153626 }
queue = source.GetQueue()
assert(queue[1] == 5143 and queue[2] == 30451 and queue[3] == 44425)
assert(queue[4] == 1449 and queue[5] == 153626)
preserve = source.GetPreserveQueue()
assert(preserve[1] == 5143 and preserve[2] == 30451 and preserve[3] == 44425)
assert(source.GetDecisionTrace():match("blast%-before%-unproven%-barrage"))
rawQueue = { 30451, 44425 }

-- A usable/cooldown result alone must never export an action the character
-- does not positively own, including the conservative Arcane fallback.
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
cooldowns[153626] = true
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

print("arcane 12.1 source tests passed")
