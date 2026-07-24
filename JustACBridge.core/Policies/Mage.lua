local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Mage policy is intentionally maintained independently from other classes.
-- Frozen Orb and Meteor are not reserved: the referenced TWW S3 rotations use
-- them rotationally rather than holding them for Icy Veins/Combustion.
Registry.RegisterClass("MAGE", {
    revision = 1,
    specs = {
        [1] = {
            id = "arcane",
            name = "奥术",
            revision = 1,
            reserve = {
                365350, -- Arcane Surge
                12051,  -- Evocation
                321507, -- Touch of the Magi
            },
        },
        [2] = {
            id = "fire",
            name = "火焰",
            revision = 1,
            reserve = {
                190319, -- Combustion
            },
        },
        [3] = {
            id = "frost",
            name = "冰霜",
            revision = 1,
            reserve = {
                12472, -- Icy Veins
            },
        },
    },
})
