#!/usr/bin/env python3
"""Native PCRE2 strict full-string regex tests + Python `re.fullmatch` compatibility.

* PCRE2 is called through ctypes on the system libpcre2-8 (pcre2_compile_8 /
  pcre2_match_8); every rule pattern is compiled twice, without and with PCRE2_UTF,
  and both verdicts must agree.
* Python `re` runs `re.fullmatch(python_fullmatch_body, value)` as a compatibility
  check only; PCRE2 is the authoritative engine.
* Expected verdicts come from rules/*.json (examples + negative_syntax_examples).
* The differential corpus (fixtures/regex-differential-corpus.json) has no expected
  verdicts; PCRE2's verdicts are recorded so tools/compare_syntax_verdicts.py can
  diff them against the Lua restricted-subset matcher.

Usage: python3 tests/pcre2/run_pcre2_tests.py [--report reports/pcre2-regex-report.json]
Exit code 1 on any failure.
"""

import argparse
import ctypes
import ctypes.util
import glob
import json
import os
import platform
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PCRE2_UTF = 0x00080000
PCRE2_ERROR_NOMATCH = -1


class PCRE2:
    def __init__(self):
        name = ctypes.util.find_library("pcre2-8") or "libpcre2-8.so.0"
        self.lib = ctypes.CDLL(name)
        L = self.lib
        L.pcre2_compile_8.restype = ctypes.c_void_p
        L.pcre2_compile_8.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32,
                                      ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p]
        L.pcre2_match_data_create_from_pattern_8.restype = ctypes.c_void_p
        L.pcre2_match_data_create_from_pattern_8.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        L.pcre2_match_8.restype = ctypes.c_int
        L.pcre2_match_8.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_size_t,
                                    ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p]
        L.pcre2_match_data_free_8.argtypes = [ctypes.c_void_p]
        L.pcre2_code_free_8.argtypes = [ctypes.c_void_p]
        L.pcre2_get_error_message_8.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_size_t]
        L.pcre2_config_8.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
        L.pcre2_config_8.restype = ctypes.c_int
        buf = ctypes.create_string_buffer(64)
        L.pcre2_config_8(11, buf)  # PCRE2_CONFIG_VERSION
        self.version = buf.value.decode()
        self.library = name

    def compile(self, pattern, options=0):
        err = ctypes.c_int()
        off = ctypes.c_size_t()
        pat = pattern.encode("utf-8")
        code = self.lib.pcre2_compile_8(pat, len(pat), options, ctypes.byref(err), ctypes.byref(off), None)
        if not code:
            buf = ctypes.create_string_buffer(256)
            self.lib.pcre2_get_error_message_8(err.value, buf, 256)
            raise ValueError("PCRE2 compile error at %d: %s" % (off.value, buf.value.decode()))
        return code

    def fullmatch(self, code, subject):
        data = subject.encode("utf-8")
        md = self.lib.pcre2_match_data_create_from_pattern_8(code, None)
        try:
            rc = self.lib.pcre2_match_8(code, data, len(data), 0, 0, md, None)
        finally:
            self.lib.pcre2_match_data_free_8(md)
        if rc >= 0:
            return True
        if rc == PCRE2_ERROR_NOMATCH:
            return False
        buf = ctypes.create_string_buffer(256)
        self.lib.pcre2_get_error_message_8(rc, buf, 256)
        raise RuntimeError("PCRE2 match error %d: %s" % (rc, buf.value.decode()))


