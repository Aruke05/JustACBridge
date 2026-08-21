-- Midnight 12.1 Fire/Frost Mage and Frost/Unholy DK source decisions.

local now = 100
local combat = true
local currentClass, currentSpec = "MAGE", 2
local enemies = 1
local resourceCurrent, resourceMaximum, resourceType = 4, 6, "rune"
local rawQueue = { 999001, 999002 }
local cooldowns, usable, known, procs, auras = {}, {}, {}, {}, {}
local healthBelow, powerBelow, maxCharges = {}, {}, {}
local display = {}
local nilAuras = {}
local durationBelow = {}
local frames = {}

function GetTime() return now end
function UnitAffectingCombat() return combat end
function UnitExists(unit) return unit == "target" end
function UnitCanAttack(_, unit) return unit == "target" end
function UnitClass() return currentClass, currentClass end
function GetSpecialization() return currentSpec end
function GetBuildInfo() return "12.1.0", "", "", 120100 end
function IsPlayerSpell(id) return known[id] == true end
function IsSpellKnown(id) return known[id] == true end

function CreateFrame()
    local frame = {
        RegisterEvent = function() end,
        RegisterUnitEvent = function() end,
        SetScript = function(self, _, callback) self.OnEvent = callback end,
    }
    frames[#frames + 1] = frame
    return frame
end

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        return durationBelow[id] ~= nil and { auraInstanceID = id } or nil
    end,
}

local bapi = {
    IsSpellUsable = function(id) return usable[id] ~= false end,
    IsSpellOnCooldown = function(id) return cooldowns[id] ~= false end,
    IsSpellProcced = function(id) return procs[id] == true end,
    IsSpellAtMaxCharges = function(id)
        return maxCharges[id] == true
    end,
    GetAuraStackAtLeast = function(_, id, threshold)
        if nilAuras[id] then return nil end
        local value = auras[id]
        if type(value) == "number" then return value >= threshold end
        return value == true
    end,
    GetClassResourcePoints = function()
        return resourceCurrent, resourceMaximum, resourceType
    end,
    GetEngagedEnemyCount = function() return enemies end,
    IsUnitHealthBelow = function(_, threshold)
        return healthBelow[threshold] == true
    end,
    IsUnitPowerBelow = function(_, threshold)
        return powerBelow[threshold] == true
    end,
    GetDisplaySpellID = function(id) return display[id] or id end,
    GetAuraDurationObject = function(_, auraInstanceID) return auraInstanceID end,
    IsDurationBelowSeconds = function(duration) return durationBelow[duration] end,
}
local spellQueue = { GetCurrentSpellQueue = function() return rawQueue end }
LibStub = function(name)
    if name == "JustAC-SpellQueue" then return spellQueue end
    if name == "JustAC-BlizzardAPI" then return bapi end
end

local function reset(classFile, spec)
    currentClass, currentSpec = classFile, spec
    enemies = 1
    resourceCurrent, resourceMaximum, resourceType = 4, 6, "rune"
    cooldowns, usable, known, procs, auras = {}, {}, {}, {}, {}
    healthBelow, powerBelow, maxCharges, display, nilAuras = {}, {}, {}, {}, {}
    durationBelow = {}
    combat = true
end

local function ready(id)
    known[id] = true
    cooldowns[id] = false
end
local function cast(frame, id)
    frame.OnEvent(frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id)
    now = now + 1.5
end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/Runtime121.lua")
dofile("JustACBridge.core/Sources/Fire121.lua")
dofile("JustACBridge.core/Sources/FrostMage121.lua")
dofile("JustACBridge.core/Sources/FrostDK121.lua")
dofile("JustACBridge.core/Sources/UnholyDK121.lua")

