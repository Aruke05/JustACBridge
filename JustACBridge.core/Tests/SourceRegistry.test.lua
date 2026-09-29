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
assert(justac.GetSpellHotkey(439843) == nil) -- missing scanner is unknown, not unbound
do
    local scanner = fakeLibraries["JustAC-ActionBarScanner"]
    scanner.GetSpellHotkey = function() return "" end
    assert(justac.GetSpellHotkey(439843) == "") -- explicit unbound proof
    scanner.GetSpellHotkey = function() return "C5" end
    assert(justac.GetSpellHotkey(439843) == "C5")
    scanner.GetSpellHotkey = function() return nil end
    assert(justac.GetSpellHotkey(439843) == nil)
    scanner.GetSpellHotkey = nil
end
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

-- Unknown capability results must survive the adapter. In particular, nil
-- cooldown is not "off cooldown", and a missing usability API is not ready.
do
    local api = fakeLibraries["JustAC-BlizzardAPI"]
    for _, name in ipairs({"IsSpellUsable", "IsSpellOnCooldown"}) do
        local original = api[name]
        api[name] = nil
        assert(justac[name](1249658) == nil)
        for _, value in ipairs({true, false, "unknown", {}}) do
            api[name] = function() return value end
            if type(value) == "boolean" then
                assert(justac[name](1249658) == value)
            else
                assert(justac[name](1249658) == nil)
            end
        end
        api[name] = function() return nil end
        assert(justac[name](1249658) == nil)
        api[name] = function() error("unavailable") end
        assert(justac[name](1249658) == nil)
        api[name] = function() return true end
        issecretvalue = function() return true end
        assert(justac[name](1249658) == nil)
        issecretvalue = nil
        api[name] = original
    end
end

-- Strict affordability must bypass BOTH upstream fail-open and cached action
-- usability, while verifying the live physical slot belongs to this spell.
do
    local secret = {}
    issecretvalue = function(v) return v == secret end
    C_Spell.IsSpellUsable = function() return true, false end
    local usable, short = justac.IsSpellUsableStrict(1249658)
    assert(usable == true and short == false)
    C_Spell.IsSpellUsable = function() return false, true end
    usable, short = justac.IsSpellUsableStrict(1249658)
    assert(usable == false and short == true)
    C_Spell.IsSpellUsable = function() return secret, secret end
    local scanner = fakeLibraries["JustAC-ActionBarScanner"]
    scanner.GetSlotForSpell = function() return 9 end
    local actionUsable, actionShort, reads = true, false, 0
    GetActionInfo = function(slot) assert(slot == 9); return "spell", 1249658 end
    C_ActionBar = {IsUsableAction = function(slot)
        assert(slot == 9); reads = reads + 1; return actionUsable, actionShort
    end}
    fakeLibraries["JustAC-BlizzardAPI"].GetActionBarUsability = function()
        error("must not read cached slot usability")
    end
    fakeLibraries["JustAC-BlizzardAPI"].IsSpellUsable = function()
        error("must not use fail-open usability")
    end
    assert(justac.IsSpellUsableStrict(1249658) == true)
    actionUsable, actionShort = false, true
    usable, short = justac.IsSpellUsableStrict(1249658)
    assert(usable == false and short == true and reads == 2)
    actionUsable, actionShort = true, false
    for _, info in ipairs({{"macro", 1249658}, {"spell", 49020}, {secret, 1249658}, {"spell", secret}}) do
        GetActionInfo = function() return info[1], info[2] end
        assert(justac.IsSpellUsableStrict(1249658) == nil)
    end
    GetActionInfo = function() return "spell", 1249658 end
    for _, entry in ipairs({{scanner, "GetSlotForSpell"}, {_G, "GetActionInfo"}, {C_ActionBar, "IsUsableAction"}}) do
        local original = entry[1][entry[2]]
        for _, fault in ipairs({"missing", "secret", "throw", "nil"}) do
            entry[1][entry[2]] = fault ~= "missing" and function()
                if fault == "throw" then error("unknown action") end
                if fault == "secret" then return secret, secret end
                return nil
            end or nil
            assert(justac.IsSpellUsableStrict(1249658) == nil)
        end
        entry[1][entry[2]] = original
    end
    actionUsable, actionShort = true, secret
    assert(justac.IsSpellUsableStrict(1249658) == nil)
    actionUsable, actionShort = secret, false
    assert(justac.IsSpellUsableStrict(1249658) == nil)
    issecretvalue = nil
end
-- Only the binary engine predicate may cross the secret-safe adapter. Missing
-- helpers, nil and secret booleans must remain unknown, not become true.
do
    local opaque={}
    issecretvalue=function(v) return rawequal(v,opaque) end
    local api=fakeLibraries["JustAC-BlizzardAPI"]
    assert(justac.ReadBinaryPredicate(100)==true)
    assert(justac.ReadBinaryPredicate(0)==false)
    assert(justac.ReadBinaryPredicate(37)==nil)
    assert(justac.ReadBinaryPredicate(nil)==nil)
    assert(justac.ReadBinaryPredicate(opaque)==nil)
    api.IsSecretZero=function(v) assert(rawequal(v,opaque)); return true end
    assert(justac.ReadBinaryPredicate(opaque)==false)
    api.IsSecretZero=function() return false end
    assert(justac.ReadBinaryPredicate(opaque)==true)
    api.IsSecretZero=function() return opaque end
    assert(justac.ReadBinaryPredicate(opaque)==nil)
    api.IsSecretZero=function() return nil end
    assert(justac.ReadBinaryPredicate(opaque)==nil)
    api.IsSecretZero=function() error("unavailable") end
    assert(justac.ReadBinaryPredicate(opaque)==nil)
    issecretvalue=nil
end
print("source registry tests passed")
