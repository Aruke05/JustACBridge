-- Beast Mastery 12.1 M5: exact current evidence, never a guessed cast cycle.
-- Reference: SimC midnight beast_mastery (NOT beast_mastery_ptr), 2026-10-08.
-- Unknown higher rows return the original JustAC queue, without reordering.
-- M4 stays raw. No cooldown/charge/aura answers are retained between frames.
local Registry = _G.JustACBridgeRecommendationSources
local Runtime = _G.JustACBridge121Runtime
if not (Registry and Runtime) then return end

local SPELL = {
    BARBED_SHOT = 217200, BESTIAL_WRATH = 19574, KILL_COMMAND = 34026,
    COBRA_SHOT = 193455, WILD_THRASH = 1264359, WILD_THRASH_BASE = 1264355,
    BLACK_ARROW = 466930, WAILING_ARROW = 392060,
    BEAST_CLEAVE_TALENT = 115939, BEAST_CLEAVE = 268877,
    COBRA_FANG = 1299389, HOWL_OF_THE_PACK_LEADER_TALENT = 471876,
    HOWL_OF_THE_PACK_LEADER = 471878, HOWL_BOAR = 472324, HOWL_BEAR = 472325,
    HOWL_COOLDOWN = 471877, BLACK_ARROW_TALENT = 466932,
    NATURES_ALLY_TALENT = 1273126, NATURES_ALLY = 1276720,
    MASTER_HANDLER = 424558, SERPENTINE_STRIKES = 468701,
}
local GCD = {}
for _, key in ipairs({"BARBED_SHOT", "BESTIAL_WRATH", "KILL_COMMAND", "COBRA_SHOT",
    "WILD_THRASH", "WILD_THRASH_BASE", "BLACK_ARROW", "WAILING_ARROW"}) do GCD[SPELL[key]] = true end
local context = Runtime.New("bmhunter121", "HUNTER", 1, GCD)
local scanner

local function plain(v, kind)
    return not (issecretvalue and issecretvalue(v)) and type(v) == kind
end
local function number(v)
    return plain(v, "number") and v == v and v >= 0 and v < math.huge
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function method(object, name)
    if not (plain(object, "table") or plain(object, "userdata")) then return nil end
    return call(function() return object[name](object) end)
end
local function either(a, b)
    if a == true or b == true then return true end
    if a == false and b == false then return false end
end
local function both(a, b)
    if a == false or b == false then return false end
    if a == true and b == true then return true end
