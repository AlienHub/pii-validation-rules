return function(T)
  T.suite("checksum_fixtures")
  local cs = require("pii.checksums")
  local fx = T.load_fixture("checksum-vectors.json")

  for _, a in ipairs(fx.algorithms) do
    local aid = a.algorithm_id
    T.case(aid .. " fixture cases (positive + check mutation)", function()
      T.check(cs.by_id[aid] ~= nil, "algorithm registered: " .. aid)
      for _, c in ipairs(a.cases) do
        if aid == "icao9303_check_digit" then
          local ok = cs.icao9303.verify(c.field, c.check_digit)
          T.eq(ok, c.expected_arithmetic, "icao field " .. c.field .. " check " .. c.check_digit)
          local ok2 = cs.icao9303.verify(c.field, c.invalid_check_digit)
          T.eq(ok2, c.invalid_expected, "icao field " .. c.field .. " invalid check " .. c.invalid_check_digit)
          T.eq(cs.icao9303.verify_with_trailing_digit(c.field .. c.check_digit), c.expected_arithmetic, "trailing-digit helper")
        else
          local ok = cs.verify(aid, c.input)
          T.eq(ok, c.expected_arithmetic, aid .. " input " .. c.input)
          local ok2 = cs.verify(aid, c.mutated_input)
          T.eq(ok2, c.mutated_expected, aid .. " mutated " .. c.mutated_input)
        end
      end
    end)
  end

  T.case("fixture file covers every registered algorithm", function()
    local seen = {}
    for _, a in ipairs(fx.algorithms) do seen[a.algorithm_id] = true end
    for _, id in ipairs(cs.ids()) do
      T.check(seen[id], "fixture cases exist for " .. id)
    end
  end)
end
