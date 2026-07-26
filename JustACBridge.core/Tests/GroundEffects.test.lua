-- Run from repository root with a Lua-compatible CLI.

local now = 100
function GetTime()
    return now
end

dofile("JustACBridge.core/Trackers/GroundEffects.lua")
local tracker = JustACBridgeGroundEffectTracker

tracker.Configure({
    {
        id = "dnd",
        name = "Death and Decay",
        spells = { 43265, 152280 },
        duration = 10,
        suppressRepeat = true,
    },
}, function(spellID)
    return spellID == 43265 and 152280 or spellID
end)

assert(tracker.OnSpellcastSucceeded(99999) == false)
assert(tracker.OnSpellcastSucceeded(152280) == true)

local active, state, rule = tracker.IsSpellActive(43265)
assert(active and state.expiresAt == 110 and rule.suppressRepeat)
assert(math.abs(tracker.GetActive()[1].remaining - 10) < 0.001)

now = 109.5
assert(tracker.IsSpellActive(152280) == true)
assert(math.abs(tracker.GetActive()[1].remaining - 0.5) < 0.001)

now = 110
assert(tracker.Update() == true)
local expired = tracker.DrainExpired()
assert(#expired == 1 and expired[1].id == "dnd")
assert(#tracker.DrainExpired() == 0)
assert(tracker.IsSpellActive(43265) == false)

print("ground-effect tracker tests passed")
