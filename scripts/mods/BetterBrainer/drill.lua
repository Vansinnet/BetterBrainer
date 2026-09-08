local Settings = require("scripts/settings/minigame/minigame_settings")
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
    local game, stage, observed, cursor_x, cursor_y, target_x, target_y, target_index
    local pending_since, settled_at, move_t, move_x, move_y
    local recovery_requested = false
    local move_release, sent_frame
    local pulse = {}
    local ready_at, submitted_until = 0, 0
    local cache_game, cache_stage, cache_index, cache_target
    local openings = setmetatable({}, { __mode = "k" })

    local function opening(mg)
        local receipt = openings[mg]
        if not receipt then
            receipt = {}
            openings[mg] = receipt
        end
        return receipt
    end

    local function fresh(mg)
        local receipt = openings[mg]
        return mg._is_server == true or receipt and receipt.started and receipt.stage and receipt.cursor and receipt.search
    end

    local function target(mg)
        local s = mg:current_stage()
        local index = s and mg:correct_targets()[s]
        local targets = s and mg:targets()[s]
        local position = index and targets and targets[index]
        if cache_game ~= mg or cache_stage ~= s or cache_index ~= index or cache_target ~= position then
            cache_game, cache_stage, cache_index, cache_target = mg, s, index, position
        end
        return s, cache_index, cache_target
    end

    function module.reset(reason)
        if reason ~= "identity" then
            if reason == "session_end" or reason == "session_changed" or reason == "ownership_changed" or reason == "inactive" then
                if game then openings[game] = nil end
            else
                table.clear(openings)
            end
        end
        game, stage, observed, cursor_x, cursor_y, target_x, target_y, target_index = nil, nil, nil, nil, nil, nil, nil, nil
        pending_since, settled_at, move_t, move_x, move_y = nil, nil, nil, nil, nil
        recovery_requested = false
        ready_at, submitted_until = 0, 0
        move_release, sent_frame = true, nil
        table.clear(pulse)
        cache_game, cache_stage, cache_index, cache_target = nil, nil, nil, nil
    end

    function module.observe(mg, t)
        t = t or ctx.time()
        if not t or not mg or mg ~= ctx.active_minigame or not mg.correct_targets
            or not ctx.settings.enable_drill_auto or mg:is_completed() then
            if game then module.reset("inactive") end
            return
        end
        if game ~= mg then
            module.reset("identity")
            game, ready_at = mg, t + ctx.pacing("drill_solve_speed") * 0.35
        end
        if observed == t then return end
        observed = t
        local s, index, position = target(mg)
        if stage ~= s then
            if stage then ready_at = t + ctx.pacing("drill_solve_speed") * 1.50 end
            stage, settled_at, submitted_until = s, nil, 0
            cursor_x, cursor_y = nil, nil
        end
        target_x, target_y, target_index = nil, nil, nil
        if not fresh(mg) or module.cancel_requested() or mg:state() ~= Settings.game_states.gameplay then
            settled_at = nil
            return
        end
        local cursor = mg:cursor_position()
        if not cursor or not position then return end
        target_x, target_y, target_index = position.x, position.y, index
        local selected = mg:selected_index()
        local synced = selected == index and math.abs(cursor.x - target_x) <= 1 / 128
            and math.abs(cursor.y - target_y) <= 1 / 128
        if pending_since then
            if synced or cursor_x ~= cursor.x or cursor_y ~= cursor.y then
                pending_since = nil
                if synced then ready_at = math.max(ready_at, t + ctx.pacing("drill_solve_speed") * 1.50) end
            end
        end
        cursor_x, cursor_y = cursor.x, cursor.y
        if synced and not pending_since and mg:is_searching() and mg:search_percentage(t) >= 1 and mg:is_on_target() then
            settled_at = settled_at or t
        else
            settled_at = nil
        end
    end

    function module.input(action, original, t, source)
        if source ~= "input_service" then return original end
        t = t or ctx.time()
        if not t or not game or game ~= ctx.active_minigame or not ctx.settings.enable_drill_auto
            or game:is_completed() or game:state() ~= Settings.game_states.gameplay then return original end
        if PRIMARY[action] then
            local held = ctx.pulse(pulse, fresh(game) and not module.cancel_requested() and not pending_since
                and settled_at ~= nil and t >= ready_at and t >= submitted_until
                and t - settled_at >= ctx.pacing("drill_solve_speed") * 1.65)
            if held and sent_frame ~= ctx.input_frame then
                sent_frame, submitted_until = ctx.input_frame, t + 1.2
            end
            return held
        elseif MOVE[action] then
            local sample = ctx.input_frame or t
            if move_t ~= sample then
                move_t, move_x, move_y = sample, 0, 0
                if move_release then
                    move_release = false
                elseif fresh(game) and not module.cancel_requested() and target_x and cursor_x
                    and t > ready_at and t >= submitted_until and not pending_since
                    and game:selected_index() ~= target_index then
                    local dx, dy = target_x - cursor_x, cursor_y - target_y
                    local length = math.sqrt(dx * dx + dy * dy)
                    if length > 0.01 then
                        move_x, move_y = dx / length, dy / length
                        pending_since, move_release, settled_at = t, true, nil
                        -- Drill does not reset its repeat timer on neutral input.
                        ready_at = math.max(ready_at, t + Settings.drill_move_delay)
                    end
                end
            end
            if move_x then return movement(action, move_x, move_y) end
        end
        return original
    end

    function module.settings_changed(id)
        if id == "enable_drill_auto" or id == "drill_solve_speed" then module.reset("settings") end
    end

    function module.cancel_requested()
        if not game or not ctx.settings.enable_drill_auto or not ctx.session_valid(game)
            or game:is_completed() then return false end
        local t = ctx.time()
        if pending_since and t and t - pending_since >= 2.5 then
            -- Direction is not idempotent; elapsed time cannot acknowledge a move.
            recovery_requested = true
        end
        return recovery_requested
    end

    ctx.mod:hook_safe("MinigameDrill", "start", function(self, player)
        if ctx.is_local_player(player) then
            if openings[self] and openings[self].foreign then openings[self] = nil end
            opening(self).started = true
        elseif player or not ctx.session_valid(self) then
            openings[self] = { foreign = true }
        end
    end)
    ctx.mod:hook_safe("MinigameDrill", "stop", function(self, is_automatic)
        if is_automatic ~= nil or not ctx.session_valid(self) then
            openings[self] = nil
            if self == game then module.reset("session_end") end
        end
    end)
    ctx.mod:hook_safe("MinigameDrill", "set_current_stage", function(self, next_stage)
        if self._is_server == false then opening(self).stage = true end
    end)
    ctx.mod:hook_safe("MinigameDrill", "set_cursor_position", function(self, x, y, selected_target)
        if self._is_server == false then opening(self).cursor = true end
    end)
    ctx.mod:hook_safe("MinigameDrill", "set_searching", function(self, t)
        if self._is_server == false then opening(self).search = true end
    end)

    ctx.mod:hook_require("scripts/ui/views/scanner_display_view/minigame_drill_view", function(View)
        ctx.mod:hook_safe(View, "draw_widgets", function(self, dt, t, input_service, ui_renderer)
            if not ctx.settings.enable_drill or not ui_renderer then return end
            local ext = self._minigame_extension
            local mg = ext and ext:minigame(Settings.types.drill)
            if not mg or mg ~= ctx.active_minigame or mg:is_completed() or mg:state() ~= Settings.game_states.gameplay then return end
            local s, index = target(mg)
            local row = s and self._target_widgets[s]
            local widget = index and row and row[index]
            if not widget then return end
            -- Reuse the engine widget without retaining a highlight in its mutable style.
            local color = widget.style.highlight.color
            local a, r, g, b = color[1], color[2], color[3], color[4]
            color[1], color[2], color[3], color[4] = 255, 255, 255, 255
            UIWidget.draw(widget, ui_renderer)
            color[1], color[2], color[3], color[4] = a, r, g, b
        end)
    end)

    return module
end
