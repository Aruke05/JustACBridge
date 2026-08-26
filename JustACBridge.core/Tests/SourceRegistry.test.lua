-- Run from repository root with a Lua-compatible CLI.

dofile("JustACBridge.core/Sources/Registry.lua")

local registry = JustACBridgeRecommendationSources
assert(registry.schemaVersion == 1)

assert(registry.Register("unavailable", {
    GetQueue = function() return {} end,
    IsAvailable = function() return false, "missing dependency" end,
}))

assert(registry.Register("custom", {
    name = "Custom",
    GetQueue = function() return { 1001, -2002 } end,
}))

local selected = assert(registry.Select("custom"))
assert(selected.id == "custom" and selected.name == "Custom")
assert(selected.GetQueue()[1] == 1001)

local fallback = assert(registry.Select("unavailable"))
assert(fallback.id == "custom")

local list = registry.List()
assert(#list == 2)
assert(list[1].available == false and list[2].available == true)

-- JustAC exposes dynamic action-bar and talent replacements through separate
-- APIs. The adapter must prefer the dynamic form, then fall back to the talent
-- form so a base queue ID always resolves to the action actually being cast.
local durationRemaining = 40
local durationThrows = false
local comparisonThrows = false
local fakeLibraries = {
    ["JustAC-SpellQueue"] = {
        GetCurrentSpellQueue = function() return { 30451, 365350, 44425 } end,
        IsBurstCue = function(id) return id == 365350 end,
    },
    ["JustAC-ActionBarScanner"] = {},
    ["JustAC-BlizzardAPI"] = {
        GetDisplaySpellID = function(id)
            return id == 30451 and 1295939 or id
        end,
        ResolveSpellID = function(id)
            return id == 1449 and 1241462 or id
        end,
        IsSpellOnCooldown = function(id) return id == 365350 end,
        IsDurationBelowSeconds = function(duration, seconds)
            if comparisonThrows then error("comparison unavailable") end
            return duration.remaining < seconds
        end,
    },
    ["JustAC-BurstInjectionEngine"] = {},
    ["JustAC-SpellDB"] = {},
    ["AceAddon-3.0"] = { GetAddon = function() return {} end },
}
C_Spell = {
    GetSpellCooldownDuration = function(id)
        if durationThrows then error("duration unavailable") end
        return id == 365350 and { remaining = durationRemaining } or nil
    end,
}
LibStub = function(name) return fakeLibraries[name] end
dofile("JustACBridge.core/Sources/JustAC.lua")
local justac = assert(registry.Get("justac"))
assert(justac.GetEffectiveSpellID(30451) == 1295939)
assert(justac.GetEffectiveSpellID(1449) == 1241462)
assert(justac.GetEffectiveSpellID(44425) == 44425)
assert(justac.IsBurstCue(365350) == true)
assert(justac.IsBurstCue(30451) == false)
assert(justac.IsSpellOnCooldown(365350) == true)
assert(justac.IsSpellOnCooldown(30451) == false)
assert(justac.IsSpellCooldownRemainingAbove(365350, 30.1) == true)
assert(justac.IsSpellCooldownRemainingAbove(365350, 45) == false)
assert(justac.IsSpellCooldownRemainingAbove(30451, 30.1) == nil)
durationRemaining = 30.099
assert(justac.IsSpellCooldownRemainingAbove(365350, 30.1) == false)
durationRemaining = 30.1
assert(justac.IsSpellCooldownRemainingAbove(365350, 30.1) == true)
durationThrows = true
assert(justac.IsSpellCooldownRemainingAbove(365350, 30.1) == nil)
durationThrows, comparisonThrows = false, true
assert(justac.IsSpellCooldownRemainingAbove(365350, 30.1) == nil)

print("source registry tests passed")
