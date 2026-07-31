local Registry = _G.JustACBridgePolicyRegistry
if not Registry then return end

Registry.RegisterSpec("MAGE", 1, {
    id = "arcane",
    name = "奥术",
    revision = 3,
    fallbackActions = {
        { spellID = 44425, label = "奥术弹幕" },
    },
    reserve = {
        365350, -- Arcane Surge
        12051,  -- Evocation
        321507, -- Touch of the Magi
    },
    -- S3 奥法循环会在一个 GCD 后主动截断奥术飞弹。
    clipChannels = {
        5143, -- Arcane Missiles / Aether Attunement override
    },
})
