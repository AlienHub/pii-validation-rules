-- Loads rules/*.json and rules/algorithms.json into an in-memory registry.
-- The JSON files are the single source of truth; nothing is duplicated in Lua.

local json = require("pii.json")

local M = {}

-- Jurisdiction files shipped in rules/. Kept explicit because plain Lua has no
-- portable directory listing; tools/check_rules.py verifies this list matches the
-- files on disk.
M.jurisdiction_files = {
  "AE", "BD", "BH", "BN", "CN", "GLOBAL", "HK", "ID", "IL", "IN", "IQ", "IR", "JO", "JP", "KH", "KR",
  "KW", "KZ", "LA", "LB", "LK", "MM", "MN", "MO", "MY", "NP", "OM", "PH", "PK", "PS", "QA", "SA", "SG",
  "SY", "TH", "TR", "TW", "UZ", "VN", "YE",
}

local Registry = {}
Registry.__index = Registry

-- load(rules_dir) -> registry ; rules_dir defaults to "rules"
function M.load(rules_dir)
  rules_dir = rules_dir or "rules"
  local reg = setmetatable({
    rules_dir = rules_dir,
    rules = {},          -- id -> rule (with .jurisdiction, .file_version added)
    order = {},          -- ids in file order
    algorithms = {},     -- id -> algorithm spec
    jurisdictions = {},  -- code -> file header (without rules)
  }, Registry)

  local algo_doc = json.decode_file(rules_dir .. "/algorithms.json")
  reg.algorithms_version = algo_doc.version
  for _, a in ipairs(algo_doc.algorithms) do
    reg.algorithms[a.id] = a
  end

  for _, code in ipairs(M.jurisdiction_files) do
    local doc = json.decode_file(rules_dir .. "/" .. code .. ".json")
    local header = {}
    for k, v in pairs(doc) do
      if k ~= "rules" then header[k] = v end
    end
    reg.jurisdictions[code] = header
    for _, r in ipairs(doc.rules) do
      if reg.rules[r.id] then error("duplicate rule id " .. r.id) end
      r.jurisdiction = code
      r.file_version = doc.version
      reg.rules[r.id] = r
      reg.order[#reg.order + 1] = r.id
    end
  end
  return reg
end

function Registry:get(rule_id)
  return self.rules[rule_id]
end

function Registry:algorithm(id)
  return self.algorithms[id]
end

function Registry:ids()
  return self.order
end

-- rules_for(jurisdiction, pii_type?) -> array of rules
function Registry:rules_for(jurisdiction, pii_type)
  local out = {}
  for _, id in ipairs(self.order) do
    local r = self.rules[id]
    if r.jurisdiction == jurisdiction and (pii_type == nil or r.pii_type == pii_type) then
      out[#out + 1] = r
    end
  end
  return out
end

-- count_by_status() -> { status = n }
function Registry:count_by_status()
  local c = {}
  for _, id in ipairs(self.order) do
    local s = self.rules[id].status
    c[s] = (c[s] or 0) + 1
  end
  return c
end

return M
