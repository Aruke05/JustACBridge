-- Conservative Midnight 12.1 Survival source (M5 only).
--
-- Survival's exact priority depends on Tip of the Spear, Twin Fangs, Takedown
-- cooldown state, Wildfire Bomb recharge and hero-specific marks.  This source
-- implements only rows whose complete boolean expression is observable.  The
-- <one-GCD and <four-second recharge comparisons deliberately fall back unless
-- readiness/max-charge state itself proves the comparison.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    KILL_COMMAND = 259489,
    WILDFIRE_BOMB = 259495,
    RAPTOR_STRIKE = 186270,
    RAPTOR_SWIPE = 1262343,
    TAKEDOWN = 1250646,
    BOOMSTICK = 1261193,
    MOONLIGHT_CHAKRAM = 1264949,

    TIP_OF_THE_SPEAR = 260286,
    HOWL_OF_THE_PACK_LEADER_TALENT = 471876,
    HOWL_OF_THE_PACK_LEADER = 471878,
    TWIN_FANGS = 1272139,
    LETHAL_CALIBRATION = 1262409,
    SENTINELS_MARK = 1266960,
    SENTINEL = 1253599,
}

local GCD = {
    [SPELL.KILL_COMMAND] = true,
    [SPELL.WILDFIRE_BOMB] = true,
    [SPELL.RAPTOR_STRIKE] = true,
    [SPELL.RAPTOR_SWIPE] = true,
    [SPELL.TAKEDOWN] = true,
    [SPELL.BOOMSTICK] = true,
    [SPELL.MOONLIGHT_CHAKRAM] = true,
}

local ROTATION_HEAD = {}
for spellID in pairs(GCD) do ROTATION_HEAD[spellID] = true end

local context = Runtime.New("survivalhunter121", "HUNTER", 3, GCD)

local function ready(spellID, reason, raw)
    local value = context:Ready(spellID)
    if value == nil then return nil, context:Fallback(reason, raw) end
    return value
end

local function cooldown(spellID, reason, raw)
    local value = context:CallBoolean("IsSpellOnCooldown", spellID)
    if value == nil then return nil, context:Fallback(reason, raw) end
    return value
end

local function tipState(raw)
    local one = context:AuraAtLeast("player", SPELL.TIP_OF_THE_SPEAR, 1)
    local two = context:AuraAtLeast("player", SPELL.TIP_OF_THE_SPEAR, 2)
    if one == nil or two == nil then
        return nil, nil, context:Fallback("tip-of-the-spear-state-unknown", raw)
    end
    return one, two
end

local function chooseRaptor(rule, detail, raw)
    local raptorReady, failure = ready(SPELL.RAPTOR_STRIKE,
        "raptor-strike-readiness-unknown", raw)
    if failure then return failure end
    if raptorReady then
        local display = context:Display(SPELL.RAPTOR_STRIKE)
        -- Keep the learned base button in the queue. The JustAC adapter/core
        -- resolves its live Raptor Swipe override for binding and M4's
        -- effective-spell frontal exclusion.
        return context:Choose(SPELL.RAPTOR_STRIKE, rule,
            display == SPELL.RAPTOR_SWIPE and (detail .. "+raptor-swipe")
                or detail, raw)
    end
    return nil
end

