-- Registry of checksum algorithms keyed by the algorithm ids used in
-- rules/algorithms.json. Each entry exposes at least verify(value) -> bool, reason.
-- Nothing here decides whether an algorithm *should* run; see pii.policies.

local east = require("pii.checksums.east_asia")
local southeast = require("pii.checksums.southeast_asia")
local west = require("pii.checksums.west_central_asia")
local luhn = require("pii.checksums.luhn")
local verhoeff = require("pii.checksums.verhoeff")
local iban = require("pii.checksums.iban")
local icao = require("pii.checksums.icao9303")

local M = {}

M.luhn = luhn
M.verhoeff = verhoeff
M.iban = iban
M.icao9303 = icao
M.east_asia = east
M.southeast_asia = southeast
M.west_central_asia = west

M.by_id = {
  cn_resident_id_mod11_2 = east.cn_resident_id_mod11_2,
  cn_uscc_mod31 = east.cn_uscc_mod31,
  jp_mynumber = east.jp_mynumber,
  jp_corporate_number = east.jp_corporate_number,
  kr_rrn_legacy = east.kr_rrn_legacy,
  tw_citizen_new_ui = east.tw_citizen_new_ui,
  hkid_mod11 = east.hkid_mod11,
  th_mod11 = southeast.th_mod11,
  sg_nric_fin_reconstructed = southeast.sg_nric_fin_reconstructed,
  tr_tckn = west.tr_tckn,
  tr_vkn = west.tr_vkn,
  ir_national_mod11 = west.ir_national_mod11,
  kz_iin = west.kz_iin,
  luhn = luhn,
  verhoeff = verhoeff,
  iban_mod97 = iban,
  -- registry-uniform entry: verify(s) treats the last character as the check digit
  icao9303_check_digit = { id = icao.id, verify = icao.verify_with_trailing_digit, check_digit = icao.check_digit },
}

-- verify(algorithm_id, value) -> bool, reason
function M.verify(algorithm_id, value)
  local algo = M.by_id[algorithm_id]
  if not algo then return false, "unknown_algorithm" end
  return algo.verify(value)
end

function M.ids()
  local out = {}
  for k in pairs(M.by_id) do out[#out + 1] = k end
  table.sort(out)
  return out
end

return M
