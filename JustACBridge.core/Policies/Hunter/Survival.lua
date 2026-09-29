local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("HUNTER", 3, {
    id = "survival",
    name = "生存",
    revision = 1,

    useDetectedBurstTriggers = false,
    preserveSourceQueueOnly = true,
    fallbackActions = {},
    reserve = {
        1250646, -- Takedown
        1261193, -- Boomstick
    },

    -- Boomstick and the live Raptor Swipe replacement are frontal cones.
    -- Instances do not expose enough trustworthy target geometry to aim them
    -- automatically.  Keep both off M4 and leave facing to M5/manual control.
    reserveExclusions = {
        1261193, -- Boomstick
        1262343, -- Raptor Swipe (live action)
    },
    reserveEffectiveExclusions = {
        1262343, -- Raptor Strike button dynamically replaced by Raptor Swipe
    },

    -- Boomstick is a three-second channel.  Once M5 starts it, neither output
    -- may truncate it merely because a later frame exposes another candidate.
    protectedChannels = {
        1261193, -- Boomstick
    },
    moveCastAlways = {
        1261193, -- Boomstick: explicitly movable while channeling
    },

    versions = {
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 1,
        },
    },
})
