-- East Asia checksum algorithms:
--   cn_resident_id_mod11_2  中国 公民身份号码 GB 11643-1999 (official)
--   cn_uscc_mod31           中国 统一社会信用代码 GB 32100-2015 (official)
--   jp_mynumber             日本 個人番号 (official, 総務省令 §5)
--   jp_corporate_number     日本 法人番号 (official, 財務省令 §2 + NTA worked example)
--   kr_rrn_legacy           韩国 住民登録番号 pre-2020-10 legacy formula (secondary; regime-gated)
--   tw_citizen_new_ui       台湾 国民身分证 / 新式统一证号 (official structure, secondary arithmetic)
--   hkid_mod11              香港 HKID (official structure, secondary arithmetic)
-- Every function returns true, or false plus a reason code. Pure arithmetic:
-- no date, region, issuance or policy decisions are made here.

local util = require("pii.checksums.util")

local M = {}

-- ------------------------------------------------------------------ CN resident ID
local CN_W = { 7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2 }
local CN_CHECK = "10X98765432" -- index = S mod 11 (0-based)

local cn_resident = { id = "cn_resident_id_mod11_2" }

function cn_resident.check_character(body17)
  local d, why = util.digits(body17, 17)
  if not d then return nil, why end
  local s = util.weighted_sum(d, CN_W)
  local idx = s % 11
  return string.sub(CN_CHECK, idx + 1, idx + 1)
end

