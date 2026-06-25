------------------------------------------------------------
-- VeinCF :: loader
-- Executes mod entrypoints in the resolved load order.
-- Handles pak mounting, config init, API registration,
-- hook setup, and lifecycle script execution.
--
-- Require as: require("modules.loader")
------------------------------------------------------------
local log     = require("modules.log")
local config  = require("modules.config")
local api     = require("modules.api")
local recipes = require("modules.recipes")
local mechanics = require("modules.mechanics")

local M = {}

local SEP    = package.config:sub(1,1)
local ui_mod = nil   -- set by main.lua via set_ui_module()

function M.set_ui_module(mod)
    ui_mod = mod
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

--- Safely execute a Lua file, returning its return value.
local function exec_script(path, mod_id)
    local fn, err = loadfile(path)
    if not fn then
        log.error(mod_id, "Failed to load script '%s': %s", path, err)
        return nil, err
    end
    local ok, result = pcall(fn)
    if not ok then
        log.error(mod_id, "Runtime error in '%s': %s", path, result)
        return nil, result
    end
    return result
end

------------------------------------------------------------
-- Pak mounting (UE4SS-specific)
------------------------------------------------------------

--- Resolve the LogicMods directory path.
--- UE5 auto-mounts all .pak files placed here.
local _logic_mods_dir = nil

local function get_logic_mods_dir()
    if _logic_mods_dir then return _logic_mods_dir end

    -- UE4SS provides CreateLogicModsDirectory which also tells us the path.
    -- The path is: <GameRoot>/<GameName>/Content/Paks/LogicMods/
    -- We derive it from the UE4SS Mods directory:
    --   Mods dir: <GameRoot>/<GameName>/Binaries/Win64/ue4ss/Mods/
    --   We need:  <GameRoot>/<GameName>/Content/Paks/LogicMods/

    -- Strategy 1: Walk up from the mod root to find Content/Paks
    -- m._root example: .../ue4ss/Mods/VeinCF/mods/some_mod
    -- Game root:       .../Vein/Vein/

    -- Strategy 2: Use the VeinCF Scripts path to locate ourselves
    local scripts_path = debug.getinfo(1, "S").source:sub(2)  -- remove @
    -- scripts_path: .../ue4ss/Mods/VeinCF/Scripts/modules/loader.lua
    -- Walk up to ue4ss/, then go to ../../Content/Paks/LogicMods
    local ue4ss_dir = scripts_path:match("(.+)[/\\]Mods[/\\]")
    if ue4ss_dir then
        -- ue4ss_dir = .../Binaries/Win64/ue4ss
        -- Go up to Win64, then Binaries, then GameName root
        local bin_dir = ue4ss_dir:match("(.+)[/\\][^/\\]+$")      -- .../Binaries/Win64
        local binaries = bin_dir and bin_dir:match("(.+)[/\\][^/\\]+$")  -- .../Binaries
        local game_dir = binaries and binaries:match("(.+)[/\\][^/\\]+$") -- .../GameName
        if game_dir then
            local candidate = game_dir .. SEP .. "Content" .. SEP .. "Paks" .. SEP .. "LogicMods"
            local test = io.open(candidate .. SEP .. ".veincf_probe", "w")
            if test then
                test:close()
                os.remove(candidate .. SEP .. ".veincf_probe")
                _logic_mods_dir = candidate
                log.debug(nil, "LogicMods dir: %s", _logic_mods_dir)
                return _logic_mods_dir
            end
        end
    end

    -- Strategy 3: Ensure directory exists via UE4SS global
    if CreateLogicModsDirectory then
        pcall(CreateLogicModsDirectory)
    end

    -- Strategy 4: Hardcoded fallback for known VEIN structure
    -- Try common relative path from mod root
    log.warn(nil, "Could not auto-detect LogicMods path — pak mounting may fail")
    return nil
end

--- Copy a file from src to dst (binary safe).
local function copy_file(src, dst)
    local fin = io.open(src, "rb")
    if not fin then return false, "cannot read " .. src end

    local fout = io.open(dst, "wb")
    if not fout then
        fin:close()
        return false, "cannot write " .. dst
    end

    local chunk_size = 65536
    while true do
        local data = fin:read(chunk_size)
        if not data then break end
        fout:write(data)
    end

    fin:close()
    fout:close()
    return true
end

