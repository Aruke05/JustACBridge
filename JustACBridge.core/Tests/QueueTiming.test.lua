-- Pure Lua: no client, user settings, process access or keyboard input.
dofile("JustACBridge.core/Framework/QueueTiming.lua")
local timing = JustACBridgeQueueTiming
local function expect(expected, observed, reason)
    local actual, game, why = timing.ReadWindow(120)
    assert(actual == expected and game == observed and why == reason,
        ("window=%s game=%s reason=%s"):format(tostring(actual), tostring(game), why))
end

C_CVar, GetCVar, issecretvalue = nil, nil, nil
expect(120, nil, "cvar-unavailable")
GetCVar = function(key) assert(key == "SpellQueueWindow"); return "80" end
expect(80, 80, "cvar-known")
local value = "400"
C_CVar = { GetCVar = function(key) assert(key == "SpellQueueWindow"); return value end }
for _, ms in ipairs({ 0, 1, 20, 80, 119, 120, 121, 400, 1000, 79.9 }) do
    value = tostring(ms)
    expect(math.min(120, math.floor(ms)), ms, "cvar-known")
    value = ms
    expect(math.min(120, math.floor(ms)), ms, "cvar-known")
end
-- Never latch a previously readable value across invalid/secret frames.
for _, invalid in ipairs({ "", "oops", false, {}, -1, math.huge, -math.huge, 0/0 }) do
    value = invalid
    expect(120, nil, "cvar-invalid")
end
value = nil
expect(120, nil, "cvar-invalid")
local secret = setmetatable({}, {
    __tostring = function() error("secret string conversion") end,
    __lt = function() error("secret comparison") end,
})
value = secret
issecretvalue = function(v) return rawequal(v, secret) end
expect(120, nil, "cvar-unknown")
issecretvalue = function() error("detector unavailable") end
expect(120, nil, "cvar-unknown")
issecretvalue = nil
C_CVar.GetCVar = function() error("CVar API failure") end
expect(120, nil, "cvar-error") -- do not use contradictory legacy getter
C_CVar.GetCVar = nil
expect(80, 80, "cvar-known")
GetCVar = nil
expect(120, nil, "cvar-unavailable")
print("queue timing tests passed")
