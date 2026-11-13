#!/usr/bin/env python3
"""Independent Python reference implementations of the checksum algorithms.

Purpose: differential-testing oracle for the Lua modules (tools/gen_reference_vectors.py
writes fixtures/reference-vectors.json from these functions; tests/lua consumes them).

These functions were written directly from the algorithm descriptions in
rules/algorithms.json, in a different language and style from the Lua code (e.g. the
IBAN oracle uses Python big integers while Lua streams mod 97; Verhoeff generation
uses the inverse table while Lua verifies by brute force). Agreement between the two
is evidence that both implement the written specification consistently. It is NOT
evidence that the specification itself is official; see the evidence grade per algorithm.

No code was copied from third-party libraries.
"""

import random
import string


def _ws(digits, weights):
    return sum(int(d) * w for d, w in zip(digits, weights))


# ---------------------------------------------------------------- CN
CN_W = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]


def cn_resident_check(body17: str) -> str:
    return "10X98765432"[_ws(body17, CN_W) % 11]


USCC_ALPHA = "0123456789ABCDEFGHJKLMNPQRTUWXY"
USCC_W = [1, 3, 9, 27, 19, 26, 16, 17, 20, 29, 25, 13, 8, 24, 10, 30, 28]


def cn_uscc_check(body17: str) -> str:
    s = sum(USCC_ALPHA.index(c) * w for c, w in zip(body17, USCC_W))
    return USCC_ALPHA[(31 - s % 31) % 31]


# ---------------------------------------------------------------- TH
def th_check(body12: str) -> str:
    return str((11 - _ws(body12, range(13, 1, -1)) % 11) % 10)


# ---------------------------------------------------------------- JP
def jp_mynumber_check(body11: str) -> str:
    total = 0
    for n in range(1, 12):
        p = int(body11[-n])
        q = n + 1 if n <= 6 else n - 5
        total += p * q
    r = total % 11
    return "0" if r <= 1 else str(11 - r)


def jp_corporate_check(base12: str) -> str:
    total = 0
    for n in range(1, 13):
        total += int(base12[-n]) * (1 if n % 2 == 1 else 2)
    return str(9 - total % 9)


# ---------------------------------------------------------------- KZ
def kz_check(body11: str):
    r = _ws(body11, range(1, 12)) % 11
    if r == 10:
        r = _ws(body11, [3, 4, 5, 6, 7, 8, 9, 10, 11, 1, 2]) % 11
        if r == 10:
            return None
    return str(r)


# ---------------------------------------------------------------- Luhn
def luhn_valid(num: str) -> bool:
    total = 0
    for i, ch in enumerate(reversed(num)):
        d = int(ch)
        if i % 2 == 1:
            d = d * 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


def luhn_check(body: str) -> str:
    for c in "0123456789":
        if luhn_valid(body + c):
            return c
    raise AssertionError("unreachable")


# ---------------------------------------------------------------- IBAN
IBAN_LAYOUT = {
    "AE": ("23", "n3n16"), "BH": ("22", "a4c14"), "IL": ("23", "n3n3n13"), "IQ": ("23", "a4n3n12"),
    "JO": ("30", "a4n4c18"), "KW": ("30", "a4c22"), "KZ": ("20", "n3c13"), "LB": ("28", "n4c20"),
    "MN": ("20", "n4n12"), "OM": ("23", "n3c16"), "PK": ("24", "a4c16"), "PS": ("29", "a4c21"),
    "QA": ("29", "a4c21"), "SA": ("24", "n2c18"), "TR": ("26", "n5n1c16"), "YE": ("30", "a4n4c18"),
}


def iban_mod97(s: str) -> int:
    moved = s[4:] + s[:4]
    num = "".join(str(ord(c) - 55) if c.isalpha() else c for c in moved)
    return int(num) % 97


def iban_check_digits(cc: str, bban: str) -> str:
    return "%02d" % (98 - iban_mod97(cc + "00" + bban))


def iban_random_bban(cc: str, rng: random.Random) -> str:
    import re
    out = []
    segments = re.findall(r"([nac])(\d+)", IBAN_LAYOUT[cc][1])
    for i, (cls, n) in enumerate(segments):
        n = int(n)
        # TCMB 2021: TR reserved national field (BBAN index after 5-digit PSP) is 0.
        if cc == "TR" and i == 1 and n == 1:
            out.append("0")
            continue
        pool = {"n": string.digits, "a": string.ascii_uppercase, "c": string.digits + string.ascii_uppercase}[cls]
        out.append("".join(rng.choice(pool) for _ in range(n)))
    return "".join(out)


