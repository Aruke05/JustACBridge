local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("DEATHKNIGHT", 1, {
    id = "blood",
    name = "鲜血",
    revision = 2,
    fallbackActions = {
        { spellID = 50842, label = "血液沸腾" },
        { spellID = 195292, label = "死神的抚摸" },
    },
    reserve = {
        49028,  -- Dancing Rune Weapon
        194844, -- Bonestorm
    },
})
