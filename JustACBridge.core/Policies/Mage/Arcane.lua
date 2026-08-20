local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 1, {
    id = "arcane",
    name = "奥术",
    revision = 17,

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
            clipChannels = {
                5143, -- Arcane Missiles (including its S3 override form)
            },
        },
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 17,
            -- These are exact, live-observable movement exceptions rather
            -- than an invented fallback. Slipstream makes a Clearcasting
            -- Missiles channel movable; Presence of Mind makes Arcane Blast
            -- instant. If the talent/aura cannot be proven, both fail closed.
            moveCastConditions = {
                {
                    spellID = 5143,          -- Arcane Missiles
                    requiresSpell = 236457,  -- Slipstream
                    auraID = 263725,         -- Clearcasting
                    label = "Slipstream + Clearcasting",
                },
                {
                    spellID = 30451,  -- Arcane Blast
                    auraID = 205025,  -- Presence of Mind
                    label = "Presence of Mind",
                },
            },
            -- Orb is instant but travels along the player's facing. While the
            -- player is moving neither held key may guess that direction. M5
            -- regains Orb immediately after movement stops; M4 already excludes
            -- it at all times through reserveExclusions above.
            moveCastNever = {
                153626, -- Arcane Orb
                153640, -- Arcane Orb override/compatibility form
            },
            moveCastResumeDelays = {
                { spellID = 153626, seconds = 2.0 },
                { spellID = 153640, seconds = 2.0 },
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
