local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("HUNTER", 1, {
    id = "beast-mastery",
    name = "野兽控制",
    revision = 1,
    reserve = {
        19574,   -- Bestial Wrath
        1264355, -- Wild Thrash
        1264359, -- Wild Thrash assisted/compatibility form
    },
    -- Preserve mode must never spend these skills, even when the source does
    -- not detect them as burst triggers or a saved override unreserves them.
    reserveExclusions = {
        19574,
        1264355,
        1264359,
    },
})
