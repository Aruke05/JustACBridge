-- Midnight 12.1 Hunter source decisions and fail-closed boundaries.
-- Run from the repository root with a Lua-compatible CLI.

local now = 100
local currentSpec = 1
local enemies = 1
local rawQueue = { 193455, 34026 }
local cooldowns, usable, known, auras = {}, {}, {}, {}
local maxCharges, display, nilAuras, durationBelow = {}, {}, {}, {}
local frames = {}

function GetTime() return now end
function UnitAffectingCombat() return true end
function UnitExists(unit) return unit == "target" end
function UnitCanAttack(_, unit) return unit == "target" end
function UnitClass() return "Hunter", "HUNTER" end
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
    IsSpellProcced = function() return false end,
    IsSpellAtMaxCharges = function(id) return maxCharges[id] == true end,
    GetAuraStackAtLeast = function(_, id, threshold)
        if nilAuras[id] then return nil end
        local value = auras[id]
        if type(value) == "number" then return value >= threshold end
        return value == true
    end,
    GetEngagedEnemyCount = function() return enemies end,
    GetDisplaySpellID = function(id) return display[id] or id end,
    GetAuraDurationObject = function(_, auraInstanceID) return auraInstanceID end,
    IsDurationBelowSeconds = function(duration) return durationBelow[duration] end,
}
local spellQueue = { GetCurrentSpellQueue = function() return rawQueue end }
LibStub = function(name)
    if name == "JustAC-SpellQueue" then return spellQueue end
    if name == "JustAC-BlizzardAPI" then return bapi end
end

local function reset(spec, queue)
    currentSpec = spec
    enemies = 1
    rawQueue = queue
    cooldowns, usable, known, auras = {}, {}, {}, {}
    maxCharges, display, nilAuras, durationBelow = {}, {}, {}, {}
end

local function ready(id)
    known[id] = true
    cooldowns[id] = false
end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/Runtime121.lua")
dofile("JustACBridge.core/Sources/BeastMasteryHunter121.lua")
dofile("JustACBridge.core/Sources/MarksmanshipHunter121.lua")
dofile("JustACBridge.core/Sources/SurvivalHunter121.lua")

-- Beast Mastery: a ready Bestial Wrath positively proves the higher Barbed
-- Shot timing row. Once Barbed is unavailable, Bestial Wrath wins.
reset(1, { 193455, 34026 })
known[471876] = true -- Pack Leader talent
ready(19574)
ready(217200)
local bm = assert(JustACBridgeRecommendationSources.Get("bmhunter121"))
local queue = bm.GetQueue()
assert(queue[1] == 217200)
assert(bm.GetDecisionTrace():match("pack_st.barbed_shot"))

cooldowns[217200] = true
queue = bm.GetQueue()
assert(queue[1] == 19574)
assert(bm.GetDecisionTrace():match("pack_st.bestial_wrath"))

-- Beast Cleave down is a complete, visible Wild Thrash refresh condition.
reset(1, { 193455, 34026 })
enemies = 3
known[471876] = true
known[115939] = true
ready(1264359)
auras[268877] = false
queue = bm.GetQueue()
assert(queue[1] == 1264359)
assert(bm.GetDecisionTrace():match("beast%-cleave%-down"))

-- Dark Ranger duration/target branches are deliberately delegated unchanged.
reset(1, { 193455, 34026 })
known[466932] = true
queue = bm.GetQueue()
assert(queue[1] == rawQueue[1])
assert(bm.GetDecisionTrace():match("dark%-ranger%-priority%-delegated"))
local preserve = bm.GetPreserveQueue()
assert(preserve[1] == rawQueue[1] and preserve[2] == rawQueue[2])

-- Marksmanship Sentinel: Volley and then Rapid Fire are exact ST rows after
-- higher actions are positively unavailable.
reset(2, { 56641, 19434 })
known[1253599] = true -- Sentinel talent
ready(260243)
local mm = assert(JustACBridgeRecommendationSources.Get("mmhunter121"))
queue = mm.GetQueue()
assert(queue[1] == 260243 and mm.GetDecisionTrace():match("sentinel_st.volley"))

cooldowns[260243] = true
ready(257044)
queue = mm.GetQueue()
assert(queue[1] == 257044)
assert(mm.GetDecisionTrace():match("sentinel_st.rapid_fire"))

