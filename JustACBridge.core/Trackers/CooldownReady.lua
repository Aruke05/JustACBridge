-- Announces DnD's explicit fixed recharge and equipped-item cooldown completions.
--
-- Patch 12.x may mark numeric cooldown values as secret in combat. Addons may
-- still pass item values to a Cooldown widget, whose OnCooldownDone event is
-- the reliable boundary we need. DnD uses the player's requested 30-second
-- sequential recharge timer and never reads those hidden times.

local Tracker = _G.JustACBridgeCooldownReadyTracker or {}
_G.JustACBridgeCooldownReadyTracker = Tracker

local records = {}
local spellRecords = {}
local trinketRecords = {}
local ready = {}
local resolveSpellID
local debugLogger
local UPDATE_RETRY_COUNT = 30
local DEATH_AND_DECAY_RECHARGE_SECONDS = 30
local TRINKET_SLOTS = { 13, 14 }

local function isDeathAndDecaySpell(spellID)
    return spellID == 43265 or spellID == 152280
end

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function visibleNumber(value)
    return type(value) == "number" and not isSecret(value)
end

local function log(message)
    if type(debugLogger) == "function" then
        pcall(debugLogger, "COOLDOWN " .. tostring(message))
    end
end

local function makeCooldownFrame(record)
    if record.frame or not CreateFrame then
        return record.frame
    end
    local frame = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    -- Keep the Cooldown genuinely shown and drawable. A fully transparent
    -- widget with swipe/edge/countdown all disabled can be culled by the UI
    -- renderer, which also prevents its OnCooldownDone script from running.
    -- Put a normal 2px widget completely outside the viewport instead.
    frame:SetSize(2, 2)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -32, -32)
    frame:EnableMouse(false)
    if frame.SetHideCountdownNumbers then frame:SetHideCountdownNumbers(true) end
    frame:SetScript("OnCooldownDone", function()
        if not record.monitoring then return end
        record.monitoring = false
        log(("done kind=%s name=%s spell=%s item=%s slot=%s")
            :format(tostring(record.kind), tostring(record.name),
                tostring(record.spellID), tostring(record.itemID), tostring(record.slot)))
        record.readyPending = {
            kind = record.kind,
            name = record.name,
            spellID = record.spellID,
            itemID = record.itemID,
            slot = record.slot,
        }
        -- Resolve the new charge count on a later frame. This avoids reading
        -- the old 0/2 or 1/2 value at the exact boundary where the Cooldown
        -- widget finishes but C_Spell has not published the increment yet.
        record.readyDelayUpdates = 1

        -- A charge spell can immediately begin recharging its next charge.
        -- Defer one update so the charge count/start time has advanced, then
        -- arm the same widget again. This is what catches 1/2 -> 2/2.
        if record.kind == "spell" then
            record.pending = true
            record.deferUpdates = 1
            record.retries = UPDATE_RETRY_COUNT
        end
    end)
    record.frame = frame
    return frame
end

local function setCooldown(record, startTime, duration, modRate)
    if startTime == nil or duration == nil then return false end
    if visibleNumber(startTime) and visibleNumber(duration)
        and (startTime <= 0 or duration <= 0) then
        return false
    end
    if modRate == nil or (visibleNumber(modRate) and modRate <= 0) then
        modRate = 1
    end
    local frame = makeCooldownFrame(record)
    if not frame or not frame.SetCooldown then return false end
    record.monitoring = true
    local ok = pcall(frame.SetCooldown, frame, startTime, duration, modRate)
    if not ok then record.monitoring = false end
    log(("arm kind=%s name=%s spell=%s item=%s slot=%s ok=%s")
        :format(tostring(record.kind), tostring(record.name), tostring(record.spellID),
            tostring(record.itemID), tostring(record.slot), tostring(ok)))
    return ok
end

local function armSpell(record)
    if not C_Spell then return false end
    local spellID = record.spellID
    if C_Spell.GetSpellCharges then
        local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and type(charges) == "table" then
            local current = charges.currentCharges
            local maximum = charges.maxCharges
            if visibleNumber(current) and visibleNumber(maximum) then
                if current >= maximum then return false end
                return setCooldown(record, charges.cooldownStartTime,
                    charges.cooldownDuration, charges.chargeModRate)
            end
        end
    end
    if not C_Spell.GetSpellCooldown then return false end
    local ok, cooldown = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cooldown) ~= "table" then return false end
    return setCooldown(record, cooldown.startTime, cooldown.duration, cooldown.modRate)
end

local function armTrinket(record)
    if not GetInventoryItemCooldown then return false end
    local ok, startTime, duration, enabled = pcall(GetInventoryItemCooldown, "player", record.slot)
    if not ok or (visibleNumber(enabled) and enabled == 0) then return false end
    return setCooldown(record, startTime, duration, 1)
