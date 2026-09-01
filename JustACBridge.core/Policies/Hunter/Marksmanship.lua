local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("HUNTER", 2, {
    id = "marksmanship",
    name = "射击",
    revision = 1,

    useDetectedBurstTriggers = false,
    preserveSourceQueueOnly = true,
    fallbackActions = {},
    reserve = {
        288613, -- Trueshot
    },

    -- Volley needs a ground placement.  M5 may still use the player's normal
    -- placement workflow, but the long-held movement/mechanics M4 key must not
    -- start a cursor-targeted action.
    reserveExclusions = {
        260243, -- Volley
    },

    -- Rapid Fire is explicitly usable while moving.  Current high-end APLs
    -- may clip only the final ticks under Unload, but the bridge cannot observe
    -- ticks_remain reliably, so every started channel is protected to its real
    -- stop/interruption event instead of approximating the clip window.
    moveCastAlways = {
        257044, -- Rapid Fire
    },
    protectedChannels = {
        257044, -- Rapid Fire
    },
    moveCastNever = {
        392060, -- Wailing Arrow (current action)
        355589, -- Wailing Arrow compatibility form
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
