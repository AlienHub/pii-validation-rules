-- Explicit presentation normalization. Never applied implicitly: pii.validate
-- only calls this when options.normalize == true, and every transformation that
-- actually changed the string is reported back to the caller.
--
-- Principles (docs/API.zh.md §归一化):
--   * input stays a string; leading zeros are never touched;
--   * only the field-specific separators declared in the rule's "normalization"
--     list are removed; no global whitespace/punctuation stripping;
--   * ASCII upper-casing only when the caller sets options.ascii_uppercase;
--   * no Unicode NFKC folding: full-width or compatibility characters are left
--     as-is and will fail the syntax layer.

local iban = require("pii.checksums.iban")

local M = {}

local transforms = {}

-- "NNNNNN-NN-NNNN" style: remove the separator only when the string has exactly
-- the layout's length and separators at exactly the layout's positions.
transforms.strip_fixed_separators = function(value, spec)
  local layout, sep = spec.layout, spec.separator
  if #value ~= #layout then return value, false end
  local out = {}
  for i = 1, #layout do
    local lc, vc = string.sub(layout, i, i), string.sub(value, i, i)
    if lc == sep then
      if vc ~= sep then return value, false end
    else
      if vc == sep then return value, false end
      out[#out + 1] = vc
    end
  end
  return table.concat(out), true
end

-- "A123456(3)" -> "A1234563": only a single trailing "(x)" pair with exactly one
-- character inside is removed.
transforms.strip_trailing_parenthesised_check = function(value)
  local body, chk = string.match(value, "^([^()]+)%(([^()])%)$")
  if body then return body .. chk, true end
  return value, false
end

-- Legacy Singapore foreign-company tax reference "F   12345A" -> "F00012345A".
transforms.sg_foreign_company_legacy_spaces = function(value)
  local rest = string.match(value, "^F   (%d%d%d%d%d%u)$")
  if rest then return "F000" .. rest, true end
  return value, false
end

transforms.strip_print_format_spaces = function(value)
  return iban.strip_print_format_spaces(value)
end

transforms.ascii_uppercase = function(value, spec, o)
  if not o.ascii_uppercase then return value, false end
  local up = string.gsub(value, "%l", string.upper)
  return up, up ~= value
end

transforms.ascii_uppercase_last_char = function(value, spec, o)
  if not o.ascii_uppercase or #value == 0 then return value, false end
  local last = string.sub(value, #value)
  if last == "x" then return string.sub(value, 1, #value - 1) .. "X", true end
  return value, false
end

-- BOC Macau self-service channel only: when the caller supplies the canonical
-- 17-digit form that starts with "00", map to the 15-digit channel input by
-- removing exactly those two zeros. Never expand 15→17 here (that would break
-- syntax of the 15-digit channel rule) and never trim arbitrary leading zeros.
transforms.mo_boc_selfservice_00_prefix_channel = function(value, spec)
  if type(value) ~= "string" then return value, false end
  if #value == 17 and string.sub(value, 1, 2) == "00" then
    return string.sub(value, 3), true
  end
  return value, false
end

-- Explicit reverse helper for callers mapping channel input → canonical 17.
function M.mo_boc_selfservice_to_canonical17(channel15)
  if type(channel15) ~= "string" or #channel15 ~= 15 then return nil, "bad_length" end
  if not string.match(channel15, "^[0-9]+$") then return nil, "bad_character" end
  return "00" .. channel15
end

-- apply(rule, value, options) -> normalized_value, applied_transforms (array of names)
function M.apply(rule, value, o)
  local applied = {}
  if type(value) ~= "string" then return value, applied end
  local list = rule.normalization or {}
  for _, spec in ipairs(list) do
    local fn = transforms[spec.transform]
    if fn then
      if spec.requires_option and not o[spec.requires_option] then
        -- caller did not opt in; skip silently
      else
        local nv, changed = fn(value, spec, o)
        if changed then
          applied[#applied + 1] = spec.transform
          value = nv
        end
      end
    else
      applied[#applied + 1] = "unknown_transform_ignored:" .. tostring(spec.transform)
    end
  end
  return value, applied
end

M.transforms = transforms

return M
