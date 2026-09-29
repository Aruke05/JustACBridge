-- Input timing only: never selects/reorders actions or changes game CVars.
local QueueTiming = {}
_G.JustACBridgeQueueTiming = QueueTiming

-- Exact live remaining time, used ONLY as an admission offset for a future
-- sequence opener. No rounding, latency allowance, old GCD duration or cache.
-- Missing evidence means the caller may use zero (no extra timing credit).
function QueueTiming.ReadGCDRemaining()
    local ok, remaining = pcall(function()
        local function number(value)
            return not (issecretvalue and issecretvalue(value))
                and type(value) == "number" and value == value and value >= 0 and value < math.huge
        end
        local cooldown = C_Spell.GetSpellCooldown(61304)
        if (issecretvalue and issecretvalue(cooldown)) or type(cooldown) ~= "table" then return nil end
        if not number(cooldown.startTime) or not number(cooldown.duration)
            or not number(cooldown.modRate) or cooldown.modRate ~= 1 then return nil end
        local now = GetTime()
        if not number(now) or cooldown.startTime > now then return nil end
        return math.max(0, cooldown.startTime + cooldown.duration - now)
    end)
    if ok then return remaining end
end

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
