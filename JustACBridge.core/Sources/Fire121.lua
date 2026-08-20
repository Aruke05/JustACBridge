-- Independent Midnight 12.1 Fire source (M5 only).
--
-- Fire's perfect double-spell/off-GCD weave happens inside an active hardcast,
-- while the bridge deliberately blocks every held-key input during casts. This
-- source therefore owns the strongest exact idle-frame priority and delegates
-- rather than pretending it can reproduce an unobservable projectile/cast-end
-- window. It never interrupts a cast to force Fire Blast or Combustion.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    FIREBALL = 133,
    FLAMESTRIKE = 2120,
    SCORCH = 2948,
    PYROBLAST = 11366,
    FIRE_BLAST = 108853,
    METEOR = 153561,
    COMBUSTION = 190319,
    FROSTFIRE_BOLT = 431044,

    HEATING_UP = 48107,
    HOT_STREAK = 48108,
    PYROCLASM = 269651,
    HYPERTHERMIA = 383874,
    HEAT_SHIMMER = 458964,
    FROSTFIRE_EMPOWERMENT = 431177,

    FIRESTARTER = 205026,
    FUEL_THE_FIRE = 416094,
    BLAST_ZONE = 416719,
    SCALD = 450746,
    SPELLFIRE_SPHERES = 448601,
}

local GCD = {
    [SPELL.FIREBALL] = true,
    [SPELL.FLAMESTRIKE] = true,
    [SPELL.SCORCH] = true,
    [SPELL.PYROBLAST] = true,
    [SPELL.METEOR] = true,
    [SPELL.FROSTFIRE_BOLT] = true,
}

local context = Runtime.New("fire121", "MAGE", 2, GCD)
local state = { combustionPrecast = nil, combustionPrecastAt = nil }

local function onEvent(_, event, spellID)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        state.combustionPrecast, state.combustionPrecastAt = nil, nil
        return
    end
    if spellID == SPELL.COMBUSTION then
        state.combustionPrecast, state.combustionPrecastAt = nil, nil
    elseif spellID == state.combustionPrecast then
        state.combustionPrecast = nil
        state.combustionPrecastAt = GetTime and GetTime() or 0
    end
end

local function heroTree()
    if context:Known(SPELL.FROSTFIRE_BOLT) then return "frostfire" end
    if context:Known(SPELL.SPELLFIRE_SPHERES) then return "sunfury" end
    return nil
end

local function procKind()
    local glow = context:Procced(SPELL.PYROBLAST)
    local hot = context:AuraUp("player", SPELL.HOT_STREAK)
    local hyper = context:AuraUp("player", SPELL.HYPERTHERMIA)
    local pyroclasm = context:AuraUp("player", SPELL.PYROCLASM)
    if hot == true or hyper == true then return "instant" end
    if pyroclasm == true then return "pyroclasm" end
    if glow == false and hot ~= true and hyper ~= true and pyroclasm ~= true then
        return nil
    end
    -- A lit Pyro button does not distinguish an instant Hot Streak from the
    -- hardcast Pyroclasm state. Guessing here would break movement safety.
    if glow == true then return "unknown" end
    if hot == false and hyper == false and pyroclasm == false then return nil end
    return "unknown"
end

local function auraOrGlow(spellID, auraID)
    local aura = context:AuraUp("player", auraID)
    if aura ~= nil then return aura end
    local glow = context:Procced(spellID)
    if glow == true then return true end
    if glow == false then return false end
    return nil
end

local function chooseIfReady(spellID, rule, detail, raw)
    local ready = context:Ready(spellID)
    if ready == true then return context:Choose(spellID, rule, detail, raw), true end
    return nil, ready
end

local function spender(enemies, proc, phase, raw)
    local flamestrike = enemies >= 3 and context:Known(SPELL.FUEL_THE_FIRE)
    local spellID = flamestrike and SPELL.FLAMESTRIKE or SPELL.PYROBLAST
    local action, ready = chooseIfReady(spellID, phase .. ".spender",
        ("proc=%s enemies=%d threshold=%s"):format(proc, enemies,
            flamestrike and "3" or "pyroblast"), raw)
    if action then return action end
    if ready == nil then return context:Fallback("fire-spender-readiness-unknown", raw) end
    return nil
end

local function combustionWindow()
    return context:AuraUpOrRecentCast(SPELL.COMBUSTION, SPELL.COMBUSTION, 9)
end

local function chooseTerminal(hero, rule, raw)
    local filler = hero == "frostfire" and SPELL.FROSTFIRE_BOLT or SPELL.FIREBALL
    local action, ready = chooseIfReady(filler, rule, hero, raw)
    if action then return action end
    return context:Fallback(ready == nil and "fire-filler-readiness-unknown"
        or "no-fire-action", raw)
end