function cn_resident.verify(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s ~= 18 then return false, "bad_length" end
  local last = string.sub(s, 18)
  if not (util.is_digit_byte(string.byte(last)) or last == "X") then return false, "bad_character" end
  local expected, why = cn_resident.check_character(string.sub(s, 1, 17))
  if not expected then return false, why end
  if expected ~= last then return false, "check_mismatch" end
  return true
end
M.cn_resident_id_mod11_2 = cn_resident

-- ------------------------------------------------------------------ CN USCC
local USCC_ALPHABET = "0123456789ABCDEFGHJKLMNPQRTUWXY"
local USCC_VALUE = {}
for i = 1, #USCC_ALPHABET do USCC_VALUE[string.byte(USCC_ALPHABET, i)] = i - 1 end
local USCC_W = { 1, 3, 9, 27, 19, 26, 16, 17, 20, 29, 25, 13, 8, 24, 10, 30, 28 }

local cn_uscc = { id = "cn_uscc_mod31", alphabet = USCC_ALPHABET }

function cn_uscc.check_character(body17)
  if type(body17) ~= "string" then return nil, "not_a_string" end
  if #body17 ~= 17 then return nil, "bad_length" end
  local s = 0
  for i = 1, 17 do
    local v = USCC_VALUE[string.byte(body17, i)]
    if v == nil then return nil, "bad_character" end
    s = s + v * USCC_W[i]
  end
  local idx = (31 - s % 31) % 31
  return string.sub(USCC_ALPHABET, idx + 1, idx + 1)
end

function cn_uscc.verify(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s ~= 18 then return false, "bad_length" end
  local last = string.sub(s, 18)
  if USCC_VALUE[string.byte(last)] == nil then return false, "bad_character" end
  local expected, why = cn_uscc.check_character(string.sub(s, 1, 17))
  if not expected then return false, why end
  if expected ~= last then return false, "check_mismatch" end
  return true
end
M.cn_uscc_mod31 = cn_uscc

-- ------------------------------------------------------------------ JP My Number
-- 総務省令 §5: P_n = n-th digit from the right of the 11 non-check digits,
-- Q_n = n+1 (1<=n<=6), n-5 (7<=n<=11); check = 11 - (ΣP_nQ_n mod 11), 0 when remainder <= 1.
local jp_my = { id = "jp_mynumber" }

function jp_my.check_digit(body11)
  local d, why = util.digits(body11, 11)
  if not d then return nil, why end
  local total = 0
  for n = 1, 11 do
    local p = d[12 - n]
    local q = (n <= 6) and (n + 1) or (n - 5)
    total = total + p * q
  end
  local r = total % 11
  if r <= 1 then return "0" end
  return util.digit_char(11 - r)
end

function jp_my.verify(s)
  local d, why = util.digits(s, 12)
  if not d then return false, why end
  local expected = jp_my.check_digit(string.sub(s, 1, 11))
  if expected ~= string.sub(s, 12) then return false, "check_mismatch" end
  return true
end
M.jp_mynumber = jp_my

-- ------------------------------------------------------------------ JP Corporate Number
-- 財務省令 §2: P_n = n-th digit from the right of the 12-digit base number,
-- Q_n = 1 (odd n) / 2 (even n); check = 9 - (ΣP_nQ_n mod 9). Check digit is the FIRST character.
local jp_corp = { id = "jp_corporate_number" }

function jp_corp.check_digit(base12)
  local d, why = util.digits(base12, 12)
  if not d then return nil, why end
  local total = 0
  for n = 1, 12 do
    local p = d[13 - n]
    total = total + p * ((n % 2 == 1) and 1 or 2)
  end
  return util.digit_char(9 - total % 9)
end

function jp_corp.verify(s)
  local d, why = util.digits(s, 13)
  if not d then return false, why end
  local expected = jp_corp.check_digit(string.sub(s, 2, 13))
  if expected ~= string.sub(s, 1, 1) then return false, "check_mismatch" end
  return true
end
M.jp_corporate_number = jp_corp

-- ------------------------------------------------------------------ KR RRN (legacy only)
local KR_W = { 2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5 }
local kr = { id = "kr_rrn_legacy" }

function kr.check_digit(body12)
  local d, why = util.digits(body12, 12)
  if not d then return nil, why end
  local s = util.weighted_sum(d, KR_W)
  return util.digit_char((11 - s % 11) % 10)
end

-- Pure arithmetic. Callers MUST only invoke this for explicitly declared
-- pre-2020-10 numbers; see pii.policies (regime gating lives there, not here).
function kr.verify(s)
  local d, why = util.digits(s, 13)
  if not d then return false, why end
  local expected = kr.check_digit(string.sub(s, 1, 12))
  if expected ~= string.sub(s, 13) then return false, "check_mismatch" end
  return true
end
M.kr_rrn_legacy = kr

-- ------------------------------------------------------------------ TW citizen / new UI
local TW_LETTER = {
  A = 10, B = 11, C = 12, D = 13, E = 14, F = 15, G = 16, H = 17, I = 34, J = 18, K = 19, L = 20, M = 21,
  N = 22, O = 35, P = 23, Q = 24, R = 25, S = 26, T = 27, U = 28, V = 29, W = 32, X = 30, Y = 31, Z = 33,
}
local TW_W = { 1, 9, 8, 7, 6, 5, 4, 3, 2, 1 } -- for the 10 values before the check digit; check weight 1
local tw = { id = "tw_citizen_new_ui", letter_values = TW_LETTER }

-- body = letter .. 8 digits (without check digit)
function tw.check_digit(body)
  if type(body) ~= "string" then return nil, "not_a_string" end
  if #body ~= 9 then return nil, "bad_length" end
  local lv = TW_LETTER[string.sub(body, 1, 1)]
  if not lv then return nil, "bad_character" end
  local d, why = util.digits(string.sub(body, 2, 9), 8)
  if not d then return nil, why end
  local seq = { math.floor(lv / 10), lv % 10 }
  for i = 1, 8 do seq[#seq + 1] = d[i] end
  local s = util.weighted_sum(seq, TW_W)
  return util.digit_char((10 - s % 10) % 10)
end

function tw.verify(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s ~= 10 then return false, "bad_length" end
  if not util.is_digit_byte(string.byte(s, 10)) then return false, "bad_character" end
  local expected, why = tw.check_digit(string.sub(s, 1, 9))
  if not expected then return false, why end
  if expected ~= string.sub(s, 10) then return false, "check_mismatch" end
  return true
end
M.tw_citizen_new_ui = tw

-- ------------------------------------------------------------------ HKID
local HK_W = { 9, 8, 7, 6, 5, 4, 3, 2 }
local hk = { id = "hkid_mod11" }

-- body = 1 or 2 uppercase letters .. 6 digits (no check character, no parentheses)
function hk.check_character(body)
  if type(body) ~= "string" then return nil, "not_a_string" end
  if #body ~= 7 and #body ~= 8 then return nil, "bad_length" end
  local nletters = #body - 6
  local seq = {}
  if nletters == 1 then seq[1] = 36 end -- leading blank counts as 36, not 0
  for i = 1, nletters do
    local v = util.letter_value(string.byte(body, i))
    if not v then return nil, "bad_character" end
    seq[#seq + 1] = v
  end
  local d, why = util.digits(string.sub(body, nletters + 1), 6)
  if not d then return nil, why end
  for i = 1, 6 do seq[#seq + 1] = d[i] end
  local s = util.weighted_sum(seq, HK_W)
  local v = (11 - s % 11) % 11
  if v == 10 then return "A" end
  return util.digit_char(v)
end

function hk.verify(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s ~= 8 and #s ~= 9 then return false, "bad_length" end
  local last = string.sub(s, #s)
  if not (util.is_digit_byte(string.byte(last)) or last == "A") then return false, "bad_character" end
  local expected, why = hk.check_character(string.sub(s, 1, #s - 1))
  if not expected then return false, why end
  if expected ~= last then return false, "check_mismatch" end
  return true
end
M.hkid_mod11 = hk

return M
