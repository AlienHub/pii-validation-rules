# 测试报告汇总（由 tools/write_summary.py 生成）

生成时间（UTC）：2026-11-13T04:17:23Z

所有数字来自同目录下的机器可读 JSON 报告；每次 `make reports` 都会重新执行全部测试并覆盖本文件。

## 1. 原生 PCRE2 全串正则测试（tests/pcre2/run_pcre2_tests.py）

- 引擎：PCRE2 10.42 2022-12-11（libpcre2-8.so.0，ctypes 直接调用 pcre2_compile_8/pcre2_match_8，分别以 options=0 与 PCRE2_UTF 编译）；Python 3.12.3 `re.fullmatch` 仅作兼容性对照
- 规则编译：129；带预期用例：1176，通过 1176，失败 0；差分语料输入：7363；三引擎分歧：0；锚定策略违规：0；耗时 0.062s

## 2. pcre2test 命令行二次核对（tests/pcre2/run_pcre2test_cli.py）

- PCRE2 version 10.42 2022-12-11：1176 个主题串，0 处不一致，耗时 0.010s

## 3. Lua 运行时测试（tests/lua/run.lua）

| 运行时 | 用例 | 通过 | 失败 | 断言 | CPU 秒 |
|---|---|---|---|---|---|
| Lua 5.1 | 299 | 299 | 0 | 89032 | 0.470 |
| Lua 5.4 | 299 | 299 | 0 | 89032 | 0.411 |
| LuaJIT 2.1.1703358377 | 299 | 299 | 0 | 89032 | 0.184 |

按套件（Lua 5.1）：

| 套件 | 用例 | 失败 | 断言 | 毫秒 |
|---|---|---|---|---|
| json | 4 | 0 | 17 | 1 |
| checksum_fixtures | 18 | 0 | 159 | 2 |
| reference_vectors | 52 | 0 | 81217 | 324 |
| checksum_properties | 95 | 0 | 1822 | 7 |
| syntax_subset | 6 | 0 | 1333 | 43 |
| normalize | 7 | 0 | 32 | 16 |
| semantic | 9 | 0 | 53 | 14 |
| policies | 8 | 0 | 178 | 13 |
| edge_cases | 90 | 0 | 286 | 16 |
| api | 10 | 0 | 3935 | 32 |

## 4. Lua 子集匹配器 vs 原生 PCRE2 差分（tools/compare_syntax_verdicts.py）

| Lua 运行时 | 比对输入 | 一致(匹配) | 一致(不匹配) | 分歧 | 缺失 |
|---|---|---|---|---|---|
| Lua 5.1 | 7363 | 722 | 6641 | 0 | 0 |
| Lua 5.4 | 7363 | 722 | 6641 | 0 | 0 |
| LuaJIT 2.1.1703358377 | 7363 | 722 | 6641 | 0 | 0 |

## 5. 覆盖计数（reports/coverage-summary.json）

- 正则规则：129（syntax_supported 72, candidate_profile 9, historical_syntax 5, dated_numbering_profile 4, country_code_envelope_only 39）
- 校验算法：17（默认策略 enabled 9, explicit_legacy_regime 1, opt_in_secondary 6, opt_in_secondary_m_series_experimental 1）
- 辖区：指定 39，清单 53（additional_asia 19, core 6, geographic_edge_inventory_only 1, middle_east 14, remaining_asia_inventory_only 13）
- 规则校验状态：algorithm_available 36, none_per_source 2, not_applicable 44, not_established 47

## 说明

- 这些测试证明：正则在 PCRE2 下的全串形状判定、Lua 校验算法与独立 Python 参考实现对同一书面规格的算术一致性、策略门控与分层结果模型按文档行为。
- 这些测试不证明：任何号码已发放、仍有效或归属某人；二级/重建来源的算法是官方算法；未收录的类型不存在格式。
