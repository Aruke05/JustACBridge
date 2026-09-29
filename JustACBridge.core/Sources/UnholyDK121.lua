-- Independent Midnight 12.1 Unholy Death Knight source (M5 only).
--
-- It owns the observable parts of the current priority list. Predicates that
-- depend on add/fight remains, pet lifetime, exact cooldown remains or hidden
-- aura timers return the untouched JustAC queue before any lower action is
-- selected. M4 is always the raw queue and its 12.1 policy precisely reserves
-- Army of the Dead and Dark Transformation; rotational Putrefy stays in queue.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    DEATH_AND_DECAY = 43265,
    DEATH_COIL = 47541,
    SCOURGE_STRIKE = 55090,
    OUTBREAK = 77575,
    FESTERING_STRIKE = 85948,
    EPIDEMIC = 207317,
    SOUL_REAPER = 343294,
    ARMY_OF_THE_DEAD = 42650,
    DARK_TRANSFORMATION = 1233448,
    PUTREFY = 1247378,
    FESTERING_SCYTHE = 458128,

    DARK_TRANSFORMATION_BUFF = 1235391,
    SUDDEN_DOOM = 81340,
    LESSER_GHOUL_READY = 1254252,
    FORBIDDEN_KNOWLEDGE = 1242223,
    FESTERING_SCYTHE_BUFF = 458123,
    FESTERING_SCYTHE_TRACKER = 1241077,
    CYCLE_OF_DEATH = 1290864,
    BLIGHTFALL_BUFF = 1271967,
    BLIGHTED = 1271199,
    DREAD_PLAGUE = 1240996,
    VIRULENT_PLAGUE = 191587,
    SOUL_REAPER_DEBUFF = 1241521,
    VAMPIRIC_STRIKE_BUFF = 433899,
    ESSENCE_OF_BLOOD_QUEEN = 433925,
    SUMMON_GARGOYLE = 49206,
}

local GCD = {
    [SPELL.DEATH_AND_DECAY] = true,
    [SPELL.DEATH_COIL] = true,
    [SPELL.SCOURGE_STRIKE] = true,
    [SPELL.OUTBREAK] = true,
    [SPELL.FESTERING_STRIKE] = true,
    [SPELL.EPIDEMIC] = true,
    [SPELL.SOUL_REAPER] = true,
    [SPELL.ARMY_OF_THE_DEAD] = true,
    [SPELL.DARK_TRANSFORMATION] = true,
    [SPELL.PUTREFY] = true,
    [SPELL.FESTERING_SCYTHE] = true,
}

local context = Runtime.New("unholydk121", "DEATHKNIGHT", 3, GCD)
local opener = { scytheCastAt = nil }

local function now()
    return GetTime and GetTime() or 0
end

local function hasRecentScytheCast()
    local castAt = opener.scytheCastAt
    if type(castAt) ~= "number" then return false end
    local age = now() - castAt
    -- This is only a one-refresh bridge while the authoritative tracker aura
    -- propagates. It must never become a fight-long substitute for that aura.
    return age >= 0 and age <= 2
end

local function onEvent(_, event, spellID)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        opener.scytheCastAt = nil
    elseif spellID == SPELL.FESTERING_SCYTHE then
        opener.scytheCastAt = now()
    elseif spellID == SPELL.ARMY_OF_THE_DEAD then
        opener.scytheCastAt = nil
    end
end

local function procOrAura(spellID, auraID)
    local proc = context:Procced(spellID)
    if proc == true then return true end
    local aura = context:AuraUp("player", auraID)
    if aura ~= nil then return aura end
    if proc == false then return false end
    return nil
end

local function readyChoice(spellID, rule, detail, raw)
    local ready = context:Ready(spellID)
    if ready == true then return context:Choose(spellID, rule, detail, raw) end
    return nil, ready
end

