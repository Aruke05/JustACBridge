local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Death Knight class-wide rules only.  Spec policy lives in one file per spec.
Registry.RegisterClass("DEATHKNIGHT", {
    revision = 4,
    groundEffects = {
        {
            id = "death-and-decay",
            name = "枯萎凋零",
            spells = { 43265, 152280 }, -- Death and Decay / Defile
            duration = 10,
            suppressRepeat = true,
        },
    },
    specs = {},
})
