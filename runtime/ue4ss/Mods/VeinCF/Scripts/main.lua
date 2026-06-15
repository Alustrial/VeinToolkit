------------------------------------------------------------
-- VeinCF :: main.lua
-- UE4SS mod entry point.
--
-- ┌─ REQUIRE PATH RULE ─────────────────────────────────┐
-- │ UE4SS resolves require() relative to Scripts/.       │
-- │ All framework modules live in Scripts/modules/.      │
-- │ require("modules.log") → Scripts/modules/log.lua    │
-- │ Do NOT manipulate package.path.                      │
-- └──────────────────────────────────────────────────────┘
------------------------------------------------------------

local VEINCF_VERSION = "0.1.0"

local SEP = package.config:sub(1,1)

local function get_veincf_root()
    local info = debug.getinfo(1, "S")
    local source = info.source
    if source:sub(1,1) == "@" then source = source:sub(2) end
    local scripts_dir = source:match("^(.+)[/\\][^/\\]+$") or "."
    local root = scripts_dir:match("^(.+)[/\\][Ss]cripts$")
    if root then return root end
    return scripts_dir .. SEP .. ".."
end

local veincf_root = get_veincf_root()

------------------------------------------------------------
-- Load framework modules
------------------------------------------------------------
local log      = require("modules.log")
local manifest = require("modules.manifest")
local resolver = require("modules.resolver")
local config   = require("modules.config")
local loader   = require("modules.loader")
local ui       = require("modules.ui")

------------------------------------------------------------
-- Environment probe — dump every UE4SS global so we know
-- exactly what APIs are available.
------------------------------------------------------------
local function probe_environment()
    log.info(nil, "=== UE4SS Environment Probe ===")

    local lua_builtins = {
        _G=1, _VERSION=1, arg=1, assert=1, collectgarbage=1,
        coroutine=1, debug=1, dofile=1, error=1, getmetatable=1,
        io=1, ipairs=1, load=1, loadfile=1, math=1, next=1,
        os=1, package=1, pairs=1, pcall=1, print=1, rawequal=1,
        rawget=1, rawlen=1, rawset=1, require=1, select=1,
        setmetatable=1, string=1, table=1, tonumber=1, tostring=1,
        type=1, utf8=1, xpcall=1, warn=1,
        setfenv=1, getfenv=1, unpack=1, loadstring=1, module=1, newproxy=1,
    }

    local custom = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and not lua_builtins[k] then
            custom[#custom+1] = string.format("  %-45s %s", k, type(v))
        end
    end
    table.sort(custom)

    log.info(nil, "Non-Lua globals (%d):", #custom)
    for _, line in ipairs(custom) do
        log.info(nil, "%s", line)
    end
    log.info(nil, "=== End Probe ===")
end

------------------------------------------------------------
-- Environment detection
------------------------------------------------------------
local function detect_env()
    local env = {
        veincf = VEINCF_VERSION,
        ue4ss  = nil,
        game   = nil,
    }
    if UE4SS and UE4SS.GetVersion then
        local ok, ver = pcall(UE4SS.GetVersion)
        if ok then env.ue4ss = ver end
    end
    if not env.ue4ss then
        env.ue4ss = "3.0.1"
    end
    env.game = nil
    return env
end

------------------------------------------------------------
-- Main
------------------------------------------------------------
local function main()
    log.reset()

    print("")
    print("========================================")
    print("  VeinCF v" .. VEINCF_VERSION)
    print("  Community Framework for VEIN")
    print("========================================")
    print("")

    log.info(nil, "Root: %s", veincf_root)

    -- Probe FIRST so we always see what UE4SS gives us
    probe_environment()

    -- Init subsystems
    config.init(veincf_root)
    loader.set_ui_module(ui)

    local env = detect_env()
    log.info(nil, "Environment: VeinCF %s, UE4SS %s, Game %s",
             env.veincf, env.ue4ss or "?", env.game or "any")

    -- Discover mods
    local mods_dir  = veincf_root .. SEP .. "mods"
    local manifests = manifest.discover(mods_dir)

    local total = 0
    for _ in pairs(manifests) do total = total + 1 end

    if total == 0 then
        log.info(nil, "No mods found in %s", mods_dir)
        log.print_summary()
        return
    end

    log.info(nil, "Discovered %d valid mod(s)", total)

    local order = resolver.resolve(manifests, env)

    local errs = log.get_errors()
    if #errs > 0 then
        log.warn(nil, "%d error(s) during resolution — affected mods will not load", #errs)
    end

    local loaded = loader.load_all(manifests, order)

    log.info(nil, "%d / %d mod(s) loaded successfully", #loaded, total)
    log.print_summary()
end

local ok, err = pcall(main)
if not ok then
    print("[VeinCF/FATAL] Framework crashed: " .. tostring(err))
    print("[VeinCF/FATAL] No mods were loaded. Please report this bug.")
end