end

local function arm(record)
    if record.monitoring then return true end
    if record.kind == "spell" then return armSpell(record) end
    return armTrinket(record)
end

local function queueArm(record)
    record.pending = true
    record.deferUpdates = 1
    record.retries = UPDATE_RETRY_COUNT
end

local function cancelFixedRecharge(record)
    record.fixedRechargeGeneration = (record.fixedRechargeGeneration or 0) + 1
    if record.fixedRechargeTimer and record.fixedRechargeTimer.Cancel then
        pcall(record.fixedRechargeTimer.Cancel, record.fixedRechargeTimer)
    end
    record.fixedRechargeTimer = nil
    record.fixedRechargeMissing = 0
end

local function scheduleFixedRecharge(record)
    if record.fixedRechargeTimer or not C_Timer then return end
    local generation = record.fixedRechargeGeneration or 0
    local function completed()
        if not records[record] or generation ~= (record.fixedRechargeGeneration or 0) then
            return
        end
        record.fixedRechargeTimer = nil
        record.fixedRechargeMissing = math.max(0, (record.fixedRechargeMissing or 1) - 1)
        local chargeCount = math.max(1, 2 - record.fixedRechargeMissing)
        ready[#ready + 1] = {
            kind = "spell",
            name = record.name,
            spellID = record.spellID,
            charges = chargeCount,
            maxCharges = 2,
            fixedTimer = true,
        }
        log(("fixed-dnd-done charges=%s missing=%s")
            :format(tostring(chargeCount), tostring(record.fixedRechargeMissing)))
        if record.fixedRechargeMissing > 0 then
            scheduleFixedRecharge(record)
        else
            record.monitoring = false
        end
    end
    if C_Timer.NewTimer then
        record.fixedRechargeTimer = C_Timer.NewTimer(DEATH_AND_DECAY_RECHARGE_SECONDS, completed)
    elseif C_Timer.After then
        -- After has no cancellation handle; the generation check still makes
        -- resets/spec changes harmless.
        record.fixedRechargeTimer = true
        C_Timer.After(DEATH_AND_DECAY_RECHARGE_SECONDS, completed)
    end
    record.monitoring = record.fixedRechargeTimer ~= nil
    log(("fixed-dnd-arm seconds=%s missing=%s")
        :format(tostring(DEATH_AND_DECAY_RECHARGE_SECONDS),
            tostring(record.fixedRechargeMissing)))
end

local function recordFixedDeathAndDecayCast(record)
    record.monitoring = false
    record.pending = false
    record.fixedRechargeMissing = math.min(2, (record.fixedRechargeMissing or 0) + 1)
    if record.fixedRechargeTimer then
        record.monitoring = true
    else
        scheduleFixedRecharge(record)
    end
end

local function resolvedSpellID(spellID)
    spellID = tonumber(spellID)
    if not spellID or type(resolveSpellID) ~= "function" then return spellID end
    local ok, resolved = pcall(resolveSpellID, spellID)
    return ok and tonumber(resolved) or spellID
end

local function itemSpell(itemID)
    if C_Item and C_Item.GetItemSpell then
        local ok, name, spellID = pcall(C_Item.GetItemSpell, itemID)
        if ok and tonumber(spellID) then return name, tonumber(spellID) end
    end
    if GetItemSpell then
        local ok, name, spellID = pcall(GetItemSpell, itemID)
        if ok and tonumber(spellID) then return name, tonumber(spellID) end
    end
    return nil, nil
end

