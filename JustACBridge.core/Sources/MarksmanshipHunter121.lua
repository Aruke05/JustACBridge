-- Conservative Midnight 12.1 Marksmanship source (M5 only).
--
-- Multi-target MM requires target_if scoring, Trick Shots duration, dungeon
-- pull timing and (for current tier) per-target Explosive Shot state. Those
-- values are not all trustworthy at runtime, so this source owns only the
-- single-target rows whose complete predicates can be proved. Rapid Fire is
-- never clipped here; its channel safety is handled by the MM policy.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    AIMED_SHOT = 19434,
    ARCANE_SHOT = 185358,
    MULTI_SHOT = 257620,
    RAPID_FIRE = 257044,
    STEADY_SHOT = 56641,
    TRUESHOT = 288613,
    VOLLEY = 260243,
    EXPLOSIVE_SHOT = 212431,
    BLACK_ARROW = 466930,
    WAILING_ARROW = 392060,
    KILL_SHOT = 53351,
    MOONLIGHT_CHAKRAM = 1264949,

    PRECISE_SHOTS = 260242,
    MOONLIGHT_CHAKRAM_OVERRIDE = 1264946,
    BLACK_ARROW_TALENT = 466932,
    SENTINEL = 1253599,
}

local GCD = {
    [SPELL.AIMED_SHOT] = true,
    [SPELL.ARCANE_SHOT] = true,
    [SPELL.MULTI_SHOT] = true,
    [SPELL.RAPID_FIRE] = true,
    [SPELL.STEADY_SHOT] = true,
    [SPELL.TRUESHOT] = true,
    [SPELL.VOLLEY] = true,
    [SPELL.EXPLOSIVE_SHOT] = true,
    [SPELL.BLACK_ARROW] = true,
    [SPELL.WAILING_ARROW] = true,
    [SPELL.KILL_SHOT] = true,
    [SPELL.MOONLIGHT_CHAKRAM] = true,
}

local ROTATION_HEAD = {}
for spellID in pairs(GCD) do ROTATION_HEAD[spellID] = true end

local context = Runtime.New("mmhunter121", "HUNTER", 2, GCD)

local function ready(spellID, reason, raw)
    local value = context:Ready(spellID)
    if value == nil then return nil, context:Fallback(reason, raw) end
    return value
end

local function preciseShots(raw)
    local precise = context:AuraUp("player", SPELL.PRECISE_SHOTS)
    if precise == nil then
        return nil, context:Fallback("precise-shots-state-unknown", raw)
    end
    return precise
end

