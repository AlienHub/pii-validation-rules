-- ICAO Doc 9303 Part 3 §4.9 check digit (weights 7,3,1; A-Z = 10..35; '<' = 0).
--
-- This is a field-level function. It is NOT a national printed passport-number
-- validator and NOT a complete TD1/TD2/TD3 MRZ parser: callers must slice the
-- exact field (or the exact concatenation for composite check digits) according
-- to the document layout and pass it here. The optional-data "<" filler check
-- digit special case is layout-specific and must be handled by the caller.

local M = {}
M.id = "icao9303_check_digit"

local WEIGHTS = { 7, 3, 1 }

local function char_value(b)
  if b >= 48 and b <= 57 then return b - 48 end       -- 0-9
  if b >= 65 and b <= 90 then return b - 55 end       -- A-Z -> 10..35
  if b == 60 then return 0 end                         -- '<'
  return nil
end

-- check_digit(field): field is an MRZ field string (A-Z, 0-9, '<'), at least
-- one character. Returns the check digit as a 1-char string, or nil, reason.
function M.check_digit(field)
  if type(field) ~= "string" then return nil, "not_a_string" end
  if #field == 0 then return nil, "bad_length" end
  local total = 0
  for i = 1, #field do
    local v = char_value(string.byte(field, i))
    if v == nil then return nil, "bad_character" end
    total = total + v * WEIGHTS[((i - 1) % 3) + 1]
  end
  return string.char(48 + total % 10)
end

-- verify(field, digit): compares the computed check digit with `digit` (1-char string).
function M.verify(field, digit)
  if type(digit) ~= "string" or #digit ~= 1 or digit < "0" or digit > "9" then
    return false, "bad_check_character"
  end
  local expected, why = M.check_digit(field)
  if not expected then return false, why end
  if expected ~= digit then return false, "check_mismatch" end
  return true
end

-- verify_with_trailing_digit(s): convenience for "field followed by its check digit".
function M.verify_with_trailing_digit(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s < 2 then return false, "bad_length" end
  return M.verify(string.sub(s, 1, #s - 1), string.sub(s, #s))
end

return M
