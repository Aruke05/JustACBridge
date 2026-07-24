local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Death Knight policy is intentionally maintained independently from Mage.
-- JustAC's detected Burst Trigger list is merged at runtime after these
-- compatibility defaults, so player/JustAC changes remain authoritative.
Registry.RegisterClass("DEATHKNIGHT", {
    revision = 1,
    specs = {
        [1] = {
            id = "blood",
            name = "鲜血",
            revision = 1,
            reserve = {
                49028, -- Dancing Rune Weapon
            },
        },
        [2] = {
            id = "frost",
            name = "冰霜",
            revision = 1,
            reserve = {
                51271,  -- Pillar of Frost
                152279, -- Breath of Sindragosa
                47568,  -- Empower Rune Weapon
                279302, -- Frostwyrm's Fury
                439843, -- Reaper's Mark
            },
        },
        [3] = {
            id = "unholy",
            name = "邪恶",
            revision = 1,
            reserve = {
                63560,  -- Dark Transformation
                42650,  -- Army of the Dead
                275699, -- Apocalypse
                207289, -- Unholy Assault
                49206,  -- Summon Gargoyle
                390279, -- Vile Contagion
            },
        },
    },
})
