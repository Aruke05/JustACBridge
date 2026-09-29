-- Independent Midnight 12.1 Frost Mage source (M5 only).
--
-- This is a priority source, not a patch over JustAC. It owns every branch
-- whose enemies/procs/talents/readiness are observable and returns the raw
-- queue at the first genuinely unknowable higher-priority predicate. Ray of
-- Frost is always allowed to finish; the SimC AoE clip optimization is not
-- reproducible from a secret tick clock and is intentionally omitted.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    FROSTBOLT = 116,
    CONE_OF_COLD = 120,
    ICE_LANCE = 30455,
    FLURRY = 44614,
    FROZEN_ORB = 84714,
    COMET_STORM = 153595,
    ICE_NOVA = 157997,
    BLIZZARD = 190356,
    GLACIAL_SPIKE = 199786,
    RAY_OF_FROST = 205021,
    FROSTFIRE_BOLT = 431044,

    FINGERS_OF_FROST = 44544,
    BRAIN_FREEZE = 190446,
    FREEZING_RAIN = 270232,
    FROSTFIRE_EMPOWERMENT = 431177,
    GLACIAL_SPIKE_READY = 1222865,
    FREEZING = 1221389,
    THERMAL_VOID = 1247730,
    RAPID_REFREEZING = 1310248,

    SPLINTERING_SORCERY = 443739,
    WINTERTIDE = 378406,
    FREEZING_RAIN_TALENT = 270233,
    CONE_OF_FROST = 1247090,
    FREEZING_WINDS = 1247554,
    HAND_OF_FROST_4 = 1263249,
}

local GCD = {
    [SPELL.FROSTBOLT] = true,
    [SPELL.CONE_OF_COLD] = true,
    [SPELL.ICE_LANCE] = true,
    [SPELL.FLURRY] = true,
    [SPELL.FROZEN_ORB] = true,
    [SPELL.COMET_STORM] = true,
    [SPELL.ICE_NOVA] = true,
    [SPELL.BLIZZARD] = true,
    [SPELL.GLACIAL_SPIKE] = true,
    [1236209] = true, -- Midnight Glacial Spike display form
    [SPELL.RAY_OF_FROST] = true,
    [SPELL.FROSTFIRE_BOLT] = true,
}

local context = Runtime.New("frostmage121", "MAGE", 3, GCD)
local opener = { ray = false, flurry = false, orb = false }

local function onEvent(_, event, spellID)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        opener.ray, opener.flurry, opener.orb = false, false, false
        return
    end
    if spellID == SPELL.RAY_OF_FROST then opener.ray = true end
    if spellID == SPELL.FLURRY then opener.flurry = true end
    if spellID == SPELL.FROZEN_ORB then opener.orb = true end
end

local function heroTree()
    if context:Known(SPELL.FROSTFIRE_BOLT) then return "frostfire" end
    if context:Known(SPELL.SPLINTERING_SORCERY) then return "spellslinger" end
    return nil
end

-- Proc glow is the combat-safe authority for action-changing procs. A true
-- aura is an additional proof path. When the glow is plainly false and aura
-- enumeration is secret, false is still valid: the action button is not in
-- its proc state.
local function procOrAura(spellID, auraID)
    local proc = context:Procced(spellID)
    if proc == true then return true end
    local aura = context:AuraUp("player", auraID)
    if aura ~= nil then return aura end
    if proc == false then return false end
    return nil
end

local function chooseIfReady(spellID, rule, detail, raw)
    local ready = context:Ready(spellID)
    if ready == true then return context:Choose(spellID, rule, detail, raw), true end
    return nil, ready
end

local function unknownReadiness(ready, reason, raw)
    if ready == nil then return context:Fallback(reason, raw) end
    return nil
end

local function glacialProc()
    local proc = context:Procced(SPELL.GLACIAL_SPIKE)
    if proc == true then return true end
    for _, auraID in ipairs({ SPELL.GLACIAL_SPIKE_READY, SPELL.RAPID_REFREEZING }) do
        local aura = context:AuraUp("player", auraID)
        if aura == true then return true end
        if aura == false then proc = proc == nil and false or proc end
    end
    if proc == false then return false end
    return nil
end

