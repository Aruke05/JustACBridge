-- Conservative Midnight 12.1 Beast Mastery source (M5 only).
--
-- The current BM APL contains charge-recharge comparisons, Apex pet state and
-- target_if clauses that are not all exposed as plain runtime values.  This
-- source owns only a proved prefix: Bestial Wrath preparation, Beast Cleave
-- refresh after Bestial Wrath, charge-cap prevention and visible Cobra Fang
-- spends.  Every unreadable or incomplete branch returns the untouched JustAC
-- queue.  M4 is always the raw queue and is filtered only by the policy/core.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    BARBED_SHOT = 217200,
    BESTIAL_WRATH = 19574,
    KILL_COMMAND = 34026,
    COBRA_SHOT = 193455,
    WILD_THRASH = 1264359,
    BLACK_ARROW = 466930,
    WAILING_ARROW = 392060,

    BEAST_CLEAVE_TALENT = 115939,
    BEAST_CLEAVE = 268877,
    COBRA_FANG = 1299389,
    HOWL_OF_THE_PACK_LEADER_TALENT = 471876,
    HOWL_OF_THE_PACK_LEADER = 471878,
    BLACK_ARROW_TALENT = 466932,
}

local GCD = {
    [SPELL.BARBED_SHOT] = true,
    [SPELL.BESTIAL_WRATH] = true,
    [SPELL.KILL_COMMAND] = true,
    [SPELL.COBRA_SHOT] = true,
    [SPELL.WILD_THRASH] = true,
    [SPELL.BLACK_ARROW] = true,
    [SPELL.WAILING_ARROW] = true,
}

local ROTATION_HEAD = {}
for spellID in pairs(GCD) do ROTATION_HEAD[spellID] = true end

local context = Runtime.New("bmhunter121", "HUNTER", 1, GCD)

local function ready(spellID, reason, raw)
    local value = context:Ready(spellID)
    if value == nil then return nil, context:Fallback(reason, raw) end
    return value
end

local function selectPackSingle(raw, enemies)
    local barbedReady, failure = ready(SPELL.BARBED_SHOT,
        "barbed-shot-readiness-unknown", raw)
    if failure then return failure end
    local wrathReady
    wrathReady, failure = ready(SPELL.BESTIAL_WRATH,
        "bestial-wrath-readiness-unknown", raw)
    if failure then return failure end

    -- SimC row 1 is Barbed Shot when BW remains < one GCD or Barbed reaches
    -- full recharge. A ready BW proves the first predicate without reading a
    -- secret duration; a full-charge boolean proves the second.
    if wrathReady then
        if barbedReady then
            return context:Choose(SPELL.BARBED_SHOT,
                "pack_st.barbed_shot", "bestial-wrath-ready", raw)
        end
        return context:Choose(SPELL.BESTIAL_WRATH,
            "pack_st.bestial_wrath", "barbed-shot-unavailable", raw)
    end
    if barbedReady then
        local capped = context:AtMaxCharges(SPELL.BARBED_SHOT)
        if capped == true then
            return context:Choose(SPELL.BARBED_SHOT,
                "pack_st.barbed_shot", "charges-capped", raw)
        end
        -- false only says the spell is not exactly capped; it cannot disprove
        -- full_recharge_time<gcd or BW having a fraction of a GCD remaining.
        return context:Fallback(capped == nil
            and "barbed-shot-charge-state-unknown"
            or "barbed-shot-recharge-window-delegated", raw)
    end

    if enemies > 1 then
        local thrashReady
        thrashReady, failure = ready(SPELL.WILD_THRASH,
            "wild-thrash-readiness-unknown", raw)
        if failure then return failure end
        if thrashReady then
            return context:Choose(SPELL.WILD_THRASH,
                "pack_st.wild_thrash", "active-enemies>1", raw)
        end
    end

    local killReady
    killReady, failure = ready(SPELL.KILL_COMMAND,
        "kill-command-readiness-unknown", raw)
    if failure then return failure end
    if killReady then
        -- Howl summon timing, Nature's Ally and the third Apex-pet state form
        -- one OR expression. None may be approximated from a simple glow.
        return context:Fallback("pack-st-kill-command-predicates-delegated", raw)
    end

    local cobraReady
    cobraReady, failure = ready(SPELL.COBRA_SHOT,
        "cobra-shot-readiness-unknown", raw)
    if failure then return failure end
    if cobraReady then
        local fangMax = context:AuraAtLeast("player", SPELL.COBRA_FANG, 4)
        if fangMax == true then
            return context:Choose(SPELL.COBRA_SHOT,
                "pack_st.cobra_shot", "cobra-fang=4", raw)
        elseif fangMax == nil then
            return context:Fallback("cobra-fang-stack-state-unknown", raw)
        end
    end

    -- The terminal Cobra row requires BW remaining > one GCD. A plain
    -- on-cooldown bit cannot prove that duration threshold.
    return context:Fallback("pack-st-terminal-timing-delegated", raw)
end

