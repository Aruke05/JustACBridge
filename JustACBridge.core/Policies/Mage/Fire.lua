local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 2, {
    id = "fire",
    name = "火焰",
    revision = 4,
    fallbackActions = {
        { spellID = 2948, label = "灼烧" },
    },
    reserve = {
        190319, -- Combustion
        153561, -- Meteor
    },
    -- Flamestrike needs a ground cursor/macro. M4 is continuously held during
    -- movement and must never guess a cursor position; M5 remains available.
    reserveExclusions = {
        2120, -- Flamestrike
    },
    moveCastAlways = {
        2948, -- Scorch
    },
    -- Pyroclasm lights the same buttons but remains a hardcast. Require the
    -- live spell form itself to report zero cast time; generic proc glow alone
    -- must never release Pyroblast/Flamestrike while moving.
    moveCastInstantOnly = {
        11366, -- Pyroblast
        2120,  -- Flamestrike
    },
})
