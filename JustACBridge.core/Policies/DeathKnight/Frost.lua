local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("DEATHKNIGHT", 2, {
    id = "frost",
    name = "冰霜",
    revision = 3,
    fallbackActions = {
        { spellID = 49184, requireProc = true, label = "白霜凛风冲击" },
        { spellID = 49184, label = "凛风冲击" },
    },
    -- Death Grip is encounter utility, never a rotational damage action.
    -- Filter stale queue/gap-closer injections from both M5 and M4.
    rotationExclusions = {
        49576, -- Death Grip
    },
    reserve = {
        51271,   -- Pillar of Frost
        152279,  -- Breath of Sindragosa
        1249658, -- Breath of Sindragosa (current override)
        47568,   -- Empower Rune Weapon
        279302,  -- Frostwyrm's Fury
        439843,  -- Reaper's Mark
    },
})
