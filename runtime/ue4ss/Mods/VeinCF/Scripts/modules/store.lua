------------------------------------------------------------
-- VeinCF :: store — persistent key/value for mods. Table -> JSON file -> reload.
-- Patch-proof + version-independent (no engine/USaveGame dependency — see
-- library docs/ue56-save-and-replication.md). The save story for script mods.
--   veincf.store.set(k, v) / get(k, default) / save() / load()
-- Persists to a single JSON file the loader binds via store.bind(path). Mods
-- should namespace their keys (e.g. "mymod.score") since the store is shared.
------------------------------------------------------------
local M = {}
local _data = {}
local _path = nil

-- minimal JSON encoder (strings/numbers/booleans/nested tables; arrays vs objects)
local function _esc(s)
    return (s:gsub('[%z\1-\31"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format('\\u%04x', string.byte(c))
    end))
end
local function _enc(v)
    local t = type(v)
    if t == "boolean" then return tostring(v)
    elseif t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or tostring(v)
    elseif t == "string" then return '"' .. _esc(v) .. '"'
    elseif t == "table" then
        local n, isarr = 0, true
        for k in pairs(v) do n = n + 1; if type(k) ~= "number" then isarr = false end end
        if isarr and n == #v then
            local p = {}; for _, e in ipairs(v) do p[#p + 1] = _enc(e) end
            return "[" .. table.concat(p, ",") .. "]"
        end
        local p = {}; for k, e in pairs(v) do p[#p + 1] = '"' .. _esc(tostring(k)) .. '":' .. _enc(e) end
        return "{" .. table.concat(p, ",") .. "}"
    end
    return "null"
end

--- Bind the on-disk file (called by the loader at startup).
function M.bind(path) _path = path end

function M.set(k, v) _data[k] = v end
function M.get(k, default) local v = _data[k]; if v == nil then return default end; return v end
function M.all() return _data end

--- Persist the in-memory store to disk. @return boolean ok, string|nil err
function M.save(path)
    path = path or _path; if not path then return false, "store: no path bound" end
    local f, e = io.open(path, "w"); if not f then return false, tostring(e) end
    f:write(_enc(_data)); f:close()
    return true
end

--- Load the store from disk (uses the framework JSON decoder). @return boolean ok, string|nil err
function M.load(path)
    path = path or _path; if not path then return false, "store: no path bound" end
    local f = io.open(path, "r"); if not f then return false, "store: no file yet" end
    local s = f:read("*a"); f:close()
    if not s or s == "" then return false, "store: empty file" end
    local ok, json = pcall(require, "modules.json")
    if not (ok and json and json.decode) then return false, "store: json decoder missing" end
    local pok, t = pcall(function() return json.decode(s) end)
    if pok and type(t) == "table" then _data = t; return true end
    return false, "store: decode failed"
end

return M
