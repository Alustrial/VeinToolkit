------------------------------------------------------------
-- VeinCF :: semver
-- Parse semantic versions and evaluate range constraints.
--
-- Supports:
--   1.2.3              exact
--   1.2.3-beta.1       pre-release
--   >=1.2.0            minimum
--   <=1.2.0            maximum
--   >1.0.0             greater than
--   <2.0.0             less than
--   1.0.*              wildcard patch (any 1.0.x)
--   >=1.0.0 <2.0.0    compound (space = AND)
--
-- Require as: require("modules.semver")
------------------------------------------------------------
local M = {}

--- Parse "1.2.3" or "1.2.3-beta.1" into {major, minor, patch, pre_tag, pre_num}
function M.parse(s)
    if type(s) ~= "string" then return nil end
    -- Try with pre-release suffix first, then plain
    local major, minor, patch, pre = s:match("^(%d+)%.(%d+)%.(%d+)(%-[%w%.]+)$")
    if not major then
        major, minor, patch = s:match("^(%d+)%.(%d+)%.(%d+)$")
    end
    -- also accept wildcard "1.0.*"
    if not major then
        major, minor = s:match("^(%d+)%.(%d+)%.%*$")
        if major then
            return { major = tonumber(major), minor = tonumber(minor), patch = nil, wildcard = true }
        end
        return nil
    end
    local v = {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
    }
    if pre then
        -- strip leading -
        pre = pre:sub(2)
        local tag, num = pre:match("^(%a+)%.(%d+)$")
        if tag then
            v.pre_tag = tag
            v.pre_num = tonumber(num)
        else
            v.pre_tag = pre
            v.pre_num = 0
        end
    end
    return v
end

--- Compare two parsed versions. Returns -1, 0, or 1.
--- Pre-release < release (1.0.0-beta.1 < 1.0.0).
function M.compare(a, b)
    if a.major ~= b.major then return a.major < b.major and -1 or 1 end
    if a.minor ~= b.minor then return a.minor < b.minor and -1 or 1 end
    if (a.patch or 0) ~= (b.patch or 0) then return (a.patch or 0) < (b.patch or 0) and -1 or 1 end
    -- pre-release ordering
    local a_pre = a.pre_tag ~= nil
    local b_pre = b.pre_tag ~= nil
    if a_pre and not b_pre then return -1 end  -- pre < release
    if not a_pre and b_pre then return  1 end
    if a_pre and b_pre then
        if a.pre_tag ~= b.pre_tag then return a.pre_tag < b.pre_tag and -1 or 1 end
        if a.pre_num ~= b.pre_num then return a.pre_num < b.pre_num and -1 or 1 end
    end
    return 0
end

--- Evaluate a single constraint like ">=1.2.0" against a parsed version.
local function eval_one(constraint_str, ver)
    constraint_str = constraint_str:match("^%s*(.-)%s*$") -- trim
    local op, raw = constraint_str:match("^([><=]+)(.+)$")
    if not op then
        -- exact match or wildcard
        raw = constraint_str
        op  = "=="
    end
    local target = M.parse(raw)
    if not target then return false, "invalid version in constraint: "..constraint_str end

    -- wildcard: 1.0.* matches any 1.0.x
    if target.wildcard then
        return ver.major == target.major and ver.minor == target.minor
    end

    local cmp = M.compare(ver, target)
    if op == ">=" then return cmp >= 0
    elseif op == "<=" then return cmp <= 0
    elseif op == ">"  then return cmp >  0
    elseif op == "<"  then return cmp <  0
    elseif op == "==" then return cmp == 0
    else return false, "unknown operator: "..op end
end

--- Evaluate a full range string (space-separated AND of constraints).
--- Returns true/false, optional error string.
function M.satisfies(version_str, range_str)
    local ver = M.parse(version_str)
    if not ver then return false, "cannot parse version: "..tostring(version_str) end

    for part in range_str:gmatch("[^%s]+") do
        local ok, err = eval_one(part, ver)
        if not ok then return false, err or (version_str.." does not satisfy "..part) end
    end
    return true
end

--- Pretty-print a parsed version back to string.
function M.tostring(v)
    if not v then return "???" end
    local s = string.format("%d.%d.%d", v.major, v.minor, v.patch or 0)
    if v.pre_tag then s = s .. "-" .. v.pre_tag .. "." .. v.pre_num end
    return s
end

return M
