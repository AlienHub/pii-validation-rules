-- Restricted regex-subset matcher for the rule patterns in rules/*.json.
--
-- IMPORTANT: this is NOT a PCRE2 engine and Lua patterns are NOT regexes.
-- The authoritative engine for every rule is PCRE2 (tests/pcre2/). This module
-- implements, byte-for-byte, only the small construct subset that the rule
-- patterns use, so that Lua callers can run the same full-string shape check
-- without a C binding. Anything outside the subset raises an error instead of
-- silently matching differently. CI differential-tests this matcher against
-- native PCRE2 on the whole fixture corpus (reports/lua-vs-pcre2-differential*).
--
-- Supported subset (see docs/REGEX-SUBSET.zh.md):
--   wrapper        \A(?: ... )\z                (mandatory, full-string anchoring)
--   alternation    a|b|c                        (inside the wrapper or a (?: ) group)
--   group          (?: ... )                    (non-capturing, no quantifier on groups)
--   class          [abc], [a-z], [0-9A-Z<]      (ASCII only, no negation, no escapes)
--   literal        A-Z a-z 0-9 < and escaped \+ \- \. \( \) \/ \<
--   quantifier     {n} or {n,m} on a class or literal (bounded; n,m <= 256)
-- Matching is on raw bytes: any byte >= 0x80 (i.e. any non-ASCII UTF-8 character,
-- full-width digits, zero-width characters, bidi controls) can never match.

local M = {}

local MAX_REPEAT = 256

local function perr(regex, pos, msg)
  error(string.format("unsupported_regex_construct: %s at offset %d in %q", msg, pos, regex), 0)
end

local function byteset_single(b)
  return { [b] = true }
end

-- parse a character class starting at '[' ; returns set, next position
local function parse_class(regex, pos)
  local set = {}
  local i = pos + 1
  local n = #regex
  if string.sub(regex, i, i) == "^" then perr(regex, i, "negated class not supported") end
  while true do
    if i > n then perr(regex, i, "unterminated class") end
    local c = string.sub(regex, i, i)
    if c == "]" then
      if next(set) == nil then perr(regex, i, "empty class") end
      return set, i + 1
    end
    if c == "\\" then perr(regex, i, "escape inside class not supported") end
    local b = string.byte(c)
    if b >= 0x80 then perr(regex, i, "non-ASCII in class") end
    if string.sub(regex, i + 1, i + 1) == "-" and string.sub(regex, i + 2, i + 2) ~= "]" and i + 2 <= n then
      local hi = string.byte(regex, i + 2)
      if hi >= 0x80 or hi < b then perr(regex, i, "bad range") end
      for x = b, hi do set[x] = true end
      i = i + 3
    else
      set[b] = true
      i = i + 1
    end
  end
end

local function parse_quant(regex, pos)
  -- returns min, max, nextpos ; pos may not be at '{'
  if string.sub(regex, pos, pos) ~= "{" then return 1, 1, pos end
  local a, b, e = string.match(regex, "^{(%d+),?(%d*)}()", pos)
  if not a then perr(regex, pos, "bad quantifier") end
  local body = string.match(regex, "^{[^}]*}", pos)
  local mn = tonumber(a)
  local mx
  if string.find(body, ",", 1, true) then
    if b == "" then perr(regex, pos, "open-ended quantifier {n,} not supported") end
    mx = tonumber(b)
  else
    mx = mn
  end
  if mx < mn or mx > MAX_REPEAT then perr(regex, pos, "quantifier out of bounds") end
  return mn, mx, e
end

local parse_alt

-- parse a sequence until '|' or ')' at depth 0; returns seq, nextpos
local function parse_seq(regex, pos)
  local seq = {}
  local n = #regex
  while pos <= n do
    local c = string.sub(regex, pos, pos)
    if c == "|" or c == ")" then break end
    local node
    if c == "(" then
      if string.sub(regex, pos, pos + 2) ~= "(?:" then perr(regex, pos, "only (?: ) groups supported") end
      local alts, np = parse_alt(regex, pos + 3)
      if string.sub(regex, np, np) ~= ")" then perr(regex, np, "expected )") end
      pos = np + 1
      if string.sub(regex, pos, pos) == "{" or string.sub(regex, pos, pos) == "?" or string.sub(regex, pos, pos) == "*" or string.sub(regex, pos, pos) == "+" then
        perr(regex, pos, "quantifier on group not supported")
      end
      node = { kind = "group", alts = alts }
    elseif c == "[" then
      local set, np = parse_class(regex, pos)
      local mn, mx, nq = parse_quant(regex, np)
      node = { kind = "set", set = set, min = mn, max = mx }
      pos = nq
    elseif c == "\\" then
      local e = string.sub(regex, pos + 1, pos + 1)
      if not string.find("+-.()/<", e, 1, true) or e == "" then
        perr(regex, pos, "escape \\" .. e .. " not supported (use explicit [0-9] etc.)")
      end
      local mn, mx, nq = parse_quant(regex, pos + 2)
      node = { kind = "set", set = byteset_single(string.byte(e)), min = mn, max = mx }
      pos = nq
    elseif string.find(c, "^[A-Za-z0-9<]$") then
      local mn, mx, nq = parse_quant(regex, pos + 1)
      node = { kind = "set", set = byteset_single(string.byte(c)), min = mn, max = mx }
      pos = nq
    else
      perr(regex, pos, "metacharacter '" .. c .. "' not supported")
    end
    seq[#seq + 1] = node
  end
  return seq, pos
end

parse_alt = function(regex, pos)
  local alts = {}
  while true do
    local seq, np = parse_seq(regex, pos)
    alts[#alts + 1] = seq
    if string.sub(regex, np, np) == "|" then
      pos = np + 1
    else
      return alts, np
    end
  end
end

local function match_seq(seq, i, s, pos, k)
  if i > #seq then return k(pos) end
  local node = seq[i]
  if node.kind == "group" then
    for _, alt in ipairs(node.alts) do
      local ok = match_seq(alt, 1, s, pos, function(p)
        return match_seq(seq, i + 1, s, p, k)
      end)
      if ok then return true end
    end
    return false
  end
  local set, len = node.set, #s
  local n = 0
  while n < node.max and pos + n <= len and set[string.byte(s, pos + n)] do
    n = n + 1
  end
  if n < node.min then return false end
  for cnt = n, node.min, -1 do
    if match_seq(seq, i + 1, s, pos + cnt, k) then return true end
  end
  return false
end

local Compiled = {}
Compiled.__index = Compiled

-- Full-string match on raw bytes. Returns true/false. Never returns captures.
function Compiled:fullmatch(s)
  if type(s) ~= "string" then return false end
  local len = #s
  if len > self.max_len or len < self.min_len then return false end
  local root = { { kind = "group", alts = self.alts } }
  return match_seq(root, 1, s, 1, function(p) return p == len + 1 end)
end

local function seq_bounds(seq)
  local mn, mx = 0, 0
  for _, node in ipairs(seq) do
    if node.kind == "group" then
      local gmn, gmx = math.huge, 0
      for _, alt in ipairs(node.alts) do
        local a, b = seq_bounds(alt)
        if a < gmn then gmn = a end
        if b > gmx then gmx = b end
      end
      mn, mx = mn + gmn, mx + gmx
    else
      mn, mx = mn + node.min, mx + node.max
    end
  end
  return mn, mx
end

local cache = {}

-- compile(regex) -> Compiled ; raises on unsupported constructs.
function M.compile(regex)
  if type(regex) ~= "string" then error("syntax.compile expects a string", 2) end
  local hit = cache[regex]
  if hit then return hit end
  local prefix, suffix = "\\A(?:", ")\\z"
  if string.sub(regex, 1, #prefix) ~= prefix or string.sub(regex, -#suffix) ~= suffix then
    perr(regex, 1, "pattern must be wrapped as \\A(?:body)\\z")
  end
  local body = string.sub(regex, #prefix + 1, #regex - #suffix)
  local alts, np = parse_alt(body, 1)
  if np <= #body then perr(body, np, "unbalanced )") end
  local mn, mx = seq_bounds({ { kind = "group", alts = alts } })
  local obj = setmetatable({ regex = regex, alts = alts, min_len = mn, max_len = mx }, Compiled)
  cache[regex] = obj
  return obj
end

-- Convenience: fullmatch(regex, s) -> boolean
function M.fullmatch(regex, s)
  return M.compile(regex):fullmatch(s)
end

-- Returns (min_len, max_len) of strings the pattern can accept.
function M.length_bounds(regex)
  local c = M.compile(regex)
  return c.min_len, c.max_len
end

M.engine_description = "pii.syntax restricted-subset byte matcher (not PCRE2); authoritative engine is PCRE2"

return M