local function selectPackSingle(raw, tipUp, tipTwo, twin)
    local killReady, failure = ready(SPELL.KILL_COMMAND,
        "kill-command-readiness-unknown", raw)
    if failure then return failure end

    local takedownReady
    takedownReady, failure = ready(SPELL.TAKEDOWN,
        "takedown-readiness-unknown", raw)
    if failure then return failure end

    if killReady and not tipTwo then
        -- SimC's first row depends on the internal howl_summon.ready state.
        -- The visible Howl aura is not proof of that driver state, so do not
        -- substitute it.  With no Twin Fangs and Takedown ready, however, the
        -- following KC row is also certainly true; both possible paths select
        -- the same action and therefore make Kill Command provable.
        if not twin and takedownReady then
            return context:Choose(SPELL.KILL_COMMAND,
                "pack_st.kill_command", "takedown-ready+tip<2+no-twin-fangs", raw)
        end
        -- Otherwise either howl_summon.ready or Takedown's sub-GCD cooldown
        -- comparison can still make a higher Kill Command row win.
        return context:Fallback(twin
            and "howl-summon-readiness-delegated"
            or "takedown-less-than-gcd-delegated", raw)
    end

    if takedownReady and ((tipUp and not twin) or (not tipUp and twin)) then
        return context:Choose(SPELL.TAKEDOWN,
            "pack_st.takedown", tipUp and "tip>0+no-twin-fangs"
                or "tip=0+twin-fangs", raw)
    end

    local bombReady
    bombReady, failure = ready(SPELL.WILDFIRE_BOMB,
        "wildfire-bomb-readiness-unknown", raw)
    if failure then return failure end
    if bombReady and tipUp then
        if not context:Known(SPELL.LETHAL_CALIBRATION) then
            return context:Choose(SPELL.WILDFIRE_BOMB,
                "pack_st.wildfire_bomb", "tip+no-lethal-calibration", raw)
        end
        local capped = context:AtMaxCharges(SPELL.WILDFIRE_BOMB)
        if capped == true then
            return context:Choose(SPELL.WILDFIRE_BOMB,
                "pack_st.wildfire_bomb", "tip+charges-capped", raw)
        end
        return context:Fallback(capped == nil
            and "wildfire-bomb-charge-state-unknown"
            or "wildfire-bomb-recharge<4+gcd-delegated", raw)
    end

    local boomReady
    boomReady, failure = ready(SPELL.BOOMSTICK,
        "boomstick-readiness-unknown", raw)
    if failure then return failure end
    if boomReady and tipUp then
        return context:Choose(SPELL.BOOMSTICK,
            "pack_st.boomstick", "tip-of-the-spear-up", raw)
    end

    if tipUp then
        local action = chooseRaptor("pack_st.raptor_strike", "tip-up", raw)
        if action then return action end
    else
        local display = context:Display(SPELL.RAPTOR_STRIKE)
        if display == nil then
            return context:Fallback("raptor-swipe-display-state-unknown", raw)
        end
        if display ~= SPELL.RAPTOR_SWIPE then
            local action = chooseRaptor("pack_st.raptor_strike",
                "raptor-swipe-down", raw)
            if action then return action end
        end
    end

    if bombReady and tipUp then
        return context:Choose(SPELL.WILDFIRE_BOMB,
            "pack_st.wildfire_bomb", "tip-terminal", raw)
    end

    local takedownOnCooldown
    takedownOnCooldown, failure = cooldown(SPELL.TAKEDOWN,
        "takedown-cooldown-state-unknown", raw)
    if failure then return failure end
    if killReady and takedownOnCooldown then
        return context:Choose(SPELL.KILL_COMMAND,
            "pack_st.kill_command", "takedown-on-cooldown", raw)
    end
    if takedownReady then
        return context:Choose(SPELL.TAKEDOWN,
            "pack_st.takedown", "terminal", raw)
    end
    return context:Fallback("no-pack-survival-single-target-action", raw)
end

