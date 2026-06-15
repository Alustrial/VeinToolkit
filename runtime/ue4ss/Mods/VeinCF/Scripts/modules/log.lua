------------------------------------------------------------
-- VeinCF :: log
-- Structured logging with levels, mod context, and buffered
-- error collection for the post-load summary.
--
-- Require as: require("modules.log")
------------------------------------------------------------
local M = {}

M.LEVEL = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 }
local NAMES = { [0]="DEBUG","INFO","WARN","ERROR","FATAL" }

local min_level = M.LEVEL.INFO
local errors     = {}   -- collected { mod_id, message } for summary
local warnings   = {}

function M.set_level(lvl) min_level = lvl end

local function emit(level, mod_id, fmt, ...)
    if level < min_level then return end
    local tag  = NAMES[level] or "???"
    local who  = mod_id and ("["..mod_id.."] ") or ""
    local msg  = string.format(fmt, ...)
    local line = string.format("[VeinCF/%s] %s%s", tag, who, msg)
    print(line)   -- goes to UE4SS console + log file

    if level >= M.LEVEL.ERROR then
        errors[#errors+1] = { mod_id = mod_id, message = msg }
    elseif level == M.LEVEL.WARN then
        warnings[#warnings+1] = { mod_id = mod_id, message = msg }
    end
end

function M.debug(mod_id, fmt, ...) emit(M.LEVEL.DEBUG, mod_id, fmt, ...) end
function M.info (mod_id, fmt, ...) emit(M.LEVEL.INFO,  mod_id, fmt, ...) end
function M.warn (mod_id, fmt, ...) emit(M.LEVEL.WARN,  mod_id, fmt, ...) end
function M.error(mod_id, fmt, ...) emit(M.LEVEL.ERROR, mod_id, fmt, ...) end
function M.fatal(mod_id, fmt, ...) emit(M.LEVEL.FATAL, mod_id, fmt, ...) end

function M.get_errors()   return errors   end
function M.get_warnings() return warnings end

function M.print_summary()
    print("")
    print("========================================")
    print("  VeinCF Load Summary")
    print("========================================")
    if #errors == 0 and #warnings == 0 then
        print("  All mods loaded successfully.")
    end
    if #warnings > 0 then
        print(string.format("  Warnings: %d", #warnings))
        for _, w in ipairs(warnings) do
            local who = w.mod_id and ("["..w.mod_id.."] ") or ""
            print("    ! " .. who .. w.message)
        end
    end
    if #errors > 0 then
        print(string.format("  Errors: %d", #errors))
        for _, e in ipairs(errors) do
            local who = e.mod_id and ("["..e.mod_id.."] ") or ""
            print("    X " .. who .. e.message)
        end
    end
    print("========================================")
    print("")
end

function M.reset()
    errors   = {}
    warnings = {}
end

return M
