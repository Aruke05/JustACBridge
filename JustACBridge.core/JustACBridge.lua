local ADDON_NAME = ...

-- WoW addons cannot open sockets or write arbitrary files.  This addon therefore
-- exposes live data to other addons through _G.JustACBridge, and exposes data to
-- desktop programs through the JustACBridgeExport SavedVariables table.  The
-- game writes that table to disk on logout or /reload (/jacb flush).

-- Sample once per rendered frame for minimum bridge latency. JustAC applies its
-- own 30/50 ms safety throttle internally, so most calls return its cached table.
local UPDATE_INTERVAL = 0
local ROW_COUNT = 2
local QUEUE_SCAN_COUNT = 8
-- Normal operation remains protocol v3. Diagnostic mode switches to v4 and
-- adds live movement state without affecting ordinary macOS/v3 clients.
local PIXEL_PROTOCOL_VERSION = 3
-- Do not fill WoW's spell queue for the whole SpellQueueWindow.  Waiting until
-- the end of the GCD leaves late procs/target changes time to change JustAC's
-- recommendation while retaining enough margin for the screen-capture bridge.
local QUEUE_COMMIT_WINDOW_MS = 120
local PIXEL_BYTE_COUNT = 72
local PIXEL_BIT_COUNT = PIXEL_BYTE_COUNT * 8
local PIXEL_COLUMNS = 48
local PIXEL_ROWS = 12
local PIXEL_CELL_SIZE = 3
local PIXEL_OFFSET_X = 2
local PIXEL_OFFSET_Y = 7
local HOTKEY_BYTES = 24

JustACBridgeDB = JustACBridgeDB or {}
JustACBridgeExport = JustACBridgeExport or {}

local PolicyRegistry = _G.JustACBridgePolicyRegistry
local SourceRegistry = _G.JustACBridgeRecommendationSources
local GroundEffectTracker = _G.JustACBridgeGroundEffectTracker
local activeSource
local supportSource
local bridgeFrame
local rows = {}
local exportBox
local debugFrame
local debugBox
local statusText
local groundAlertFrame
local groundAlertText
local groundAlertExpiresAt
local pixelFrame
local pixelCells = {}
local elapsed = 0
local sequence = tonumber(JustACBridgeExport.sequence) or 0
local lastSignature
local currentRows = {}
local playerIsChanneling = false
local playerChannelSpellID
local playerIsCasting = false
local playerIsMoving = false
local lastMovementStartedAt = -math.huge
local movementStopPendingUntil = 0
local movementFlapCount = 0
local movementLastDebugAt = -math.huge
local MOVEMENT_FLAP_WINDOW_SECONDS = 0.12
local MOVEMENT_STOP_DEBOUNCE_SECONDS = 0.25
local queueReady = true
local gcdRemainingMs = 0
local reservedSpellIDs = {}
local reserveExcludedSpellIDs = {}
local rotationExcludedSpellIDs = {}
local currentSpecKey
local currentPolicy
local getSpellData
local issecretvalue = issecretvalue
local statusBaseText = ""
local lastStatusText
local groundStatusElapsed = 0
local debugLines = {}
local debugLastSnapshot
local debugLastSnapshotAt = 0
local debugStartedAt = GetTime()
-- Debug snapshots are intentionally verbose.  Keep enough history for the
-- user to finish a pull and copy the log without losing the incident that
-- happened a few minutes earlier.
local DEBUG_MAX_LINES = 3600
local policyFallbackTraces = {}
local failedMovementRecommendations = {}
local debugFailureLastLog = {}
local FAILURE_WINDOW_SECONDS = 0.30
local FAILURE_DUPLICATE_WINDOW_SECONDS = 0.08
local FAILURE_THRESHOLD = 3
local FAILURE_SUPPRESS_SECONDS = 1.00

local PAD_ATLAS_TO_KEY = {
    Gamepad_Gen_1_64 = "PAD1",
    Gamepad_Gen_2_64 = "PAD2",
    Gamepad_Gen_3_64 = "PAD3",
    Gamepad_Gen_4_64 = "PAD4",
    Gamepad_Gen_5_64 = "PAD5",
    Gamepad_Gen_6_64 = "PAD6",
    Gamepad_Ltr_A_64 = "PAD1",
    Gamepad_Ltr_B_64 = "PAD2",
    Gamepad_Ltr_X_64 = "PAD3",
    Gamepad_Ltr_Y_64 = "PAD4",
    Gamepad_Shp_Cross_64 = "PAD1",
    Gamepad_Shp_Circle_64 = "PAD2",
    Gamepad_Shp_Square_64 = "PAD3",
    Gamepad_Shp_Triangle_64 = "PAD4",
    Gamepad_Shp_MicMute_64 = "PAD5",
    Gamepad_Shp_TouchpadR_64 = "PAD6",
}

local function copyTable(source)
    if not source then
        return nil
    end

    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function sourceCall(methodName, ...)
    local source = activeSource
    local method = source and source[methodName]
    if type(method) == "function" then
        local ok, first, second = pcall(method, ...)
        return ok, first, second
    end
    if supportSource and supportSource ~= source then
        method = supportSource[methodName]
        if type(method) == "function" then
            local ok, first, second = pcall(method, ...)
            return ok, first, second
        end
    end
    return false, nil, "unsupported capability: " .. tostring(methodName)
end

local function activateRecommendationSource(preferredID, strict)
    if not SourceRegistry or not SourceRegistry.Select then
        activeSource, supportSource = nil, nil
        return false, "recommendation-source registry unavailable"
    end

    local source, reason
    if strict and preferredID and SourceRegistry.Get then
        source, reason = SourceRegistry.Get(preferredID)
    else
        source, reason = SourceRegistry.Select(preferredID)
    end
    if not source then
        activeSource, supportSource = nil, nil
        return false, reason
    end
    activeSource = source
    supportSource = SourceRegistry.Get and SourceRegistry.Get("justac") or nil
    JustACBridgeDB.recommendationSource = source.id
    return true
end

local function getSpecContext()
    local _, classFile = UnitClass("player")
    local spec = GetSpecialization and GetSpecialization()
    if not classFile or not spec then
        return nil
    end

    local storageKey = classFile .. "_" .. tostring(spec)
    local policy = PolicyRegistry and PolicyRegistry.Resolve
        and PolicyRegistry.Resolve(classFile, spec) or nil
    return storageKey, classFile, spec, policy
end

local function getSpecKey()
    local storageKey = getSpecContext()
    return storageKey
end

local function addReservedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return
    end

    reservedSpellIDs[spellID] = true
    local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
    if ok and type(displayID) == "number" and displayID > 0 then
        reservedSpellIDs[displayID] = true
    end
end

local function removeReservedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return
    end
    reservedSpellIDs[spellID] = nil
    local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
    if ok and type(displayID) == "number" and displayID > 0 then
        reservedSpellIDs[displayID] = nil
    end
end

local function refreshReserveExclusions(spellIDs)
    reserveExcludedSpellIDs = {}
    for _, spellID in ipairs(spellIDs or {}) do
        spellID = tonumber(spellID)
        if spellID and spellID > 0 then
            reserveExcludedSpellIDs[spellID] = true
            local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
            if ok and type(displayID) == "number" and displayID > 0 then
                reserveExcludedSpellIDs[displayID] = true
            end
        end
    end
end

local function refreshRotationExclusions(spellIDs)
    rotationExcludedSpellIDs = {}
    for _, spellID in ipairs(spellIDs or {}) do
        spellID = tonumber(spellID)
        if spellID and spellID > 0 then
            rotationExcludedSpellIDs[spellID] = true
            local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
            if ok and type(displayID) == "number" and displayID > 0 then
                rotationExcludedSpellIDs[displayID] = true
            end
        end
    end
end

local function refreshReservedSpells()
    reservedSpellIDs = {}
    local storageKey, _, _, policy = getSpecContext()
    currentSpecKey = storageKey
    currentPolicy = policy
    refreshReserveExclusions(currentPolicy and currentPolicy.reserveExclusions)
    refreshRotationExclusions(currentPolicy and currentPolicy.rotationExclusions)
    if GroundEffectTracker and GroundEffectTracker.Configure then
        GroundEffectTracker.Configure(
            currentPolicy and currentPolicy.groundEffects or {},
            function(spellID)
                local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
                return ok and displayID or spellID
            end
        )
    end
    if not currentSpecKey then
        return
    end

    for _, spellID in ipairs(currentPolicy and currentPolicy.reserve or {}) do
        addReservedSpell(spellID)
    end

    -- Follow JustAC's current per-spec trigger configuration for every class.
    -- Registered policies add compatibility defaults; unregistered/new classes
    -- still work in JustAC-only mode without changing this bridge core.
    local ok, triggers = sourceCall("GetDetectedBurstTriggers")
    if ok and type(triggers) == "table" then
        for _, trigger in ipairs(triggers) do
            addReservedSpell(type(trigger) == "table" and trigger.spellID or trigger)
        end
    end

    -- A game-version policy may explicitly keep a former burst trigger in the
    -- normal M4 rotation. Apply this after JustAC's detected trigger list so a
    -- stale/default JustAC profile cannot reintroduce a removed interaction.
    -- Player overrides below remain authoritative and can reserve it again.
    for _, spellID in ipairs(currentPolicy and currentPolicy.reservePassthrough or {}) do
        removeReservedSpell(spellID)
    end

    JustACBridgeDB.reserveOverrides = JustACBridgeDB.reserveOverrides or {}
    local overrides = JustACBridgeDB.reserveOverrides[currentSpecKey]
    if overrides then
        for spellID, enabled in pairs(overrides.include or {}) do
            if enabled then
                addReservedSpell(spellID)
            end
        end
        for spellID, excluded in pairs(overrides.exclude or {}) do
            if excluded then
                removeReservedSpell(spellID)
            end
        end
    end
end

local function isReservedQueueValue(queueValue)
    if type(queueValue) ~= "number" or queueValue == 0 then
        return false
    end
    -- Items in an offensive queue are normally potions/on-use trinkets. Keep
    -- all of them for the player's chosen burst window in reserve mode.
    return queueValue < 0 or reservedSpellIDs[queueValue] == true
end

local function isReserveExcludedQueueValue(queueValue)
    return type(queueValue) == "number"
        and queueValue > 0
        and reserveExcludedSpellIDs[queueValue] == true
end

