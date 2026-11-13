-- Luhn (ISO/IEC 7812-1 Annex B) mod-10 check digit.
-- Arithmetic consistency only: it is neither brand detection, card validity,
-- bank-account validation nor issuer verification. Field-level length/prefix
-- constraints are enforced by the rule, not here.

local util = require("pii.checksums.util")

local M = {}
M.id = "luhn"

-- verify(s): s is the full number including the trailing check digit.
-- Returns true, or false plus a reason code.
function M.verify(s)
  local d, why = util.digits(s)
  if not d then return false, why end
  if #d < 2 then return false, "bad_length" end
  local total = 0
  local double = false -- rightmost (check) digit has weight 1
  for i = #d, 1, -1 do
    local v = d[i]
    if double then
      v = v * 2
      if v > 9 then v = v - 9 end
    end
    total = total + v
    double = not double
  end
  if total % 10 ~= 0 then return false, "check_mismatch" end
  return true
end

-- check_digit(body): computes the digit that makes body..digit Luhn-valid.
-- Implemented by the closed-form formula, independent from verify's loop.
function M.check_digit(body)
  local d, why = util.digits(body)
  if not d then return nil, why end
  local total = 0
  local double = true -- the digit immediately left of the check digit is doubled
  for i = #d, 1, -1 do
    local v = d[i]
    if double then
      v = v * 2
      if v > 9 then v = v - 9 end
    end
    total = total + v
    double = not double
  end
  return util.digit_char((10 - total % 10) % 10)
end

return M
