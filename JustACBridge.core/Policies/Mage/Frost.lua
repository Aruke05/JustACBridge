local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 3, {
    id = "frost",
    name = "冰霜",
    revision = 14,
    fallbackActions = {
        { spellID = 30455, label = "冰枪术" },
    },
    -- Maintain the barrier only from its exact self aura. This also works
    -- with Glacial Bulwark charges because readiness is read from the live
    -- charge/cooldown API rather than inferred from the talent build.
    maintenanceBuffs = {
        {
            spellID = 11426, -- Ice Barrier
            auraID = 11426,
            lossless = true,
            preserve = true,
            reserveCharges = 1,
            label = "寒冰护体",
        },
    },
    reserve = {
        12472, -- Icy Veins
    },
    reserveExclusions = {
        84714,  -- Frozen Orb
        205021, -- Ray of Frost
        190356, -- Blizzard (ground cursor)
        120,    -- Cone of Cold (directional frontal)
    },
    -- 冰霜射线必须完整引导；即使引导期间收到移动事件，也不能让持续按住的
    -- M4/M5 在 GCD 结束时发送下一技能并提前截断。
    protectedChannels = {
        205021, -- Ray of Frost
    },
    -- Midnight 的冰川尖刺是冰霜箭的临时覆盖形态；移动时强制跳过。
    moveCastNever = {
        199786,  -- Glacial Spike (legacy compatibility)
        1236209, -- Glacial Spike (Midnight)
    },
    -- 只有当前有效法术形态被 API 明确报告为零读条时才允许移动施放。
    moveCastInstantOnly = {
        116,    -- Frostbolt
        431044, -- Frostfire Bolt (replaces Frostbolt)
        468655, -- Frostfire Bolt proc/trigger form
        190356, -- Blizzard
    },
    rangeSequenceRules = {
        {
            requiresSpell = 431044,
            beyond = 20,
            defer = { 199786, 1236209 },
            prefer = { 44614 }, -- Flurry
        },
    },
    versions = {
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 16,
            -- Icy Veins was removed in Midnight. Ray of Frost is the current
            -- main cooldown and must be held by M4; do not let a stale JustAC
            -- Burst Trigger re-add the removed spell to this exact ruleset.
            reserve = { 205021 },
            useDetectedBurstTriggers = false,
        },
    },
})
