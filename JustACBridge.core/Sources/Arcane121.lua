-- Independent Midnight 12.1 Arcane decision source.
--
-- This source owns every recommendation it can prove from live, branchable
-- state.  It deliberately returns the untouched JustAC queue as soon as a
-- higher-priority SimC predicate becomes unknowable; unknown is never treated
-- as false.  Arcane is the deliberate preserve-mode exception: M4 runs the
-- same owned priority as M5, but never selects Arcane Surge or Touch of the
-- Magi.  The policy layer still enforces hold-safe cast/channel rules.

local Registry = _G.JustACBridgeRecommendationSources
if not Registry then return end

local SpellQueue
local BlizzardAPI
local SURGE_AFTER_TOUCH_SECONDS = 10

local SPELL = {
    ARCANE_BLAST = 30451,
    ARCANE_BARRAGE = 44425,
    ARCANE_MISSILES = 5143,
    ARCANE_ORB = 153626,
    TOUCH_OF_THE_MAGI = 321507,
    ARCANE_SURGE = 365350,
    PRISMATIC_BOLT = 1295924,
    ARCANE_PULSE = 1241462,

    SPLINTERING_SORCERY = 443739,
    SPELLFIRE_SPHERES = 448601,
    LUSTROUS_GLEAM = 1295147,
    LIQUID_LUSTER = 1295132,
    ARCANE_SALVO = 1242974,
    CLEARCASTING = 263725,
    ARCANE_SOUL = 453413,
    CUMULATIVE_POWER = 1296930,
    ORB_BARRAGE = 384858,
}

local GCD_SPELLS = {
    [SPELL.ARCANE_BLAST] = true,
    [SPELL.ARCANE_BARRAGE] = true,
    [SPELL.ARCANE_MISSILES] = true,
    [SPELL.ARCANE_ORB] = true,
    [SPELL.TOUCH_OF_THE_MAGI] = true,
    [SPELL.ARCANE_SURGE] = true,
    [SPELL.PRISMATIC_BOLT] = true,
    [1295939] = true, -- Prismatic Bolt display/effective form
    [SPELL.ARCANE_PULSE] = true,
    [1243460] = true, -- Arcane Pulse compatibility form
}

local state = {
    cleanAuraBaseline = false,
    liquidLusterCastAt = nil,
    castSequenceSerial = 0,
    touchCastAt = nil,
    touchCastStep = 0,
    surgeCastAt = nil,
    surgeCastStep = 0,
    orbCastAt = nil,
    lastGCDSpellID = nil,
    decision = "uninitialized",
    selectedSpellID = nil,
}

local function isPlain(value, expectedType)
    if type(value) ~= expectedType then return false end
    return not (issecretvalue and issecretvalue(value))
end

local function now()
    if not GetTime then return 0 end
    local ok, value = pcall(GetTime)
    return ok and isPlain(value, "number") and value or 0
end

local function inCombat()
    if not UnitAffectingCombat then return false end
    local ok, value = pcall(UnitAffectingCombat, "player")
    return ok and isPlain(value, "boolean") and value == true
end

local function isArcane121()
    if not UnitClass then return false end
    local okClass, _, classFile = pcall(UnitClass, "player")
    local okSpec, spec = false, nil
    if GetSpecialization then okSpec, spec = pcall(GetSpecialization) end
    local okBuild, interface = false, nil
    if GetBuildInfo then
        local version, build, date
        okBuild, version, build, date, interface = pcall(GetBuildInfo)
    end
    return okClass and isPlain(classFile, "string") and classFile == "MAGE"
        and okSpec and isPlain(spec, "number") and spec == 1
        and okBuild and isPlain(interface, "number")
        and interface >= 120100 and interface <= 120199
end

local function isKnown(spellID)
    if IsPlayerSpell then
        local ok, value = pcall(IsPlayerSpell, spellID)
        if ok and isPlain(value, "boolean") and value == true then return true end
    end
    if IsSpellKnown then
        local ok, value = pcall(IsSpellKnown, spellID)
        if ok and isPlain(value, "boolean") and value == true then return true end
    end
    return false
end

