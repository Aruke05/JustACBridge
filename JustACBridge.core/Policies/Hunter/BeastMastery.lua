local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("HUNTER", 1, {
    id = "beast_mastery",
    name = "野兽控制",
    revision = 1,

    -- M4 remains the real JustAC queue with safety deletions only.  Bestial
    -- Wrath is BM's sole ordinary major cooldown in the current 12.1 guide;
    -- Black Arrow, Wild Thrash, Barbed Shot and Kill Command remain normal
    -- rotational actions rather than an invented preserve list.
    useDetectedBurstTriggers = false,
    preserveSourceQueueOnly = true,
    fallbackActions = {},
    reserve = {
        19574, -- Bestial Wrath
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
            revision = 1,
        },
    },
})
