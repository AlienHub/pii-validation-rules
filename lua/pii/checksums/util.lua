-- Shared byte-level helpers for the checksum modules.
-- All functions operate on ASCII bytes only. Inputs are never converted with
-- tonumber() as a whole, so leading zeros are preserved and large identifiers
-- never pass through floating point.

local M = {}

local B0, B9, BA, BZ = string.byte("0"), string.byte("9"), string.byte("A"), string.byte("Z")

-- Returns an array of digit values if s is a string of exactly n ASCII digits
-- (any n when n is nil), otherwise nil plus a reason code.
function M.digits(s, n)
  if type(s) ~= "string" then return nil, "not_a_string" end
  if n and #s ~= n then return nil, "bad_length" end
  if #s == 0 then return nil, "bad_length" end
  local out = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    if b < B0 or b > B9 then return nil, "bad_character" end
    out[i] = b - B0
  end
  return out
end

-- Value of an ASCII uppercase letter A=10..Z=35, or nil.
function M.letter_value(b)
  if b >= BA and b <= BZ then return b - BA + 10 end
  return nil
end

function M.is_digit_byte(b)
  return b >= B0 and b <= B9
end

function M.is_upper_byte(b)
  return b >= BA and b <= BZ
end

-- Weighted sum of digit array d[1..#w] with weights w (1-based arrays).
function M.weighted_sum(d, w, offset)
  offset = offset or 0
  local s = 0
  for i = 1, #w do
    s = s + d[i + offset] * w[i]
  end
  return s
end

-- Non-negative modulo (Lua's % already yields a non-negative result for a
-- positive divisor, but the intent is made explicit for readers coming from C/JS).
function M.nmod(x, m)
  return ((x % m) + m) % m
end

-- Digit character for a value 0..9.
function M.digit_char(v)
  return string.char(B0 + v)
end

return M
