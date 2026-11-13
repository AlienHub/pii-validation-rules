-- Minimal JSON decoder/encoder (pure Lua 5.1 / 5.3 / 5.4 / LuaJIT).
-- Used to load rules/*.json and fixtures and to write test reports.
-- Scope: RFC 8259 documents produced by this repository. Not a general-purpose
-- streaming parser; numbers are decoded with tonumber, strings keep UTF-8 bytes.

local M = {}

local NULL = setmetatable({}, { __tostring = function() return "null" end })
M.null = NULL

local function decode_error(str, pos, msg)
  error(string.format("json decode error at byte %d: %s", pos, msg), 0)
end

local function skip_ws(str, pos)
  local _, e = string.find(str, "^[ \t\r\n]*", pos)
  return e + 1
end

local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  else
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
      0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
end

local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decode_string(str, pos)
  -- pos points at the opening quote
  local out = {}
  local i = pos + 1
  while true do
    local c = string.sub(str, i, i)
    if c == "" then decode_error(str, i, "unterminated string") end
    if c == '"' then
      return table.concat(out), i + 1
    elseif c == "\\" then
      local e = string.sub(str, i + 1, i + 1)
      if e == "u" then
        local hex = string.sub(str, i + 2, i + 5)
        if not string.match(hex, "^%x%x%x%x$") then decode_error(str, i, "bad \\u escape") end
        local cp = tonumber(hex, 16)
        i = i + 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local lo = string.sub(str, i, i + 5)
          local lohex = string.match(lo, "^\\u(%x%x%x%x)$")
          if lohex then
            local cp2 = tonumber(lohex, 16)
            if cp2 >= 0xDC00 and cp2 <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
              i = i + 6
            end
          end
        end
        out[#out + 1] = utf8_encode(cp)
      elseif ESC[e] then
        out[#out + 1] = ESC[e]
        i = i + 2
      else
        decode_error(str, i, "bad escape")
      end
    else
      -- copy a run of ordinary bytes at once
      local s, e = string.find(str, '^[^"\\]+', i)
      out[#out + 1] = string.sub(str, s, e)
      i = e + 1
    end
  end
end

local decode_value

local function decode_array(str, pos)
  local arr = {}
  local i = skip_ws(str, pos + 1)
  if string.sub(str, i, i) == "]" then return arr, i + 1 end
  while true do
    local v
    v, i = decode_value(str, i)
    arr[#arr + 1] = v
    i = skip_ws(str, i)
    local c = string.sub(str, i, i)
    if c == "," then
      i = skip_ws(str, i + 1)
    elseif c == "]" then
      return arr, i + 1
    else
      decode_error(str, i, "expected , or ] in array")
    end
  end
end

local function decode_object(str, pos)
  local obj = {}
  local i = skip_ws(str, pos + 1)
  if string.sub(str, i, i) == "}" then return obj, i + 1 end
  while true do
    if string.sub(str, i, i) ~= '"' then decode_error(str, i, "expected string key") end
    local k
    k, i = decode_string(str, i)
    i = skip_ws(str, i)
    if string.sub(str, i, i) ~= ":" then decode_error(str, i, "expected :") end
    i = skip_ws(str, i + 1)
    local v
    v, i = decode_value(str, i)
    obj[k] = v
    i = skip_ws(str, i)
    local c = string.sub(str, i, i)
    if c == "," then
      i = skip_ws(str, i + 1)
    elseif c == "}" then
      return obj, i + 1
    else
      decode_error(str, i, "expected , or } in object")
    end
  end
end

decode_value = function(str, pos)
  pos = skip_ws(str, pos)
  local c = string.sub(str, pos, pos)
  if c == "{" then return decode_object(str, pos) end
  if c == "[" then return decode_array(str, pos) end
  if c == '"' then return decode_string(str, pos) end
  if string.sub(str, pos, pos + 3) == "true" then return true, pos + 4 end
  if string.sub(str, pos, pos + 4) == "false" then return false, pos + 5 end
  if string.sub(str, pos, pos + 3) == "null" then return NULL, pos + 4 end
  local num = string.match(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
  if num and num ~= "" and num ~= "-" then
    local n = tonumber(num)
    if n == nil then decode_error(str, pos, "bad number") end
    return n, pos + #num
  end
  decode_error(str, pos, "unexpected character '" .. c .. "'")
end

function M.decode(str)
  if type(str) ~= "string" then error("json.decode expects a string", 2) end
  local v, pos = decode_value(str, 1)
  pos = skip_ws(str, pos)
  if pos <= #str then decode_error(str, pos, "trailing garbage") end
  return v
end

function M.decode_file(path)
  local f, err = io.open(path, "rb")
  if not f then error("cannot open " .. path .. ": " .. tostring(err), 2) end
  local s = f:read("*a")
  f:close()
  return M.decode(s)
end

-- ---------------------------------------------------------------- encoder

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  if n == 0 then return rawget(t, 1) ~= nil or getmetatable(t) == M.array_mt end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

M.array_mt = {}
function M.array(t) return setmetatable(t or {}, M.array_mt) end

local function encode_string(s)
  s = string.gsub(s, '[%c"\\]', function(ch)
    if ch == '"' then return '\\"' end
    if ch == "\\" then return "\\\\" end
    if ch == "\n" then return "\\n" end
    if ch == "\r" then return "\\r" end
    if ch == "\t" then return "\\t" end
    if ch == "\b" then return "\\b" end
    if ch == "\f" then return "\\f" end
    return string.format("\\u%04x", string.byte(ch))
  end)
  return '"' .. s .. '"'
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  return keys
end

local function encode_value(v, indent, level, out)
  local tv = type(v)
  if v == NULL or v == nil then
    out[#out + 1] = "null"
  elseif tv == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif math.floor(v) == v and math.abs(v) < 1e15 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif tv == "string" then
    out[#out + 1] = encode_string(v)
  elseif tv == "table" then
    local pad = indent and ("\n" .. string.rep(indent, level + 1)) or ""
    local padend = indent and ("\n" .. string.rep(indent, level)) or ""
    local sep = indent and "," or ","
    if is_array(v) then
      if #v == 0 then out[#out + 1] = "[]" return end
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = sep end
        out[#out + 1] = pad
        encode_value(v[i], indent, level + 1, out)
      end
      out[#out + 1] = padend .. "]"
    else
      local keys = sorted_keys(v)
      if #keys == 0 then out[#out + 1] = "{}" return end
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = sep end
        out[#out + 1] = pad .. encode_string(k) .. (indent and ": " or ":")
        encode_value(v[k], indent, level + 1, out)
      end
      out[#out + 1] = padend .. "}"
    end
  else
    out[#out + 1] = encode_string(tostring(v))
  end
end

-- encode(value, indent): indent is an optional string (e.g. "  ") for pretty output.
-- Object keys are emitted sorted so reports are deterministic across Lua versions.
function M.encode(v, indent)
  local out = {}
  encode_value(v, indent, 0, out)
  return table.concat(out)
end

return M