local function mount_paks(m)
    if not m.paks then return end

    local lm_dir = get_logic_mods_dir()
    if not lm_dir then
        log.error(m.id, "Cannot mount paks: LogicMods directory not found")
        return
    end

    for _, pak in ipairs(m.paks) do
        local pak_file = type(pak) == "table" and pak.file or pak
        local src_path = m._root .. SEP .. pak_file
        local pak_name = pak_file:match("[^/\\]+$")  -- just the filename
        local dst_path = lm_dir .. SEP .. pak_name

        -- Check source exists
        local f = io.open(src_path, "rb")
        if not f then
            log.error(m.id, "Pak file not found: %s", pak_file)
        else
            f:close()

            -- Check if already deployed (avoid redundant copies)
            local existing = io.open(dst_path, "rb")
            if existing then
                -- Compare file sizes to detect changes
                local src_size = existing:seek("end") -- this is dst actually
                existing:close()
                local src_f = io.open(src_path, "rb")
                local real_src_size = src_f:seek("end")
                src_f:close()

                if src_size == real_src_size then
                    log.debug(m.id, "Pak already deployed: %s", pak_name)
                    goto next_pak
                end
                log.info(m.id, "Pak changed, re-deploying: %s", pak_name)
            end

            -- Copy pak to LogicMods
            log.info(m.id, "Deploying pak: %s -> %s", pak_file, dst_path)
            local ok, err = copy_file(src_path, dst_path)
            if ok then
                log.info(m.id, "Pak deployed: %s (will load on next game start)", pak_name)
            else
                log.error(m.id, "Failed to deploy pak %s: %s", pak_name, err)
            end
        end
        ::next_pak::
    end
end

------------------------------------------------------------
-- Build the sandbox environment each mod script sees
------------------------------------------------------------