-- Precise Shots makes Kill Shot a proved higher spender after Rapid Fire.
cooldowns[257044] = true
auras[260242] = true
ready(53351)
queue = mm.GetQueue()
assert(queue[1] == 53351)
assert(mm.GetDecisionTrace():match("sentinel_st.kill_shot"))

-- Current multi-target target_if/tier routing is never approximated.
enemies = 3
queue = mm.GetQueue()
assert(queue[1] == rawQueue[1])
assert(mm.GetDecisionTrace():match("multi%-target%-target%-selection%-delegated"))

-- Dark Ranger spends visible Precise Shots with Black Arrow first.
reset(2, { 56641, 19434 })
known[466932] = true
known[466930] = true
auras[260242] = true
ready(466930)
queue = mm.GetQueue()
assert(queue[1] == 466930)
assert(mm.GetDecisionTrace():match("precise%-shots%-up"))

-- Explosive Shot depends on Tactical Reload/Unstable Trigger and route state.
reset(2, { 56641, 19434 })
known[1253599] = true
ready(212431)
queue = mm.GetQueue()
assert(queue[1] == rawQueue[1])
assert(mm.GetDecisionTrace():match("explosive%-shot%-branch%-delegated"))
preserve = mm.GetPreserveQueue()
assert(preserve[1] == rawQueue[1])

-- Survival Sentinel: zero Tip and no Twin Fangs proves the first KC row.
reset(3, { 186270, 259489 })
ready(259489)
known[1253599] = true
known[1250646] = true
known[1261193] = true
cooldowns[1250646] = false
local survival = assert(JustACBridgeRecommendationSources.Get("survivalhunter121"))
queue = survival.GetQueue()
assert(queue[1] == 259489)
assert(survival.GetDecisionTrace():match("tip=0%+no%-twin%-fangs"))

-- With KC unavailable, Sentinel Boomstick is the next unconditional row.
reset(3, { 186270, 259489 })
known[1253599] = true
known[1250646] = true
auras[260286] = 1
ready(1261193)
queue = survival.GetQueue()
assert(queue[1] == 1261193)
assert(survival.GetDecisionTrace():match("sentinel_st.boomstick"))

-- Pack Leader prepares a ready Takedown with KC while below two Tip stacks.
reset(3, { 186270, 259489 })
known[471876] = true
known[1261193] = true
auras[260286] = 1
ready(259489)
ready(1250646)
queue = survival.GetQueue()
assert(queue[1] == 259489)
assert(survival.GetDecisionTrace():match("takedown%-ready%+tip<2"))

-- The Pack Leader howl_summon.ready driver is not the visible Howl aura.
-- With Twin Fangs, a ready Takedown would be the lower row, so an unresolved
-- Howl decision must preserve JustAC rather than guessing Takedown.
reset(3, { 186270, 259489 })
known[471876] = true
known[1272139] = true
known[1261193] = true
ready(259489)
ready(1250646)
queue = survival.GetQueue()
assert(queue[1] == rawQueue[1])
assert(survival.GetDecisionTrace():match("howl%-summon%-readiness%-delegated"))

-- Once KC is unavailable, Tip>0 and no Twin Fangs proves Takedown itself.
reset(3, { 186270, 259489 })
known[471876] = true
known[1261193] = true
auras[260286] = 1
ready(259489)
ready(1250646)
cooldowns[259489] = true
queue = survival.GetQueue()
assert(queue[1] == 1250646)
assert(survival.GetDecisionTrace():match("tip>0%+no%-twin%-fangs"))

-- Cleave target selection remains owned by the original JustAC queue.
enemies = 3
queue = survival.GetQueue()
assert(queue[1] == rawQueue[1])
assert(survival.GetDecisionTrace():match("cleave%-target%-selection%-delegated"))

-- A secret/unreadable Tip state fails closed rather than guessing zero stacks.
reset(3, { 186270, 259489 })
known[1253599] = true
known[1250646] = true
known[1261193] = true
nilAuras[260286] = true
queue = survival.GetQueue()
assert(queue[1] == rawQueue[1])
assert(survival.GetDecisionTrace():match("tip%-of%-the%-spear%-state%-unknown"))
preserve = survival.GetPreserveQueue()
assert(preserve[1] == rawQueue[1] and preserve[2] == rawQueue[2])

print("hunter 12.1 source tests passed")
