#!/usr/bin/env python3
"""Compare the committed reports (git HEAD) with the reports just regenerated in the
working tree. Only count-type fields are compared (cases, passed, failed, assertions,
rules compiled, inputs compared, disagreements); timestamps, runtimes and engine
version strings may legitimately differ between machines.

Exit 1 when a committed report claims different counts than the fresh run produced,
i.e. when somebody edited code/fixtures without re-running `make reports`.
"""

import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COUNT_KEYS = {
    "pcre2-regex-report.json": ["summary.rules_compiled", "summary.expected_cases", "summary.expected_cases_passed",
                                "summary.expected_cases_failed", "summary.corpus_inputs_evaluated",
                                "summary.engine_disagreements_pcre2_vs_pcre2utf_vs_python"],
    "pcre2test-cli-report.json": ["status", "subjects"],
    "lua-test-report-*.json": ["summary.suites", "summary.cases", "summary.passed", "summary.failed", "summary.assertions"],
    "lua-vs-pcre2-differential-*.json": ["summary.rules", "summary.inputs_compared", "summary.agree_match",
                                         "summary.agree_nomatch", "summary.disagreements", "summary.missing"],
    "coverage-summary.json": ["regex_rules_total", "checksum_algorithms_total", "jurisdictions_named", "jurisdictions_inventory_total"],
    "banking-format-report.json": ["fixture_count", "unique_rules_compiled", "failure_count", "passed"],
    "banking-algorithm-report.json": ["fixture_count", "failure_count", "passed"],
}


def get(d, dotted):
    for part in dotted.split("."):
        if not isinstance(d, dict) or part not in d:
            return None
        d = d[part]
    return d


def committed(path):
    rel = os.path.relpath(path, ROOT)
    try:
        out = subprocess.run(["git", "show", "HEAD:" + rel], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        return None
    return json.loads(out)


def main():
    problems = []
    checked = 0
    for pattern, keys in COUNT_KEYS.items():
        for path in sorted(glob.glob(os.path.join(ROOT, "reports", pattern))):
            fresh = json.load(open(path, encoding="utf-8"))
            old = committed(path)
            rel = os.path.relpath(path, ROOT)
            if old is None:
                print("not in HEAD (new report):", rel)
                continue
            checked += 1
            for k in keys:
                a, b = get(old, k), get(fresh, k)
                if a != b:
                    problems.append("%s: %s committed=%r fresh=%r" % (rel, k, a, b))
    print("verified %d committed report(s) against the fresh run" % checked)
    if problems:
        print("committed reports are stale:")
        for p in problems:
            print(" -", p)
        sys.exit(1)
    print("verify_reports: OK")


if __name__ == "__main__":
    main()
