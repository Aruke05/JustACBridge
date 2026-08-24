local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

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
            revision = 5,
            -- Midnight 12.1 has only two policy-owned burst cooldowns:
            -- Army and Dark Transformation. Putrefy is a charge-based
            -- rotational action and must remain owned by JustAC. Ignore stale
            -- Burst Trigger entries; explicit /jacb reserve overrides still
            -- apply after this exact set is built.
            useDetectedBurstTriggers = false,
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
