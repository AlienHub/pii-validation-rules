#!/usr/bin/env python3
"""Collect the machine-readable reports under reports/ into reports/SUMMARY.md
(concise human-readable stdout-style summary with runtimes, case counts, pass/fail)."""

import glob
import json
import os
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(ROOT, "reports")


def load(name):
    p = os.path.join(R, name)
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None


def main():
    L = []
    L.append("# 测试报告汇总（由 tools/write_summary.py 生成）\n")
    L.append("生成时间（UTC）：%s\n" % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    L.append("所有数字来自同目录下的机器可读 JSON 报告；每次 `make reports` 都会重新执行全部测试并覆盖本文件。\n")

    p = load("pcre2-regex-report.json")
    if p:
        s = p["summary"]
        L.append("## 1. 原生 PCRE2 全串正则测试（tests/pcre2/run_pcre2_tests.py）\n")
        L.append("- 引擎：PCRE2 %s（%s，ctypes 直接调用 pcre2_compile_8/pcre2_match_8，分别以 options=0 与 PCRE2_UTF 编译）；Python %s `re.fullmatch` 仅作兼容性对照" % (
            p["engine_versions"]["PCRE2"], p["engine_versions"]["PCRE2_library"], p["engine_versions"]["Python"]))
        L.append("- 规则编译：%d；带预期用例：%d，通过 %d，失败 %d；差分语料输入：%d；三引擎分歧：%d；锚定策略违规：%d；耗时 %.3fs" % (
            s["rules_compiled"], s["expected_cases"], s["expected_cases_passed"], s["expected_cases_failed"],
            s["corpus_inputs_evaluated"], s["engine_disagreements_pcre2_vs_pcre2utf_vs_python"], len(s["anchor_policy_violations"]), s["runtime_seconds"]))
        L.append("")
    c = load("pcre2test-cli-report.json")
    if c:
        L.append("## 2. pcre2test 命令行二次核对（tests/pcre2/run_pcre2test_cli.py）\n")
        if c.get("status") == "ok":
            L.append("- %s：%d 个主题串，%d 处不一致，耗时 %.3fs\n" % (c["pcre2test_version"], c["subjects"], len(c["mismatches"]), c["runtime_seconds"]))
        else:
            L.append("- 状态：%s\n" % c.get("status"))

    L.append("## 3. Lua 运行时测试（tests/lua/run.lua）\n")
    L.append("| 运行时 | 用例 | 通过 | 失败 | 断言 | CPU 秒 |\n|---|---|---|---|---|---|")
    for f in sorted(glob.glob(os.path.join(R, "lua-test-report-*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        s = d["summary"]
        L.append("| %s | %d | %d | %d | %d | %.3f |" % (d["runtime"], s["cases"], s["passed"], s["failed"], s["assertions"], s["cpu_seconds"]))
    L.append("")
    first = sorted(glob.glob(os.path.join(R, "lua-test-report-*.json")))
    if first:
        d = json.load(open(first[0], encoding="utf-8"))
        L.append("按套件（%s）：\n" % d["runtime"])
        L.append("| 套件 | 用例 | 失败 | 断言 | 毫秒 |\n|---|---|---|---|---|")
        for su in d["suites"]:
            L.append("| %s | %d | %d | %d | %d |" % (su["name"], len(su["cases"]), su["failed"], su["assertions"], su["ms"]))
        L.append("")
        fails = [x for x in d["failures"]]
        if fails:
            L.append("失败用例：")
            for x in fails:
                L.append("- %s :: %s — %s" % (x["suite"], x["case"], x["error"]))
            L.append("")

    L.append("## 4. Lua 子集匹配器 vs 原生 PCRE2 差分（tools/compare_syntax_verdicts.py）\n")
    L.append("| Lua 运行时 | 比对输入 | 一致(匹配) | 一致(不匹配) | 分歧 | 缺失 |\n|---|---|---|---|---|---|")
    for f in sorted(glob.glob(os.path.join(R, "lua-vs-pcre2-differential-*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        s = d["summary"]
        L.append("| %s | %d | %d | %d | %d | %d |" % (d["lua_runtime"], s["inputs_compared"], s["agree_match"], s["agree_nomatch"], s["disagreements"], s["missing"]))
    L.append("")

    cov = load("coverage-summary.json")
    if cov:
        L.append("## 5. 覆盖计数（reports/coverage-summary.json）\n")
        L.append("- 正则规则：%d（%s）" % (cov["regex_rules_total"], ", ".join("%s %d" % kv for kv in cov["regex_rules_by_status"].items())))
        L.append("- 校验算法：%d（默认策略 %s）" % (cov["checksum_algorithms_total"], ", ".join("%s %d" % kv for kv in cov["checksum_algorithms_by_default_policy"].items())))
        L.append("- 辖区：指定 %d，清单 %d（%s）" % (cov["jurisdictions_named"], cov["jurisdictions_inventory_total"], ", ".join("%s %d" % kv for kv in cov["jurisdictions_by_scope_group"].items())))
        L.append("- 规则校验状态：%s" % ", ".join("%s %d" % kv for kv in cov["rules_by_checksum_status"].items()))
        L.append("")
    L.append("## 说明\n")
    L.append("- 这些测试证明：正则在 PCRE2 下的全串形状判定、Lua 校验算法与独立 Python 参考实现对同一书面规格的算术一致性、策略门控与分层结果模型按文档行为。")
    L.append("- 这些测试不证明：任何号码已发放、仍有效或归属某人；二级/重建来源的算法是官方算法；未收录的类型不存在格式。")
    out = os.path.join(R, "SUMMARY.md")
    open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("wrote", out)


if __name__ == "__main__":
    main()
