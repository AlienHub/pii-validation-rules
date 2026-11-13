#!/usr/bin/env python3
"""Lint rules/*.json, rules/algorithms.json, research/coverage.json and research/sources.json.

Checks: unique ids, vocabulary, regex contract (\\A(?:...)\\z, explicit [0-9], no \\d),
Python compile + example verdicts, algorithm/policy references, source references,
coverage <-> rules consistency, the Lua jurisdiction file list, and a privacy scan
(no e-mail addresses / phone-contact strings in committed text files).
Exit code 1 on any problem.
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STATUS = {"syntax_supported", "historical_syntax", "candidate_profile", "country_code_envelope_only", "dated_numbering_profile"}
PII_TYPES = {"national_id", "resident_id", "tax_id", "tax_id_entity", "passport", "phone", "iban", "payment_card", "passport_mrz_field"}
CHECKSUM_STATUS = {"algorithm_available", "none_per_source", "not_established", "not_applicable"}
POLICIES = {"enabled", "opt_in_secondary", "opt_in_secondary_m_series_experimental", "explicit_legacy_regime"}
COVERAGE_STATUS = {"researched_partial", "unsupported_insufficient_primary_spec", "not_implemented_not_fully_researched", "out_of_requested_named_scope_backlog"}

problems = []


def problem(msg):
    problems.append(msg)


def main():
    algo_doc = json.load(open(os.path.join(ROOT, "rules", "algorithms.json"), encoding="utf-8"))
    algos = {a["id"]: a for a in algo_doc["algorithms"]}
    for aid, a in algos.items():
        if a["default_policy"] not in POLICIES:
            problem("algorithm %s: bad default_policy %s" % (aid, a["default_policy"]))
        if not a.get("source_ids"):
            problem("algorithm %s: no sources" % aid)
        if not a.get("lua_module", "").startswith("pii.checksums."):
            problem("algorithm %s: lua_module missing" % aid)

    sources = {s["id"]: s for s in json.load(open(os.path.join(ROOT, "research", "sources.json"), encoding="utf-8"))["sources"]}

    rule_files = sorted(f for f in glob.glob(os.path.join(ROOT, "rules", "*.json")) if not f.endswith("algorithms.json"))
    codes_on_disk = [os.path.basename(f)[:-5] for f in rule_files]

    lua_rules = open(os.path.join(ROOT, "lua", "pii", "rules.lua"), encoding="utf-8").read()
    m = re.search(r"jurisdiction_files = \{(.*?)\}", lua_rules, re.S)
    lua_codes = re.findall(r'"([A-Z]+)"', m.group(1))
    if sorted(lua_codes) != sorted(codes_on_disk):
        problem("lua/pii/rules.lua jurisdiction_files %s != files on disk %s" % (sorted(lua_codes), sorted(codes_on_disk)))

    rules = {}
    status_counts = {}
    for f in rule_files:
        doc = json.load(open(f, encoding="utf-8"))
        code = os.path.basename(f)[:-5]
        if doc["jurisdiction"] != code:
            problem("%s: jurisdiction field %s != filename" % (f, doc["jurisdiction"]))
        if doc.get("schema_version") != "pii-rules-1":
            problem("%s: schema_version" % f)
        for r in doc["rules"]:
            rid = r["id"]
            if rid in rules:
                problem("duplicate rule id %s" % rid)
            rules[rid] = r
            if not rid.startswith(code + "."):
                problem("%s: id prefix != jurisdiction %s" % (rid, code))
            if r["status"] not in STATUS:
                problem("%s: bad status %s" % (rid, r["status"]))
            status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1
            if r["pii_type"] not in PII_TYPES:
                problem("%s: bad pii_type %s" % (rid, r["pii_type"]))
            pat = r["regex_pcre2"]
            if not (pat.startswith("\\A(?:") and pat.endswith(")\\z")):
                problem("%s: regex not wrapped \\A(?:...)\\z" % rid)
            if re.search(r"\\[dws]", pat):
                problem("%s: shorthand class in regex" % rid)
            if pat[5:-3] != r["python_fullmatch_body"]:
                problem("%s: python_fullmatch_body != PCRE2 body" % rid)
            if re.search(r"\{\d+,\}|[*+?]", pat.replace("\\+", "").replace("(?:", "(")):
                problem("%s: unbounded quantifier" % rid)
            try:
                pyre = re.compile(r["python_fullmatch_body"])
            except re.error as e:
                problem("%s: python compile error %s" % (rid, e))
                continue
            for e in r["examples"]:
                if (pyre.fullmatch(e["input"]) is not None) != e["expected_syntax"]:
                    problem("%s: example %r verdict mismatch" % (rid, e["input"]))
                if "provenance" not in e:
                    problem("%s: example without provenance" % rid)
            if not r["examples"]:
                problem("%s: no positive examples" % rid)
            for e in r["negative_syntax_examples"]:
                if pyre.fullmatch(e["input"]) is not None:
                    problem("%s: negative example %r matches" % (rid, e["input"]))
            cs = r.get("checksum", {})
            if cs.get("status") not in CHECKSUM_STATUS:
                problem("%s: bad checksum.status %s" % (rid, cs.get("status")))
            if cs.get("status") == "algorithm_available":
                if cs.get("algorithm") not in algos:
                    problem("%s: unknown algorithm %s" % (rid, cs.get("algorithm")))
                if cs.get("policy") not in POLICIES:
                    problem("%s: bad policy %s" % (rid, cs.get("policy")))
                if not cs.get("evidence"):
                    problem("%s: missing checksum evidence" % rid)
            elif any(k in cs for k in ("algorithm", "policy")):
                problem("%s: algorithm fields on non-available checksum" % rid)
            if not r.get("source_ids"):
                problem("%s: no source_ids" % rid)
            for sid in r.get("source_ids", []):
                if sid not in sources:
                    problem("%s: unknown source id %s" % (rid, sid))
            urls = [sources[s]["url"] for s in r.get("source_ids", []) if s in sources]
            if urls != r.get("source_urls"):
                problem("%s: source_urls out of sync with sources.json" % rid)
            if not r.get("notes_zh"):
                problem("%s: missing notes_zh" % rid)
            if not r.get("accessed_on"):
                problem("%s: missing accessed_on" % rid)

    cov = json.load(open(os.path.join(ROOT, "research", "coverage.json"), encoding="utf-8"))
    referenced = set()
    if len(cov["jurisdictions"]) != cov["inventory_total"]:
        problem("coverage inventory_total mismatch")
    for j in cov["jurisdictions"]:
        for cat, cell in j["coverage"].items():
            if cell["status"] not in COVERAGE_STATUS:
                problem("coverage %s/%s: bad status %s" % (j["jurisdiction"], cat, cell["status"]))
            for rid in cell["rule_ids"]:
                if rid not in rules:
                    problem("coverage %s/%s references unknown rule %s" % (j["jurisdiction"], cat, rid))
                referenced.add(rid)
            if cell["rule_ids"] and cell["status"] != "researched_partial":
                problem("coverage %s/%s has rules but status %s" % (j["jurisdiction"], cat, cell["status"]))
            if not cell["rule_ids"] and cell["status"] == "researched_partial":
                problem("coverage %s/%s researched_partial without rules" % (j["jurisdiction"], cat))
    for rid in rules:
        if not rid.startswith("GLOBAL.") and rid not in referenced:
            problem("rule %s not referenced in coverage.json" % rid)

    # privacy scan: no e-mail addresses or contact phone markers in committed text
    email_re = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    for pattern in ("rules/*.json", "research/*", "fixtures/*.json", "docs/*", "README.md", "lua/pii/*.lua", "lua/pii/checksums/*.lua", "tests/lua/*.lua", "tools/*.py"):
        for f in glob.glob(os.path.join(ROOT, pattern)):
            if os.path.isdir(f):
                continue
            txt = open(f, encoding="utf-8", errors="replace").read()
            for mm in email_re.finditer(txt):
                problem("%s: e-mail-like string %s" % (os.path.relpath(f, ROOT), mm.group(0)))
            if re.search(r"(?i)\btel:\+?\d", txt):
                problem("%s: tel: contact string" % os.path.relpath(f, ROOT))

    # forbidden artefacts
    for bad_dir in ("sources", "extracts"):
        if os.path.isdir(os.path.join(ROOT, bad_dir)):
            problem("directory %s/ must not be committed" % bad_dir)
    for f in glob.glob(os.path.join(ROOT, "**", "*.pdf"), recursive=True):
        problem("PDF committed: %s" % f)
    if os.path.exists(os.path.join(ROOT, "LICENSE")):
        problem("LICENSE file present but no license was requested")

    print("rules: %d in %d jurisdiction files; algorithms: %d; sources: %d; coverage entries: %d"
          % (len(rules), len(rule_files), len(algos), len(sources), len(cov["jurisdictions"])))
    print("rules by status:", json.dumps(status_counts, sort_keys=True))
    if problems:
        print("%d problem(s):" % len(problems))
        for p in problems:
            print(" -", p)
        sys.exit(1)
    print("check_rules: OK")


if __name__ == "__main__":
    main()
