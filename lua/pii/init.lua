-- pii: format / checksum / semantic consistency checks for Asian and Middle-Eastern
-- personal and entity identifiers. Pure Lua (5.1 / 5.3 / 5.4 / LuaJIT).
--
-- This library NEVER verifies that an identifier was issued, is current, or
-- belongs to anyone. Every result carries issuer_verification = "unknown".
--
--   local pii = require("pii")
--   pii.load("rules")                      -- optional; default rules dir is "rules"
--   local r = pii.validate("CN.resident_id", "11010519491231002X")
--   r.syntax, r.checksum, r.semantic, r.issuer_verification, r.summary, r.warnings
--
-- Layer vocabulary: "pass" | "fail" | "unknown" | "not_applicable" | "not_evaluated".
-- "unknown" is neither pass nor fail: the repository has no sufficiently evidenced
-- rule or the caller did not enable a secondary formula.

local rules_mod = require("pii.rules")
local syntax = require("pii.syntax")
local checksums = require("pii.checksums")
local policies = require("pii.policies")
local normalize = require("pii.normalize")
local semantic = require("pii.semantic")
local json = require("pii.json")

local M = {}

M.version = "0.1.0"
M.syntax = syntax
M.checksums = checksums
M.policies = policies
M.semantic = semantic
M.json = json
M.normalize_module = normalize

local registry

function M.load(rules_dir)
  registry = rules_mod.load(rules_dir)
  return registry
end

function M.rules()
  if not registry then M.load() end
  return registry
end

function M.rule(rule_id)
  return M.rules():get(rule_id)
end

-- ------------------------------------------------------------------ input guards

-- UTF-8 encodings of Unicode format/bidi controls that must never appear in an
-- identifier: U+200B..U+200F, U+202A..U+202E, U+2060..U+2064, U+FEFF.
local function has_format_control(s)
  for i = 1, #s - 2 do
    local a, b, c = string.byte(s, i, i + 2)
    if a == 0xE2 and b == 0x80 and ((c >= 0x8B and c <= 0x8F) or (c >= 0xAA and c <= 0xAE)) then return true end
    if a == 0xE2 and b == 0x81 and (c >= 0xA0 and c <= 0xA4) then return true end
    if a == 0xEF and b == 0xBB and c == 0xBF then return true end
  end
  return false
end

local function classify_syntax_failure(s)
  for i = 1, #s do
    local b = string.byte(s, i)
    if b < 0x20 or b == 0x7F then return "control_character" end
  end
  if has_format_control(s) then return "format_control_character" end
  for i = 1, #s do
    if string.byte(s, i) >= 0x80 then return "non_ascii_character" end
  end
  return "pattern_mismatch"
end

-- ------------------------------------------------------------------ main API

local STATUS_WARNINGS = {
  candidate_profile = "rule_status:candidate_profile_not_authoritative_do_not_hard_reject",
  country_code_envelope_only = "rule_status:country_code_envelope_only_not_a_phone_number_validator",
  dated_numbering_profile = "rule_status:dated_numbering_profile_snapshot_not_current_allocation",
}