local function heroTree()
    if isKnown(SPELL.SPLINTERING_SORCERY) then return "spellslinger" end
    if isKnown(SPELL.SPELLFIRE_SPHERES) then return "sunfury" end
    return nil
end

local function callBoolean(method, ...)
    if not BlizzardAPI or type(BlizzardAPI[method]) ~= "function" then return nil end
    local ok, value = pcall(BlizzardAPI[method], ...)
    if not ok or not isPlain(value, "boolean") then return nil end
    return value
end

local function spellReady(spellID)
    -- Cooldown/usability/proc state never proves that the current character
    -- actually owns an action. Every source-owned export starts with a
    -- positive ownership check.
    if not isKnown(spellID) then return false end
    local usable = callBoolean("IsSpellUsable", spellID)
    local cooldown = callBoolean("IsSpellOnCooldown", spellID)
    if usable == nil or cooldown == nil then return nil end
    return usable and not cooldown
end

local function auraAtLeast(spellID, stacks)
    if not BlizzardAPI or type(BlizzardAPI.GetAuraStackAtLeast) ~= "function" then return nil end
    local ok, value = pcall(BlizzardAPI.GetAuraStackAtLeast, "player", spellID, stacks)
    if not ok or not isPlain(value, "boolean") then return nil end
    return value
end

local function classResource()
    if not BlizzardAPI or type(BlizzardAPI.GetClassResourcePoints) ~= "function" then
        return nil, nil
    end
    local ok, current, maximum, resource = pcall(BlizzardAPI.GetClassResourcePoints)
    if not ok or not isPlain(resource, "string") or resource ~= "arcane_charges"
        or not isPlain(current, "number")
        or (maximum ~= nil and not isPlain(maximum, "number")) then
        return nil, nil
    end
    return current, maximum
end

local function displaySpell(spellID)
    if not BlizzardAPI or type(BlizzardAPI.GetDisplaySpellID) ~= "function" then return nil end
    local ok, value = pcall(BlizzardAPI.GetDisplaySpellID, spellID)
    return ok and isPlain(value, "number") and value or nil
end

local function prismaticBoltActive()
    -- Prismatic Bolt is the live replacement form of the owned Arcane Blast
    -- button; the display ID alone is not sufficient ownership evidence.
    if not isKnown(SPELL.ARCANE_BLAST) then return false end
    local display = displaySpell(SPELL.ARCANE_BLAST)
    if display == nil then return nil end
    return display == SPELL.PRISMATIC_BOLT or display == 1295939
end

local function arcaneSoulActive()
    local active = auraAtLeast(SPELL.ARCANE_SOUL, 1)
    if active ~= nil then return active end
    local age = state.surgeCastAt and (now() - state.surgeCastAt) or nil
    if age and age >= 0 and age < 12 then return false end
    if not state.surgeCastAt and state.cleanAuraBaseline then return false end
    return nil
end

local function surgeWindow()
    -- Exact fast path: a successful Surge cast guarantees that its base 15 s
    -- aura is still active for the first 12 s.  No extension can shorten it.
    if state.surgeCastAt and now() - state.surgeCastAt >= 0
        and now() - state.surgeCastAt < 12 then
        return true, nil
    end

    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and BlizzardAPI and BlizzardAPI.GetAuraDurationObject
            and BlizzardAPI.IsDurationBelowSeconds) then
        return nil, nil
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SPELL.ARCANE_SURGE)
    if not ok then return nil, nil end
    if aura ~= nil and type(aura) ~= "table" then return nil, nil end
    if not aura or not isPlain(aura.auraInstanceID, "number") then
        local secret = callBoolean("AreAurasSecret")
        if secret == true or secret == nil then return nil, nil end
        return false, false
    end
    local okDuration, duration = pcall(BlizzardAPI.GetAuraDurationObject,
        "player", aura.auraInstanceID)
    if not okDuration then return true, nil end
    if not duration then return true, nil end
    local okBelow, below = pcall(BlizzardAPI.IsDurationBelowSeconds, duration, 12)
    if okBelow and isPlain(below, "boolean") then return true, below end
    return true, nil
end

