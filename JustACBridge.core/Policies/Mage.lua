local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Mage policy is intentionally maintained independently from other classes.
-- Frozen Orb and Meteor are not reserved: the referenced TWW S3 rotations use
-- them rotationally rather than holding them for Icy Veins/Combustion.
Registry.RegisterClass("MAGE", {
    revision = 3,
    -- These are class-wide movement exceptions.  Hardcasts made instant by a
    -- proc are detected live through JustAC's IsSpellProcced API.
    moveCastAlways = {
        2948, -- Scorch: has a cast bar but is natively castable while moving
    },
    moveCastBuffs = {
        108839, -- Ice Floes: permits Mage spells to be cast while moving
    },
    specs = {
        [1] = {
            id = "arcane",
            name = "奥术",
            revision = 2,
            reserve = {
                365350, -- Arcane Surge
                12051,  -- Evocation
                321507, -- Touch of the Magi
            },
            -- S3 奥法循环会在一个 GCD 后主动截断奥术飞弹。Bridge 保留
            -- 引导状态供 UI/导出使用，但只在 GCD 最后 120ms 开放按键。
            clipChannels = {
                5143, -- Arcane Missiles / Aether Attunement override
            },
        },
        [2] = {
            id = "fire",
            name = "火焰",
            revision = 1,
            reserve = {
                190319, -- Combustion
            },
        },
        [3] = {
            id = "frost",
            name = "冰霜",
            revision = 2,
            reserve = {
                12472, -- Icy Veins
            },
            -- 霜火冰在 20 码外使用“冰川尖刺 -> 冰风暴”会让套装火球
            -- 吃不到碎冰；仅在明确超距且已学霜火之箭时改为先冰风暴。
            rangeSequenceRules = {
                {
                    requiresSpell = 431044, -- Frostfire Bolt
                    beyond = 20,
                    defer = { 199786 }, -- Glacial Spike
                    prefer = { 44614 }, -- Flurry
                },
            },
        },
    },
})
