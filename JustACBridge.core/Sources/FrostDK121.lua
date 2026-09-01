-- Independent Midnight 12.1 Frost Death Knight source (M5 only).
-- Rider/Shattering is owned deeply; Breath and Deathbringer pooling branches
-- fall back whenever their exact cooldown-remains predicates are unavailable.

local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    FROST_STRIKE = 49143,
    HOWLING_BLAST = 49184,
    OBLITERATE = 49020,
    PILLAR_OF_FROST = 51271,
    RAISE_DEAD = 46585,
    EMPOWER_RUNE_WEAPON = 47568,
    FROSTSCYTHE = 207230,
    FROSTWYRM_FURY = 279302,
    REMORSELESS_WINTER = 196770,
    GLACIAL_ADVANCE = 194913,
    REAPERS_MARK = 439843,
    BREATH_OF_SINDRAGOSA = 1249658,

    KILLING_MACHINE = 51124,
    RIME = 59052,
    RAZORICE = 51714,
    FROSTBANE = 1229310,
    BONEGRINDER_FROST = 377103,
    CHOSEN_FROSTWYRM = 1265639,
    FROST_FEVER = 55095,
    GATHERING_STORM = 194912,
    OBLITERATION = 207256,
    SHATTERING_BLADE = 207057,
    FROSTBOUND_WILL = 1238680,
    FROSTBANE_ACTION = 1228433,
}

local GCD = {
    [SPELL.FROST_STRIKE] = true,
    [SPELL.HOWLING_BLAST] = true,
    [SPELL.OBLITERATE] = true,
    [SPELL.PILLAR_OF_FROST] = true,
    [SPELL.RAISE_DEAD] = true,
    [SPELL.EMPOWER_RUNE_WEAPON] = true,
    [SPELL.FROSTSCYTHE] = true,
    [SPELL.FROSTWYRM_FURY] = true,
    [SPELL.REMORSELESS_WINTER] = true,
    [SPELL.GLACIAL_ADVANCE] = true,
    [SPELL.REAPERS_MARK] = true,
    [SPELL.BREATH_OF_SINDRAGOSA] = true,
}

local context = Runtime.New("frostdk121", "DEATHKNIGHT", 2, GCD)

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

