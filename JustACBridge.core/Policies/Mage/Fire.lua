local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 2, {
    id = "fire",
    name = "火焰",
    revision = 2,
    fallbackActions = {
        { spellID = 2948, label = "灼烧" },
    },
    reserve = {
        190319, -- Combustion
    },
})
