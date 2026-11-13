#!/usr/bin/env python3
"""Run 62 banking algorithm fixtures via the independent Python reference_impl.

Does not treat format-fixture positives as checksum passes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import reference_impl as R  # noqa: E402


def verify_luhn(s: str) -> bool:
    return isinstance(s, str) and re.fullmatch(r"[0-9]{2,19}", s) is not None and R.luhn_valid(s)


def verify_cn(s: str) -> bool:
    if not isinstance(s, str) or re.fullmatch(r"[0-9]{17}[0-9X]", s) is None:
        return False
    return R.cn_resident_check(s[:17]) == s[-1]


def verify_iban(s: str) -> bool:
    if not isinstance(s, str) or re.fullmatch(r"TR[0-9]{2}[0-9]{5}0[A-Z0-9]{16}", s) is None:
        return False
    cd = int(s[2:4])
    if cd < 2 or cd > 98:
        return False
    return R.iban_mod97(s) == 1


FUNCS = {
    "luhn": verify_luhn,
    "cn_mod11_2": verify_cn,
    "iban_mod97": verify_iban,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=os.path.join(ROOT, "reports", "banking-algorithm-report.json"))
    args = ap.parse_args()

    fixtures = json.load(
        open(os.path.join(ROOT, "fixtures", "banking-algorithm-fixtures.json"), encoding="utf-8")
    )["fixtures"]

    failures = []
    t0 = time.perf_counter()
    for fx in fixtures:
        fn = FUNCS.get(fx["algorithm"])
        if not fn:
            failures.append({"algorithm": fx["algorithm"], "error": "missing_impl"})
            continue
        got = fn(fx["input"])
        if bool(got) != bool(fx["expected_checksum"]):
            failures.append({
                "algorithm": fx["algorithm"],
                "label": fx.get("label"),
                "expected": fx["expected_checksum"],
                "got": bool(got),
                "provenance": fx.get("provenance"),
            })

    elapsed = time.perf_counter() - t0
    report = {
        "fixture_count": len(fixtures),
        "passed": len(failures) == 0,
        "failure_count": len(failures),
        "failures": failures[:40],
        "elapsed_seconds": round(elapsed, 6),
    }
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    json.dump(report, open(args.report, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    open(args.report, "a", encoding="utf-8").write("\n")
    print(
        "banking algorithm fixtures: %d cases, %d failures, %.3fs"
        % (len(fixtures), len(failures), elapsed)
    )
    if failures:
        for f in failures[:20]:
            print(" -", f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
