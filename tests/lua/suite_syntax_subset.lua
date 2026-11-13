-- Tests for the restricted regex-subset matcher. The expected verdicts for the
-- rule examples are the same ones PCRE2 is tested against; the differential
-- corpus verdicts are written out for tools/compare_syntax_verdicts.py.
return function(T)
  T.suite("syntax_subset")
  local syntax = require("pii.syntax")
  local rules = require("pii.rules").load(T.opts.rules)
  local json = require("pii.json")

  T.case("all rule patterns compile in the restricted subset", function()
    for _, id in ipairs(rules:ids()) do
      local r = rules:get(id)
      local ok, err = pcall(syntax.compile, r.regex_pcre2)
      T.check(ok, id .. ": " .. tostring(err))
    end
  end)

  T.case("unsupported constructs raise instead of silently matching", function()
    local bad = {
      "\\A(?:\\d{3})\\z", "^[0-9]{3}$", "\\A(?:[0-9]+)\\z", "\\A(?:[0-9]*)\\z", "\\A(?:(?:ab)+)\\z",
      "\\A(?:[^0-9])\\z", "\\A(?:a.b)\\z", "\\A(?:[0-9]{3,})\\z", "\\A(?:(a|b))\\z", "\\A(?:\\w)\\z",
      "\\A(?:[0-9]{999})\\z", "[0-9]{3}",
    }
    for _, p in ipairs(bad) do
      local ok, err = pcall(syntax.compile, p)
      T.check(not ok and string.find(tostring(err), "unsupported_regex_construct", 1, true), "rejects " .. p)
    end
  end)

  T.case("rule examples and negative examples match the expected verdicts", function()
    for _, id in ipairs(rules:ids()) do
      local r = rules:get(id)
      local c = syntax.compile(r.regex_pcre2)
      for _, e in ipairs(r.examples) do
        T.eq(c:fullmatch(e.input), e.expected_syntax, id .. " example " .. e.input)
      end
      for _, e in ipairs(r.negative_syntax_examples) do
        T.eq(c:fullmatch(e.input), e.expected_syntax, id .. " negative " .. string.format("%q", e.input) .. " (" .. tostring(e.reason) .. ")")
      end
    end
  end)

  T.case("length bounds are derived correctly", function()
    local mn, mx = syntax.length_bounds("\\A(?:[0-9]{17}[0-9X])\\z")
    T.eq(mn, 18, "cn min"); T.eq(mx, 18, "cn max")
    mn, mx = syntax.length_bounds("\\A(?:(?:SG|OG)[0-9]{9,11})\\z")
    T.eq(mn, 11, "my legacy min"); T.eq(mx, 13, "my legacy max")
    mn, mx = syntax.length_bounds("\\A(?:\\+7[0-9]{1,14})\\z")
    T.eq(mn, 3, "kz phone min"); T.eq(mx, 16, "kz phone max")
  end)

  T.case("byte semantics: newline, NUL, non-ASCII never match; non-string is false", function()
    local c = syntax.compile("\\A(?:[0-9]{3})\\z")
    T.eq(c:fullmatch("123"), true, "plain")
    T.eq(c:fullmatch("123\n"), false, "trailing newline (\\z, not $)")
    T.eq(c:fullmatch("12\0"), false, "NUL")
    T.eq(c:fullmatch("12\239\188\145"), false, "full-width digit")
    T.eq(c:fullmatch(123), false, "number")
    T.eq(c:fullmatch(nil), false, "nil")
    local alt = syntax.compile("\\A(?:(?:C|CS)[0-9]{2}0)\\z")
    T.eq(alt:fullmatch("CS120"), true, "backtracking across alternation")
    T.eq(alt:fullmatch("C120"), true, "shorter alternative")
    T.eq(alt:fullmatch("CS12"), false, "missing trailing literal")
  end)

  T.case("differential corpus verdicts recorded for PCRE2 comparison", function()
    local corpus = T.load_fixture("regex-differential-corpus.json")
    local verdicts = {}
    local n = 0
    for _, id in ipairs(rules:ids()) do
      local r = rules:get(id)
      local c = syntax.compile(r.regex_pcre2)
      local vd = {}
      for _, input in ipairs(corpus.rules[id] or {}) do
        vd[input] = c:fullmatch(input)
        n = n + 1
      end
      verdicts[id] = vd
    end
    T.check(n > 5000, "corpus evaluated (" .. n .. " inputs)")
    if T.opts.syntax_verdicts then
      T.write_json(T.opts.syntax_verdicts, {
        stage = "lua_restricted_subset_matcher_verdicts",
        runtime = (rawget(_G, "jit") and jit.version) or _VERSION,
        engine = syntax.engine_description,
        inputs = n,
        verdicts = verdicts,
      })
    end
  end)
end
