-- Announces authoritative cooldown completions through hidden Cooldown widgets.
--
-- Patch 12.x may mark numeric cooldown values as secret in combat. Addons may
-- still pass those values to a Cooldown widget, whose OnCooldownDone event is
-- the reliable boundary we need. Never perform arithmetic on those values.

local Tracker = _G.JustACBridgeCooldownReadyTracker or {}
_G.JustACBridgeCooldownReadyTracker = Tracker

local records = {}
local spellRecords = {}
local trinketRecords = {}
local ready = {}
local resolveSpellID
local UPDATE_RETRY_COUNT = 30
local TRINKET_SLOTS = { 13, 14 }

local function isSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function visibleNumber(value)
    return type(value) == "number" and not isSecret(value)
end

local function makeCooldownFrame(record)
    if record.frame or not CreateFrame then
        return record.frame
    end
    local frame = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    frame:SetSize(1, 1)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -4, -4)
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    if frame.SetDrawEdge then frame:SetDrawEdge(false) end
    if frame.SetDrawSwipe then frame:SetDrawSwipe(false) end
    if frame.SetHideCountdownNumbers then frame:SetHideCountdownNumbers(true) end
    frame:SetScript("OnCooldownDone", function()
        if not record.monitoring then return end
        record.monitoring = false
        ready[#ready + 1] = {
            kind = record.kind,
            name = record.name,
            spellID = record.spellID,
            itemID = record.itemID,
            slot = record.slot,
        }

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
                queueArm(record) -- Also catches a recharge already running at login/reload.
            end
        end
    end
    for spellID, record in pairs(spellRecords) do
        if not nextSpellRecords[spellID] then
            record.monitoring = false
            record.pending = false
            records[record] = nil
        end
    end
    spellRecords = nextSpellRecords
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
            record.monitoring = false
            queueArm(record)
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
    return matched
end

function Tracker.Update()
    for record in pairs(records) do
        if record.pending and not record.monitoring then
            if (record.deferUpdates or 0) > 0 then
                record.deferUpdates = record.deferUpdates - 1
            else
                record.retries = (record.retries or UPDATE_RETRY_COUNT) - 1
                if arm(record) then
                    record.pending = false
                elseif record.retries <= 0 then
                    record.pending = false
                end
            end
        end
    end
end

function Tracker.DrainReady()
    local result = ready
    ready = {}
    return result
end

function Tracker.Reset()
    ready = {}
    for record in pairs(records) do
        record.monitoring = false
        record.pending = false
        record.deferUpdates = 0
    end
end

Tracker._Test = {
    GetSpellRecord = function(spellID) return spellRecords[spellID] end,
    GetTrinketRecord = function(slot) return trinketRecords[slot] end,
}