-- validate(rule_id, value, options) -> result table (see docs/API.zh.md)
function M.validate(rule_id, value, options)
  local reg = M.rules()
  local rule = reg:get(rule_id)
  if not rule then
    error("unknown rule id: " .. tostring(rule_id), 2)
  end
  local o = policies.merge(options)
  local algo = rule.checksum and rule.checksum.algorithm and reg:algorithm(rule.checksum.algorithm) or nil

  local res = {
    rule_id = rule.id,
    jurisdiction = rule.jurisdiction,
    pii_type = rule.pii_type,
    rule_status = rule.status,
    rule_version = rule.file_version,
    library_version = M.version,
    syntax = "fail",
    checksum = "not_evaluated",
    semantic = "not_evaluated",
    issuer_verification = "unknown",
    issuer_verification_note = "never performed by this library",
    checksum_status = rule.checksum and rule.checksum.status or "not_established",
    checksum_algorithm = rule.checksum and rule.checksum.algorithm or nil,
    checksum_evidence = rule.checksum and rule.checksum.evidence or nil,
    checksum_policy = rule.checksum and rule.checksum.policy or nil,
    transformations = json.array({}),
    warnings = json.array({}),
  }
  local warnings = res.warnings

  if STATUS_WARNINGS[rule.status] then warnings[#warnings + 1] = STATUS_WARNINGS[rule.status] end
  if rule.status == "historical_syntax" and not o.historical_import then
    warnings[#warnings + 1] = "rule_status:historical_syntax_only_meaningful_in_historical_import_mode"
  end

  -- 1. type / size guards
  if type(value) ~= "string" then
    res.syntax_error = "not_a_string"
    res.input_type = type(value)
    res.summary = "fail"
    return res
  end
  res.input_type = "string"
  if #value > (o.max_input_length or 128) then
    res.syntax_error = "input_too_long"
    res.summary = "fail"
    return res
  end

  -- 2. explicit, opt-in normalization
  local work = value
  if o.normalize then
    local nv, applied = normalize.apply(rule, value, o)
    work = nv
    res.transformations = json.array(applied)
    if #applied > 0 then res.normalized_value = nv end
  end

  -- 3. syntax (restricted-subset matcher; authoritative engine is PCRE2, see docs)
  local compiled = syntax.compile(rule.regex_pcre2)
  if compiled:fullmatch(work) then
    res.syntax = "pass"
  else
    res.syntax = "fail"
    res.syntax_error = classify_syntax_failure(work)
    res.summary = "fail"
    return res
  end

  -- 4. checksum
  local cstatus = res.checksum_status
  if cstatus == "algorithm_available" and algo then
    local decision, reason = policies.decide(rule, algo, work, o)
    if decision == "run" then
      local ok, why = checksums.verify(algo.id, work)
      res.checksum = ok and "pass" or "fail"
      if not ok then res.checksum_reason = why end
      if rule.checksum.evidence ~= "official" and rule.checksum.evidence ~= "standard_algorithm" then
        warnings[#warnings + 1] = "checksum:evidence_" .. tostring(rule.checksum.evidence) .. "_not_issuer_certified"
      end
    elseif decision == "not_applicable" then
      res.checksum = "not_applicable"
      res.checksum_reason = reason
    else
      res.checksum = "unknown"
      res.checksum_reason = reason
    end
  elseif cstatus == "none_per_source" then
    res.checksum = "not_applicable"
    res.checksum_reason = "source_states_no_check_digit"
  elseif cstatus == "not_applicable" then
    res.checksum = "not_applicable"
    res.checksum_reason = "type_has_no_rule_level_check_digit"
  else
    res.checksum = "unknown"
    res.checksum_reason = "checksum_not_established_in_research"
  end

  -- 5. semantic
  if o.semantic == false then
    res.semantic = "not_evaluated"
  else
    local st, details, sw = semantic.evaluate(rule, work, o)
    res.semantic = st
    res.semantic_details = details
    for _, w in ipairs(sw) do warnings[#warnings + 1] = w end
  end

  -- 6. summary (never "valid": only "nothing failed" at the layers that could run)
  if res.checksum == "fail" or res.semantic == "fail" then
    res.summary = "fail"
  elseif (res.checksum == "pass" or res.checksum == "not_applicable")
    and (res.semantic == "pass" or res.semantic == "not_applicable" or res.semantic == "not_evaluated") then
    res.summary = "pass"
  else
    res.summary = "pass_with_unknowns"
  end
  return res
end

-- normalize(rule_id, value, options) -> normalized_value, transformations
function M.normalize(rule_id, value, options)
  local rule = M.rules():get(rule_id)
  if not rule then error("unknown rule id: " .. tostring(rule_id), 2) end
  local o = policies.merge(options)
  o.normalize = true
  return normalize.apply(rule, value, o)
end

-- Matching helper exposing the restricted-subset matcher for a rule id.
function M.syntax_match(rule_id, value)
  local rule = M.rules():get(rule_id)
  if not rule then error("unknown rule id: " .. tostring(rule_id), 2) end
  return syntax.compile(rule.regex_pcre2):fullmatch(value)
end

-- Log-safe projection: drops every field that could carry input material.
function M.redact(result)
  local out = {}
  for k, v in pairs(result) do
    if k ~= "normalized_value" then out[k] = v end
  end
  return out
end

return M