-- The capped-Salvo Sunfury Barrage branch requires Surge to be down or to
-- have more than gcd.max remaining.  A Mage GCD cannot exceed 1.5 seconds, so
-- a plain >1.5 s duration result is a sufficient (conservative) proof.  The
-- first 12 seconds after a confirmed Surge cast are also safe because the
-- non-shortenable base aura still has more than 3 seconds remaining.
local function surgeDownOrSafelyAboveGCD()
    local active = auraAtLeast(SPELL.ARCANE_SURGE, 1)
    if active == false then return true, "surge-down" end

    local age = state.surgeCastAt and (now() - state.surgeCastAt) or nil
    if age and age >= 0 and age < 12 then
        return true, "confirmed-surge-remains>3"
    end

    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and BlizzardAPI and BlizzardAPI.GetAuraDurationObject
            and BlizzardAPI.IsDurationBelowSeconds) then
        return nil, "surge-gcd-window-unknown"
    end
    local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SPELL.ARCANE_SURGE)
    if not okAura or (aura ~= nil and type(aura) ~= "table") then
        return nil, "surge-gcd-window-unknown"
    end
    if not aura then
        local secret = callBoolean("AreAurasSecret")
        if secret == false then return true, "surge-down-observed" end
        return nil, "surge-gcd-window-unknown"
    end
    if not isPlain(aura.auraInstanceID, "number") then
        return nil, "surge-gcd-window-unknown"
    end

    local okDuration, duration = pcall(BlizzardAPI.GetAuraDurationObject,
        "player", aura.auraInstanceID)
    if not okDuration or not duration then return nil, "surge-gcd-window-unknown" end
    -- 1.51 deliberately leaves a small strictness margin: `not below 1.5`
    -- could include the exact equality point, while SimC requires `> gcd.max`.
    local okBelow, below = pcall(BlizzardAPI.IsDurationBelowSeconds, duration, 1.51)
    if not okBelow or not isPlain(below, "boolean") then
        return nil, "surge-gcd-window-unknown"
    end
    return not below, below and "surge-remains<1.51" or "surge-remains>=1.51"
end

local function lustrousGate()
    local atLeastTwo = auraAtLeast(SPELL.LUSTROUS_GLEAM, 2)
    if atLeastTwo == true then return true, "lustrous>=2" end

    local atLeastOne = auraAtLeast(SPELL.LUSTROUS_GLEAM, 1)
    if atLeastOne == true and atLeastTwo == false then
        return false, "lustrous=1"
    end
    if atLeastOne == false then
        return true, "lustrous-missing"
    end

    -- Liquid Luster is the only source of this gate.  Its successful use is a
    -- plain player spellcast event.  From that event until the 30 s applicator
    -- plus the final 30 s Gleam can have expired, unreadable stacks are unknown.
    local castAge = state.liquidLusterCastAt and (now() - state.liquidLusterCastAt) or nil
    if castAge and castAge >= 0 and castAge <= 61 then
        return nil, "lustrous-secret-after-potion"
    end

    -- We have observed a clean, out-of-combat baseline and every subsequent
    -- Liquid Luster cast since it.  With no such cast in its maximum window,
    -- the aura is provably absent even if combat aura enumeration is hidden.
    if state.cleanAuraBaseline then
        return true, "lustrous-missing-observed"
    end
    return nil, "lustrous-unknown"
end

-- User-required cooldown ordering, deliberately identical in evidence quality
-- to Frostwyrm after Pillar: only a newer successful Touch event may release
-- Surge, and that proof expires after ten seconds. Cooldown state and a stale
-- historical Touch never count as ordering evidence.
local function touchRecentlyPrecedesSurge()
    local touchAt = state.touchCastAt
    if not touchAt then return false end
    if state.touchCastStep <= state.surgeCastStep then return false end
    local age = now() - touchAt
    return age >= 0 and age < SURGE_AFTER_TOUCH_SECONDS
end

