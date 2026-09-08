local mod = get_mod("BetterBrainer")
local path = "BetterBrainer/scripts/mods/BetterBrainer/"
local settings, definitions, pacing = {}, {}, {}
local ctx = { mod = mod, settings = settings }
local local_state, active, observed_at
local sampling_service, sampling_time, sampling_ephemeral
local fast_exit_sent

function ctx.time()
    local time = Managers.time
    return time and time:has_timer("gameplay") and time:time("gameplay") or nil
end

function ctx.is_local_player(player)
    local players = Managers.player
    return player ~= nil and players ~= nil and player == players:local_player_safe(1)
end

function ctx.pacing(id)
    return pacing[id]
end

function ctx.pulse(state, ready)
    local frame = ctx.input_frame
    if not frame then return false end
    if state.frame ~= frame then
        -- Every primary alias shares one edge; the next sampled frame must release.
        local first = state.frame == nil or frame < state.frame
        state.frame, state.held = frame, not first and not state.held and ready or false
    end
    return state.held
end

local function read_setting(id, definition)
    local value = mod:get(id)
    local default = definition.default_value
    if type(value) ~= type(default) then value = default end
    if definition.range then
        if value ~= value or value == math.huge or value == -math.huge then value = default end
        value = math.max(definition.range[1], math.min(definition.range[2], math.floor(value + 0.5)))
    end
    settings[id] = value
    if id == "expedition_solve_speed" or id == "drill_solve_speed" or id == "frequency_solve_speed" then
        pacing[id] = (5 - value) / 4
    end
end

local function read_definitions(widgets)
    for i = 1, #widgets do
        local widget = widgets[i]
        if widget.sub_widgets then
            read_definitions(widget.sub_widgets)
        elseif widget.default_value ~= nil then
            definitions[widget.setting_id] = widget
            read_setting(widget.setting_id, widget)
        end
    end
end

read_definitions(mod:io_dofile(path .. "BetterBrainer_data").options.widgets)

local symbols = mod:io_dofile(path .. "symbols")(ctx)
local search = mod:io_dofile(path .. "search")(ctx)
local drill = mod:io_dofile(path .. "drill")(ctx)
local frequency = mod:io_dofile(path .. "frequency")(ctx)
local balance = mod:io_dofile(path .. "balance")(ctx)
local scan = mod:io_dofile(path .. "scan")(ctx)
local modules = { symbols, search, drill, frequency, balance, scan }
local solvers = {
    decode_symbols = symbols,
    decode_search = search,
    drill = drill,
    frequency = frequency,
    balance = balance,
}

local function end_session(reason)
    ctx.active_minigame = nil
    fast_exit_sent = nil
    local_state, observed_at = nil, nil
    if active then active.reset(reason) end
    active = nil
end

local function reset(reason)
    ctx.active_minigame = nil
    fast_exit_sent = nil
    ctx.input_frame = nil
    sampling_service, sampling_time, sampling_ephemeral = nil, nil, nil
    local_state, active, observed_at = nil, nil, nil
    for i = 1, #modules do modules[i].reset(reason) end
end

local function select_session(state)
    local mg = state._minigame
    local extension = mg and mg._minigame_extension
    local solver = extension and solvers[extension:minigame_type()]
    if not solver then
        if active then end_session("session_end") end
        return
    end
    if ctx.active_minigame ~= mg then
        if active then end_session("session_changed") end
        ctx.active_minigame, active, observed_at = mg, solver, nil
        fast_exit_sent = nil
    end
    local_state = state
end

-- Passing a minigame also requires current CSM identity on the normal explicit-owner path.
function ctx.session_valid(minigame)
    if not local_state then return false end
    local player = local_state._player
    local mg = ctx.active_minigame
    if not (ctx.is_local_player(player) and player.player_unit ~= nil and Unit.alive(player.player_unit)
        and local_state._minigame == mg and mg ~= nil
        and (minigame == nil or minigame == mg)) then return false end
    local owner = mg:player_session_id()
    if owner ~= nil then
        if owner ~= player:session_id() then return false end
        if minigame == nil then return true end
    elseif mg._is_server ~= false then
        return false
    end
    if local_state._unit ~= player.player_unit then return false end
    -- Nil-owner receipts and direct submissions require the actual current state, not retained prediction.
    local csm = ScriptUnit.has_extension(player.player_unit, "character_state_machine_system")
    return csm ~= nil and csm:current_state() == local_state
