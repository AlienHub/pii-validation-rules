-- End-to-end API tests over every rule in rules/*.json.
return function(T)
  T.suite("api")
  local pii = require("pii")
  local reg = pii.load(T.opts.rules)
  local json = require("pii.json")

  local ALL_ON = { secondary_checksums = true, sg_m_series_experimental = true, kr_rrn_regime = "legacy_pre_2020_10", historical_import = true }

  T.case("registry statistics match the documented inventory", function()
    local c = reg:count_by_status()
    T.eq(#reg:ids(), 129, "129 regex rules")
    T.eq(c.syntax_supported, 72, "syntax_supported")
    T.eq(c.historical_syntax, 5, "historical_syntax")
    T.eq(c.candidate_profile, 9, "candidate_profile")
    T.eq(c.country_code_envelope_only, 39, "country_code_envelope_only")
    T.eq(c.dated_numbering_profile, 4, "dated_numbering_profile")
    local n = 0
    for _ in pairs(reg.algorithms) do n = n + 1 end
    T.eq(n, 17, "17 checksum algorithm specs")
    T.eq(#pii.checksums.ids(), 17, "17 implemented algorithms")
  end)

  T.case("result shape and vocabulary", function()
    local r = pii.validate("CN.resident_id", "11010519491231002X")
    for _, k in ipairs({ "rule_id", "jurisdiction", "pii_type", "rule_status", "rule_version", "library_version", "syntax", "checksum", "semantic", "issuer_verification", "summary", "warnings", "transformations", "checksum_status" }) do
      T.check(r[k] ~= nil, "field present: " .. k)
    end
    T.eq(r.issuer_verification, "unknown", "issuer unknown")
    T.eq(r.rule_version, "2026.11.13", "rule version")
    local vocab = { pass = true, fail = true, unknown = true, not_applicable = true, not_evaluated = true }
    for _, k in ipairs({ "syntax", "checksum", "semantic" }) do
      T.check(vocab[r[k]], k .. " in vocabulary")
    end
    T.eq(r.normalized_value, nil, "no normalized value without normalize option")
    local red = pii.redact(pii.validate("MY.nric", "900101-01-0001", { normalize = true }))
    T.eq(red.normalized_value, nil, "redact drops normalized_value")
    T.eq(red.rule_id, "MY.nric", "redact keeps rule id")
  end)

  T.case("unknown rule id raises; options table is not mutated", function()
    T.eq(pcall(pii.validate, "XX.nothing", "1"), false, "raises")
    local o = { secondary_checksums = true }
    pii.validate("TH.citizen_id", "1234567890121", o)
    T.eq(o.normalize, nil, "caller options untouched")
  end)

  T.case("every rule: positive examples pass syntax; negative examples fail", function()
    for _, id in ipairs(reg:ids()) do
      local r = reg:get(id)
      for _, e in ipairs(r.examples) do
        local res = pii.validate(id, e.input)
        T.eq(res.syntax, e.expected_syntax and "pass" or "fail", id .. " example " .. e.input)
      end
      for _, e in ipairs(r.negative_syntax_examples) do
        local res = pii.validate(id, e.input)
        T.eq(res.syntax, "fail", id .. " negative " .. string.format("%q", e.input))
        T.eq(res.checksum, "not_evaluated", id .. " checksum not evaluated after syntax failure")
      end
    end
  end)

  T.case("every rule: expected_checksum_arithmetic holds when all algorithms are enabled", function()
    for _, id in ipairs(reg:ids()) do
      local r = reg:get(id)
      for _, e in ipairs(r.examples) do
        if e.expected_checksum_arithmetic ~= nil and e.expected_checksum_arithmetic ~= json.null then
          local res = pii.validate(id, e.input, ALL_ON)
          T.eq(res.checksum, e.expected_checksum_arithmetic and "pass" or "fail", id .. " checksum for " .. e.input)
        end
      end
    end
  end)

  T.case("default mode never reports checksum=fail for opt-in or regime-gated algorithms", function()
    for _, id in ipairs(reg:ids()) do
      local r = reg:get(id)
      if r.checksum.status == "algorithm_available" and r.checksum.policy ~= "enabled" then
        for _, e in ipairs(r.examples) do
          local mutated = string.sub(e.input, 1, #e.input - 1) .. (string.sub(e.input, #e.input) == "0" and "1" or "0")
          local res = pii.validate(id, mutated)
          if res.syntax == "pass" then
            T.check(res.checksum == "unknown", id .. " default checksum is unknown, got " .. res.checksum)
          end
        end
      end
    end
  end)

  T.case("checksum_status vocabulary is respected per rule", function()
    for _, id in ipairs(reg:ids()) do
      local r = reg:get(id)
      local st = r.checksum.status
      local e = r.examples[1]
      local res = pii.validate(id, e.input, ALL_ON)
      if st == "algorithm_available" then
        T.check(res.checksum == "pass" or res.checksum == "fail", id .. " evaluated when enabled (" .. res.checksum .. ")")
      elseif st == "none_per_source" or st == "not_applicable" then
        T.eq(res.checksum, "not_applicable", id .. " not applicable")
      elseif st == "not_established" then
        T.eq(res.checksum, "unknown", id .. " unknown")
      else
        error("unknown checksum status " .. tostring(st))
      end
    end
  end)

  T.case("status warnings: candidate / envelope / dated / historical", function()
    local function has(id, needle, opts)
      local r = pii.validate(id, reg:get(id).examples[1].input, opts)
      for _, w in ipairs(r.warnings) do if string.find(w, needle, 1, true) then return true end end
      return false
    end
    T.check(has("MY.tin_individual", "candidate_profile"), "candidate warns")
    T.check(has("CN.phone_country_envelope", "country_code_envelope_only"), "envelope warns")
    T.check(has("SG.phone_nsn_profile", "dated_numbering_profile"), "dated warns")
    T.check(has("TW.old_ui", "historical_syntax"), "historical warns")
    T.check(not has("TW.old_ui", "historical_syntax", { historical_import = true }), "historical silent in import mode")
    T.check(not has("CN.resident_id", "rule_status:"), "syntax_supported has no status warning")
  end)

  T.case("non-string and oversize inputs for every rule", function()
    for _, id in ipairs(reg:ids()) do
      for _, bad in ipairs({ 12345, true, {} }) do
        local res = pii.validate(id, bad)
        T.eq(res.syntax, "fail", id .. " non-string")
        T.eq(res.syntax_error, "not_a_string", id .. " reason")
        T.eq(res.summary, "fail", id .. " summary")
      end
      local res = pii.validate(id, nil)
      T.eq(res.syntax_error, "not_a_string", id .. " nil")
      res = pii.validate(id, string.rep("1", 129))
      T.eq(res.syntax_error, "input_too_long", id .. " too long")
      res = pii.validate(id, string.rep("1", 129), { max_input_length = 200 })
      T.check(res.syntax_error ~= "input_too_long", id .. " custom length guard")
    end
  end)

  T.case("rules_for() and jurisdiction headers", function()
    T.eq(#reg:rules_for("SG"), 10, "SG rules")
    T.eq(#reg:rules_for("SG", "phone"), 2, "SG phone rules")
    T.eq(reg.jurisdictions.CN.calling_code, "86", "CN calling code")
    T.eq(reg.jurisdictions.GLOBAL.scope_group, "international", "GLOBAL group")
  end)
end
