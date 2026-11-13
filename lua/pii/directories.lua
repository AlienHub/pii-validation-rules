-- Pluggable offline directories (routing / allocation / prefix maps).
--
-- Full bank or regulator tables are NOT bundled when redistribution rights are
-- unclear (notably UOB Appendix A and complete OFCA allocation dumps). Callers
-- inject their own snapshots via set_provider / load_json. Missing directory or
-- a key outside the table yields "unknown" — never "fail" and never an online
-- probe. Portability means an allocation row is not proof of the current carrier.

local json = require("pii.json")

local M = {}

local providers = {}

function M.set_provider(name, provider)
  if type(name) ~= "string" or name == "" then
    error("directory name required", 2)
  end
  if provider ~= nil and type(provider) ~= "table" then
    error("provider must be a table or nil", 2)
  end
  providers[name] = provider
end

function M.get_provider(name)
  return providers[name]
end

function M.clear()
  providers = {}
end

-- load_json(name, path) reads a directory fixture written by the banking import
-- (schema_version directory-1) and registers it under name.
function M.load_json(name, path)
  local doc = json.decode_file(path)
  providers[name] = doc
  return doc
end

local function range_lookup(ranges, value)
  if type(ranges) ~= "table" or type(value) ~= "string" then return nil end
  for _, row in ipairs(ranges) do
    local a, b = row.start, row["end"]
    if type(a) == "string" and type(b) == "string" and a <= value and value <= b then
      return row
    end
  end
  return nil
end

-- lookup(name, key) -> status, detail
-- status: "pass" (found / mapped), "unknown" (no provider or key absent)
function M.lookup(name, key)
  local doc = providers[name]
  if not doc then
    return "unknown", { reason = "directory_not_loaded:" .. tostring(name) }
  end
  if name == "sg_uob_prefix_branch" then
    local map = doc.prefix_to_branch or doc
    local branch = type(map) == "table" and map[key] or nil
    if branch == nil then
      return "unknown", { reason = "prefix_not_in_directory", prefix = key }
    end
    return "pass", { prefix = key, branch = branch, source_date = doc.source_date }
  end
  if name == "hk_mobile_allocation" or name == "mo_mobile_allocation" then
    local row = range_lookup(doc.ranges, key)
    if not row then
      return "unknown", { reason = "number_not_in_directory_snapshot", value = key }
    end
    return "pass", {
      status = row.status,
      service = row.service,
      start = row.start,
      ["end"] = row["end"],
      source_date = doc.source_date,
      portability_note = "allocation_snapshot_not_current_carrier",
    }
  end
  return "unknown", { reason = "unsupported_directory:" .. tostring(name) }
end

M.range_lookup = range_lookup

return M
