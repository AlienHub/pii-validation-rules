-- Policy layer: decides whether a rule's checksum algorithm may run for a given
-- call, based on the evidence grade recorded in rules/*.json and the caller's
-- explicit options. Arithmetic never runs implicitly for secondary/reconstructed
-- formulas; when it does not run the checksum layer reports "unknown", never
-- "pass" and never "fail".
--
-- Options recognised (all default to the conservative value):
--   secondary_checksums      boolean  enable every opt_in_secondary algorithm
--   algorithms               table    per-algorithm override { th_mod11 = true/false }
--   sg_m_series_experimental boolean  evaluate the disputed Singapore M-series table
--   kr_rrn_regime            string   "unknown" (default) | "current_post_2020_10" | "legacy_pre_2020_10"
--   historical_import        boolean  acknowledge historical_syntax rules (suppresses the warning)
--   ir_reject_repeated_digits boolean default true; anti-placeholder policy for IR national code
--   processor_profiles       table    { worldpay = true } enables opt_in_processor_profile rules

local M = {}

M.defaults = {
  secondary_checksums = false,
  algorithms = {},
  sg_m_series_experimental = false,
  kr_rrn_regime = "unknown",
  historical_import = false,
  ir_reject_repeated_digits = true,
  ascii_uppercase = false,
  normalize = false,
  semantic = true,
  max_input_length = 128,
  reference_date = nil, -- "YYYY-MM-DD"; when nil, future-date checks are skipped
  processor_profiles = {},
}

function M.merge(options)
  local o = {}
  for k, v in pairs(M.defaults) do o[k] = v end
  if options then
    for k, v in pairs(options) do o[k] = v end
  end
  if type(o.algorithms) ~= "table" then o.algorithms = {} end
  if type(o.processor_profiles) ~= "table" then o.processor_profiles = {} end
  return o
end

-- decide(rule, algorithm_spec, value, options) ->
--   "run"            algorithm may be evaluated
--   "skip", reason   checksum layer must report "unknown" with reason
--   "not_applicable", reason  (only for regime-gated algorithms with a declared non-matching regime)
function M.decide(rule, algo, value, o)
  local policy = (rule.checksum and rule.checksum.policy) or (algo and algo.default_policy) or "opt_in_secondary"
  local id = algo and algo.id or (rule.checksum and rule.checksum.algorithm)
  local override = id and o.algorithms[id]

  if policy == "enabled" then
    if override == false then return "skip", "algorithm_disabled_by_caller" end
    return "run"
  end

  if policy == "opt_in_secondary" then
    if override == false then return "skip", "algorithm_disabled_by_caller" end
    if override == true or o.secondary_checksums then return "run" end
    return "skip", "secondary_formula_not_enabled:" .. tostring(rule.checksum and rule.checksum.evidence)
  end

  if policy == "opt_in_secondary_m_series_experimental" then
    local prefix = type(value) == "string" and string.sub(value, 1, 1) or ""
    if prefix == "M" then
      if o.sg_m_series_experimental then return "run" end
      return "skip", "sg_m_series_table_disputed_experimental_flag_not_set"
    end
    if override == false then return "skip", "algorithm_disabled_by_caller" end
    if override == true or o.secondary_checksums then return "run" end
    return "skip", "secondary_formula_not_enabled:reconstructed_not_ica_official"
  end

  if policy == "explicit_legacy_regime" then
    local regime = o.kr_rrn_regime or "unknown"
    if regime == "legacy_pre_2020_10" then return "run" end
    if regime == "current_post_2020_10" then return "not_applicable", "current_regime_has_no_public_checksum" end
    return "skip", "issuance_regime_unknown_legacy_formula_not_applied"
  end

  if policy == "opt_in_processor_profile" then
    if override == false then return "skip", "algorithm_disabled_by_caller" end
    if override == true then return "run" end
    local proc = rule.checksum and rule.checksum.processor
    if proc and o.processor_profiles[proc] then return "run" end
    return "skip", "processor_profile_not_enabled:" .. tostring(proc or "unspecified")
  end

  return "skip", "unknown_policy:" .. tostring(policy)
end

return M
