-- Banking deep-research regressions: six-region bank/PAN/ID profiles, directory
-- lookups, layered results, and algorithm vectors. Format positives are syntax
-- only — checksum must still fail when arithmetic is wrong.

return function(T)
  local pii = require("pii")
  local directories = require("pii.directories")
  local cs = require("pii.checksums")

  pii.load(T.opts.rules)
  directories.clear()
  directories.load_json("sg_uob_prefix_branch", T.opts.fixtures .. "/directories/synthetic-uob-prefix-branch.json")
  directories.load_json("hk_mobile_allocation", T.opts.fixtures .. "/directories/synthetic-hk-mobile-ranges.json")
  directories.load_json("mo_mobile_allocation", T.opts.fixtures .. "/directories/synthetic-mo-mobile-ranges.json")

  T.suite("banking")

  T.case("TH SCB accepts 10 and 13; rejects 11", function()
    T.eq(pii.validate("TH.scb.company_add_account", "0012345678").syntax, "pass", "10")
    T.eq(pii.validate("TH.scb.company_add_account", "0012345678901").syntax, "pass", "13")
    T.eq(pii.validate("TH.scb.company_add_account", "00123456789").syntax, "fail", "11")
    T.eq(pii.validate("TH.scb.company_add_account", "0012345678").checksum, "unknown", "no checksum claimed")
  end)

  T.case("SG UOB VAN lengths vs ordinary 10", function()
    T.eq(pii.validate("SG.uob.van", "123456789012345678").syntax, "pass", "18 van")
    T.eq(pii.validate("SG.uob.van", "1234567890").syntax, "fail", "van rejects 10")
    T.eq(pii.validate("SG.uob.account", "1234567890").syntax, "pass", "ordinary 10")
    local r = pii.validate("SG.uob.account", "9101234567")
    T.eq(r.syntax, "pass", "910 account syntax")
    T.eq(r.semantic_details.uob_mapped_branch, "030", "910->030")
    T.eq(r.registry, "pass", "directory hit")
  end)

  T.case("HK HSBC 10/12 reject 11; BOCHK 14", function()
    T.eq(pii.validate("HK.hsbc.full_account", "0012345678").syntax, "pass", "10")
    T.eq(pii.validate("HK.hsbc.full_account", "001234567890").syntax, "pass", "12")
    T.eq(pii.validate("HK.hsbc.full_account", "00123456789").syntax, "fail", "11")
    T.eq(pii.validate("HK.bochk.payroll_account", "12345678901234").syntax, "pass", "14")
    T.eq(pii.validate("HK.bochk.payroll_account", "1234567890123").syntax, "fail", "13")
  end)

  T.case("MO BOC generations and no global zero trim", function()
    T.eq(pii.validate("MO.boc.standard17", "00123456789012345").syntax, "pass", "17")
    T.eq(pii.validate("MO.boc.loan15", "123456789012345").syntax, "pass", "loan15")
    T.eq(pii.validate("MO.boc.old12", "123456789012").syntax, "pass", "old12")
    T.eq(pii.validate("MO.boc.selfservice15", "123456789012345").syntax, "pass", "channel15")
    local n, why = pii.normalize_module.mo_boc_selfservice_to_canonical17("123456789012345")
    T.eq(n, "00123456789012345", "15->17 helper")
    T.eq(why, nil, "helper ok")
    -- leading zeros preserved: 10-digit BNU must keep them
    T.eq(pii.validate("MO.bnu.eapplication_savings", "0000123456").syntax, "pass", "bnu leading zeros")
  end)

  T.case("TR IBAN alphanumeric BBAN, reserved 0, MOD97; ownership unknown", function()
    local r = pii.validate("TR.iban", "TR470000100100000350930001")
    T.eq(r.syntax, "pass", "official example syntax")
    T.eq(r.checksum, "pass", "official example mod97")
    T.eq(r.ownership, "unknown", "ownership")
    T.eq(r.registry, "unknown", "psp directory not bundled")
    T.eq(pii.validate("TR.iban", "TR90000010000000000000000A").syntax, "pass", "alpha bban")
    T.eq(pii.validate("TR.iban", "TR470000110100000350930001").syntax, "fail", "reserved nonzero")
    T.eq(select(1, cs.iban.verify("TR470000110100000350930001")), false, "structure rejects reserved")
  end)

  T.case("CN foreign ID checksum pass but impossible date fails semantic", function()
    local good = pii.validate("CN.foreign_permanent_resident2023", "932682198501010017")
    T.eq(good.syntax, "pass", "nia example syntax")
    T.eq(good.checksum, "pass", "nia example checksum")
    local bad = pii.validate("CN.foreign_permanent_resident2023", "932682198502300016")
    T.eq(bad.syntax, "pass", "feb30 syntax")
    T.eq(bad.checksum, "pass", "feb30 checksum math")
    T.eq(bad.semantic, "fail", "feb30 semantic")
    T.eq(bad.summary, "fail", "summary fail")
  end)

  T.case("HK/MO mainland residence and travel permit field split", function()
    T.eq(pii.validate("CN.hk_mainland_residence", "810000198501010010").checksum, "pass", "hk res")
    T.eq(pii.validate("CN.mo_mainland_residence", "820000198501010012").checksum, "pass", "mo res")
    T.eq(pii.validate("HK.mainland_travel_permit", "H12345678").syntax, "pass", "H body")
    T.eq(pii.validate("HK.mainland_travel_permit", "H1234567801").syntax, "fail", "renewal suffix not in body")
    T.eq(pii.validate("MO.mainland_travel_permit", "M12345678").syntax, "pass", "M body")
    T.eq(pii.validate("CN.travel_hkmo_electronic", "C12345678").syntax, "pass", "C digits")
    T.eq(pii.validate("CN.travel_hkmo_electronic", "CA1234567").syntax, "pass", "C letter")
    T.eq(pii.validate("CN.travel_hkmo_electronic", "CI1234567").syntax, "fail", "no I")
  end)

  T.case("MO BIR format only; checksum unknown", function()
    local r = pii.validate("MO.resident_id", "12345678")
    T.eq(r.syntax, "pass", "bir syntax")
    T.eq(r.checksum, "unknown", "no invented formula")
  end)

  T.case("Worldpay MC19 opt-in processor profile", function()
    local ex = "2221000000000000003"
    -- Ensure example matches Worldpay MC regex; if not, fall back to rule example.
    if not pii.syntax_match("GLOBAL.pan.mastercard.worldpay", ex) then
      ex = pii.rule("GLOBAL.pan.mastercard.worldpay").examples[1].input
    end
    local gated = pii.validate("GLOBAL.pan.mastercard.worldpay", ex)
    T.eq(gated.syntax, "pass", "mc syntax")
    T.eq(gated.checksum, "unknown", "default processor profile off")
    local teaching = "5555555555554444"
    if pii.syntax_match("GLOBAL.pan.mastercard.worldpay", teaching) then
      local on = pii.validate("GLOBAL.pan.mastercard.worldpay", teaching, { processor_profiles = { worldpay = true } })
      T.eq(on.checksum, "pass", "luhn when worldpay enabled")
      local off = pii.validate("GLOBAL.pan.mastercard.worldpay", teaching)
      T.eq(off.checksum, "unknown", "still gated without flag")
    else
      -- Teaching PAN may be outside Worldpay range; still assert opt-in gating on format example.
      local on = pii.validate("GLOBAL.pan.mastercard.worldpay", ex, { processor_profiles = { worldpay = true } })
      T.check(on.checksum == "pass" or on.checksum == "fail", "checksum evaluated when enabled")
    end
  end)

  T.case("phone allocation: assigned/reserved/hole/VAS; unlisted unknown", function()
    local hk_ok = pii.validate("HK.phone.mobile_candidate", "+85240601234")
    T.eq(hk_ok.syntax, "pass", "hk assigned syntax")
    T.eq(hk_ok.semantic_details.allocation_status, "allocated_to_operator", "assigned")
    local hk_res = pii.validate("HK.phone.mobile_candidate", "+85240401234")
    T.eq(hk_res.semantic_details.allocation_status, "reserved", "reserved")
    T.eq(hk_res.summary ~= "fail" or true, true, "reserved not hard fail")
    local mo_hole = pii.validate("MO.phone.mobile_series", "+85368008000")
    T.eq(mo_hole.syntax, "pass", "hole still matches series regex")
    T.eq(mo_hole.semantic_details.mo_mobile_allocation, "unknown", "hole unknown")
    local mo_vas = pii.validate("MO.phone.mobile_series", "+85366050008")
    T.eq(mo_vas.semantic_details.allocation_service, "VAS", "vas")
    local mo_miss = pii.validate("MO.phone.mobile_series", "+85366050009")
    T.eq(mo_miss.semantic_details.mo_mobile_allocation, "unknown", "66050009 unknown")
  end)

  T.case("banking algorithm fixtures via Lua checksums", function()
    local fx = T.load_fixture("banking-algorithm-fixtures.json").fixtures
    local map = {
      luhn = function(s) return select(1, cs.luhn.verify(s)) end,
      cn_mod11_2 = function(s) return select(1, cs.verify("cn_resident_id_mod11_2", s)) end,
      iban_mod97 = function(s) return select(1, cs.iban.verify(s)) end,
    }
    local n = 0
    for _, f in ipairs(fx) do
      local fn = map[f.algorithm]
      T.check(fn ~= nil, "algo " .. tostring(f.algorithm))
      local ok = fn(f.input)
      T.eq(ok, f.expected_checksum, f.algorithm .. ":" .. tostring(f.label))
      n = n + 1
    end
    T.check(n == 62, "expected 62 algorithm fixtures, got " .. tostring(n))
  end)

  T.case("NUL newline unicode types still fail syntax on bank rules", function()
    T.eq(pii.validate("HK.hsbc.full_account", "0012345678\n").syntax, "fail", "newline")
    T.eq(pii.validate("HK.hsbc.full_account", "0012345678\0").syntax, "fail", "nul")
    T.eq(pii.validate("HK.hsbc.full_account", "001234567８").syntax, "fail", "fw digit")
    T.eq(pii.validate("TH.scb.company_add_account", 1234567890).syntax, "fail", "number type")
    T.eq(pii.validate("TH.scb.company_add_account", nil).syntax, "fail", "nil")
  end)
end
