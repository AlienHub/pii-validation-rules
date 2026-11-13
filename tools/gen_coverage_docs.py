#!/usr/bin/env python3
"""Generate research/COVERAGE.zh.md (coverage matrix) and reports/coverage-summary.json
from rules/*.json, rules/algorithms.json and research/coverage.json.

Run after editing any rule or coverage file; CI fails if the generated matrix drifts.
"""

import argparse
import glob
import json
import os
from collections import Counter, OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STATUS_ZH = OrderedDict([
    ("syntax_supported", "现行官方结构（仅语法）"),
    ("candidate_profile", "候选剖面"),
    ("historical_syntax", "历史格式"),
    ("dated_numbering_profile", "带年代的电话编号剖面"),
    ("country_code_envelope_only", "仅国家区号外壳"),
])
CAT_ZH = OrderedDict([
    ("national_resident_id", "国民/居民身份号"),
    ("tax", "税号"),
    ("phone", "电话"),
    ("passport", "护照"),
    ("bank", "银行/IBAN"),
])
COV_ZH = {
    "researched_partial": "部分",
    "unsupported_insufficient_primary_spec": "未支持",
    "not_implemented_not_fully_researched": "待办",
    "out_of_requested_named_scope_backlog": "范围外待办",
}
SHORT = {"syntax_supported": "S", "candidate_profile": "C", "historical_syntax": "H",
         "dated_numbering_profile": "D", "country_code_envelope_only": "E"}


def load():
    rules = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "rules", "*.json"))):
        if f.endswith("algorithms.json"):
            continue
        for r in json.load(open(f, encoding="utf-8"))["rules"]:
            rules[r["id"]] = r
    algos = json.load(open(os.path.join(ROOT, "rules", "algorithms.json"), encoding="utf-8"))["algorithms"]
    cov = json.load(open(os.path.join(ROOT, "research", "coverage.json"), encoding="utf-8"))
    return rules, algos, cov


def summary(rules, algos, cov):
    by_status = Counter(r["status"] for r in rules.values())
    by_type = Counter(r["pii_type"] for r in rules.values())
    by_checksum_status = Counter(r["checksum"]["status"] for r in rules.values())
    algo_by_policy = Counter(a["default_policy"] for a in algos)
    algo_by_evidence = Counter(a["evidence"] for a in algos)
    jur_by_group = Counter(j["scope_group"] for j in cov["jurisdictions"])
    cells = Counter()
    for j in cov["jurisdictions"]:
        for cat, cell in j["coverage"].items():
            cells[cat + ":" + cell["status"]] += 1
    rules_with_official_checksum = sorted(r["id"] for r in rules.values()
                                          if r["checksum"]["status"] == "algorithm_available"
                                          and r["checksum"]["policy"] == "enabled")
    return OrderedDict([
        ("regex_rules_total", len(rules)),
        ("regex_rules_by_status", OrderedDict((k, by_status.get(k, 0)) for k in STATUS_ZH)),
        ("regex_rules_by_pii_type", OrderedDict(sorted(by_type.items()))),
        ("rules_by_checksum_status", OrderedDict(sorted(by_checksum_status.items()))),
        ("rules_with_checksum_enabled_by_default", rules_with_official_checksum),
        ("checksum_algorithms_total", len(algos)),
        ("checksum_algorithms_by_default_policy", OrderedDict(sorted(algo_by_policy.items()))),
        ("checksum_algorithms_by_evidence", OrderedDict(sorted(algo_by_evidence.items()))),
        ("jurisdictions_named", cov["named_jurisdictions"]),
        ("jurisdictions_inventory_total", cov["inventory_total"]),
        ("jurisdictions_by_scope_group", OrderedDict(sorted(jur_by_group.items()))),
        ("coverage_cells_by_category_and_status", OrderedDict(sorted(cells.items()))),
    ])


