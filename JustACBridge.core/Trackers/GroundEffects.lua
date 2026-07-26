-- Tracks player-created ground effects from successful spell placement.
-- WoW does not expose a durable ground-object handle, so expiry is derived from
-- UNIT_SPELLCAST_SUCCEEDED plus policy duration. Merely opening the reticle does
-- not start a timer.

local Tracker = _G.JustACBridgeGroundEffectTracker or {}
_G.JustACBridgeGroundEffectTracker = Tracker

local rules = {}
local states = {}
local expiredStates = {}
local resolveSpellID

local function copyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end

local function displayID(spellID)
    if type(resolveSpellID) ~= "function" then
        return spellID
    end
    local ok, result = pcall(resolveSpellID, spellID)
    return ok and tonumber(result) or spellID
end

local function matches(rule, spellID)
    local resolved = displayID(spellID)
    for _, configuredID in ipairs(rule.spells or {}) do
        if configuredID == spellID or configuredID == resolved
            or displayID(configuredID) == resolved then
            return true
        end
    end
    return false
end

function Tracker.Configure(nextRules, resolver)
    local next = {}
    local known = {}
    resolveSpellID = resolver
    for index, rule in ipairs(nextRules or {}) do
        if type(rule) == "table" and tonumber(rule.duration) and tonumber(rule.duration) > 0 then
            local configured = {
                id = tostring(rule.id or index),
                name = rule.name,
                spells = copyArray(rule.spells),
                duration = tonumber(rule.duration),
                suppressRepeat = rule.suppressRepeat ~= false,
            }
            next[#next + 1] = configured
            known[configured.id] = true
        end
    end
    rules = next
    for id in pairs(states) do
        if not known[id] then
            states[id] = nil
        end
    end
end

function Tracker.Reset()
    states = {}
    expiredStates = {}
end

function Tracker.OnSpellcastSucceeded(spellID, now)
    spellID = tonumber(spellID)
    if not spellID then
        return false
    end
    now = tonumber(now) or GetTime()
    for _, rule in ipairs(rules) do
        if matches(rule, spellID) then
            states[rule.id] = {
                id = rule.id,
                name = rule.name,
                spellID = spellID,
                placedAt = now,
                expiresAt = now + rule.duration,
                duration = rule.duration,
                suppressRepeat = rule.suppressRepeat,
            }
            return true
        end
    end
    return false
end

function Tracker.Update(now)
    now = tonumber(now) or GetTime()
    local changed = false
    for id, state in pairs(states) do
        if now >= state.expiresAt then
            expiredStates[#expiredStates + 1] = {
                id = state.id,
                name = state.name,
                spellID = state.spellID,
                placedAt = state.placedAt,
                expiresAt = state.expiresAt,
                duration = state.duration,
            }
            states[id] = nil
            changed = true
        end
    end
    return changed
end

function Tracker.DrainExpired()
    local result = expiredStates
    expiredStates = {}
    return result
end

function Tracker.IsSpellActive(spellID, now)
    Tracker.Update(now)
    for _, rule in ipairs(rules) do
        if matches(rule, spellID) then
            local state = states[rule.id]
            return state ~= nil, state, rule
        end
    end
    return false, nil, nil
end

function Tracker.GetActive(now)
    now = tonumber(now) or GetTime()
    Tracker.Update(now)
    local result = {}
    for _, state in pairs(states) do
        result[#result + 1] = {
            id = state.id,
            name = state.name,
            spellID = state.spellID,
            placedAt = state.placedAt,
            expiresAt = state.expiresAt,
            duration = state.duration,
            remaining = math.max(0, state.expiresAt - now),
            suppressRepeat = state.suppressRepeat,
        }
    end
    table.sort(result, function(left, right)
        return left.expiresAt < right.expiresAt
    end)
    return result
end
