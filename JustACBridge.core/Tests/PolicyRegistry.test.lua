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
dofile("JustACBridge.core/Policies/Hunter.lua")
dofile("JustACBridge.core/Policies/Hunter/BeastMastery.lua")
dofile("JustACBridge.core/Policies/Hunter/Marksmanship.lua")
dofile("JustACBridge.core/Policies/Hunter/Survival.lua")

local registry = JustACBridgePolicyRegistry
assert(registry.schemaVersion == 26)

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
assert(arcane121.revision == 34)
assert(#arcane121.reserveExclusions == 0)
assert(arcane121.useDetectedBurstTriggers == false)
assert(#arcane121.offGCD == 1 and arcane121.offGCD[1] == 321507)
assert(#arcane121.castSequenceRules == 0)
assert(#arcane121.pairedCastRules == 1)
assert(arcane121.pairedCastRules[1].leaderSpellID == 365350
    and arcane121.pairedCastRules[1].followerSpellID == 321507
    and arcane121.pairedCastRules[1].withinSeconds == 10
    and arcane121.pairedCastRules[1].targetBound == true
    and arcane121.pairedCastRules[1]
        .directFollowerMinLeaderCooldownRemainingSeconds == nil)
assert(arcane121.preserveUsesCurrentSafety == true)
assert(#arcane121.movementFallbackProofSpells == 1
    and arcane121.movementFallbackProofSpells[1] == 44425)
assert(#arcane121.rotationExclusions == 0)
assert(#arcane121.rotationEffectiveExclusions == 1
    and arcane121.rotationEffectiveExclusions[1] == 1449)
assert(#arcane121.clipChannels == 0)
assert(#arcane121.protectedChannels == 1 and arcane121.protectedChannels[1] == 5143)
assert(#arcane121.moveCastConditions == 2)
assert(arcane121.moveCastConditions[1].spellID == 5143)
assert(arcane121.moveCastConditions[1].requiresSpell == 236457)
assert(arcane121.moveCastConditions[1].auraID == 263725)
assert(arcane121.moveCastConditions[1].probeWhenUsable == true)
assert(arcane121.moveCastConditions[2].spellID == 30451)
assert(arcane121.moveCastConditions[2].auraID == 205025)
assert(#arcane121.moveCastResumeDelays == 2)
assert(arcane121.moveCastResumeDelays[1].spellID == 153626)
assert(arcane121.moveCastResumeDelays[1].seconds == 0.8)
assert(arcane121.moveCastResumeDelays[1].lossless == true)
assert(arcane121.moveCastResumeDelays[1].preserve == true)
assert(arcane121.moveCastResumeDelays[2].spellID == 153640)
assert(arcane121.moveCastResumeDelays[2].seconds == 0.8)
assert(arcane121.moveCastResumeDelays[2].lossless == true)
assert(arcane121.moveCastResumeDelays[2].preserve == true)
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

local frostMage121 = assert(registry.Resolve("MAGE", 3, 120100))
assert(frostMage121.ruleset == "midnight-12.1")
assert(frostMage121.revision == 16)
assert(#frostMage121.reserve == 1 and frostMage121.reserve[1] == 205021)
assert(frostMage121.useDetectedBurstTriggers == false)

local fire = assert(registry.Resolve("MAGE", 2, 120100))
assert(fire.ruleset == "midnight-12.1" and fire.revision == 6)
assert(#fire.reserve == 2 and fire.reserve[1] == 190319 and fire.reserve[2] == 153561)
assert(#fire.reserveExclusions == 1 and fire.reserveExclusions[1] == 2120)
assert(#fire.moveCastAlways == 1 and fire.moveCastAlways[1] == 2948)
assert(#fire.moveCastInstantOnly == 2)
assert(#fire.maintenanceBuffs == 1)
assert(fire.maintenanceBuffs[1].spellID == 235313)
assert(fire.maintenanceBuffs[1].auraID == 235313)
assert(fire.maintenanceBuffs[1].preserve == true)
assert(fire.maintenanceBuffs[1].reserveCharges == 1)
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
assert(frostDK121.ruleset == "midnight-12.1" and frostDK121.revision == 16)
assert(frostDK121.useDetectedBurstTriggers == false)
assert(frostDK121.preserveSourceQueueOnly == true)
assert(#frostDK121.fallbackActions == 0)
assert(frostDK121.losslessSourceQueueOnlyBeyond.beyond == 5
    and frostDK121.losslessSourceQueueOnlyBeyond.allow[1] == 49184)
assert(frostDK121.preserveSourceQueueOnlyBeyond.beyond == 5
    and frostDK121.preserveSourceQueueOnlyBeyond.allow[1] == 49184)
assert(#frostDK121.reserve == 5)
assert(frostDK121.reserve[1] == 51271)
assert(frostDK121.reserve[4] == 279302 and frostDK121.reserve[5] == 439843)
assert(#frostDK121.rotationExclusions == 1 and frostDK121.rotationExclusions[1] == 49576)
assert(#frostDK121.reserveExclusions == 2)
assert(frostDK121.reserveExclusions[1] == 194913
    and frostDK121.reserveExclusions[2] == 207230)
assert(#frostDK121.castSequenceRules == 1)
assert(frostDK121.castSequenceRules[1].spellID == 279302
    and frostDK121.castSequenceRules[1].afterSpellID == 51271
    and frostDK121.castSequenceRules[1].afterAuraID == 51271
    and frostDK121.castSequenceRules[1].withinSeconds == 10)
assert(#frostDK121.castSequenceRules[1].passthroughEffectiveSpellIDs == 1
    and frostDK121.castSequenceRules[1].passthroughEffectiveSpellIDs[1] == 1265384)
assert(#frostDK121.castFollowups == 1)
assert(frostDK121.castFollowups[1].spellID == 46585
    and frostDK121.castFollowups[1].triggerSpells[1] == 279302
    and frostDK121.castFollowups[1].withinSeconds == 4
    and frostDK121.castFollowups[1].lossless == true
    and frostDK121.castFollowups[1].preserve == false)

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

local unholy121 = assert(registry.Resolve("DEATHKNIGHT", 3, 120100))
assert(unholy121.ruleset == "midnight-12.1" and unholy121.revision == 6)
assert(unholy121.useDetectedBurstTriggers == false)
assert(unholy121.preserveSourceQueueOnly == true)
assert(#unholy121.fallbackActions == 0)
assert(#unholy121.reserve == 3)
assert(unholy121.reserve[1] == 63560
    and unholy121.reserve[2] == 1233448
    and unholy121.reserve[3] == 42650)

local beastMastery = assert(registry.Resolve("HUNTER", 1, 120100))
assert(beastMastery.ruleset == "midnight-12.1" and beastMastery.revision == 1)
assert(beastMastery.useDetectedBurstTriggers == false)
assert(beastMastery.preserveSourceQueueOnly == true)
assert(#beastMastery.reserve == 1 and beastMastery.reserve[1] == 19574)
assert(#beastMastery.fallbackActions == 0)
assert(#beastMastery.moveCastNever == 2)
assert(beastMastery.moveCastNever[1] == 392060
    and beastMastery.moveCastNever[2] == 355589)
assert(#beastMastery.rotationExclusions == 7)
assert(beastMastery.rotationExclusions[1] == 781
    and beastMastery.rotationExclusions[7] == 190925)

local marksmanship = assert(registry.Resolve("HUNTER", 2, 120100))
assert(marksmanship.ruleset == "midnight-12.1" and marksmanship.revision == 1)
assert(marksmanship.useDetectedBurstTriggers == false)
assert(marksmanship.preserveSourceQueueOnly == true)
assert(#marksmanship.reserve == 1 and marksmanship.reserve[1] == 288613)
assert(#marksmanship.reserveExclusions == 1
    and marksmanship.reserveExclusions[1] == 260243)
assert(#marksmanship.moveCastAlways == 1
    and marksmanship.moveCastAlways[1] == 257044)
assert(#marksmanship.protectedChannels == 1
    and marksmanship.protectedChannels[1] == 257044)
assert(#marksmanship.moveCastNever == 2)
assert(#marksmanship.fallbackActions == 0)

local survival = assert(registry.Resolve("HUNTER", 3, 120100))
assert(survival.ruleset == "midnight-12.1" and survival.revision == 1)
assert(survival.useDetectedBurstTriggers == false)
assert(survival.preserveSourceQueueOnly == true)
assert(#survival.reserve == 2)
assert(survival.reserve[1] == 1250646 and survival.reserve[2] == 1261193)
assert(#survival.reserveExclusions == 2)
assert(survival.reserveExclusions[1] == 1261193
    and survival.reserveExclusions[2] == 1262343)
assert(#survival.reserveEffectiveExclusions == 1
    and survival.reserveEffectiveExclusions[1] == 1262343)
assert(#survival.protectedChannels == 1
    and survival.protectedChannels[1] == 1261193)
assert(#survival.moveCastAlways == 1
    and survival.moveCastAlways[1] == 1261193)
assert(#survival.fallbackActions == 0)

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
