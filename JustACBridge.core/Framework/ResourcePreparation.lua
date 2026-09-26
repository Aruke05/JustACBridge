-- Stateless, opt-in preparation primitives. No class IDs, predicted gains,
-- cached resource/CD answers, or success-event state lives here.
local Preparation = {}
_G.JustACBridgeResourcePreparation = Preparation

local function plain(v, kind)
    return not (issecretvalue and issecretvalue(v)) and type(v) == kind
end
local function number(v)
    return plain(v, "number") and v == v and v >= 0 and v < math.huge
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end
local function method(object, name, ...)
    if not (plain(object, "table") or plain(object, "userdata")) then return nil end
    local ok, result = pcall(function(...) return object[name](object, ...) end, ...)
    if ok then return result end
end

-- Only immutable curve shapes are cached. Step semantics MUST pass native
-- Evaluate self-checks, including the exact boundary, before engine use.
-- Unlike ramp/rounded-percent predicates this has no optimistic boundary.
local curves, curveCount = {}, 0
local function stepCurve(threshold, domain)
    if not number(threshold) or threshold <= 0 or threshold > domain then return nil end
    local key = string.format("%.17g:%.17g", threshold, domain)
    if curves[key] then return curves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
        return nil, "curve-api-missing"
    end
    local ok, curve = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 0)
        c:AddPoint(threshold, 100)
        if domain > threshold then c:AddPoint(domain, 100) end
        local epsilon = math.min(threshold * 0.000001, 0.000001)
        for _, pair in ipairs({{0, 0}, {threshold / 2, 0}, {threshold - epsilon, 0},
            {threshold, 100}, {threshold + epsilon, 100}, {domain, 100}}) do
            local value = c:Evaluate(pair[1])
            if not plain(value, "number") or value ~= pair[2] then return nil end
        end
        return c
    end)
    if ok and curve then
        if curveCount >= 64 then curves, curveCount = {}, 0 end
        curves[key], curveCount = curve, curveCount + 1
        return curve
    end
    return nil, "curve-selftest-failed"
end

local function binary(value, query, trueValue)
    if plain(value, "number") then
        if value == (trueValue or 100) then return true end
        if value == 0 then return false end
        return nil, "non-binary-engine-result"
    end
    -- Only validated 0/100 step or 0/1 boolean results reach this adapter. Never
    -- hand it raw resource values (its underlying UI conversion may round).
    if not (issecretvalue and issecretvalue(value)) or type(query) ~= "function" then
        return nil, "engine-result-or-adapter-unavailable"
    end
    local ok, succeeded, result = pcall(query, "ReadBinaryPredicate", value)
    if ok and succeeded == true and plain(result, "boolean") then return result end
    return nil, "binary-adapter-unknown"
end

function Preparation.CooldownBelow(spellID, seconds, query)
    if not number(seconds) or seconds <= 0 then return nil end
    local duration = call(C_Spell and C_Spell.GetSpellCooldownDuration, spellID, true)
    if not (plain(duration, "table") or plain(duration, "userdata")) then
        return nil, "duration-unavailable"
    end
    local remaining = method(duration, "GetRemainingDuration") -- default RealTime
    if plain(remaining, "number") then
        if number(remaining) then return remaining < seconds, "visible-duration" end
        return nil, "invalid-duration"
    end
    local curve, reason = stepCurve(seconds, math.max(seconds * 2, 3600))
    if not curve then return nil, reason end
    local above, why = binary(method(duration, "EvaluateRemainingDuration", curve), query)
    if above ~= nil then return not above, "engine-duration-step" end
    return nil, why
end

-- Strict >, including an inclusive WAIT at the boundary. Use the next IEEE
-- double, NOT a guessed epsilon. Native curves may store lower precision: if
-- they cannot distinguish the boundary, never silently change > into >=.
-- In that case an independently validated integer upper bound can still
-- positively prove 'far'; the narrow unresolved interval remains UNKNOWN.
function Preparation.CooldownAbove(spellID, seconds, query)
    if not number(seconds) or seconds <= 0 then return nil end
    local duration = call(C_Spell and C_Spell.GetSpellCooldownDuration, spellID, true)
    if not (plain(duration, "table") or plain(duration, "userdata")) then
        return nil, "duration-unavailable"
    end
    local remaining = method(duration, "GetRemainingDuration")
    if plain(remaining, "number") then
        if number(remaining) then return remaining > seconds, "visible-duration" end
        return nil, "invalid-duration"
    end
    local scale = 1
    while scale > seconds do scale = scale / 2 end
    while scale * 2 <= seconds do scale = scale * 2 end
    local successor = seconds + scale * 2 ^ -52
    local curve = stepCurve(successor, math.max(seconds * 2, 3600))
    local atBoundary = curve and method(curve, "Evaluate", seconds)
    local atSuccessor = curve and method(curve, "Evaluate", successor)
    if plain(atBoundary, "number") and atBoundary == 0
        and plain(atSuccessor, "number") and atSuccessor == 100 then
        return binary(method(duration, "EvaluateRemainingDuration", curve), query)
    end
    -- >= floor(seconds)+1 implies > seconds without approximating an answer
    -- in the intervening interval. This also works for float-backed curves.
    local upper = math.floor(seconds) + 1
    curve = stepCurve(upper, math.max(upper * 2, 3600))
    if not curve then return nil, "strict-boundary-unavailable" end
    local far = binary(method(duration, "EvaluateRemainingDuration", curve), query)
    if far == true then return true, "engine-duration-proven-upper-bound" end
    return nil, "strict-boundary-unresolved"