local function selectDarkRangerSingle(raw)
    -- Dark Ranger spends Precise Shots with Black Arrow before every other
    -- specialization-list row on a single target.
    local precise, failure = preciseShots(raw)
    if failure then return failure end
    if precise then
        local blackReady
        blackReady, failure = ready(SPELL.BLACK_ARROW,
            "black-arrow-readiness-unknown", raw)
        if failure then return failure end
        if blackReady then
            return context:Choose(SPELL.BLACK_ARROW,
                "dark_ranger_st.black_arrow", "precise-shots-up", raw)
        end
    end

    local explosiveReady
    explosiveReady, failure = ready(SPELL.EXPLOSIVE_SHOT,
        "explosive-shot-readiness-unknown", raw)
    if failure then return failure end
    if explosiveReady then
        -- Tactical Reload/Lock and Load, Unstable Trigger and dungeon-route
        -- ordering decide whether Explosive Shot beats Rapid Fire.
        return context:Fallback("explosive-shot-branch-delegated", raw)
    end

    local volleyReady
    volleyReady, failure = ready(SPELL.VOLLEY,
        "volley-readiness-unknown", raw)
    if failure then return failure end
    if volleyReady then
        return context:Choose(SPELL.VOLLEY,
            "dark_ranger_st.volley", "higher-rows-unavailable", raw)
    end

    local aimedReady
    aimedReady, failure = ready(SPELL.AIMED_SHOT,
        "aimed-shot-readiness-unknown", raw)
    if failure then return failure end
    if aimedReady then
        local capped = context:AtMaxCharges(SPELL.AIMED_SHOT)
        if capped == true then
            return context:Choose(SPELL.AIMED_SHOT,
                "dark_ranger_st.aimed_shot", "charges-capped", raw)
        end
        local trueshotUp = context:AuraUp("player", SPELL.TRUESHOT)
        local blackReady = context:Ready(SPELL.BLACK_ARROW)
        if trueshotUp == true and not precise and blackReady == true then
            return context:Choose(SPELL.AIMED_SHOT,
                "dark_ranger_st.aimed_shot",
                "trueshot+precise-down+black-arrow-ready", raw)
        end
        -- Not-at-cap does not disprove full_recharge_time<gcd+cast_time.
        -- Likewise, any hidden aura/readiness input can satisfy the first OR.
        local reason = (capped == nil or trueshotUp == nil or blackReady == nil)
            and "dark-ranger-aimed-state-unknown"
            or "dark-ranger-aimed-recharge-window-delegated"
        return context:Fallback(reason, raw)
    end

    local trueshotReady
    trueshotReady, failure = ready(SPELL.TRUESHOT,
        "trueshot-readiness-unknown", raw)
    if failure then return failure end
    if trueshotReady then
        return context:Fallback("trueshot-encounter-timing-delegated", raw)
    end

    local rapidReady
    rapidReady, failure = ready(SPELL.RAPID_FIRE,
        "rapid-fire-readiness-unknown", raw)
    if failure then return failure end
    if rapidReady then
        return context:Choose(SPELL.RAPID_FIRE,
            "dark_ranger_st.rapid_fire", "higher-rows-unavailable", raw)
    end

    local wailingReady
    wailingReady, failure = ready(SPELL.WAILING_ARROW,
        "wailing-arrow-readiness-unknown", raw)
    if failure then return failure end
    if wailingReady then
        return context:Choose(SPELL.WAILING_ARROW,
            "dark_ranger_st.wailing_arrow", "higher-rows-unavailable", raw)
    end

    if precise then
        local arcaneReady
        arcaneReady, failure = ready(SPELL.ARCANE_SHOT,
            "arcane-shot-readiness-unknown", raw)
        if failure then return failure end
        if arcaneReady then
            return context:Choose(SPELL.ARCANE_SHOT,
                "dark_ranger_st.arcane_shot", "precise-shots-up", raw)
        end
    end

    -- Aimed Shot was already proved unavailable above, so the unconditional
    -- later Aimed row cannot win here.
    local blackReady
    blackReady, failure = ready(SPELL.BLACK_ARROW,
        "black-arrow-readiness-unknown", raw)
    if failure then return failure end
    if blackReady then
        return context:Choose(SPELL.BLACK_ARROW,
            "dark_ranger_st.black_arrow", "terminal", raw)
    end

    local steadyReady
    steadyReady, failure = ready(SPELL.STEADY_SHOT,
        "steady-shot-readiness-unknown", raw)
    if failure then return failure end
    if steadyReady then
        return context:Choose(SPELL.STEADY_SHOT,
            "dark_ranger_st.steady_shot", "terminal", raw)
    end
    return context:Fallback("no-dark-ranger-single-target-action", raw)
end

local function moonlightExpiryReady(raw)
    local aura = context:AuraUp("player", SPELL.MOONLIGHT_CHAKRAM_OVERRIDE)
    if aura == false then return true end -- absent means SimC remains=0
    if aura == nil then
        return nil, context:Fallback("moonlight-chakram-aura-state-unknown", raw)
    end
    local below = context:PlayerAuraRemainsBelow(
        SPELL.MOONLIGHT_CHAKRAM_OVERRIDE, 5)
    if below == nil then
        return nil, context:Fallback("moonlight-chakram-remains-unknown", raw)
    end
    return below
end

