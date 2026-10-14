-- Run from the workspace root with tools/luajit/luajit.exe (see README.md).
-- Reopen-based speed-ups (DESIGN.md): Search transition skip and Symbols reroll, through a model of the character
-- state machine around the real minigame state: cancel exits, a `decoding` interaction re-enters on the next frame
-- and the new state initializes the minigame before consuming that frame's input
-- (player_character_state_minigame.lua:138-148,206,270-342,376-402; decoding_interaction.lua:11-34). The server
-- runs client frame n in tick n + 3 and applies the decoder's 0.1 s gate (decoder_device_extension.lua:292-305).
assert(jit and jit.version, "LuaJIT required")
local H = dofile("mods/active/BetterBrainer/tests/fixture.lua")
local baseline = arg[1] == "--baseline"
assert(arg[1] == nil or baseline, "usage: reopen_spec.lua [--baseline]")
local fixture = H.factory()
local eq = H.eq
local passed, failed = 0, 0
local function test(name, body)
    local ok, err = xpcall(body, debug.traceback)
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function mean(list) local s = 0; for _, v in ipairs(list) do s = s + v end; return #list > 0 and s / #list or 0 end

print("BetterBrainer reopen tests | " .. jit.version .. " | source " .. (FIXTURE_SOURCE_VERSION or "darktide-source") .. " | "
    .. (baseline and "BASELINE expectations" or "CURRENT runtime"))

local GATE, LAG, STEP = 0.1, 3, 0.02