local function chooseRunicSpender(raw, enemies, forbidden, reason)
    -- Current SimC variable.epidemic_prio: 4+ without Forbidden Knowledge,
    -- 6+ while it is active.
    local threshold = forbidden and 6 or 4
    local spellID = enemies >= threshold and SPELL.EPIDEMIC or SPELL.DEATH_COIL
    local action, ready = readyChoice(spellID, "runic_power.spender",
        ("%s forbidden=%s enemies=%d threshold=%d")
            :format(reason, tostring(forbidden), enemies, threshold), raw)
    if action then return action end
    if ready == nil then return context:Fallback("runic-spender-readiness-unknown", raw) end
    return nil
end

-- Return true/false only when variable.spending_rp is completely proven.
-- Gargoyle activity has a delayed spawn and is not exposed as a player aura;
-- it is therefore delegated instead of inferred from an Army timestamp.
local function spendingRunicPower(runes, sudden, forbidden, raw)
    if runes < 2 or sudden then return true end
    if not forbidden then return false end
    if runes < 3 then return true end

    local essenceTwo = context:AuraAtLeast("player", SPELL.ESSENCE_OF_BLOOD_QUEEN, 2)
    if essenceTwo == true then return true end
    if essenceTwo == nil then
        return nil, context:Fallback("essence-stack-state-unknown", raw)
    end
    if context:Known(SPELL.SUMMON_GARGOYLE) then
        return nil, context:Fallback("gargoyle-active-state-unknown", raw)
    end
    return false
end

local function festeringScytheUrgent(raw)
    if not context:Known(SPELL.FESTERING_SCYTHE) then return false end
    local scythe = context:AuraUp("player", SPELL.FESTERING_SCYTHE_BUFF)
    local tracker = context:AuraUp("player", SPELL.FESTERING_SCYTHE_TRACKER)
    if scythe == nil or tracker == nil then
        return nil, context:Fallback("festering-scythe-timer-state-unknown", raw)
    end

    if tracker == false then return true end -- absent aura has zero remains
    local trackerLow = context:PlayerAuraRemainsBelow(SPELL.FESTERING_SCYTHE_TRACKER, 3)
    if trackerLow == nil then
        return nil, context:Fallback("festering-scythe-tracker-remains-unknown", raw)
    end
    if trackerLow then return true end
    if scythe == false then return false end
    local scytheLow = context:PlayerAuraRemainsBelow(SPELL.FESTERING_SCYTHE_BUFF, 3)
    if scytheLow == nil then
        return nil, context:Fallback("festering-scythe-remains-unknown", raw)
    end
    return scytheLow
end

