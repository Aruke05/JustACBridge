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
local equippedTierPieces = 4
local tierSlots = { [1] = 1, [3] = 2, [5] = 3, [7] = 4, [10] = 5 }
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
local unknownAuraThresholds = {}
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
function GetInventoryItemID(_, slot)
    local piece = tierSlots[slot]
    return piece and piece <= equippedTierPieces and (100000 + piece) or nil
end
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
C_Item = {
    GetSetBonusesForSpecializationByItemID = function(specID, itemID)
        if specID == 62 and itemID >= 100001 and itemID <= 100005 then
            return { 1296580, 1296582 }
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
        if unknownAuraThresholds[tostring(id) .. ":" .. tostring(threshold)] then
            return nil
        end
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

-- With four equipped Season 2 pieces, below 8 Cumulative Power the first Bolt
-- line is false and the independently proven capped-Salvo Barrage remains ahead.
auraStacks[453413] = 0
auraStacks[1296930] = 0
auraStacks[365350] = 0
displayBlast = 1295924
salvoStacks, charges, missilesProcced = 25, 4, false
rawQueue = { 44425, 30451 }
queue = source.GetQueue()
assert(queue[1] == 44425)
assert(source.GetDecisionTrace():match("sunfury.arcane_barrage"))

-- Capped Cumulative Power restores the high Bolt line.
auraStacks[1296930] = 8
queue = source.GetQueue()
assert(queue[1] == 1295924)
assert(source.GetDecisionTrace():match("season2%-4pc%+cumulative=8"))

-- Without 4pc, the same live Bolt must be spent before another capped-Salvo
-- Barrage. Otherwise the non-stacking proc can be overwritten and lost.
equippedTierPieces = 2
sourceFrame.OnEvent(sourceFrame, "PLAYER_EQUIPMENT_CHANGED", 7)
auraStacks[1296930] = 0
queue = source.GetQueue()
assert(queue[1] == 1295924)
assert(source.GetDecisionTrace():match("no%-season2%-4pc%+soul%-down"))

-- Missing equipment evidence is unknown: preserve the raw JustAC order rather
-- than guessing either the 2pc or 4pc priority.
local savedSetReader = C_Item.GetSetBonusesForSpecializationByItemID
C_Item.GetSetBonusesForSpecializationByItemID = nil
sourceFrame.OnEvent(sourceFrame, "PLAYER_EQUIPMENT_CHANGED", 7)
queue = source.GetQueue()
assert(queue == rawQueue and queue[1] == 44425)
assert(source.GetDecisionTrace():match("season2%-4pc%-state%-unknown"))
C_Item.GetSetBonusesForSpecializationByItemID = savedSetReader
equippedTierPieces = 4
sourceFrame.OnEvent(sourceFrame, "PLAYER_EQUIPMENT_CHANGED", 7)

-- Unreadable Cumulative Power remains a hard fallback barrier.
auraStacks[1296930] = nil
queue = source.GetQueue()
assert(queue == rawQueue and queue[1] == 44425)
assert(source.GetDecisionTrace():match("cumulative%-power%-unknown"))
displayBlast = 30451
rawQueue = { 30451, 44425 }

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

-- Moving never creates a Barrage condition. The source proof hook reuses the
-- exact ordinary APL predicates and fails closed for false, unknown, unusable,
-- out-of-combat and unsupported states.
source._Test.state.surgeCastAt = nil
source._Test.state.lastGCDSpellID = nil
auraStacks[453413], auraStacks[365350] = 0, 0
cooldowns[321507], cooldowns[365350] = true, true
charges, salvoStacks, missilesProcced = 4, 8, false
local allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason:match("condition%-false"))

salvoStacks = 25
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason:match("salvo=25"))

salvoStacks, missilesProcced = 12, true
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason:match("clearcasting%+salvo>=12"))

salvoStacks, missilesProcced = nil, false
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason:match("unknown"))

auraStacks[453413], salvoStacks, charges = 1, 0, 0
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason == "arcane-soul")
usable[44425] = false
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason:match("unusable"))
usable[44425] = true
local savedCooldownReader = bapi.IsSpellOnCooldown
bapi.IsSpellOnCooldown = nil
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason == "barrage-readiness-unknown")
bapi.IsSpellOnCooldown = savedCooldownReader
combat = false
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason == "not-positively-in-combat")
combat = true

