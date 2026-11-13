#!/usr/bin/env python3
"""Generate fixtures/regex-differential-corpus.json: inputs (without verdicts) used to
differential-test the Lua restricted-subset matcher against native PCRE2.

Each rule gets its positive/negative examples plus deterministic mutations:
truncation, extension, single-byte substitution, case flips, inserted separators,
Unicode digits/zero-width characters, line terminators. Verdicts are NOT stored here:
tests/pcre2/run_pcre2_tests.py records PCRE2's verdicts, tests/lua records the Lua
verdicts, and tools/compare_syntax_verdicts.py diffs them.
"""

import glob
import json
import os
import random
import string

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 20261113
MUTATIONS_PER_POSITIVE = 24

UNICODE_DIGITS = ["０", "１", "９", "٠", "١", "۵", "๑", "१", "৩"]
CONTROLS = ["\u200b", "\u200d", "\u202e", "\ufeff", "\u2060"]
ASCII_POOL = string.ascii_uppercase + string.ascii_lowercase + string.digits + "+<-(). /"


def mutations(s, rng):
    out = set()
    if not s:
        return out
    out.add(s[:-1])
    out.add(s[1:])
    out.add(s + rng.choice(ASCII_POOL))
    out.add(rng.choice(ASCII_POOL) + s)
    out.add(s + "\n")
    out.add(s + "\r\n")
    out.add("\n" + s)
    out.add(" " + s)
    out.add(s + " ")
    out.add(s.lower())
    out.add(s.swapcase())
    out.add(s + rng.choice(UNICODE_DIGITS))
    out.add(rng.choice(CONTROLS) + s)
    for _ in range(MUTATIONS_PER_POSITIVE - len(out)):
        kind = rng.random()
        pos = rng.randrange(len(s))
        if kind < 0.45:
            out.add(s[:pos] + rng.choice(ASCII_POOL) + s[pos + 1:])
        elif kind < 0.65:
            out.add(s[:pos] + rng.choice(UNICODE_DIGITS) + s[pos + 1:])
        elif kind < 0.8:
            out.add(s[:pos] + rng.choice(CONTROLS) + s[pos:])
        elif kind < 0.9:
            out.add(s[:pos] + s[pos + 1:])
        else:
            out.add(s[:pos] + rng.choice(ASCII_POOL) + s[pos:])
    return out


def main():
    rng = random.Random(SEED)
    corpus = {}
    files = sorted(glob.glob(os.path.join(ROOT, "rules", "*.json")))
    total = 0
    for f in files:
        if os.path.basename(f) == "algorithms.json":
            continue
        doc = json.load(open(f, encoding="utf-8"))
        for r in doc["rules"]:
            inputs = set()
            for e in r["examples"]:
                inputs.add(e["input"])
                inputs |= mutations(e["input"], rng)
            for e in r["negative_syntax_examples"]:
                inputs.add(e["input"])
            # random strings of plausible length from the ASCII pool
            for e in r["examples"][:2]:
                L = len(e["input"])
                for _ in range(6):
                    inputs.add("".join(rng.choice(ASCII_POOL) for _ in range(L)))
                    inputs.add("".join(rng.choice(string.digits) for _ in range(L)))
            corpus[r["id"]] = sorted(inputs)
            total += len(inputs)
    out = os.path.join(ROOT, "fixtures", "regex-differential-corpus.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump({"generator": "tools/gen_regex_corpus.py", "seed": SEED,
                   "notice_zh": "差分测试语料，仅输入，不含预期；PCRE2 与 Lua 子集匹配器各自给出判定后由 tools/compare_syntax_verdicts.py 比对。全部为合成字符串。",
                   "rules": corpus}, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    print("wrote %s: %d rules, %d inputs" % (out, len(corpus), total))


if __name__ == "__main__":
    main()
