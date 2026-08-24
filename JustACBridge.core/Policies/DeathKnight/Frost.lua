local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

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
})
