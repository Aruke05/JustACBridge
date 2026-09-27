local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end
local Sequence = assert(_G.JustACBridgeActionSequence, "ActionSequence must load before Frost policy")
local Preparation = assert(_G.JustACBridgeResourcePreparation, "ResourcePreparation must load before Frost policy")

-- These helpers deliberately do not use JustAC's fail-open usability/charge
-- wrappers or its memoized percentage power predicate. Unknown cooldowns do
-- not establish a burst window; unknown affordability never opens its gate.
local function visible(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end

local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value, extra = pcall(fn, ...)
    if ok then return value, extra end
end

local cooldownProbe
local function cooldownReady(spellID)
    -- GCD-excluded DurationObjects, without IsSpellReady's look-ahead. Unlike
    -- upstream's convenience wrapper, nil/error is NOT an inactive cooldown.
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local duration = read(C_Spell.GetSpellCooldownDuration, spellID, true)
    if (issecretvalue and issecretvalue(duration)) or duration == nil then return nil end
    local ok, ready = pcall(function()
        if not cooldownProbe then
            if not CreateFrame then return nil end
            local holder = CreateFrame("Frame", nil, UIParent)
            holder:Hide()
            cooldownProbe = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
        end
        if type(cooldownProbe.SetCooldownFromDurationObject) ~= "function"
            or type(cooldownProbe.IsShown) ~= "function"
            or type(cooldownProbe.SetCooldown) ~= "function" then return nil end
        cooldownProbe:SetCooldown(0, 0)
        cooldownProbe:SetCooldownFromDurationObject(duration)
        local shown = cooldownProbe:IsShown()
        cooldownProbe:SetCooldown(0, 0)
        if visible(shown, "boolean") then return not shown end
    end)
    if ok then return ready end
end

local function power()
    local amount = read(UnitPower, "player", 6)
    local maximum = read(UnitPowerMax, "player", 6)
    if visible(amount, "number") and (amount ~= amount or amount < 0 or amount >= math.huge)
        or visible(maximum, "number") and (maximum ~= maximum or maximum < 60 or maximum >= math.huge)
        or visible(amount, "number") and visible(maximum, "number") and amount > maximum then
        return nil, nil, "invalid"
    end
    if visible(amount, "number") and visible(maximum, "number")
        and maximum >= 60 and maximum < math.huge
        and amount >= 0 and amount <= maximum then return amount, maximum end
end

local function usability(spellID, query)
    local usable, noPower
    if type(query) == "function" then
        local ok
        ok, usable, noPower = query("IsSpellUsableStrict", spellID)
        if not ok then return nil end
    else
        usable, noPower = read(C_Spell and C_Spell.IsSpellUsable, spellID)
    end
    if visible(usable, "boolean") and visible(noPower, "boolean") then
        return usable, noPower
    end
end

local function breathAffordable(spellID, query)
    local amount, _, powerState = power()
    if powerState == "invalid" then return nil, "invalid-resource-state" end
    if amount and amount < 60 then return false, "rp-below-60" end
    -- Numeric RP can be secret even when the engine positively reports this
    -- exact spell affordable. Do not require an unavailable numeric duplicate
    -- of that proof; never replace it with the upstream fail-open boolean.
    local usable, noPower = usability(spellID, query)
    if usable == nil then return nil, "strict-usability-unknown" end
    if not usable or noPower then return false, noPower and "insufficient-power" or "unusable" end
    return true, amount and "ready-visible-rp" or "ready-engine-affordability"
end

-- User-requested M5 gate, not a full Frost APL. Pool BEFORE spending Pillar.
-- The three cooldowns are observed afresh; neither queue membership nor a
-- recommendation counts as a successful cast or credits generated RP.
local BURST = { [439843] = true, [51271] = true, [152279] = true,
    [1249658] = true, [279302] = true }
local SPENDERS = { [49143] = true, [1228433] = true, -- Frost Strike / Frostbane
    [194913] = true, [49998] = true }
-- Rune-consuming Frost/common DK actions only. Costs (including free procs)
-- come from the CURRENT effective spell, never a hard-coded cost or proc guess.
local RUNE_SPENDERS = { [49020] = true, [49184] = true, [196770] = true,
    [207230] = true, [43265] = true, [152280] = true, [45524] = true,
    [343294] = true }
local POOL_BLOCKED = {}
for id in pairs(BURST) do POOL_BLOCKED[id] = true end
for id in pairs(SPENDERS) do POOL_BLOCKED[id] = true end
local sequence = Sequence.New({
    withinSeconds = 10,
    cancelOnFailure = false, -- held M5 can legitimately fail during GCD
    cancelSpellIDs = { [1265384] = true },
    steps = {
        {spellID = 439843, name = "MARK", gcdAfter = 1},
        {spellID = 51271, name = "PILLAR", windowAnchor = true, gcdAfter = 0},
        {spellID = 1249658, name = "BREATH", aliases = {152279}, gcdAfter = 0},
        {spellID = 279302, name = "FURY"},
    },
})
-- A second DECLARATIVE sequence, not a second hand-written state machine.
-- It has no Breath step/resource reserve and ends on successful Pillar.
local smallSequence = Sequence.New({
    withinSeconds = 10,
    cancelOnFailure = false,
    steps = {
        {spellID = 439843, name = "MARK", gcdAfter = 1},
        {spellID = 51271, name = "PILLAR"},
    },
})
local function resetBurst() sequence:Reset(); smallSequence:Reset() end
local function observeBurstCast(event, spellID, targetGUID)
    sequence:Observe(event, spellID, targetGUID, GetTime())
    smallSequence:Observe(event, spellID, targetGUID, GetTime())
end
local PASSTHROUGH = { [1265384] = true } -- explicit live recall, never first Fury
local function startCooldowns(instance, context)
    -- Frost uses a 1.5s melee-hasted GCD, floored at 0.75s. Pillar and Breath
    -- add ZERO GCDs: all three successors share Mark's one-GCD deadline.
    -- No old GCD/haste cache, no latency padding, no forecast of RP generation.
    local gcd, evidence = Sequence.HastedGCD(1.5, 0.75, read(GetHaste))
    local delay = read(JustACBridgeQueueTiming and JustACBridgeQueueTiming.ReadGCDRemaining)
    local ready, why = instance:CanStartCooldowns(cooldownReady, function(id, budget)
        return Preparation.CooldownAtMost(id, budget, context.query)
    end, gcd, delay)
    return ready, why .. ":gcd=" .. tostring(gcd) .. ":" .. tostring(evidence)
        .. ":startDelay=" .. tostring(delay)
end
local function gatedQueue(queue, context, pool, reason)
    local decision = Sequence.Filter(queue, context.resolve, pool and POOL_BLOCKED or BURST, reason, PASSTHROUGH)
    decision.allowCastFollowup = not pool
    return decision
end

local function selectSmallBurst(queue, context, pillarReady)
    local function wait(reason)
        -- No 60-RP reservation here: ordinary spenders keep source order.
        return gatedQueue(queue, context, false, reason)
    end
    if smallSequence.suspended then
        if pillarReady == false then smallSequence:Reset()
        else return wait("SMALL_COMPLETE_WAIT_COOLDOWN") end
    end
    if smallSequence:HasProposal(context.now)
        and cooldownReady(smallSequence.config.steps[smallSequence.proposed].spellID) == false then
        if smallSequence.step then return {queue = {}, reason = "WAIT_SMALL_CAST_CONFIRM"} end
        return wait("WAIT_SMALL_CAST_CONFIRM")
    end
    if smallSequence.step == 2 then
        local usable, noPower = usability(51271, context.query)
        if pillarReady == true and usable == true and noPower == false then
            return smallSequence:Propose(2, context, "SMALL_EXPECT_PILLAR")
        end
        -- The pair is committed. Do not insert a filler GCD into the last
        -- milliseconds before the planned Pillar, or restart at cooling Mark.
        return {queue = {}, reason = "WAIT_SMALL_PILLAR_STEP"}
    end
    local timing, timingReason = startCooldowns(smallSequence, context)
    local usable, noPower = usability(51271, context.query)
    if (pillarReady ~= true and timing ~= true) or usable ~= true or noPower ~= false then
        return wait("WAIT_SMALL_PILLAR:" .. timingReason)
    end
    local evidence = context.inspect(439843)
    evidence.ready = cooldownReady(439843)
    evidence.usable, evidence.noPower = usability(439843, context.query)
    local disposition, why = Sequence.Prerequisite(evidence)
    local detail = why .. ":" .. Sequence.Describe(evidence)
    if disposition == "ready" then
        return smallSequence:Propose(1, context, "SMALL_EXPECT_MARK:" .. detail .. ";START_TIMING:" .. timingReason)
    end
    if visible(evidence.known, "boolean") and evidence.known
        and visible(evidence.bound, "boolean") and evidence.bound and evidence.ready == true
        and (evidence.usable == false or evidence.noPower == true) then
        -- Do not repeatedly spend the runes this mandatory opener needs.
        return {queue = {}, reason = "WAIT_SMALL_MARK:" .. detail,
            markResourceWait = evidence.noPower == true}
    end
    return wait("WAIT_SMALL_MARK:" .. detail)
end

local function prepareUpcomingBurst(queue, context, readiness)
    -- Six seconds is a bounded user-selected preparation horizon, NOT a full
    -- APL or a forecast of future resource gains. All evidence is current.
    for _, id in ipairs({51271, 1249658, 279302}) do
        if readiness[id] ~= true then
            if readiness[id] ~= false then return nil, "PREP_BREATH_UNKNOWN_CD:" .. id end
            local near, evidence = Preparation.CooldownBelow(id, 6, context.query)
            if near ~= true then
                return nil, "PREP_BREATH_NOT_NEAR:" .. id .. ":within6=" .. tostring(near)
                    .. ":evidence=" .. tostring(evidence)
            end
        end
    end
    -- Mark is mandatory in BOTH variants. Absence/unknown cannot authorize
    -- standalone Pillar, nor justify reserving RP for an unavailable opener.
    local mark = context.inspect(439843)
    if not visible(mark.known, "boolean") or not visible(mark.bound, "boolean")
        or not mark.known or not mark.bound then return nil, "PREP_BREATH_MARK_UNAVAILABLE" end
    if cooldownReady(439843) ~= true
        and Preparation.CooldownBelow(439843, 6, context.query) ~= true then
        return nil, "PREP_BREATH_MARK_NOT_NEAR"
    end
    return Preparation.Filter(queue, context, {
        blocked = BURST, spenders = SPENDERS, powerType = 6, reserve = 60,
        reason = "PREP_BREATH_WITHIN_6S",
    })
end

local function markPreparationConfig(context)
    -- Prepare for the actual selected group, not merely two ready buttons:
    -- if either dragon is near/unknown, ALL FOUR must be within 6 seconds.
    -- After Mark's success the reserve is spent; never keep it through Pillar.
    if sequence.step or smallSequence.step or context.outOfRange
        or not (context.targetKey or context.targetGUID)
        or context.targetContext and context.targetContext.valid ~= true then return nil end
    for _, id in ipairs({439843,51271,1249658,279302}) do
        if context.resolve(id) ~= id or context.canUse(id) ~= true then return nil end
    end
    local mark = context.inspect(439843)
    if not visible(mark.known, "boolean") or not mark.known
        or not visible(mark.bound, "boolean") or not mark.bound then return nil end
    local function near(id)
        local ready = cooldownReady(id)
        return ready == true or ready == false and Preparation.CooldownBelow(id, 6, context.query) == true
    end
    if not near(439843) or not near(51271) then return nil end
    local bothFar = cooldownReady(1249658) == false and cooldownReady(279302) == false
        and Preparation.CooldownAbove(1249658, 18, context.query) == true
        and Preparation.CooldownAbove(279302, 18, context.query) == true
    if not bothFar and not (near(1249658) and near(279302)) then return nil end
    local reserve = Preparation.FixedCost(439843, 5)
    if reserve and reserve % 1 ~= 0 then reserve = nil end
    return {
        blocked = BURST, spenders = RUNE_SPENDERS, powerType = 5, reserve = reserve,
        allowFree = true, integerCosts = true,
        resourceAtLeast = function(threshold)
            return Preparation.ReadySlotsAtLeast(6, threshold, function(index)
                return select(3, GetRuneCooldown(index))
            end, context.query)
        end,
        reason = "PREP_MARK_WITHIN_6S:reserve=" .. tostring(reserve),
    }
end

local function selectBurst(queue, context)
    if context.targetContext and context.targetContext.valid == nil and not context.outOfRange then
        -- Unknown is not absent and cannot hand an unguarded burst back to the
        -- ordinary queue. Keep success receipts bounded, but export only safe
        -- original-order generators until live target validity is readable.
        sequence:Check(context)
        if not smallSequence:Check(context) and smallSequence.suspended then
            smallSequence:Reset() -- expiry while target evidence is hidden is not completion
        end
        return gatedQueue(queue, context, true, "WAIT_TARGET_EVIDENCE:" .. context.targetContext.evidence)
    end
    local valid, invalidReason = sequence:Check(context)
    local smallValid = smallSequence:Check(context)
    if not valid then return nil, "burst-" .. invalidReason end
    if not smallValid and smallSequence.suspended then
        smallSequence:Reset()
        return gatedQueue(queue, context, false, "SMALL_SEQUENCE_EXPIRED")
    end
    local phase = sequence.step and sequence.config.steps[sequence.step].name
    local function eligible(id) return context.canUse(id) == true end
    for _, id in ipairs({51271, 1249658, 279302}) do
        if not eligible(id) then
            resetBurst()
            return nil, "burst-unlearned-or-unbound:" .. tostring(id)
        end
    end
    -- Recall is not a new first Fury and must stay owned by JustAC.
    if context.resolve(279302) ~= 279302 or context.resolve(1249658) ~= 1249658 then
        resetBurst()
        return nil, "burst-override-delegate"
    end
    local pillarReady, breathCDReady, furyReady = cooldownReady(51271), cooldownReady(1249658), cooldownReady(279302)
    local alignmentDetail
    -- Finish a committed small pair on its own success receipts. Before
    -- commitment, select it only when BOTH dragons are positively far away.
    -- Unknown/near cooldowns are never interpreted as a long unavailable CD.
    if smallValid and not phase and not sequence:HasProposal(context.now) then
        local activeSmall = smallSequence.step or (smallSequence:HasProposal(context.now)
            and cooldownReady(439843) == false)
        local breathFar, breathEvidence, furyFar, furyEvidence
        if breathCDReady == false and furyReady == false then
            breathFar, breathEvidence = Preparation.CooldownAbove(1249658, 18, context.query)
            furyFar, furyEvidence = Preparation.CooldownAbove(279302, 18, context.query)
        end
        local bothFar = breathCDReady == false and furyReady == false and breathFar == true and furyFar == true
        alignmentDetail = ":align18:breathFar=" .. tostring(breathFar) .. ":" .. tostring(breathEvidence)
            .. ":furyFar=" .. tostring(furyFar) .. ":" .. tostring(furyEvidence)
        if activeSmall or bothFar then
            return selectSmallBurst(queue, context, pillarReady)
        end
        smallSequence:Reset()
    end
    if sequence.suspended then
        if pillarReady == false or breathCDReady == false or furyReady == false then sequence.suspended = nil
        else return nil, "burst-attempt-complete-or-cancelled" end
    end
    if not phase and sequence:HasProposal(context.now)
        and cooldownReady(sequence.config.steps[sequence.proposed].spellID) == false then
        -- SPELL_UPDATE_COOLDOWN may precede UNIT_SPELLCAST_SUCCEEDED. Do not
        -- skip a just-cast Mark/Pillar because its cooldown appeared first.
        return gatedQueue(queue, context, true, "WAIT_CAST_CONFIRM")
    end
    local timing, timingReason
    if not phase then timing, timingReason = startCooldowns(sequence, context) end
    if not phase and timing ~= true and (pillarReady ~= true or breathCDReady ~= true or furyReady ~= true) then
        local prepared, reason = prepareUpcomingBurst(queue, context,
            {[51271] = pillarReady, [1249658] = breathCDReady, [279302] = furyReady})
        if prepared then prepared.reason = prepared.reason .. ";START_TIMING:" .. timingReason end
        return prepared, tostring(reason) .. (alignmentDetail or "") .. ";START_TIMING:" .. timingReason
    end
    local function choose(id, reason)
        return sequence:Propose(sequence.membership[id], context, reason)
    end
    if phase == "FURY" then
        local usable, noPower = usability(279302, context.query)
        if furyReady == true and usable == true and noPower == false then
            return choose(279302, "EXPECT_FURY")
        end
        return {queue = {}, reason = "WAIT_FURY"}
    end
    if phase == "BREATH" and breathCDReady ~= true then
        if sequence.proposed == 3 then
            return {queue = {}, reason = "WAIT_BREATH_CONFIRM"}
        end
        -- A successor admitted for its turn may legitimately still be cooling
        -- now. Current-step readiness, not a new whole-group zero-CD gate.
        return {queue = {}, reason = "WAIT_BREATH_STEP"}
    end
    if not phase then
        local mark = context.inspect(439843)
        if not visible(mark.known, "boolean") or not mark.known
            or not visible(mark.bound, "boolean") or not mark.bound then
            local disposition, why = Sequence.Prerequisite(mark)
            local reason = "WAIT_MARK:" .. why .. ":" .. Sequence.Describe(mark)
            if disposition == "skip" then return gatedQueue(queue, context, false, reason) end
            return {queue = {}, reason = reason}
        end
        if cooldownReady(439843) ~= true then
            local prepared = prepareUpcomingBurst(queue, context,
                {[51271] = pillarReady, [1249658] = breathCDReady, [279302] = furyReady})
            if prepared then return prepared end
            local mark = context.inspect(439843)
            mark.ready = cooldownReady(439843)
            mark.usable, mark.noPower = usability(439843, context.query)
            local _, why = Sequence.Prerequisite(mark)
            return gatedQueue(queue, context, false, "WAIT_MARK:" .. why .. ":" .. Sequence.Describe(mark))
        end
    end
    if not phase then
        for _, id in ipairs({51271, 279302}) do
            local usable, noPower = usability(id, context.query)
            if usable ~= true or noPower ~= false then
                return gatedQueue(queue, context, false, "WAIT_FULL_MEMBER:" .. id)
            end
        end
    end
    local affordable, why = breathAffordable(1249658, context.query)
    if affordable ~= true then
        -- This does NOT cancel the window. Continue original-order generators
        -- (including JustAC's ERW), but no RP spender or burst can leak through.
        return gatedQueue(queue, context, true, "POOL_BREATH:" .. tostring(why))
    end
    if phase == "BREATH" then return choose(1249658, "EXPECT_BREATH") end
    if phase == "PILLAR" then
        local usable, noPower = usability(51271, context.query)
        if pillarReady == true and usable == true and noPower == false then
            return choose(51271, "EXPECT_PILLAR")
        end
        return {queue = {}, reason = "WAIT_PILLAR"}
    end
    -- This profile declares Mark mandatory. The shared evaluator's 'skip'
    -- means positive absence, not permission to omit a required predecessor.
    -- Unknown, cooldown, GCD and resource shortage all hold the sequence.
    local evidence = context.inspect(439843)
    evidence.ready = cooldownReady(439843)
    evidence.usable, evidence.noPower = usability(439843, context.query)
    local disposition, why = Sequence.Prerequisite(evidence)
    local detail = why .. ":" .. Sequence.Describe(evidence)
    if disposition == "ready" then
        return choose(439843, "EXPECT_MARK:" .. detail .. ";START_TIMING:" .. tostring(timingReason))
    end
    -- Required Mark may never be skipped, even when absent/unbound. Waiting
    -- for a temporarily unusable learned Mark must not consume its runes.
    if disposition == "wait" then
        return {queue = {}, reason = "WAIT_MARK:" .. detail,
            markResourceWait = evidence.noPower == true, keepBreathResource = true}
    end
    return gatedQueue(queue, context, false, "WAIT_MARK:" .. detail)
end

-- All exits, including unknown cooldowns, missing members, target reset,
-- recall and completion, retain group ownership. NEVER delegate these four
-- actions back to an unfiltered upstream queue. The core also enforces this
-- exclusion if this selector throws or unexpectedly returns nil.
local function selectGroupedBurst(queue, context)
    if not Preparation.IsEnabled(context) then
        -- A preserve/unspecified context can neither start a burst nor read
        -- its resource gates; preserve the original ordinary-action order.
        return Sequence.Filter(queue, context.resolve, BURST, "BURST_PREPARATION_DISABLED_FOR_MODE", PASSTHROUGH)
    end
    local decision, reason = selectBurst(queue, context)
    decision = decision or gatedQueue(queue, context, false, "WAIT_GROUP:" .. tostring(reason))
    if not decision.spellID then
        local config = markPreparationConfig(context)
        if config then
            -- Replace the old all-M5 resource pause only with proven safe
            -- current-queue actions. Full windows must retain BOTH reserves.
            local candidates = decision.queue
            if decision.markResourceWait then
                candidates = gatedQueue(queue, context, false, decision.reason).queue
                if decision.keepBreathResource then
                    local breathPrepared = Preparation.Filter(candidates, context, {
                        blocked = BURST, spenders = SPENDERS, powerType = 6,
                        reserve = 60, reason = "KEEP_BREATH_RESERVE",
                    })
                    candidates = breathPrepared.queue
                    decision.reason = decision.reason .. ";" .. breathPrepared.reason
                end
            end
            local prepared = Preparation.Filter(candidates, context, config)
            prepared.reason = decision.reason .. ";" .. prepared.reason
            prepared.allowCastFollowup = decision.allowCastFollowup
            return prepared
        end
    end
    return decision
end

Registry.RegisterSpec("DEATHKNIGHT", 2, {
    id = "frost",
    name = "冰霜",
    revision = 15,
    -- Frost owns an exact M4 preserve set.  A stale/custom JustAC Burst
    -- Trigger must not turn resource recovery or Raise Dead back into a hold;
    -- explicit /jacb reserve overrides remain authoritative in the core.
    useDetectedBurstTriggers = false,
    -- M4 may consume Howling Blast when it is present in JustAC's real queue,
    -- but never invents a ranged filler from proc/highlight/final-fallback data.
    preserveSourceQueueOnly = true,
    -- At confirmed range, M5 accepts only a real JustAC Howling Blast entry;
    -- every other action waits while the player handles movement.
    losslessSourceQueueOnlyBeyond = {
        beyond = 5,
        allow = { 49184 },
    },
    preserveSourceQueueOnlyBeyond = {
        beyond = 5,
        allow = { 49184 },
    },
    fallbackActions = {
        { spellID = 49184, requireProc = true, label = "白霜凛风冲击" },
        { spellID = 49184, label = "凛风冲击" },
    },
    reserve = {
        51271,   -- Pillar of Frost
        152279,  -- Breath of Sindragosa
        1249658, -- Breath of Sindragosa (current override)
        279302,  -- Frostwyrm's Fury
        439843,  -- Reaper's Mark
    },
    -- Directional frontal movement is left to M5/manual facing.
    reserveExclusions = {
        194913, -- Glacial Advance
        207230, -- Frostscythe
    },
    castSequenceRules = {
        {
            spellID = 279302,      -- Frostwyrm's Fury
            afterSpellID = 51271,  -- Pillar of Frost
            afterAuraID = 51271,
            -- The base buff lasts 12 sec. When aura data is hidden, accept
            -- only the first 10 sec after the authoritative success event.
            withinSeconds = 10,
            -- Chosen of Frostbrood's recall is a live action-bar override.
            -- Its timing stays entirely owned by JustAC.
            passthroughEffectiveSpellIDs = { 1265384 },
            label = "冰霜巨龙之怒必须在冰霜之柱之后",
        },
    },
    castFollowups = {
        {
            spellID = 46585,       -- Raise Dead
            triggerSpells = { 279302 }, -- First Frostwyrm's Fury only
            withinSeconds = 4,
            lossless = true,
            preserve = false,
            label = "冰霜巨龙之怒后接亡者复生",
        },
    },
    versions = {
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 28,
            selectionTargetScope = "target-epoch",
            selectLossless = selectGroupedBurst,
            losslessSelectionFallbackBlock = {439843, 51271, 152279, 1249658, 279302},
            losslessSelectionPassthrough = {1265384},
            resetLosslessSelection = resetBurst,
            observePlayerSpellcast = observeBurstCast,
            addCastSequenceRules = {
                { spellID = 152279, afterSpellID = 51271,
                    afterAuraID = 51271, withinSeconds = 10 },
                { spellID = 1249658, afterSpellID = 51271,
                    afterAuraID = 51271, withinSeconds = 10 },
            },
            -- A JustAC fallback or the experimental source's fallback=true
            -- path may only delete unsafe entries while retaining source
            -- order. It must not manufacture Howling Blast merely because
            -- the player is moving or the queue is empty.
            fallbackActions = {},
        },
    },
})