local function isRotationExcludedQueueValue(queueValue)
    return type(queueValue) == "number"
        and queueValue > 0
        and rotationExcludedSpellIDs[queueValue] == true
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function getDisplaySpellID(spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return spellID
    end
    local ok, displayID = sourceCall("GetDisplaySpellID", spellID)
    return ok and type(displayID) == "number" and displayID > 0 and displayID or spellID
end

local function cooldownRemainingSeconds(spellID)
    if type(spellID) ~= "number" or spellID <= 0 or not C_Spell then return nil end
    local displayID = getDisplaySpellID(spellID)
    if C_Spell.GetSpellCharges then
        local ok, charges = pcall(C_Spell.GetSpellCharges, displayID)
        if ok and type(charges) == "table" then
            local current = charges.currentCharges
            if type(current) == "number" and not isSecret(current) then
                if current > 0 then return 0 end
                local start = charges.cooldownStartTime
                local duration = charges.cooldownDuration
                local rate = charges.chargeModRate
                if type(start) == "number" and type(duration) == "number"
                    and not isSecret(start) and not isSecret(duration) then
                    rate = type(rate) == "number" and not isSecret(rate) and rate > 0 and rate or 1
                    return math.max(0, start + duration / rate - GetTime())
                end
            end
        end
    end
    if not C_Spell.GetSpellCooldown then return nil end
    local ok, cooldown = pcall(C_Spell.GetSpellCooldown, displayID)
    if not ok or type(cooldown) ~= "table" then return nil end
    local start = cooldown.startTime
    local duration = cooldown.duration
    local rate = cooldown.modRate
    if type(start) ~= "number" or type(duration) ~= "number"
        or isSecret(start) or isSecret(duration) then return nil end
    if start <= 0 or duration <= 0 then return 0 end
    rate = type(rate) == "number" and not isSecret(rate) and rate > 0 and rate or 1
    return math.max(0, start + duration / rate - GetTime())
end

local function isUsableNow(spellID)
    local ok, isUsable = sourceCall("IsSpellUsable", spellID)
    if ok and isUsable == false then return false end
    local remaining = cooldownRemainingSeconds(spellID)
    return remaining == nil or remaining * 1000 <= QUEUE_COMMIT_WINDOW_MS
end

local function spellListContains(list, spellID)
    spellID = tonumber(spellID)
    if not spellID then
        return false
    end
    local displayID = getDisplaySpellID(spellID)
    for _, configuredID in ipairs(list or {}) do
        if configuredID == spellID or configuredID == displayID
            or getDisplaySpellID(configuredID) == displayID then
            return true
        end
    end
    return false
end

local function policyContains(field, spellID)
    return currentPolicy and spellListContains(currentPolicy[field], spellID) or false
end

local function isPolicyFallbackSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or not currentPolicy then return false end
    local displayID = getDisplaySpellID(spellID)
    for _, rule in ipairs(currentPolicy.fallbackActions or {}) do
        local configuredID = tonumber(type(rule) == "table" and rule.spellID or rule)
        if configuredID and (configuredID == spellID or configuredID == displayID
            or getDisplaySpellID(configuredID) == displayID) then
            return true
        end
    end
    return false
end

local function channelBlocksInput()
    -- Some high-value channels must finish even if WoW emits movement intent
    -- while the channel itself is still preventing actual translation.  In
    -- particular, clipping Ray of Frost after the GCD loses most of the cast.
    local protected = policyContains("protectedChannels", playerChannelSpellID)
    if playerIsChanneling and protected then
        return true
    end
    -- A genuine/attempted movement transition must be allowed to break a
    -- stationary channel.  Midnight can emit STARTED/STOPPED movement pairs
    -- every frame while a channel is preventing translation; blocking input
    -- here would otherwise deadlock the held M4/M5 key until the channel ends.
    return playerIsChanneling and not playerIsMoving
        and not policyContains("clipChannels", playerChannelSpellID)
end

local function resolveChannelSpellID(eventSpellID)
    local resolved = tonumber(eventSpellID)
    if resolved or not UnitChannelInfo then
        return resolved
    end
    local ok, _, _, _, _, _, _, _, queriedSpellID = pcall(UnitChannelInfo, "player")
    return ok and tonumber(queriedSpellID) or nil
end

local function hasMovementCastBuff()
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not getAura or not currentPolicy then
        return false
    end
    for _, auraID in ipairs(currentPolicy.moveCastBuffs or {}) do
        local ok, aura = pcall(getAura, auraID)
        if ok and not isSecret(aura) and aura ~= nil then
            return true
        end
    end
    return false
end

local function isSpellMoveCastableNow(spellID)
    -- Some replacement spells share the base button's proc/highlight state.
    -- Stationary-only policy must win before generic movement buffs or proc
    -- detection, otherwise a hardcast can leak through while moving.
    if policyContains("moveCastNever", spellID) then
        return false
    end
    local instantOnly = policyContains("moveCastInstantOnly", spellID)
    if not instantOnly
        and (policyContains("moveCastAlways", spellID) or hasMovementCastBuff()) then
        return true
    end

    -- Channels and empowered casts commonly report castTime=0 even though
    -- movement interrupts/prevents them. JustAC's channeled-spell registry
    -- explicitly includes Evoker empower spells, so classify it first.
    local ok, channeled = sourceCall("IsChanneled", spellID)
    if ok and channeled == true then
        return false
    end

    local effectiveSpellID = getDisplaySpellID(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo
        and C_Spell.GetSpellInfo(effectiveSpellID)
    local castTime = info and info.castTime
    if type(castTime) == "number" and not isSecret(castTime) and castTime == 0 then
        return true
    end

    -- For ambiguous recommendations, accept only the effective spell form's
    -- live zero cast time. Recommendation glows and movement-casting buffs are
    -- intentionally insufficient for an instant-only rule.
    if instantOnly then
        return false
    end

    -- Spell metadata contains the base cast time.  JustAC's proc signal is the
    -- fallback live indication that a hardcast has currently been converted
    -- to an instant cast. Its implementation also resolves override spell IDs
    -- and fails closed for secret values.
    local procOk, procced = sourceCall("IsSpellProcced", spellID)
    if procOk and procced == true then
        return true
    end
    return false
end

local function isMovementSafeQueueValue(queueValue)
    if JustACBridgeDB.movementFilter == false or not playerIsMoving then
        return true
    end
    if type(queueValue) ~= "number" or queueValue == 0 then
        return false
    end
    return queueValue < 0 or isSpellMoveCastableNow(queueValue)
end

local function isRangeSafeQueueValue(queueValue)
    if JustACBridgeDB.rangeFilter == false
        or type(queueValue) ~= "number" or queueValue <= 0 then
        return true
    end
    local ok, outOfRange = sourceCall("IsConfirmedOutOfRange", queueValue)
    if ok and outOfRange == true then
        return false
    end
    -- nil/secret/unsupported checks fail open.  We only skip an action when
    -- JustAC obtains a definite false from C_Spell.IsSpellInRange.
    return true
end

local function isGroundEffectSafeQueueValue(queueValue)
    if JustACBridgeDB.groundEffectFilter == false
        or type(queueValue) ~= "number" or queueValue <= 0
        or not GroundEffectTracker or not GroundEffectTracker.IsSpellActive then
        return true
    end
    local active, _, rule = GroundEffectTracker.IsSpellActive(queueValue)
    return not active or not rule or rule.suppressRepeat == false
end

local function isFailureSuppressedQueueValue(queueValue)
    if type(queueValue) ~= "number" or queueValue <= 0 then
        return false
    end
    local state = failedMovementRecommendations[queueValue]
    return state and (tonumber(state.suppressUntil) or 0) > GetTime() or false
end

local function isSafeQueueValue(queueValue)
    return not isRotationExcludedQueueValue(queueValue)
        and isMovementSafeQueueValue(queueValue)
        and isRangeSafeQueueValue(queueValue)
        and isGroundEffectSafeQueueValue(queueValue)
        and not isFailureSuppressedQueueValue(queueValue)
end

local function isSpellKnown(spellID)
    if not spellID then
        return true
    end
    local check = IsPlayerSpell or IsSpellKnown
    if not check then
        return false
    end
    local ok, known = pcall(check, spellID)
    if ok and known == true then
        return true
    end
    local displayID = getDisplaySpellID(spellID)
    if displayID ~= spellID then
        ok, known = pcall(check, displayID)
        return ok and known == true
    end
    return false
end

local function findRangeSequenceRecommendation(queue, count)
    local primary = queue[1]
    if JustACBridgeDB.rangeFilter == false or type(primary) ~= "number"
        or primary <= 0 or not currentPolicy then
        return nil
    end

    for _, rule in ipairs(currentPolicy.rangeSequenceRules or {}) do
        local distance = tonumber(rule.beyond)
        local applies = distance and distance > 0
            and spellListContains(rule.defer, primary)
            and isSpellKnown(rule.requiresSpell)
        if applies then
            local ok, within = sourceCall("IsTargetWithin", distance)
            -- Fail open for secret/unknown distance.  The sequence changes only
            -- when JustAC can prove that the target is beyond the guide limit.
            applies = ok and within == false
        else
            applies = false
        end

        if applies then
            for index = 2, count do
                local queueValue = queue[index]
                if type(queueValue) == "number" and queueValue > 0
                    and spellListContains(rule.prefer, queueValue)
                    and isSafeQueueValue(queueValue) and isUsableNow(queueValue) then
                    local data = getSpellData(queueValue, 1)
                    if data and data.plainHotkey ~= "" then
                        data.rangeFallback = true
                        data.sequenceFallback = true
                        data.sequenceReason = "confirmed-beyond-" .. tostring(distance)
                        return data
                    end
                end
            end
        end
    end
    return nil
end

local function findSafeRecommendation(queue)
    local count = math.min(#queue, QUEUE_SCAN_COUNT)
    local sequenceRecommendation = findRangeSequenceRecommendation(queue, count)
    if sequenceRecommendation then
        return sequenceRecommendation
    end
    local primaryMovementBlocked = not isMovementSafeQueueValue(queue[1])
    local primaryRangeBlocked = not isRangeSafeQueueValue(queue[1])
    local primaryGroundBlocked = not isGroundEffectSafeQueueValue(queue[1])
    local primaryFailureBlocked = isFailureSuppressedQueueValue(queue[1])
    local primaryRotationBlocked = isRotationExcludedQueueValue(queue[1])
    for index = 1, count do
        local queueValue = queue[index]
        if type(queueValue) == "number" and queueValue ~= 0
            and isSafeQueueValue(queueValue)
            and (queueValue < 0 or isUsableNow(queueValue)) then
            local data = getSpellData(queueValue, 1)
            -- Preserve the historical behavior for the primary entry, but do
            -- not replace a blocked hardcast with an unusable unbound fallback.
            if data and (index == 1 or data.plainHotkey ~= "") then
                data.movementFallback = index ~= 1 and primaryMovementBlocked
                data.rangeFallback = index ~= 1 and primaryRangeBlocked
                data.groundFallback = index ~= 1 and primaryGroundBlocked
                data.failureFallback = index ~= 1 and primaryFailureBlocked
                data.rotationFallback = index ~= 1 and primaryRotationBlocked
                return data
            end
        end
    end
    return nil
end

local function refreshPlayerMoving()
    if not GetUnitSpeed then
        return
    end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and type(speed) == "number" and not isSecret(speed) then
        playerIsMoving = speed > 0
        movementStopPendingUntil = 0
    elseif movementStopPendingUntil > 0 and GetTime() >= movementStopPendingUntil then
        -- When speed is secret, accept a STOP only after no matching START has
        -- arrived for the debounce interval. Repeated same-frame START/STOP
        -- pairs therefore represent movement intent instead of stationary.
        playerIsMoving = false
        movementStopPendingUntil = 0
        lastSignature = nil
    end
end

local function findReserveRecommendation(queue, startIndex)
    local count = math.min(#queue, QUEUE_SCAN_COUNT)
    for index = startIndex or 1, count do
        local queueValue = queue[index]
        if type(queueValue) == "number" and queueValue > 0
            and not isReservedQueueValue(queueValue)
            and not isReserveExcludedQueueValue(queueValue)
            and isUsableNow(queueValue)
            and isSafeQueueValue(queueValue) then
            local data = getSpellData(queueValue, 2)
            if data and data.plainHotkey ~= "" then
                return data
            end
        end
    end

    if type(queue[1]) ~= "number" or queue[1] == 0 then
        return nil
    end

    -- Highlight mode can expose the next valid Blizzard recommendation when
    -- the primary button is hidden/blacklisted. Use it only as a bounded
    -- fallback; the normal hot path above remains a table scan.
    local ok, spellID = sourceCall("GetHighlightCastSpell")
    if ok and type(spellID) == "number" and spellID > 0
        and spellID ~= queue[1] and not isReservedQueueValue(spellID)
        and not isReserveExcludedQueueValue(spellID)
        and isUsableNow(spellID) and isSafeQueueValue(spellID) then
        local data = getSpellData(spellID, 2)
        if data and data.plainHotkey ~= "" then
            return data
        end
    end

    return nil
end

local function findPolicyFinalFallback(position)
    local trace = {
        position = position,
        moving = playerIsMoving,
        filter = JustACBridgeDB.movementFilter ~= false,
        policy = currentPolicy and currentPolicy.id,
        rules = {},
    }
    policyFallbackTraces[position] = trace
    if not currentPolicy then
        trace.gate = "no-policy"
        return nil
    elseif not currentPolicy.fallbackActions or #currentPolicy.fallbackActions == 0 then
        trace.gate = "no-fallback-actions"
        return nil
    end
    trace.gate = "evaluating"

    local enemyCount = 0
    local enemyOK, detectedEnemies = sourceCall("GetEngagedEnemyCount")
    if enemyOK and type(detectedEnemies) == "number" and not isSecret(detectedEnemies) then
        enemyCount = math.max(0, math.floor(detectedEnemies))
    end
    trace.enemyOK = enemyOK
    trace.enemyCount = enemyCount
    trace.detectedEnemies = detectedEnemies

    for _, configuredRule in ipairs(currentPolicy.fallbackActions) do
        -- Final fallback selection is a core invariant shared by every class
        -- and specialization.  Policies only provide the ordered actions;
        -- the selector must not contain spell- or class-specific branches.
        local rule = type(configuredRule) == "table"
            and configuredRule or { spellID = configuredRule }
        local spellID = tonumber(rule.spellID)
        local minEnemies = tonumber(rule.minEnemies)
        local maxEnemies = tonumber(rule.maxEnemies)
        local enemyEligible = spellID and spellID > 0
            and (not minEnemies or enemyCount >= minEnemies)
            and (not maxEnemies or enemyCount <= maxEnemies)
        local procOK, procced = true, true
        if enemyEligible and rule.requireProc then
            procOK, procced = sourceCall("IsSpellProcced", spellID)
        end
        local eligible = enemyEligible and procOK and procced == true
        local known = spellID and isSpellKnown(spellID) or false
        local reserved = spellID and isReservedQueueValue(spellID) or false
        local excluded = spellID and isReserveExcludedQueueValue(spellID) or false
        local rotationExcluded = spellID and isRotationExcludedQueueValue(spellID) or false
        local movementSafe = spellID and (not playerIsMoving
            or JustACBridgeDB.movementFilter == false
            or isMovementSafeQueueValue(spellID)) or false
        local rangeSafe = spellID and isRangeSafeQueueValue(spellID) or false
        local groundSafe = spellID and isGroundEffectSafeQueueValue(spellID) or false
        local usable = spellID and isUsableNow(spellID) or false
        local ruleTrace = {
            spellID = spellID,
            label = rule.label,
            minEnemies = minEnemies,
            maxEnemies = maxEnemies,
            requireProc = rule.requireProc == true,
            enemyEligible = enemyEligible == true,
            procOK = procOK == true,
            procced = procced == true,
            known = known,
            reserved = reserved,
            excluded = excluded,
            rotationExcluded = rotationExcluded,
            movementSafe = movementSafe,
            rangeSafe = rangeSafe,
            groundSafe = groundSafe,
            usable = usable,
        }
        trace.rules[#trace.rules + 1] = ruleTrace
        -- This is the final action, not another recommendation candidate.
        -- Range/usability failures are deliberately diagnostic-only: when no
        -- normal action exists, M4/M5 must still have a bound fallback to send.
        if eligible and known and not reserved and not excluded
            and not rotationExcluded and movementSafe then
            local data = getSpellData(spellID, position)
            ruleTrace.data = data ~= nil
            ruleTrace.hotkey = data and data.plainHotkey or ""
            if data and data.plainHotkey ~= "" then
                data.finalFallback = true
                data.finalFallbackLabel = rule.label
                data.finalFallbackEnemyCount = enemyCount
                -- Kept for consumers of the 2.10.4 SavedVariables schema.
                data.movementFallback = true
                data.emergencyMovementFallback = true
                data.emergencyFallbackLabel = rule.label
                data.emergencyFallbackEnemyCount = enemyCount
                ruleTrace.selected = true
                trace.selected = spellID
                return data
            end
        end
    end
    return nil
end

local function toPlainHotkey(hotkey)
    if not hotkey or hotkey == "" then
        return ""
    end

    return (hotkey:gsub("|A:([^:]+):.-|a", function(atlas)
        return PAD_ATLAS_TO_KEY[atlas] or ("[" .. atlas .. "]")
    end))
end

getSpellData = function(queueValue, position)
    if type(queueValue) ~= "number" or queueValue == 0 then
        return nil
    end

    local data = {
        position = position,
        queueValue = queueValue,
        kind = queueValue < 0 and "item" or "spell",
        spellID = nil,
        itemID = nil,
        name = "Unknown",
        icon = 134400,
        hotkey = "",
        plainHotkey = "",
    }

    if queueValue < 0 then
        local itemID = -queueValue
        data.itemID = itemID

        if C_Item then
            if C_Item.GetItemNameByID then
                data.name = C_Item.GetItemNameByID(itemID) or data.name
            end
            if C_Item.GetItemIconByID then
                data.icon = C_Item.GetItemIconByID(itemID) or data.icon
            end
        elseif GetItemInfo then
            local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            data.name = name or data.name
            data.icon = icon or data.icon
        end

        local ok, hotkey = sourceCall("GetItemHotkey", itemID)
        data.hotkey = ok and hotkey or ""
    else
        data.spellID = queueValue

        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(queueValue)
        if info then
            data.name = info.name or data.name
            data.icon = info.iconID or data.icon
        end

        local ok, hotkey = sourceCall("GetSpellHotkey", queueValue)
        data.hotkey = ok and hotkey or ""
    end

    data.plainHotkey = toPlainHotkey(data.hotkey)
    return data
end

local function debugSafe(value)
    if isSecret(value) then
        return "<secret>"
    end
    if value == nil then
        return "nil"
    end
    return tostring(value):gsub("[\r\n\t]", " ")
end

local function appendDebug(line)
    if JustACBridgeDB.debugEnabled == false then
        return
    end
    debugLines[#debugLines + 1] = ("[%8.3f] %s"):format(GetTime(), tostring(line))
    while #debugLines > DEBUG_MAX_LINES do
        table.remove(debugLines, 1)
    end
    JustACBridgeExport.debugLog = table.concat(debugLines, "\n")
    if debugBox and debugBox:IsShown() then
        debugBox:SetText(JustACBridgeExport.debugLog)
        debugBox:SetCursorPosition(#JustACBridgeExport.debugLog)
    end
end

local function movementDecision(spellID)
    local displayID = getDisplaySpellID(spellID)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(displayID)
    local castTime = info and info.castTime
    local chOk, channeled = sourceCall("IsChanneled", spellID)
    local procOk, procced = sourceCall("IsSpellProcced", spellID)
    local hotkeyOk, hotkey = sourceCall("GetSpellHotkey", spellID)
    return table.concat({
        "raw=" .. debugSafe(spellID),
        "display=" .. debugSafe(displayID),
        "name=" .. debugSafe(info and info.name),
        "castMs=" .. debugSafe(castTime),
        "never=" .. tostring(policyContains("moveCastNever", spellID)),
        "instantOnly=" .. tostring(policyContains("moveCastInstantOnly", spellID)),
        "always=" .. tostring(policyContains("moveCastAlways", spellID)),
        "moveBuff=" .. tostring(hasMovementCastBuff()),
        "chan=" .. (chOk and debugSafe(channeled) or "call-error"),
        "proc=" .. (procOk and debugSafe(procced) or "call-error"),
        "safe=" .. tostring(isMovementSafeQueueValue(spellID)),
        "usable=" .. tostring(isUsableNow(spellID)),
        "hotkey=" .. (hotkeyOk and debugSafe(toPlainHotkey(hotkey)) or "call-error"),
    }, " ")
end

local function recordDebugSnapshot(reason, queue, lossless, preserve)
    if JustACBridgeDB.debugEnabled == false then
        return
    end
    local speedOK, speed = pcall(GetUnitSpeed, "player")
    local queueKey = {}
    for index = 1, math.min(#queue, QUEUE_SCAN_COUNT) do
        queueKey[#queueKey + 1] = tostring(queue[index])
    end
    local now = GetTime()
    local snapshotKey = table.concat({
        tostring(reason), tostring(playerIsMoving), debugSafe(speed),
        table.concat(queueKey, ","), tostring(lossless and lossless.queueValue),
        tostring(preserve and preserve.queueValue), tostring(queueReady),
        tostring(playerIsCasting), tostring(playerIsChanneling),
    }, ":")
    if snapshotKey == debugLastSnapshot
        and (not playerIsMoving or now - debugLastSnapshotAt < 1) then
        return
    end
    debugLastSnapshot = snapshotKey
    debugLastSnapshotAt = now

    local _, class = UnitClass("player")
    appendDebug(("SNAP reason=%s build=%s uptime=%.3f class=%s spec=%s policy=%s/r%s source=%s filter=%s moving=%s speed=%s speedOK=%s cast=%s channel=%s channelID=%s queueReady=%s gcdMs=%s")
        :format(
            reason, "2.10.9", GetTime() - debugStartedAt,
            debugSafe(class), debugSafe(currentSpecKey),
            debugSafe(currentPolicy and currentPolicy.id),
            debugSafe(currentPolicy and currentPolicy.revision),
            debugSafe(activeSource and activeSource.id),
            tostring(JustACBridgeDB.movementFilter ~= false),
            tostring(playerIsMoving), debugSafe(speed), tostring(speedOK),
            tostring(playerIsCasting), tostring(playerIsChanneling),
            debugSafe(playerChannelSpellID), tostring(queueReady), debugSafe(gcdRemainingMs)))

    local queueParts = {}
    for index = 1, math.min(#queue, QUEUE_SCAN_COUNT) do
        queueParts[#queueParts + 1] = tostring(index) .. "=" .. debugSafe(queue[index])
    end
    appendDebug("QUEUE " .. table.concat(queueParts, " "))
    appendDebug(("SELECT lossless=%s/%s/%s moveFallback=%s failureFallback=%s emergency=%s preserve=%s/%s/%s moveFallback=%s failureFallback=%s emergency=%s")
        :format(
            debugSafe(lossless and lossless.queueValue), debugSafe(lossless and lossless.name),
            debugSafe(lossless and lossless.plainHotkey),
            tostring(lossless and lossless.movementFallback == true),
            tostring(lossless and lossless.failureFallback == true),
            tostring(lossless and lossless.emergencyMovementFallback == true),
            debugSafe(preserve and preserve.queueValue), debugSafe(preserve and preserve.name),
            debugSafe(preserve and preserve.plainHotkey),
            tostring(preserve and preserve.movementFallback == true),
            tostring(preserve and preserve.failureFallback == true),
            tostring(preserve and preserve.emergencyMovementFallback == true)))

    for index = 1, math.min(#queue, QUEUE_SCAN_COUNT) do
        local value = queue[index]
        if type(value) == "number" and value > 0 then
            appendDebug("Q" .. tostring(index) .. " " .. movementDecision(value))
            local failed = failedMovementRecommendations[value]
            if failed then
                appendDebug(("Q%s FAILURE count=%s lastAt=%.3f suppressRemaining=%.3f")
                    :format(index, debugSafe(failed.count), tonumber(failed.lastAt) or 0,
                        math.max(0, (tonumber(failed.suppressUntil) or 0) - GetTime())))
            end
        else
            appendDebug("Q" .. tostring(index) .. " value=" .. debugSafe(value))
        end
    end

    for position = 1, 2 do
        local trace = policyFallbackTraces[position]
        if not trace then
            appendDebug("FALLBACK slot=" .. tostring(position) .. " invoked=false")
        else
            appendDebug(("FALLBACK slot=%s gate=%s policy=%s enemyOK=%s enemyCount=%s rawEnemies=%s selected=%s")
                :format(position, debugSafe(trace.gate), debugSafe(trace.policy),
                    tostring(trace.enemyOK), debugSafe(trace.enemyCount),
                    debugSafe(trace.detectedEnemies), debugSafe(trace.selected)))
            for ruleIndex, rule in ipairs(trace.rules) do
                appendDebug(("FALLBACK slot=%s rule=%s spell=%s label=%s enemies=%s min=%s max=%s requireProc=%s procOK=%s proc=%s known=%s reserved=%s excluded=%s moveSafe=%s rangeSafe=%s groundSafe=%s usable=%s data=%s hotkey=%s selected=%s")
                    :format(position, ruleIndex, debugSafe(rule.spellID), debugSafe(rule.label),
                        tostring(rule.enemyEligible), debugSafe(rule.minEnemies), debugSafe(rule.maxEnemies),
                        tostring(rule.requireProc), tostring(rule.procOK), tostring(rule.procced),
                        tostring(rule.known), tostring(rule.reserved), tostring(rule.excluded),
                        tostring(rule.movementSafe), tostring(rule.rangeSafe), tostring(rule.groundSafe),
                        tostring(rule.usable), tostring(rule.data), debugSafe(rule.hotkey),
                        tostring(rule.selected)))
            end
        end
    end
end

local function getGcdState()
    local cooldown = C_Spell and C_Spell.GetSpellCooldown
        and C_Spell.GetSpellCooldown(61304)
    local startTime = type(cooldown) == "table" and tonumber(cooldown.startTime) or 0
    local duration = type(cooldown) == "table" and tonumber(cooldown.duration) or 0
    if not startTime or not duration or startTime <= 0 or duration <= 0 then
        return true, 0
    end

    local remaining = math.max(0, math.ceil((startTime + duration - GetTime()) * 1000))
    return remaining <= QUEUE_COMMIT_WINDOW_MS, remaining
end

local function makeSignature(dataRows, canCommitQueue)
    local parts = {}
    for index = 1, ROW_COUNT do
        local data = dataRows[index]
        if data then
            parts[index] = table.concat({
                data.kind,
                tostring(data.queueValue),
                data.hotkey,
                data.name,
            }, "\031")
        else
            parts[index] = "-"
        end
    end
    parts[ROW_COUNT + 1] = playerIsChanneling
        and ("channeling:" .. tostring(playerChannelSpellID or 0)
            .. (channelBlocksInput() and ":block" or ":clip"))
        or "not-channeling"
    parts[ROW_COUNT + 2] = playerIsCasting and "casting" or "not-casting"
    parts[ROW_COUNT + 3] = canCommitQueue and "queue-ready" or "queue-wait"
    parts[ROW_COUNT + 4] = playerIsMoving and "moving" or "stationary"
    return table.concat(parts, "\030")
end

local function makeExternalLine(first)
    if not first then
        return table.concat({
            "JACB1",
            tostring(sequence),
            tostring(time()),
            "none",
            "0",
            "",
            "",
        }, "\t")
    end

    return table.concat({
        "JACB1",
        tostring(sequence),
        tostring(time()),
        first.kind,
        tostring(first.spellID or first.itemID or 0),
        first.plainHotkey ~= "" and first.plainHotkey or "UNBOUND",
        ((first.name or "Unknown"):gsub("[\t\r\n]", " ")),
    }, "\t")
end

local function putU24(bytes, offset, value)
    value = math.max(0, math.floor(tonumber(value) or 0)) % 16777216
    bytes[offset] = value % 256
    bytes[offset + 1] = math.floor(value / 256) % 256
    bytes[offset + 2] = math.floor(value / 65536) % 256
end

local function putFixedString(bytes, lengthOffset, dataOffset, value)
    value = tostring(value or "")
    local length = math.min(#value, HOTKEY_BYTES)
    bytes[lengthOffset] = length

    for index = 1, HOTKEY_BYTES do
        bytes[dataOffset + index - 1] = index <= length and string.byte(value, index) or 0
    end
end

-- Encodes both recommendations into a 48x12 monochrome bit matrix (72 bytes).
-- Binary black/white cells survive WoW's color-space conversion, HDR tonemapping,
-- and screen-capture gamma changes much better than byte-exact RGB colors.
local function updatePixelProtocol(dataRows)
    if not pixelFrame then
        return
    end

    local bytes = {}
    for index = 1, PIXEL_BYTE_COUNT do
        bytes[index] = 0
    end

    -- Header: ASCII "JAC", protocol version, 16-bit change sequence, flags.
    bytes[1], bytes[2], bytes[3] = 74, 65, 67
    bytes[4] = PIXEL_PROTOCOL_VERSION
    bytes[5] = sequence % 256
    bytes[6] = math.floor(sequence / 256) % 256

    local first = dataRows[1]
    local second = dataRows[2]
    local flags = 0
    if first then flags = flags + 1 end
    if first and first.kind == "item" then flags = flags + 2 end
    if first and first.plainHotkey ~= "" then flags = flags + 4 end
    if second then flags = flags + 8 end
    if second and second.kind == "item" then flags = flags + 16 end
    if second and second.plainHotkey ~= "" then flags = flags + 32 end
    -- The desktop treats this bit as "channel blocks input".  Clip-policy
    -- channels (Arcane Missiles) stay visible in SavedVariables/UI, while the
    -- v3 GCD gate decides exactly when the next action may interrupt them.
    if channelBlocksInput() then flags = flags + 64 end
    if playerIsCasting then flags = flags + 128 end
    bytes[7] = flags

    -- Bytes 8..35: first ID and up to 24 hotkey bytes.
    putU24(bytes, 8, first and (first.spellID or first.itemID) or 0)
    putFixedString(bytes, 11, 12, first and first.plainHotkey or "")

    -- Bytes 36..63: second ID and up to 24 hotkey bytes.
    putU24(bytes, 36, second and (second.spellID or second.itemID) or 0)
    putFixedString(bytes, 39, 40, second and second.plainHotkey or "")

    -- Diagnostic protocol v4 adds live movement state to the v3 queue gate.
    bytes[64] = (queueReady and 1 or 0)
    if PIXEL_PROTOCOL_VERSION >= 4 then
        bytes[64] = bytes[64]
            + (playerIsMoving and 2 or 0)
            + (JustACBridgeDB.movementFilter ~= false and 4 or 0)
    end
    local remaining = math.min(65535, math.max(0, math.floor(gcdRemainingMs)))
    bytes[65] = remaining % 256
    bytes[66] = math.floor(remaining / 256) % 256

    -- Fletcher-style checks plus an independent rolling byte checksum.
    local sum1, sum2, rolling = 0, 0, 0
    for index = 1, 66 do
        sum1 = (sum1 + bytes[index]) % 255
        sum2 = (sum2 + sum1) % 255
        rolling = (rolling * 33 + bytes[index]) % 256
    end
    bytes[67], bytes[68], bytes[69] = sum1, sum2, rolling
    bytes[70], bytes[71], bytes[72] = 69, 78, 68 -- ASCII "END"

    for bitIndex = 1, PIXEL_BIT_COUNT do
        local byteIndex = math.floor((bitIndex - 1) / 8) + 1
        local bitOffset = 7 - ((bitIndex - 1) % 8)
        local bitValue = math.floor(bytes[byteIndex] / (2 ^ bitOffset)) % 2
        pixelCells[bitIndex]:SetColorTexture(bitValue, bitValue, bitValue, 1)
    end
end

local function updatePixelGeometry()
    if not pixelFrame then
        return
    end

    -- Convert physical pixels to WoW UI units so the reader always sees a
    -- 144x36 matrix at client-area coordinate (2, 7).  The extra 5 physical
    -- pixels keep the transport clear of overlays attached to the top edge.
    -- Multiplication is required
    -- here because the rendered client surface maps UI units inversely through
    -- UIParent's effective scale (including Windows DPI composition).
    local scale = UIParent:GetEffectiveScale()
    if not scale or scale <= 0 then
        scale = 1
    end
    local cellSize = PIXEL_CELL_SIZE * scale

    pixelFrame:ClearAllPoints()
    pixelFrame:SetPoint(
        "TOPLEFT",
        UIParent,
        "TOPLEFT",
        PIXEL_OFFSET_X * scale,
        -PIXEL_OFFSET_Y * scale
    )
    pixelFrame:SetSize(PIXEL_COLUMNS * cellSize, PIXEL_ROWS * cellSize)

    for index = 1, PIXEL_BIT_COUNT do
        local cell = pixelCells[index]
        if cell then
            local zeroIndex = index - 1
            local column = zeroIndex % PIXEL_COLUMNS
            local row = math.floor(zeroIndex / PIXEL_COLUMNS)
            cell:ClearAllPoints()
            cell:SetSize(cellSize, cellSize)
            cell:SetPoint("TOPLEFT", pixelFrame, "TOPLEFT", column * cellSize, -row * cellSize)
        end
    end
end

local function updateSavedExport(dataRows)
    sequence = sequence + 1

    JustACBridgeExport = JustACBridgeExport or {}
    JustACBridgeExport.schemaVersion = PIXEL_PROTOCOL_VERSION
    JustACBridgeExport.sequence = sequence
    JustACBridgeExport.updatedAt = time()
    JustACBridgeExport.updatedAtGame = GetTime()
    JustACBridgeExport.addon = ADDON_NAME
    JustACBridgeExport.isChanneling = playerIsChanneling
    JustACBridgeExport.channelSpellID = playerChannelSpellID
    JustACBridgeExport.channelBlocksInput = channelBlocksInput()
    JustACBridgeExport.isCasting = playerIsCasting
    JustACBridgeExport.isMoving = playerIsMoving
    JustACBridgeExport.movementFilter = JustACBridgeDB.movementFilter ~= false
    JustACBridgeExport.rangeFilter = JustACBridgeDB.rangeFilter ~= false
    JustACBridgeExport.groundEffectFilter = JustACBridgeDB.groundEffectFilter ~= false
    JustACBridgeExport.groundAlert = JustACBridgeDB.groundAlert ~= false
    JustACBridgeExport.groundSound = JustACBridgeDB.groundSound ~= false
    JustACBridgeExport.groundVoice = JustACBridgeDB.groundVoice ~= false
    JustACBridgeExport.recommendationSource = activeSource and {
        id = activeSource.id,
        name = activeSource.name,
        justACFallback = supportSource ~= nil and supportSource ~= activeSource,
    } or nil
    JustACBridgeExport.groundEffects = GroundEffectTracker
        and GroundEffectTracker.GetActive and GroundEffectTracker.GetActive() or {}
    JustACBridgeExport.queueReady = queueReady
    JustACBridgeExport.gcdRemainingMs = gcdRemainingMs
    JustACBridgeExport.playerState = playerIsChanneling and "channeling"
        or (playerIsCasting and "casting" or "idle")
    JustACBridgeExport.policy = currentPolicy and {
        storageKey = currentPolicy.storageKey,
        id = currentPolicy.id,
        ruleset = currentPolicy.ruleset,
        revision = currentPolicy.revision,
        interfaceVersion = currentPolicy.interfaceVersion,
    } or {
        storageKey = currentSpecKey,
        id = "justac-only",
        ruleset = "dynamic",
        revision = 0,
        interfaceVersion = PolicyRegistry and PolicyRegistry.GetInterfaceVersion
            and PolicyRegistry.GetInterfaceVersion() or 0,
    }
    JustACBridgeExport.first = copyTable(dataRows[1])
    JustACBridgeExport.lossless = copyTable(dataRows[1])
    JustACBridgeExport.reserveBurst = copyTable(dataRows[2])
    JustACBridgeExport.rows = {}

    for index = 1, ROW_COUNT do
        JustACBridgeExport.rows[index] = copyTable(dataRows[index])
    end

    JustACBridgeExport.line = makeExternalLine(dataRows[1])
    updatePixelProtocol(dataRows)
end

local function refreshStatusText()
    if not statusText then
        return
    end
    local suffix = ""
    local active = GroundEffectTracker and GroundEffectTracker.GetActive
        and GroundEffectTracker.GetActive() or {}
    if active[1] then
        local effect = active[1]
        local label = effect.name
        if not label or label == "" then
            local info = C_Spell and C_Spell.GetSpellInfo
                and C_Spell.GetSpellInfo(effect.spellID)
            label = info and info.name or "场地技能"
        end
        suffix = (" · %s %.1fs"):format(label, effect.remaining)
    end
    local text = statusBaseText .. suffix
    if text ~= lastStatusText then
        lastStatusText = text
        statusText:SetText(text)
    end
end

local function updateUI(dataRows)
    if not bridgeFrame then
        return
    end

    for index = 1, ROW_COUNT do
        local row = rows[index]
        local data = dataRows[index]

        if data then
            row.icon:SetTexture(data.icon)
            row.icon:SetDesaturated(false)
            row.name:SetText(data.name)
            local fallbackLabel = data.finalFallback
                and (" · 专精兜底" .. (data.finalFallbackLabel
                    and ("：" .. data.finalFallbackLabel) or ""))
                or (data.emergencyMovementFallback
                and (" · 移动兜底" .. (data.emergencyFallbackLabel
                    and ("：" .. data.emergencyFallbackLabel) or ""))
                or (data.movementFallback and " · 移动替代"
                or (data.failureFallback and " · 失败后替代"
                or (data.rangeFallback and " · 射程替代"
                    or (data.groundFallback and " · 场地仍存在" or "")))))
            row.id:SetText((data.kind == "item"
                and ("物品 " .. tostring(data.itemID))
                or ("法术 " .. tostring(data.spellID)))
                .. fallbackLabel)
            row.hotkey:SetText(data.hotkey ~= "" and data.hotkey or "未绑定")
            if data.hotkey ~= "" then
                row.hotkey:SetTextColor(1, 0.82, 0)
            else
                row.hotkey:SetTextColor(1, 0.25, 0.25)
            end
        else
            row.icon:SetTexture(134400)
            row.icon:SetDesaturated(true)
            row.name:SetText(playerIsMoving and JustACBridgeDB.movementFilter ~= false
                and (index == 2 and "移动中无安全非爆发推荐" or "移动中无安全推荐")
                or "暂无推荐")
            row.id:SetText("-")
            row.hotkey:SetText("-")
            row.hotkey:SetTextColor(0.55, 0.55, 0.55)
        end
    end

    if exportBox then
        exportBox:SetText(JustACBridgeExport.line or "")
        exportBox:SetCursorPosition(0)
        exportBox:ClearFocus()
    end

    local castState = playerIsChanneling
        and (channelBlocksInput() and " · 持续引导中" or " · 引导中（GCD末可截断）")
        or (playerIsCasting and " · 施法中" or "")
    local movementState = playerIsMoving and JustACBridgeDB.movementFilter ~= false
        and " · 移动过滤中" or ""
    local sourceName = activeSource and activeSource.name or "无推荐源"
    statusBaseText = dataRows[1]
        and ("实时接口已更新 · " .. sourceName .. " · 序号 " .. sequence
            .. castState .. movementState)
        or ("等待 " .. sourceName .. " 的可执行推荐" .. castState .. movementState)
    refreshStatusText()
end

local function refresh()
    if not activeSource or type(activeSource.GetQueue) ~= "function" then
        return false, "recommendation source unavailable"
    end

    -- Movement events are normally immediate, but refresh the authoritative
    -- speed every frame as well so a missed/delayed event can never leave a
    -- stationary recommendation active while the player is moving.
    refreshPlayerMoving()

    local ok, queue = pcall(activeSource.GetQueue)
    if not ok or type(queue) ~= "table" then
        return false, ok and "invalid recommendation queue" or tostring(queue)
    end

    policyFallbackTraces = {}
    local lossless = findSafeRecommendation(queue)
    if not lossless then
        lossless = findPolicyFinalFallback(1)
    end
    local preserve
    if lossless and lossless.plainHotkey ~= ""
        and not isReservedQueueValue(lossless.queueValue)
        and not isReserveExcludedQueueValue(lossless.queueValue) then
        preserve = copyTable(lossless)
        preserve.position = 2
    else
        -- A movement fallback may originate from any queue position.  Rescan
        -- from the front so reserve mode still gets the best safe non-burst
        -- action rather than accidentally skipping an earlier candidate.
        preserve = findReserveRecommendation(
            queue,
            playerIsMoving and JustACBridgeDB.movementFilter ~= false
                and 1 or (lossless and 2 or 1)
        )
        if not preserve then
            preserve = findPolicyFinalFallback(2)
        end
    end
    local nextRows = { lossless, preserve }

    local nextQueueReady, nextGcdRemainingMs = getGcdState()
    queueReady = nextQueueReady
    gcdRemainingMs = nextGcdRemainingMs
    recordDebugSnapshot("frame", queue, lossless, preserve)
    local signature = makeSignature(nextRows, nextQueueReady)
    if signature == lastSignature then
        return true
    end

    lastSignature = signature
    currentRows = nextRows
    updateSavedExport(currentRows)
    updateUI(currentRows)
    return true
end

local function savePosition()
    if not bridgeFrame then
        return
    end

    local point, _, relativePoint, x, y = bridgeFrame:GetPoint(1)
    JustACBridgeDB.point = point
    JustACBridgeDB.relativePoint = relativePoint
    JustACBridgeDB.x = x
    JustACBridgeDB.y = y
end

local function getGroundEffectName(effect)
    if effect and effect.name and effect.name ~= "" then
        return effect.name
    end
    local info = effect and C_Spell and C_Spell.GetSpellInfo
        and C_Spell.GetSpellInfo(effect.spellID)
    return info and info.name or "场地技能"
end

local function showGroundEffectExpiredAlert(effect)
    local name = getGroundEffectName(effect)
    if JustACBridgeDB.groundAlert ~= false and groundAlertFrame and groundAlertText then
        groundAlertText:SetText(name .. " 已结束")
        groundAlertFrame:SetAlpha(1)
        groundAlertFrame:Show()
        groundAlertExpiresAt = GetTime() + 2
    end
    if JustACBridgeDB.groundVoice ~= false
        and C_VoiceChat and C_VoiceChat.SpeakText then
        local voiceType = Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard or 0
        local voiceID = 0
        if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
            local ok, configuredVoiceID = pcall(C_TTSSettings.GetVoiceOptionID, voiceType)
            if ok and type(configuredVoiceID) == "number" then
                voiceID = configuredVoiceID
            end
        end
        -- Patch 12.0 signature: voiceID, text, rate, volume, overlap.
        pcall(C_VoiceChat.SpeakText, voiceID, name .. "结束", 0, 100, false)
    end
    if JustACBridgeDB.groundSound ~= false and PlaySound then
        local soundID = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        pcall(PlaySound, soundID, "Master")
    end
end

local function createRow(parent, index, topOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 12, topOffset)
    row:SetPoint("TOPRIGHT", -12, topOffset)
    row:SetHeight(42)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexture(134400)

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rank:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 2, -2)
    row.rank:SetText(tostring(index))

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -2)
    row.name:SetPoint("RIGHT", -92, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetText("暂无推荐")

    row.id = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 2)
    row.id:SetText("-")

    row.hotkey = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.hotkey:SetPoint("RIGHT", -4, 0)
    row.hotkey:SetWidth(82)
    row.hotkey:SetJustifyH("RIGHT")
    row.hotkey:SetText("-")

    local divider = row:CreateTexture(nil, "BACKGROUND")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetPoint("BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)

    return row
end

local function createUI()
    bridgeFrame = CreateFrame("Frame", "JustACBridgeFrame", UIParent, "BackdropTemplate")
    bridgeFrame:SetSize(380, 166)
    bridgeFrame:SetFrameStrata("MEDIUM")
    bridgeFrame:SetClampedToScreen(true)
    bridgeFrame:SetMovable(true)
    bridgeFrame:EnableMouse(true)
    bridgeFrame:RegisterForDrag("LeftButton")
    bridgeFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bridgeFrame:SetBackdropColor(0.025, 0.025, 0.035, 0.94)
    bridgeFrame:SetBackdropBorderColor(0.25, 0.65, 1, 0.85)

    bridgeFrame:SetScript("OnDragStart", function(self)
        if not JustACBridgeDB.locked then
            self:StartMoving()
        end
    end)
    bridgeFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    local title = bridgeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 13, -10)
    title:SetText("JustACBridge · 推荐快捷键")

    local close = CreateFrame("Button", nil, bridgeFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetSize(28, 28)
    close:SetScript("OnClick", function()
        JustACBridgeDB.visible = false
        bridgeFrame:Hide()
    end)

    rows[1] = createRow(bridgeFrame, 1, -30)
    rows[2] = createRow(bridgeFrame, 2, -73)
    rows[1].rank:SetText("全")
    rows[2].rank:SetText("留")

    exportBox = CreateFrame("EditBox", nil, bridgeFrame, "InputBoxTemplate")
    exportBox:SetAutoFocus(false)
    exportBox:SetFontObject("GameFontHighlightSmall")
    exportBox:SetPoint("BOTTOMLEFT", 13, 24)
    exportBox:SetPoint("BOTTOMRIGHT", -13, 24)
    exportBox:SetHeight(20)
    exportBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        self:HighlightText()
    end)
    exportBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    exportBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText((JustACBridgeExport and JustACBridgeExport.line) or "")
            self:HighlightText()
        end
    end)

    statusText = bridgeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 14, 9)
    statusText:SetText("等待推荐源队列")

    bridgeFrame:ClearAllPoints()
    bridgeFrame:SetPoint(
        JustACBridgeDB.point or "CENTER",
        UIParent,
        JustACBridgeDB.relativePoint or "CENTER",
        JustACBridgeDB.x or 0,
        JustACBridgeDB.y or 120
    )

    if JustACBridgeDB.visible == false then
        bridgeFrame:Hide()
    end

    groundAlertFrame = CreateFrame("Frame", "JustACBridgeGroundAlertFrame", UIParent)
    groundAlertFrame:SetSize(520, 72)
    groundAlertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
    groundAlertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    groundAlertFrame:EnableMouse(false)
    local groundAlertBackground = groundAlertFrame:CreateTexture(nil, "BACKGROUND")
    groundAlertBackground:SetAllPoints()
    groundAlertBackground:SetColorTexture(0, 0, 0, 0.72)
    groundAlertText = groundAlertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    groundAlertText:SetPoint("CENTER")
    groundAlertText:SetTextColor(1, 0.2, 0.15)
    groundAlertText:SetText("")
    groundAlertFrame:Hide()

    -- Dedicated screen-capture transport. It remains independent from the
    -- normal panel so hiding the panel does not interrupt an external reader.
    pixelFrame = CreateFrame("Frame", "JustACBridgePixelFrame", UIParent)
    pixelFrame:SetFrameStrata("TOOLTIP")
    pixelFrame:SetFrameLevel(10000)
    pixelFrame:EnableMouse(false)

    for index = 1, PIXEL_BIT_COUNT do
        local cell = pixelFrame:CreateTexture(nil, "OVERLAY")
        cell:SetColorTexture(0, 0, 0, 1)
        pixelCells[index] = cell
    end

    updatePixelGeometry()

    if JustACBridgeDB.pixelVisible == false then
        pixelFrame:Hide()
    end

    updatePixelProtocol(currentRows)
end

local function showDebugWindow()
    if not debugFrame then
        debugFrame = CreateFrame("Frame", "JustACBridgeDebugFrame", UIParent, "BackdropTemplate")
        debugFrame:SetSize(860, 520)
        debugFrame:SetPoint("CENTER")
        debugFrame:SetFrameStrata("DIALOG")
        debugFrame:SetMovable(true)
        debugFrame:EnableMouse(true)
        debugFrame:RegisterForDrag("LeftButton")
        debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
        debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
        debugFrame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        debugFrame:SetBackdropColor(0.015, 0.015, 0.02, 0.98)

        local title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("JustACBridge 诊断日志 · Ctrl+A / Ctrl+C 复制全部")
        local close = CreateFrame("Button", nil, debugFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 1, 1)

        local scroll = CreateFrame("ScrollFrame", nil, debugFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -42)
        scroll:SetPoint("BOTTOMRIGHT", -32, 44)
        debugBox = CreateFrame("EditBox", nil, scroll)
        debugBox:SetMultiLine(true)
        debugBox:SetAutoFocus(false)
        -- Do not inherit ChatFontNormal: users often enlarge their chat font,
        -- which made each diagnostic line fill the entire window.
        debugBox:SetFontObject("GameFontHighlightSmall")
        debugBox:SetWidth(800)
        debugBox:SetMaxLetters(1000000)
        debugBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(debugBox)

        local selectAll = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
        selectAll:SetSize(170, 24)
        selectAll:SetPoint("BOTTOMLEFT", 14, 12)
        selectAll:SetText("选中全部（然后 Ctrl+C）")
        selectAll:SetScript("OnClick", function()
            debugBox:SetFocus()
            debugBox:HighlightText()
        end)
        local hint = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", selectAll, "RIGHT", 12, 0)
        hint:SetText("复现后不要 /reload；输入 /jacb debug，再复制这里和 Windows 客户端日志。")
    end
    local text = table.concat(debugLines, "\n")
    debugBox:SetText(text ~= "" and text or "暂无日志")
    debugBox:SetCursorPosition(#text)
    debugFrame:Show()
end

local API = _G.JustACBridge or {}
_G.JustACBridge = API

function API.GetCurrentHotkey()
    local first = currentRows[1]
    return first and first.plainHotkey or nil
end

function API.GetCurrentRecommendation()
    return copyTable(currentRows[1])
end

function API.GetLosslessRecommendation()
    return copyTable(currentRows[1])
end

function API.GetPreserveBurstRecommendation()
    return copyTable(currentRows[2])
end

function API.GetRecommendations()
    local result = {}
    for index = 1, ROW_COUNT do
        result[index] = copyTable(currentRows[index])
    end
    return result
end

function API.GetExternalLine()
    return JustACBridgeExport and JustACBridgeExport.line or nil
end

function API.IsPlayerChanneling()
    return playerIsChanneling
end

function API.IsPlayerCasting()
    return playerIsCasting
end

function API.IsPlayerMoving()
    return playerIsMoving
end

function API.GetPlayerCastState()
    return {
        isChanneling = playerIsChanneling,
        channelSpellID = playerChannelSpellID,
        channelBlocksInput = channelBlocksInput(),
        isCasting = playerIsCasting,
        isMoving = playerIsMoving,
    }
end

function API.GetRecommendationSource()
    return activeSource and {
        id = activeSource.id,
        name = activeSource.name,
        justACFallback = supportSource ~= nil and supportSource ~= activeSource,
    } or nil
end

function API.GetGroundEffects()
    return GroundEffectTracker and GroundEffectTracker.GetActive
        and GroundEffectTracker.GetActive() or {}
end

function API.IsGroundEffectActive(spellID)
    if not GroundEffectTracker or not GroundEffectTracker.IsSpellActive then
        return false
    end
    return GroundEffectTracker.IsSpellActive(spellID)
end

function API.Refresh()
    return refresh()
end

function API.Show()
    JustACBridgeDB.visible = true
    if bridgeFrame then
        bridgeFrame:Show()
        updateUI(currentRows)
    end
end

function API.Hide()
    JustACBridgeDB.visible = false
    if bridgeFrame then
        bridgeFrame:Hide()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("PLAYER_STARTED_MOVING")
eventFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:SetScript("OnEvent", function(_, event, unitTarget, castGUID, spellID)
    if event == "PLAYER_LOGIN" then
        JustACBridgeDB = JustACBridgeDB or {}
        if JustACBridgeDB.visible == nil then
            JustACBridgeDB.visible = true
        end
        if JustACBridgeDB.locked == nil then
            JustACBridgeDB.locked = false
        end
        if JustACBridgeDB.pixelVisible == nil then
            JustACBridgeDB.pixelVisible = true
        end

        if JustACBridgeDB.movementFilter == nil then
            JustACBridgeDB.movementFilter = true
        end
        if JustACBridgeDB.debugEnabled == nil then
            JustACBridgeDB.debugEnabled = false
        end
        PIXEL_PROTOCOL_VERSION = JustACBridgeDB.debugEnabled and 4 or 3
        if JustACBridgeDB.rangeFilter == nil then
            JustACBridgeDB.rangeFilter = true
        end
        if JustACBridgeDB.groundEffectFilter == nil then
            JustACBridgeDB.groundEffectFilter = true
        end
        if JustACBridgeDB.groundAlert == nil then
            JustACBridgeDB.groundAlert = true
        end
        if JustACBridgeDB.groundSound == nil then
            JustACBridgeDB.groundSound = true
        end
        if JustACBridgeDB.groundVoice == nil then
            JustACBridgeDB.groundVoice = true
        end
        local sourceOK, sourceError = activateRecommendationSource(
            JustACBridgeDB.recommendationSource
        )
        refreshPlayerMoving()
        refreshReservedSpells()
        createUI()
        appendDebug(("START addon=%s protocol=%d locale=%s interface=%s")
            :format("2.10.9", PIXEL_PROTOCOL_VERSION,
                debugSafe(GetLocale and GetLocale()),
                debugSafe(select(4, GetBuildInfo()))))

        if not sourceOK then
            statusBaseText = "错误：找不到可用推荐源 · " .. tostring(sourceError)
            statusText:SetTextColor(1, 0.2, 0.2)
            refreshStatusText()
            return
        end

        refresh()
    elseif event == "PLAYER_LOGOUT" then
        savePosition()
        refresh()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        C_Timer.After(0, updatePixelGeometry)
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerIsChanneling = false
        playerChannelSpellID = nil
        playerIsCasting = false
        if GroundEffectTracker and GroundEffectTracker.Reset then
            GroundEffectTracker.Reset()
        end
        refreshPlayerMoving()
        lastSignature = nil
        refreshReservedSpells()
    elseif event == "PLAYER_STARTED_MOVING" then
        local now = GetTime()
        local changed = not playerIsMoving
        playerIsMoving = true
        lastMovementStartedAt = now
        movementStopPendingUntil = 0
        if changed then lastSignature = nil end
        local ok, speed = pcall(GetUnitSpeed, "player")
        if changed or now - movementLastDebugAt >= 0.5 then
            movementLastDebugAt = now
            appendDebug(("EVENT PLAYER_STARTED_MOVING speed=%s flapCount=%s")
                :format(debugSafe(ok and speed or "call-error"), movementFlapCount))
            movementFlapCount = 0
        end
    elseif event == "PLAYER_STOPPED_MOVING" then
        local now = GetTime()
        local deferred = now - lastMovementStartedAt <= MOVEMENT_FLAP_WINDOW_SECONDS
        if deferred then
            movementStopPendingUntil = now + MOVEMENT_STOP_DEBOUNCE_SECONDS
            movementFlapCount = movementFlapCount + 1
        else
            playerIsMoving = false
            movementStopPendingUntil = 0
            lastSignature = nil
        end
        local ok, speed = pcall(GetUnitSpeed, "player")
        if not deferred or now - movementLastDebugAt >= 0.5 then
            movementLastDebugAt = now
            appendDebug(("EVENT PLAYER_STOPPED_MOVING speed=%s deferred=%s flapCount=%s")
                :format(debugSafe(ok and speed or "call-error"), tostring(deferred), movementFlapCount))
            if not deferred then movementFlapCount = 0 end
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then
        if GroundEffectTracker and GroundEffectTracker.Reset then
            GroundEffectTracker.Reset()
        end
        refreshReservedSpells()
        lastSignature = nil
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        failedMovementRecommendations[tonumber(spellID)] = nil
        appendDebug(("EVENT %s spell=%s castGUID=%s moving=%s")
            :format(event, debugSafe(spellID), debugSafe(castGUID), tostring(playerIsMoving)))
        if GroundEffectTracker and GroundEffectTracker.OnSpellcastSucceeded
            and GroundEffectTracker.OnSpellcastSucceeded(spellID) then
            lastSignature = nil
            refreshStatusText()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        playerIsChanneling = true
        playerChannelSpellID = resolveChannelSpellID(spellID)
        playerIsCasting = false
        lastSignature = nil
        appendDebug(("EVENT %s spell=%s moving=%s")
            :format(event, debugSafe(spellID), tostring(playerIsMoving)))
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        playerIsChanneling = false
        playerChannelSpellID = nil
        lastSignature = nil
        appendDebug(("EVENT %s spell=%s moving=%s"):format(event, debugSafe(spellID), tostring(playerIsMoving)))
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        playerIsCasting = true
        playerIsChanneling = false
        playerChannelSpellID = nil
        lastSignature = nil
        appendDebug(("EVENT %s spell=%s moving=%s"):format(event, debugSafe(spellID), tostring(playerIsMoving)))
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        local numericSpellID = tonumber(spellID)
        local selected = false
        for index = 1, ROW_COUNT do
            local row = currentRows[index]
            if row and row.spellID == numericSpellID then
                selected = true
                break
            end
        end
        local now = GetTime()
        local state = numericSpellID and failedMovementRecommendations[numericSpellID] or nil
        local newlySuppressed = false
        local duplicateFailure = false
        local fallbackSpell = isPolicyFallbackSpell(numericSpellID)
        if selected and not fallbackSpell and playerIsMoving
            and JustACBridgeDB.movementFilter ~= false then
            if not state or now - (tonumber(state.lastAt) or 0) > FAILURE_WINDOW_SECONDS then
                state = { count = 0, lastAt = now, suppressUntil = 0 }
                failedMovementRecommendations[numericSpellID] = state
            end
            local failureGUID = type(castGUID) == "string" and castGUID ~= "" and castGUID or nil
            duplicateFailure = (failureGUID and state.lastCastGUID == failureGUID)
                or (not failureGUID and state.lastEventAt
                    and now - state.lastEventAt < FAILURE_DUPLICATE_WINDOW_SECONDS)
            state.lastEventAt = now
            if failureGUID then state.lastCastGUID = failureGUID end
            if not duplicateFailure then
                state.count = (tonumber(state.count) or 0) + 1
                state.lastAt = now
                if state.count >= FAILURE_THRESHOLD then
                    local previousUntil = tonumber(state.suppressUntil) or 0
                    state.suppressUntil = math.max(previousUntil, now + FAILURE_SUPPRESS_SECONDS)
                    newlySuppressed = previousUntil <= now
                    lastSignature = nil
                end
            end
        end
        playerIsCasting = false
        local lastLog = numericSpellID and (debugFailureLastLog[numericSpellID] or 0) or 0
        if newlySuppressed or now - lastLog >= FAILURE_WINDOW_SECONDS then
            if numericSpellID then debugFailureLastLog[numericSpellID] = now end
            appendDebug(("EVENT %s spell=%s castGUID=%s moving=%s selected=%s fallback=%s duplicate=%s failCount=%s suppressed=%s suppressRemaining=%.3f")
                :format(event, debugSafe(spellID), debugSafe(castGUID), tostring(playerIsMoving),
                    tostring(selected), tostring(fallbackSpell), tostring(duplicateFailure),
                    debugSafe(state and state.count), tostring(newlySuppressed),
                    math.max(0, (state and tonumber(state.suppressUntil) or 0) - now)))
        end
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        playerIsCasting = false
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            playerIsChanneling = false
            playerChannelSpellID = nil
        end
        lastSignature = nil
        appendDebug(("EVENT %s spell=%s moving=%s"):format(event, debugSafe(spellID), tostring(playerIsMoving)))
    end
end)

eventFrame:SetScript("OnUpdate", function(_, delta)
    if GroundEffectTracker and GroundEffectTracker.Update
        and GroundEffectTracker.Update() then
        lastSignature = nil
    end
    if GroundEffectTracker and GroundEffectTracker.DrainExpired then
        local expired = GroundEffectTracker.DrainExpired()
        for _, effect in ipairs(expired) do
            showGroundEffectExpiredAlert(effect)
        end
    end
    if groundAlertFrame and groundAlertExpiresAt then
        local remaining = groundAlertExpiresAt - GetTime()
        if remaining <= 0 then
            groundAlertFrame:Hide()
            groundAlertExpiresAt = nil
        elseif remaining < 0.5 then
            groundAlertFrame:SetAlpha(remaining / 0.5)
        end
    end
    groundStatusElapsed = groundStatusElapsed + delta
    if groundStatusElapsed >= 0.1 then
        groundStatusElapsed = 0
        refreshStatusText()
    end

    elapsed = elapsed + delta
    if UPDATE_INTERVAL > 0 and elapsed < UPDATE_INTERVAL then
        return
    end
    elapsed = 0
    refresh()
end)

SLASH_JUSTACBRIDGE1 = "/jacb"
SLASH_JUSTACBRIDGE2 = "/justacbridge"
SlashCmdList.JUSTACBRIDGE = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    local reserveAction, reserveID = command:match("^reserve%s+(%a+)%s+(%d+)$")
    if reserveAction ~= "add" and reserveAction ~= "remove" then
        reserveAction, reserveID = nil, nil
    end

    if reserveAction and reserveID then
        currentSpecKey = getSpecKey()
        local spellID = tonumber(reserveID)
        if not currentSpecKey or not spellID then
            print("|cffff4040JustACBridge:|r 当前专精或法术 ID 无效。")
            return
        end
        JustACBridgeDB.reserveOverrides = JustACBridgeDB.reserveOverrides or {}
        local overrides = JustACBridgeDB.reserveOverrides[currentSpecKey] or { include = {}, exclude = {} }
        overrides.include = overrides.include or {}
        overrides.exclude = overrides.exclude or {}
        JustACBridgeDB.reserveOverrides[currentSpecKey] = overrides
        if reserveAction == "add" then
            overrides.include[spellID] = true
            overrides.exclude[spellID] = nil
        else
            overrides.include[spellID] = nil
            overrides.exclude[spellID] = true
        end
        refreshReservedSpells()
        lastSignature = nil
        print(("|cff40a9ffJustACBridge:|r %s保留法术 %d（%s）。")
            :format(reserveAction == "add" and "已添加" or "已移除", spellID, currentSpecKey))
    elseif command == "reserve reset" then
        currentSpecKey = getSpecKey()
        if currentSpecKey and JustACBridgeDB.reserveOverrides then
            JustACBridgeDB.reserveOverrides[currentSpecKey] = nil
        end
        refreshReservedSpells()
        lastSignature = nil
        print("|cff40a9ffJustACBridge:|r 当前专精保留法术已恢复默认。")
    elseif command == "reserve list" then
        local ids = {}
        for spellID in pairs(reservedSpellIDs) do
            ids[#ids + 1] = spellID
        end
        table.sort(ids)
        local policyLabel = currentPolicy
            and (currentPolicy.id .. "/" .. currentPolicy.ruleset .. " r" .. tostring(currentPolicy.revision))
            or "JustAC dynamic"
        print(("|cff40a9ffJustACBridge:|r 保留法术（%s，策略 %s）：%s")
            :format(currentSpecKey or "unknown", policyLabel,
                #ids > 0 and table.concat(ids, ", ") or "无"))
    elseif command == "source list" then
        local entries = SourceRegistry and SourceRegistry.List and SourceRegistry.List() or {}
        print("|cff40a9ffJustACBridge:|r 推荐源：")
        for _, entry in ipairs(entries) do
            local selected = activeSource and activeSource.id == entry.id and "（当前）" or ""
            print(("  %s · %s%s%s"):format(
                entry.id,
                entry.available and entry.name or "不可用",
                selected,
                entry.reason and (" · " .. entry.reason) or ""
            ))
        end
    elseif command:match("^source%s+[%w_-]+$") then
        local sourceID = command:match("^source%s+([%w_-]+)$")
        local ok, err = activateRecommendationSource(sourceID, true)
        if ok and activeSource and activeSource.id == sourceID then
            if GroundEffectTracker and GroundEffectTracker.Reset then
                GroundEffectTracker.Reset()
            end
            refreshReservedSpells()
            lastSignature = nil
            print(("|cff40a9ffJustACBridge:|r 推荐源已切换为 %s（%s）。")
                :format(activeSource.name, activeSource.id))
        else
            print("|cffff4040JustACBridge:|r 无法切换推荐源：" .. tostring(err or sourceID))
        end
    elseif command == "ground on" or command == "ground off" then
        JustACBridgeDB.groundEffectFilter = command == "ground on"
        lastSignature = nil
        print(JustACBridgeDB.groundEffectFilter
            and "|cff40a9ffJustACBridge:|r 场地技能到期过滤已开启。"
            or "|cff40a9ffJustACBridge:|r 场地技能仍会计时，但不再抑制重复推荐。")
    elseif command == "ground alert on" or command == "ground alert off" then
        JustACBridgeDB.groundAlert = command == "ground alert on"
        print(JustACBridgeDB.groundAlert
            and "|cff40a9ffJustACBridge:|r 场地技能中央文字提醒已开启。"
            or "|cff40a9ffJustACBridge:|r 场地技能中央文字提醒已关闭。")
    elseif command == "ground sound on" or command == "ground sound off" then
        JustACBridgeDB.groundSound = command == "ground sound on"
        print(JustACBridgeDB.groundSound
            and "|cff40a9ffJustACBridge:|r 场地技能到期声音已开启。"
            or "|cff40a9ffJustACBridge:|r 场地技能到期声音已关闭。")
    elseif command == "ground voice on" or command == "ground voice off" then
        JustACBridgeDB.groundVoice = command == "ground voice on"
        print(JustACBridgeDB.groundVoice
            and "|cff40a9ffJustACBridge:|r 场地技能到期语音已开启。"
            or "|cff40a9ffJustACBridge:|r 场地技能到期语音已关闭。")
    elseif command == "ground test" then
        showGroundEffectExpiredAlert({ name = "枯萎凋零", spellID = 43265 })
        print("|cff40a9ffJustACBridge:|r 已触发场地技能到期测试提醒。")
    elseif command == "ground reset" then
        if GroundEffectTracker and GroundEffectTracker.Reset then
            GroundEffectTracker.Reset()
        end
        lastSignature = nil
        refreshStatusText()
        print("|cff40a9ffJustACBridge:|r 场地技能计时已清除。")
    elseif command == "ground status" then
        local active = GroundEffectTracker and GroundEffectTracker.GetActive
            and GroundEffectTracker.GetActive() or {}
        if active[1] then
            for _, effect in ipairs(active) do
                print(("|cff40a9ffJustACBridge:|r %s：剩余 %.1f 秒。")
                    :format(effect.name or tostring(effect.spellID), effect.remaining))
            end
        else
            print("|cff40a9ffJustACBridge:|r 当前没有活动的已跟踪场地技能。")
        end
    elseif command == "debug" or command == "debug show" then
        showDebugWindow()
        print("|cff40a9ffJustACBridge:|r 已打开诊断日志；点击选中全部后按 Ctrl+C。")
    elseif command == "debug on" or command == "debug off" then
        JustACBridgeDB.debugEnabled = command == "debug on"
        PIXEL_PROTOCOL_VERSION = JustACBridgeDB.debugEnabled and 4 or 3
        lastSignature = nil
        appendDebug("DEBUG enabled=true")
        print(JustACBridgeDB.debugEnabled
            and "|cff40a9ffJustACBridge:|r 诊断记录已开启。"
            or "|cff40a9ffJustACBridge:|r 诊断记录已关闭。")
    elseif command == "debug clear" then
        debugLines = {}
        debugLastSnapshot = nil
        JustACBridgeExport.debugLog = ""
        appendDebug("DEBUG log-cleared")
        showDebugWindow()
    elseif command == "movement on" or command == "movement off" then
        JustACBridgeDB.movementFilter = command == "movement on"
        lastSignature = nil
        print(JustACBridgeDB.movementFilter
            and "|cff40a9ffJustACBridge:|r 移动过滤已开启；移动时会跳过不可移动读条、蓄力和引导。"
            or "|cff40a9ffJustACBridge:|r 移动过滤已关闭。")
    elseif command == "range on" or command == "range off" then
        JustACBridgeDB.rangeFilter = command == "range on"
        lastSignature = nil
        print(JustACBridgeDB.rangeFilter
            and "|cff40a9ffJustACBridge:|r 射程过滤已开启；明确超出目标射程的动作会被跳过。"
            or "|cff40a9ffJustACBridge:|r 射程过滤已关闭。")
    elseif command == "show" then
        API.Show()
    elseif command == "hide" then
        API.Hide()
    elseif command == "lock" then
        JustACBridgeDB.locked = true
        print("|cff40a9ffJustACBridge:|r 面板已锁定。")
    elseif command == "unlock" then
        JustACBridgeDB.locked = false
        print("|cff40a9ffJustACBridge:|r 面板已解锁，可用鼠标左键拖动。")
    elseif command == "refresh" then
        refreshReservedSpells()
        lastSignature = nil
        local ok, err = refresh()
        print(ok and "|cff40a9ffJustACBridge:|r 已刷新。" or ("|cffff4040JustACBridge:|r " .. tostring(err)))
    elseif command == "flush" then
        print("|cff40a9ffJustACBridge:|r 正在重载界面并把 SavedVariables 写入磁盘……")
        C_Timer.After(0, ReloadUI)
    elseif command == "pixels" or command == "pixels on" or command == "pixels off" then
        if command == "pixels on" then
            JustACBridgeDB.pixelVisible = true
        elseif command == "pixels off" then
            JustACBridgeDB.pixelVisible = false
        else
            JustACBridgeDB.pixelVisible = not JustACBridgeDB.pixelVisible
        end
        if pixelFrame then
            pixelFrame:SetShown(JustACBridgeDB.pixelVisible)
        end
        print(JustACBridgeDB.pixelVisible
            and "|cff40a9ffJustACBridge:|r 实时像素接口已开启。"
            or "|cff40a9ffJustACBridge:|r 实时像素接口已关闭。")
    elseif command == "" or command == "toggle" then
        if bridgeFrame and bridgeFrame:IsShown() then
            API.Hide()
        else
            API.Show()
        end
    else
        print("|cff40a9ffJustACBridge 命令：|r")
        print("/jacb - 显示/隐藏面板")
        print("/jacb lock | unlock - 锁定/解锁面板")
        print("/jacb refresh - 立即刷新")
        print("/jacb pixels [on|off] - 控制实时像素接口")
        print("/jacb reserve list - 查看当前专精保留法术")
        print("/jacb reserve add <法术ID> | remove <法术ID> | reset")
        print("/jacb source list | <ID> - 查看或切换推荐源")
        print("/jacb ground on | off | status | reset - 场地技能到期监控")
        print("/jacb ground alert/sound/voice on|off / test - 到期提醒")
        print("/jacb movement on | off - 移动时跳过不可移动读条/蓄力/引导")
        print("/jacb range on | off - 跳过明确超出目标射程的动作")
        print("/jacb debug [show|on|off|clear] - 打开并复制完整诊断日志")
        print("/jacb flush - 重载 UI 并将导出数据写入磁盘")
    end
end
