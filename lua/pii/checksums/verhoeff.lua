-- Verhoeff dihedral-group (D5) check digit, as used by Aadhaar.
-- Tables are the standard published multiplication (d), permutation (p) and
-- inverse (inv) tables; mathematical indices are 0-based and are converted to
-- Lua's 1-based tables explicitly (+1) at every access.
-- Original implementation written from the algorithm description; no code copied.

local util = require("pii.checksums.util")

local M = {}
M.id = "verhoeff"

local D = {
  { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
  { 1, 2, 3, 4, 0, 6, 7, 8, 9, 5 },
  { 2, 3, 4, 0, 1, 7, 8, 9, 5, 6 },
  { 3, 4, 0, 1, 2, 8, 9, 5, 6, 7 },
  { 4, 0, 1, 2, 3, 9, 5, 6, 7, 8 },
  { 5, 9, 8, 7, 6, 0, 4, 3, 2, 1 },
  { 6, 5, 9, 8, 7, 1, 0, 4, 3, 2 },
  { 7, 6, 5, 9, 8, 2, 1, 0, 4, 3 },
  { 8, 7, 6, 5, 9, 3, 2, 1, 0, 4 },
  { 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 },
}

local P = {
  { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
  { 1, 5, 7, 6, 2, 8, 3, 0, 9, 4 },
  { 5, 8, 0, 3, 7, 9, 6, 1, 4, 2 },
  { 8, 9, 1, 6, 0, 4, 3, 5, 2, 7 },
  { 9, 4, 5, 3, 1, 2, 6, 8, 7, 0 },
  { 4, 2, 8, 6, 5, 7, 3, 9, 0, 1 },
  { 2, 7, 9, 3, 8, 0, 6, 4, 1, 5 },
  { 7, 0, 4, 6, 9, 1, 3, 2, 5, 8 },
}

local INV = { 0, 4, 3, 2, 1, 5, 6, 7, 8, 9 }

-- d(c, x) with 0-based mathematical arguments
local function dmul(c, x) return D[c + 1][x + 1] end
local function perm(i, x) return P[(i % 8) + 1][x + 1] end

-- verify(s): full number, check digit last. c must end at 0.
function M.verify(s)
  local d, why = util.digits(s)
  if not d then return false, why end
  if #d < 2 then return false, "bad_length" end
  local c = 0
  local pos = 0 -- 0-based position counted from the right, check digit is position 0
  for i = #d, 1, -1 do
    c = dmul(c, perm(pos, d[i]))
    pos = pos + 1
  end
  if c ~= 0 then return false, "check_mismatch" end
  return true
end

-- check_digit(body): generation uses positions shifted by one (the future
-- check digit occupies position 0) and the inverse table; verify() is then
-- used as an independent self-check before returning.
function M.check_digit(body)
  local d, why = util.digits(body)
  if not d then return nil, why end
  local c = 0
  local pos = 1
  for i = #d, 1, -1 do
    c = dmul(c, perm(pos, d[i]))
    pos = pos + 1
  end
  local ch = util.digit_char(INV[c + 1])
  if not M.verify(body .. ch) then return nil, "internal_inconsistency" end
  return ch
end

return M