local function build_mod_env(mod_id, mod_root)
    -- Start with a copy of _G so mods have full UE4SS access
    local env = setmetatable({}, { __index = _G })

    -- Inject VeinCF namespace
    env.veincf = {
        -- config
        config = {
            get     = function(key) return config.get(mod_id, key) end,
            get_all = function()    return config.get_all(mod_id) end,
        },
        -- inter-mod API
        api = {
            call         = api.call,
            has          = api.has,
            get_version  = api.get_version,
            list_exports = api.list_exports,
        },
        -- logging scoped to this mod
        log = {
            debug = function(fmt, ...) log.debug(mod_id, fmt, ...) end,
            info  = function(fmt, ...) log.info(mod_id, fmt, ...)  end,
            warn  = function(fmt, ...) log.warn(mod_id, fmt, ...)  end,
            error = function(fmt, ...) log.error(mod_id, fmt, ...) end,
        },
        -- UI: in-game overlay panel + draw callback registration
        ui = ui_mod and {
            register_draw    = function(fn) ui_mod.register_draw(mod_id, fn) end,
            unregister_draw  = function()   ui_mod.unregister_draw(mod_id)   end,
            register_panel   = function(name, fn) ui_mod.register_panel(name, fn) end,
            unregister_panel = function(name) ui_mod.unregister_panel(name) end,
            set_panel_visible = function(name, v) ui_mod.set_panel_visible(name, v) end,
            toggle_overlay   = function() ui_mod.toggle_overlay() end,
            is_overlay_visible = function() return ui_mod.is_overlay_visible() end,
            is_available     = function() return ui_mod.is_available() end,
        } or nil,
        -- recipe injection API
        recipes = {
            add               = recipes.add,
            remove            = recipes.remove,
            remove_all        = recipes.remove_all,
            modify            = recipes.modify,
            list              = recipes.list,
            get_all_recipes   = recipes.get_all_recipes,
            get_recipe        = recipes.get_recipe,
            invalidate_cache  = recipes.invalidate_cache,
            -- new-content pipeline (pak -> repair -> register)
            load_from_pak     = recipes.load_from_pak,
            load_class_by_path = recipes.load_class_by_path,
            repair            = recipes.repair,
            register          = recipes.register,
            register_declared = recipes.register_declared,
            register_backend  = recipes.register_backend,
            raw               = recipes.raw,
            register_content  = recipes.register_content,
        },
        -- gameplay verbs (reflected; crash-safe wrappers — see modules/mechanics.lua)
        player = {
            get                 = mechanics.player,   -- the local player pawn
            get_health          = mechanics.get_health,
            heal                = mechanics.heal,
            heal_everyone       = mechanics.heal_everyone,
            damage              = mechanics.damage,
            damage_consciousness = mechanics.damage_consciousness,
            damage_target       = mechanics.damage_target,
            set_item_damage     = mechanics.set_item_damage,
            set_vehicle_damage  = mechanics.set_vehicle_damage,
            give_key            = mechanics.give_key,
            give_ammo           = mechanics.give_ammo,
            -- give / items (contract cracked 2026-06-24: GiveItem(name:string, count:number))
            give_item           = mechanics.give_item,
            give_item_list      = mechanics.give_item_list,
            give_every_item     = mechanics.give_every_item,
            -- progress / status
            add_xp              = mechanics.add_xp,
            add_perk            = mechanics.add_perk,
            power_up            = mechanics.power_up,
            set_condition       = mechanics.set_condition,   -- set_condition(name, amount)
            ignite              = mechanics.ignite_target,
            -- reads
            get_conditions      = mechanics.get_conditions,
            get_stats           = mechanics.get_stats,
            get_inventory       = mechanics.get_inventory,
            get_temperature     = mechanics.get_temperature,
            -- inventory (class-based, no struct): has_item(class) / remove_amount(class, count)
            has_item            = mechanics.has_item,
            remove_amount       = mechanics.remove_amount,
        },
        -- world: BASE VERBS (primitives — modders compose mechanics like brood/dungeon themselves)
        world = {
            spawn       = mechanics.spawn,        -- functional spawn (body+AI): spawn(class, {near,x,y,z,scale,ai})
            give_ai     = mechanics.give_ai,      -- possess a pawn with its default AI controller
            is_dead     = mechanics.is_dead,
            get_health  = mechanics.get_health_of,-- any actor's health
            destroy     = mechanics.destroy,
            find        = mechanics.find,         -- all live instances of a class name
            find_class  = mechanics.find_class,   -- resolve a class by name/path
            on          = mechanics.on,           -- event hook: on(class, "FuncName", cb) -> handle (the trigger primitive)
            off         = mechanics.off,           -- off(handle)
            spawn_horde = mechanics.spawn_horde,
            spawn_flyby = mechanics.spawn_flyby,
            -- teleport / movement (TargetId / VectorString are name/string args)
            teleport_to     = mechanics.teleport_to,
            teleport_all_to = mechanics.teleport_all_to,
            bring_all_to_me = mechanics.bring_all_to_me,
            goto_vec        = mechanics.goto_vec,
            -- world / event
            explosion   = mechanics.explosion,
            set_weather = mechanics.set_weather,
            add_time    = mechanics.add_time,
            remove_ai   = mechanics.remove_ai,
            zombify     = mechanics.zombify,
        },
        actor = {
            location     = mechanics.location,
            set_location = mechanics.set_location,
            set_scale    = mechanics.set_scale,
            distance     = mechanics.distance,
        },
        timer = {
            loop   = mechanics.loop,    -- loop(ms, fn): fn returns true to stop
            after  = mechanics.after,   -- after(ms, fn): one-shot
            cancel = mechanics.cancel,  -- cancel(handle)
        },
        -- game definitions (lazy-loaded from generated defs)
        defs = (function()
            local ok, framework = pcall(require, "generated.lua.veincf_framework")
            if ok then return framework end
            -- Fallback: try loading from VeinCF root
            local defs_path = mod_root:match("(.+)[/\\]mods[/\\]") or mod_root
            defs_path = defs_path .. SEP .. "generated" .. SEP .. "lua" .. SEP .. "veincf_framework"
            local fn = loadfile(defs_path .. ".lua")
            if fn then return fn() end
            return {}
        end)(),
        -- identity
        mod_id   = mod_id,
        mod_root = mod_root,
    }

    return env
end

------------------------------------------------------------
-- Hook registration (UE4SS-specific)
------------------------------------------------------------

--- Load a handler script from a mod and return its callback function.
--- The script should return a function (or table of functions).
local function load_handler(m, handler_path)
    local full_path = m._root .. SEP .. handler_path
    local fn, err = loadfile(full_path)
    if not fn then
        log.error(m.id, "Failed to load handler '%s': %s", handler_path, err)
        return nil
    end

    -- Run in mod's sandboxed environment
    local env = build_mod_env(m.id, m._root)
    if setfenv then
        setfenv(fn, env)
    else
        local i = 1
        while true do
            local name = debug.getupvalue(fn, i)
            if name == "_ENV" then
                debug.setupvalue(fn, i, env)
                break
            elseif not name then break end
            i = i + 1
        end
    end

    local ok, result = pcall(fn)
    if not ok then
        log.error(m.id, "Handler '%s' error: %s", handler_path, tostring(result))
        return nil
    end
    return result
end

