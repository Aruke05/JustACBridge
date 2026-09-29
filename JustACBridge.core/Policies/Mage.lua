local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Mage class-wide rules only.  Every specialization is registered from its
-- own file under Policies/Mage/ so a patch can replace one spec atomically.
Registry.RegisterClass("MAGE", {
    revision = 12,
    moveCastAlways = {
        2948, -- Scorch: has a cast bar but is natively castable while moving
    },
    moveCastBuffs = {
        108839, -- Ice Floes: permits Mage spells to be cast while moving
    },
    specs = {},
})
