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
local knownSpells = {}
local auraStacks = {}
local rawQueue = { 30451, 44425 }
local sourceFrame

function GetTime() return now end
function UnitAffectingCombat() return combat end
function UnitExists(unit) return unit == "target" end
function UnitCanAttack(_, unit) return unit == "target" end
function UnitClass() return "Mage", "MAGE" end
function GetSpecialization() return 1 end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function IsPlayerSpell(id)
    if id == 443739 then return hero == "spellslinger" end
    if id == 448601 then return hero == "sunfury" end
    return knownSpells[id] == true
end

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

-- Sunfury owns the current SimC precombat Surge.
local queue = source.GetQueue()
assert(queue[1] == 365350)
assert(source.GetDecisionTrace():match("precombat.arcane_surge"))

-- Spellslinger owns one opening Orb; after its successful cast it advances to
-- Surge without waiting for Assisted Combat to surface that cooldown.
hero, combat = "spellslinger", true
queue = source.GetQueue()
assert(queue[1] == 153626)
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 153626)
lustrousOne, lustrousTwo = nil, nil
queue = source.GetQueue()
assert(queue[1] == 365350)
assert(source.GetDecisionTrace():match("lustrous%-missing%-observed"))

-- Exactly one Gleam stack holds; two stacks release Surge.
lustrousOne, lustrousTwo = true, false
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("fallback=true"))
lustrousOne, lustrousTwo = true, true
queue = source.GetQueue()
assert(queue[1] == 365350)

-- If a Liquid Luster was observed but its combat stacks are secret, the
-- source does not guess and returns the exact JustAC fallback queue.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1295132)
lustrousOne, lustrousTwo = nil, nil
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("lustrous%-secret%-after%-potion"))

-- Touch is source-owned only when the complete higher-priority branch is
-- proven: a successful Barrage immediately inside the observed Surge window.
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 365350)
sourceFrame.OnEvent(sourceFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 44425)
cooldowns[365350] = true
queue = source.GetQueue()
assert(queue[1] == 321507)
assert(source.GetDecisionTrace():match("cooldowns.touch_of_the_magi"))

-- M4 gets only the untouched JustAC queue, never the custom M5 head.
local preserve = source.GetPreserveQueue()
assert(preserve[1] == rawQueue[1] and preserve[2] == rawQueue[2])

-- Sunfury's first normal rule is also owned when both proc and Salvo threshold
-- are exact; otherwise it delegates instead of treating unknown as false.
hero = "sunfury"
now = now + 20
source._Test.state.lastGCDSpellID = nil
cooldowns[365350] = true
missilesProcced, salvoStacks = true, 11
queue = source.GetQueue()
assert(queue[1] == 5143)
salvoStacks = nil
queue = source.GetQueue()
assert(queue[1] == rawQueue[1])
assert(source.GetDecisionTrace():match("arcane%-salvo<12%-unknown"))

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

print("arcane 12.1 source tests passed")
