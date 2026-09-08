local mod = get_mod("BetterBrainer")

local function checkbox(id, default)
    return {
        setting_id = id,
        type = "checkbox",
        default_value = default,
        tooltip = id .. "_tooltip",
    }
end

local function numeric(id, default, minimum, maximum)
    return {
        setting_id = id,
        type = "numeric",
        default_value = default,
        range = { minimum, maximum },
        decimals_number = 0,
        tooltip = id .. "_tooltip",
    }
end

local function group(id, widgets)
    return {
        setting_id = id,
        type = "group",
        title = id,
        sub_widgets = widgets,
    }
end

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "language",
                type = "dropdown",
                default_value = "auto",
                require_restart = true,
                tooltip = "language_tooltip",
                options = {
                    { text = "language_auto", value = "auto" },
                    { text = "language_en", value = "en" },
                    { text = "language_zh_cn", value = "zh-cn" },
                    { text = "language_zh_tw", value = "zh-tw" },
                    { text = "language_ru", value = "ru" },
                },
            },
            group("decode_symbols_group", {
                checkbox("enable_decode_highlight", true),
                checkbox("enable_decode_auto", true),
            }),
            group("matching_group", {
                checkbox("enable_matching", true),
                checkbox("enable_expedition_auto_solve", true),
                numeric("expedition_solve_speed", 1, 1, 5),
            }),
            group("scan_group", {
                checkbox("enable_scan", true),
                checkbox("enable_auto_scan", true),
            }),
            group("balance_group", {
                checkbox("enable_balance", true),
            }),
            group("drill_group", {
                checkbox("enable_drill", true),
                checkbox("enable_drill_auto", true),
                numeric("drill_solve_speed", 1, 1, 5),
            }),
            group("frequency_group", {
                checkbox("enable_frequency_highlight", true),
                checkbox("enable_frequency_auto", true),
                numeric("frequency_solve_speed", 1, 1, 5),
            }),
        },
    },
}
