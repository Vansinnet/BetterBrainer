return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`BetterBrainer` failed loading DMF.")
        new_mod("BetterBrainer", {
            mod_script = "BetterBrainer/scripts/mods/BetterBrainer/BetterBrainer",
            mod_data = "BetterBrainer/scripts/mods/BetterBrainer/BetterBrainer_data",
            mod_localization = "BetterBrainer/scripts/mods/BetterBrainer/BetterBrainer_localization",
        })
    end,
    packages = {},
}
