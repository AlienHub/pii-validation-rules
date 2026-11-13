#!/usr/bin/env python3
"""Generate fixtures/reference-vectors.json from the Python reference implementations.

Deterministic (fixed seed). Every vector is synthetic; bodies are random digits /
letters and may coincide with an issued identifier by chance. Never use them for
identity, authentication or payment operations.

Usage: python3 tools/gen_reference_vectors.py [--count N] [--seed S]
"""

import argparse
import json
import os
import random
import string
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference_impl as R  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def digits(rng, n):
    return "".join(rng.choice(string.digits) for _ in range(n))


def cn_body(rng):
    # 6 area digits + plausible Gregorian date + 3 sequence digits
    import datetime
    y = rng.randint(1900, 2025)
    m = rng.randint(1, 12)
    d = rng.randint(1, 28)
    return digits(rng, 6) + "%04d%02d%02d" % (y, m, d) + digits(rng, 3)


def generate(count, seed):
    rng = random.Random(seed)
    out = {}

    def add(aid, check_position, check_alphabet, vectors, notes=None):
        out[aid] = {"check_position": check_position, "check_alphabet": check_alphabet,
                    "count": len(vectors), "vectors": vectors}
        if notes:
            out[aid]["notes"] = notes

    v = []
    for _ in range(count):
        b = cn_body(rng)
        c = R.cn_resident_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("cn_resident_id_mod11_2", "last", "0123456789X", v)

    v = []
    for _ in range(count):
        b = rng.choice("159Y") + rng.choice("123459") + digits(rng, 6) + "".join(rng.choice(R.USCC_ALPHA) for _ in range(9))
        c = R.cn_uscc_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("cn_uscc_mod31", "last", R.USCC_ALPHA, v)

    v = []
    for _ in range(count):
        b = digits(rng, 12)
        c = R.th_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("th_mod11", "last", string.digits, v)

    v = []
    for _ in range(count):
        b = digits(rng, 11)
        c = R.jp_mynumber_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("jp_mynumber", "last", string.digits, v)

    v = []
    for _ in range(count):
        b = digits(rng, 12)
        c = R.jp_corporate_check(b)
        v.append({"body": b, "check": c, "full": c + b})
    add("jp_corporate_number", "first", string.digits, v)

    v = []
    none_count = 0
    while len(v) < count:
        b = digits(rng, 11)
        c = R.kz_check(b)
        if c is None:
            none_count += 1
            v.append({"body": b, "check": None, "full": None})
        else:
            v.append({"body": b, "check": c, "full": b + c})
    add("kz_iin", "last", string.digits, v,
        notes="check=null means both weight rounds give 10: no decimal check digit exists; verify must fail for every digit")

    v = []
    for _ in range(count):
        n = rng.choice([9, 10, 12, 13, 15, 16, 16, 16, 19])
        b = digits(rng, n - 1)
        c = R.luhn_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("luhn", "last", string.digits, v)

    v = []
    ccs = sorted(R.IBAN_LAYOUT)
    for i in range(count):
        cc = ccs[i % len(ccs)]
        bban = R.iban_random_bban(cc, rng)
        cd = R.iban_check_digits(cc, bban)
        v.append({"country": cc, "bban": bban, "check": cd, "full": cc + cd + bban})
    add("iban_mod97", "3-4", "02..98", v)

    v = []
    for _ in range(count):
        n = rng.randint(1, 20)
        f = "".join(rng.choice(string.ascii_uppercase + string.digits + "<<<") for _ in range(n))
        c = R.icao_check(f)
        v.append({"body": f, "check": c, "full": f + c})
    add("icao9303_check_digit", "last", string.digits, v)

    v = []
    for _ in range(count):
        b = rng.choice("23456789") + digits(rng, 10)
        c = R.verhoeff_check(b)
        assert R.verhoeff_valid(b + c)
        v.append({"body": b, "check": c, "full": b + c})
    add("verhoeff", "last", string.digits, v)

    v = []
    for _ in range(count):
        b = rng.choice("123456789") + digits(rng, 8)
        full = R.tr_tckn_complete(b)
        v.append({"body": b, "check": full[9:], "full": full})
    add("tr_tckn", "last2", "00..99", v, notes="two check digits d10 d11; mutating either must fail")

    v = []
    for _ in range(count):
        b = digits(rng, 9)
        c = R.tr_vkn_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("tr_vkn", "last", string.digits, v)

    v = []
    for i in range(count):
        p = "STFGM"[i % 5]
        d7 = digits(rng, 7)
        c = R.sg_check(p, d7)
        v.append({"body": p + d7, "prefix": p, "check": c, "full": p + d7 + c})
    add("sg_nric_fin_reconstructed", "last", string.ascii_uppercase, v,
        notes="reconstructed tables; M-series vectors exercise the disputed table and are experimental")

    v = []
    letters = sorted(R.TW_LETTERS)
    for i in range(count):
        L = letters[i % len(letters)]
        second = rng.choice("1289")
        d8 = second + digits(rng, 7)
        c = R.tw_check(L, d8)
        v.append({"body": L + d8, "check": c, "full": L + d8 + c})
    add("tw_citizen_new_ui", "last", string.digits, v)

    v = []
    for i in range(count):
        nl = 1 if i % 2 == 0 else 2
        ls = "".join(rng.choice(string.ascii_uppercase) for _ in range(nl))
        d6 = digits(rng, 6)
        c = R.hkid_check(ls, d6)
        v.append({"body": ls + d6, "check": c, "full": ls + d6 + c})
    add("hkid_mod11", "last", "0123456789A", v)

    v = []
    for _ in range(count):
        b = digits(rng, 9)
        c = R.ir_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("ir_national_mod11", "last", string.digits, v)

    v = []
    for _ in range(count):
        b = digits(rng, 12)
        c = R.kr_check(b)
        v.append({"body": b, "check": c, "full": b + c})
    add("kr_rrn_legacy", "last", string.digits, v)

    return out, none_count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--seed", type=int, default=20261113)
    ap.add_argument("--out", default=os.path.join(ROOT, "fixtures", "reference-vectors.json"))
    a = ap.parse_args()
    algos, none_count = generate(a.count, a.seed)
    doc = {
        "generator": "tools/gen_reference_vectors.py",
        "reference_implementation": "tools/reference_impl.py (Python, written independently from the Lua modules)",
        "seed": a.seed,
        "count_per_algorithm": a.count,
        "notice_zh": "全部为合成向量，可能与真实号码偶然相同；仅用于算术差分测试，不是官方测试集，不得用于身份/支付操作。两套实现一致只证明实现与书面规格一致，不证明规格本身官方。",
        "algorithms": algos,
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    total = sum(x["count"] for x in algos.values())
    print("wrote %s: %d algorithms, %d vectors (kz no-check-digit cases: %d)" % (a.out, len(algos), total, none_count))


if __name__ == "__main__":
    main()
