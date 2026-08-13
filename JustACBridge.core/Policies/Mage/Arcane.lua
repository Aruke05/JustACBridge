local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 1, {
    id = "arcane",
    name = "奥术",
    revision = 6,
    fallbackActions = {
        { spellID = 44425, label = "奥术弹幕" },
    },

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
            revision = 6,
            -- 12.1 once again clips ordinary Missiles as soon as the next GCD
            -- can be queued.  The Overpowered proc doubles their damage and
            -- grants maximum Salvo, so that specific channel must finish.
            clipChannels = {
                5143, -- Arcane Missiles
            },
            conditionalProtectedChannels = {
                {
                    spellID = 5143,
                    buffs = {
                        1277009, -- Overpowered Missiles
                    },
                    label = "Overpowered Missiles",
                },
            },
        },
    },
})
