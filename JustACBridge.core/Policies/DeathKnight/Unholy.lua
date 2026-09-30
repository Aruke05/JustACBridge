local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end
local Sequence = assert(_G.JustACBridgeActionSequence, "ActionSequence must load before Unholy policy")
local Preparation = assert(_G.JustACBridgeResourcePreparation,
    "ResourcePreparation must load before Unholy policy")

local ARMY, TRANSFORM = 42650, 1233448
local PAIR = {[ARMY] = true, [63560] = true, [TRANSFORM] = true}
local pair = Sequence.New({
    withinSeconds = 10,
    cancelOnFailure = false, -- a held key can fail during GCD without a cast
    steps = {
        {spellID = ARMY, name = "ARMY", optional = true},
        {spellID = TRANSFORM, name = "DARK_TRANSFORMATION", aliases = {63560}},
    },
})
local cooldownProbe

local function plain(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end

local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

-- Read the actual spell cooldown with GCD excluded. A missing/hidden duration
-- cannot establish either a ready Army or the strict 30-second split.
local function cooldownReady(spellID)
    local duration = read(C_Spell and C_Spell.GetSpellCooldownDuration, spellID, true)
    if duration == nil or (issecretvalue and issecretvalue(duration)) then return nil end
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
        if plain(shown, "boolean") then return not shown end
    end)
    if ok then return ready end
end

local function inspect(spellID, context)
    local evidence = context.inspect(spellID)
    evidence.ready = cooldownReady(spellID)
    local ok, usable, noPower = context.query("IsSpellUsableStrict", spellID)
    if ok and plain(usable, "boolean") and plain(noPower, "boolean") then
        evidence.usable, evidence.noPower = usable, noPower
    end
    return evidence, Sequence.Prerequisite(evidence)
end

local function ordinary(queue, context, reason)
    return Sequence.Filter(queue, context.resolve, PAIR, reason)
end

local function selectArmyTransformation(queue, context)
    if context.mode ~= "lossless" then
        return ordinary(queue, context, "UNHOLY_PAIR_M5_ONLY")
    end
    local valid, why = pair:Check(context)
    if not valid or context.targetContext and context.targetContext.valid ~= true then
        return ordinary(queue, context, "WAIT_UNHOLY_TARGET:" .. tostring(why))
    end

    -- A successful Army event owns this follower even when Army's cooldown
    -- update arrives first. Do not spend a filler GCD between the two steps.
    if pair.step == 2 then
        local transformation, status = inspect(TRANSFORM, context)
        if status == "ready" then
            return pair:Propose(2, context, "EXPECT_DARK_TRANSFORMATION")
        end
        return {queue = {}, reason = "WAIT_DARK_TRANSFORMATION:" .. Sequence.Describe(transformation)}
    end
    if pair:HasProposal(context.now)
        and cooldownReady(pair.config.steps[pair.proposed].spellID) == false then
        return {queue = {}, reason = "WAIT_UNHOLY_CAST_CONFIRM"}
    end

    local army, armyStatus = inspect(ARMY, context)
    local transformation, transformationStatus = inspect(TRANSFORM, context)
    if pair.suspended then
        if army.ready == false or transformation.ready == false then pair.suspended = nil
        else return ordinary(queue, context, "WAIT_UNHOLY_COOLDOWN_UPDATE") end
    end
    if transformationStatus ~= "ready" then
        if transformationStatus == "skip" and armyStatus == "ready" and queue[1] == ARMY then
            return {spellID = ARMY, reason = "ARMY_WITHOUT_TRANSFORMATION"}
        end
        return ordinary(queue, context,
            "WAIT_DARK_TRANSFORMATION:" .. Sequence.Describe(transformation))
    end
    if armyStatus == "skip" then
        return pair:Propose(2, context, "DARK_TRANSFORMATION_NO_ARMY", {[1] = army})
    end
    if army.known ~= true or army.bound ~= true then
        return ordinary(queue, context, "WAIT_ARMY_OWNERSHIP:" .. Sequence.Describe(army))
    end
    if army.ready == true then
        if armyStatus == "ready" and queue[1] == ARMY then
            -- JustAC (or the explicitly selected Unholy source) still owns
            -- higher-priority disease/scythe setup before its Army queue head.
            return pair:Propose(1, context, "EXPECT_ARMY")
        end
        return ordinary(queue, context, "WAIT_ARMY_SOURCE:" .. Sequence.Describe(army))
    end
    if army.ready == false then
        local far, evidence = Preparation.CooldownAbove(ARMY, 30, context.query)
        if far == true then
            return {spellID = TRANSFORM,
                reason = "DARK_TRANSFORMATION_ARMY_ABOVE_30:" .. tostring(evidence)}
        end
        return ordinary(queue, context,
            "HOLD_DARK_TRANSFORMATION_ARMY_AT_MOST_30:" .. tostring(evidence))
    end
    return ordinary(queue, context, "WAIT_ARMY_COOLDOWN_UNKNOWN")
end

local function resetPair() pair:Reset() end
local function observePair(event, spellID, targetKey)
    pair:Observe(event, spellID, targetKey, read(GetTime))
end

Registry.RegisterSpec("DEATHKNIGHT", 3, {
    id = "unholy",
    name = "邪恶",
    revision = 4,
    fallbackActions = {
        { spellID = 207317, minEnemies = 5, label = "传染" },
        { spellID = 47541, label = "凋零缠绕" },
    },
    reserve = {
        63560,   -- Dark Transformation (base)
        1233448, -- Dark Transformation (current override)
        42650,   -- Army of the Dead
        275699,  -- Apocalypse (legacy)
        220143,  -- Apocalypse (current)
        207289,  -- Unholy Assault
        49206,   -- Summon Gargoyle
        288853,  -- Raise Abomination
        390279,  -- Vile Contagion
        1247378, -- Putrefy / 腐化
    },
    versions = {
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 7,
            selectionTargetScope = "target-epoch",
            selectLossless = selectArmyTransformation,
            losslessSelectionFallbackBlock = {ARMY, 63560, TRANSFORM},
            resetLosslessSelection = resetPair,
            observePlayerSpellcast = observePair,
            -- Midnight 12.1 has only two policy-owned burst cooldowns:
            -- Army and Dark Transformation. Putrefy is a charge-based
            -- rotational action and must remain owned by JustAC. Ignore stale
            -- Burst Trigger entries; explicit /jacb reserve overrides still
            -- apply after this exact set is built.
            useDetectedBurstTriggers = false,
            preserveSourceQueueOnly = true,
            -- Midnight 12.1 never invents Epidemic/Death Coil after the
            -- authoritative queue is exhausted. Empty is a valid safe result.
            fallbackActions = {},
            reserve = {
                63560,   -- Dark Transformation (base/compatibility)
                1233448, -- Dark Transformation (current override)
                42650,   -- Army of the Dead
            },
        },
    },
    -- Death and Decay is ground-targeted; M4 never guesses cursor placement.
    reserveExclusions = {
        43265, -- Death and Decay
    },
})