local function setup_hooks(m)
    if not m.hooks then return end

    for _, hook in ipairs(m.hooks) do
        local callback

        -- Load the handler if specified as a file path
        if hook.handler then
            callback = load_handler(m, hook.handler)
            if not callback then
                log.error(m.id, "Skipping hook '%s' — handler failed to load", hook.target)
                goto next_hook
            end
            -- If handler returned a table, look for a specific function
            if type(callback) == "table" then
                local func_name = hook.callback or "on_hook"
                callback = callback[func_name]
                if not callback then
                    log.error(m.id, "Handler table has no '%s' function for hook '%s'",
                              func_name, hook.target)
                    goto next_hook
                end
            end
            if type(callback) ~= "function" then
                log.error(m.id, "Hook handler for '%s' is not a function (got %s)",
                          hook.target, type(callback))
                goto next_hook
            end
        end

        if hook.type == "function" then
            -- UE4SS: RegisterHook("/Path/To/Function", callback)
            if not RegisterHook then
                log.warn(m.id, "RegisterHook not available — hook '%s' skipped", hook.target)
            elseif not callback then
                log.warn(m.id, "No handler for function hook '%s'", hook.target)
            else
                local ok, err = pcall(RegisterHook, hook.target, function(self, ...)
                    local s, e = pcall(callback, self, ...)
                    if not s then
                        log.error(m.id, "Hook callback error [%s]: %s", hook.target, tostring(e))
                    end
                end)
                if ok then
                    log.info(m.id, "Hook registered: function %s", hook.target)
                else
                    log.error(m.id, "RegisterHook failed for '%s': %s", hook.target, tostring(err))
                end
            end

        elseif hook.type == "object_create" then
            -- UE4SS: NotifyOnNewObject("/Path/To/Class", callback)
            if not NotifyOnNewObject then
                log.warn(m.id, "NotifyOnNewObject not available — hook '%s' skipped", hook.target)
            elseif not callback then
                log.warn(m.id, "No handler for object_create hook '%s'", hook.target)
            else
                local ok, err = pcall(NotifyOnNewObject, hook.target, function(obj)
                    local s, e = pcall(callback, obj)
                    if not s then
                        log.error(m.id, "Hook callback error [%s]: %s", hook.target, tostring(e))
                    end
                end)
                if ok then
                    log.info(m.id, "Hook registered: object_create %s", hook.target)
                else
                    log.error(m.id, "NotifyOnNewObject failed for '%s': %s", hook.target, tostring(err))
                end
            end

        elseif hook.type == "console_command" then
            -- UE4SS: RegisterConsoleCommandHandler(name, callback)
            if not RegisterConsoleCommandHandler then
                log.warn(m.id, "RegisterConsoleCommandHandler not available — '%s' skipped", hook.target)
            elseif not callback then
                log.warn(m.id, "No handler for console_command hook '%s'", hook.target)
            else
                local ok, err = pcall(RegisterConsoleCommandHandler, hook.target, function(full_cmd, args, output_device)
                    local s, e = pcall(callback, full_cmd, args, output_device)
                    if not s then
                        log.error(m.id, "Console command error [%s]: %s", hook.target, tostring(e))
                    end
                    return s
                end)
                if ok then
                    log.info(m.id, "Hook registered: console_command %s", hook.target)
                else
                    log.error(m.id, "RegisterConsoleCommandHandler failed for '%s': %s", hook.target, tostring(err))
                end
            end

        elseif hook.type == "key_bind" then
            -- UE4SS: RegisterKeyBind(key, callback) or RegisterKeyBind(key, modifiers, callback)
            if not RegisterKeyBind then
                log.warn(m.id, "RegisterKeyBind not available — '%s' skipped", hook.target)
            elseif not callback then
                log.warn(m.id, "No handler for key_bind hook '%s'", hook.target)
            else
                local key = hook.target
                local mods = hook.modifiers  -- e.g. { ModifierKey.CONTROL }
                local ok, err
                if mods and #mods > 0 then
                    ok, err = pcall(RegisterKeyBind, key, mods, function()
                        local s, e = pcall(callback)
                        if not s then
                            log.error(m.id, "Key bind error [%s]: %s", key, tostring(e))
                        end
                    end)
                else
                    ok, err = pcall(RegisterKeyBind, key, function()
                        local s, e = pcall(callback)
                        if not s then
                            log.error(m.id, "Key bind error [%s]: %s", key, tostring(e))
                        end
                    end)
                end
                if ok then
                    log.info(m.id, "Hook registered: key_bind %s", key)
                else
                    log.error(m.id, "RegisterKeyBind failed for '%s': %s", key, tostring(err))
                end
            end

        else
            log.warn(m.id, "Unknown hook type '%s'", tostring(hook.type))
        end

        ::next_hook::
    end
