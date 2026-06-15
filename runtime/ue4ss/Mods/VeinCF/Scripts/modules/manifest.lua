------------------------------------------------------------
-- VeinCF :: manifest
-- Discover mod folders, parse manifest.json, validate fields.
--
-- Require as: require("modules.manifest")
------------------------------------------------------------
local json   = require("modules.json")
local semver = require("modules.semver")
local log    = require("modules.log")

local M = {}

------------------------------------------------------------
-- File helpers
------------------------------------------------------------
local SEP = package.config:sub(1,1)  -- \ on Windows

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

--- List immediate subdirectories of `root`.
local function list_subdirs(root)
    local dirs = {}
    local cmd
    if SEP == '\\' then
        cmd = 'dir /b /ad "' .. root .. '" 2>nul'
    else
        cmd = 'ls -1d "' .. root .. '"/*/ 2>/dev/null'
    end
    local pipe = io.popen(cmd)
    if not pipe then return dirs end
    for line in pipe:lines() do
        local name = line:match("([^/\\]+)[/\\]?$") or line
        if name ~= "" then dirs[#dirs+1] = name end
    end
    pipe:close()
    return dirs
end

------------------------------------------------------------
-- Validation
------------------------------------------------------------
local REQUIRED_FIELDS = { "manifest_version", "id", "name", "version", "author" }
local ID_PATTERN      = "^[a-z][a-z0-9_]+$"

local function validate(m, folder)
    local errs = {}
    local function fail(fmt, ...) errs[#errs+1] = string.format(fmt, ...) end

    -- required fields
    for _, key in ipairs(REQUIRED_FIELDS) do
        if m[key] == nil then fail("missing required field '%s'", key) end
    end
    if #errs > 0 then return errs end  -- can't continue without basics

    -- manifest_version
    if m.manifest_version ~= 1 then
        fail("unsupported manifest_version %s (expected 1)", tostring(m.manifest_version))
    end

    -- id format
    if type(m.id) ~= "string" or not m.id:match(ID_PATTERN) then
        fail("id must be lowercase alphanumeric+underscore, 2-64 chars (got '%s')", tostring(m.id))
    end

    -- id must match folder name
    if m.id ~= folder then
        fail("id '%s' does not match folder name '%s' — they must be identical", m.id, folder)
    end

    -- version parseable
    if not semver.parse(m.version) then
        fail("version '%s' is not valid semver", tostring(m.version))
    end

    -- author
    if type(m.author) ~= "string" and type(m.author) ~= "table" then
        fail("author must be a string or {name, url} object")
    elseif type(m.author) == "table" and type(m.author.name) ~= "string" then
        fail("author.name is required when author is an object")
    end

    -- entrypoints: check files exist
    if m.entrypoints and type(m.entrypoints) == "table" then
        for phase, path in pairs(m.entrypoints) do
            if type(path) == "string" then
                local full = m._root .. SEP .. path
                if not read_file(full) then
                    fail("entrypoint '%s' references '%s' which does not exist", phase, path)
                end
            end
        end
    end

    -- recipes (optional): declared cooked recipes to register from paks.
    -- Accepts the friendly form (asset/makes/needs/tab/bench) OR the explicit form
    -- (package/results/ingredient_sets/recipe_type/workbench_type).
    if m.recipes ~= nil then
        if type(m.recipes) ~= "table" then
            fail("recipes must be an array of recipe objects")
        else
            for i, r in ipairs(m.recipes) do
                if type(r) ~= "table" then
                    fail("recipes[%d] must be an object", i)
                else
                    local pkg = r.asset or r.package
                    if type(pkg) ~= "string" or not pkg:match("^/Game/") then
                        fail("recipes[%d].asset must be a '/Game/...' content path", i)
                    end
                    if r.makes ~= nil and type(r.makes) ~= "string" and type(r.makes) ~= "table" then
                        fail("recipes[%d].makes must be an item path or array of item paths", i)
                    end
                    if r.needs ~= nil and type(r.needs) ~= "table" then
                        fail("recipes[%d].needs must be an array of item paths (= all required)", i)
                    end
                    if r.results ~= nil and type(r.results) ~= "table" then
                        fail("recipes[%d].results must be an array of item paths", i)
                    end
                    if r.ingredient_sets ~= nil and type(r.ingredient_sets) ~= "table" then
                        fail("recipes[%d].ingredient_sets must be an array of arrays of item paths", i)
                    end
                end
            end
        end
    end

    -- config_schema types
    if m.config_schema and type(m.config_schema) == "table" then
        local valid_types = { bool=1, int=1, float=1, string=1, enum=1 }
        for key, def in pairs(m.config_schema) do
            if type(def) == "table" then
                if not valid_types[def.type] then
                    fail("config '%s' has invalid type '%s'", key, tostring(def.type))
                end
                if def.default == nil then
                    fail("config '%s' missing default value", key)
                end
                if def.type == "enum" and (not def.options or #def.options == 0) then
                    fail("config '%s' is enum but has no options", key)
                end
            end
        end
    end

    return errs
end

------------------------------------------------------------
-- Discovery & loading
------------------------------------------------------------

--- Scan `mods_dir` for subdirectories containing manifest.json.
--- Returns { [id] = manifest_table, ... } and a list of load errors.
function M.discover(mods_dir)
    local manifests = {}
    local folders   = list_subdirs(mods_dir)

    log.info(nil, "Scanning %d mod folders in %s", #folders, mods_dir)

    for _, folder in ipairs(folders) do
        local mod_root = mods_dir .. SEP .. folder
        local mf_path  = mod_root .. SEP .. "manifest.json"
        local raw      = read_file(mf_path)

        if not raw then
            log.debug(nil, "Skipping '%s' — no manifest.json", folder)
            goto continue
        end

        -- parse JSON
        local ok, m = pcall(json.decode, raw)
        if not ok then
            log.error(nil, "Failed to parse %s: %s", mf_path, tostring(m))
            goto continue
        end

        -- attach internal metadata
        m._root   = mod_root
        m._folder = folder

        -- validate
        local errs = validate(m, folder)
        if #errs > 0 then
            for _, e in ipairs(errs) do
                log.error(m.id or folder, "%s", e)
            end
            goto continue
        end

        -- duplicate check
        if manifests[m.id] then
            log.error(m.id, "Duplicate mod ID — found in both '%s' and '%s'",
                      manifests[m.id]._folder, folder)
            goto continue
        end

        manifests[m.id] = m
        log.info(m.id, "Discovered v%s by %s",
                 m.version,
                 type(m.author)=="table" and m.author.name or tostring(m.author))

        ::continue::
    end

    return manifests
end

return M
