------------------------------------------------------------
-- VeinCF :: api
-- Inter-mod API registry.
-- Mods export a table of functions via their manifest's
-- api.exports script. Other mods call them through
--   veincf.api.call("mod_id", "function_name", ...)
--
-- Require as: require("modules.api")
------------------------------------------------------------
local log = require("modules.log")

local M = {}

local registry = {}   -- [mod_id] = { version = N, funcs = { ... } }

--- Register a mod's API from its exports script return value.
function M.register(mod_id, api_table, version)
    if type(api_table) ~= "table" then
        log.warn(mod_id, "api.exports did not return a table — skipping API registration")
        return false
    end
    registry[mod_id] = {
        version = version or 1,
        funcs   = api_table,
    }
    local count = 0
    for _ in pairs(api_table) do count = count + 1 end
    log.debug(mod_id, "Registered API v%d with %d exports", version or 1, count)
    return true
end

--- Call another mod's exported function.
--- Returns nil + error string on failure.
function M.call(mod_id, func_name, ...)
    local entry = registry[mod_id]
    if not entry then
        return nil, string.format("no API registered for mod '%s'", mod_id)
    end
    local fn = entry.funcs[func_name]
    if not fn then
        return nil, string.format("mod '%s' does not export '%s'", mod_id, func_name)
    end
    return fn(...)
end

--- Get the API version number a mod registered.
function M.get_version(mod_id)
    local entry = registry[mod_id]
    return entry and entry.version
end

--- Check if a mod has registered an API.
function M.has(mod_id)
    return registry[mod_id] ~= nil
end

--- List all exported function names for a mod.
function M.list_exports(mod_id)
    local entry = registry[mod_id]
    if not entry then return {} end
    local names = {}
    for k in pairs(entry.funcs) do names[#names+1] = k end
    table.sort(names)
    return names
end

return M