local function selectCombustion(raw, hero, enemies, proc)
    -- Meteor lands within Combustion. Frostfire Burnout wants a late Meteor;
    -- without a readable aura-remains predicate that exact sub-branch stays
    -- with JustAC instead of being approximated by a fixed timer.
    local meteorReady = context:Ready(SPELL.METEOR)
    if meteorReady == nil then return context:Fallback("meteor-readiness-unknown", raw) end
    if meteorReady then
        if hero == "sunfury" then
            local age = context:CastAge(SPELL.COMBUSTION)
            local belowTwo
            if age and age < 7 then
                belowTwo = false
            else
                belowTwo = context:PlayerAuraRemainsBelow(SPELL.COMBUSTION, 2)
            end
            if belowTwo == nil then
                return context:Fallback("combustion-remains-for-meteor-unknown", raw)
            end
            if not belowTwo then
                return context:Choose(SPELL.METEOR, "combustion.meteor",
                    "sunfury+remains>2", raw)
            end
        end
        if hero == "frostfire" then
            return context:Fallback("frostfire-burnout-meteor-timing-delegated", raw)
        end
    end

    if proc == "unknown" then return context:Fallback("pyro-proc-kind-unknown", raw) end
    if proc == "instant" then
        local action = spender(enemies, proc, "combustion", raw)
        if action then return action end
    elseif proc == "pyroclasm" then
        -- Both hero lists require the hardcast to finish before Combustion
        -- expires. Exact live cast/remains comparison is unavailable.
        return context:Fallback("pyroclasm-combustion-remains-delegated", raw)
    end

    local heating = auraOrGlow(SPELL.FIRE_BLAST, SPELL.HEATING_UP)
    if heating == nil then return context:Fallback("combustion-heating-up-unknown", raw) end
    if heating then
        local action, ready = chooseIfReady(SPELL.FIRE_BLAST,
            "combustion.fire_blast", "heating-up", raw)
        if action then return action end
        if ready == nil then return context:Fallback("fire-blast-readiness-unknown", raw) end
    end

    local heatShimmer = auraOrGlow(SPELL.SCORCH, SPELL.HEAT_SHIMMER)
    if heatShimmer == nil then return context:Fallback("heat-shimmer-state-unknown", raw) end
    local execute = context:HealthBelow("target", 30)
    if execute == nil then return context:Fallback("execute-health-gate-unknown", raw) end
    if heatShimmer or (execute and context:Known(SPELL.SCALD)) or hero == "sunfury" then
        local action, ready = chooseIfReady(SPELL.SCORCH,
            "combustion.scorch", heatShimmer and "heat-shimmer"
                or (execute and "scald-execute" or "sunfury-builder"), raw)
        if action then return action end
        if ready == nil then return context:Fallback("scorch-readiness-unknown", raw) end
    end
    return chooseTerminal(hero, "combustion.filler", raw)
end

local function selectFiller(raw, hero, enemies, proc, combustionReady, heldForFirestarter)
    -- Frostfire casts Meteor on cooldown once the initial Firestarter delay has
    -- passed. Sunfury uses it on cooldown outside Combustion only with Blast
    -- Zone and only after the first Combustion has actually been observed.
    local meteorReady = context:Ready(SPELL.METEOR)
    if meteorReady == nil then return context:Fallback("meteor-readiness-unknown", raw) end
    if meteorReady and not combustionReady then
        if hero == "frostfire" and not heldForFirestarter then
            return context:Choose(SPELL.METEOR, "filler.meteor", "frostfire-on-cooldown", raw)
        elseif hero == "sunfury" and context:Known(SPELL.BLAST_ZONE)
            and context:CastAge(SPELL.COMBUSTION) then
            return context:Choose(SPELL.METEOR, "filler.meteor",
                "sunfury+blast-zone+post-first-combustion", raw)
        end
    end

    if proc == "unknown" then return context:Fallback("pyro-proc-kind-unknown", raw) end
    if proc == "instant" then
        local action = spender(enemies, proc, "filler", raw)
        if action then return action end
    elseif proc == "pyroclasm" then
        if hero == "sunfury" then
            local action = spender(enemies, proc, "filler", raw)
            if action then return action end
        end
        local two = context:AuraAtLeast("player", SPELL.PYROCLASM, 2)
        if two == nil then return context:Fallback("pyroclasm-two-stack-state-unknown", raw) end
        if two then
            local action = spender(enemies, proc, "filler", raw)
            if action then return action end
        end
        -- Frostfire's other release is Combustion cooldown >12 seconds.
        return context:Fallback("pyroclasm-combustion-remains-delegated", raw)
    end

    -- The ideal Fire Blast is pressed during the current hardcast. Because
    -- held-key cast protection forbids that input, idle-frame conversion is
    -- the best non-clipping action the bridge can prove.
    local heating = auraOrGlow(SPELL.FIRE_BLAST, SPELL.HEATING_UP)
    if heating == nil then return context:Fallback("heating-up-state-unknown", raw) end
    if heating then
        local action, ready = chooseIfReady(SPELL.FIRE_BLAST,
            "filler.fire_blast", "idle-frame-heating-up", raw)
        if action then return action end
        if ready == nil then return context:Fallback("fire-blast-readiness-unknown", raw) end
    end

    local heatShimmer = auraOrGlow(SPELL.SCORCH, SPELL.HEAT_SHIMMER)
    if heatShimmer == nil then return context:Fallback("heat-shimmer-state-unknown", raw) end
    local execute = context:HealthBelow("target", 30)
    if execute == nil then return context:Fallback("execute-health-gate-unknown", raw) end
    if heatShimmer or (execute and context:Known(SPELL.SCALD)) then
        local action, ready = chooseIfReady(SPELL.SCORCH,
            "filler.scorch", heatShimmer and "heat-shimmer" or "scald-execute", raw)
        if action then return action end
        if ready == nil then return context:Fallback("scorch-readiness-unknown", raw) end
    end

    return chooseTerminal(hero, "filler.terminal", raw)