# ---------------------------------------------------------------- ICAO 9303
def icao_check(field: str) -> str:
    total = 0
    for i, c in enumerate(field):
        v = 0 if c == "<" else (int(c) if c.isdigit() else ord(c) - 55)
        total += v * (7, 3, 1)[i % 3]
    return str(total % 10)


# ---------------------------------------------------------------- Verhoeff
VD = [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 0, 6, 7, 8, 9, 5], [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
      [3, 4, 0, 1, 2, 8, 9, 5, 6, 7], [4, 0, 1, 2, 3, 9, 5, 6, 7, 8], [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
      [6, 5, 9, 8, 7, 1, 0, 4, 3, 2], [7, 6, 5, 9, 8, 2, 1, 0, 4, 3], [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
      [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]]
VP = [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 5, 7, 6, 2, 8, 3, 0, 9, 4], [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
      [8, 9, 1, 6, 0, 4, 3, 5, 2, 7], [9, 4, 5, 3, 1, 2, 6, 8, 7, 0], [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
      [2, 7, 9, 3, 8, 0, 6, 4, 1, 5], [7, 0, 4, 6, 9, 1, 3, 2, 5, 8]]
VINV = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]


def verhoeff_valid(num: str) -> bool:
    c = 0
    for i, ch in enumerate(reversed(num)):
        c = VD[c][VP[i % 8][int(ch)]]
    return c == 0


def verhoeff_check(body: str) -> str:
    c = 0
    for i, ch in enumerate(reversed(body)):
        c = VD[c][VP[(i + 1) % 8][int(ch)]]
    return str(VINV[c])


# ---------------------------------------------------------------- TR
def tr_tckn_complete(body9: str) -> str:
    d = [int(c) for c in body9]
    o = d[0] + d[2] + d[4] + d[6] + d[8]
    e = d[1] + d[3] + d[5] + d[7]
    d10 = (7 * o - e) % 10
    d11 = (sum(d) + d10) % 10
    return body9 + str(d10) + str(d11)


def tr_tckn_valid(s: str) -> bool:
    return len(s) == 11 and s.isdigit() and s[0] != "0" and tr_tckn_complete(s[:9]) == s


def tr_vkn_check(body9: str) -> str:
    total = 0
    for i in range(1, 10):
        a = (int(body9[i - 1]) + 10 - i) % 10
        if a != 0:
            b = (a * 2 ** (10 - i)) % 9
            total += 9 if b == 0 else b
    return str((10 - total % 10) % 10)


# ---------------------------------------------------------------- SG
SG_W = [2, 7, 6, 5, 4, 3, 2]
SG_OFF = {"S": 0, "T": 4, "F": 0, "G": 4, "M": 3}
SG_MAP = {"S": "JZIHGFEDCBA", "T": "JZIHGFEDCBA", "F": "XWUTRQPNMLK", "G": "XWUTRQPNMLK", "M": "XWUTRQPNJLK"}


def sg_check(prefix: str, digits7: str) -> str:
    return SG_MAP[prefix][(_ws(digits7, SG_W) + SG_OFF[prefix]) % 11]


# ---------------------------------------------------------------- TW
TW_LETTERS = {"A": 10, "B": 11, "C": 12, "D": 13, "E": 14, "F": 15, "G": 16, "H": 17, "I": 34, "J": 18,
              "K": 19, "L": 20, "M": 21, "N": 22, "O": 35, "P": 23, "Q": 24, "R": 25, "S": 26, "T": 27,
              "U": 28, "V": 29, "W": 32, "X": 30, "Y": 31, "Z": 33}


def tw_check(letter: str, digits8: str) -> str:
    v = TW_LETTERS[letter]
    seq = [v // 10, v % 10] + [int(c) for c in digits8]
    s = _ws(seq, [1, 9, 8, 7, 6, 5, 4, 3, 2, 1])
    return str((10 - s % 10) % 10)


# ---------------------------------------------------------------- HK
def hkid_check(letters: str, digits6: str) -> str:
    vals = [ord(c) - 55 for c in letters]
    if len(vals) == 1:
        vals = [36] + vals
    s = _ws(vals + [int(c) for c in digits6], [9, 8, 7, 6, 5, 4, 3, 2])
    v = (11 - s % 11) % 11
    return "A" if v == 10 else str(v)


# ---------------------------------------------------------------- IR
def ir_check(body9: str) -> str:
    r = _ws(body9, range(10, 1, -1)) % 11
    return str(r if r < 2 else 11 - r)


# ---------------------------------------------------------------- KR legacy
def kr_check(body12: str) -> str:
    return str((11 - _ws(body12, [2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5]) % 11) % 10)
