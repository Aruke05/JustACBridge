local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("DEATHKNIGHT", 2, {
    id = "frost",
    name = "冰霜",
    revision = 8,
    fallbackActions = {
        { spellID = 49184, requireProc = true, label = "白霜凛风冲击" },
        { spellID = 49184, label = "凛风冲击" },
    },
    reserve = {
        51271,   -- Pillar of Frost
        152279,  -- Breath of Sindragosa
        1249658, -- Breath of Sindragosa (current override)
        47568,   -- Empower Rune Weapon
        279302,  -- Frostwyrm's Fury
        439843,  -- Reaper's Mark
        46585,   -- Raise Dead
    },
    -- Directional frontal movement is left to M5/manual facing.
    reserveExclusions = {
        194913, -- Glacial Advance
        207230, -- Frostscythe
    },
})
