-- Input timing only: never selects/reorders actions or changes game CVars.
local QueueTiming = {}
_G.JustACBridgeQueueTiming = QueueTiming

function QueueTiming.ReadWindow(capMs)
    local getter = C_CVar and C_CVar.GetCVar
    if type(getter) ~= "function" then getter = GetCVar end
    if type(getter) ~= "function" then return capMs, nil, "cvar-unavailable" end

    local ok, value = pcall(getter, "SpellQueueWindow")
    if not ok then return capMs, nil, "cvar-error" end
    -- Check secrecy before conversion, comparison, logging or caching.
    if type(issecretvalue) == "function" then
        local safe, secret = pcall(issecretvalue, value)
        if not safe or secret then return capMs, nil, "cvar-unknown" end
    end
    if type(value) ~= "string" and type(value) ~= "number" then
        return capMs, nil, "cvar-invalid"
    end
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value == math.huge then
        return capMs, nil, "cvar-invalid"
    end
    -- Do not widen the established commit window based on ping or speculation.
    -- Zero is meaningful: the player disabled pre-queueing. Do not clamp it up.
    return math.min(capMs, math.floor(value)), value, "cvar-known"
end
