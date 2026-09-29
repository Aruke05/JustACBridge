local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("HUNTER", 1, {
    id = "beast_mastery",
    name = "野兽控制",
    revision = 2,

    -- M4 keeps the real JustAC queue, with the user's explicit reservation of
    -- Bestial Wrath and both Wild Thrash forms. Black Arrow, Barbed Shot and
    -- Kill Command remain ordinary rotational actions.
    useDetectedBurstTriggers = false,
    preserveSourceQueueOnly = true,
    fallbackActions = {},
    reserve = {
        19574,   -- Bestial Wrath
        1264355, -- Wild Thrash
        1264359, -- Wild Thrash assisted/compatibility form
    },
    -- Saved "reserve remove" overrides must not reintroduce these skills.
    reserveExclusions = {
        19574,
        1264355,
        1264359,
    },

    -- Wailing Arrow retains a real cast even when the action button glows.
    -- Do not let the generic proc fallback misclassify it as movement-safe.
    moveCastNever = {
        392060, -- Wailing Arrow (current action)
        355589, -- Wailing Arrow compatibility form
    },

    versions = {
        {
            id = "midnight-12.1",
            minInterface = 120100,
            maxInterface = 120199,
            revision = 2,
        },
    },
})
