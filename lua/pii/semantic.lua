-- Semantic layer: calendar / embedded-field plausibility checks that neither a
-- regex nor a check digit can express. Each check reports pass / fail / unknown.
-- "pass" means only that the checks listed in result.semantic_details passed;
-- anything the repository could not verify (region tables, issuance, century)
-- is reported as "unknown" in the details and as a warning, never as pass.

local M = {}

-- ------------------------------------------------------------------ calendar helpers
function M.is_leap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local MDAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function M.days_in_month(y, m)
  if m == 2 and M.is_leap(y) then return 29 end
  return MDAYS[m]
end

function M.valid_date(y, m, d)
  if type(y) ~= "number" or type(m) ~= "number" or type(d) ~= "number" then return false end
  if m < 1 or m > 12 or d < 1 then return false end
  return d <= M.days_in_month(y, m)
end

-- parse "YYYY-MM-DD" -> y, m, d or nil
function M.parse_iso_date(s)
  if type(s) ~= "string" then return nil end
  local y, m, d = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not M.valid_date(y, m, d) then return nil end
  return y, m, d
end

local function after(y, m, d, ry, rm, rd)
  if y ~= ry then return y > ry end
  if m ~= rm then return m > rm end
  return d > rd
end

local function num(s, i, j)
  return tonumber(string.sub(s, i, j))
end

-- Two-digit year whose century is unknown: valid if the date is valid in at
-- least one of 1900+yy / 2000+yy (and 1800+yy for completeness of leap rules).
local function ambiguous_century_date_ok(yy, m, d)
  for _, base in ipairs({ 1800, 1900, 2000 }) do
    if M.valid_date(base + yy, m, d) then return true end
  end
  return false
end

-- ------------------------------------------------------------------ rule checks
local checks = {}

checks["CN.resident_id"] = function(value, o, details, warnings)
  local y, m, d = num(value, 7, 10), num(value, 11, 12), num(value, 13, 14)
  local ok = M.valid_date(y, m, d)
  details.birth_date_gregorian = ok and "pass" or "fail"
  if ok and o.reference_date then
    local ry, rm, rd = M.parse_iso_date(o.reference_date)
    if ry then
      details.not_after_reference_date = after(y, m, d, ry, rm, rd) and "fail" or "pass"
    end
  end
  details.region_code = "unknown"
  warnings[#warnings + 1] = "semantic:region_code_not_verified_no_gb2260_history_table"
end

checks["ID.nik"] = function(value, o, details, warnings)
  local dd, mm, yy = num(value, 7, 8), num(value, 9, 10), num(value, 11, 12)
  if dd >= 41 then
    dd = dd - 40
    details.sex_encoding = "female_day_plus_40"
  else
    details.sex_encoding = "male_or_unmarked"
  end
  details.birth_date_ddmmyy = ambiguous_century_date_ok(yy, mm, dd) and "pass" or "fail"
  details.century = "unknown"
  details.region_code = "unknown"
  warnings[#warnings + 1] = "semantic:century_ambiguous_two_digit_year"
  warnings[#warnings + 1] = "semantic:region_code_not_verified"
end

checks["MY.nric"] = function(value, o, details, warnings)
  local yy, mm, dd = num(value, 1, 2), num(value, 3, 4), num(value, 5, 6)
  details.birth_date_yymmdd = ambiguous_century_date_ok(yy, mm, dd) and "pass" or "fail"
  details.century = "unknown"
  details.birthplace_code = "unknown"
  warnings[#warnings + 1] = "semantic:century_ambiguous_two_digit_year"
  warnings[#warnings + 1] = "semantic:birthplace_code_not_verified"
end

local KR_CENTURY = { ["1"] = 1900, ["2"] = 1900, ["3"] = 2000, ["4"] = 2000, ["5"] = 1900, ["6"] = 1900,
  ["7"] = 2000, ["8"] = 2000, ["9"] = 1800, ["0"] = 1800 }

checks["KR.rrn"] = function(value, o, details, warnings)
  local yy, mm, dd = num(value, 1, 2), num(value, 3, 4), num(value, 5, 6)
  local base = KR_CENTURY[string.sub(value, 7, 7)]
  local y = base + yy
  local ok = M.valid_date(y, mm, dd)
  details.birth_date_with_century_digit = ok and "pass" or "fail"
  if ok and o.reference_date then
    local ry, rm, rd = M.parse_iso_date(o.reference_date)
    if ry then
      details.not_after_reference_date = after(y, mm, dd, ry, rm, rd) and "fail" or "pass"
    end
  end
  warnings[#warnings + 1] = "semantic:century_digit_mapping_is_conventional_not_issuer_verified_here"
end

checks["IN.pan"] = function(value, o, details)
  details.serial_not_0000 = (string.sub(value, 6, 9) ~= "0000") and "pass" or "fail"
end

-- Anti-placeholder policy (e.g. 1111111111). Separate from the MOD 11 arithmetic,
-- which such strings can satisfy; disabled with options.ir_reject_repeated_digits = false.
checks["IR.national_code"] = function(value, o, details, warnings)
  if o.ir_reject_repeated_digits == false then
    details.repeated_digits_placeholder = "unknown"
    warnings[#warnings + 1] = "semantic:repeated_digits_policy_disabled_by_caller"
    return
  end
  local first = string.sub(value, 1, 1)
  details.repeated_digits_placeholder = (string.rep(first, #value) == value) and "fail" or "pass"
end

M.checks = checks

-- evaluate(rule, value, options) -> status, details, warnings
-- status: "pass" | "fail" | "unknown" | "not_applicable"
function M.evaluate(rule, value, o)
  local details, warnings = {}, {}
  local listed = rule.semantic_checks or {}
  local fn = checks[rule.id]
  if not fn then
    if #listed == 0 then return "not_applicable", details, warnings end
    warnings[#warnings + 1] = "semantic:checks_listed_but_not_implemented"
    return "unknown", details, warnings
  end
  fn(value, o, details, warnings)
  local status = "pass"
  local any_checked = false
  for _, v in pairs(details) do
    if v == "fail" then status = "fail" end
    if v == "pass" or v == "fail" then any_checked = true end
  end
  if not any_checked then status = "unknown" end
  return status, details, warnings
end

return M
