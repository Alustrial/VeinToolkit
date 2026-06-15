------------------------------------------------------------
-- VeinCF :: config
-- Manages per-mod configuration: defaults from manifest,
-- user overrides from disk, type validation.
--
-- Config files live at: <veincf_root>/config/<mod_id>.json
-- They contain only the keys the user has overridden.
--
-- Require as: require("modules.config")
------------------------------------------------------------
local json = require("modules.json")
local log  = require("modules.log")

local M = {}

local SEP        = package.config:sub(1,1)
local config_dir = nil   -- set by init()
local store      = {}    -- [mod_id] = { key = value }

function M.init(veincf_root)
    config_dir = veincf_root .. SEP .. "config"
    -- ensure dir exists
    os.execute('mkdir "' .. config_dir .. '" 2>nul')
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

------------------------------------------------------------
-- Type coercion & validation
------------------------------------------------------------
local function validate_value(key, val, def)
    local t = def.type
    if t == "bool" then
        if type(val) ~= "boolean" then return nil, "expected boolean" end
    elseif t == "int" then
        if type(val) ~= "number" or val ~= math.floor(val) then return nil, "expected integer" end
        if def.min and val < def.min then return nil, string.format("below minimum %s", def.min) end
        if def.max and val > def.max then return nil, string.format("above maximum %s", def.max) end
    elseif t == "float" then
        if type(val) ~= "number" then return nil, "expected number" end
        if def.min and val < def.min then return nil, string.format("below minimum %s", def.min) end
        if def.max and val > def.max then return nil, string.format("above maximum %s", def.max) end
    elseif t == "string" then
        if type(val) ~= "string" then return nil, "expected string" end
    elseif t == "enum" then
        if type(val) ~= "string" then return nil, "expected string" end
        local found = false
        for _, opt in ipairs(def.options or {}) do
            if opt == val then found = true; break end
        end
        if not found then return nil, "not a valid option" end
    end
    return val
end

------------------------------------------------------------
-- Load config for a single mod
------------------------------------------------------------
function M.load_mod_config(mod_id, schema)
    -- Start with defaults
    local cfg = {}
    if schema then
        for key, def in pairs(schema) do
            cfg[key] = def.default
        end
    end

    -- Overlay user overrides
    if config_dir then
        local path = config_dir .. SEP .. mod_id .. ".json"
        local raw  = read_file(path)
        if raw then
            local ok, overrides = pcall(json.decode, raw)
            if ok and type(overrides) == "table" then
                for key, val in pairs(overrides) do
                    if schema and schema[key] then
                        local checked, err = validate_value(key, val, schema[key])
                        if checked ~= nil then
                            cfg[key] = checked
                        else
                            log.warn(mod_id, "Config '%s' override invalid (%s), using default", key, err)
                        end
                    else
                        -- Allow unknown keys (forward compat) but warn
                        log.debug(mod_id, "Config '%s' not in schema, passing through", key)
                        cfg[key] = val
                    end
                end
            elseif raw:match("%S") then
                log.warn(mod_id, "Failed to parse config file %s", path)
            end
        end
    end

    store[mod_id] = cfg
    return cfg
end

------------------------------------------------------------
-- Public API for mods
------------------------------------------------------------

--- Get a config value. Returns default if unset.
function M.get(mod_id, key)
    local cfg = store[mod_id]
    if not cfg then return nil end
    return cfg[key]
end

--- Get entire config table for a mod (read-only copy).
function M.get_all(mod_id)
    local cfg = store[mod_id]
    if not cfg then return {} end
    local copy = {}
    for k, v in pairs(cfg) do copy[k] = v end
    return copy
end

return M
