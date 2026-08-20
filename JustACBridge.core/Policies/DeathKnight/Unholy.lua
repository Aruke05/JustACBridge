local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("DEATHKNIGHT", 3, {
    id = "unholy",
    name = "邪恶",
    revision = 3,
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
        343294,  -- Soul Reaper
    },
    -- Death and Decay is ground-targeted; M4 never guesses cursor placement.
    reserveExclusions = {
        43265, -- Death and Decay
    },
})
