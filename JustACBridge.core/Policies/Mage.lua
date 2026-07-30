local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Mage policy is intentionally maintained independently from other classes.
-- Frozen Orb and Ray of Frost are exposed only by the lossless action; the
-- preserve-burst action must skip them without changing JustAC's base queue.
Registry.RegisterClass("MAGE", {
    revision = 10,
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
            revision = 9,
            reserve = {
                12472, -- Icy Veins
            },
            -- 只允许无损版释放；保留爆发版在快速复用、队列扫描和高亮
            -- 回退中都必须跳过这两个技能。
            reserveExclusions = {
                84714,  -- Frozen Orb
                205021, -- Ray of Frost
            },
            -- Midnight 的冰川尖刺是冰霜箭的临时覆盖形态。移动过滤必须
            -- 在浮冰/Proc 快路径之前截住它，避免把覆盖高亮误当成瞬发。
            moveCastNever = {
                199786,  -- Glacial Spike (legacy compatibility)
                1236209, -- Glacial Spike (Midnight)
            },
            -- 这些技能的推荐高亮和浮冰都不足以证明瞬发；只有当前有效
            -- 法术形态被游戏 API 明确报告为零读条时才允许移动施放。
            moveCastInstantOnly = {
                116,    -- Frostbolt
                431044, -- Frostfire Bolt (replaces Frostbolt)
                468655, -- Frostfire Bolt proc/trigger form
                190356, -- Blizzard
            },
            -- 霜火冰在 20 码外使用“冰川尖刺 -> 冰风暴”会让套装火球
            -- 吃不到碎冰；仅在明确超距且已学霜火之箭时改为先冰风暴。
            rangeSequenceRules = {
                {
                    requiresSpell = 431044, -- Frostfire Bolt
                    beyond = 20,
                    defer = {
                        199786,  -- Glacial Spike (legacy compatibility)
                        1236209, -- Glacial Spike (Midnight)
                    },
                    prefer = { 44614 }, -- Flurry
                },
            },
        },
    },
})
