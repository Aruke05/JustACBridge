local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Death Knight policy is intentionally maintained independently from Mage.
-- JustAC's detected Burst Trigger list is merged at runtime after these
-- compatibility defaults, so player/JustAC changes remain authoritative.
Registry.RegisterClass("DEATHKNIGHT", {
    revision = 3,
    groundEffects = {
        {
            id = "death-and-decay",
            name = "枯萎凋零",
            spells = {
                43265,  -- Death and Decay
                152280, -- Defile
            },
            duration = 10,
            suppressRepeat = true,
        },
    },
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
                1249658, -- Breath of Sindragosa (current override)
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
                1233448, -- Dark Transformation (current override)
                42650,  -- Army of the Dead
                275699, -- Apocalypse
                220143, -- Apocalypse (current spell ID)
                207289, -- Unholy Assault
                49206,  -- Summon Gargoyle
                390279, -- Vile Contagion
            },
        },
    },
})
