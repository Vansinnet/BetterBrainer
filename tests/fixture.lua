-- Adapt the historical fixture only; never execute its legacy test suite.
local M = { source = "darktide-source/Darktide-Source-Code-1.13.0/" }
local ROOT = "mods/active/BetterBrainer/scripts/mods/BetterBrainer/"

function M.read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

function M.replace(text, before, after)
    local first, last = text:find(before, 1, true)
    assert(first, "adapter block missing: " .. before)
    assert(not text:find(before, last + 1, true), "adapter block is not unique: " .. before)
    return text:sub(1, first - 1) .. after .. text:sub(last + 1)
end

function M.pack(...) return { n = select("#", ...), ... } end
function M.eq(actual, expected, why)
    assert(actual == expected, (why or "equality") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function M.near(actual, expected, why)
    assert(math.abs(actual - expected) < 1e-8,
        (why or "scalar mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function M.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = M.copy(item) end
    return result
end

local historical = M.read("tools/tests/better_brainer_spec.lua")
local boundary = assert(historical:find("\nlocal tests, failed = 0, 0", 1, true), "historical fixture boundary")
local fixture_text = historical:sub(1, boundary - 1)
assert(fixture_text:match("return f\nend\n$"), "historical fixture ending changed")
fixture_text = M.replace(fixture_text, "env.math.atan2 = math.atan", "env.math.atan2 = math.atan2")
fixture_text = M.replace(fixture_text, "{ rewind_ms = function() return f.rewind or 0 end }",
    "{ rewind_seconds = function() return f.rewind or 0 end }")

-- Snapshot once per process: every fixture sees identical runtime module text.
local runtime = {}
for _, name in ipairs({ "BetterBrainer", "BetterBrainer_data", "symbols", "search", "frequency", "scan", "drill", "balance" }) do
    runtime[ROOT .. name .. ".lua"] = M.read(ROOT .. name .. ".lua")
end

function M.factory()
    local compat_table = M.copy(table)
    compat_table.pack, compat_table.unpack = M.pack, unpack
    local outer = setmetatable({ table = compat_table }, { __index = _G })
    outer.loadfile = function(path, mode, env)
        if path:sub(1, 16) == "darktide-source/" then path = M.source .. path:sub(17) end
        local text = runtime[path] or M.read(path)
        local chunk, err = loadstring(text, "@" .. path)
        if chunk then setfenv(chunk, env or outer) end
        return chunk, err
    end
    local chunk = assert(loadstring(fixture_text .. "\nreturn fixture\n", "@tools/tests/better_brainer_spec.lua"))
    setfenv(chunk, outer)
    return chunk()
end

function M.deliver(f, name)
    for i, item in ipairs(f.queue) do
        if item.name == name then
            table.remove(f.queue, i)
            f:dispatch(item.to, item.name, item.args)
            return item
        end
    end
    error("missing queued " .. name)
end

function M.rpc(f, suffix, ...)
    f:dispatch("client", "rpc_minigame_sync_" .. suffix, M.pack(1, true, ...))
end

function M.scan_fixture(factory)
    local f = factory({ enable_scan = false, enable_auto_scan = true })
    local env = f.env
    local function noop() end
    local base = env.class("ActionWeaponBase")
    base.start, base.finish = noop, noop
    local original_require, cache = env.require, {}
    local ACTION = "scripts/extension_systems/weapon/actions/"
    local EXT = "scripts/extension_systems/mission_objective_zone_scannable/mission_objective_zone_scannable_extension"
    local allowed = { [ACTION .. "action_scan"] = true, [ACTION .. "action_scan_confirm"] = true,
        ["scripts/utilities/scanning"] = true, [EXT] = true }
    env.require = function(path)
        if path == ACTION .. "action_weapon_base" then return base end
        if path == "scripts/utilities/alternate_fire" or path == "scripts/utilities/weapon/weapon_template" then return {} end
        if not allowed[path] then return original_require(path) end
        if not cache[path] then
            local chunk = assert(loadstring(M.read(M.source .. path .. ".lua"), "@" .. M.source .. path .. ".lua"))
            setfenv(chunk, env)
            cache[path] = chunk()
            if f.deferred[path] then f.deferred[path](cache[path]) end
        end
        return cache[path]
    end
    local template = M.read(M.source .. "scripts/settings/equipment/weapon_templates/devices/scanner_equip.lua")
    local settings_text = assert(template:match("local scan_settings = (%b{})\n\nweapon_template.actions"))
    local scan_settings = assert(loadstring("return " .. settings_text))()
    M.eq(scan_settings.confirm_time, 1, "historical scanner stub matches pinned source")
    env.ALIVE = setmetatable({}, { __index = function(_, unit) return env.Unit.alive(unit) end })
    env.Quaternion = { forward = function() return env.Vector3(0, 1, 0) end }
    env.Actor = { unit = function(actor) return actor end }
    env.PhysicsWorld = { raycast = function(_, _, _, distance, mode, _, filter)
        M.eq(distance, scan_settings.distance.near)
        if mode == "closest" then M.eq(filter, "filter_interactable_line_of_sight_check"); return nil end
        M.eq(mode, "all"); M.eq(filter, "filter_interactable_overlap")
        return f.aim and { { [2] = 1, [4] = f.aim } } or nil
    end }
    local zone = { scannable_units = function() return {} end, any_active_scanning_zone = function() return true end }
    env.Managers.state.extension = { system = function(_, name)
        M.eq(name, "mission_objective_zone_system"); return zone
    end, has_system = function() return false end }
    local extension_class = env.require(EXT)
    f.a, f.b = {}, {}
    for _, unit in ipairs({ f.a, f.b }) do
        f.extensions[unit] = { mission_objective_zone_scannable_system = setmetatable({
            _unit = unit, _is_active = true, _is_server = false,
        }, extension_class) }
    end
    f.components = { weapon_action = {}, scanning = { is_active = false, line_of_sight = false } }
    f.extensions[f.player.player_unit] = { unit_data_system = { read_component = function(_, name)
        return f.components[name]
    end } }
    local function action(class)
        return setmetatable({ _scanning_compomnent = f.components.scanning, _player = f.player, _is_server = false,
            _action_settings = { scan_settings = scan_settings }, _weapon_template = {},
            _weapon_tweak_templates_component = {}, _alternate_fire_component = { is_active = true },
            _first_person_component = { position = env.Vector3.zero(), rotation = {} },
            _fx_extension = { trigger_gear_wwise_event_with_source = noop },
        }, class)
    end
    f.scan_action = action(env.require(ACTION .. "action_scan"))
    f.confirm_action = action(env.require(ACTION .. "action_scan_confirm"))
    function f:resume(target)
        self.aim = target
        self.components.weapon_action.current_action_name = "action_scan"
        self.scan_action:start(self.scan_action._action_settings, self.t)
        self.scan_action:fixed_update(0.02, self.t, 0)
        M.eq(self.components.scanning.scannable_unit, target, "native acquisition")
    end
    function f:confirm()
        self.components.weapon_action.current_action_name = "action_scan_confirm"
        self.confirm_action:start(self.confirm_action._action_settings, self.t)
        self.confirm_action:fixed_update(0.02, self.t, 0)
        self.mod.update(0.02)
    end
    function f:abort()
        self.confirm_action:finish("action_complete", nil, self.t, 0.1)
        M.eq(self.components.scanning.is_active, false, "native finish clears component")
        M.eq(self.components.scanning.scannable_unit, nil)
    end
    return f
end

return M