def matrix_md(rules, algos, cov, summ):
    L = []
    L.append("# 覆盖矩阵（自动生成，勿手改）\n")
    L.append("由 `python3 tools/gen_coverage_docs.py` 从 `rules/*.json` 与 `research/coverage.json` 生成。\n")
    L.append("## 分类计数\n")
    L.append("| 规则状态 | 数量 |\n|---|---|")
    for k, zh in STATUS_ZH.items():
        L.append("| `%s` %s | %d |" % (k, zh, summ["regex_rules_by_status"][k]))
    L.append("| **合计** | **%d** |\n" % summ["regex_rules_total"])
    L.append("129 条规则中只有 `syntax_supported` 具备现行官方结构证据，且仍只是语法；其余为候选、历史、年代快照或区号外壳。\n")
    L.append("| 校验算法默认策略 | 数量 |\n|---|---|")
    for k, v in summ["checksum_algorithms_by_default_policy"].items():
        L.append("| `%s` | %d |" % (k, v))
    L.append("| **合计** | **%d** |\n" % summ["checksum_algorithms_total"])
    L.append("| 辖区分组 | 数量 |\n|---|---|")
    for k, v in summ["jurisdictions_by_scope_group"].items():
        L.append("| `%s` | %d |" % (k, v))
    L.append("| **合计** | **%d**（指定 %d） |\n" % (summ["jurisdictions_inventory_total"], summ["jurisdictions_named"]))

    L.append("## 逐辖区矩阵\n")
    L.append("单元格：覆盖状态 + 规则 ID（括号内为规则状态缩写：S=syntax_supported，C=candidate_profile，H=historical_syntax，D=dated_numbering_profile，E=country_code_envelope_only；`✓ck` 表示默认启用的官方校验算法，`?ck` 表示需显式启用的二级/重建算法，`~ck` 表示年代门控）。\n")
    header = "| 辖区 | 分组 | " + " | ".join(CAT_ZH.values()) + " |"
    L.append(header)
    L.append("|---|---|" + "---|" * len(CAT_ZH))
    for j in cov["jurisdictions"]:
        row = ["%s %s" % (j["jurisdiction"], j.get("name_zh", "")), "`%s`" % j["scope_group"]]
        for cat in CAT_ZH:
            cell = j["coverage"].get(cat, {"status": "not_implemented_not_fully_researched", "rule_ids": []})
            parts = [COV_ZH.get(cell["status"], cell["status"])]
            for rid in cell["rule_ids"]:
                r = rules[rid]
                tag = SHORT[r["status"]]
                cs = r["checksum"]
                if cs["status"] == "algorithm_available":
                    tag += {"enabled": " ✓ck", "explicit_legacy_regime": " ~ck"}.get(cs["policy"], " ?ck")
                parts.append("`%s`(%s)" % (rid, tag))
            row.append("<br>".join(parts))
        L.append("| " + " | ".join(row) + " |")
    L.append("")
    L.append("## 国际统一类型（GLOBAL）\n")
    L.append("| 规则 | 类型 | 状态 | 校验 |\n|---|---|---|---|")
    for rid, r in rules.items():
        if rid.startswith("GLOBAL."):
            cs = r["checksum"]
            L.append("| `%s` | %s | `%s` | %s |" % (rid, r["pii_type"], r["status"],
                     ("`%s` (%s)" % (cs["algorithm"], cs["policy"])) if cs["status"] == "algorithm_available" else cs["status"]))
    L.append("")
    L.append("## 校验算法清单\n")
    L.append("| 算法 | Lua 模块 | 证据等级 | 默认策略 | 使用规则 |\n|---|---|---|---|---|")
    users = {}
    for rid, r in rules.items():
        if r["checksum"]["status"] == "algorithm_available":
            users.setdefault(r["checksum"]["algorithm"], []).append(rid)
    for a in algos:
        L.append("| `%s` | `%s` | `%s` | `%s` | %s |" % (a["id"], a["lua_module"], a["evidence"], a["default_policy"],
                 ", ".join("`%s`" % u for u in users.get(a["id"], []))))
    L.append("")
    L.append("## 明确未支持 / 待办\n")
    L.append("以下单元格没有任何规则。这不是“格式不存在”，而是本仓库没有取得足够的一手规范，拒绝编造严格正则。\n")
    for j in cov["jurisdictions"]:
        unsupported = [CAT_ZH[c] for c, cell in j["coverage"].items() if not cell["rule_ids"]]
        if unsupported:
            L.append("- **%s %s**：%s。%s" % (j["jurisdiction"], j.get("name_zh", ""), "、".join(unsupported), j.get("notes_zh", "")))
    L.append("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if generated files differ from committed ones")
    a = ap.parse_args()
    rules, algos, cov = load()
    summ = summary(rules, algos, cov)
    md = matrix_md(rules, algos, cov, summ)
    md_path = os.path.join(ROOT, "research", "COVERAGE.zh.md")
    js_path = os.path.join(ROOT, "reports", "coverage-summary.json")
    js = json.dumps(summ, ensure_ascii=False, indent=1) + "\n"
    if a.check:
        ok = True
        if not os.path.exists(md_path) or open(md_path, encoding="utf-8").read() != md:
            print("research/COVERAGE.zh.md is out of date; run tools/gen_coverage_docs.py")
            ok = False
        if not os.path.exists(js_path) or open(js_path, encoding="utf-8").read() != js:
            print("reports/coverage-summary.json is out of date; run tools/gen_coverage_docs.py")
            ok = False
        raise SystemExit(0 if ok else 1)
    os.makedirs(os.path.dirname(js_path), exist_ok=True)
    open(md_path, "w", encoding="utf-8").write(md)
    open(js_path, "w", encoding="utf-8").write(js)
    print(json.dumps(summ, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
