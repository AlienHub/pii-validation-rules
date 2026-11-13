# 银行与高价值 PII 深度调研：实现笔记（2026-11-13）

交接包只作提案。实现阶段重新跑了 `tests/run_research_tests.py`（本机 Python 3.12.3 / PCRE2 10.42：458 格式×2 引擎、62 数学、2554 范围断言通过），再改编进仓库。未把交接包报告冒充为本仓库测试结果。

## 独立核对与修正

| 项 | 结论 |
|---|---|
| TR IBAN | 基线已允许末 16 位字母数字；按 TCMB 2021 公报把保留位收紧为字面 `0`，并入现有 `TR.iban`（不另建 `TR.iban.2021`，保 API）。`iban.lua` 增加 `reserved_zero_at`。 |
| UOB Appendix A 全表 | 再分发权利未核清：**不提交** 452 行提取表。提供 `pii.directories` + 合成样例（含 910→030）。 |
| OFCA/澳门完整号段表 | 不提交全量提取；合成范围夹具覆盖关键回归（4060 已分配、4040 保留、68008000 空洞、66050008 VAS）。 |
| Worldpay MC/Visa/Amex | 标 `processor_scoped_profile` + `opt_in_processor_profile`；默认 checksum=unknown，需 `processor_profiles.worldpay=true`。 |
| 格式正例 | 仅 syntax；完整 pipeline 下错误检查位仍 fail。 |
| PayNow 后缀空串 | 组件规则可匹配空串，表示“未填可选后缀”，**不是**空 PayNow ID；UEN 根号须另校验。 |
| MO BIR | 仅 8 位结构；`checksum=not_established`，不发明权重。 |
| CN 五星卡 | 复用 `cn_resident_id_mod11_2`；语义检查出生日期（含校验通过但 2 月 30 日失败）。 |
| 回乡证 | H/M+8 本体；换证次数不并入本体规则。 |

## 未覆盖（显式保留）

- 泰/新/港/澳/大陆多家大行仍无足够一手长度规范（见 `coverage-by-country-bank.csv`）。
- 泰国手机：NBTC/ITU 代际表冲突，不伪造更严正则。
- 香港清算目录正文未核验（实时页出现未来日期）；行/分行码保持 candidate。
- 无 IIN/BIN 发卡行数据库；无账户存在/归属/别名注册核验。
- Mastercard 规则 PDF 直取 403：19 位接受仅处理商证据。

## 计数口径

- **正则规则**按 `rules/*.json` 条数计（实现后 180）。
- **组件**（routing、HKID check 字段、PayNow 后缀、渠道输入）带 `rule_role=component|routing`，文档中不宣传为新增完整 PII 类型。
- 52 个研究 profile ≠ 52 种新 PII；`TR.iban.2021` 并入 `TR.iban` 后新增强制规则 51 条。
