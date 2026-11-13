return function(T)
  T.suite("policies")
  local policies = require("pii.policies")
  local pii = require("pii")
  local reg = pii.load(T.opts.rules)

  local function decide(rule_id, value, options)
    local rule = reg:get(rule_id)
    local algo = reg:algorithm(rule.checksum.algorithm)
    return policies.decide(rule, algo, value, policies.merge(options))
  end

  T.case("defaults are conservative", function()
    local o = policies.merge(nil)
    T.eq(o.secondary_checksums, false, "secondary off")
    T.eq(o.sg_m_series_experimental, false, "M off")
    T.eq(o.kr_rrn_regime, "unknown", "KR unknown")
    T.eq(o.normalize, false, "normalize off")
    T.eq(o.ascii_uppercase, false, "uppercase off")
    T.eq(o.historical_import, false, "historical off")
    T.eq(o.max_input_length, 128, "length guard")
  end)

  T.case("enabled (official) algorithms run by default and can be disabled per id", function()
    T.eq(decide("CN.resident_id", "x", nil), "run", "cn runs")
    T.eq(decide("JP.my_number", "x", nil), "run", "jp runs")
    T.eq(decide("KZ.iin", "x", nil), "run", "kz runs")
    T.eq(decide("AE.iban", "x", nil), "run", "iban runs")
    T.eq(decide("IN.aadhaar", "x", nil), "run", "verhoeff runs")
    T.eq(decide("GLOBAL.payment_pan_current", "x", nil), "run", "luhn runs for PAN")
    local d, why = decide("CN.resident_id", "x", { algorithms = { cn_resident_id_mod11_2 = false } })
    T.eq(d, "skip", "disabled by caller")
    T.eq(why, "algorithm_disabled_by_caller", "reason")
  end)

  T.case("opt_in_secondary algorithms skip by default with an evidence reason", function()
    for _, id in ipairs({ "TH.citizen_id", "TR.tckn", "TR.vkn", "TW.citizen_id", "HK.hkid", "IR.national_code", "IL.id_tin" }) do
      local d, why = decide(id, "x", nil)
      T.eq(d, "skip", id .. " skips by default")
      T.check(string.find(why, "secondary_formula_not_enabled", 1, true), id .. " reason mentions secondary")
      T.eq(decide(id, "x", { secondary_checksums = true }), "run", id .. " runs with global opt-in")
    end
    T.eq(decide("TH.citizen_id", "x", { algorithms = { th_mod11 = true } }), "run", "per-algorithm opt-in")
    local d = decide("TH.citizen_id", "x", { secondary_checksums = true, algorithms = { th_mod11 = false } })
    T.eq(d, "skip", "per-algorithm override beats global")
  end)

  T.case("IL Luhn is rule-scoped: PAN runs by default, IL.id_tin does not", function()
    T.eq(decide("GLOBAL.payment_pan_current", "x", nil), "run", "pan")
    T.eq(decide("IL.id_tin", "x", nil), "skip", "il")
    T.eq(reg:get("IL.entity_tin").checksum.status, "not_established", "entity tin has no algorithm")
  end)

  T.case("SG: S/T/F/G opt-in; M requires the experimental flag", function()
    T.eq(decide("SG.nric", "S1234567D", nil), "skip", "S default skip")
    T.eq(decide("SG.nric", "S1234567D", { secondary_checksums = true }), "run", "S opt-in")
    local d, why = decide("SG.fin", "M1234567B", { secondary_checksums = true })
    T.eq(d, "skip", "M still skipped")
    T.check(string.find(why, "experimental", 1, true), "reason mentions experimental")
    T.eq(decide("SG.fin", "M1234567B", { sg_m_series_experimental = true }), "run", "M experimental")
    T.eq(decide("SG.fin", "F1234567N", { secondary_checksums = true }), "run", "F opt-in")
    T.eq(decide("SG.fin", "G1234567X", { sg_m_series_experimental = true }), "skip", "experimental flag alone does not enable F/G")
  end)

  T.case("KR: regime gating", function()
    local d, why = decide("KR.rrn", "x", nil)
    T.eq(d, "skip", "unknown regime skips")
    T.check(string.find(why, "regime_unknown", 1, true), "reason")
    d, why = decide("KR.rrn", "x", { kr_rrn_regime = "current_post_2020_10" })
    T.eq(d, "not_applicable", "current -> not_applicable")
    T.eq(decide("KR.rrn", "x", { kr_rrn_regime = "legacy_pre_2020_10" }), "run", "legacy runs")
    T.eq(decide("KR.rrn", "x", { secondary_checksums = true }), "skip", "secondary flag does not unlock legacy formula")
  end)

  T.case("every rule with an algorithm has a policy from the known vocabulary", function()
    local known = { enabled = true, opt_in_secondary = true, opt_in_secondary_m_series_experimental = true, explicit_legacy_regime = true }
    for _, id in ipairs(reg:ids()) do
      local r = reg:get(id)
      if r.checksum.status == "algorithm_available" then
        T.check(known[r.checksum.policy], id .. " policy " .. tostring(r.checksum.policy))
        T.check(reg:algorithm(r.checksum.algorithm) ~= nil, id .. " algorithm spec exists")
        T.check(pii.checksums.by_id[r.checksum.algorithm] ~= nil, id .. " algorithm implemented")
      end
    end
  end)

  T.case("official evidence <=> enabled policy; secondary evidence never enabled by default", function()
    for aid, spec in pairs(reg.algorithms) do
      if spec.default_policy == "enabled" then
        T.check(spec.evidence == "official" or spec.evidence == "standard_algorithm" or spec.evidence == "official_algorithm_name_secondary_tables",
          aid .. " enabled only with official/standard evidence (" .. tostring(spec.evidence) .. ")")
      else
        T.check(spec.evidence ~= "official", aid .. " non-official evidence is not enabled by default")
      end
    end
  end)
end