def load_rules():
    rules = []
    for f in sorted(glob.glob(os.path.join(ROOT, "rules", "*.json"))):
        if os.path.basename(f) == "algorithms.json":
            continue
        doc = json.load(open(f, encoding="utf-8"))
        for r in doc["rules"]:
            r["_jurisdiction"] = doc["jurisdiction"]
            rules.append(r)
    return rules


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=os.path.join(ROOT, "reports", "pcre2-regex-report.json"))
    ap.add_argument("--corpus", default=os.path.join(ROOT, "fixtures", "regex-differential-corpus.json"))
    ap.add_argument("--corpus-verdicts", default=os.path.join(ROOT, "reports", "pcre2-corpus-verdicts.json"),
                    help="large intermediate file consumed by tools/compare_syntax_verdicts.py (git-ignored)")
    a = ap.parse_args()

    t0 = time.time()
    pc = PCRE2()
    rules = load_rules()
    corpus = json.load(open(a.corpus, encoding="utf-8"))["rules"] if os.path.exists(a.corpus) else {}

    cases = []
    failures = []
    verdicts = {}
    engine_disagreements = []
    compiled_ok = 0
    anchor_violations = []
    for r in rules:
        rid = r["id"]
        pat = r["regex_pcre2"]
        if not (pat.startswith("\\A(?:") and pat.endswith(")\\z")):
            anchor_violations.append(rid)
        if "\\d" in pat or "\\w" in pat or "\\s" in pat:
            anchor_violations.append(rid + ":shorthand_class")
        code_plain = pc.compile(pat, 0)
        code_utf = pc.compile(pat, PCRE2_UTF)
        pyre = re.compile(r["python_fullmatch_body"])
        compiled_ok += 1

        def run(value, expected, kind, reason=None):
            v_plain = pc.fullmatch(code_plain, value)
            v_utf = pc.fullmatch(code_utf, value)
            v_py = pyre.fullmatch(value) is not None
            ok = (v_plain == expected) and (v_utf == expected) and (v_py == expected)
            case = {"rule_id": rid, "input": value, "kind": kind, "expected": expected,
                    "pcre2": v_plain, "pcre2_utf": v_utf, "python_re_fullmatch": v_py, "passed": ok}
            if reason:
                case["reason"] = reason
            cases.append(case)
            if not ok:
                failures.append(case)

        for e in r["examples"]:
            run(e["input"], e["expected_syntax"], "positive_example")
        for e in r["negative_syntax_examples"]:
            run(e["input"], e["expected_syntax"], "negative_example", e.get("reason"))

        vd = {}
        for value in corpus.get(rid, []):
            v_plain = pc.fullmatch(code_plain, value)
            v_utf = pc.fullmatch(code_utf, value)
            v_py = pyre.fullmatch(value) is not None
            if not (v_plain == v_utf == v_py):
                engine_disagreements.append({"rule_id": rid, "input": value, "pcre2": v_plain,
                                             "pcre2_utf": v_utf, "python": v_py})
            vd[value] = v_plain
        verdicts[rid] = vd
        pc.lib.pcre2_code_free_8(code_plain)
        pc.lib.pcre2_code_free_8(code_utf)

    elapsed = time.time() - t0
    n_corpus = sum(len(v) for v in verdicts.values())
    summary = {
        "rules_compiled": compiled_ok,
        "expected_cases": len(cases),
        "expected_cases_passed": len(cases) - len(failures),
        "expected_cases_failed": len(failures),
        "corpus_inputs_evaluated": n_corpus,
        "engine_disagreements_pcre2_vs_pcre2utf_vs_python": len(engine_disagreements),
        "anchor_policy_violations": anchor_violations,
        "runtime_seconds": round(elapsed, 3),
    }
    report = {
        "stage": "implementation_pcre2_native_regex_tests",
        "command": "python3 tests/pcre2/run_pcre2_tests.py",
        "run_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "engine_versions": {
            "PCRE2": pc.version,
            "PCRE2_library": pc.library,
            "PCRE2_binding": "ctypes -> pcre2_compile_8/pcre2_match_8 (native; options 0 and PCRE2_UTF)",
            "Python": platform.python_version(),
            "python_re_role": "compatibility check only; not the authoritative engine",
        },
        "summary": summary,
        "failures": failures,
        "engine_disagreements": engine_disagreements,
        "cases": cases,
        "corpus_verdicts_file": os.path.relpath(a.corpus_verdicts, ROOT),
    }
    os.makedirs(os.path.dirname(a.report), exist_ok=True)
    with open(a.report, "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    with open(a.corpus_verdicts, "w", encoding="utf-8") as fh:
        json.dump({"engine_versions": report["engine_versions"], "corpus_verdicts": verdicts}, fh, ensure_ascii=False)
        fh.write("\n")
    print("PCRE2 %s (%s) | Python %s" % (pc.version, pc.library, platform.python_version()))
    print("rules compiled: %d | expected cases: %d passed / %d failed | corpus inputs: %d | engine disagreements: %d | %.3fs"
          % (compiled_ok, summary["expected_cases_passed"], summary["expected_cases_failed"], n_corpus,
             len(engine_disagreements), elapsed))
    if anchor_violations:
        print("anchor policy violations:", anchor_violations)
    for f in failures[:20]:
        print("FAIL", f)
    bad = failures or engine_disagreements or anchor_violations
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