local function selectPackCleave(raw, beastCleaveKnown)
    local thrashReady, failure = ready(SPELL.WILD_THRASH,
        "wild-thrash-readiness-unknown", raw)
    if failure then return failure end
    local cleaveUp
    if beastCleaveKnown then
        cleaveUp = context:AuraUp("player", SPELL.BEAST_CLEAVE)
    end

    if thrashReady and beastCleaveKnown then
        if context:PreviousGCD(1) == SPELL.BESTIAL_WRATH or cleaveUp == false then
            return context:Choose(SPELL.WILD_THRASH,
                "pack_cleave.wild_thrash",
                context:PreviousGCD(1) == SPELL.BESTIAL_WRATH
                    and "previous-gcd=bestial-wrath" or "beast-cleave-down", raw)
        elseif cleaveUp == nil then
            return context:Fallback("beast-cleave-state-unknown", raw)
        end
    end

    local barbedReady
    barbedReady, failure = ready(SPELL.BARBED_SHOT,
        "barbed-shot-readiness-unknown", raw)
    if failure then return failure end
    if barbedReady then
        local capped = context:AtMaxCharges(SPELL.BARBED_SHOT)
        if capped == true then
            return context:Choose(SPELL.BARBED_SHOT,
                "pack_cleave.barbed_shot", "charges-capped", raw)
        end
        return context:Fallback(capped == nil
            and "barbed-shot-charge-state-unknown"
            or "barbed-shot-recharge-window-delegated", raw)
    end

    local wrathReady
    wrathReady, failure = ready(SPELL.BESTIAL_WRATH,
        "bestial-wrath-readiness-unknown", raw)
    if failure then return failure end
    if wrathReady then
        if not beastCleaveKnown or not context:Known(SPELL.WILD_THRASH)
            or cleaveUp == true then
            return context:Choose(SPELL.BESTIAL_WRATH,
                "pack_cleave.bestial_wrath",
                not beastCleaveKnown and "beast-cleave-not-talented"
                    or (cleaveUp and "beast-cleave-up" or "wild-thrash-not-known"),
                raw)
        elseif cleaveUp == nil then
            return context:Fallback("beast-cleave-state-unknown", raw)
        end
    end

    if thrashReady then
        if not beastCleaveKnown then
            return context:Choose(SPELL.WILD_THRASH,
                "pack_cleave.wild_thrash", "beast-cleave-not-talented", raw)
        end
        -- The remaining branch compares BW cooldown against Beast Cleave
        -- duration; neither side may be replaced by an on/off bit.
        return context:Fallback("wild-thrash-duration-comparison-delegated", raw)
    end

    local killReady
    killReady, failure = ready(SPELL.KILL_COMMAND,
        "kill-command-readiness-unknown", raw)
    if failure then return failure end
    if killReady then
        return context:Fallback("pack-cleave-kill-command-predicates-delegated", raw)
    end

    local cobraReady
    cobraReady, failure = ready(SPELL.COBRA_SHOT,
        "cobra-shot-readiness-unknown", raw)
    if failure then return failure end
    if cobraReady and beastCleaveKnown then
        local fang = context:AuraUp("player", SPELL.COBRA_FANG)
        if fang == true and cleaveUp == true then
            return context:Choose(SPELL.COBRA_SHOT,
                "pack_cleave.cobra_shot", "cobra-fang+beast-cleave", raw)
        elseif fang == nil or cleaveUp == nil then
            return context:Fallback("cleave-cobra-aura-state-unknown", raw)
        end
    end

    return context:Fallback("pack-cleave-terminal-timing-delegated", raw)
end

local function selectQueue(raw)
    if not context:InScope() then
        return context:Fallback("outside-bm-hunter-12.1", raw)
    end
    if not context:InCombat() or not context:HasHostileTarget() then
        return context:Fallback("precombat-or-no-target", raw)
    end
    if type(raw[1]) == "number" and raw[1] < 0 then
        return context:Fallback("active-item-timing-delegated", raw)
    end
    if type(raw[1]) == "number" and raw[1] > 0
        and not ROTATION_HEAD[raw[1]] then
        return context:Fallback("non-rotation-head-delegated", raw)
    end

    local enemies = context:EnemyCount()
    if not enemies or enemies < 1 then
        return context:Fallback("enemy-count-unknown", raw)
    end

    if context:Known(SPELL.BLACK_ARROW_TALENT)
        or context:Known(SPELL.BLACK_ARROW) then
        -- Withering Fire duration, Kill Command recharge, Wailing execute time
        -- and target_if state are not all available as plain values.
        return context:Fallback("dark-ranger-priority-delegated", raw)
    end
    if not context:Known(SPELL.HOWL_OF_THE_PACK_LEADER_TALENT)
        and not context:Known(SPELL.HOWL_OF_THE_PACK_LEADER) then
        return context:Fallback("hero-tree-unknown", raw)
    end

    local beastCleaveKnown = context:Known(SPELL.BEAST_CLEAVE_TALENT)
    local cleave = enemies > 2 or beastCleaveKnown and enemies > 1
    if cleave then return selectPackCleave(raw, beastCleaveKnown) end
    return selectPackSingle(raw, enemies)
end

local Source = { name = "兽王猎 12.1 可证明切片（JustAC 兜底）" }

function Source.Initialize() return context:Initialize() end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, selectQueue = selectQueue }
Registry.Register("bmhunter121", Source)
