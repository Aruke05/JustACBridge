-- Isolated 12.1 preparation proofs. No client/process/input access.
local spec
JustACBridgePolicyRegistry = {RegisterSpec = function(_, _, value) spec = value end}
local secret = {}
function issecretvalue(value) return value == secret end
local values, cooldowns, faults
local function value(key)
    if faults[key] == "throw" then error("injected " .. key) end
    if faults[key] == "missing" then return nil end
    if faults[key] == "secret" then return secret end
    return values[key]
end
function UnitPower() return value("rp") end
function UnitPowerMax() return value("maxRP") end
C_Spell = {
    GetSpellCooldownDuration = function(id, excludeGCD)
        assert(excludeGCD == true)
        if faults.duration == "throw" then error("duration failure") end
        if faults.duration == "missing" then return nil end
        if faults.duration == "secret" then return secret end
        return {active = cooldowns[id] == true}
    end,
    IsSpellUsable = function(id)
        if id == 47568 then return value("erwUsable"), false end
        return value("breathUsable"), value("noPower")
    end,
    GetSpellCharges = function()
        if faults.charges == "throw" then error("charge failure") end
        if faults.charges == "missing" then return nil end
        if faults.charges == "secret" then return secret end
        return {currentCharges = value("charges"), maxCharges = value("maxCharges")}
    end,
}
C_Secrets = {ShouldAurasBeSecret = function() return value("secretAuras") end}
C_UnitAuras = {GetPlayerAuraBySpellID = function(id)
    assert(id == 51124)
    return value("km")
end}
function CreateFrame(kind)
    if faults.frame == "throw" then error("frame failure") end
    return {
        Hide = function() end,
        SetCooldown = function(self) self.shown = false end,
        SetCooldownFromDurationObject = function(self, duration)
            if faults.setter == "throw" then error("setter failure") end
            self.shown = duration.active
        end,
        IsShown = function(self)
            if faults.shown == "throw" then error("shown failure") end
            if faults.shown == "missing" then return nil end
            if faults.shown == "secret" then return secret end
            return self.shown
        end,
    }
end
local function reset()
    values = {rp = 42, maxRP = 100, charges = 1, maxCharges = 2,
        erwUsable = true, breathUsable = false, noPower = true, secretAuras = false}
    faults, cooldowns = {}, {}
    dofile("JustACBridge.core/Policies/DeathKnight/Frost.lua")
    return spec.versions[1]
end
local function owned(id) return id == 1249658 or id == 47568 end
local function prepare(p, selected) return p.prepareLossless(selected or 51271, owned) end
local p = reset()
assert(prepare(p) == 47568)
assert(prepare(p, 49184) == nil)
assert(prepare(p, 439843) == nil) -- never reorder Mark or ordinary procs
assert(prepare(p, 279302) == nil)
assert(p.prepareLossless(51271, function() return false end) == nil)
for _, id in ipairs({51271, 1249658}) do
    p = reset(); cooldowns[id] = true; assert(prepare(p) == nil)
end
for _, case in ipairs({
    {0, 100, 1, 47568}, {59, 100, 1, 47568}, {60, 100, 1, nil},
    {60, 100, 2, 47568}, {61, 100, 2, nil}, {85, 100, 2, nil},
    {90, 100, 2, nil}, {90, 130, 2, 47568}, {91, 130, 2, nil},
    {42, 100, 0, nil}, {42, 100, 3, nil}, {-1, 100, 1, nil},
    {101, 100, 2, nil}, {42, 59, 2, nil}, {42, math.huge, 2, nil},
}) do
    p = reset()
    values.rp, values.maxRP, values.charges = case[1], case[2], case[3]
    values.breathUsable, values.noPower = case[1] >= 60, case[1] < 60
    assert(prepare(p) == case[4], "RP/charge boundary " .. tostring(case[1]))
end
for _, key in ipairs({"rp", "maxRP", "charges", "maxCharges", "breathUsable",
    "erwUsable", "secretAuras", "km", "duration", "shown"}) do
    for _, fault in ipairs({"missing", "secret", "throw"}) do
        -- A verified nonsecret nil aura means absent, not unknown.
        if not (key == "km" and fault == "missing") then
            p = reset(); faults[key] = fault
            assert(prepare(p) == nil, key .. " " .. fault)
        end
    end
end
for _, key in ipairs({"frame", "setter"}) do
    p = reset(); faults[key] = "throw"; assert(prepare(p) == nil)
end
for _, key in ipairs({"secretAuras", "km"}) do
    p = reset(); values[key] = true; assert(prepare(p) == nil)
end
p = reset(); values.km = {applications = 1}; assert(prepare(p) == nil)
p = reset(); values.maxCharges = 1; assert(prepare(p) == nil)
p = reset(); values.erwUsable = false; assert(prepare(p) == nil)
p = reset(); values.noPower = false; assert(prepare(p) == nil)
for _, event in ipairs({"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED"}) do
    p = reset(); assert(prepare(p) == 47568)
    p.observePlayerSpellcast(event, 47568)
    for _ = 1, 5 do assert(prepare(p) == nil) end -- old charge/RP cannot double-send
    faults.duration = "missing"; assert(prepare(p) == nil)
    faults.duration = nil; assert(prepare(p) == nil)
    cooldowns[1249658] = true; assert(prepare(p, 49184) == nil)
    cooldowns[1249658] = false; assert(prepare(p) == 47568)
end
-- Current numeric RP, never a memoized percentage or an inferred ERW gain.
p = reset()
local ready = p.addCastFollowups[1].readyPredicate
values.breathUsable = true
for _, id in ipairs({1249658, 152279}) do
    values.rp = 59; assert(ready(id) == false)
    values.rp = 60; assert(ready(id) == true)
    values.rp = 30; assert(ready(id) == false) -- same-frame spend invalidates proof
    values.rp = 90; values.maxRP = 130; assert(ready(id) == true)
end
values.rp, values.maxRP = 60, 100
for _, key in ipairs({"rp", "maxRP", "breathUsable", "duration", "shown"}) do
    for _, fault in ipairs({"missing", "secret", "throw"}) do
        faults[key] = fault; assert(ready(1249658) == nil, key .. " strict " .. fault)
        faults[key] = nil
        assert(ready(1249658) == true) -- no stale failed probe left behind
    end
end
cooldowns[1249658] = true; assert(ready(1249658) == false)
cooldowns[1249658] = nil; values.breathUsable = false; assert(ready(1249658) == false)
print("frost preparation tests passed")
