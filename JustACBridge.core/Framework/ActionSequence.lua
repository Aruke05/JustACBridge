-- Reusable prerequisite + success-confirmed sequence mechanism. No class IDs,
-- resource thresholds, APL, cooldown inference, or automatic opt-in lives here.
local Sequence = {}
_G.JustACBridgeActionSequence = Sequence

local function plain(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end

local function seconds(value)
    return plain(value, "number") and value == value and value >= 0 and value < math.huge
end

-- Current haste, never the duration of an earlier GCD. Unknown haste can only
-- use the policy's proven minimum, not an invented 'normal' GCD. These are
-- admission budgets, NOT timers, queued casts, or evidence of successful casts.
function Sequence.HastedGCD(base, minimum, haste)
    if not seconds(base) or not seconds(minimum) or minimum > base then return nil end
    if not plain(haste, "number") or haste ~= haste or haste <= -100 or haste == math.huge then
        return minimum, "minimum-gcd-proof"
    end
    return math.max(minimum, base / (1 + haste / 100)), "current-haste"
end

-- false is positive absence; nil means unknown. Never collapse the two when
-- deciding whether an OPTIONAL prerequisite can be skipped.
function Sequence.Ownership(ids, readers)
    local observed, unknown = false, false
    for _, id in ipairs(ids) do
        for _, reader in ipairs(readers) do
            if type(reader) == "function" then
                local ok, result = pcall(reader, id)
                if ok and plain(result, "boolean") then
                    if result then return true end
                    observed = true
                else unknown = true end
            end
        end
    end
    if observed and not unknown then return false end
end

function Sequence.Binding(ok, hotkey)
    if ok == true and plain(hotkey, "string") then return hotkey ~= "" end
end

function Sequence.Prerequisite(evidence)
    if plain(evidence.known, "boolean") and evidence.known == false then
        return "skip", "not-learned"
    end
    if not plain(evidence.known, "boolean") then return "wait", "ownership-unknown" end
    if plain(evidence.bound, "boolean") and evidence.bound == false then
        return "skip", "not-bound"
    end
    if not plain(evidence.bound, "boolean") then return "wait", "binding-unknown" end
    if not plain(evidence.ready, "boolean") then return "wait", "cooldown-unknown" end
    if not evidence.ready then return "wait", "cooldown-active" end
    if not plain(evidence.usable, "boolean") or not plain(evidence.noPower, "boolean") then
        return "wait", "usability-unknown"
    end
    if evidence.noPower then return "wait", "insufficient-power" end
    if not evidence.usable then return "wait", "unusable" end
    return "ready", "ready"
end

function Sequence.Describe(evidence)
    local result = {}
    for _, key in ipairs({"known", "bound", "ready", "usable", "noPower"}) do
        local v = evidence[key]
        result[#result + 1] = key .. "=" .. (plain(v, "boolean") and tostring(v) or "unknown")
    end
    return table.concat(result, ",")
end

-- Filtering is deletion-only and never mutates the latest upstream queue.
-- An empty result is authoritative: callers MUST NOT append ordinary fallback.
function Sequence.Filter(queue, resolve, blocked, reason, passthrough)
    local filtered = {}
    for _, id in ipairs(queue) do
        local effective = resolve(id)
        if (passthrough and passthrough[effective]) or (not blocked[id] and not blocked[effective]) then
            filtered[#filtered + 1] = id
        end
    end
    return {queue = filtered, reason = reason}
end

local State = {}
State.__index = State

function Sequence.New(config)
    assert(type(config.steps) == "table" and #config.steps > 0)
    assert(type(config.withinSeconds) == "number" and config.withinSeconds > 0)
    local self = setmetatable({config = config, membership = {}}, State)
    for index, step in ipairs(config.steps) do
        assert(type(step.spellID) == "number" and type(step.name) == "string")
        assert(not self.membership[step.spellID], "duplicate sequence spell")
        self.membership[step.spellID] = index
        for _, id in ipairs(step.aliases or {}) do
            assert(not self.membership[id], "duplicate sequence alias")
            self.membership[id] = index
        end
    end
    self:Reset()
    return self
end

-- Stateless look-ahead, opt-in per step via gcdAfter (0 for off-GCD). A later
-- action needs to be ready by ITS position, not at the opener. Unknown timing
-- never prevents an already-ready group; it only withholds early admission.
-- Readers are current-frame evidence supplied by the class policy. Ownership,
-- binding, resources and the opener's actual usability remain its responsibility.
function State:CanStartCooldowns(ready, within, gcd, startDelay)
    local budget, detail = seconds(startDelay) and startDelay or 0, {}
    for index, step in ipairs(self.config.steps) do
        local ok, value = pcall(ready, step.spellID)
        local status = "ready"
        if not ok or not plain(value, "boolean") then
            return nil, "cooldown-unknown:" .. step.name
        end
        if not value then
            if index == 1 or not seconds(budget) or budget <= 0 then
                return false, "cooldown-active:" .. step.name
            end
            local readOK, byThen = pcall(within, step.spellID, budget)
            if not readOK or not plain(byThen, "boolean") then
                return nil, "deadline-unknown:" .. step.name
            end
            if not byThen then return false, "deadline-missed:" .. step.name end
            status = "by=" .. tostring(budget)
        end
        detail[#detail + 1] = step.name .. ":" .. status
        if index < #self.config.steps then
            local count = step.gcdAfter
            if not seconds(count) or not seconds(budget) then budget = nil
            elseif count > 0 then
                if seconds(gcd) then budget = budget + count * gcd else budget = nil end
            end
        end
    end
    return true, table.concat(detail, ",")
end

function State:Reset()
    self.step, self.stepAt, self.windowAt, self.target = nil, nil, nil, nil
    self.proposed, self.proposedAt, self.suspended = nil, nil, nil
end

function State:Cancel()
    self.step, self.stepAt, self.windowAt = nil, nil, nil
    self.proposed, self.proposedAt, self.suspended = nil, nil, true
end

function State:Check(context)
    local key = context.targetKey or context.targetGUID
    if not key or context.outOfRange then
        self:Reset()
        return false, context.outOfRange and "out-of-range" or "no-target-identity"
    end
    if self.target and self.target ~= key then self:Reset() end
    local limit = self.config.withinSeconds
    if self.step and (context.now < self.stepAt or context.now - self.stepAt >= limit
        or self.windowAt and context.now - self.windowAt >= limit) then
        self:Cancel()
        return false, "sequence-expired"
    end
    return true
end

function State:Propose(index, context, reason, skippedEvidence)
    assert(self.config.steps[index], "unknown sequence step")
    local expected = self.step or 1
    assert(index >= expected, "cannot replay a completed sequence step")
    for predecessor = expected, index - 1 do
        local evidence = skippedEvidence and skippedEvidence[predecessor]
        assert(self.config.steps[predecessor].optional and evidence
            and Sequence.Prerequisite(evidence) == "skip",
            "cannot skip a predecessor without positive absence/binding proof")
    end
    self.target, self.proposed, self.proposedAt = context.targetKey or context.targetGUID, index, context.now
    return {spellID = self.config.steps[index].spellID,
        reason = reason or "EXPECT_" .. self.config.steps[index].name}
end

function State:HasProposal(now)
    return self.proposed ~= nil and now >= self.proposedAt
        and now - self.proposedAt < self.config.withinSeconds
end

function State:Observe(event, spellID, targetGUID, now)
    if not plain(spellID, "number") then return end
    if not self.target or self.target ~= targetGUID then self:Reset(); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local index = self.membership[spellID]
        if self:HasProposal(now) and index == self.proposed then
            if self.config.steps[index].windowAnchor then self.windowAt = now end
            if index == #self.config.steps then self:Cancel(); return end
            self.step, self.stepAt = index + 1, now
            self.proposed, self.proposedAt = nil, nil
        elseif index or (self.config.cancelSpellIDs or {})[spellID] then
            self:Cancel() -- real out-of-order cast, not a transient failed keypress
        end
    elseif self.config.cancelOnFailure and self.membership[spellID]
        and (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
            or event == "UNIT_SPELLCAST_INTERRUPTED") then
        self:Cancel()
    end
end
