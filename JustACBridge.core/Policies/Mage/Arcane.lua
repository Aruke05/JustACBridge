local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 1, {
    id = "arcane",
    name = "奥术",
    revision = 19,

    -- Midnight 12.0 rebuilt Arcane.  Evocation is mana recovery again rather
    -- than a Siphon Storm setup spell, so M4 must not hold it with the actual
    -- damage cooldowns.  reservePassthrough also removes it when an older
    -- JustAC Burst Trigger profile still reports it as a trigger.
    reserve = {
        365350, -- Arcane Surge
        321507, -- Touch of the Magi
    },
    reservePassthrough = {
        12051, -- Evocation
    },
    -- Arcane Orb travels along the player's facing rather than locking to the
    -- selected target. Instances do not expose enough positional information
    -- to aim it reliably, so the hold-safe M4 action must never fire it.
    reserveExclusions = {
        153626, -- Arcane Orb
        153640, -- Arcane Orb override/compatibility form
    },
    -- Compare against the action that is actually active, not just the raw
    -- queue ID. Arcane Pulse talent-replaces Arcane Explosion's 1449 button;
    -- resolving that button to Pulse must keep the valid spell available.
    reserveEffectiveExclusions = {
        1449, -- Arcane Explosion: no guessed M4 filler/fallback
    },

    -- TWW S3 used Evocation as part of the Surge/Touch setup and explicitly
    -- clipped every Arcane Missiles channel after one GCD.  Keep that behavior
    -- only on 11.2 clients; applying it to Midnight loses valid missile ticks.
    versions = {
        {
            id = "tww-s3",
            minInterface = 110200,
            maxInterface = 110299,
            revision = 4,
            reserve = {
                365350, -- Arcane Surge
                12051,  -- Evocation / Siphon Storm setup
                321507, -- Touch of the Magi
            },
            reservePassthrough = {},
            -- Preserve the historical facing-dependent hold rule on 11.2.
            reserveExclusions = {
                153626, -- Arcane Orb
                153640, -- Arcane Orb override/compatibility form
            },
            clipChannels = {
                5143, -- Arcane Missiles (including its S3 override form)
            },
        },
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 34,
            -- 12.1 M4 shares the owned Arcane priority with M5. Orb is no
            -- longer permanently excluded; both modes use the movement and
            -- stationary-resume rules below.
            reserveExclusions = {},
            -- The Arcane M4 contract is exact: hold only Surge and Touch by
            -- default. Do not let stale/custom JustAC Burst Trigger entries
            -- silently turn additional ordinary Arcane actions into M4 holds.
            -- Explicit /jacb reserve overrides remain authoritative.
            useDetectedBurstTriggers = false,
            -- Touch is explicitly use_off_gcd=1 in the current SimC APL.
            -- The action retains every normal safety/binding gate, but the
            -- desktop may send it immediately after the confirmed Barrage or
            -- Prismatic Bolt event instead of waiting for the GCD commit gate.
            offGCD = {
                321507, -- Touch of the Magi
            },
            -- Pairing contract: when Surge is currently available, hold it
            -- until Touch is also positively ready, then enforce Surge first
            -- and Touch within ten seconds. If Surge is unlearned, unbound,
            -- positively unusable or on cooldown, Touch fires directly with no
            -- remaining-cooldown threshold.
            -- Unknown readiness fails closed instead of guessing either path.
            pairedCastRules = {
                {
                    leaderSpellID = 365350,   -- Arcane Surge
                    followerSpellID = 321507, -- Touch of the Magi
                    withinSeconds = 10,
                    -- A target change invalidates the entire big-burn
                    -- credential; a Surge/Barrage setup from enemy A may never
                    -- release Touch on enemy B.
                    targetBound = true,
                },
            },
            -- Arcane M4 shares M5's proven owned actions minus Surge and Touch.
            -- JustAC fallback order remains unchanged. Use the
            -- player's real movement state instead of the generic always-moving
            -- M4 filter. Protected Missiles still lock both outputs until the
            -- real channel stop/interruption event.
            preserveUsesCurrentSafety = true,
            -- Movement may delete an uncastable action, but it must never turn
            -- a low-priority, low-Salvo Barrage into the rotation choice merely
            -- because Barrage is instant. When Barrage is taken from any queue
            -- position after the first while actually moving, the active source
            -- must positively prove an ordinary APL Barrage condition. Missing,
            -- false, secret or errored proof fails closed; a source/JustAC
            -- Barrage already at queue position 1 remains authoritative.
            movementFallbackProofSpells = {
                44425, -- Arcane Barrage
            },
            -- M4 is also the long-held mechanics key. Keep its defensive
            -- shield maintained without spending an M5 damage GCD: inject
            -- Prismatic Barrier only when the live aura is explicitly absent
            -- and the spell is known, usable, ready and bound. Any unknown
            -- runtime value fails closed in the generic maintenance gate.
            maintenanceBuffs = {
                {
                    spellID = 235450, -- Prismatic Barrier
                    auraID = 235450,
                    lossless = false,
                    preserve = true,
                    reserveCharges = 0,
                    label = "棱光护体",
                },
            },
            -- These are exact, live-observable movement exceptions rather
            -- than an invented fallback. Slipstream makes a Clearcasting
            -- Missiles channel movable; Presence of Mind makes Arcane Blast
            -- instant. If the talent/aura cannot be proven, both fail closed.
            moveCastConditions = {
                {
                    spellID = 5143,          -- Arcane Missiles
                    requiresSpell = 236457,  -- Slipstream
                    auraID = 263725,         -- Clearcasting
                    -- Combat aura enumeration can hide Clearcasting even while
                    -- JustAC still exposes a usable Missiles recommendation.
                    -- Permit one bounded moving probe per continuous movement
                    -- episode; its first failed cast blocks further probes.
                    probeWhenUsable = true,
                    label = "Slipstream + Clearcasting",
                },
                {
                    spellID = 30451,  -- Arcane Blast
                    auraID = 205025,  -- Presence of Mind
                    label = "Presence of Mind",
                },
            },
            -- Orb is instant but travels along the player's facing. While the
            -- player is moving neither held key may guess that direction. Both
            -- M5 and M4 wait for 0.8 continuous stationary seconds after every
            -- ordinary movement stop before Orb can be exported again.
            moveCastNever = {
                153626, -- Arcane Orb
                153640, -- Arcane Orb override/compatibility form
            },
            moveCastResumeDelays = {
                { spellID = 153626, seconds = 0.8, lossless = true, preserve = true },
                { spellID = 153640, seconds = 0.8, lossless = true, preserve = true },
            },
            -- A successful Blink/Shimmer changes facing without a trustworthy
            -- target-direction signal. Both M5 and M4 therefore hold Orb for
            -- two seconds from the authoritative successful-cast event. The
            -- three trigger IDs cover Blink and both live Shimmer forms seen
            -- in the current 12.1 spell data.
            successfulCastResumeDelays = {
                {
                    spellID = 153626,
                    seconds = 2.0,
                    triggerSpells = { 1953, 212653, 1294067 },
                    lossless = true,
                    preserve = true,
                },
                {
                    spellID = 153640,
                    seconds = 2.0,
                    triggerSpells = { 1953, 212653, 1294067 },
                    lossless = true,
                    preserve = true,
                },
            },
            -- Current Midnight S2 SimC and guide priorities do not contain
            -- Arcane Explosion in either Spellslinger or Sunfury. JustAC's
            -- bundled MAGE_1 SimC queue omits it as well, so a transient
            -- Assisted Combat recommendation must not enter either automatic
            -- Bridge output. Manual casting remains untouched.
            rotationEffectiveExclusions = {
                1449, -- Arcane Explosion
            },
            -- The guide recommends clipping ordinary Missiles but completing
            -- Overpowered Missiles. WoW event/aura ordering has not been
            -- verified in live telemetry, so use the loss-minimizing fallback:
            -- protect every 12.1 Missiles channel rather than guess wrong.
            clipChannels = {},
            protectedChannels = {
                5143, -- Arcane Missiles
            },
        },
    },
})
