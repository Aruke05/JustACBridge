-- Run from repository root with a Lua-compatible CLI.

local now = 100
local charges = {}
local itemCooldowns = {}
local equipped = { [13] = 1001, [14] = 1002 }
local timers = {}

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
C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
}

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

-- DnD deliberately uses a fixed 30-second recharge queue. Two casts during
-- the first recharge produce one alert at 30 seconds and the second at 60,
-- matching sequential WoW charge recovery without reading secret times.
charges[43265] = {
    currentCharges = 0,
    maxCharges = 2,
    cooldownStartTime = 100,
    cooldownDuration = 10,
    chargeModRate = 1,
}
assert(tracker.OnSpellcastSucceeded(43265))
assert(tracker.OnSpellcastSucceeded(43265))
local spellRecord = tracker._Test.GetSpellRecord(43265)
assert(spellRecord.monitoring and #timers == 1 and timers[1].delay == 30)

now = 130
timers[1].callback()
local firstReady = tracker.DrainReady()
assert(#firstReady == 1 and firstReady[1].spellID == 43265
    and firstReady[1].charges == 1 and firstReady[1].maxCharges == 2
    and firstReady[1].fixedTimer == true)
assert(spellRecord.monitoring and #timers == 2 and timers[2].delay == 30)

now = 160
timers[2].callback()
local secondReady = tracker.DrainReady()
assert(#secondReady == 1 and secondReady[1].spellID == 43265
    and secondReady[1].charges == 2 and secondReady[1].maxCharges == 2)
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
tracker.Update()
tracker.Update()
local trinketReady = tracker.DrainReady()
assert(#trinketReady == 1 and trinketReady[1].slot == 13
    and trinketReady[1].itemID == 1001)

print("cooldown-ready tracker tests passed")