end

------------------------------------------------------------
-- Execute a single entrypoint script with the mod's env
------------------------------------------------------------

local function run_entrypoint(m, phase)
    local ep = m.entrypoints and m.entrypoints[phase]
    if not ep then return true end

    local path = m._root .. SEP .. ep
    local env  = build_mod_env(m.id, m._root)

    local fn, err = loadfile(path)
    if not fn then
        log.error(m.id, "[%s] Failed to load: %s", phase, err)
        return false
    end

    -- Run in the mod's environment
    if setfenv then
        setfenv(fn, env)  -- Lua 5.1
    else
        -- Lua 5.2+ / LuaJIT: use debug.setupvalue for _ENV
        local i = 1
        while true do
            local name = debug.getupvalue(fn, i)
            if name == "_ENV" then
                debug.setupvalue(fn, i, env)
                break
            elseif not name then
                break
            end
            i = i + 1
        end
    end

    local ok, result = pcall(fn)
    if not ok then
        log.error(m.id, "[%s] Runtime error: %s", phase, tostring(result))
        return false
    end

    return true, result
end

------------------------------------------------------------
-- Load a single mod (full lifecycle)
------------------------------------------------------------

local function load_one(m)
    log.info(m.id, "Loading v%s ...", m.version)

    -- 1. Mount paks (before any Lua runs)
    mount_paks(m)

    -- 2. Load config
    config.load_mod_config(m.id, m.config_schema)
    local cfg_count = 0
    if m.config_schema then
        for _ in pairs(m.config_schema) do cfg_count = cfg_count + 1 end
    end
    log.debug(m.id, "Config loaded (%d keys)", cfg_count)

    -- 3. Run entrypoints in lifecycle order
    local phases = { "config", "shared", "main" }
    -- TODO: detect client vs server context and add the appropriate phase
    for _, phase in ipairs(phases) do
        local ok = run_entrypoint(m, phase)
        if not ok then
            log.error(m.id, "Aborted at '%s' phase", phase)
            return false
        end
    end

    -- 4. Register API exports
    if m.api and m.api.exports then
        local path   = m._root .. SEP .. m.api.exports
        local result = exec_script(path, m.id)
        if result then
            api.register(m.id, result, m.api.version or 1)
        end
    end

    -- 5. Set up hooks
    setup_hooks(m)

    -- 6. Queue declared cooked recipes (manifest `recipes`) for WORLD-LOAD registration.
    --    Paks must already be mounted (deployed on a prior launch). Registration itself runs
    --    at world-load (AssetManager exists, before the craft UI builds) via register_content.
    if m.recipes and #m.recipes > 0 then
        local r = recipes.register_declared(m.recipes, m.id, m._root)
        log.info(m.id, "Recipes: %d queued for world-load registration (of %d declared)",
                 r.prepared, #m.recipes)
    end

    log.info(m.id, "Loaded successfully.")
    return true
end

------------------------------------------------------------
-- Public: load all mods in order
------------------------------------------------------------

--- Execute all mods in the given order.
--- `manifests` = { [id] = manifest }, `order` = { id1, id2, ... }
--- Returns list of successfully loaded mod IDs.
function M.load_all(manifests, order)
    local loaded  = {}
    local failed  = {}

    log.info(nil, "Loading %d mods ...", #order)
    log.info(nil, "Load order: %s", table.concat(order, " -> "))

    for _, id in ipairs(order) do
        local m = manifests[id]
        if not m then
            log.error(id, "Manifest disappeared after resolution — skipping")
            goto next
        end

        -- Check that all hard deps actually loaded (not just resolved)
        local deps = m.requires and m.requires.mods
        if deps then
            local dep_ok = true
            for dep_id in pairs(deps) do
                local found = false
                for _, lid in ipairs(loaded) do
                    if lid == dep_id then found = true; break end
                end
                if not found then
                    log.error(id, "Dependency '%s' failed to load — skipping", dep_id)
                    dep_ok = false
                    break
                end
            end
            if not dep_ok then
                failed[#failed+1] = id
                goto next
            end
        end

        local ok = load_one(m)
        if ok then
            loaded[#loaded+1] = id
        else
            failed[#failed+1] = id
        end

        ::next::
    end

    if #failed > 0 then
        log.warn(nil, "%d mod(s) failed to load: %s", #failed, table.concat(failed, ", "))
    end

    return loaded
end

return M
