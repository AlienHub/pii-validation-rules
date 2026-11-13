-- IBAN (ISO 13616) structure + ISO 7064 MOD 97-10 check, streamed byte by byte.
--
-- Scope: the 16 Asian / Middle-Eastern IBAN countries whose BBAN layout was
-- taken from the SWIFT IBAN Registry (Release 103, 2026-09) in research/sources.json.
-- Other countries are rejected as "country_not_in_registry_subset" (this is a
-- deliberate scope limit, not a claim that they have no IBAN).
--
-- A passing result proves arithmetic consistency and registry shape only. It
-- does not prove that the bank, branch or account exists. Domestic account
-- numbers (BBAN internals) are not validated beyond the registry character classes.

local util = require("pii.checksums.util")

local M = {}
M.id = "iban_mod97"

-- BBAN segments: n = digits, a = uppercase letters, c = uppercase letters or digits.
-- total = full IBAN length including the 2-letter country code and 2 check digits.
M.registry = {
  AE = { total = 23, bban = { { 3, "n" }, { 16, "n" } }, notation = "3!n16!n" },
  BH = { total = 22, bban = { { 4, "a" }, { 14, "c" } }, notation = "4!a14!c" },
  IL = { total = 23, bban = { { 3, "n" }, { 3, "n" }, { 13, "n" } }, notation = "3!n3!n13!n" },
  IQ = { total = 23, bban = { { 4, "a" }, { 3, "n" }, { 12, "n" } }, notation = "4!a3!n12!n" },
  JO = { total = 30, bban = { { 4, "a" }, { 4, "n" }, { 18, "c" } }, notation = "4!a4!n18!c" },
  KW = { total = 30, bban = { { 4, "a" }, { 22, "c" } }, notation = "4!a22!c" },
  KZ = { total = 20, bban = { { 3, "n" }, { 13, "c" } }, notation = "3!n13!c" },
  LB = { total = 28, bban = { { 4, "n" }, { 20, "c" } }, notation = "4!n20!c" },
  MN = { total = 20, bban = { { 4, "n" }, { 12, "n" } }, notation = "4!n12!n" },
  OM = { total = 23, bban = { { 3, "n" }, { 16, "c" } }, notation = "3!n16!c" },
  PK = { total = 24, bban = { { 4, "a" }, { 16, "c" } }, notation = "4!a16!c" },
  PS = { total = 29, bban = { { 4, "a" }, { 21, "c" } }, notation = "4!a21!c" },
  QA = { total = 29, bban = { { 4, "a" }, { 21, "c" } }, notation = "4!a21!c" },
  SA = { total = 24, bban = { { 2, "n" }, { 18, "c" } }, notation = "2!n18!c" },
  -- TR reserved national field (position 10 / BBAN index 6) must be ASCII '0'
  -- per TCMB 2021-08-05 gazette; character class alone is insufficient.
  TR = { total = 26, bban = { { 5, "n" }, { 1, "n" }, { 16, "c" } }, notation = "5!n1!n16!c", reserved_zero_at = 10 },
  YE = { total = 30, bban = { { 4, "a" }, { 4, "n" }, { 18, "c" } }, notation = "4!a4!n18!c" },
}

local function class_ok(b, cls)
  if cls == "n" then return util.is_digit_byte(b) end
  if cls == "a" then return util.is_upper_byte(b) end
  return util.is_digit_byte(b) or util.is_upper_byte(b)
end

-- validate_structure(s): country known, exact length, check digits numeric,
-- BBAN segments in their character classes. Returns true or false, reason.
function M.validate_structure(s)
  if type(s) ~= "string" then return false, "not_a_string" end
  if #s < 4 then return false, "bad_length" end
  local cc = string.sub(s, 1, 2)
  local entry = M.registry[cc]
  if not entry then
    if not (util.is_upper_byte(string.byte(s, 1)) and util.is_upper_byte(string.byte(s, 2))) then
      return false, "bad_character"
    end
    return false, "country_not_in_registry_subset"
  end
  if #s ~= entry.total then return false, "bad_length" end
  if not (util.is_digit_byte(string.byte(s, 3)) and util.is_digit_byte(string.byte(s, 4))) then
    return false, "bad_character"
  end
  local pos = 5
  for _, seg in ipairs(entry.bban) do
    for i = pos, pos + seg[1] - 1 do
      if not class_ok(string.byte(s, i), seg[2]) then return false, "bad_character" end
    end
    pos = pos + seg[1]
  end
  if entry.reserved_zero_at then
    if string.sub(s, entry.reserved_zero_at, entry.reserved_zero_at) ~= "0" then
      return false, "reserved_field_nonzero"
    end
  end
  return true
end

-- mod97(s): streamed ISO 7064 MOD 97-10 remainder of s with its first four
-- characters moved to the end and letters expanded to 10..35.
-- Returns remainder (0..96) or nil, reason for an illegal character.
function M.mod97(s)
  if type(s) ~= "string" or #s < 5 then return nil, "bad_length" end
  local rem = 0
  local n = #s
  local function feed(b)
    if util.is_digit_byte(b) then
      rem = (rem * 10 + (b - 48)) % 97
    elseif util.is_upper_byte(b) then
      local v = b - 55 -- A=10 .. Z=35, two decimal digits
      rem = (rem * 10 + math.floor(v / 10)) % 97
      rem = (rem * 10 + v % 10) % 97
    else
      return false
    end
    return true
  end
  for i = 5, n do
    if not feed(string.byte(s, i)) then return nil, "bad_character" end
  end
  for i = 1, 4 do
    if not feed(string.byte(s, i)) then return nil, "bad_character" end
  end
  return rem
end

-- verify(s): structure for the registry subset + check digits 02..98 + remainder 1.
function M.verify(s)
  local ok, why = M.validate_structure(s)
  if not ok then return false, why end
  local cd = tonumber(string.sub(s, 3, 4))
  if cd < 2 or cd > 98 then return false, "check_digits_out_of_range" end
  local rem, err = M.mod97(s)
  if not rem then return false, err end
  if rem ~= 1 then return false, "check_mismatch" end
  return true
end

-- check_digits(cc, bban): synthetic generation helper. Computes the two check
-- digits for cc .. "00" .. bban (ISO 13616 Annex A method) as a 2-char string.
function M.check_digits(cc, bban)
  if type(cc) ~= "string" or type(bban) ~= "string" then return nil, "not_a_string" end
  local rem, err = M.mod97(cc .. "00" .. bban)
  if not rem then return nil, err end
  return string.format("%02d", 98 - rem)
end

-- Electronic format helper used by pii.normalize: removes single spaces that
-- sit exactly between 4-character groups ("AE15 1111 ..."). Anything else is
-- left untouched so the caller sees the syntax failure.
function M.strip_print_format_spaces(s)
  if type(s) ~= "string" or not string.find(s, " ", 1, true) then return s, false end
  local groups = {}
  for g in string.gmatch(s, "[^ ]+") do groups[#groups + 1] = g end
  local rebuilt = table.concat(groups, " ")
  if rebuilt ~= s then return s, false end -- double/leading/trailing spaces: not print format
  for i = 1, #groups - 1 do
    if #groups[i] ~= 4 then return s, false end
  end
  if #groups[#groups] < 1 or #groups[#groups] > 4 then return s, false end
  return table.concat(groups), true
end

return M