local function withoutSpell(raw, blockedSpellID)
    local result, changed = {}, false
    for _, spellID in ipairs(raw) do
        if spellID == blockedSpellID then
            changed = true
        else
            result[#result + 1] = spellID
        end
    end
    return changed and result or raw
end

local function appendFallback(first, raw)
    local result, seen = {}, {}
    if first then
        result[1], seen[first] = first, true
    end
    for i = 1, #raw do
        local value = raw[i]
        if type(value) == "number" and not seen[value] then
            result[#result + 1], seen[value] = value, true
        end
    end
    return result
end

local function choose(spellID, rule, detail, raw)
    state.selectedSpellID = spellID
    state.decision = ("owner=arcane121 action=%s rule=%s detail=%s fallback=false")
        :format(tostring(spellID), tostring(rule), tostring(detail or "ok"))
    return appendFallback(spellID, raw)
end

local function fallback(reason, raw)
    state.selectedSpellID = nil
    state.decision = ("owner=arcane121 action=nil rule=fallback.justac reason=%s fallback=true")
        :format(tostring(reason or "no-proven-action"))
    return raw
end

-- A delegated JustAC queue can place Barrage ahead of Blast as a generic
-- instant fallback even when Barrage was not selected by a proven Arcane APL
-- branch. Under secret aura state that can make either held key dump charges
-- forever. Put the known baseline filler Blast before that unproven Barrage for
-- both routes, inserting it when JustAC's four-entry fallback omitted it. The
-- core will then use Blast while stationary and
-- naturally skip its hardcast back to Barrage while moving. This deliberately
-- sacrifices unknown optimal Barrage windows rather than pretending we can
-- read them; source-owned proven Barrage decisions never pass through here.
local function buildConservativeFallback(raw)
    if not isKnown(SPELL.ARCANE_BLAST) then return raw end
    local barrageIndex, blastIndex
    for index, spellID in ipairs(raw) do
        if spellID == SPELL.ARCANE_BARRAGE and not barrageIndex then
            barrageIndex = index
        elseif spellID == SPELL.ARCANE_BLAST and not blastIndex then
            blastIndex = index
        end
    end
    if not barrageIndex or (blastIndex and blastIndex < barrageIndex) then
        return raw
    end

    local result = {}
    for index, spellID in ipairs(raw) do
        if not blastIndex and index == barrageIndex then
            result[#result + 1] = SPELL.ARCANE_BLAST
            result[#result + 1] = SPELL.ARCANE_BARRAGE
        elseif index ~= barrageIndex then
            result[#result + 1] = spellID
            if blastIndex and index == blastIndex then
                result[#result + 1] = SPELL.ARCANE_BARRAGE
            end
        end
    end
    return result
end

local function selectQueue(raw, preserve)
    if not isArcane121() then return fallback("outside-mage-arcane-12.1", raw) end
    local hero = heroTree()
    if not hero then return fallback("hero-tree-unknown", raw) end

    local combat = inCombat()

    -- This project intentionally diverges from SimC's Sunfury precombat Surge:
    -- Surge may never precede a newly successful Touch, so it is not injected
    -- before combat. The policy sequence gate also removes any raw JustAC Surge.
    if not combat then return fallback("precombat-surge-waits-touch", raw) end

    -- Spellslinger cooldown list starts with one Arcane Orb per combat.  The
    -- cast event, not a guessed timer, owns line_cd=999. Both modes expose the
    -- same owned Orb decision; the policy layer suppresses it while moving,
    -- applies M4's stationary delay and applies both routes' Blink delay.
    if hero == "spellslinger" then
        local orbUsed = state.orbCastAt and now() - state.orbCastAt < 900
        if not orbUsed then
            local ready = spellReady(SPELL.ARCANE_ORB)
            if ready == true then
                return choose(SPELL.ARCANE_ORB, "cooldowns.arcane_orb", "spellslinger-line-cd", raw)
            elseif ready == nil then
                return fallback("orb-readiness-unknown", raw)
            end
        end
    end

    local previousSetsTouch = state.lastGCDSpellID == SPELL.PRISMATIC_BOLT
        or state.lastGCDSpellID == 1295939
        or state.lastGCDSpellID == SPELL.ARCANE_BARRAGE
    local surgeReady
    if not preserve then
        surgeReady = spellReady(SPELL.ARCANE_SURGE)
        if surgeReady == nil then return fallback("surge-readiness-unknown", raw) end
    end

    -- The original observable Touch branch remains valid while Surge is
    -- already active. The custom sync adds a second exact branch: when Surge
    -- is ready but lacks a recent Touch token, the next proven Bolt/Barrage
    -- setup releases Touch first. Touch's successful event then unlocks Surge.
    if not preserve and previousSetsTouch then
        local surgeActive = surgeWindow()
        if surgeActive == true
            or (surgeReady == true and not touchRecentlyPrecedesSurge()) then
            local ready = spellReady(SPELL.TOUCH_OF_THE_MAGI)
            if ready == true then
                return choose(SPELL.TOUCH_OF_THE_MAGI, "cooldowns.touch_of_the_magi",
                    surgeActive == true and "prev-bolt-or-barrage+surge"
                        or "prev-bolt-or-barrage+surge-ready-first", raw)
            elseif ready == nil then
                return fallback("touch-readiness-unknown", raw)
            end
        elseif surgeActive == nil and callBoolean("IsSpellOnCooldown", SPELL.ARCANE_SURGE) == true then
            return fallback("touch-surge-window-unknown", raw)
        end
    end

    if not preserve and surgeReady then
        if touchRecentlyPrecedesSurge() then
            local gate, detail = lustrousGate()
            if gate == true then
                return choose(SPELL.ARCANE_SURGE, "cooldowns.arcane_surge",
                    "after-touch+" .. detail, raw)
            elseif gate == nil then
                return fallback(detail, raw)
            end
            -- A proven single Gleam stack still holds Surge. Because the recent
            -- Touch token would otherwise make the generic sequence gate admit
            -- a raw JustAC Surge, remove only Surge from this fallback queue.
            return fallback(detail, withoutSpell(raw, SPELL.ARCANE_SURGE))
        end
        -- No recent successful Touch: continue the normal owned list while the
        -- policy sequence gate independently blocks any raw/source Surge.
    end

    -- Sunfury's first normal-list line is fully observable when Missiles has
    -- the engine proc glow and Arcane Salvo is positively below 12 stacks.
    -- At/above 12 the APL continues to several dynamic lines; unknown never
    -- falls through to a guessed lower action.
    if hero == "sunfury" then
        local clearcasting = callBoolean("IsSpellProcced", SPELL.ARCANE_MISSILES)
        if clearcasting == nil then return fallback("clearcasting-unknown", raw) end
        if clearcasting then
            local salvoAtLeast12 = auraAtLeast(SPELL.ARCANE_SALVO, 12)
            if salvoAtLeast12 == false then
                local ready = spellReady(SPELL.ARCANE_MISSILES)
                if ready == true then
                    return choose(SPELL.ARCANE_MISSILES, "sunfury.arcane_missiles",
                        "clearcasting+salvo<12", raw)
                elseif ready == nil then
                    return fallback("missiles-readiness-unknown", raw)
                end
            elseif salvoAtLeast12 == nil then
                return fallback("arcane-salvo<12-unknown", raw)
            end
        end
    end

    local charges = classResource()
    if charges == nil then return fallback("arcane-charges-unknown", raw) end

    if hero == "spellslinger" then
        local bolt = prismaticBoltActive()
        if bolt == nil then return fallback("prismatic-bolt-state-unknown", raw) end

        -- First Prismatic Bolt line: implement the target-count-independent
        -- Salvo>13 branch. Other branches remain a hard fallback barrier.
        if bolt then
            local salvo14 = auraAtLeast(SPELL.ARCANE_SALVO, 14)
            if salvo14 == true then
                return choose(SPELL.PRISMATIC_BOLT, "spellslinger.prismatic_bolt",
                    "arcane-salvo>13", raw)
            end
            -- Salvo>13 is one sufficient OR branch. When it is false, the
            -- set-bonus/enemy/Clearcasting branch can still win; do not jump
            -- past the first APL line without all of those inputs.
            return fallback("spellslinger-first-bolt-other-branches-unknown", raw)
        end

        -- The intervening Orb line requires both Orb Mastery and an exact AoE
        -- count. If the talent is absent or Orb cannot be cast it is proven
        -- false; otherwise do not jump past it on a guessed enemy count.
        if isKnown(1243435) then
            local orbReady = spellReady(SPELL.ARCANE_ORB)
            if orbReady == nil then return fallback("spellslinger-orb-readiness-unknown", raw) end
            if orbReady then return fallback("spellslinger-orb-aoe-count-unknown", raw) end
        end

        -- Barrage branches that are independent of enemy count.
        local orbBarrage = isKnown(SPELL.ORB_BARRAGE)
        local firstThreshold = orbBarrage and 19 or 20
        local surgeThreshold = orbBarrage and 15 or 10
        local salvoFirst = auraAtLeast(SPELL.ARCANE_SALVO, firstThreshold)
        local salvoSurge = auraAtLeast(SPELL.ARCANE_SALVO, surgeThreshold)
        if state.lastGCDSpellID == SPELL.ARCANE_SURGE and salvoSurge == true then
            local ready = spellReady(SPELL.ARCANE_BARRAGE)
            if ready == true then
                return choose(SPELL.ARCANE_BARRAGE, "spellslinger.arcane_barrage",
                    "prev-surge+salvo-threshold", raw)
            elseif ready == nil then return fallback("barrage-readiness-unknown", raw) end
        elseif salvoFirst == true and charges == 4 then
            local ready = spellReady(SPELL.ARCANE_BARRAGE)
            if ready == true then
                return choose(SPELL.ARCANE_BARRAGE, "spellslinger.arcane_barrage",
                    "four-charges+salvo-threshold", raw)
            elseif ready == nil then return fallback("barrage-readiness-unknown", raw) end
        elseif salvoFirst == nil or (state.lastGCDSpellID == SPELL.ARCANE_SURGE and salvoSurge == nil) then
            return fallback("spellslinger-barrage-condition-unknown", raw)
        elseif salvoFirst == true and charges ~= 4 then
            return fallback("spellslinger-barrage-enemy-count-unknown", raw)
        end

        local clearcasting = callBoolean("IsSpellProcced", SPELL.ARCANE_MISSILES)
        if clearcasting == nil then return fallback("clearcasting-unknown", raw) end
        if clearcasting then
            local salvo15 = auraAtLeast(SPELL.ARCANE_SALVO, 15)
            if salvo15 == false then
                local ready = spellReady(SPELL.ARCANE_MISSILES)
                if ready == true then
                    return choose(SPELL.ARCANE_MISSILES, "spellslinger.arcane_missiles",
                        "clearcasting+salvo<15", raw)
                elseif ready == nil then return fallback("missiles-readiness-unknown", raw) end
            elseif salvo15 == nil then
                return fallback("spellslinger-missiles-condition-unknown", raw)
            else
                local clearcasting3 = auraAtLeast(SPELL.CLEARCASTING, 3)
                if clearcasting3 == nil or clearcasting3 == true then
                    return fallback("spellslinger-missiles-aoe-condition-unknown", raw)
                end
            end
        end

        if bolt then
            return choose(SPELL.PRISMATIC_BOLT, "spellslinger.prismatic_bolt",
                "unconditional-bolt", raw)
        end

        local orbReady = spellReady(SPELL.ARCANE_ORB)
        if orbReady == nil then return fallback("orb-readiness-unknown", raw) end
        if orbReady and charges < 3 then
            return choose(SPELL.ARCANE_ORB, "spellslinger.arcane_orb", "charges<3", raw)
        elseif orbReady then
            return fallback("spellslinger-lower-orb-condition-unknown", raw)
        end

        local surgeActive = surgeWindow()
        if charges < 3 then
            if surgeActive == nil then return fallback("arcane-surge-window-unknown", raw) end
            if surgeActive == false then
                local ready = spellReady(SPELL.ARCANE_PULSE)
                if ready == true then
                    return choose(SPELL.ARCANE_PULSE, "spellslinger.arcane_pulse",
                        "charges<3+surge-down", raw)
                elseif ready == nil then return fallback("pulse-readiness-unknown", raw) end
            end
        end

        local blastReady = spellReady(SPELL.ARCANE_BLAST)
        if blastReady == true then
            return choose(SPELL.ARCANE_BLAST, "spellslinger.arcane_blast", "terminal", raw)
        end
        return fallback(blastReady == nil and "blast-readiness-unknown" or "no-spellslinger-action", raw)
    end

    -- Sunfury: own the target-count-independent branches before delegating any
    -- remaining enemy-count/charge-fraction condition.
    local bolt = prismaticBoltActive()
    if bolt == nil then return fallback("prismatic-bolt-state-unknown", raw) end
    local soul = arcaneSoulActive()
    if soul == nil then return fallback("arcane-soul-state-unknown", raw) end
    if bolt then
        local cumulative8 = auraAtLeast(SPELL.CUMULATIVE_POWER, 8)
        if soul == false and cumulative8 == true then
            return choose(SPELL.PRISMATIC_BOLT, "sunfury.prismatic_bolt",
                "cumulative=8+soul-down", raw)
        end
        -- IsPlayerSpell(false) cannot distinguish "no 4pc" from an item-set
        -- passive the spellbook API does not expose. The !set_bonus branch is
        -- therefore unknown unless a separate exact equipment reader exists.
        return fallback("sunfury-first-bolt-set-bonus-unknown", raw)
    end

    local salvo9 = auraAtLeast(SPELL.ARCANE_SALVO, 9)
    local touchReady = spellReady(SPELL.TOUCH_OF_THE_MAGI)
    local touchBranch
    if salvo9 == true and touchReady == true then
        touchBranch = true
    elseif salvo9 == false or touchReady == false then
        touchBranch = false
    end
    if soul == true or touchBranch == true then
        local ready = spellReady(SPELL.ARCANE_BARRAGE)
        if ready == true then
            return choose(SPELL.ARCANE_BARRAGE, "sunfury.arcane_barrage",
                soul and "arcane-soul" or "salvo>8+touch-ready", raw)
        elseif ready == nil then return fallback("barrage-readiness-unknown", raw) end
    elseif touchBranch == nil then
        return fallback("sunfury-barrage-condition-unknown", raw)
    end

    if charges == 4 then
        -- Current Sunfury APL has an independent capped-Salvo release even
        -- without Clearcasting. Arcane Salvo caps at 25, so >=25 is exact.
        local salvo25 = auraAtLeast(SPELL.ARCANE_SALVO, 25)
        if salvo25 == nil then return fallback("sunfury-salvo-25-state-unknown", raw) end
        if salvo25 then
            local surgeGate, detail = surgeDownOrSafelyAboveGCD()
            if surgeGate == true then
                local ready = spellReady(SPELL.ARCANE_BARRAGE)
                if ready == true then
                    return choose(SPELL.ARCANE_BARRAGE, "sunfury.arcane_barrage",
                        "four-charges+salvo=25+" .. detail, raw)
                elseif ready == nil then return fallback("barrage-readiness-unknown", raw) end
            elseif surgeGate == nil then
                return fallback(detail, raw)
            end
        end

        local salvo12 = auraAtLeast(SPELL.ARCANE_SALVO, 12)
        if salvo12 == nil then return fallback("sunfury-complex-barrage-unknown", raw) end
        if salvo12 == true then
            local clearcasting = callBoolean("IsSpellProcced", SPELL.ARCANE_MISSILES)
            if clearcasting == true then
                local ready = spellReady(SPELL.ARCANE_BARRAGE)
                if ready == true then
                    return choose(SPELL.ARCANE_BARRAGE, "sunfury.arcane_barrage",
                        "four-charges+clearcasting+salvo>=12", raw)
                elseif ready == nil then return fallback("barrage-readiness-unknown", raw) end
            end
            return fallback("sunfury-complex-barrage-enemy-state", raw)
        end
    end

    if bolt then
        return choose(SPELL.PRISMATIC_BOLT, "sunfury.prismatic_bolt", "unconditional-bolt", raw)
    end

    local orbReady = spellReady(SPELL.ARCANE_ORB)
    if orbReady == nil then return fallback("orb-readiness-unknown", raw) end
    if charges < 1 and orbReady then
        return choose(SPELL.ARCANE_ORB, "sunfury.arcane_orb", "charges<1", raw)
    end

    local pulseReady = spellReady(SPELL.ARCANE_PULSE)
    if pulseReady == nil then return fallback("pulse-readiness-unknown", raw) end
    if charges < 1 and pulseReady then
        return choose(SPELL.ARCANE_PULSE, "sunfury.arcane_pulse", "charges<1", raw)
    elseif pulseReady then
        return fallback("sunfury-pulse-enemy-count-unknown", raw)
    end

    local blastReady = spellReady(SPELL.ARCANE_BLAST)
    if blastReady == true then
        return choose(SPELL.ARCANE_BLAST, "sunfury.arcane_blast", "terminal", raw)
    end
    return fallback(blastReady == nil and "blast-readiness-unknown" or "no-sunfury-action", raw)

end

local Source = {
    name = "奥法 12.1 自有循环（JustAC 兜底）",
}

function Source.Initialize()
    local libStub = _G.LibStub
    if not libStub then return false, "LibStub unavailable" end
    SpellQueue = libStub("JustAC-SpellQueue", true)
    BlizzardAPI = libStub("JustAC-BlizzardAPI", true)
    if not SpellQueue then return false, "JustAC-SpellQueue unavailable" end
    if not BlizzardAPI then return false, "JustAC-BlizzardAPI unavailable" end

    state.cleanAuraBaseline = not inCombat()
    local frame = CreateFrame and CreateFrame("Frame")
    if frame then
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        frame:SetScript("OnEvent", function(_, event, _, _, spellID)
            if event == "PLAYER_REGEN_ENABLED" then
                state.cleanAuraBaseline = true
                state.orbCastAt = nil
                state.castSequenceSerial = 0
                state.touchCastAt = nil
                state.touchCastStep = 0
                state.surgeCastAt = nil
                state.surgeCastStep = 0
                state.lastGCDSpellID = nil
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if not isPlain(spellID, "number") then return end
                if spellID == SPELL.LIQUID_LUSTER then state.liquidLusterCastAt = now() end
                if spellID == SPELL.TOUCH_OF_THE_MAGI
                    or spellID == SPELL.ARCANE_SURGE then
                    state.castSequenceSerial = state.castSequenceSerial + 1
                    if spellID == SPELL.TOUCH_OF_THE_MAGI then
                        state.touchCastAt = now()
                        state.touchCastStep = state.castSequenceSerial
                    else
                        state.surgeCastAt = now()
                        state.surgeCastStep = state.castSequenceSerial
                    end
                end
                if spellID == SPELL.ARCANE_ORB then state.orbCastAt = now() end
                if GCD_SPELLS[spellID] then state.lastGCDSpellID = spellID end
            end
        end)
        Source._eventFrame = frame
    end
    return true
end

function Source.IsAvailable()
    return SpellQueue ~= nil and BlizzardAPI ~= nil
end

local function rawQueue()
    if not SpellQueue or type(SpellQueue.GetCurrentSpellQueue) ~= "function" then
        return {}
    end
    local ok, value = pcall(SpellQueue.GetCurrentSpellQueue)
    return ok and type(value) == "table" and value or {}
end

function Source.GetQueue()
    local raw = rawQueue()
    local selected = selectQueue(raw, false)
    if selected == raw then
        local adjusted = buildConservativeFallback(raw)
        if adjusted ~= raw then
            state.decision = state.decision
                .. " conservativeFallback=blast-before-unproven-barrage"
        end
        return adjusted
    end
    return selected
end

function Source.GetPreserveQueue()
    local raw = rawQueue()
    local selected = selectQueue(raw, true)
    if selected == raw then
        local adjusted = buildConservativeFallback(raw)
        if adjusted ~= raw then
            state.decision = state.decision
                .. " conservativeFallback=blast-before-unproven-barrage"
        end
        return adjusted
    end
    return selected
end

function Source.GetDecisionTrace()
    return state.decision
end

-- Test seam: pure selection and tracker state, never used by the live core.
Source._Test = {
    spell = SPELL,
    state = state,
    selectQueue = selectQueue,
    buildConservativeFallback = buildConservativeFallback,
}

Registry.Register("arcane121", Source)
