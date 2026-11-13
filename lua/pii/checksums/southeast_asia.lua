-- Southeast Asia checksum algorithms:
--   th_mod11                  泰国 13 位公民身份号码 / 税号 (official structure, secondary formula)
--   sg_nric_fin_reconstructed 新加坡 NRIC/FIN 校验字母 (public reconstruction, NOT an ICA algorithm;
--                             M-series table disputed -> experimental)
-- Pure arithmetic; policy gating (opt-in / experimental) lives in pii.policies.

local util = require("pii.checksums.util")

local M = {}

-- ------------------------------------------------------------------ TH
local TH_W = { 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2 }
local th = { id = "th_mod11" }

function th.check_digit(body12)
  local d, why = util.digits(body12, 12)
  if not d then return nil, why end
  local s = util.weighted_sum(d, TH_W)
  return util.digit_char((11 - s % 11) % 10)
end

function th.verify(s)
  local d, why = util.digits(s, 13)
  if not d then return false, why end
  local expected = th.check_digit(string.sub(s, 1, 12))
  if expected ~= string.sub(s, 13) then return false, "check_mismatch" end
  return true
end
M.th_mod11 = th

-- ------------------------------------------------------------------ SG
local SG_W = { 2, 7, 6, 5, 4, 3, 2 }
local SG_OFFSET = { S = 0, T = 4, F = 0, G = 4, M = 3 }
local SG_TABLE = {
  S = "JZIHGFEDCBA", T = "JZIHGFEDCBA",
  F = "XWUTRQPNMLK", G = "XWUTRQPNMLK",
  M = "XWUTRQPNJLK", -- reconstruction with known third-party disagreement
}
local sg = { id = "sg_nric_fin_reconstructed", offsets = SG_OFFSET, tables = SG_TABLE }

-- series_of(s) -> "S","T","F","G","M" or nil
function sg.series_of(s)
  if type(s) ~= "string" or #s < 1 then return nil end
  local p = string.sub(s, 1, 1)
  if SG_TABLE[p] then return p end
  return nil
end

function sg.is_experimental_series(prefix)
  return prefix == "M"
end

-- check_letter(prefix, digits7)
function sg.check_letter(prefix, digits7)
  local tbl = SG_TABLE[prefix]
  if not tbl then return nil, "bad_character" end
  local d, why = util.digits(digits7, 7)
  if not d then return nil, why end
  local r = (util.weighted_sum(d, SG_W) + SG_OFFSET[prefix]) % 11
  return string.sub(tbl, r + 1, r + 1)
end

function sg.verify(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s ~= 9 then return false, "bad_length" end
  local prefix = string.sub(s, 1, 1)
  if not SG_TABLE[prefix] then return false, "bad_character" end
  local last = string.sub(s, 9)
  if not util.is_upper_byte(string.byte(last)) then return false, "bad_character" end
  local expected, why = sg.check_letter(prefix, string.sub(s, 2, 8))
  if not expected then return false, why end
  if expected ~= last then return false, "check_mismatch" end
  return true
end
M.sg_nric_fin_reconstructed = sg

return M