-- Fire: owns the safe precombat/Combustion decisions, but M4 remains raw.
reset("MAGE", 2)
known[431044] = true -- Frostfire
ready(11366)
combat = false
local fire = assert(JustACBridgeRecommendationSources.Get("fire121"))
local fireFrame = frames[#frames]
durationBelow[123456] = false
assert(fire._Test.context:PlayerAuraRemainsBelow(123456, 3) == false)
local queue = fire.GetQueue()
assert(queue[1] == 11366 and fire.GetDecisionTrace():match("precombat.pyroblast"))

combat = true
ready(190319)
ready(431044)
queue = fire.GetQueue()
assert(queue[1] == 431044 and fire.GetDecisionTrace():match("combustion.precast"))
cast(fireFrame, 431044)
queue = fire.GetQueue()
assert(queue[1] == 190319 and fire.GetDecisionTrace():match("confirmed%-precast%-complete"))
cast(fireFrame, 190319)
cooldowns[190319] = true
auras[48108] = true
ready(11366)
queue = fire.GetQueue()
assert(queue[1] == 11366 and fire.GetDecisionTrace():match("combustion.spender"))
local preserve = fire.GetPreserveQueue()
assert(preserve[1] == rawQueue[1] and preserve[2] == rawQueue[2])

-- Firestarter is a proved hold, not an accidental lost Combustion.
fire._Test.context.castAt = {}
auras[48108] = false
known[205026] = true
ready(190319)
ready(431044)
queue = fire.GetQueue()
assert(queue[1] == 431044 and fire.GetDecisionTrace():match("filler.terminal"))

-- Frost Mage: opener advances only after successful casts; normal priority is
-- owned after the three confirmed opener actions.
reset("MAGE", 3)
known[431044] = true -- Frostfire
ready(205021)
ready(84714)
local frostMage = assert(JustACBridgeRecommendationSources.Get("frostmage121"))
local frostMageFrame = frames[#frames]
queue = frostMage.GetQueue()
assert(queue[1] == 205021 and frostMage.GetDecisionTrace():match("opening_ray"))
cast(frostMageFrame, 205021)
queue = frostMage.GetQueue()
assert(queue[1] == 84714 and frostMage.GetDecisionTrace():match("opening_orb"))
cast(frostMageFrame, 84714)

-- Cooldown/usable data alone must not invent an unlearned talent action.
-- The live 12.1 wrapper exposed Comet Storm as usable even when the current
-- Frost build did not own it, which left M5 pointing at a nonexistent spell.
cooldowns[205021] = true
cooldowns[84714] = true
cooldowns[153595] = false
queue = frostMage.GetQueue()
assert(queue[1] == rawQueue[1]
    and not frostMage.GetDecisionTrace():match("frostfire.comet_storm"))
ready(153595)
queue = frostMage.GetQueue()
assert(queue[1] == 153595 and frostMage.GetDecisionTrace():match("frostfire.comet_storm"))
preserve = frostMage.GetPreserveQueue()
assert(preserve[1] == rawQueue[1])

-- The AoE GS-X-Comet line delegates when Rapid Refreezing is secret.
enemies = 4
frostMage._Test.context.gcdHistory = { 30455, 199786 }
nilAuras[1310248] = true
queue = frostMage.GetQueue()
assert(queue[1] == rawQueue[1])
assert(frostMage.GetDecisionTrace():match("rapid%-refreezing%-state%-unknown"))

-- Frost DK: full-burst Pillar, Breath pooling fallback, and exact AoE KM line.
reset("DEATHKNIGHT", 2)
resourceType, resourceCurrent = "rune", 4
ready(51271)
local frostDK = assert(JustACBridgeRecommendationSources.Get("frostdk121"))
queue = frostDK.GetQueue()
assert(queue[1] == 51271 and frostDK.GetDecisionTrace():match("pillar_of_frost"))

known[1249658] = true
queue = frostDK.GetQueue()
assert(queue[1] == rawQueue[1])
assert(frostDK.GetDecisionTrace():match("breath%-pillar%-timing%-delegated"))

known[1249658] = nil
cooldowns[51271] = true
enemies = 3
procs[49020] = true
auras[51124] = 2
ready(49020)
cooldowns[207230] = false
queue = frostDK.GetQueue()
assert(queue[1] == 49020 and frostDK.GetDecisionTrace():match("obliterate"))
ready(207230)
queue = frostDK.GetQueue()
assert(queue[1] == 207230 and frostDK.GetDecisionTrace():match("killing%-machine=2"))
preserve = frostDK.GetPreserveQueue()
assert(preserve[1] == rawQueue[1])

-- Unholy DK: missing diseases delegate; Army waits for a server-confirmed
-- Festering Scythe replacement; AoE uses the current 4/6 thresholds.
reset("DEATHKNIGHT", 3)
resourceType, resourceCurrent = "rune", 4
local unholy = assert(JustACBridgeRecommendationSources.Get("unholydk121"))
local unholyFrame = frames[#frames]
queue = unholy.GetQueue()
assert(queue[1] == rawQueue[1])
assert(unholy.GetDecisionTrace():match("disease%-maintenance%-delegated"))

auras[1240996], auras[191587] = true, true
known[458128] = true
ready(42650)
ready(85948)
queue = unholy.GetQueue()
assert(queue[1] == 85948 and unholy.GetDecisionTrace():match("army_setup"))
cast(unholyFrame, 85948)
queue = unholy.GetQueue()
assert(queue[1] == 85948)
cast(unholyFrame, 458128)
queue = unholy.GetQueue()
assert(queue[1] == 42650 and unholy.GetDecisionTrace():match("army_of_the_dead"))
cast(unholyFrame, 42650)

cooldowns[42650] = true
ready(1233448)
auras[1271967] = false
queue = unholy.GetQueue()
assert(queue[1] == 1233448 and unholy.GetDecisionTrace():match("dark_transformation"))
cast(unholyFrame, 1233448)

known[458128] = nil
cooldowns[1233448] = true
enemies = 4
cooldowns[1247378] = false
queue = unholy.GetQueue()
assert(queue[1] == 85948 and not unholy.GetDecisionTrace():match("putrefy"))
ready(1247378)
queue = unholy.GetQueue()
assert(queue[1] == 1247378 and unholy.GetDecisionTrace():match("aoe.putrefy"))
cooldowns[1247378] = true
ready(343294)
queue = unholy.GetQueue()
assert(queue[1] == 343294 and unholy.GetDecisionTrace():match("aoe.soul_reaper"))
cooldowns[343294] = true
procs[47541] = true
ready(207317)
queue = unholy.GetQueue()
assert(queue[1] == 207317 and unholy.GetDecisionTrace():match("threshold=4"))
preserve = unholy.GetPreserveQueue()
assert(preserve[1] == rawQueue[1] and preserve[2] == rawQueue[2])

print("optimized 12.1 source tests passed")