hero, charges, salvoStacks = "spellslinger", 4, 20
source._Test.state.lastGCDSpellID = nil
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason == "four-charges+salvo-threshold")
source._Test.state.lastGCDSpellID = 365350
unknownAuraThresholds["1242974:10"] = true
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason == "four-charges+salvo-threshold")
unknownAuraThresholds["1242974:10"] = nil
salvoStacks = 19
source._Test.state.lastGCDSpellID = nil
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == false and movementReason:match("condition%-false"))
source._Test.state.lastGCDSpellID, salvoStacks = 365350, 10
allowed, movementReason = source.IsMovementFallbackAllowed(44425)
assert(allowed == true and movementReason == "prev-surge+salvo-threshold")
source._Test.state.lastGCDSpellID = nil
auraStacks[453413] = 0

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

-- Sunfury's current low-charge Orb line is <3, not <1. Exercise both routes
-- with and without Pulse, including an Orb already ahead of Blast in JustAC.
do
    local savedResourceReader = bapi.GetClassResourcePoints
    local savedReadyReader = bapi.IsSpellReady
    local savedUsableReader = bapi.IsSpellUsable
    local savedSecretReader = issecretvalue

    local function resetOrbCase()
        hero, combat = "sunfury", true
        charges, salvoStacks, missilesProcced = 2, 0, false
        displayBlast, orbChargeReady = 30451, true
        knownSpells[153626], knownSpells[1241462] = true, false
        cooldowns[365350], cooldowns[321507] = true, true
        cooldowns[153626], usable[153626] = true, true -- one usable charge
        auraStacks[453413], auraStacks[365350] = 0, 0
        source._Test.state.surgeCastAt = nil
        source._Test.state.burstStage = nil
        source._Test.state.cleanAuraBaseline = false
        rawQueue = { 30451, 44425, 153626 }
        bapi.GetClassResourcePoints = savedResourceReader
        bapi.IsSpellReady = savedReadyReader
        bapi.IsSpellUsable = savedUsableReader
        issecretvalue = savedSecretReader
    end

    local function assertBoth(expected, rule)
        for _, select in ipairs({ source.GetQueue, source.GetPreserveQueue }) do
            local result = select()
            assert(result[1] == expected, "Sunfury Orb charges=" .. tostring(charges)
                .. " expected=" .. expected .. " got=" .. tostring(result[1]))
            assert(source.GetDecisionTrace():find(rule, 1, true))
        end
    end

    local function assertRawBoth(reason)
        for _, select in ipairs({ source.GetQueue, source.GetPreserveQueue }) do
            assert(select() == rawQueue, "unknown must preserve the original queue")
            local trace = source.GetDecisionTrace()
            assert(trace:find("fallback=true", 1, true))
            assert(trace:find(reason, 1, true))
        end
        assert(rawQueue[1] == 30451 and rawQueue[2] == 44425 and rawQueue[3] == 153626)
    end

    for _, pulseKnown in ipairs({ false, true }) do
        for _, orbFirst in ipairs({ false, true }) do
            for _, n in ipairs({ 1, 2, 0, 3, 4 }) do
                resetOrbCase()
                knownSpells[1241462], charges = pulseKnown, n
                if orbFirst then rawQueue = { 153626, 30451, 44425 } end
                if n < 3 then
                    assertBoth(153626, "rule=sunfury.arcane_orb detail=charges<3")
                elseif pulseKnown then
                    -- The later Pulse AOE predicate is unknown, not permission
                    -- to reorder JustAC or infer a low-charge Orb decision.
                    for _, select in ipairs({ source.GetQueue, source.GetPreserveQueue }) do
                        assert(select() == rawQueue)
                        assert(source.GetDecisionTrace():find(
                            "sunfury-pulse-enemy-count-unknown", 1, true))
                    end
                else
                    assertBoth(30451, "rule=sunfury.arcane_blast")
                end
            end
        end
    end

    for _, n in ipairs({ 1, 2 }) do
        resetOrbCase()
        charges = n
        orbChargeReady = false
        rawQueue = { 30451, 44425 }
        assertBoth(30451, "rule=sunfury.arcane_blast")
        orbChargeReady, usable[153626] = true, false
        assertBoth(30451, "rule=sunfury.arcane_blast")
        usable[153626], knownSpells[153626] = true, false
        assertBoth(30451, "rule=sunfury.arcane_blast")

        -- Exact low charges never leapfrog higher normal-list actions.
        resetOrbCase()
        charges, missilesProcced, salvoStacks = n, true, 11
        assertBoth(5143, "rule=sunfury.arcane_missiles")
        missilesProcced, displayBlast, auraStacks[1296930] = false, 1295924, 8
        assertBoth(1295924, "rule=sunfury.prismatic_bolt")
        displayBlast, auraStacks[453413] = 30451, 1
        assertBoth(44425, "rule=sunfury.arcane_barrage")
    end

    -- Fault injection: no stale low-charge/readiness value may survive an
    -- unavailable, malformed, throwing, or secret result on the next refresh.
    for _, fault in ipairs({ "nil", "wrong-type", "throw", "missing", "secret" }) do
        resetOrbCase()
        assertBoth(153626, "rule=sunfury.arcane_orb")
        if fault == "missing" then
            bapi.GetClassResourcePoints = nil
        else
            bapi.GetClassResourcePoints = function()
                if fault == "throw" then error("resource unavailable") end
                if fault == "nil" then return nil, 4, "arcane_charges" end
                if fault == "wrong-type" then return "2", 4, "arcane_charges" end
                return 2, 4, "arcane_charges"
            end
            if fault == "secret" then issecretvalue = function(v) return v == 2 end end
        end
        assertRawBoth("arcane-charges-unknown")

        resetOrbCase()
        assertBoth(153626, "rule=sunfury.arcane_orb")
        if fault == "missing" then
            bapi.IsSpellReady = nil
        else
            local secretReadyPending = false
            bapi.IsSpellReady = function()
                if fault == "throw" then error("charge readiness unavailable") end
                if fault == "nil" then return nil end
                if fault == "wrong-type" then return 1 end
                secretReadyPending = fault == "secret"
                return true
            end
            if fault == "secret" then
                issecretvalue = function()
                    local secret = secretReadyPending
                    secretReadyPending = false
                    return secret
                end
            end
        end
        assertRawBoth("orb-readiness-unknown")

        resetOrbCase()
        assertBoth(153626, "rule=sunfury.arcane_orb")
        local secretUsablePending = false
        if fault == "missing" then
            bapi.IsSpellUsable = nil
        else
            bapi.IsSpellUsable = function(id)
                if id ~= 153626 then return savedUsableReader(id) end
                if fault == "throw" then error("Orb usability unavailable") end
                if fault == "nil" then return nil end
                if fault == "wrong-type" then return 1 end
                secretUsablePending = true
                return true
            end
        end
        if fault == "secret" then
            issecretvalue = function()
                local secret = secretUsablePending
                secretUsablePending = false
                return secret
            end
        end
        assertRawBoth("readiness-unknown")
    end

    resetOrbCase()
    unknownAuraThresholds["453413:1"] = true
    assertRawBoth("arcane-soul-state-unknown")
    unknownAuraThresholds["453413:1"] = nil
    missilesProcced = true
    unknownAuraThresholds["1242974:12"] = true
    assertRawBoth("arcane-salvo<12-unknown")
    unknownAuraThresholds["1242974:12"] = nil
    resetOrbCase()

    -- Low charges do not override M5's hard Surge/Touch pair. M4 continues to
    -- reserve both cooldowns and may independently select its normal Orb.
    cooldowns[365350], cooldowns[321507] = false, false
    assert(source.GetQueue()[1] == 365350)
    assert(source.GetPreserveQueue()[1] == 153626)
    sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "orb-test-surge", 365350)
    assert(source.GetQueue()[1] == 321507)
    assert(source.GetPreserveQueue()[1] == 153626)
    sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "orb-test-touch", 321507)
    resetOrbCase()
end

print("arcane 12.1 source tests passed")