end

local function observe(t)
    if active and observed_at ~= t then
        observed_at = t
        active.observe(ctx.active_minigame, t)
    end
end

mod:hook_require("scripts/extension_systems/character_state_machine/character_states/player_character_state_minigame", function(State)
    mod:hook(State, "_update_input", function(func, self, t, fixed_frame, input_extension)
        if ctx.is_local_player(self._player) then
            select_session(self)
            if ctx.session_valid() then observe(t) end
        end
        -- Keep native input edges, dodging, animation, and weapon action ordering.
        return func(self, t, fixed_frame, input_extension)
    end)
    mod:hook_safe(State, "on_exit", function(self, unit, t, next_state)
        if self == local_state then end_session("session_end") end
    end)
end)

local function finish_sample(...)
    sampling_service, sampling_time, sampling_ephemeral = nil, nil, nil
    return ...
end

mod:hook_require("scripts/managers/player/player_game_states/human_input_handler", function(Handler)
    mod:hook(Handler, "pre_update", function(func, self, dt, t, input_service, ui_interaction_action)
        if not ctx.is_local_player(self._player) then
            return func(self, dt, t, input_service, ui_interaction_action)
        end
        -- Ephemeral buttons are collected in main time; solver clocks use gameplay time.
        sampling_service, sampling_time, sampling_ephemeral = input_service, ctx.time(), true
        return finish_sample(func(self, dt, t, input_service, ui_interaction_action))
    end)
    mod:hook(Handler, "fixed_update", function(func, self, dt, t, frame, input_service, yaw, pitch, roll)
        if not ctx.is_local_player(self._player) then
            return func(self, dt, t, frame, input_service, yaw, pitch, roll)
        end
        ctx.input_frame = frame
        sampling_service, sampling_time, sampling_ephemeral = input_service, t, false
        return finish_sample(func(self, dt, t, frame, input_service, yaw, pitch, roll))
    end)
end)

local relevant = {
    action_one_hold = true, interact_hold = true, jump_held = true,
    action_one_pressed = true, action_one_released = true,
    action_two_pressed = true,
    move = true, move_left = true, move_right = true, move_forward = true, move_backward = true,
}
local scan_actions = { action_one_pressed = true, action_one_hold = true, action_one_released = true }

mod:hook(CLASS.InputService, "_get", function(func, self, action)
    local original = func(self, action)
    if self ~= sampling_service or self.type ~= "Ingame" or not relevant[action] then return original end
    local scanning = settings.enable_auto_scan and scan_actions[action]
    if not active and not scanning then return original end
    local t = sampling_time
    if not t then return original end
    if active then
        if not ctx.session_valid() then
            end_session("ownership_changed")
        else
            local ui = Managers.ui
            if ui and ui:view_active("scanner_display_view") then
                if sampling_ephemeral then
                    if action == "action_two_pressed" and not fast_exit_sent
                        and (((active == search and settings.enable_expedition_auto_solve
                            or active == drill and settings.enable_drill_auto)
                            and ctx.active_minigame:is_completed())
                            or active.cancel_requested and active.cancel_requested()) then
                        -- Skip a confirmed outro, or leave an uncertain response without retrying it.
                        fast_exit_sent = true
                        return true
                    end
                    return original
                end
                observe(t)
                return active.input(action, original, t, "input_service")
            end
            return original
        end
    end
    if scanning then return scan.input(action, original, t, "input_service") end
    return original
end)

mod.update = function(dt)
    if not mod:is_enabled() then return end
    if local_state and not ctx.session_valid() then end_session("ownership_changed") end
    local scan_enabled = settings.enable_scan or settings.enable_auto_scan
    if not scan_enabled then return end
    local t = ctx.time()
    if not t then return end
    scan.update(dt, t)
end

mod.on_setting_changed = function(id)
    local definition = definitions[id]
    if not definition then return end
    read_setting(id, definition)
    observed_at = nil
    for i = 1, #modules do
        local callback = modules[i].settings_changed
        if callback then callback(id) end
    end
end

mod.on_enabled = function()
    for id, definition in pairs(definitions) do read_setting(id, definition) end
    reset("enabled")
end

mod.on_disabled = function()
    reset("disabled")
end

mod.on_game_state_changed = function(status, name)
    if status == "exit" and name == "StateGameplay" then reset("gameplay_exit") end
end

mod.on_unload = function(exit_game)
    reset("unload")
end
