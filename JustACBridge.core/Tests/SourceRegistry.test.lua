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
local fakeLibraries = {
    ["JustAC-SpellQueue"] = { GetCurrentSpellQueue = function() return { 1449 } end },
    ["JustAC-ActionBarScanner"] = {},
    ["JustAC-BlizzardAPI"] = {
        GetDisplaySpellID = function(id)
            return id == 30451 and 1295939 or id
        end,
        ResolveSpellID = function(id)
            return id == 1449 and 1241462 or id
        end,
    },
    ["JustAC-BurstInjectionEngine"] = {},
    ["JustAC-SpellDB"] = {},
    ["AceAddon-3.0"] = { GetAddon = function() return {} end },
}
LibStub = function(name) return fakeLibraries[name] end
dofile("JustACBridge.core/Sources/JustAC.lua")
local justac = assert(registry.Get("justac"))
assert(justac.GetEffectiveSpellID(30451) == 1295939)
assert(justac.GetEffectiveSpellID(1449) == 1241462)
assert(justac.GetEffectiveSpellID(44425) == 44425)

print("source registry tests passed")
