local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

-- These helpers deliberately do not use JustAC's fail-open usability/charge
-- wrappers or its memoized percentage power predicate. Missing/secret evidence
-- must leave the current source action alone, never create a new priority.
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
    if visible(amount, "number") and visible(maximum, "number")
        and maximum >= 60 and maximum < math.huge
        and amount >= 0 and amount <= maximum then return amount, maximum end
end

local function breathReady(spellID)
    local amount = power()
    if not amount then return nil end
    if amount < 60 then return false end
    local usable = read(C_Spell and C_Spell.IsSpellUsable, spellID)
    if not visible(usable, "boolean") then return nil end
    if not usable then return false end
    return cooldownReady(spellID)
end

-- Once attempted, never inject a second ERW off the same stale charge/RP
-- snapshot. Only an observed Breath cooldown re-arms this optional preparation;
-- changing targets or a missing/secret frame cannot resurrect it. No resource
-- is credited on success: ERW's projectile may not have reached the target yet.
local preparationSpent = false
local function observePreparationCast(event, spellID)
    if spellID == 47568 and (event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
        or event == "UNIT_SPELLCAST_INTERRUPTED") then preparationSpent = true end
end

local function prepareBurst(selectedSpellID, canUse)
    local breathCDReady = cooldownReady(1249658)
    if breathCDReady == false then preparationSpent = false end
    if preparationSpent or breathCDReady ~= true
        or (selectedSpellID ~= 51271 and selectedSpellID ~= 1249658) then return nil end
    if selectedSpellID == 51271 and cooldownReady(51271) ~= true then return nil end
    if not canUse(1249658) or not canUse(47568) then return nil end
    local amount, maximum = power()
    if not amount or amount + 40 > maximum then return nil end
    local usable, noPower = read(C_Spell and C_Spell.IsSpellUsable, 1249658)
    if not visible(usable, "boolean") or (not usable
        and not (amount < 60 and visible(noPower, "boolean") and noPower)) then return nil end
    local charges = read(C_Spell and C_Spell.GetSpellCharges, 47568)
    if not visible(charges, "table") then return nil end
    local current, maxCharges = charges.currentCharges, charges.maxCharges
    if not visible(current, "number") or not visible(maxCharges, "number")
        or maxCharges ~= 2 or (current ~= 1 and current ~= 2) then return nil end
    if current ~= 2 and amount >= 60 then return nil end
    local erwUsable = read(C_Spell and C_Spell.IsSpellUsable, 47568)
    if not visible(erwUsable, "boolean") or not erwUsable then return nil end
    -- Only the no-KM case is proven here. Do not steal a proc-consumption GCD
    -- or assume Killing Streak's talent-dependent stack budget.
    local secretAuras = read(C_Secrets and C_Secrets.ShouldAurasBeSecret)
    if not visible(secretAuras, "boolean") or secretAuras then return nil end
    if not (C_UnitAuras and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function") then return nil end
    local auraOK, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 51124)
    if not auraOK or (issecretvalue and issecretvalue(aura)) or aura ~= nil then return nil end
    return 47568
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
            revision = 18,
            prepareLossless = prepareBurst,
            observePlayerSpellcast = observePreparationCast,
            -- This is a bounded missing-action repair, not an owned Frost APL.
            -- Only a real Pillar success opens the Breath follow-up. A small
            -- Pillar window never waits for Breath's 90-second cooldown.
            addCastFollowups = {
                {
                    spellID = 1249658,
                    triggerSpells = { 51271 },
                    withinSeconds = 4,
                    lossless = true,
                    preserve = false,
                    targetBound = true,
                    requiresCombat = true,
                    readyPredicate = breathReady,
                    cancelOnUnusable = true,
                    cancelOnFailure = true,
                    cancelSpells = { 152279, 1249658, 279302, 1265384 },
                    label = "冰霜之柱后补冰龙吐息",
                },
            },
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
