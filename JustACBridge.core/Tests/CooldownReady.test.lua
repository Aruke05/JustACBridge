-- Run from repository root with a Lua-compatible CLI.

local now = 100
local charges = {}
local itemCooldowns = {}
local equipped = { [13] = 1001, [14] = 1002 }

function GetTime() return now end
UIParent = {}

local function widget()
    local frame = {}
    return setmetatable(frame, {
        __index = function(self, key)
            local method
            if key == "SetScript" then
                method = function(target, event, callback) target[event] = callback end
            elseif key == "SetCooldown" then
                method = function(target, startTime, duration, modRate)
                    target.cooldown = { startTime, duration, modRate }
                end
            else
                method = function() end
            end
            rawset(self, key, method)
            return method
        end,
    })
end

function CreateFrame() return widget() end
function GetInventoryItemID(_, slot) return equipped[slot] end
function GetInventoryItemCooldown(_, slot)
    local cooldown = itemCooldowns[slot] or { 0, 0, 1 }
    return cooldown[1], cooldown[2], cooldown[3]
end

C_Spell = {
    GetSpellCharges = function(spellID) return charges[spellID] end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0, modRate = 1 } end,
}
C_Item = {
    GetItemSpell = function(itemID)
        if itemID == 1001 then return "Use Trinket", 9001 end
        return nil, nil -- slot 14 is a passive/proc trinket
    end,
    GetItemNameByID = function(itemID) return itemID == 1001 and "Active Trinket" or "Passive Trinket" end,
}

dofile("JustACBridge.core/Trackers/CooldownReady.lua")
local tracker = JustACBridgeCooldownReadyTracker

charges[43265] = {
    currentCharges = 2,
    maxCharges = 2,
    cooldownStartTime = 0,
    cooldownDuration = 0,
    chargeModRate = 1,
}
tracker.Configure({ { name = "Death and Decay", spells = { 43265 } } })

-- One cast spends both available charges in this synthetic sequence. The
-- widget must announce 0/2 -> 1/2, re-arm, then also announce 1/2 -> 2/2.
charges[43265] = {
    currentCharges = 0,
    maxCharges = 2,
    cooldownStartTime = 100,
    cooldownDuration = 10,
    chargeModRate = 1,
}
assert(tracker.OnSpellcastSucceeded(43265))
tracker.Update() -- one-frame API synchronization delay
tracker.Update() -- arms the first recharge
local spellRecord = tracker._Test.GetSpellRecord(43265)
assert(spellRecord.monitoring and spellRecord.frame.cooldown[2] == 10)

now = 110
charges[43265].currentCharges = 1
charges[43265].cooldownStartTime = 110
spellRecord.frame.OnCooldownDone()
local firstReady = tracker.DrainReady()
assert(#firstReady == 1 and firstReady[1].spellID == 43265)
tracker.Update()
tracker.Update()
assert(spellRecord.monitoring and spellRecord.frame.cooldown[1] == 110)

now = 120
charges[43265].currentCharges = 2
spellRecord.frame.OnCooldownDone()
local secondReady = tracker.DrainReady()
assert(#secondReady == 1 and secondReady[1].spellID == 43265)
tracker.Update()
tracker.Update()
assert(not spellRecord.monitoring) -- full 2/2 has no third timer

-- Only a trinket with GetItemSpell is considered active. An already-running
-- equipped cooldown is resumed, including after login/reload.
itemCooldowns[13] = { 100, 90, 1 }
tracker.RefreshEquipment()
tracker.Update()
tracker.Update()
local active = tracker._Test.GetTrinketRecord(13)
assert(active and active.monitoring and active.name:match("饰品1"))
assert(tracker._Test.GetTrinketRecord(14) == nil)

now = 190
active.frame.OnCooldownDone()
local trinketReady = tracker.DrainReady()
assert(#trinketReady == 1 and trinketReady[1].slot == 13
    and trinketReady[1].itemID == 1001)

print("cooldown-ready tracker tests passed")