local function selectQueue(raw)
    if not context:InScope() then return context:Fallback("outside-unholy-dk-12.1", raw) end
    if not context:InCombat() or not context:HasHostileTarget() then
        return context:Fallback("precombat-or-no-target", raw)
    end
    if type(raw[1]) == "number" and raw[1] < 0 then
        return context:Fallback("active-item-timing-delegated", raw)
    end
    local enemies = context:EnemyCount()
    if not enemies then return context:Fallback("enemy-count-unknown", raw) end
    local runes = context:Resource("rune")
    if runes == nil then return context:Fallback("rune-count-unknown", raw) end

    -- Disease maintenance is above every cooldown. Blightburst's Putrefy
    -- cooldown and remaining-fight gates are not exposed as plain values, so
    -- let the original source decide rather than ever delaying Outbreak.
    local dread = context:AuraUp("target", SPELL.DREAD_PLAGUE)
    local virulent = context:AuraUp("target", SPELL.VIRULENT_PLAGUE)
    if dread == nil or virulent == nil then
        return context:Fallback("disease-state-unknown", raw)
    end
    if not dread or not virulent then
        return context:Fallback("disease-maintenance-delegated", raw)
    end

    -- Army requires the Festering Scythe target-tracker when that talent is
    -- selected. Only an actual Scythe replacement cast (not an arbitrary two
    -- Festering casts) proves it; the event flag also bridges one-frame aura
    -- propagation delay without ever advancing after a failed keypress.
    local armyReady = context:Ready(SPELL.ARMY_OF_THE_DEAD)
    if armyReady == nil then return context:Fallback("army-readiness-unknown", raw) end
    if armyReady then
        if context:Known(SPELL.FESTERING_SCYTHE) then
            local tracker = context:AuraUp("player", SPELL.FESTERING_SCYTHE_TRACKER)
            if tracker ~= true and not hasRecentScytheCast() then
                local action, ready = readyChoice(SPELL.FESTERING_STRIKE,
                    "cooldowns.army_setup", "awaiting-confirmed-scythe", raw)
                if action then return action end
                if ready == nil then
                    return context:Fallback("army-setup-readiness-unknown", raw)
                end
                -- Army's Festering Scythe tracker is a hard prerequisite in
                -- the current APL. An unavailable builder does not make that
                -- prerequisite true; delegate instead of incorrectly jumping
                -- straight to Army.
                return context:Fallback("army-setup-incomplete", raw)
            end
        end
        return context:Choose(SPELL.ARMY_OF_THE_DEAD,
            "cooldowns.army_of_the_dead", "setup-complete", raw)
    end

    local transformationReady = context:Ready(SPELL.DARK_TRANSFORMATION)
    if transformationReady == nil then
        return context:Fallback("dark-transformation-readiness-unknown", raw)
    end
    if transformationReady then
        local blightfall = context:AuraUp("player", SPELL.BLIGHTFALL_BUFF)
        if blightfall == nil then return context:Fallback("blightfall-state-unknown", raw) end
        if blightfall then
            -- Reaping/Soul Reaper debuff remaining time is a higher-priority
            -- condition that cannot be read reliably from the target aura.
            return context:Fallback("blightfall-transformation-timing-delegated", raw)
        end
        local armyAge = context:CastAge(SPELL.ARMY_OF_THE_DEAD)
        if (armyAge and armyAge < 8) or not context:Known(SPELL.ARMY_OF_THE_DEAD) then
            return context:Choose(SPELL.DARK_TRANSFORMATION,
                "cooldowns.dark_transformation", armyAge and "after-army" or "no-army", raw)
        end
        -- The other exact APL release is Army cooldown >30 seconds.
        return context:Fallback("dark-transformation-army-remains-delegated", raw)
    end

    local transformation = context:AuraUpOrRecentCast(SPELL.DARK_TRANSFORMATION_BUFF,
        SPELL.DARK_TRANSFORMATION, 18)
    if transformation == nil then
        return context:Fallback("dark-transformation-window-unknown", raw)
    end

    local aoe = enemies >= 3
    if aoe and context:Known(SPELL.CYCLE_OF_DEATH) then
        local dndReady = context:Ready(SPELL.DEATH_AND_DECAY)
        if dndReady == nil then return context:Fallback("death-and-decay-readiness-unknown", raw) end
        if dndReady then
            local putrefyCapped = context:AtMaxCharges(SPELL.PUTREFY)
            if putrefyCapped == nil then
                return context:Fallback("putrefy-charge-state-unknown", raw)
            end
            if not putrefyCapped then
                return context:Fallback("cycle-of-death-ground-timing-delegated", raw)
            end
        end
    end

    local scytheUrgent, scytheFallback = festeringScytheUrgent(raw)
    if scytheFallback then return scytheFallback end
    if scytheUrgent then
        -- Both AoE and ST lines additionally require remaining fight/add time.
        return context:Fallback("festering-scythe-fight-remains-delegated", raw)
    end

    if aoe and transformation == true then
        local putrefyReady = context:Ready(SPELL.PUTREFY)
        if putrefyReady == nil then return context:Fallback("putrefy-readiness-unknown", raw) end
        if putrefyReady then
            return context:Choose(SPELL.PUTREFY, "aoe.putrefy",
                "dark-transformation-up", raw)
        end
    end

    -- AoE Soul Reaper is unconditional and sits above the RP spender.
    if aoe then
        local action, ready = readyChoice(SPELL.SOUL_REAPER,
            "aoe.soul_reaper", "ready", raw)
        if action then return action end
        if ready == nil then return context:Fallback("soul-reaper-readiness-unknown", raw) end
    end

    local sudden = procOrAura(SPELL.DEATH_COIL, SPELL.SUDDEN_DOOM)
    if sudden == nil then return context:Fallback("sudden-doom-state-unknown", raw) end
    local forbidden = context:AuraUp("player", SPELL.FORBIDDEN_KNOWLEDGE)
    if forbidden == nil then return context:Fallback("forbidden-knowledge-state-unknown", raw) end

    if aoe then
        local spending, spendingFallback = spendingRunicPower(runes, sudden, forbidden, raw)
        if spendingFallback then return spendingFallback end
        if spending then
            local spender = chooseRunicSpender(raw, enemies, forbidden, "spending-rp")
            if spender then return spender end
        end
    else
        -- The two San'layn lines above Putrefy/Coil are implemented only when
        -- their proc and duration predicates are fully visible.
        local vampiric = context:AuraUp("player", SPELL.VAMPIRIC_STRIKE_BUFF)
        local essence = context:AuraUp("player", SPELL.ESSENCE_OF_BLOOD_QUEEN)
        if vampiric == nil or essence == nil then
            return context:Fallback("sanlayn-proc-state-unknown", raw)
        end
        if vampiric and essence then
            -- The first line is essence.remains < 3*current GCD. The bridge
            -- has no plain current-GCD duration and must not replace it with a
            -- fixed 4.5/5-second approximation.
            local scourgeReady = context:Ready(SPELL.SCOURGE_STRIKE)
            if scourgeReady == nil then
                return context:Fallback("scourge-strike-readiness-unknown", raw)
            end
            if scourgeReady then
                return context:Fallback("vampiric-essence-gcd-timing-delegated", raw)
            end
        end

        if transformation == true then
            local below90 = context:PowerBelow("player", 90, 6) -- RP deficit >10
            if below90 == nil then return context:Fallback("runic-power-threshold-unknown", raw) end
            if below90 then
                local action, ready = readyChoice(SPELL.PUTREFY,
                    "single_target.putrefy", "dark-transformation+rp<90", raw)
                if action then return action end
                if ready == nil then return context:Fallback("putrefy-readiness-unknown", raw) end
            end
        end

        if essence then
            local below10 = context:PowerBelow("player", 10, 6)
            if below10 == nil then return context:Fallback("runic-power-threshold-unknown", raw) end
            if not below10 then
                -- The next Scourge Strike line also needs dynamic max stacks.
                local scourgeReady = context:Ready(SPELL.SCOURGE_STRIKE)
                if scourgeReady == nil then
                    return context:Fallback("scourge-strike-readiness-unknown", raw)
                end
                if scourgeReady then
                    return context:Fallback("essence-max-stack-delegated", raw)
                end
            end
        end

        if sudden then
            local action, ready = readyChoice(SPELL.DEATH_COIL,
                "single_target.death_coil", "sudden-doom", raw)
            if action then return action end
            if ready == nil then return context:Fallback("death-coil-readiness-unknown", raw) end
        end

        if transformation == true then
            local putrefyReady = context:Ready(SPELL.PUTREFY)
            if putrefyReady == true then
                return context:Choose(SPELL.PUTREFY, "single_target.putrefy",
                    "dark-transformation-up", raw)
            elseif putrefyReady == nil then
                return context:Fallback("putrefy-readiness-unknown", raw)
            end
        end

        local soulReady = context:Ready(SPELL.SOUL_REAPER)
        if soulReady == nil then return context:Fallback("soul-reaper-readiness-unknown", raw) end
        if soulReady then
            local execute = context:HealthBelow("target", 35)
            if execute == nil then return context:Fallback("execute-health-gate-unknown", raw) end
            local transformationLow = false
            if transformation == true then
                local age = context:CastAge(SPELL.DARK_TRANSFORMATION)
                if not (age and age < 6) then
                    transformationLow = context:PlayerAuraRemainsBelow(
                        SPELL.DARK_TRANSFORMATION_BUFF, 12)
                    if transformationLow == nil then
                        return context:Fallback("dark-transformation-remains-unknown", raw)
                    end
                end
            end
            if execute or transformationLow then
                return context:Choose(SPELL.SOUL_REAPER, "single_target.soul_reaper",
                    execute and "target<35" or "transformation-remains<12", raw)
            end
            -- Lord of the Dead active/remains is the unobservable third OR.
            return context:Fallback("lord-of-the-dead-state-delegated", raw)
        end

        local essenceLow = false
        if essence then
            essenceLow = context:PlayerAuraRemainsBelow(SPELL.ESSENCE_OF_BLOOD_QUEEN, 5)
            if essenceLow == nil then return context:Fallback("essence-remains-unknown", raw) end
        end
        if transformation == true or forbidden == true or (essenceLow and not vampiric) then
            local action, ready = readyChoice(SPELL.DEATH_COIL,
                "single_target.death_coil", transformation == true and "dark-transformation"
                    or forbidden == true and "forbidden-knowledge" or "essence-expiring", raw)
            if action then return action end
            if ready == nil then return context:Fallback("death-coil-readiness-unknown", raw) end
        end
    end

    local lesser = context:AuraAtLeast("player", SPELL.LESSER_GHOUL_READY, 1)
    if lesser == nil then return context:Fallback("lesser-ghoul-state-unknown", raw) end

    if not aoe and lesser then
        local blighted = context:AuraUp("player", SPELL.BLIGHTED)
        if blighted == nil then return context:Fallback("blighted-state-unknown", raw) end
        if blighted then
            local action, ready = readyChoice(SPELL.SCOURGE_STRIKE,
                "single_target.scourge_strike", "lesser-ghoul+blighted", raw)
            if action then return action end
            if ready == nil then
                return context:Fallback("scourge-strike-readiness-unknown", raw)
            end
        end
    end

    if not aoe then
        -- RP deficit<50 is current RP>50. Integer runic power makes
        -- `not below 51` an exact representation, including the 50 boundary.
        local rpBelow51 = context:PowerBelow("player", 51, 6)
        if rpBelow51 == nil then return context:Fallback("runic-power-threshold-unknown", raw) end
        if not rpBelow51 then
            local action, ready = readyChoice(SPELL.DEATH_COIL,
                "single_target.death_coil", "runic-power>50", raw)
            if action then return action end
            if ready == nil then return context:Fallback("death-coil-readiness-unknown", raw) end
        else
            -- The other OR is Army cooldown >5 seconds, not a cooldown bool.
            return context:Fallback("army-cooldown-remains-delegated", raw)
        end
    end

    local builder = lesser and SPELL.SCOURGE_STRIKE or SPELL.FESTERING_STRIKE
    local action, ready = readyChoice(builder,
        aoe and (lesser and "aoe.scourge_strike" or "aoe.festering_strike")
            or (lesser and "single_target.scourge_strike" or "single_target.festering_strike"),
        lesser and "lesser-ghoul>=1" or "lesser-ghoul=0", raw)
    if action then return action end
    if ready == nil then return context:Fallback("builder-readiness-unknown", raw) end

    if aoe then
        local spender = chooseRunicSpender(raw, enemies, forbidden, "terminal")
        if spender then return spender end
    end
    return context:Fallback("no-unholy-action", raw)
end

local Source = { name = "邪DK 12.1 自有循环（JustAC 兜底）" }

function Source.Initialize() return context:Initialize(onEvent) end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = {
    spell = SPELL,
    context = context,
    opener = opener,
    selectQueue = selectQueue,
}
Registry.Register("unholydk121", Source)
