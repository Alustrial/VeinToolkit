------------------------------------------------------------
-- VeinCF :: json
-- Minimal, dependency-free JSON decoder.
-- Only decodes (we never need to write manifests at runtime).
-- Handles: objects, arrays, strings, numbers, bools, null.
--
-- Require as: require("modules.json")
------------------------------------------------------------
local M = {}

local function skip_ws(s, i)
    return s:match("^%s*()", i)
end

local esc_map = { ['"']='"', ['\\'  ]='\\', ['/'  ]='/',
                  ['b']='\b', ['f']='\f', ['n']='\n',
                  ['r']='\r', ['t']='\t' }

local function decode_string(s, i)
    i = i + 1 -- skip opening "
    local buf = {}
    while i <= #s do
        local c = s:sub(i,i)
        if c == '"' then
            return table.concat(buf), i + 1
        elseif c == '\\' then
            i = i + 1
            local e = s:sub(i,i)
            if e == 'u' then
                local hex = s:sub(i+1, i+4)
                local cp  = tonumber(hex, 16)
                if cp and cp < 0x80 then
                    buf[#buf+1] = string.char(cp)
                elseif cp and cp < 0x800 then
                    buf[#buf+1] = string.char(0xC0 + math.floor(cp/64),
                                               0x80 + cp%64)
                elseif cp then
                    buf[#buf+1] = string.char(0xE0 + math.floor(cp/4096),
                                               0x80 + math.floor(cp/64)%64,
                                               0x80 + cp%64)
                end
                i = i + 5
            else
                buf[#buf+1] = esc_map[e] or e
                i = i + 1
            end
        else
            buf[#buf+1] = c
            i = i + 1
        end
    end
    error("JSON: unterminated string")
end

local decode_value  -- forward decl

local function decode_object(s, i)
    local obj = {}
    i = skip_ws(s, i + 1) -- skip {
    if s:sub(i,i) == '}' then return obj, i + 1 end
    while true do
        i = skip_ws(s, i)
        if s:sub(i,i) ~= '"' then error("JSON: expected string key at "..i) end
        local key
        key, i = decode_string(s, i)
        i = skip_ws(s, i)
        if s:sub(i,i) ~= ':' then error("JSON: expected ':' at "..i) end
        i = skip_ws(s, i + 1)
        local val
        val, i = decode_value(s, i)
        obj[key] = val
        i = skip_ws(s, i)
        local c = s:sub(i,i)
        if c == '}' then return obj, i + 1 end
        if c ~= ',' then error("JSON: expected ',' or '}' at "..i) end
        i = i + 1
    end
end

local function decode_array(s, i)
    local arr = {}
    i = skip_ws(s, i + 1) -- skip [
    if s:sub(i,i) == ']' then return arr, i + 1 end
    while true do
        i = skip_ws(s, i)
        local val
        val, i = decode_value(s, i)
        arr[#arr+1] = val
        i = skip_ws(s, i)
        local c = s:sub(i,i)
        if c == ']' then return arr, i + 1 end
        if c ~= ',' then error("JSON: expected ',' or ']' at "..i) end
        i = i + 1
    end
end

function decode_value(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i,i)
    if c == '"' then return decode_string(s, i)
    elseif c == '{' then return decode_object(s, i)
    elseif c == '[' then return decode_array(s, i)
    elseif c == 't' then
        if s:sub(i, i+3) == "true" then return true, i+4 end
    elseif c == 'f' then
        if s:sub(i, i+4) == "false" then return false, i+5 end
    elseif c == 'n' then
        if s:sub(i, i+3) == "null" then return nil, i+4 end
    else
        -- number
        local num_str = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if num_str then
            return tonumber(num_str), i + #num_str
        end
    end
    error("JSON: unexpected character '"..c.."' at position "..i)
end

function M.decode(s)
    if type(s) ~= "string" then error("JSON: decode expects a string") end
    local val, i = decode_value(s, 1)
    return val
end

return M