local function selectSentinelSingle(raw, tipUp, tipTwo, twin)
    local killReady, failure = ready(SPELL.KILL_COMMAND,
        "kill-command-readiness-unknown", raw)
    if failure then return failure end
    local takedownReady
    takedownReady, failure = ready(SPELL.TAKEDOWN,
        "takedown-readiness-unknown", raw)
    if failure then return failure end
    local takedownOnCooldown
    takedownOnCooldown, failure = cooldown(SPELL.TAKEDOWN,
        "takedown-cooldown-state-unknown", raw)
    if failure then return failure end

    if killReady and not tipUp then
        if not twin or takedownOnCooldown then
            return context:Choose(SPELL.KILL_COMMAND,
                "sentinel_st.kill_command", not twin and "tip=0+no-twin-fangs"
                    or "tip=0+takedown-on-cooldown", raw)
        end
    end

    local boomReady
    boomReady, failure = ready(SPELL.BOOMSTICK,
        "boomstick-readiness-unknown", raw)
    if failure then return failure end
    if boomReady then
        return context:Choose(SPELL.BOOMSTICK,
            "sentinel_st.boomstick", "higher-row-false", raw)
    end

    local bombReady
    bombReady, failure = ready(SPELL.WILDFIRE_BOMB,
        "wildfire-bomb-readiness-unknown", raw)
    if failure then return failure end
    if bombReady and tipUp then
        local mark = context:AuraUp("target", SPELL.SENTINELS_MARK)
        local capped = context:AtMaxCharges(SPELL.WILDFIRE_BOMB)
        if mark == true or capped == true then
            return context:Choose(SPELL.WILDFIRE_BOMB,
                "sentinel_st.wildfire_bomb",
                mark == true and "tip+sentinels-mark" or "tip+charges-capped", raw)
        end
        if mark == nil or capped == nil then
            return context:Fallback("sentinel-bomb-state-unknown", raw)
        end
        -- A false max-charge bit does not prove full_recharge_time>=4.
        return context:Fallback("wildfire-bomb-recharge<4-delegated", raw)
    end

    if killReady and not tipTwo and not twin then
        if takedownReady then
            return context:Choose(SPELL.KILL_COMMAND,
                "sentinel_st.kill_command",
                "takedown-ready+tip<2+no-twin-fangs", raw)
        end
        return context:Fallback("takedown-less-than-gcd-delegated", raw)
    end

    if takedownReady and ((tipUp and not twin) or (not tipUp and twin)) then
        return context:Choose(SPELL.TAKEDOWN,
            "sentinel_st.takedown", tipUp and "tip>0+no-twin-fangs"
                or "tip=0+twin-fangs", raw)
    end

    local moonlightReady
    moonlightReady, failure = ready(SPELL.MOONLIGHT_CHAKRAM,
        "moonlight-chakram-readiness-unknown", raw)
    if failure then return failure end
    if moonlightReady then
        return context:Choose(SPELL.MOONLIGHT_CHAKRAM,
            "sentinel_st.moonlight_chakram", "ready", raw)
    end

    local raptor = chooseRaptor("sentinel_st.raptor_strike", "ready", raw)
    if raptor then return raptor end

    if killReady and takedownOnCooldown then
        return context:Choose(SPELL.KILL_COMMAND,
            "sentinel_st.kill_command", "takedown-on-cooldown", raw)
    end
    if bombReady then
        return context:Choose(SPELL.WILDFIRE_BOMB,
            "sentinel_st.wildfire_bomb", "terminal", raw)
    end
    if takedownReady then
        return context:Choose(SPELL.TAKEDOWN,
            "sentinel_st.takedown", "terminal", raw)
    end
    return context:Fallback("no-sentinel-survival-single-target-action", raw)
end

local function selectQueue(raw)
    if not context:InScope() then
        return context:Fallback("outside-survival-hunter-12.1", raw)
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
    if enemies >= 3 then
        -- Current cleave lists contain target_if Sentinel's Mark selection and
        -- frontal Raptor Swipe decisions. Preserve JustAC's target/order.
        return context:Fallback("survival-cleave-target-selection-delegated", raw)
    end

    if not context:Known(SPELL.TAKEDOWN) or not context:Known(SPELL.BOOMSTICK) then
        return context:Fallback("unsupported-survival-cooldown-build", raw)
    end

    local tipUp, tipTwo, failure = tipState(raw)
    if failure then return failure end
    local twin = context:Known(SPELL.TWIN_FANGS)
    if context:Known(SPELL.HOWL_OF_THE_PACK_LEADER_TALENT)
        or context:Known(SPELL.HOWL_OF_THE_PACK_LEADER) then
        return selectPackSingle(raw, tipUp, tipTwo, twin)
    end
    if context:Known(SPELL.SENTINEL) then
        return selectSentinelSingle(raw, tipUp, tipTwo, twin)
    end
    return context:Fallback("hero-tree-unknown", raw)
end

local Source = { name = "生存猎 12.1 可证明切片（JustAC 兜底）" }

function Source.Initialize() return context:Initialize() end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, selectQueue = selectQueue }
Registry.Register("survivalhunter121", Source)