local function selectSentinelSingle(raw)
    local explosiveReady, failure = ready(SPELL.EXPLOSIVE_SHOT,
        "explosive-shot-readiness-unknown", raw)
    if failure then return failure end
    if explosiveReady then
        return context:Fallback("explosive-shot-branch-delegated", raw)
    end

    local volleyReady
    volleyReady, failure = ready(SPELL.VOLLEY,
        "volley-readiness-unknown", raw)
    if failure then return failure end
    if volleyReady then
        return context:Choose(SPELL.VOLLEY,
            "sentinel_st.volley", "higher-rows-unavailable", raw)
    end

    local trueshotReady
    trueshotReady, failure = ready(SPELL.TRUESHOT,
        "trueshot-readiness-unknown", raw)
    if failure then return failure end
    if trueshotReady then
        return context:Fallback("trueshot-encounter-timing-delegated", raw)
    end

    local moonlightReady
    moonlightReady, failure = ready(SPELL.MOONLIGHT_CHAKRAM,
        "moonlight-chakram-readiness-unknown", raw)
    if failure then return failure end
    if moonlightReady then
        local expiryReady
        expiryReady, failure = moonlightExpiryReady(raw)
        if failure then return failure end
        if expiryReady then
            return context:Choose(SPELL.MOONLIGHT_CHAKRAM,
                "sentinel_st.moonlight_chakram", "override-remains<5", raw)
        end
    end

    local rapidReady
    rapidReady, failure = ready(SPELL.RAPID_FIRE,
        "rapid-fire-readiness-unknown", raw)
    if failure then return failure end
    if rapidReady then
        return context:Choose(SPELL.RAPID_FIRE,
            "sentinel_st.rapid_fire", "higher-rows-unavailable", raw)
    end

    local precise
    precise, failure = preciseShots(raw)
    if failure then return failure end
    if precise then
        local killReady
        killReady, failure = ready(SPELL.KILL_SHOT,
            "kill-shot-readiness-unknown", raw)
        if failure then return failure end
        if killReady then
            return context:Choose(SPELL.KILL_SHOT,
                "sentinel_st.kill_shot", "precise-shots-up", raw)
        end

        local arcaneReady
        arcaneReady, failure = ready(SPELL.ARCANE_SHOT,
            "arcane-shot-readiness-unknown", raw)
        if failure then return failure end
        if arcaneReady then
            return context:Choose(SPELL.ARCANE_SHOT,
                "sentinel_st.arcane_shot", "precise-shots-up", raw)
        end
    end

    local aimedReady
    aimedReady, failure = ready(SPELL.AIMED_SHOT,
        "aimed-shot-readiness-unknown", raw)
    if failure then return failure end
    if aimedReady then
        return context:Choose(SPELL.AIMED_SHOT,
            "sentinel_st.aimed_shot", "terminal-primary", raw)
    end

    if moonlightReady then
        return context:Choose(SPELL.MOONLIGHT_CHAKRAM,
            "sentinel_st.moonlight_chakram", "terminal", raw)
    end

    local steadyReady
    steadyReady, failure = ready(SPELL.STEADY_SHOT,
        "steady-shot-readiness-unknown", raw)
    if failure then return failure end
    if steadyReady then
        return context:Choose(SPELL.STEADY_SHOT,
            "sentinel_st.steady_shot", "terminal", raw)
    end
    return context:Fallback("no-sentinel-single-target-action", raw)
end

local function selectQueue(raw)
    if not context:InScope() then
        return context:Fallback("outside-mm-hunter-12.1", raw)
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
    if enemies ~= 1 then
        return context:Fallback("multi-target-target-selection-delegated", raw)
    end

    if context:Known(SPELL.BLACK_ARROW_TALENT)
        or context:Known(SPELL.BLACK_ARROW) then
        return selectDarkRangerSingle(raw)
    end
    if context:Known(SPELL.SENTINEL)
        or context:Known(SPELL.MOONLIGHT_CHAKRAM)
        or context:Known(SPELL.MOONLIGHT_CHAKRAM_OVERRIDE) then
        return selectSentinelSingle(raw)
    end
    return context:Fallback("hero-tree-unknown", raw)
end

local Source = { name = "射击猎 12.1 可证明切片（JustAC 兜底）" }

function Source.Initialize() return context:Initialize() end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, selectQueue = selectQueue }
Registry.Register("mmhunter121", Source)