-- Wrap an opened fixture with both sides' state machines. Options: refuse (the decoder refuses every interaction),
-- look_away (the interactor never finds the terminal), local_server.
local function machine(f, options)
    options = options or {}
    local unit = f.player.player_unit
    local sides = {}
    local function side(mg, player, state, is_server)
        local s = { mg = mg, player = player, state = state, mode = "minigame", active = true, last = f.t,
            is_server = is_server }
        mg._minigame_extension.set_active = function(_, on) s.active = on end
        sides[#sides + 1] = s
        return s
    end
    local C = side(f.client or f.server, f.player, f.local_state, not f.client)
    local S = f.client and side(f.server, f.remote, f.server_state, true) or nil
    local log = { reopens = 0, entries = 0, refused = 0, requests = 0 }
    f.reopen_log = log
    -- Count the solver's own reopen requests through DMF debug lines (off by default in game).
    f.mod.debug = function(_, message, ...)
        local line = string.format(message, ...)
        if line:find("^Reopen: requested") then log.requests = log.requests + 1 end
    end
    local function allowed(s, t)
        return not options.refuse and s.mode == "walking" and not s.active and t - s.last > GATE
    end
    local function install()
        local ext = f.extensions[unit]
        ext.character_state_machine_system = {
            current_state = function() return C.mode == "minigame" and C.state or nil end,
            current_state_name = function() return C.mode == "minigame" and "minigame" or "walking" end,
        }
        ext.interactor_system = {
            is_interacting = function() return false end,
            _find_interaction_object = function()
                if options.look_away then return nil, 0, nil end
                if allowed(C, f.t) then return f.terminal, 0, nil end
                return nil, 0, f.terminal -- focus only while the minigame is active
            end,
            can_interact = function(_, target, kind) return target == f.terminal and kind == "decoding" and allowed(C, f.t) end,
        }
    end
    f.extensions[f.terminal] = { interactee_system = { interaction_type = function() return "decoding" end },
        decoder_device_system = {} }
    install()
    local function enter(s, n, t)
        local state = f:state(s.mg, s.player)
        state._minigame, state._is_server = nil, s.is_server
        state._minigame_character_state_component = {
            interface_is_level_unit = true, interface_level_unit_id = 1, interface_game_object_id = -1 }
        f.extensions[f.terminal].minigame_system = s.mg._minigame_extension
        s.state, s.mode = state, "minigame"
        if s == C then f.local_state = state; install() else f.server_state = state end
        assert(state:_check_initialize_minigame_from_unit(), "native initialization")
        if s == C then log.entries = log.entries + 1; if not s.manual then log.reopens = log.reopens + 1 end end
        s.manual = nil
    end
    local function step(s, n, t)
        if s.mode == "entering" then enter(s, n, t) end
        if s.mode == "minigame" then
            local cancel = f:consume(s.state, n, t)
            if cancel then
                s.state:on_exit(s.player.player_unit, t, "walking")
                s.mode = "walking"
            end
        elseif s.mode == "walking" then
            local sample = f.frames[n]
            if sample and sample.interact_pressed then
                if allowed(s, t) then s.last, s.mode = t, "entering"
                elseif s == C then log.refused = log.refused + 1 end
            end
        end
    end
    function f:ctick(n)
        self.t = self.t + STEP
        self.transport_t = self.t
        self:deliver()
        -- An inactive minigame extension is not updated (minigame_extension.lua:128-138).
        if (S or C).active then self.server:update(STEP, self.t) end
        self:sample(n)
        step(C, n, self.t)
        if S and n > LAG then
            local m = n - LAG
            step(S, m, self.t - LAG * STEP)
            if not self.drop_server_state then
                self.queue[#self.queue + 1] = { at = self.t + self.delay, to = "client",
                    name = "server_unit_data_state", args = H.pack(m, true) }
            end
        end
        self.mod.update(STEP)
    end
    -- The player re-enters by hand (after a refused or abandoned reopen).
    function f:manual_entry()
        for _, s in ipairs(sides) do if s.mode == "walking" then s.mode, s.last, s.manual = "entering", self.t, true end end
    end
    f.sides = { client = C, server = S }
    return f
end

local SPEED5 = { expedition_solve_speed = 5, enable_scan = false, enable_auto_scan = false }

local function open_search(seed, values, delay, options)
    local f = fixture(values or SPEED5)
    local Search = f.env.MinigameDecodeSearch
    local init = Search.init
    Search.init = function(self, unit, is_server, _, context) return init(self, unit, is_server, 1000 + seed * 7, context) end
    f:open("decode_search", not (options and options.local_server), delay or 0.05)
    Search.init = init
    f.ping = 2 * (delay or 0.05) + 0.06
    return machine(f, options)
end

local function solve(f, limit, on_frame)
    local origin = f.t
    for n = 1, limit or 3000 do
        f:ctick(n)
        if on_frame then on_frame(f, n) end
        if f.server:is_completed() and (not f.client or f.client:is_completed()) then return f.t - origin end
    end
end

-- Server record of stage-advancing presses.
local function record(f)
    local log = { presses = {} }
    local press = f.server.on_action_pressed
    f.server.on_action_pressed = function(self, t)
        local before = self._current_stage
        local result = press(self, t)
        if self._current_stage > before then log.presses[#log.presses + 1] = t end
        return result
    end
    return log
end

for _, delay in ipairs({ 0.03, 0.165 }) do
    test("Search transition skip: faster, zero mistakes, two reopens per board, receipt delay=" .. delay, function()
        local with, without, reopens = {}, {}, 0
        for seed = 1, 40 do
            local f = open_search(seed, nil, delay)
            local elapsed = solve(f)
            assert(elapsed, "seed " .. seed .. ": stalled")
            eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
            with[#with + 1], reopens = elapsed, reopens + f.reopen_log.reopens
            local g = open_search(seed, { expedition_solve_speed = 5, enable_expedition_reopen = false,
                enable_scan = false, enable_auto_scan = false }, delay)
            local plain = solve(g)
            assert(plain, "seed " .. seed .. ": stalled without reopen")
            eq(g.server._mistakes, 0)
            eq(g.reopen_log.reopens, 0, "the setting turns reopening off")
            without[#without + 1] = plain
        end
        print(string.format("  mean solve %.3fs with reopen, %.3fs without; %d reopens on 40 boards",
            mean(with), mean(without), reopens))
        if not baseline then
            eq(reopens, 80, "two transitions skipped per board")
            assert(mean(with) < mean(without) - 0.25, "reopen saves at least 0.25 s per board")
        end
    end)
end

test("Search transition skip on a local server", function()
    local with, without = {}, {}
    for seed = 1, 20 do
        local f = open_search(seed, nil, nil, { local_server = true })
        local elapsed = solve(f)
        assert(elapsed, "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0)
        with[#with + 1] = elapsed
        local g = open_search(seed, { expedition_solve_speed = 5, enable_expedition_reopen = false,
            enable_scan = false, enable_auto_scan = false }, nil, { local_server = true })
        without[#without + 1] = assert(solve(g))
    end
    print(string.format("  mean solve %.3fs with reopen, %.3fs without", mean(with), mean(without)))
    if not baseline then assert(mean(with) < mean(without) - 0.2, "faster on a local server too") end
end)

test("Search not looking at the terminal: no reopen, native transition", function()
    for seed = 1, 10 do
        local f = open_search(seed, nil, 0.05, { look_away = true })
        assert(solve(f), "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0)
        eq(f.reopen_log.reopens, 0)
    end
end)

test("Search refused re-entry: reopening switches off, the player re-enters, no mistake", function()
    for seed = 1, 10 do
        local f = open_search(seed, nil, 0.05, { refuse = true })
        local entered = false
        local elapsed = solve(f, 6000, function(g)
            local C = g.sides.client
            if not entered and C.mode == "walking" and g.t - C.last > 1.5 then
                entered = true
                g:manual_entry()
            end
        end)
        -- The refusal model refuses every interaction, so the manual entry bypasses it.
        assert(elapsed, "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
        eq(f.reopen_log.requests, 1, "one attempt, then switched off")
        eq(f.reopen_log.reopens, 0, "the refused attempt never entered")
    end
end)

test("Search press lost before the reopen: plans its stage again, no mistake", function()
    for seed = 1, 10 do
        local f = open_search(seed, nil, 0.08)
        local press, dropped = f.server.on_action_pressed, false
        f.server.on_action_pressed = function(self, t)
            if not dropped and self._current_stage == 1 then dropped = true; return end
            return press(self, t)
        end
        assert(solve(f, 6000), "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
    end
end)

test("Search recentre receipt 0.5 s late (ordered channel): no mistake", function()
    for seed = 1, 10 do
        local f = open_search(seed, nil, 0.05)
        local send, floor = f.send, 0
        f.send = function(self, to, name, ...)
            send(self, to, name, ...)
            local item = self.queue[#self.queue]
            if not item or item.name ~= name then return end
            if name == "rpc_minigame_sync_decode_search_set_cursor" and self.server._cursor_position.x == 3
                and self.server._cursor_position.y == 2 and self.server._current_stage > 1 then
                item.at = item.at + 0.5
            end
            -- Reliable RPCs keep their order.
            item.at = math.max(item.at, floor); floor = item.at
        end
        assert(solve(f, 6000), "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
    end
end)

local function open_symbols(seed, limit, delay, options)
    local f = fixture({ decode_reroll_limit = limit, enable_scan = false, enable_auto_scan = false })
    local Symbols = f.env.MinigameDecodeSymbols
    local init = Symbols.init
    Symbols.init = function(self, unit, is_server, _) return init(self, unit, is_server, 5000 + seed * 13) end
    f:open("decode_symbols", not (options and options.local_server), delay or 0.05)
    Symbols.init = init
    f.ping = 2 * (delay or 0.05) + 0.06
    return machine(f, options)
end

for _, delay in ipairs({ 0.03, 0.165 }) do
    test("Symbols reroll: faster on average, zero mistakes, at most four rerolls, receipt delay=" .. delay, function()
        local with, without, rerolls, most = {}, {}, 0, 0
        for seed = 1, 60 do
            local f = open_symbols(seed, 4, delay)
            local elapsed = solve(f, 6000)
            assert(elapsed, "seed " .. seed .. ": stalled")
            eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
            assert(f.reopen_log.reopens <= 4, "seed " .. seed .. ": more rerolls than the limit")
            with[#with + 1], rerolls = elapsed, rerolls + f.reopen_log.reopens
            most = math.max(most, f.reopen_log.reopens)
            local g = open_symbols(seed, 0, delay)
            without[#without + 1] = assert(solve(g, 6000), "seed " .. seed .. ": stalled without reroll")
            eq(g.server._mistakes, 0)
            eq(g.reopen_log.reopens, 0, "limit 0 turns rerolls off")
        end
        print(string.format("  mean solve %.3fs with rerolls (%.2f per hack, at most %d), %.3fs without",
            mean(with), rerolls / 60, most, mean(without)))
        if not baseline then assert(mean(with) < mean(without) - 0.5, "rerolls save at least 0.5 s on average") end
    end)
end

test("Symbols reroll on a local server", function()
    local with, without = {}, {}
    for seed = 1, 40 do
        local f = open_symbols(seed, 4, nil, { local_server = true })
        with[#with + 1] = assert(solve(f, 6000), "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0)
        local g = open_symbols(seed, 0, nil, { local_server = true })
        without[#without + 1] = assert(solve(g, 6000))
    end
    print(string.format("  mean solve %.3fs with rerolls, %.3fs without", mean(with), mean(without)))
    if not baseline then assert(mean(with) < mean(without) - 0.5, "faster on a local server too") end
end)

test("Symbols reroll refused: one attempt, the player re-enters, no mistake", function()
    for seed = 1, 20 do
        local f = open_symbols(seed, 4, 0.05, { refuse = true })
        local entered = false
        local elapsed = solve(f, 8000, function(g)
            local C = g.sides.client
            if not entered and C.mode == "walking" and g.t - C.last > 1.5 then entered = true; g:manual_entry() end
        end)
        assert(elapsed, "seed " .. seed .. ": stalled")
        eq(f.server._mistakes, 0, "seed " .. seed .. ": mistake")
        assert(f.reopen_log.requests <= 1, "switched off after the refusal")
    end
end)

print(string.format("RESULT %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