local function itemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local ok, name = pcall(C_Item.GetItemNameByID, itemID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

function Tracker.Configure(spellRules, resolver)
    resolveSpellID = resolver
    local nextSpellRecords = {}
    for index, rule in ipairs(spellRules or {}) do
        for _, configuredID in ipairs(rule.spells or {}) do
            local spellID = resolvedSpellID(configuredID)
            if spellID and spellID > 0 and not nextSpellRecords[spellID] then
                local record = spellRecords[spellID] or {
                    kind = "spell",
                    spellID = spellID,
                }
                record.name = rule.name or record.name or ("法术 " .. spellID)
                nextSpellRecords[spellID] = record
                records[record] = true
                if not isDeathAndDecaySpell(spellID) then
                    queueArm(record) -- Resume observable non-DnD cooldowns after reload.
                end
            end
        end
    end
    for spellID, record in pairs(spellRecords) do
        if not nextSpellRecords[spellID] then
            cancelFixedRecharge(record)
            record.monitoring = false
            record.pending = false
            records[record] = nil
        end
    end
    spellRecords = nextSpellRecords
    log(("configured spells=%d"):format(#(spellRules or {})))
end

function Tracker.RefreshEquipment()
    local next = {}
    for index, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        itemID = tonumber(itemID)
        if itemID then
            local _, spellID = itemSpell(itemID)
            -- GetItemSpell only returns an item's usable spell. Passive/proc
            -- trinkets therefore never enter this tracker.
            if spellID then
                local record = trinketRecords[slot]
                if not record or record.itemID ~= itemID or record.spellID ~= spellID then
                    if record then records[record] = nil; record.monitoring = false end
                    record = { kind = "trinket", slot = slot, itemID = itemID, spellID = spellID }
                end
                local equippedName = itemName(itemID)
                record.name = ("饰品%d"):format(index)
                    .. (equippedName and (" · " .. equippedName) or "")
                next[slot] = record
                records[record] = true
                queueArm(record) -- Resume a real equipped-item cooldown after reload/swap.
                log(("trinket-detected slot=%s item=%s spell=%s name=%s")
                    :format(tostring(slot), tostring(itemID), tostring(spellID), tostring(record.name)))
            end
        end
    end
    for slot, record in pairs(trinketRecords) do
        if next[slot] ~= record then
            record.monitoring = false
            record.pending = false
            records[record] = nil
        end
    end
    trinketRecords = next
end

function Tracker.OnSpellcastSucceeded(spellID)
    spellID = tonumber(spellID)
    if not spellID then return false end
    local matched = false
    local resolved = resolvedSpellID(spellID)
    for configuredID, record in pairs(spellRecords) do
        if configuredID == spellID or configuredID == resolved then
            if isDeathAndDecaySpell(spellID) or isDeathAndDecaySpell(configuredID) then
                recordFixedDeathAndDecayCast(record)
            else
                record.monitoring = false
                queueArm(record)
            end
            matched = true
        end
    end
    for _, record in pairs(trinketRecords) do
        if record.spellID == spellID then
            record.monitoring = false
            queueArm(record)
            matched = true
        end
    end
    if matched then log("cast-matched spell=" .. tostring(spellID)) end
    return matched
end

function Tracker.Update()
    for record in pairs(records) do
        if record.readyPending then
            if (record.readyDelayUpdates or 0) > 0 then
                record.readyDelayUpdates = record.readyDelayUpdates - 1
            else
                local event = record.readyPending
                if record.kind == "spell" and C_Spell and C_Spell.GetSpellCharges then
                    local ok, charges = pcall(C_Spell.GetSpellCharges, record.spellID)
                    if ok and type(charges) == "table"
                        and visibleNumber(charges.currentCharges)
                        and visibleNumber(charges.maxCharges) then
                        event.charges = math.max(0, math.floor(charges.currentCharges))
                        event.maxCharges = math.max(0, math.floor(charges.maxCharges))
                    end
                end
                ready[#ready + 1] = event
                record.readyPending = nil
            end
        end
        if record.pending and not record.monitoring then
            if (record.deferUpdates or 0) > 0 then
                record.deferUpdates = record.deferUpdates - 1
            else
                record.retries = (record.retries or UPDATE_RETRY_COUNT) - 1
                if arm(record) then
                    record.pending = false
                elseif record.retries <= 0 then
                    record.pending = false
                    log(("idle kind=%s name=%s spell=%s item=%s slot=%s")
                        :format(tostring(record.kind), tostring(record.name),
                            tostring(record.spellID), tostring(record.itemID), tostring(record.slot)))
                end
            end
        end
    end
end

function Tracker.SetDebugLogger(logger)
    debugLogger = type(logger) == "function" and logger or nil
end

function Tracker.GetStatus()
    local result = { spells = {}, trinkets = {} }
    for spellID, record in pairs(spellRecords) do
        result.spells[#result.spells + 1] = {
            spellID = spellID,
            name = record.name,
            monitoring = record.monitoring == true,
            pending = record.pending == true,
        }
    end
    for slot, record in pairs(trinketRecords) do
        result.trinkets[#result.trinkets + 1] = {
            slot = slot,
            itemID = record.itemID,
            spellID = record.spellID,
            name = record.name,
            monitoring = record.monitoring == true,
            pending = record.pending == true,
        }
    end
    table.sort(result.spells, function(left, right) return left.spellID < right.spellID end)
    table.sort(result.trinkets, function(left, right) return left.slot < right.slot end)
    return result
end

function Tracker.DrainReady()
    local result = ready
    ready = {}
    return result
end

function Tracker.Reset()
    ready = {}
    for record in pairs(records) do
        cancelFixedRecharge(record)
        record.monitoring = false
        record.pending = false
        record.deferUpdates = 0
        record.readyPending = nil
        record.readyDelayUpdates = 0
    end
end

Tracker._Test = {
    GetSpellRecord = function(spellID) return spellRecords[spellID] end,
    GetTrinketRecord = function(slot) return trinketRecords[slot] end,
}