local function blizzardThreshold(hero)
    local rainTalent = context:Known(SPELL.FREEZING_RAIN_TALENT)
    local winds = context:Known(SPELL.FREEZING_WINDS)
    if hero == "frostfire" then return 8 - (winds and 3 or 0) - (rainTalent and 2 or 0) end
    return 7 - (winds and 2 or 0) - (rainTalent and 2 or 0)
end

local function selectFrostfire(raw, enemies, brain, fofOne, fofTwo, spike, thermal)
    local action, ready

    -- GS -> Comet is the S2 set loop. A live GS/4pc proc is the highest line.
    if spike then
        action, ready = chooseIfReady(SPELL.GLACIAL_SPIKE,
            "frostfire.glacial_spike", "ready-or-rapid-refreezing", raw)
        if action then return action end
        local fallback = unknownReadiness(ready, "glacial-spike-readiness-unknown", raw)
        if fallback then return fallback end
    end

    local previous2 = context:PreviousGCD(2)
    local spikeTwoGCDsAgo = previous2 == SPELL.GLACIAL_SPIKE or previous2 == 1236209
    local cometCondition = enemies <= 2
    if enemies > 2 and spikeTwoGCDsAgo then
        -- In AoE the current APL releases Comet two GCDs after Spike only
        -- outside Rapid Refreezing. That aura is observable; never collapse
        -- its unknown state into a guessed false.
        local rapid = context:AuraUp("player", SPELL.RAPID_REFREEZING)
        if rapid == nil then return context:Fallback("rapid-refreezing-state-unknown", raw) end
        if rapid then
            -- The remaining OR is exact time since the 4pc trigger (>1.5s),
            -- not merely whether its aura is currently present.
            return context:Fallback("rapid-refreezing-timing-delegated", raw)
        end
        cometCondition = true
    end
    if cometCondition then
        action, ready = chooseIfReady(SPELL.COMET_STORM,
            "frostfire.comet_storm", enemies <= 2 and "enemies<=2" or "two-gcd-after-spike", raw)
        if action then return action end
        local fallback = unknownReadiness(ready, "comet-readiness-unknown", raw)
        if fallback then return fallback end
    end

    if brain then
        if thermal == nil then return context:Fallback("thermal-void-state-unknown", raw) end
        if not thermal then
            action, ready = chooseIfReady(SPELL.FLURRY,
                "frostfire.brain_freeze", "thermal-void-down", raw)
            if action then return action end
            local fallback = unknownReadiness(ready, "flurry-readiness-unknown", raw)
            if fallback then return fallback end
        end
    end

    if fofTwo == nil then return context:Fallback("fingers-of-frost-two-state-unknown", raw) end
    if fofTwo then
        action, ready = chooseIfReady(SPELL.ICE_LANCE,
            "frostfire.ice_lance", "fingers-of-frost=2", raw)
        if action then return action end
        local fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
        if fallback then return fallback end
    end

    -- Without the final Hand of Frost node Ray is above Orb. We still protect
    -- the complete channel instead of applying SimC's unobservable tick clip.
    if not context:Known(SPELL.HAND_OF_FROST_4) then
        action, ready = chooseIfReady(SPELL.RAY_OF_FROST,
            "frostfire.ray_of_frost", "hand-of-frost-down+full-channel", raw)
        if action then return action end
        local fallback = unknownReadiness(ready, "ray-readiness-unknown", raw)
        if fallback then return fallback end
    end

    action, ready = chooseIfReady(SPELL.FROZEN_ORB,
        "frostfire.frozen_orb", "ready", raw)
    if action then return action end
    local fallback = unknownReadiness(ready, "orb-readiness-unknown", raw)
    if fallback then return fallback end

    local rain = procOrAura(SPELL.BLIZZARD, SPELL.FREEZING_RAIN)
    if rain == nil then return context:Fallback("freezing-rain-state-unknown", raw) end
    if enemies >= blizzardThreshold("frostfire") or (enemies >= 3 and rain) then
        action, ready = chooseIfReady(SPELL.BLIZZARD,
            "frostfire.blizzard", rain and "freezing-rain" or "enemy-threshold", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "blizzard-readiness-unknown", raw)
        if fallback then return fallback end
    end

    if fofOne then
        if thermal == nil then return context:Fallback("thermal-void-state-unknown", raw) end
        if thermal then
            action, ready = chooseIfReady(SPELL.ICE_LANCE,
                "frostfire.ice_lance", "fingers-of-frost+thermal-void", raw)
            if action then return action end
            fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
            if fallback then return fallback end
        end
    end

    local freezing12 = context:AuraAtLeast("target", SPELL.FREEZING, 12)
    if freezing12 == nil then return context:Fallback("freezing-12-state-unknown", raw) end
    if freezing12 then
        action, ready = chooseIfReady(SPELL.ICE_LANCE,
            "frostfire.ice_lance", "freezing>=12", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
        if fallback then return fallback end
    end

    action, ready = chooseIfReady(SPELL.FLURRY,
        "frostfire.flurry", "cooldown-ready", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "flurry-readiness-unknown", raw)
    if fallback then return fallback end

    if enemies >= 5 and context:Known(SPELL.CONE_OF_FROST) then
        local empowerment = context:AuraUp("player", SPELL.FROSTFIRE_EMPOWERMENT)
        if empowerment == nil then
            return context:Fallback("frostfire-empowerment-state-unknown", raw)
        end
        if not empowerment then
            local rayCharge = context:Ready(SPELL.RAY_OF_FROST)
            if rayCharge == nil then return context:Fallback("ray-charge-state-unknown", raw) end
            if rayCharge then
                for _, entry in ipairs({
                    { SPELL.ICE_NOVA, "ice_nova" },
                    { SPELL.CONE_OF_COLD, "cone_of_cold" },
                }) do
                    action, ready = chooseIfReady(entry[1],
                        "frostfire." .. entry[2], "enemies>=5+cone-of-frost", raw)
                    if action then return action end
                    fallback = unknownReadiness(ready, entry[2] .. "-readiness-unknown", raw)
                    if fallback then return fallback end
                end
            end
        end
    end

    -- Apex Frostfire holds Ray while its empowerment must be spent in AoE.
    local rayReady = context:Ready(SPELL.RAY_OF_FROST)
    if rayReady == nil then return context:Fallback("ray-readiness-unknown", raw) end
    if rayReady then
        if enemies <= 2 then
            return context:Choose(SPELL.RAY_OF_FROST,
                "frostfire.ray_of_frost", "enemies<=2+full-channel", raw)
        end
        local empowerment = context:AuraUp("player", SPELL.FROSTFIRE_EMPOWERMENT)
        if empowerment == nil then
            return context:Fallback("frostfire-empowerment-state-unknown", raw)
        end
        if not empowerment then
            return context:Choose(SPELL.RAY_OF_FROST,
                "frostfire.ray_of_frost", "empowerment-down+full-channel", raw)
        end
    end

    action, ready = chooseIfReady(SPELL.GLACIAL_SPIKE,
        "frostfire.glacial_spike", "terminal-resource-ready", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "glacial-spike-readiness-unknown", raw)
    if fallback then return fallback end

    action, ready = chooseIfReady(SPELL.FROSTBOLT,
        "frostfire.frostbolt", "terminal", raw)
    if action then return action end
    return context:Fallback(ready == nil and "frostbolt-readiness-unknown"
        or "no-frostfire-action", raw)
end

local function selectSpellslinger(raw, enemies, brain, fofOne, fofTwo, spike, thermal)
    local action, ready, fallback

    action, ready = chooseIfReady(SPELL.COMET_STORM,
        "spellslinger.comet_storm", "highest-normal-action", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "comet-readiness-unknown", raw)
    if fallback then return fallback end

    if brain then
        if thermal == nil then return context:Fallback("thermal-void-state-unknown", raw) end
        if not thermal then
            action, ready = chooseIfReady(SPELL.FLURRY,
                "spellslinger.brain_freeze", "thermal-void-down", raw)
            if action then return action end
            fallback = unknownReadiness(ready, "flurry-readiness-unknown", raw)
            if fallback then return fallback end
        end
    end

    if fofTwo == nil then return context:Fallback("fingers-of-frost-two-state-unknown", raw) end
    if fofTwo then
        action, ready = chooseIfReady(SPELL.ICE_LANCE,
            "spellslinger.ice_lance", "fingers-of-frost=2", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
        if fallback then return fallback end
    end

    action, ready = chooseIfReady(SPELL.FROZEN_ORB,
        "spellslinger.frozen_orb", "ready", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "orb-readiness-unknown", raw)
    if fallback then return fallback end

    if spike then
        action, ready = chooseIfReady(SPELL.GLACIAL_SPIKE,
            "spellslinger.glacial_spike", "ready-or-rapid-refreezing", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "glacial-spike-readiness-unknown", raw)
        if fallback then return fallback end
    end

    local rain = procOrAura(SPELL.BLIZZARD, SPELL.FREEZING_RAIN)
    if rain == nil then return context:Fallback("freezing-rain-state-unknown", raw) end
    local rainThreshold = 5 - (context:Known(SPELL.FREEZING_WINDS) and 2 or 0)
    if rain and enemies >= rainThreshold then
        action, ready = chooseIfReady(SPELL.BLIZZARD,
            "spellslinger.blizzard", "freezing-rain-threshold", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "blizzard-readiness-unknown", raw)
        if fallback then return fallback end
    end

    if fofOne then
        action, ready = chooseIfReady(SPELL.ICE_LANCE,
            "spellslinger.ice_lance", "fingers-of-frost", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
        if fallback then return fallback end
    end

    local freezing6 = context:AuraAtLeast("target", SPELL.FREEZING, 6)
    if freezing6 == nil then return context:Fallback("freezing-6-state-unknown", raw) end
    if freezing6 then
        action, ready = chooseIfReady(SPELL.ICE_LANCE,
            "spellslinger.ice_lance", "freezing>=6", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "ice-lance-readiness-unknown", raw)
        if fallback then return fallback end
    end

    local rayReady = context:Ready(SPELL.RAY_OF_FROST)
    if rayReady == nil then return context:Fallback("ray-readiness-unknown", raw) end
    if rayReady then
        if enemies >= 3 then
            return context:Choose(SPELL.RAY_OF_FROST,
                "spellslinger.ray_of_frost", "enemies>=3+full-channel", raw)
        end
        -- The other sufficient branch is icicles<=3. That counter is not a
        -- reliably observable class resource, so do not guess it.
        return context:Fallback("spellslinger-ray-icicle-count-unknown", raw)
    end

    action, ready = chooseIfReady(SPELL.FLURRY,
        "spellslinger.flurry", "cooldown-ready", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "flurry-readiness-unknown", raw)
    if fallback then return fallback end

    if enemies >= 4 and context:Known(SPELL.CONE_OF_FROST) then
        for _, entry in ipairs({
            { SPELL.ICE_NOVA, "ice_nova" },
            { SPELL.CONE_OF_COLD, "cone_of_cold" },
        }) do
            action, ready = chooseIfReady(entry[1],
                "spellslinger." .. entry[2], "enemies>=4+cone-of-frost", raw)
            if action then return action end
            fallback = unknownReadiness(ready, entry[2] .. "-readiness-unknown", raw)
            if fallback then return fallback end
        end
    end

    if enemies >= blizzardThreshold("spellslinger") then
        action, ready = chooseIfReady(SPELL.BLIZZARD,
            "spellslinger.blizzard", "enemy-threshold", raw)
        if action then return action end
        fallback = unknownReadiness(ready, "blizzard-readiness-unknown", raw)
        if fallback then return fallback end
    end

    action, ready = chooseIfReady(SPELL.GLACIAL_SPIKE,
        "spellslinger.glacial_spike", "terminal-resource-ready", raw)
    if action then return action end
    fallback = unknownReadiness(ready, "glacial-spike-readiness-unknown", raw)
    if fallback then return fallback end

    action, ready = chooseIfReady(SPELL.FROSTBOLT,
        "spellslinger.frostbolt", "terminal", raw)
    if action then return action end
    return context:Fallback(ready == nil and "frostbolt-readiness-unknown"
        or "no-spellslinger-action", raw)
end

local function selectQueue(raw)
    if not context:InScope() then return context:Fallback("outside-frost-mage-12.1", raw) end
    local hero = heroTree()
    if not hero then return context:Fallback("hero-tree-unknown", raw) end
    if not context:HasHostileTarget() then return context:Fallback("no-hostile-target", raw) end
    if type(raw[1]) == "number" and raw[1] < 0 then
        return context:Fallback("active-item-timing-delegated", raw)
    end

    if not context:InCombat() then
        local enemies = context:EnemyCount()
        if not enemies then return context:Fallback("precombat-enemy-count-unknown", raw) end
        if enemies >= blizzardThreshold(hero) then
            local action, ready = chooseIfReady(SPELL.BLIZZARD,
                "precombat.blizzard", "enemy-threshold", raw)
            if action then return action end
            if ready == nil then return context:Fallback("precombat-blizzard-readiness-unknown", raw) end
        end
        local action, ready = chooseIfReady(SPELL.GLACIAL_SPIKE,
            "precombat.glacial_spike", "resource-ready", raw)
        if action then return action end
        if ready == nil then return context:Fallback("precombat-spike-readiness-unknown", raw) end
        local action, ready = chooseIfReady(SPELL.FROSTBOLT,
            "precombat.frostbolt", hero, raw)
        if action then return action end
        return context:Fallback(ready == nil and "precombat-readiness-unknown"
            or "precombat-delegated", raw)
    end

    local enemies = context:EnemyCount()
    if not enemies then return context:Fallback("enemy-count-unknown", raw) end

    -- Current SimC line_cd=9999 opener. These flags advance only after the
    -- server confirms a cast, so holding M5 cannot skip a failed action.
    local openingOrder = hero == "frostfire"
        and {
            { SPELL.RAY_OF_FROST, "ray", true },
            { SPELL.FLURRY, "flurry", context:Known(SPELL.WINTERTIDE) },
            { SPELL.FROZEN_ORB, "orb", true },
        }
        or {
            { SPELL.FLURRY, "flurry", context:Known(SPELL.WINTERTIDE) },
            { SPELL.FROZEN_ORB, "orb", true },
            { SPELL.RAY_OF_FROST, "ray", true },
        }
    for _, entry in ipairs(openingOrder) do
        if entry[3] and not opener[entry[2]] then
            local ready = context:Ready(entry[1])
            if ready == true then
                return context:Choose(entry[1], "cooldowns.opening_" .. entry[2],
                    hero .. "+full-channel", raw)
            elseif ready == nil then
                return context:Fallback("opening-" .. entry[2] .. "-readiness-unknown", raw)
            end
        end
    end

    local rayCapped = context:AtMaxCharges(SPELL.RAY_OF_FROST)
    if rayCapped == nil then return context:Fallback("ray-charge-cap-state-unknown", raw) end
    if rayCapped then
        local ready = context:Ready(SPELL.RAY_OF_FROST)
        if ready == true then
            return context:Choose(SPELL.RAY_OF_FROST,
                "cooldowns.ray_of_frost", "charge-cap+full-channel", raw)
        elseif ready == nil then
            return context:Fallback("ray-readiness-unknown", raw)
        end
    end

    -- End-of-fight Comet is above the normal lists. In these two cases the
    -- normal list would not already cast it, so the fight-remains predicate
    -- cannot be treated as false.
    if hero == "frostfire" and enemies > 2 then
        local previous2 = context:PreviousGCD(2)
        local afterSpike = previous2 == SPELL.GLACIAL_SPIKE or previous2 == 1236209
        local cometReady = context:Ready(SPELL.COMET_STORM)
        if cometReady == nil then return context:Fallback("comet-readiness-unknown", raw) end
        if cometReady and not afterSpike then
            return context:Fallback("comet-end-of-fight-timing-delegated", raw)
        end
    end
    local brain = procOrAura(SPELL.FLURRY, SPELL.BRAIN_FREEZE)
    local fofOne = procOrAura(SPELL.ICE_LANCE, SPELL.FINGERS_OF_FROST)
    local fofTwo = context:AuraAtLeast("player", SPELL.FINGERS_OF_FROST, 2)
    local spike = glacialProc()
    local thermal = context:AuraUp("player", SPELL.THERMAL_VOID)
    if brain == nil then return context:Fallback("brain-freeze-state-unknown", raw) end
    if fofOne == nil then return context:Fallback("fingers-of-frost-state-unknown", raw) end
    if fofOne == false then fofTwo = false end
    if spike == nil then return context:Fallback("glacial-spike-state-unknown", raw) end

    if hero == "frostfire" then
        return selectFrostfire(raw, enemies, brain, fofOne, fofTwo, spike, thermal)
    end
    return selectSpellslinger(raw, enemies, brain, fofOne, fofTwo, spike, thermal)
end

local Source = { name = "冰法 12.1 自有循环（JustAC 兜底）" }

function Source.Initialize() return context:Initialize(onEvent) end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, opener = opener, selectQueue = selectQueue }
Registry.Register("frostmage121", Source)
