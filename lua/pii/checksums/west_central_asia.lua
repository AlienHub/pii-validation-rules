-- West / Central Asia checksum algorithms:
--   tr_tckn            土耳其 T.C. Kimlik No (reconstructed, opt-in)
--   tr_vkn             土耳其 Vergi Kimlik No (reconstructed, opt-in)
--   ir_national_mod11  伊朗 کد ملی 10 位国民号 (reconstructed, opt-in)
--   kz_iin             哈萨克斯坦 IIN 两轮 MOD 11 (official)
-- Pure arithmetic; policy gating lives in pii.policies.

local util = require("pii.checksums.util")

local M = {}

-- ------------------------------------------------------------------ TR TCKN
local tckn = { id = "tr_tckn" }

-- complete(body9) -> 11-digit string with d10, d11 appended
function tckn.complete(body9)
  local d, why = util.digits(body9, 9)
  if not d then return nil, why end
  if d[1] == 0 then return nil, "leading_zero_not_allowed" end
  local odd = d[1] + d[3] + d[5] + d[7] + d[9]
  local even = d[2] + d[4] + d[6] + d[8]
  local d10 = util.nmod(7 * odd - even, 10)
  local sum10 = 0
  for i = 1, 9 do sum10 = sum10 + d[i] end
  local d11 = (sum10 + d10) % 10
  return body9 .. util.digit_char(d10) .. util.digit_char(d11)
end

function tckn.verify(s)
  local d, why = util.digits(s, 11)
  if not d then return false, why end
  if d[1] == 0 then return false, "leading_zero_not_allowed" end
  local odd = d[1] + d[3] + d[5] + d[7] + d[9]
  local even = d[2] + d[4] + d[6] + d[8]
  if d[10] ~= util.nmod(7 * odd - even, 10) then return false, "check_mismatch" end
  local sum10 = 0
  for i = 1, 10 do sum10 = sum10 + d[i] end
  if d[11] ~= sum10 % 10 then return false, "check_mismatch" end
  return true
end
M.tr_tckn = tckn

-- ------------------------------------------------------------------ TR VKN
local vkn = { id = "tr_vkn" }

local POW2 = { [1] = 2, [2] = 4, [3] = 8, [4] = 16, [5] = 32, [6] = 64, [7] = 128, [8] = 256, [9] = 512 }

function vkn.check_digit(body9)
  local d, why = util.digits(body9, 9)
  if not d then return nil, why end
  local total = 0
  for i = 1, 9 do
    local a = (d[i] + 10 - i) % 10
    if a ~= 0 then
      local b = (a * POW2[10 - i]) % 9
      if b == 0 then b = 9 end
      total = total + b
    end
  end
  return util.digit_char((10 - total % 10) % 10)
end

function vkn.verify(s)
  local d, why = util.digits(s, 10)
  if not d then return false, why end
  local expected = vkn.check_digit(string.sub(s, 1, 9))
  if expected ~= string.sub(s, 10) then return false, "check_mismatch" end
  return true
end
M.tr_vkn = vkn

-- ------------------------------------------------------------------ IR national code
local IR_W = { 10, 9, 8, 7, 6, 5, 4, 3, 2 }
local ir = { id = "ir_national_mod11" }

function ir.check_digit(body9)
  local d, why = util.digits(body9, 9)
  if not d then return nil, why end
  local r = util.weighted_sum(d, IR_W) % 11
  if r < 2 then return util.digit_char(r) end
  return util.digit_char(11 - r)
end

-- Pure arithmetic. The "all ten digits identical" rejection is a separate
-- anti-placeholder policy exposed as is_repeated_digits(), not part of verify().
function ir.verify(s)
  local d, why = util.digits(s, 10)
  if not d then return false, why end
  local expected = ir.check_digit(string.sub(s, 1, 9))
  if expected ~= string.sub(s, 10) then return false, "check_mismatch" end
  return true
end

function ir.is_repeated_digits(s)
  if type(s) ~= "string" or #s == 0 then return false end
  local first = string.sub(s, 1, 1)
  return string.rep(first, #s) == s
end
M.ir_national_mod11 = ir

-- ------------------------------------------------------------------ KZ IIN
local KZ_W1 = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local KZ_W2 = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2 }
local kz = { id = "kz_iin" }

-- check_digit(body11) -> digit string, or nil, "no_valid_check_digit" when both
-- rounds give 10 (such bodies are never issued), or nil, reason.
function kz.check_digit(body11)
  local d, why = util.digits(body11, 11)
  if not d then return nil, why end
  local r = util.weighted_sum(d, KZ_W1) % 11
  if r == 10 then
    r = util.weighted_sum(d, KZ_W2) % 11
    if r == 10 then return nil, "no_valid_check_digit" end
  end
  return util.digit_char(r)
end

function kz.verify(s)
  local d, why = util.digits(s, 12)
  if not d then return false, why end
  local expected, err = kz.check_digit(string.sub(s, 1, 11))
  if not expected then return false, err end
  if expected ~= string.sub(s, 12) then return false, "check_mismatch" end
  return true
end
M.kz_iin = kz

return M
