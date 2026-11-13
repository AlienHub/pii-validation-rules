#!/usr/bin/env python3
"""Run the 458 banking deep-research format fixtures against *repo* rules.

Positives assert syntax only. They must NOT be treated as checksum passes.
TR.iban.2021 fixtures are aliased to TR.iban (API-compatible merge).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "pcre2"))

# Reuse the ctypes PCRE2 helper from the main runner if present; else minimal copy.
import ctypes
import ctypes.util

ALIAS = {"TR.iban.2021": "TR.iban"}


def load_pcre2():
    lib = ctypes.CDLL(ctypes.util.find_library("pcre2-8") or "libpcre2-8.so.0")
    lib.pcre2_compile_8.argtypes = [
        ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p,
    ]
    lib.pcre2_compile_8.restype = ctypes.c_void_p
    lib.pcre2_match_data_create_from_pattern_8.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.pcre2_match_data_create_from_pattern_8.restype = ctypes.c_void_p
    lib.pcre2_match_8.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_size_t,
        ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p,
    ]
    lib.pcre2_match_8.restype = ctypes.c_int
    lib.pcre2_code_free_8.argtypes = [ctypes.c_void_p]
    lib.pcre2_match_data_free_8.argtypes = [ctypes.c_void_p]
    return lib


def load_rules():
    rules = {}
    for name in os.listdir(os.path.join(ROOT, "rules")):
        if not name.endswith(".json") or name == "algorithms.json":
            continue
        doc = json.load(open(os.path.join(ROOT, "rules", name), encoding="utf-8"))
        for r in doc["rules"]:
            rules[r["id"]] = r
    return rules


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=os.path.join(ROOT, "reports", "banking-format-report.json"))
    args = ap.parse_args()

    rules = load_rules()
    fixtures = json.load(open(os.path.join(ROOT, "fixtures", "banking-format-fixtures.json"), encoding="utf-8"))["fixtures"]
    lib = load_pcre2()

    compiled = {}
    failures = []
    t0 = time.perf_counter()
    for fx in fixtures:
        rid = ALIAS.get(fx["rule_id"], fx["rule_id"])
        rule = rules.get(rid)
        if not rule:
            failures.append({"rule_id": fx["rule_id"], "error": "missing_rule", "mapped": rid})
            continue
        if rid not in compiled:
            err = ctypes.c_int()
            off = ctypes.c_size_t()
            raw = rule["regex_pcre2"].encode()
            code = lib.pcre2_compile_8(raw, len(raw), 0, ctypes.byref(err), ctypes.byref(off), None)
            if not code:
                failures.append({"rule_id": rid, "error": "compile", "err": err.value})
                continue
            md = lib.pcre2_match_data_create_from_pattern_8(code, None)
            compiled[rid] = (code, md, re.compile(rule["python_fullmatch_body"]))
        code, md, pyre = compiled[rid]
        b = fx["input"].encode("utf-8", errors="surrogateescape")
        pcmatch = lib.pcre2_match_8(code, b, len(b), 0, 0, md, None) >= 0
        pymatch = pyre.fullmatch(fx["input"]) is not None
        expect = bool(fx["expect_syntax"])
        if not (pcmatch == pymatch == expect):
            failures.append({
                "rule_id": rid,
                "input_len": len(fx["input"]),
                "kind": fx["kind"],
                "expect_syntax": expect,
                "pcre2": pcmatch,
                "python": pymatch,
            })

    for code, md, _ in compiled.values():
        lib.pcre2_match_data_free_8(md)
        lib.pcre2_code_free_8(code)

    elapsed = time.perf_counter() - t0
    report = {
        "fixture_count": len(fixtures),
        "unique_rules_compiled": len(compiled),
        "passed": len(failures) == 0,
        "failures": failures[:50],
        "failure_count": len(failures),
        "elapsed_seconds": round(elapsed, 6),
        "note": "syntax-only; checksum not asserted from format fixtures",
        "alias": ALIAS,
    }
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    json.dump(report, open(args.report, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    open(args.report, "a", encoding="utf-8").write("\n")
    print(
        "banking format fixtures: %d cases, %d compiled rules, %d failures, %.3fs"
        % (len(fixtures), len(compiled), len(failures), elapsed)
    )
    if failures:
        for f in failures[:20]:
            print(" -", f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