end

function Preparation.ResourceAtLeast(unit, powerType, threshold, query)
    if not number(threshold) then return nil end
    local maximum = call(UnitPowerMax, unit, powerType)
    if not number(maximum) or maximum <= 0 then return nil, "resource-maximum-unknown" end
    local amount = call(UnitPower, unit, powerType)
    if plain(amount, "number") then
        if not number(amount) or amount > maximum then return nil, "invalid-resource" end
        return amount >= threshold, "visible-resource"
    end
    if threshold > maximum then return false end
    if threshold == 0 then return true end
    local curve, why = stepCurve(threshold / maximum, 1)
    if not curve then return nil, why end
    return binary(call(UnitPowerPercent, unit, powerType, false, curve), query)
end

-- Only fixed, current cost rows are supported. Conditional/variable/periodic
-- cost schemas are deliberately unknown, not guessed from a tooltip or cache.
function Preparation.FixedCost(spellID, powerType)
    local rows = call(C_Spell and C_Spell.GetSpellPowerCost, spellID)
    if not plain(rows, "table") then return nil end
    local total, found = 0, false
    for _, row in ipairs(rows) do
        if not plain(row, "table") or not number(row.type) then return nil end
        if row.type == powerType then
            if not number(row.cost) then return nil end
            for _, key in ipairs({"costPercent", "costPerSec", "requiredAuraID"}) do
                local value = row[key]
                if not plain(value, "nil") and (not number(value) or value ~= 0) then return nil end
            end
            if not plain(row.minCost, "nil") and (not number(row.minCost) or row.minCost ~= row.cost) then return nil end
            total, found = total + row.cost, true
        end
    end
    -- Missing rows for a configured spender are not proof of a free cast.
    if found and number(total) then return total end
end

-- Discrete resources (runes, charges, etc.) must supply a fresh per-slot
-- readiness reader. Count only positively readable booleans; unknown slots
-- may prove neither ready nor empty. Never predict recharge or cache answers.
function Preparation.ReadySlotsAtLeast(slotCount, threshold, readReady, query)
    if not number(slotCount) or slotCount % 1 ~= 0 or slotCount > 100
        or not number(threshold) or type(readReady) ~= "function" then return nil end
    if threshold == 0 then return true, "zero-threshold" end
    if threshold > slotCount then return false, "above-slot-capacity" end
    local ready, unknown = 0, 0
    for index = 1, slotCount do
        local value = call(readReady, index)
        if issecretvalue and issecretvalue(value) then
            -- Native boolean -> EXACT 0/1, not a rounded numeric resource.
            -- Validate both constants before forwarding any hidden result to
            -- the existing binary adapter. No frame-state/cache readback.
            local evaluate = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
            local yes, no = call(evaluate, true, 1, 0), call(evaluate, false, 1, 0)
            if plain(yes, "number") and yes == 1 and plain(no, "number") and no == 0 then
                value = binary(call(evaluate, value, 1, 0), query, 1)
            end
        end
        if plain(value, "boolean") then
            if value then ready = ready + 1 end
        else unknown = unknown + 1 end
    end
    if ready >= threshold then return true, "current-ready-slots" end
    if ready + unknown < threshold then return false, "current-insufficient-slots" end
    return nil, "slot-readiness-unknown"
end

-- Preserve the current queue's relative order, including affordable spenders.
-- Caller must first positively prove the near-window and action ownership.
function Preparation.Filter(queue, context, config)
    local output, detail = {}, {}
    for _, id in ipairs(queue) do
        local effective = context.resolve(id)
        local blocked = config.blocked[id] or config.blocked[effective]
        if not blocked and (config.spenders[id] or config.spenders[effective]) then
            local cost = Preparation.FixedCost(effective, config.powerType)
            if cost ~= nil and config.integerCosts and cost % 1 ~= 0 then cost = nil end
            local enough, why
            if cost == 0 and config.allowFree then
                enough, why = true, "current-zero-cost"
            elseif cost ~= nil and number(config.reserve) then
                if config.resourceAtLeast then
                    local ok, result, evidence = pcall(config.resourceAtLeast, config.reserve + cost)
                    if ok and plain(result, "boolean") then enough = result end
                    why = ok and plain(evidence, "string") and evidence
                        or ok and "resource-reader-unknown" or "resource-reader-error"
                else
                    enough, why = Preparation.ResourceAtLeast(config.unit or "player", config.powerType,
                        config.reserve + cost, context.query)
                end
            end
            blocked = enough ~= true
            detail[#detail + 1] = tostring(effective) .. ":cost=" .. tostring(cost)
                .. ":leaves-reserve=" .. tostring(enough)
                .. (why and ":evidence=" .. why or "")
        end
        if not blocked then output[#output + 1] = id end
    end
    return {queue = output, reason = config.reason .. ":" .. table.concat(detail, ";")}
end
