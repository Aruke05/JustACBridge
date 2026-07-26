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

print("source registry tests passed")

