-- Run from the repository root with any Lua-compatible CLI:
--   lua JustACBridge.core/Tests/PolicyRegistry.test.lua

function GetBuildInfo()
    return "12.0.7", "", "", 120007
end

dofile("JustACBridge.core/Policies/Registry.lua")
dofile("JustACBridge.core/Policies/Mage.lua")
dofile("JustACBridge.core/Policies/Mage/Arcane.lua")
dofile("JustACBridge.core/Policies/Mage/Fire.lua")
dofile("JustACBridge.core/Policies/Mage/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Blood.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Frost.lua")
dofile("JustACBridge.core/Policies/DeathKnight/Unholy.lua")

local registry = JustACBridgePolicyRegistry
assert(registry.schemaVersion == 19)

local arcane = assert(registry.Resolve("MAGE", 1, 120007))
assert(arcane.storageKey == "MAGE_1" and arcane.id == "arcane")
assert(arcane.ruleset == "base")
assert(#arcane.reserve == 2)
assert(arcane.reserve[1] == 365350 and arcane.reserve[2] == 321507)
assert(#arcane.reservePassthrough == 1 and arcane.reservePassthrough[1] == 12051)
assert(#arcane.reserveExclusions == 2)
assert(arcane.reserveExclusions[1] == 153626 and arcane.reserveExclusions[2] == 153640)
assert(#arcane.reserveEffectiveExclusions == 1
    and arcane.reserveEffectiveExclusions[1] == 1449)
assert(#arcane.moveCastAlways == 1 and arcane.moveCastAlways[1] == 2948)
assert(#arcane.moveCastBuffs == 1 and arcane.moveCastBuffs[1] == 108839)
assert(#arcane.clipChannels == 0)
assert(#arcane.fallbackActions == 0)
assert(#arcane.maintenanceBuffs == 0)
assert(#arcane.priorityCues == 0)

local arcane121 = assert(registry.Resolve("MAGE", 1, 120100))
assert(arcane121.ruleset == "midnight-12.1")
assert(arcane121.revision == 24)
assert(#arcane121.reserveExclusions == 0)
assert(arcane121.useDetectedBurstTriggers == false)
assert(arcane121.preserveUsesCurrentSafety == true)
assert(#arcane121.rotationExclusions == 0)
assert(#arcane121.rotationEffectiveExclusions == 1
    and arcane121.rotationEffectiveExclusions[1] == 1449)
assert(#arcane121.clipChannels == 0)
assert(#arcane121.protectedChannels == 1 and arcane121.protectedChannels[1] == 5143)
assert(#arcane121.moveCastConditions == 2)
assert(arcane121.moveCastConditions[1].spellID == 5143)
assert(arcane121.moveCastConditions[1].requiresSpell == 236457)
assert(arcane121.moveCastConditions[1].auraID == 263725)
assert(arcane121.moveCastConditions[2].spellID == 30451)
assert(arcane121.moveCastConditions[2].auraID == 205025)
assert(#arcane121.moveCastResumeDelays == 2)
assert(arcane121.moveCastResumeDelays[1].spellID == 153626)
assert(arcane121.moveCastResumeDelays[1].seconds == 2.0)
assert(arcane121.moveCastResumeDelays[1].lossless == false)
assert(arcane121.moveCastResumeDelays[1].preserve == true)
assert(#arcane121.successfulCastResumeDelays == 2)
assert(arcane121.successfulCastResumeDelays[1].spellID == 153626)
assert(arcane121.successfulCastResumeDelays[1].seconds == 2.0)
assert(arcane121.successfulCastResumeDelays[1].lossless == true)
assert(arcane121.successfulCastResumeDelays[1].preserve == true)
assert(#arcane121.successfulCastResumeDelays[1].triggerSpells == 3)
assert(arcane121.successfulCastResumeDelays[1].triggerSpells[1] == 1953)
assert(arcane121.successfulCastResumeDelays[1].triggerSpells[2] == 212653)
assert(arcane121.successfulCastResumeDelays[1].triggerSpells[3] == 1294067)
assert(#arcane121.maintenanceBuffs == 1)
assert(arcane121.maintenanceBuffs[1].spellID == 235450)
assert(arcane121.maintenanceBuffs[1].auraID == 235450)
assert(arcane121.maintenanceBuffs[1].lossless == false)
assert(arcane121.maintenanceBuffs[1].preserve == true)
assert(arcane121.maintenanceBuffs[1].reserveCharges == 0)
assert(#arcane121.priorityCues == 0)

local arcaneTwwS3 = assert(registry.Resolve("MAGE", 1, 110207))
assert(arcaneTwwS3.ruleset == "tww-s3")
assert(#arcaneTwwS3.reserve == 3)
assert(arcaneTwwS3.reserve[1] == 365350 and arcaneTwwS3.reserve[3] == 321507)
assert(#arcaneTwwS3.reserveExclusions == 2)
assert(arcaneTwwS3.useDetectedBurstTriggers == true)
assert(arcaneTwwS3.preserveUsesCurrentSafety == false)
assert(#arcaneTwwS3.reservePassthrough == 0)
assert(#arcaneTwwS3.clipChannels == 1 and arcaneTwwS3.clipChannels[1] == 5143)
assert(#arcaneTwwS3.moveCastConditions == 0)
assert(#arcaneTwwS3.maintenanceBuffs == 0)
assert(#arcaneTwwS3.successfulCastResumeDelays == 0)

local frostMage = assert(registry.Resolve("MAGE", 3, 120007))
assert(frostMage.revision == 14)
assert(#frostMage.reserve == 1 and frostMage.reserve[1] == 12472)
assert(#frostMage.rangeSequenceRules == 1)
assert(frostMage.rangeSequenceRules[1].requiresSpell == 431044)
assert(frostMage.rangeSequenceRules[1].defer[1] == 199786)
assert(frostMage.rangeSequenceRules[1].prefer[1] == 44614)
assert(#frostMage.fallbackActions == 1 and frostMage.fallbackActions[1].spellID == 30455)
assert(#frostMage.protectedChannels == 1 and frostMage.protectedChannels[1] == 205021)
assert(#frostMage.maintenanceBuffs == 1)
assert(frostMage.maintenanceBuffs[1].spellID == 11426)
assert(frostMage.maintenanceBuffs[1].auraID == 11426)
assert(frostMage.maintenanceBuffs[1].reserveCharges == 1)
assert(#frostMage.reserveExclusions == 4)
assert(frostMage.reserveExclusions[1] == 84714)
assert(frostMage.reserveExclusions[4] == 120)

local fire = assert(registry.Resolve("MAGE", 2, 120100))
assert(fire.revision == 4)
assert(#fire.reserve == 2 and fire.reserve[1] == 190319 and fire.reserve[2] == 153561)
assert(#fire.reserveExclusions == 1 and fire.reserveExclusions[1] == 2120)
assert(#fire.moveCastAlways == 1 and fire.moveCastAlways[1] == 2948)
assert(#fire.moveCastInstantOnly == 2)
assert(fire.moveCastInstantOnly[1] == 11366 and fire.moveCastInstantOnly[2] == 2120)

local blood = assert(registry.Resolve("DEATHKNIGHT", 1, 120007))
assert(#blood.reserve == 2 and blood.reserve[2] == 194844)
assert(#blood.fallbackActions == 2)
assert(blood.fallbackActions[1].spellID == 50842)
assert(#blood.rotationExclusions == 1 and blood.rotationExclusions[1] == 49576)

local frostDK = assert(registry.Resolve("DEATHKNIGHT", 2, 120007))
assert(#frostDK.fallbackActions == 2)
assert(frostDK.fallbackActions[1].spellID == 49184 and frostDK.fallbackActions[1].requireProc)
assert(#frostDK.rotationExclusions == 1 and frostDK.rotationExclusions[1] == 49576)

local frostDK121 = assert(registry.Resolve("DEATHKNIGHT", 2, 120100))
assert(frostDK121.ruleset == "base" and frostDK121.revision == 10)
assert(#frostDK121.reserve == 7)
assert(frostDK121.reserve[1] == 51271)
assert(frostDK121.reserve[6] == 439843 and frostDK121.reserve[7] == 46585)
assert(#frostDK121.rotationExclusions == 1 and frostDK121.rotationExclusions[1] == 49576)
assert(#frostDK121.reserveExclusions == 2)
assert(frostDK121.reserveExclusions[1] == 194913
    and frostDK121.reserveExclusions[2] == 207230)
assert(#frostDK121.castSequenceRules == 1)
assert(frostDK121.castSequenceRules[1].spellID == 279302
    and frostDK121.castSequenceRules[1].afterSpellID == 51271
    and frostDK121.castSequenceRules[1].afterAuraID == 51271)
assert(#frostDK121.castSequenceRules[1].passthroughEffectiveSpellIDs == 1
    and frostDK121.castSequenceRules[1].passthroughEffectiveSpellIDs[1] == 1265384)

local unholy = assert(registry.Resolve("DEATHKNIGHT", 3, 120007))
assert(unholy.revision == 4)
assert(#unholy.reserve == 10 and unholy.reserve[3] == 42650)
assert(unholy.reserve[8] == 288853 and unholy.reserve[10] == 1247378)
assert(#unholy.reserveExclusions == 1 and unholy.reserveExclusions[1] == 43265)
assert(#unholy.rotationExclusions == 1 and unholy.rotationExclusions[1] == 49576)
assert(#unholy.groundEffects == 1)
assert(unholy.groundEffects[1].id == "death-and-decay")
assert(unholy.groundEffects[1].spells[2] == 152280)
assert(unholy.groundEffects[1].duration == 10)
assert(#unholy.fallbackActions == 2)
assert(unholy.fallbackActions[1].spellID == 207317 and unholy.fallbackActions[1].minEnemies == 5)
assert(unholy.fallbackActions[2].spellID == 47541)

-- An unregistered class falls back to JustAC-only behavior in the bridge core.
assert(registry.Resolve("WARRIOR", 1, 120007) == nil)

assert(registry.RegisterClass("TEST", {
    revision = 2,
    specs = {
        [1] = {
            id = "test",
            reserve = { 1001, 1002 },
            versions = {
                {
                    id = "12.1",
                    minInterface = 120100,
                    maxInterface = 120199,
                    removeReserve = { 1001 },
                    addReserve = { 1003 },
                },
                {
                    id = "13.0",
                    minInterface = 130000,
                    reserve = { 2001, 2002 },
                },
            },
        },
    },
}))

local patch121 = assert(registry.Resolve("TEST", 1, 120150))
assert(patch121.ruleset == "12.1")
assert(#patch121.reserve == 2)
assert(patch121.reserve[1] == 1002 and patch121.reserve[2] == 1003)

local patch130 = assert(registry.Resolve("TEST", 1, 130001))
assert(patch130.ruleset == "13.0")
assert(#patch130.reserve == 2)
assert(patch130.reserve[1] == 2001 and patch130.reserve[2] == 2002)

print("policy registry tests passed")
