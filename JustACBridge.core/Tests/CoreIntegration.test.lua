-- Lightweight WoW-runtime integration smoke test.
-- Run from repository root with a Lua-compatible CLI.

local now = 100
local speed = 0
local speedSecret = false
local eventFrame
local soundCount = 0
local voiceCount = 0

local function makeWidget()
    local widget = {}
    local methods = {
        CreateTexture = function() return makeWidget() end,
        CreateFontString = function() return makeWidget() end,
        SetScript = function(self, name, callback) self[name] = callback end,
        GetEffectiveScale = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        IsShown = function(self) return self.shown ~= false end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetText = function(self, text) self.text = text end,
    }
    return setmetatable(widget, {
        __index = function(self, key)
            local method = methods[key] or function() end
            rawset(self, key, method)
            return method
        end,
    })
end

UIParent = makeWidget()
SlashCmdList = {}
C_Item = {
    GetItemNameByID = function(id) return "Item " .. id end,
    GetItemIconByID = function() return 134400 end,
}
C_Spell = {
    GetSpellInfo = function(id)
        return { name = "Spell " .. id, iconID = 134400, castTime = 0 }
    end,
    GetSpellCooldown = function() return nil end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return nil end,
}
C_TTSSettings = {
    GetVoiceOptionID = function() return 1 end,
}
C_VoiceChat = {
    SpeakText = function() voiceCount = voiceCount + 1 end,
}

function CreateFrame()
    local frame = makeWidget()
    if not eventFrame then eventFrame = frame end
    return frame
end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
function GetSpecialization() return 3 end
function GetBuildInfo() return "12.0.7", "", "", 120007 end
function GetUnitSpeed() return speed end
function GetTime() return now end
function time() return 100000 end
function IsPlayerSpell() return true end
function issecretvalue(value) return speedSecret and value == speed end
function PlaySound() soundCount = soundCount + 1 end

dofile("JustACBridge.core/Sources/Registry.lua")
dofile("JustACBridge.core/Sources/JustAC.lua")

assert(JustACBridgeRecommendationSources.Register("test", {
    name = "Test Source",
    GetQueue = function() return { 43265, 47541 } end,
    GetSpellHotkey = function(id) return id == 43265 and "1" or "2" end,
    GetDisplaySpellID = function(id) return id end,
    IsSpellUsable = function() return true end,
    IsSpellProcced = function() return false end,
    IsChanneled = function() return false end,
    IsConfirmedOutOfRange = function() return false end,
    GetDetectedBurstTriggers = function() return {} end,
}))

dofile("JustACBridge.core/Policies/Registry.lua")
dofile("JustACBridge.core/Policies/Mage.lua")
dofile("JustACBridge.core/Policies/Mage/Arcane.lua")
dofile("JustACBridge.core/Policies/Mage/Fire.lua")
dofile("JustACBridge.core/Policies/Mage/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Blood.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Unholy.lua")
dofile("JustACBridge.core/Trackers/GroundEffects.lua")
dofile("JustACBridge.core/JustACBridge.lua")

eventFrame.OnEvent(eventFrame, "PLAYER_LOGIN")
assert(JustACBridge.GetRecommendationSource().id == "test")
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)

eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 43265)
JustACBridge.Refresh()
local active = JustACBridge.GetGroundEffects()
assert(#active == 1 and active[1].expiresAt == 110)
local fallback = JustACBridge.GetCurrentRecommendation()
assert(fallback.spellID == 47541 and fallback.groundFallback == true)

now = 110
eventFrame.OnUpdate(eventFrame, 0.1)
assert(#JustACBridge.GetGroundEffects() == 0)
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
assert(soundCount == 1)
assert(voiceCount == 1)

-- A movement-safe recommendation can still be rejected by the game at cast
-- time.  Three rapid failures must temporarily advance both selectors instead
-- of hammering the same dead action forever.
speed = 7
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)
for index = 1, 3 do
    eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player", "cast-fail-" .. index, 43265)
end
JustACBridge.Refresh()
local failureFallback = JustACBridge.GetCurrentRecommendation()
assert(failureFallback.spellID == 47541 and failureFallback.failureFallback == true)

now = 111.1
JustACBridge.Refresh()
assert(JustACBridge.GetCurrentRecommendation().spellID == 43265)

-- Midnight can report speed as secret and emit START/STOP movement events in
-- the same frame while a stationary channel resists movement.  The STOP must
-- be debounced, and movement intent must be allowed to interrupt the channel.
speedSecret = true
eventFrame.OnEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player", "channel-1", 205021)
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
local movingChannel = JustACBridge.GetPlayerCastState()
assert(movingChannel.isMoving == true and movingChannel.channelBlocksInput == false)

now = 111.2
eventFrame.OnEvent(eventFrame, "PLAYER_STARTED_MOVING")
eventFrame.OnEvent(eventFrame, "PLAYER_STOPPED_MOVING")
JustACBridge.Refresh()
assert(JustACBridge.IsPlayerMoving() == true)

now = 111.5
JustACBridge.Refresh()
assert(JustACBridge.IsPlayerMoving() == false)

print("core integration tests passed")
