local Registry = _G.JustACBridgePolicyRegistry
if not Registry then
    return
end

-- Hunter utility is player-owned rather than part of a damage APL.  These
-- actions can move the player, move/control enemies, interrupt, or require a
-- ground reticle.  A recommendation source must never turn them into a blind
-- held-key cast simply because the button happens to be usable.
Registry.RegisterClass("HUNTER", {
    revision = 1,
    rotationExclusions = {
        781,    -- Disengage
        109248, -- Binding Shot
        147362, -- Counter Shot
        187650, -- Freezing Trap
        187698, -- Tar Trap
        187707, -- Muzzle
        190925, -- Harpoon
    },
    specs = {},
})
