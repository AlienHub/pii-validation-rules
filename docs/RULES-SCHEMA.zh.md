# 规则文件结构（`rules/*.json`，schema `pii-rules-1`）

每个辖区一个文件（ISO 3166-1 alpha-2，加 `GLOBAL.json` 放国际统一类型）。文件头：

| 字段 | 说明 |
|---|---|
| `schema_version` | `pii-rules-1` |
| `version` | 规则集版本，当前 `2026.11.13`（随研究查阅日期） |
| `jurisdiction`, `name_zh`, `scope_group`, `calling_code` | 辖区信息；`scope_group` ∈ `core`、`middle_east`、`additional_asia`、`international` |
| `regex_engine`, `anchor_policy` | `PCRE2`，`\A(?:body)\z` |
| `rules[]` | 规则数组 |

## 规则字段

| 字段 | 说明 |
|---|---|
| `id` | `<辖区>.<类型名>`，全局唯一 |
| `pii_type` | `national_id`、`resident_id`、`tax_id`、`tax_id_entity`、`passport`、`phone`、`iban`、`payment_card`、`passport_mrz_field` |
| `status` | 证据等级，见下 |
| `regex_pcre2` | 权威正则，`\A(?:…)\z`，显式 `[0-9]`，有界重复 |
| `python_fullmatch_body` | 去掉包装的正文，供 `re.fullmatch` 兼容测试；lint 校验与 PCRE2 正文一致 |
| `length`, `iban_bban_notation` | 仅 IBAN：总长与 SWIFT 记法（`n` 数字、`a` 大写字母、`c` 字母数字） |
| `checksum.status` | `algorithm_available`（有实现的算法）、`not_established`（研究未取得算法 → 结果 `unknown`）、`none_per_source`（来源明确无检查位 → `not_applicable`）、`not_applicable`（类型本身没有规则级检查位：电话外壳、MRZ 字段规则） |
| `checksum.algorithm`, `checksum.evidence`, `checksum.policy` | 仅 `algorithm_available`：算法 ID（见 `rules/algorithms.json`）、本规则的证据等级、默认策略（`enabled`、`opt_in_secondary`、`opt_in_secondary_m_series_experimental`、`explicit_legacy_regime`）。规则级 `policy`/`evidence` 覆盖算法默认值（例：`IL.id_tin` 的 Luhn 为 `opt_in_secondary`，而 PAN 的 Luhn 为 `enabled`） |
| `notes_zh` | 结构说明、代际、不覆盖的变体、公式来源性质 |
| `semantic_checks[]` | 语义层应检查的项目名；`lua/pii/semantic.lua` 实现其中一部分，未实现的以 warning `semantic:checks_listed_but_not_implemented` 返回 `unknown` |
| `normalization[]` | 允许的展示归一化变换（`transform`、`layout`、`requires_option`） |
| `source_ids[]`, `source_urls[]`, `accessed_on` | 指向 `research/sources.json`；lint 校验 URL 同步 |
| `examples[]` | 正例：`input`、`expected_syntax`、`provenance`（`synthetic_research_fixture`、`official_*_illustrative_example*`、`processor_test_pan_*`），有算法的规则另有 `expected_checksum_arithmetic`（算法显式启用时的算术结果，与默认策略无关） |
| `negative_syntax_examples[]` | 反例：空串、非法字符、首尾换行、后缀、过短、过长、非 ASCII 数字 |
| `sample_notice_zh` | 样本仅合成/官方说明性，可能与真实号码偶然相同 |

## 规则状态词汇（`status`）

| 值 | 含义 | 验证器行为 |
|---|---|---|
| `syntax_supported` | 有现行官方结构证据；仅语法 | 正常评估 |
| `official_scoped_syntax` | 官方但**产品/渠道/发行人限定** | 评估并附 scope 提醒；`issuer_scope` 必填含义 |
| `processor_scoped_profile` | 支付处理商接入剖面 | 默认不启用校验码；需 `processor_profiles` |
| `dated_bank_generation_profile` / `dated_channel_profile` | 银行代际或渠道输入 | 仅在对应代际/渠道显式选用时有意义 |
| `standard_announcement_envelope` | 标准公告长度外壳 | 非发卡行/产品目录 |
| `syntax_plus_required_allocation_lookup` | 语法 + 离线分配表 | 表外 → registry/semantic `unknown`，不证明无效 |
| `candidate_profile` | 候选剖面，不是权威硬拒绝依据 | 评估并附 `rule_status:candidate_profile_*` 提醒 |
| `historical_syntax` | 历史格式 | 评估；非 `historical_import` 模式附提醒 |
| `dated_numbering_profile` | 带年代的电话编号快照 | 评估并附提醒 |
| `country_code_envelope_only` | 仅 `+区号` + ≤15 位 | 评估并附“不是电话验证器”提醒 |

可选字段：`issuer_scope`、`rule_role`（`full_identifier` / `component` / `routing` / `processor_profile`）、`validation_scope`、`source_dates`、`effective_from`。组件与路由规则计入规则总数，但**不宣传为新增完整 PII 类型**。

## `rules/algorithms.json`

| 字段 | 说明 |
|---|---|
| `id`, `lua_module` | 算法 ID 与实现模块 |
| `evidence` | `official`、`standard_algorithm`、`official_algorithm_name_secondary_tables`、`official_structure_secondary_formula`、`official_structure_secondary_algorithm`、`reconstructed`、`reconstructed_disputed_M`、`legacy_secondary_algorithm` |
| `default_policy` | 见上；`tests/lua/suite_policies.lua` 断言：非官方证据的算法默认策略一定不是 `enabled` |
| `source_ids[]`, `steps_zh[]`, `parameters` | 来源、算法步骤（含下标基、负数取模说明）、权重/表格 |

## `research/coverage.json`

逐辖区 × 五类（`national_resident_id`、`tax`、`phone`、`passport`、`bank`）的 `status` + `rule_ids`：`researched_partial`（至少一条规则）、`unsupported_insufficient_primary_spec`（明确未支持）、`not_implemented_not_fully_researched`（清单待办）、`out_of_requested_named_scope_backlog`（EG）。lint 保证每条非 GLOBAL 规则都被引用、每个引用都存在、有规则的格子状态必为 `researched_partial`。
