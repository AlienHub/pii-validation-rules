-- Runs fixtures/edge-cases.json through pii.validate and compares the layered
-- results (syntax / checksum / semantic / summary / reasons / warnings).
return function(T)
  T.suite("edge_cases")
  local pii = require("pii")
  pii.load(T.opts.rules)
  local json = require("pii.json")
  local fx = T.load_fixture("edge-cases.json")

  local function contains(list, needle)
    for _, w in ipairs(list) do
      if string.find(w, needle, 1, true) then return true end
    end
    return false
  end

  for _, c in ipairs(fx.cases) do
    T.case(c.id, function()
      local opts = {}
      for k, v in pairs(c.options or {}) do opts[k] = v end
      local r = pii.validate(c.rule_id, c.input, opts)
      local e = c.expect
      for _, layer in ipairs({ "syntax", "checksum", "semantic", "summary", "syntax_error", "checksum_reason" }) do
        if e[layer] ~= nil then
          T.eq(r[layer], e[layer], c.id .. " " .. layer)
        end
      end
      if e.transformations then
        T.eq(json.encode(r.transformations), json.encode(e.transformations), c.id .. " transformations")
      end
      if e.warning_contains then
        T.check(contains(r.warnings, e.warning_contains), c.id .. " warning contains " .. e.warning_contains .. " in " .. json.encode(r.warnings))
      end
      if e.warning_not_contains then
        T.check(not contains(r.warnings, e.warning_not_contains), c.id .. " warning must not contain " .. e.warning_not_contains)
      end
      T.eq(r.issuer_verification, "unknown", c.id .. " issuer verification always unknown")
    end)
  end
end
