-- Run from the repository root with any Lua-compatible CLI:
--   lua JustACBridge.core/Tests/PolicyRegistry.test.lua

function GetBuildInfo()
    return "12.0.7", "", "", 120007
end

dofile("JustACBridge.core/Policies/Registry.lua")
dofile("JustACBridge.core/Policies/Mage.lua")
dofile("JustACBridge.core/Policies/DeathKnight.lua")

local registry = JustACBridgePolicyRegistry
assert(registry.schemaVersion == 1)

local arcane = assert(registry.Resolve("MAGE", 1, 120007))
assert(arcane.storageKey == "MAGE_1" and arcane.id == "arcane")
assert(#arcane.reserve == 3)
assert(arcane.reserve[1] == 365350 and arcane.reserve[3] == 321507)

local frostMage = assert(registry.Resolve("MAGE", 3, 120007))
assert(#frostMage.reserve == 1 and frostMage.reserve[1] == 12472)

local unholy = assert(registry.Resolve("DEATHKNIGHT", 3, 120007))
assert(#unholy.reserve == 6 and unholy.reserve[2] == 42650)

-- An unregistered class falls back to JustAC-only behavior in the bridge core.
assert(registry.Resolve("WARRIOR", 1, 120007) == nil)

assert(registry.RegisterClass("TEST", {
    revision = 2,
    specs = {
        [1] = {
            id = "test",
            reserve = { 1001, 1002 },
            versions = {
                {
                    id = "12.1",
                    minInterface = 120100,
                    maxInterface = 120199,
                    removeReserve = { 1001 },
                    addReserve = { 1003 },
                },
                {
                    id = "13.0",
                    minInterface = 130000,
                    reserve = { 2001, 2002 },
                },
            },
        },
    },
}))

local patch121 = assert(registry.Resolve("TEST", 1, 120150))
assert(patch121.ruleset == "12.1")
assert(#patch121.reserve == 2)
assert(patch121.reserve[1] == 1002 and patch121.reserve[2] == 1003)

local patch130 = assert(registry.Resolve("TEST", 1, 130001))
assert(patch130.ruleset == "13.0")
assert(#patch130.reserve == 2)
assert(patch130.reserve[1] == 2001 and patch130.reserve[2] == 2002)

print("policy registry tests passed")