local function selectQueue(raw)
    if not context:InScope() then return context:Fallback("outside-frost-dk-12.1", raw) end
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

    local killing = procOrAura(SPELL.OBLITERATE, SPELL.KILLING_MACHINE)
    local killingTwo = context:AuraAtLeast("player", SPELL.KILLING_MACHINE, 2)
    local rime = procOrAura(SPELL.HOWLING_BLAST, SPELL.RIME)
    if killing == nil then return context:Fallback("killing-machine-state-unknown", raw) end
    if rime == nil then return context:Fallback("rime-state-unknown", raw) end

    -- Cooldown list: exact parts of current SimC plus the guide's Pillar/FWF
    -- alignment. M4 never sees this list because GetPreserveQueue is raw.
    local winterReady = context:Ready(SPELL.REMORSELESS_WINTER)
    if winterReady == nil then return context:Fallback("remorseless-winter-readiness-unknown", raw) end
    if winterReady and (enemies > 1 or context:Known(SPELL.GATHERING_STORM)) then
        -- fight_remains>10 and sending_cds are higher predicates. M5 means
        -- "do not reserve burst", not "pretend the encounter timer exists".
        return context:Fallback("remorseless-winter-encounter-timing-delegated", raw)
    end

    local deathbringer = context:Known(SPELL.REAPERS_MARK)
    local breathKnown = context:Known(SPELL.BREATH_OF_SINDRAGOSA)
    local pillarReady = context:Ready(SPELL.PILLAR_OF_FROST)
    if pillarReady == nil then return context:Fallback("pillar-readiness-unknown", raw) end
    if pillarReady then
        if deathbringer and runes < 2 then
            return context:Fallback("pillar-deathbringer-rune-pool", raw)
        end
        if breathKnown then
            local breathReady = context:Ready(SPELL.BREATH_OF_SINDRAGOSA)
            if breathReady == nil then
                return context:Fallback("breath-readiness-unknown", raw)
            end
            if not breathReady then
                -- The alternate branch is Breath cooldown >20 s. A plain
                -- on-cooldown bit cannot prove that remaining-time predicate.
                return context:Fallback("breath-pillar-timing-delegated", raw)
            end
            local requiredPower = deathbringer and 40 or 60
            local below = context:PowerBelow("player", requiredPower, 6)
            if below == nil then
                return context:Fallback("breath-runic-power-threshold-unknown", raw)
            end
            if below then return context:Fallback("breath-runic-power-pooling", raw) end
        end
        return context:Choose(SPELL.PILLAR_OF_FROST, "cooldowns.pillar_of_frost",
            deathbringer and "runes>=2" or "full-burst", raw)
    end

    local pillar = context:AuraUpOrRecentCast(SPELL.PILLAR_OF_FROST,
        SPELL.PILLAR_OF_FROST, 10)
    if breathKnown then
        local breathReady = context:Ready(SPELL.BREATH_OF_SINDRAGOSA)
        if breathReady == nil then return context:Fallback("breath-readiness-unknown", raw) end
        if breathReady then
            if pillar == true then
                return context:Choose(SPELL.BREATH_OF_SINDRAGOSA,
                    "cooldowns.breath_of_sindragosa", "pillar-up", raw)
            elseif pillar == nil then
                return context:Fallback("pillar-window-unknown-for-breath", raw)
            end
        end
    end

    if deathbringer then
        local markReady = context:Ready(SPELL.REAPERS_MARK)
        if markReady == nil then return context:Fallback("reapers-mark-readiness-unknown", raw) end
        if markReady then
            if pillar == true then
                return context:Choose(SPELL.REAPERS_MARK, "cooldowns.reapers_mark",
                    "pillar-up", raw)
            end
            return context:Fallback("reapers-mark-pillar-remains-unknown", raw)
        end
    end

    local wyrmReady = context:Ready(SPELL.FROSTWYRM_FURY)
    if wyrmReady == nil then return context:Fallback("frostwyrm-readiness-unknown", raw) end
    if wyrmReady then
        -- Every current FWF branch also needs talent-tree, expiration,
        -- add-timing or fight-remains predicates that are not all observable.
        return context:Fallback("frostwyrm-window-delegated", raw)
    end

    local raiseReady = context:Ready(SPELL.RAISE_DEAD)
    if raiseReady == true then
        return context:Choose(SPELL.RAISE_DEAD, "cooldowns.raise_dead", "ready", raw)
    elseif raiseReady == nil then
        return context:Fallback("raise-dead-readiness-unknown", raw)
    end

    local erwReady = context:Ready(SPELL.EMPOWER_RUNE_WEAPON)
    if erwReady == nil then return context:Fallback("erw-readiness-unknown", raw) end
    if erwReady then
        local lowRunicPower = context:PowerBelow("player", 35, 6) -- RunicPower
        if lowRunicPower == nil then return context:Fallback("runic-power-threshold-unknown", raw) end
        if (runes < 2 or not killing) and lowRunicPower then
            return context:Choose(SPELL.EMPOWER_RUNE_WEAPON,
                "cooldowns.empower_rune_weapon", "low-runes-or-no-km+rp<35", raw)
        end
        -- Full-recharge, Breath alignment and Pillar remaining time are later
        -- ERW branches; a ready bit cannot prove they are all false.
        return context:Fallback("erw-later-priorities-delegated", raw)
    end

    local function frostbaneActive()
        local display = context:Display(SPELL.FROST_STRIKE)
        if display == SPELL.FROSTBANE_ACTION then return true end
        return procOrAura(SPELL.FROST_STRIKE, SPELL.FROSTBANE)
    end

    local aoe = enemies >= 2
    if aoe then
        -- Preserve the exact first four SimC AoE rows. Frost Strike with a
        -- live Frostbane proc sits between the two-stack Frostscythe row and
        -- the later rune-gated Frostscythe/Obliterate rows. The previous
        -- combined branch skipped that Frost Strike whenever Frostscythe was
        -- unavailable, silently changing the APL instead of falling through
        -- to the next row.
        local frostscytheReady = false
        if killing then
            frostscytheReady = context:Ready(SPELL.FROSTSCYTHE)
            if frostscytheReady == nil then
                return context:Fallback("frostscythe-readiness-unknown", raw)
            end
        end
        if killing and killingTwo == true and frostscytheReady then
            return context:Choose(SPELL.FROSTSCYTHE, "aoe.frostscythe",
                "killing-machine=2", raw)
        end
        -- If the stack count is unreadable, only an unavailable Frostscythe
        -- proves the first row cannot win. A ready spell must be delegated;
        -- guessing one stack would incorrectly promote Frostbane.
        if killing and killingTwo == nil and frostscytheReady then
            return context:Fallback("killing-machine-two-stack-unknown", raw)
        end

        local razoriceFive = context:AuraAtLeast("target", SPELL.RAZORICE, 5)
        local frostbane = frostbaneActive()
        if razoriceFive == true and frostbane == true then
            local action, ready = readyChoice(SPELL.FROST_STRIKE,
                "aoe.frost_strike", "razorice=5+frostbane", raw)
            if action then return action end
            if ready == nil then return context:Fallback("frost-strike-readiness-unknown", raw) end
        elseif razoriceFive == true and frostbane == nil then
            return context:Fallback("frostbane-state-unknown", raw)
        end

        if killing and runes >= 3 and frostscytheReady then
            return context:Choose(SPELL.FROSTSCYTHE, "aoe.frostscythe",
                "killing-machine+runes>=3", raw)
        end
        if killing and (killingTwo == true or runes >= 3) then
            local action, ready = readyChoice(SPELL.OBLITERATE,
                "aoe.obliterate", killingTwo == true and "killing-machine=2"
                    or "killing-machine+runes>=3", raw)
            if action then return action end
            if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
        elseif killing and killingTwo == nil then
            local obliterateReady = context:Ready(SPELL.OBLITERATE)
            if obliterateReady == nil then
                return context:Fallback("obliterate-readiness-unknown", raw)
            end
            if obliterateReady then
                return context:Fallback("killing-machine-two-stack-unknown", raw)
            end
        end

        -- Rime+Frostbound and missing Frost Fever are above the pooling lines.
        local fever = context:AuraUp("target", SPELL.FROST_FEVER)
        if (rime and context:Known(SPELL.FROSTBOUND_WILL)) or fever == false then
            local action, ready = readyChoice(SPELL.HOWLING_BLAST,
                "aoe.howling_blast", fever == false and "frost-fever-missing"
                    or "rime+frostbound-will", raw)
            if action then return action end
            if ready == nil then return context:Fallback("howling-blast-readiness-unknown", raw) end
        elseif fever == nil and not (rime and context:Known(SPELL.FROSTBOUND_WILL)) then
            return context:Fallback("frost-fever-state-unknown", raw)
        end

        -- The Shattering Blade spender follows disease maintenance but is
        -- above the generic KM line. AoE additionally requires the Frostbane
        -- *talent* to be absent; a down proc aura does not prove that.
        if enemies < 5 and context:Known(SPELL.SHATTERING_BLADE)
            and razoriceFive == true and frostbane ~= true then
            return context:Fallback("shattering-vs-frostbane-talent-delegated", raw)
        end

        if killing then
            if deathbringer then
                return context:Fallback("deathbringer-rune-pooling-delegated", raw)
            end
            local action, ready = readyChoice(SPELL.FROSTSCYTHE,
                "aoe.frostscythe", "killing-machine", raw)
            if action then return action end
            if ready == nil then return context:Fallback("frostscythe-readiness-unknown", raw) end
            action, ready = readyChoice(SPELL.OBLITERATE,
                "aoe.obliterate", "killing-machine-frostscythe-unavailable", raw)
            if action then return action end
            if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
        end

        if rime then
            local action, ready = readyChoice(SPELL.HOWLING_BLAST,
                "aoe.howling_blast", "rime", raw)
            if action then return action end
            if ready == nil then return context:Fallback("howling-blast-readiness-unknown", raw) end
        end

        if breathKnown then
            return context:Fallback("breath-runic-power-pooling-delegated", raw)
        end
        if enemies >= 3 then
            local action, ready = readyChoice(SPELL.GLACIAL_ADVANCE,
                "aoe.glacial_advance", "enemies>=3", raw)
            if action then return action end
            if ready == nil then return context:Fallback("glacial-advance-readiness-unknown", raw) end
        else
            local action, ready = readyChoice(SPELL.FROST_STRIKE,
                "aoe.frost_strike", "two-target-rp-spender", raw)
            if action then return action end
            if ready == nil then return context:Fallback("frost-strike-readiness-unknown", raw) end
        end

        if deathbringer then
            return context:Fallback("deathbringer-rune-pooling-delegated", raw)
        end
        if context:Known(SPELL.OBLITERATION) then
            if pillar == nil then return context:Fallback("pillar-window-unknown", raw) end
            if pillar == true then
                local action, ready = readyChoice(SPELL.HOWLING_BLAST,
                    "aoe.howling_blast", "obliteration+pillar+no-km", raw)
                if action then return action end
                if ready == nil then
                    return context:Fallback("howling-blast-readiness-unknown", raw)
                end
                return context:Fallback("no-obliteration-weave-action", raw)
            end
        end
        local action, ready = readyChoice(SPELL.FROSTSCYTHE,
            "aoe.frostscythe", "terminal", raw)
        if action then return action end
        if ready == nil then return context:Fallback("terminal-frostscythe-readiness-unknown", raw) end
        action, ready = readyChoice(SPELL.OBLITERATE,
            "aoe.obliterate", "terminal-fallback", raw)
        if action then return action end
        if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
        return context:Fallback("no-frost-dk-aoe-action", raw)
    end

    -- Single target: only the two-stack / >=3-rune KM line is above Rime.
    if killing and (killingTwo == true or runes >= 3) then
        local action, ready = readyChoice(SPELL.OBLITERATE,
            "single_target.obliterate", killingTwo == true
                and "killing-machine=2" or "killing-machine+runes>=3", raw)
        if action then return action end
        if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
    elseif killing and killingTwo == nil and runes < 3 then
        return context:Fallback("killing-machine-two-stack-unknown", raw)
    end

    if rime and context:Known(SPELL.FROSTBOUND_WILL) then
        local action, ready = readyChoice(SPELL.HOWLING_BLAST,
            "single_target.howling_blast", "rime+frostbound-will", raw)
        if action then return action end
        if ready == nil then return context:Fallback("howling-blast-readiness-unknown", raw) end
    end

    local razoriceFive = context:AuraAtLeast("target", SPELL.RAZORICE, 5)
    if context:Known(SPELL.SHATTERING_BLADE) then
        if razoriceFive == true then
            if breathKnown then return context:Fallback("breath-rp-pooling-delegated", raw) end
            local action, ready = readyChoice(SPELL.FROST_STRIKE,
                "single_target.frost_strike", "shattering-blade+razorice=5", raw)
            if action then return action end
            if ready == nil then return context:Fallback("frost-strike-readiness-unknown", raw) end
        elseif razoriceFive == nil then
            return context:Fallback("razorice-stack-state-unknown", raw)
        end
    end

    if rime then
        local action, ready = readyChoice(SPELL.HOWLING_BLAST,
            "single_target.howling_blast", "rime", raw)
        if action then return action end
        if ready == nil then return context:Fallback("howling-blast-readiness-unknown", raw) end
    end

    if not context:Known(SPELL.SHATTERING_BLADE) then
        if breathKnown then return context:Fallback("breath-rp-pooling-delegated", raw) end
        local rpBelow70 = context:PowerBelow("player", 70, 6)
        if rpBelow70 == nil then return context:Fallback("runic-power-threshold-unknown", raw) end
        if not rpBelow70 then
            local action, ready = readyChoice(SPELL.FROST_STRIKE,
                "single_target.frost_strike", "runic-power>70", raw)
            if action then return action end
            if ready == nil then return context:Fallback("frost-strike-readiness-unknown", raw) end
        end
    end

    if killing then
        if deathbringer then return context:Fallback("deathbringer-rune-pooling-delegated", raw) end
        local action, ready = readyChoice(SPELL.OBLITERATE,
            "single_target.obliterate", "killing-machine", raw)
        if action then return action end
        if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
    end

    if breathKnown then return context:Fallback("breath-rp-pooling-delegated", raw) end
    local action, ready = readyChoice(SPELL.FROST_STRIKE,
        "single_target.frost_strike", "terminal-spender", raw)
    if action then return action end
    if ready == nil then return context:Fallback("frost-strike-readiness-unknown", raw) end

    if deathbringer then return context:Fallback("deathbringer-rune-pooling-delegated", raw) end
    if context:Known(SPELL.OBLITERATION) then
        if pillar == nil then return context:Fallback("pillar-window-unknown", raw) end
        if pillar == true then
            action, ready = readyChoice(SPELL.HOWLING_BLAST,
                "single_target.howling_blast", "obliteration+pillar+no-km", raw)
            if action then return action end
            if ready == nil then return context:Fallback("howling-blast-readiness-unknown", raw) end
            return context:Fallback("no-obliteration-weave-action", raw)
        end
    end
    action, ready = readyChoice(SPELL.OBLITERATE,
        "single_target.obliterate", "terminal-builder", raw)
    if action then return action end
    if ready == nil then return context:Fallback("obliterate-readiness-unknown", raw) end
    return context:Fallback("no-frost-dk-action", raw)
end

local Source = { name = "冰DK 12.1 自有循环（JustAC 兜底）" }

function Source.Initialize() return context:Initialize() end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue() return selectQueue(context:RawQueue()) end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision end

Source._Test = { spell = SPELL, context = context, selectQueue = selectQueue }
Registry.Register("frostdk121", Source)
