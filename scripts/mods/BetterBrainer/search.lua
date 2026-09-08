local Settings = require("scripts/settings/minigame/minigame_settings")
local ViewSettings = require("scripts/ui/views/scanner_display_view/scanner_display_view_decode_search_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local MOVE = { move = true, move_left = true, move_right = true, move_forward = true, move_backward = true }
local PRIMARY = { action_one_hold = true, interact_hold = true, jump_held = true }

local function movement(action, x, y)
    if action == "move_left" then return math.max(-x, 0) end
    if action == "move_right" then return math.max(x, 0) end
    if action == "move_forward" then return math.max(y, 0) end
    if action == "move_backward" then return math.max(-y, 0) end
    return Vector3(x, y, 0)
end

return function(ctx)
    local module = {}
    local game, stage, observed, target_x, target_y
    local cursor_x, cursor_y
    local pending = {}
    local pulse = {}
    local resync_until, cautious, ack_timeout = nil, false, 0.8
    local base_timeout, backoff, next_ping = 0.8, 1, 0
    local move_limit = 2
    local ready_at, settled_at, submitted_until = 0, nil, 0
    local move_frame, move_x, move_y, move_release, last_move_frame, sent_frame, press_ready
    local cache_game, cache_stage, cache_symbols, cache_target, cache_x, cache_y
    local widgets
    local width, height = Settings.decode_search_board_width, Settings.decode_search_board_height
    local cw, ch = Settings.decode_search_cursor_width, Settings.decode_search_cursor_height

    local function target(mg)
        local s, symbols, wanted = mg:current_stage(), mg:symbols(), mg:current_decode_target()
        if not s or not wanted or #wanted ~= cw * ch or #symbols ~= width * height then
            return nil
        end
        if cache_game == mg and cache_stage == s and cache_symbols == symbols and cache_target == wanted then
            return cache_x, cache_y
        end
        local cursor = mg:cursor_position()
        local best_steps, best_distance = math.huge, math.huge
        cache_x, cache_y = nil, nil
        for y = 1, height - ch + 1 do
            for x = 1, width - cw + 1 do
                -- The engine returns a shared temporary array; compare it immediately.
                local found = mg:get_symbols_for_target(x, y)
                local matches = true
                for i = 1, cw * ch do
                    if found[i] ~= wanted[i] then
                        matches = false
                        break
                    end
                end
                if matches then
                    local dx, dy = cursor and math.abs(x - cursor.x) or 0, cursor and math.abs(y - cursor.y) or 0
                    local steps, distance = math.max(dx, dy), dx + dy
                    if steps < best_steps or steps == best_steps and distance < best_distance then
                        cache_x, cache_y, best_steps, best_distance = x, y, steps, distance
                    end
                end
            end
        end
        cache_game, cache_stage, cache_symbols, cache_target = mg, s, symbols, wanted
        return cache_x, cache_y
    end

    function module.reset(reason)
        game, stage, observed, target_x, target_y = nil, nil, nil, nil, nil
        cursor_x, cursor_y = nil, nil
        table.clear(pending)
        table.clear(pulse)
        resync_until, cautious, ack_timeout = nil, false, 0.8
        base_timeout, backoff, next_ping = 0.8, 1, 0
        move_limit = 2
        ready_at, settled_at, submitted_until = 0, nil, 0
        move_frame, move_x, move_y, last_move_frame, sent_frame, press_ready = nil, 0, 0, nil, nil, false
        move_release = true
        cache_game, cache_stage, cache_symbols, cache_target, cache_x, cache_y = nil, nil, nil, nil, nil, nil
        widgets = nil
    end

    function module.observe(mg, t)
        t = t or ctx.time()
        if not t or not mg or mg ~= ctx.active_minigame or not mg.current_decode_target
            or not ctx.settings.enable_expedition_auto_solve or mg:is_completed() then
            if game then module.reset("inactive") end
            return
        end
        if game ~= mg then
            module.reset("identity")
            game, ready_at = mg, t + (ctx.pacing("expedition_solve_speed") == 0 and 0 or 0.20)
        end
        if observed == t then return end
        observed = t
        if not mg._is_server and t >= next_ping then
            local connection = Managers.connection
            local host = connection and connection:host()
            local rtt = host and Network.ping(host)
            if type(rtt) ~= "number" or rtt ~= rtt or rtt < 0 or rtt == math.huge then rtt = 0 end
            -- Reduce prediction immediately; expand only after outstanding moves drain.
            if rtt >= 0.25 then move_limit = 1
            elseif #pending == 0 then move_limit = 2 end
            base_timeout = math.min(3.2, math.max(0.8, rtt * 2 + 0.2))
            ack_timeout, next_ping = math.min(3.2, base_timeout * backoff), t + 1
        end
        local s = mg:current_stage()
        if stage ~= s then
            if stage then ready_at = t + ctx.pacing("expedition_solve_speed") * 1.632 end
            stage, settled_at, submitted_until = s, nil, 0
        end
        target_x, target_y = nil, nil
        if mg:state() ~= Settings.game_states.gameplay then
            settled_at = nil
            return
        end
        local cursor = mg:cursor_position()
        if not cursor then return end
        target_x, target_y = target(mg)
        local changed = cursor_x ~= cursor.x or cursor_y ~= cursor.y
        local mismatch = false
        if resync_until then
            if changed then resync_until = t + ack_timeout end
            if t >= resync_until then resync_until = nil end
        elseif changed and cursor_x then
            local matched = false
            for i = #pending, 1, -1 do
                local command = pending[i]
                local complete = cursor.x == command.x and cursor.y == command.y
                -- A diagonal emits X first. Retire predecessors, not this partial move.
                local partial = command.diagonal and cursor.x == command.x and cursor.y == command.start_y
                if complete or partial then
                    for _ = 1, complete and i or i - 1 do table.remove(pending, 1) end
                    if complete then
                        cautious, backoff, ack_timeout = false, 1, base_timeout
                        ready_at = math.max(ready_at, t + ctx.pacing("expedition_solve_speed") * 1.054)
                    end
                    matched = true
                    break
                end
            end
            mismatch = not matched
        end
        if not resync_until and (mismatch or pending[1] and t >= pending[1].until_t) then
            -- A timeout is not an ACK. Drain late traffic before trusting a new baseline,
            -- and use one command until a full confirmation restores the RTT-limited window.
            table.clear(pending)
            cautious, backoff = true, math.min(4, backoff * 2)
            ack_timeout = math.min(3.2, base_timeout * backoff)
            resync_until, settled_at, move_release = t + ack_timeout, nil, true
        end
        if changed then settled_at = nil end
        cursor_x, cursor_y = cursor.x, cursor.y
        if not resync_until and #pending == 0 and cursor_x == target_x and cursor_y == target_y then
            settled_at = settled_at or t
        else
            settled_at = nil
        end
    end

    function module.input(action, original, t, source)
        -- The extension reads the serialized sample; never replace it with a newer decision.
        if source ~= "input_service" then return original end
        t = t or ctx.time()
        if not t or not game or game ~= ctx.active_minigame or not ctx.settings.enable_expedition_auto_solve
            or game:is_completed() or game:state() ~= Settings.game_states.gameplay then return original end
        if not PRIMARY[action] and not MOVE[action] then return original end
        local sample = ctx.input_frame
        if not sample then return original end
        if move_frame ~= sample then
            move_frame, move_x, move_y = sample, 0, 0
            if move_release then
                -- Always serialize neutral, never the user's movement, between commands.
                move_release = false
            elseif target_x and cursor_x and not resync_until and t >= ready_at and t >= submitted_until
                and #pending < (cautious and 1 or move_limit) then
                local tail = pending[#pending]
                local x, y = tail and tail.x or cursor_x, tail and tail.y or cursor_y
                local dx, dy = target_x - x, target_y - y
                if dx ~= 0 or dy ~= 0 then
                    move_x = dx == 0 and 0 or dx > 0 and 1 or -1
                    move_y = dy == 0 and 0 or dy > 0 and -1 or 1
                    pending[#pending + 1] = {
                        x = x + move_x, y = y - move_y, start_y = y,
                        diagonal = move_x ~= 0 and move_y ~= 0, until_t = t + ack_timeout,
                    }
                    ready_at = math.max(ready_at, t + ctx.pacing("expedition_solve_speed") * 1.054)
                    settled_at, move_release, last_move_frame = nil, true, sample
                end
            end
            press_ready = not resync_until and #pending == 0 and settled_at ~= nil and t > settled_at
                and last_move_frame ~= sample and t >= ready_at and t >= submitted_until
                and t - settled_at >= ctx.pacing("expedition_solve_speed") * 0.646
        end
        if PRIMARY[action] then
            local held = ctx.pulse(pulse, press_ready)
            if held and sent_frame ~= sample then
                sent_frame, submitted_until = sample, t + 1.2
            end
            return held
        end
        return movement(action, move_x, move_y)
    end

    function module.settings_changed(id)
        if id == "enable_expedition_auto_solve" or id == "expedition_solve_speed" then module.reset("settings") end
    end

    ctx.mod:hook_require("scripts/ui/views/scanner_display_view/minigame_decode_search_view", function(View)
        ctx.mod:hook_safe(View, "draw_widgets", function(self, dt, t, input_service, ui_renderer)
            if not ctx.settings.enable_matching or not ui_renderer then return end
            local ext = self._minigame_extension
            local mg = ext and ext:minigame(Settings.types.decode_search)
            if not mg or mg ~= ctx.active_minigame or mg:is_completed() or mg:state() ~= Settings.game_states.gameplay then return end
            local tx, ty = target(mg)
            if not tx then return end
            if not widgets then
                widgets = {}
                for i = 1, cw * ch do
                    widgets[i] = UIWidget.init("tnb_search_" .. i, UIWidget.create_definition({{
                        pass_type = "texture", style_id = "highlight",
                        value = "content/ui/materials/backgrounds/scanner/scanner_decode_symbol_highlight",
                        style = { hdr = true, color = { 110, 255, 165, 0 } },
                    }}, "center_pivot", nil, ViewSettings.symbol_widget_size))
                end
            end
            local size, spacing = ViewSettings.symbol_widget_size, ViewSettings.symbol_spacing
            for y = 0, ch - 1 do
                for x = 0, cw - 1 do
                    local widget = widgets[y * cw + x + 1]
                    widget.offset[1] = ViewSettings.symbol_starting_offset_x + (size[1] + spacing) * (tx + x - 1)
                    widget.offset[2] = ViewSettings.symbol_starting_offset_y + (size[2] + spacing) * (ty + y - 1)
                    widget.offset[3] = 6
                    UIWidget.draw(widget, ui_renderer)
                end
            end
        end)
    end)

    return module
end
