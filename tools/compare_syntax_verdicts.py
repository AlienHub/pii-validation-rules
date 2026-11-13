#!/usr/bin/env python3
"""Diff the Lua restricted-subset matcher verdicts against native PCRE2 verdicts
over the differential corpus and write reports/lua-vs-pcre2-differential-<runtime>.json.

Usage:
  python3 tools/compare_syntax_verdicts.py --pcre2 reports/pcre2-corpus-verdicts.json \
      --lua reports/lua-syntax-verdicts-lua5.4.json --out reports/lua-vs-pcre2-differential-lua5.4.json
Exit code 1 when any verdict differs or any input is missing on either side.
"""

import argparse
import json
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pcre2", required=True)
    ap.add_argument("--lua", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    p = json.load(open(a.pcre2, encoding="utf-8"))
    l = json.load(open(a.lua, encoding="utf-8"))
    pv = p["corpus_verdicts"]
    lv = l["verdicts"]
    diffs = []
    missing = []
    compared = 0
    agree_match = 0
    agree_nomatch = 0
    for rid, inputs in pv.items():
        lua_rule = lv.get(rid)
        if lua_rule is None:
            missing.append({"rule_id": rid, "side": "lua"})
            continue
        for inp, verdict in inputs.items():
            if inp not in lua_rule:
                missing.append({"rule_id": rid, "input": inp, "side": "lua"})
                continue
            compared += 1
            if lua_rule[inp] != verdict:
                diffs.append({"rule_id": rid, "input": inp, "pcre2": verdict, "lua": lua_rule[inp]})
            elif verdict:
                agree_match += 1
            else:
                agree_nomatch += 1
    for rid in lv:
        if rid not in pv:
            missing.append({"rule_id": rid, "side": "pcre2"})
    out = {
        "stage": "lua_subset_matcher_vs_native_pcre2_differential",
        "run_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "pcre2_version": p["engine_versions"]["PCRE2"],
        "lua_runtime": l.get("runtime"),
        "lua_engine": l.get("engine"),
        "summary": {
            "rules": len(pv),
            "inputs_compared": compared,
            "agree_match": agree_match,
            "agree_nomatch": agree_nomatch,
            "disagreements": len(diffs),
            "missing": len(missing),
        },
        "disagreements": diffs,
        "missing": missing,
    }
    with open(a.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print("lua(%s) vs PCRE2 %s: %d inputs compared, %d match-agreements, %d nomatch-agreements, %d disagreements, %d missing"
          % (l.get("runtime"), p["engine_versions"]["PCRE2"], compared, agree_match, agree_nomatch, len(diffs), len(missing)))
    for d in diffs[:20]:
        print("DIFF", d)
    sys.exit(1 if (diffs or missing) else 0)


if __name__ == "__main__":
    main()
