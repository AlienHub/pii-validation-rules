-- Property-style tests shared by every checksum algorithm: determinism,
-- non-string / nil inputs, bad lengths, illegal ASCII characters, Unicode digits,
-- preservation of leading zeros, and (where the scheme guarantees it) detection
-- of all single-character substitutions / adjacent transpositions.
return function(T)
  T.suite("checksum_properties")
  local cs = require("pii.checksums")
  local east, se, west = cs.east_asia, cs.southeast_asia, cs.west_central_asia

  -- one known-good value per algorithm (all synthetic / published examples)
  local GOOD = {
    cn_resident_id_mod11_2 = "11010519491231002X",
    cn_uscc_mod31 = "91110101ABCDEFGH1E",
    th_mod11 = "0991123456781",
    jp_mynumber = "123456789018",
    jp_corporate_number = "8700110005901",
    kz_iin = "123456789013",
    luhn = "4242424242424242",
    iban_mod97 = "AE151111111111111111111",
    icao9303_check_digit = "L898902C36",
    verhoeff = "234567890124",
    tr_tckn = "12345678950",
    tr_vkn = "0010213576",
    sg_nric_fin_reconstructed = "S1234567D",
    tw_citizen_new_ui = "A100000001",
    hkid_mod11 = "A1234563",
    ir_national_mod11 = "0012345679",
    kr_rrn_legacy = "9001011234568",
  }

  local function verify(aid, v)
    return cs.verify(aid, v)
  end

  -- algorithms without a fixed length: a truncated value may be valid by chance
  local VARIABLE_LENGTH = { luhn = true, icao9303_check_digit = true, verhoeff = true }

  local UNICODE_DIGITS = { "\239\188\145", "\217\161", "\224\185\145", "\224\165\167" } -- １ ١ ๑ १

  for _, aid in ipairs(cs.ids()) do
    local good = GOOD[aid]
    T.case(aid .. ": determinism and accepted sample", function()
      local a, b = verify(aid, good), verify(aid, good)
      T.eq(a, true, "sample accepted")
      T.eq(b, true, "second call identical")
    end)

    T.case(aid .. ": nil, non-string and empty inputs are rejected with a reason", function()
      for _, bad in ipairs({ nil, 123456789, true, {}, 1.5 }) do
        local ok, why = verify(aid, bad)
        T.eq(ok, false, aid .. " rejects " .. type(bad))
        T.eq(why, "not_a_string", aid .. " reason for " .. type(bad))
      end
      local ok, why = verify(aid, "")
      T.eq(ok, false, "empty rejected")
      T.check(why == "bad_length", "empty reason is bad_length, got " .. tostring(why))
    end)

    T.case(aid .. ": wrong lengths are rejected", function()
      if VARIABLE_LENGTH[aid] then
        T.eq(verify(aid, string.sub(good, #good)), false, "single character rejected")
        T.eq(select(2, verify(aid, string.sub(good, #good))), "bad_length", "reason")
      else
        local shorter = string.sub(good, 1, #good - 1)
        local longer = good .. string.sub(good, #good)
        T.eq(verify(aid, shorter), false, "one char shorter")
        T.eq(select(2, verify(aid, shorter)), "bad_length", "shorter reason")
        T.eq(verify(aid, longer), false, "one char longer")
        T.eq(verify(aid, string.sub(good, 2)), false, "first char dropped")
      end
    end)

    T.case(aid .. ": illegal ASCII characters are rejected", function()
      for _, ch in ipairs({ " ", "-", "!", "a", "x", "*", "\n", "\0" }) do
        local mutated = ch .. string.sub(good, 2)
        T.eq(verify(aid, mutated), false, aid .. " rejects leading " .. string.format("%q", ch))
        local mid = string.sub(good, 1, 3) .. ch .. string.sub(good, 5)
        T.eq(verify(aid, mid), false, aid .. " rejects middle " .. string.format("%q", ch))
      end
      -- lowercase form of the whole value must not be accepted when letters are involved
      if string.lower(good) ~= good then
        T.eq(verify(aid, string.lower(good)), false, aid .. " rejects lowercase")
      end
    end)

    T.case(aid .. ": Unicode digits and format characters are rejected", function()
      for _, u in ipairs(UNICODE_DIGITS) do
        -- same byte length is irrelevant: any non-ASCII byte must fail
        local mutated = u .. string.sub(good, 2)
        T.eq(verify(aid, mutated), false, aid .. " rejects unicode digit prefix")
        local replaced = string.sub(good, 1, #good - 1) .. u
        T.eq(verify(aid, replaced), false, aid .. " rejects unicode digit as check")
      end
      T.eq(verify(aid, "\226\128\139" .. good), false, "zero-width space rejected")
      T.eq(verify(aid, good .. "\226\128\139"), false, "trailing zero-width space rejected")
    end)
  end

  T.case("leading zeros are preserved by generators (no numeric conversion)", function()
    T.eq(se.th_mod11.check_digit("000000000000"), "1", "th all-zero body")
    T.eq(cs.luhn.check_digit("0000000"), "0", "luhn zeros")
    T.eq(west.ir_national_mod11.check_digit("000000001"), "9", "ir leading zeros")
    T.eq(west.tr_vkn.check_digit("000000000"), "1", "vkn zeros")
    T.eq(#west.tr_tckn.complete("100000000"), 11, "tckn keeps 11 chars")
    T.eq(east.jp_mynumber.check_digit("00000000000"), "0", "mynumber zeros")
    T.eq(east.jp_corporate_number.check_digit("000000000000"), "9", "corporate zeros -> 9 - 0")
    T.eq(cs.verhoeff.check_digit("00000000000"), "3", "verhoeff zeros")
    T.eq(cs.iban.check_digits("AE", "0000000000000000000"), "63", "iban zeros")
    T.eq(west.kz_iin.check_digit("00000000000"), "0", "kz zeros")
    T.eq(east.cn_resident_id_mod11_2.check_character("00000000000000000"), "1", "cn zeros -> index 0 -> 1")
    T.eq(cs.verify("th_mod11", "0000000000001"), true, "th zero body verifies")
  end)

  T.case("ISO 7064 / Luhn / Verhoeff schemes detect every single-character substitution", function()
    local function all_single_substitutions_detected(aid, value, alphabet)
      for i = 1, #value do
        for j = 1, #alphabet do
          local c = string.sub(alphabet, j, j)
          if c ~= string.sub(value, i, i) then
            local m = string.sub(value, 1, i - 1) .. c .. string.sub(value, i + 1)
            local ok = verify(aid, m)
            T.check(ok == false, aid .. " must detect substitution at " .. i .. " -> " .. c)
          end
        end
      end
    end
    all_single_substitutions_detected("cn_resident_id_mod11_2", "110105199001010010", "0123456789")
    all_single_substitutions_detected("cn_uscc_mod31", "91110101ABCDEFGH1E", east.cn_uscc_mod31.alphabet)
    all_single_substitutions_detected("luhn", "4242424242424242", "0123456789")
    all_single_substitutions_detected("verhoeff", "234567890124", "0123456789")
    all_single_substitutions_detected("iban_mod97", "AE151111111111111111111", "0123456789")
  end)

  T.case("JP corporate number (mod 9) cannot distinguish 0 from 9: documented blind spot", function()
    T.eq(cs.verify("jp_corporate_number", "8700110005901"), true, "official example")
    T.eq(cs.verify("jp_corporate_number", "8709110005901"), true, "0->9 substitution in the base is undetected by design of mod 9")
    T.eq(cs.verify("jp_corporate_number", "8710110005901"), false, "other substitutions are detected")
  end)

  T.case("Verhoeff detects every adjacent transposition; Luhn misses only 09<->90", function()
    local v = "234567890124"
    for i = 1, #v - 1 do
      local a, b = string.sub(v, i, i), string.sub(v, i + 1, i + 1)
      if a ~= b then
        local m = string.sub(v, 1, i - 1) .. b .. a .. string.sub(v, i + 2)
        T.eq(cs.verify("verhoeff", m), false, "verhoeff transposition at " .. i)
      end
    end
    T.eq(cs.verify("luhn", "0900000000000001"), true, "luhn valid with 09")
    T.eq(cs.verify("luhn", "9000000000000001"), true, "luhn 09<->90 transposition undetected (documented blind spot)")
  end)

  T.case("KZ two-stage: bodies with no valid digit are rejected for all ten digits", function()
    local body = "12345600048"
    local c, why = west.kz_iin.check_digit(body)
    T.eq(c, nil, "no check digit")
    T.eq(why, "no_valid_check_digit", "reason")
    for d = 0, 9 do
      local ok, r = cs.verify("kz_iin", body .. d)
      T.eq(ok, false, "digit " .. d .. " rejected")
      T.eq(r, "no_valid_check_digit", "reason for digit " .. d)
    end
    T.eq(west.kz_iin.check_digit("12345600040"), "5", "second round remainder 5")
  end)

  T.case("IBAN: registry subset, structure classes and check-digit range", function()
    local ok, why = cs.iban.verify("DE89370400440532013000")
    T.eq(ok, false, "DE not in subset")
    T.eq(why, "country_not_in_registry_subset", "reason")
    ok, why = cs.iban.verify("AE00" .. string.rep("1", 19))
    T.eq(why, "check_digits_out_of_range", "00 rejected")
    ok, why = cs.iban.verify("IQ09ZZZZ1111111111111A1")
    T.eq(why, "bad_character", "letter in 12!n account field")
    ok, why = cs.iban.verify("BH081111ZZZZZZZZZZZZZZ")
    T.eq(why, "bad_character", "digits in 4!a bank code")
    T.eq(select(2, cs.iban.verify("AE15111111111111111111")), "bad_length", "AE 22 chars")
    T.eq(cs.iban.mod97("AE151111111111111111111"), 1, "streamed remainder")
    T.eq(cs.iban.registry.YE.total, 30, "YE length 30")
    T.eq(cs.iban.registry.OM.total, 23, "OM length 23")
    T.eq(cs.iban.registry.MN.total, 20, "MN length 20")
  end)

  T.case("SG: series detection and experimental flag are separate from arithmetic", function()
    local sg = se.sg_nric_fin_reconstructed
    T.eq(sg.series_of("M1234567B"), "M", "M series")
    T.eq(sg.is_experimental_series("M"), true, "M experimental")
    T.eq(sg.is_experimental_series("S"), false, "S not experimental")
    T.eq(sg.check_letter("M", "1234567"), "K", "reconstructed M table gives K for ICA example digits")
    T.eq(cs.verify("sg_nric_fin_reconstructed", "M1234567B"), false, "arithmetic alone disagrees with ICA illustration")
    T.eq(select(2, cs.verify("sg_nric_fin_reconstructed", "A1234567B")), "bad_character", "unknown prefix")
  end)

  T.case("TR: TCKN leading zero and YKN separation", function()
    local ok, why = cs.verify("tr_tckn", "02345678950")
    T.eq(ok, false, "leading zero")
    T.eq(why, "leading_zero_not_allowed", "reason")
    T.eq(cs.by_id.tr_ykn, nil, "no YKN algorithm is registered")
  end)

  T.case("ICAO: composite check digit over TD3 sample slices", function()
    local fx = T.load_fixture("edge-cases.json").icao_composite
    local line2 = fx.line2
    local parts = {}
    for _, s in ipairs(fx.slices) do parts[#parts + 1] = string.sub(line2, s[1], s[2]) end
    local composite = table.concat(parts)
    T.eq(cs.icao9303.check_digit(composite), fx.expected_composite_check, "composite check digit")
    for _, f in ipairs(fx.field_checks) do
      T.eq(cs.icao9303.check_digit(f.field), f.check, "field " .. f.field)
    end
    T.eq(select(2, cs.icao9303.check_digit("l898902c3")), "bad_character", "lowercase rejected")
    T.eq(select(2, cs.icao9303.verify("L898902C3", "<")), "bad_check_character", "filler is not accepted as a check digit here")
  end)

  T.case("HKID: single-letter prefix uses 36, two-letter prefix does not", function()
    T.eq(east.hkid_mod11.check_character("A123456"), "3", "single letter")
    T.eq(east.hkid_mod11.check_character("AB123456"), "9", "two letters")
    T.eq(east.hkid_mod11.check_character("A007919"), "A", "value 10 -> A")
  end)
end