end
local function known(id)
    local sequence = _G.JustACBridgeActionSequence
    if not sequence then return nil end
    local readers = {}
    if type(IsPlayerSpell) == "function" then readers[#readers + 1] = IsPlayerSpell end
    if type(IsSpellKnown) == "function" then readers[#readers + 1] = IsSpellKnown end
    return sequence.Ownership({id}, readers)
end
local function bound(id)
    local value = call(scanner and scanner.GetSpellHotkey, id)
    if plain(value, "string") then return value ~= "" end
end
local function eligible(id)
    return both(known(id), bound(id))
end
local function strictUsable(id)
    local usable, noPower = call(C_Spell and C_Spell.IsSpellUsable, id)
    if plain(usable, "boolean") and plain(noPower, "boolean") then
        return usable and not noPower
    end
    local adapter = Registry.Get("justac", false)
    usable, noPower = call(adapter and adapter.IsSpellUsableStrict, id)
    if plain(usable, "boolean") and plain(noPower, "boolean") then
        return usable and not noPower
    end
end
local function cooldownRemaining(id)
    local duration = call(C_Spell and C_Spell.GetSpellCooldownDuration, id, true)
    local remaining = method(duration, "GetRemainingDuration")
    if number(remaining) then return remaining end
end
local function cooldownBelow(id, threshold)
    local prep = _G.JustACBridgeResourcePreparation
    if prep and number(threshold) and threshold > 0 then
        return prep.CooldownBelow(id, threshold,
            function(name, value)
                local adapter = Registry.Get("justac", false)
                if name ~= "ReadBinaryPredicate" or not adapter then return false end
                local fn = adapter.ReadBinaryPredicate
                if type(fn) ~= "function" then return false end
                local ok, result = pcall(fn, value)
                return ok, result
            end)
    end
end
local function cooldownAbove(id, threshold)
    -- Only a live exact value is used here; no rounded duration helper.
    local remaining = cooldownRemaining(id)
    if remaining ~= nil and number(threshold) then return remaining > threshold end
end
local function currentGCD()
    local haste = call(GetHaste)
    local sequence = _G.JustACBridgeActionSequence
    -- A lower bound can admit a sequence, but CANNOT exclude an APL row.
    if sequence and number(haste) then return sequence.HastedGCD(1.5, 0.75, haste) end
end

local function chargeState(id)
    local info = call(C_Spell and C_Spell.GetSpellCharges, id)
    if not plain(info, "table") then return nil end
    local count, maximum = info.currentCharges, info.maxCharges
    if not number(count) or not number(maximum) or count % 1 ~= 0
        or maximum % 1 ~= 0 or maximum < 1 or count > maximum then return nil end
    local result = {count = count, maximum = maximum}
    if count == maximum then result.full, result.fractional = 0, count; return result end
    local start, duration, rate = info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
    local now = call(GetTime)
    -- Non-unit rate or stale/hidden timestamps do not prove full_recharge_time.
    -- Never use a single-charge cooldown as if it were the full recharge.
    if not number(start) or not number(duration) or duration <= 0 or not plain(rate, "number") or rate ~= 1 or not number(now) or start > now then return result end
    local remaining = start + duration - now
    if remaining <= 0 or remaining > duration then return result end
    result.full = remaining + (maximum - count - 1) * duration
    result.fractional = count + (1 - remaining / duration)
    return result
end
local function ready(id)
    local allowed = eligible(id)
    if allowed ~= true then return allowed end
    local usable = strictUsable(id)
    if usable == false then return false end
    if usable ~= true then return nil end
    if id == SPELL.BARBED_SHOT or id == SPELL.KILL_COMMAND then
        local charges = chargeState(id)
        if charges then return charges.count > 0 end
        -- Same secret-safe charge-aware capability used by Arcane Orb.
        -- IsSpellOnCooldown is intentionally NOT consulted for charged spells.
        return context:CallBoolean("IsSpellReady", id)
    end
    local remaining = cooldownRemaining(id)
    if remaining ~= nil then return remaining == 0 end
end
local function fullRecharge(id)
    local charges = chargeState(id)
    -- A current native non-full count rules out a wrapper's cached "full".
    -- Hidden recharge timing cannot turn 1/2 into full_recharge_time=0.
    if charges then return charges.full end
    if context:AtMaxCharges(id) == true then return 0 end
end
local function capSoon(id, gcd)
    local full = fullRecharge(id)
    if full == 0 then return true end
    if full ~= nil and gcd then return full < gcd end
end
local function auraRemaining(id)
    local up = context:AuraUp("player", id)
    if up == false then return 0 end
    if up ~= true then return nil end
    local aura = call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not plain(aura, "table") or not number(aura.auraInstanceID) then return nil end
    local api = context.BlizzardAPI
    local duration = call(api and api.GetAuraDurationObject, "player", aura.auraInstanceID)
    local remaining = method(duration, "GetRemainingDuration")
    if number(remaining) then return remaining end
end
-- Cobra Fang is the BM 12.1 S2 FOUR-piece reward, not an assumed baseline.
-- Count the currently equipped set's BM-specific bonus spell, never item names
-- or a cached gear guess. Four positive slots suffice even if a fifth is unknown.
local function equippedCobraFourPiece()
    context.cobraSet = "unknown"
    if type(GetInventoryItemID) ~= "function" or not C_Item
        or type(C_Item.GetSetBonusesForSpecializationByItemID) ~= "function" then return nil end
    local pieces, unknown = 0, false
    for _, slot in ipairs({1, 3, 5, 7, 10}) do
        local ok, id = pcall(GetInventoryItemID, "player", slot)
        if not ok or not plain(id, "nil") and (not number(id) or id <= 0 or id % 1 ~= 0) then
            unknown = true
        elseif id ~= nil then
            local bonuses = call(C_Item.GetSetBonusesForSpecializationByItemID, 253, id)
            if not plain(bonuses, "table") then unknown = true
            else
                local belongs = false
                for _, bonus in ipairs(bonuses) do
                    if not number(bonus) then unknown = true
                    elseif bonus == 1296632 then belongs = true end
                end
                if belongs then pieces = pieces + 1 end
            end
        end
    end
    if pieces >= 4 then context.cobraSet = "4pc"; return true end
    if unknown then return nil end
    context.cobraSet = pieces >= 2 and "2pc" or "none"
    return false
end
local function chooseCobraFang(rule, detail, raw)
    local fourPiece = equippedCobraFourPiece()
    if fourPiece == true then return context:Choose(SPELL.COBRA_SHOT, rule, detail, raw) end
    -- Positive residual aura without proven current equipment is conflicting
    -- evidence, not permission to assume four pieces or erase the proc.
    return context:Fallback(fourPiece == false and "cobra-fang-equipment-conflict"
        or "cobra-fang-equipment-unknown", raw)
end

local function howlReady()
    -- Exact SimC mapping: OR of ALL THREE ready buffs, not the summoned beast
    -- buff, glow, last BW event, or a guessed internal 30-second driver.
    return either(either(context:AuraUp("player", SPELL.HOWL_OF_THE_PACK_LEADER),
        context:AuraUp("player", SPELL.HOWL_BOAR)), context:AuraUp("player", SPELL.HOWL_BEAR))
end
local function thrashID()
    if known(SPELL.WILD_THRASH_BASE) == true then return SPELL.WILD_THRASH_BASE end
    return SPELL.WILD_THRASH
end
local function choose(id, rule, detail, raw)
    return context:Choose(id, rule, detail, raw)
end
local function fallback(reason, raw) return context:Fallback(reason, raw) end

local function singleKillPredicate(gcd)
    local howl = howlReady()
    if howl == true then return true, "howl-ready" end
    local apex = known(SPELL.NATURES_ALLY_TALENT)
    local strengthened = context:AuraUp("player", SPELL.NATURES_ALLY)
    local full = fullRecharge(SPELL.KILL_COMMAND)
    local window
    if strengthened == false then window = false
    elseif strengthened == true and full ~= nil and gcd then
        window = cooldownAbove(SPELL.BESTIAL_WRATH, full + gcd)
    end
    local noApex
    if apex ~= nil then noApex = not apex end
    local damage = either(window, noApex)
    local charges = chargeState(SPELL.KILL_COMMAND)
    local nearCap
    if charges and charges.fractional ~= nil then nearCap = charges.fractional > 1.8 end
    local howlCD = auraRemaining(SPELL.HOWL_COOLDOWN)
    local farHowl
    if howlCD ~= nil then farHowl = howlCD > 4 end
    local bank = either(nearCap, farHowl)
    return either(howl, both(damage, bank)), "natures-ally+recharge+howl-bank"
end

local function selectPackSingle(raw, enemies)
    local gcd = currentGCD()
    local barbed = ready(SPELL.BARBED_SHOT)
    if barbed == nil then return fallback("barbed-shot-readiness-unknown", raw) end
    if barbed then
        local capped = capSoon(SPELL.BARBED_SHOT, gcd)
        local wrathEligible = eligible(SPELL.BESTIAL_WRATH)
        local soon = cooldownBelow(SPELL.BESTIAL_WRATH, gcd)
        -- Missing BW binding/ownership cannot disprove its near-CD APL row.
        -- Nor may we inject preparation for an unavailable follow-up. Delegate
        -- that case; an independent Barbed charge-cap proof can still win.
        if soon == true and wrathEligible ~= true then soon = nil end
        local prep = either(capped, soon)
        if prep == true then
            if enemies ~= 1 then return fallback("barbed-shot-target-if-delegated", raw) end
            return choose(SPELL.BARBED_SHOT, "pack_st.barbed_shot",
                soon == true and "bestial-wrath-near" or "charge-cap-soon", raw)
        elseif prep == nil then return fallback("barbed-shot-recharge-window-delegated", raw) end
    end
    local wrath = ready(SPELL.BESTIAL_WRATH)
    if wrath == nil then return fallback("bestial-wrath-readiness-unknown", raw) end
    if wrath then return choose(SPELL.BESTIAL_WRATH, "pack_st.bestial_wrath", "barbed-prefix-excluded", raw) end
    if enemies > 1 then
        local id = thrashID()
        local thrash = ready(id)
        if thrash == nil then return fallback("wild-thrash-readiness-unknown", raw) end
        if thrash then return choose(id, "pack_st.wild_thrash", "active-enemies>1", raw) end
    end
    local kill = ready(SPELL.KILL_COMMAND)
    if kill == nil then return fallback("kill-command-readiness-unknown", raw) end
    if kill then
        local allowed, reason = singleKillPredicate(gcd)
        if allowed == true then return choose(SPELL.KILL_COMMAND, "pack_st.kill_command", reason, raw) end
        if allowed == nil then return fallback("pack-st-kill-command-predicates-delegated", raw) end
    end
    local cobra = ready(SPELL.COBRA_SHOT)
    if cobra == nil then return fallback("cobra-shot-readiness-unknown", raw) end
    if cobra then
        local fang = context:AuraAtLeast("player", SPELL.COBRA_FANG, 4)
        if fang == true then return chooseCobraFang("pack_st.cobra_shot", "cobra-fang=4", raw) end
        if fang == nil then return fallback("cobra-fang-stack-state-unknown", raw) end
    end
    if barbed then
        -- The lower ST row has no target_if, including the two-target/no-Cleave
        -- table. Only the higher target-scored Barbed row must be delegated.
        local serpentine = known(SPELL.SERPENTINE_STRIKES)
        local lowFocus
        local focus = call(UnitPower, "player", 2)
        if number(focus) then lowFocus = focus < 75 end
        local noSerpentine
        if serpentine ~= nil then noSerpentine = not serpentine end
        local spend = either(serpentine, both(noSerpentine, lowFocus))
        if spend == true then return choose(SPELL.BARBED_SHOT, "pack_st.barbed_shot", "serpentine-or-focus<75", raw) end
        if spend == nil then return fallback("pack-st-barbed-focus-talents-delegated", raw) end
    end
    if cobra and gcd then
        local far = cooldownAbove(SPELL.BESTIAL_WRATH, gcd)
        if far == true then return choose(SPELL.COBRA_SHOT, "pack_st.cobra_shot", "bestial-wrath>gcd", raw) end
    end
    return fallback("pack-st-terminal-timing-delegated", raw)
end

local function selectPackCleave(raw, beastCleaveKnown, enemies)
    local gcd, id = currentGCD(), thrashID()
    local thrash = ready(id)
    if thrash == nil then return fallback("wild-thrash-readiness-unknown", raw) end
    local cleave
    if beastCleaveKnown then cleave = context:AuraUp("player", SPELL.BEAST_CLEAVE) end
    if beastCleaveKnown and thrash then
        if context:PreviousGCD(1) == SPELL.BESTIAL_WRATH or cleave == false then
            return choose(id, "pack_cleave.wild_thrash",
                context:PreviousGCD(1) == SPELL.BESTIAL_WRATH and "previous-gcd=bestial-wrath" or "beast-cleave-down", raw)
        end
        if cleave == nil then return fallback("beast-cleave-state-unknown", raw) end
        if context:PreviousGCD(1) == nil then return fallback("previous-gcd-unknown", raw) end
    end
    local barbed = ready(SPELL.BARBED_SHOT)
    if barbed == nil then return fallback("barbed-shot-readiness-unknown", raw) end
    if barbed then
        local capped = capSoon(SPELL.BARBED_SHOT, gcd)
        if capped == true then return fallback("barbed-shot-target-if-delegated", raw) end
        if capped == nil then return fallback("barbed-shot-recharge-window-delegated", raw) end
    end
    local wrath = ready(SPELL.BESTIAL_WRATH)
    if wrath == nil then return fallback("bestial-wrath-readiness-unknown", raw) end
    if wrath then
        local thrashKnown = either(known(SPELL.WILD_THRASH_BASE), known(SPELL.WILD_THRASH))
        local aligned
        if not beastCleaveKnown or thrashKnown == false then aligned = true
        elseif cleave == false then aligned = false
        elseif cleave == true then
            -- buff.remains is not merely buff.up: a listed aura at expiration
            -- or with unreadable duration does not prove this alignment row.
            local cleaveRemaining = auraRemaining(SPELL.BEAST_CLEAVE)
            if cleaveRemaining == 0 then aligned = false
            elseif cleaveRemaining ~= nil then
                aligned = thrash == true and true or cooldownBelow(id, gcd)
            end
        end
        if aligned == true then return choose(SPELL.BESTIAL_WRATH, "pack_cleave.bestial_wrath", "cleave+thrash-aligned", raw) end
        if aligned == nil then return fallback("bestial-wrath-thrash-alignment-unknown", raw) end
    end
    -- Formal live APL row 4: only !talent.beast_cleave. The old source mixed
    -- in Dark Ranger's duration comparison and could mask Pack Leader KC.
    if not beastCleaveKnown and thrash then return choose(id, "pack_cleave.wild_thrash", "beast-cleave-not-talented", raw) end
    local remaining = auraRemaining(SPELL.BEAST_CLEAVE)
    local liveCleaveEnough
    if remaining ~= nil and gcd then liveCleaveEnough = remaining > gcd * 0.25 end
    local cleaveEnough = true
    if beastCleaveKnown then cleaveEnough = liveCleaveEnough end
    local kill = ready(SPELL.KILL_COMMAND)
    if kill == nil then return fallback("kill-command-readiness-unknown", raw) end
    if kill then
        local nature = context:AuraUp("player", SPELL.NATURES_ALLY)
        local master = known(SPELL.MASTER_HANDLER)
        local howl = howlReady()
        local masterBranch = both(master, enemies > 3 and true or howl)
        local apex = known(SPELL.NATURES_ALLY_TALENT)
        local noApex
        if apex ~= nil then noApex = not apex end
        local allowed = both(either(either(nature, masterBranch), noApex), cleaveEnough)
        if allowed == true then return choose(SPELL.KILL_COMMAND, "pack_cleave.kill_command",
            masterBranch == true and "master-handler+targets-or-howl" or "natures-ally+cleave-duration", raw) end
        if allowed == nil then return fallback("pack-cleave-kill-command-predicates-delegated", raw) end
    end
    local cobra = ready(SPELL.COBRA_SHOT)
    if cobra == nil then return fallback("cobra-shot-readiness-unknown", raw) end
    if cobra then
        local fang = context:AuraUp("player", SPELL.COBRA_FANG)
        local allowed = both(fang, liveCleaveEnough)
        if allowed == true then return chooseCobraFang("pack_cleave.cobra_shot", "cobra-fang+cleave-duration", raw) end
        if allowed == nil then return fallback("cleave-cobra-aura-state-unknown", raw) end
    end
    -- Target scoring for lower Barbed is not observable: never change target.
    if barbed then return fallback("pack-cleave-barbed-target-if-delegated", raw) end
    if cobra and cleaveEnough == true then return choose(SPELL.COBRA_SHOT, "pack_cleave.cobra_shot", "cleave-duration", raw) end
    return fallback("pack-cleave-terminal-timing-delegated", raw)
end

local function currentEnemyCount()
    local api = context.BlizzardAPI
    local value = call(api and api.GetEngagedEnemyCount)
    -- Validate BEFORE normalization: Lua 5.1 math.max can turn NaN into zero,
    -- which the shared runtime would then treat as one hostile target.
    if not number(value) or value % 1 ~= 0 then return nil end
    if value == 0 and context:HasHostileTarget() then return 1 end
    return value
end

local function selectQueue(raw)
    context.cobraSet = "not-read"
    if not context:InScope() then return fallback("outside-bm-hunter-12.1", raw) end
    if not context:InCombat() or not context:HasHostileTarget() then return fallback("precombat-or-no-target", raw) end
    if type(raw[1]) == "number" and raw[1] < 0 then return fallback("active-item-timing-delegated", raw) end
    if type(raw[1]) == "number" and raw[1] > 0 and not GCD[raw[1]] then return fallback("non-rotation-head-delegated", raw) end
    local enemies = currentEnemyCount()
    if not number(enemies) or enemies < 1 then return fallback("enemy-count-unknown", raw) end
    local dark = either(known(SPELL.BLACK_ARROW_TALENT), known(SPELL.BLACK_ARROW))
    if dark ~= false then return fallback(dark == true and "dark-ranger-priority-delegated" or "hero-tree-unknown", raw) end
    if known(SPELL.HOWL_OF_THE_PACK_LEADER_TALENT) ~= true then return fallback("hero-tree-unknown", raw) end
    local beastCleaveKnown = known(SPELL.BEAST_CLEAVE_TALENT)
    if beastCleaveKnown == nil then return fallback("beast-cleave-talent-unknown", raw) end
    if enemies > 2 or beastCleaveKnown and enemies > 1 then return selectPackCleave(raw, beastCleaveKnown, enemies) end
    return selectPackSingle(raw, enemies)
end

local Source = { name = "兽王猎 12.1 可证明切片（JustAC 兜底）" }
function Source.Initialize()
    local ok, reason = context:Initialize()
    if not ok then return ok, reason end
    -- LibStub is normally a table with __call, not a Lua function.
    -- Protect the invocation without rejecting its actual library shape.
    scanner = call(function() return _G.LibStub("JustAC-ActionBarScanner", true) end)
    local frame = context.eventFrame
    if frame then
        local resets = {PLAYER_ENTERING_WORLD=true, PLAYER_SPECIALIZATION_CHANGED=true,
            PLAYER_TALENT_UPDATE=true, TRAIT_CONFIG_UPDATED=true, PLAYER_TARGET_CHANGED=true}
        for event in pairs(resets) do frame:RegisterEvent(event) end
        local previous = frame.GetScript and frame:GetScript("OnEvent")
        frame:SetScript("OnEvent", function(self, event, ...)
            if resets[event] then context.gcdHistory, context.castAt = {}, {}; return end
            if previous and (event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED"
                or event == "UNIT_SPELLCAST_SUCCEEDED" and select(1, ...) == "player") then
                if event == "UNIT_SPELLCAST_SUCCEEDED" then
                    local id = select(3, ...)
                    if not plain(id, "number") or not GCD[id] then
                        -- Unknown utility/item GCD attribution invalidates the
                        -- receipt; never keep BW as the previous GCD by guessing.
                        context.gcdHistory, context.castAt = {}, {}
                        return
                    end
                end
                previous(self, event, ...)
            end
        end)
    end
    return true
end
function Source.IsAvailable() return context:IsAvailable() end
function Source.GetQueue()
    local raw = context:RawQueue()
    local ok, queue = pcall(selectQueue, raw)
    if ok then return queue end
    -- An unexpected observation error must not erase or rewrite JustAC's
    -- current queue. Keep this guard local; other sources are unchanged.
    return fallback("bm-current-evidence-error", raw)
end
function Source.GetPreserveQueue() return context:RawQueue() end
function Source.GetDecisionTrace() return context.decision .. " scope=M5 cobraSet=" .. (context.cobraSet or "not-read") end
Source._Test = {spell=SPELL, context=context, selectQueue=selectQueue, chargeState=chargeState,
    ready=ready, singleKillPredicate=singleKillPredicate, howlReady=howlReady}
Registry.Register("bmhunter121", Source)