end

local function selectQueue(raw)
    if not context:InScope() then return context:Fallback("outside-fire-12.1", raw) end
    local hero = heroTree()
    if not hero then return context:Fallback("hero-tree-unknown", raw) end
    if not context:HasHostileTarget() then return context:Fallback("no-hostile-target", raw) end
    if type(raw[1]) == "number" and raw[1] < 0 then
        return context:Fallback("active-item-timing-delegated", raw)
    end

    if not context:InCombat() then
        local action, ready = chooseIfReady(SPELL.PYROBLAST,
            "precombat.pyroblast", hero, raw)
        if action then return action end
        return context:Fallback(ready == nil and "precombat-pyro-readiness-unknown"
            or "precombat-delegated", raw)
    end

    local enemies = context:EnemyCount()
    if not enemies then return context:Fallback("enemy-count-unknown", raw) end
    local proc = procKind()
    local combustion = combustionWindow()
    if combustion == true then return selectCombustion(raw, hero, enemies, proc) end
    if combustion == nil and context:CallBoolean("IsSpellOnCooldown", SPELL.COMBUSTION) == true then
        return context:Fallback("combustion-window-unknown", raw)
    end

    local combustionReady = context:Ready(SPELL.COMBUSTION)
    if combustionReady == nil then return context:Fallback("combustion-readiness-unknown", raw) end
    local heldForFirestarter = false
    if combustionReady and context:Known(SPELL.FIRESTARTER) then
        local below90 = context:HealthBelow("target", 90)
        if below90 == nil then return context:Fallback("firestarter-health-gate-unknown", raw) end
        heldForFirestarter = not below90
    end

    if combustionReady and not heldForFirestarter then
        -- Sunfury spends a visible instant Hot Streak before entering the
        -- precast. The bridge cannot inject Combustion in the last 150 ms of a
        -- hardcast, so after this exact spender it activates at the next idle
        -- opportunity rather than claiming a fake double-Pyro sequence.
        if hero == "sunfury" and proc == "instant" then
            local action = spender(enemies, proc, "combustion_setup", raw)
            if action then return action end
        elseif proc == "unknown" then
            return context:Fallback("combustion-setup-proc-kind-unknown", raw)
        end

        local completedAge = state.combustionPrecastAt
            and math.max(0, (GetTime and GetTime() or 0) - state.combustionPrecastAt)
        if completedAge and completedAge < 2 then
            return context:Choose(SPELL.COMBUSTION, "cooldowns.combustion",
                hero .. "+confirmed-precast-complete", raw)
        elseif completedAge then
            state.combustionPrecastAt = nil
        end

        -- Reproduce the strongest part of the precast sequence without ever
        -- sending an off-GCD key during an active hardcast. Combustion is sent
        -- on the first idle frame after the server confirms this cast; its
        -- projectile is still in flight, unlike an immediate idle Combustion.
        local spellID
        if proc == "pyroclasm" then
            spellID = enemies >= 3 and context:Known(SPELL.FUEL_THE_FIRE)
                and SPELL.FLAMESTRIKE or SPELL.PYROBLAST
        elseif hero == "sunfury" then
            local execute = context:HealthBelow("target", 30)
            if execute == nil then
                return context:Fallback("combustion-precast-health-gate-unknown", raw)
            end
            spellID = (enemies >= 4 or execute) and SPELL.SCORCH or SPELL.FIREBALL
        else
            spellID = hero == "frostfire" and SPELL.FROSTFIRE_BOLT or SPELL.FIREBALL
        end
        local action, ready = chooseIfReady(spellID, "combustion.precast",
            hero .. "+confirmed-cast-then-combustion", raw)
        if action then
            state.combustionPrecast = spellID
            return action
        end
        if ready == nil then return context:Fallback("combustion-precast-readiness-unknown", raw) end
        return context:Fallback("combustion-precast-unavailable", raw)
    end

    state.combustionPrecast, state.combustionPrecastAt = nil, nil

    return selectFiller(raw, hero, enemies, proc, combustionReady, heldForFirestarter)
end

local Source = { name = "火法 12.1 自有循环（JustAC 兜底）" }

function Source.Initialize() return context:Initialize(onEvent) end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, state = state, selectQueue = selectQueue }
Registry.Register("fire121", Source)
