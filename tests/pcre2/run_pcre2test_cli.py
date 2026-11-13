#!/usr/bin/env python3
"""Secondary native check through the `pcre2test` command-line tool (pcre2-utils).

Writes a pcre2test input file (one block per rule, subjects escaped byte-by-byte as
\\x{hh} so whitespace/newlines/UTF-8 survive verbatim), runs pcre2test, parses the
" 0: ..." / "No match" lines and compares them with the expected verdicts from
rules/*.json. Complements tests/pcre2/run_pcre2_tests.py (ctypes binding).

Usage: python3 tests/pcre2/run_pcre2test_cli.py [--report reports/pcre2test-cli-report.json]
Exit 1 on mismatch; exit 0 with "skipped" in the report if pcre2test is not installed.
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def esc(s):
    return "".join("\\x{%02x}" % b for b in s.encode("utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=os.path.join(ROOT, "reports", "pcre2test-cli-report.json"))
    a = ap.parse_args()
    t0 = time.time()
    exe = shutil.which("pcre2test")
    report = {"stage": "pcre2test_cli_secondary_check", "command": "python3 tests/pcre2/run_pcre2test_cli.py",
              "run_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    if not exe:
        report["status"] = "skipped_pcre2test_not_installed"
        json.dump(report, open(a.report, "w", encoding="utf-8"), indent=1)
        print("pcre2test not installed; skipped")
        return 0
    version = subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.strip()

    rules = []
    for f in sorted(glob.glob(os.path.join(ROOT, "rules", "*.json"))):
        if f.endswith("algorithms.json"):
            continue
        rules.extend(json.load(open(f, encoding="utf-8"))["rules"])

    blocks = []
    expected = []  # list of (rule_id, input, expected)
    skipped_empty_positives = 0
    for r in rules:
        subjects = [(e["input"], e["expected_syntax"]) for e in r["examples"]] + \
                   [(e["input"], e["expected_syntax"]) for e in r["negative_syntax_examples"]]
        lines = ["/" + r["regex_pcre2"] + "/"]
        for s, exp in subjects:
            if s == "" and exp:
                # pcre2test cannot express an empty subject. Empty-string positives
                # (e.g. optional PayNow suffix component) are covered by ctypes /
                # Python fullmatch runners instead.
                skipped_empty_positives += 1
                continue
            lines.append(esc(s) if s != "" else "\\x{00}")  # empty negatives → NUL must also fail
            expected.append((r["id"], s, exp))
        if len(lines) == 1:
            # pattern with no remaining subjects: still compile once with a NUL probe
            lines.append("\\x{00}")
            expected.append((r["id"], "", False))
        blocks.append("\n".join(lines))
    src = "\n\n".join(blocks) + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".pcre2test", delete=False, encoding="utf-8") as fh:
        fh.write(src)
        path = fh.name
    proc = subprocess.run([exe, "-q", path], capture_output=True, text=True, errors="replace")
    os.unlink(path)

    verdicts = []
    for line in proc.stdout.splitlines():
        if line.startswith(" 0:"):
            verdicts.append(True)
        elif line.strip() == "No match":
            verdicts.append(False)
    mism = []
    if len(verdicts) != len(expected):
        report["status"] = "parse_error"
        report["detail"] = "expected %d verdict lines, parsed %d" % (len(expected), len(verdicts))
        report["stderr"] = proc.stderr[-2000:]
        json.dump(report, open(a.report, "w", encoding="utf-8"), indent=1)
        print(report["detail"])
        return 1
    for (rid, s, exp), got in zip(expected, verdicts):
        # the empty subject was submitted as a single NUL byte, which must also not match
        if got != exp:
            mism.append({"rule_id": rid, "input": s, "expected": exp, "pcre2test": got})
    elapsed = time.time() - t0
    report.update({
        "status": "ok" if not mism else "mismatch",
        "pcre2test_version": version,
        "subjects": len(expected),
        "mismatches": mism,
        "runtime_seconds": round(elapsed, 3),
        "skipped_empty_positives": skipped_empty_positives,
        "note": "empty negatives submitted as NUL (must fail); empty positives skipped (no pcre2test empty-subject syntax)",
    })
    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    with open(a.report, "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print("pcre2test %s: %d subjects, %d mismatches, %d empty-positives skipped, %.3fs"
          % (version, len(expected), len(mism), skipped_empty_positives, elapsed))
    for m in mism[:10]:
        print("MISMATCH", m)
    return 1 if mism else 0


if __name__ == "__main__":
    sys.exit(main())
