# Lua API

纯 Lua（5.1 / 5.3 / 5.4 / LuaJIT），无第三方依赖。模块名与函数名为英文，文档为中文。

## 加载

```lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local pii = require("pii")
pii.load("rules")        -- 可选；默认读取 ./rules（相对当前工作目录）。返回 registry。
```

`pii.load(dir)` 读取 `rules/algorithms.json` 与 `rules/<辖区>.json`（文件清单在 `lua/pii/rules.lua`，`tools/check_rules.py` 校验其与磁盘一致）。规则 JSON 是唯一事实来源，Lua 里不复制任何正则或权重表之外的规则信息。

## `pii.validate(rule_id, value, options) -> result`

未知 `rule_id` 抛错。`value` 可以是任意类型；非字符串直接 `syntax = "fail"`，`syntax_error = "not_a_string"`。`options` 不会被修改。

### 结果模型

| 字段 | 说明 |
|---|---|
| `rule_id`, `jurisdiction`, `pii_type`, `rule_status`, `rule_version`, `library_version` | 规则与版本信息 |
| `syntax` | `pass` / `fail`。失败时 `syntax_error` ∈ `not_a_string`、`input_too_long`、`control_character`（含 NUL、换行）、`format_control_character`（U+200B–200F、U+202A–202E、U+2060–2064、U+FEFF）、`non_ascii_character`、`pattern_mismatch` |
| `checksum` | `pass` / `fail` / `unknown` / `not_applicable` / `not_evaluated`；`checksum_status` 为规则声明（`algorithm_available`、`not_established`、`none_per_source`、`not_applicable`）；`checksum_algorithm`、`checksum_evidence`、`checksum_policy`、`checksum_reason` 说明算法、证据等级、策略和未运行/失败原因 |
| `semantic` | 同上词汇；`semantic_details` 列出实际执行的每项检查及结果（如 `birth_date_gregorian = "pass"`, `region_code = "unknown"`） |
| `issuer_verification` | 恒为 `"unknown"`；本库永远不做发证核验 |
| `summary` | `pass`（所有可运行层通过或不适用）、`pass_with_unknowns`、`fail`。**不是“有效”** |
| `warnings` | 字符串数组：规则状态提醒（`rule_status:*`）、证据提醒（`checksum:evidence_*`）、语义层未核验项（`semantic:*`） |
| `transformations`, `normalized_value` | 仅 `options.normalize = true` 且实际发生变换时出现 |
| `input_type` | `"string"` 或原始类型名 |

层间依赖：语法失败 → `checksum`、`semantic` 为 `not_evaluated`。`unknown` 既不是通过也不是失败；调用方不得把它当成任一方向的证据。

### 选项（默认值均为保守值）

| 选项 | 默认 | 作用 |
|---|---|---|
| `secondary_checksums` | `false` | 启用所有 `opt_in_secondary` 算法（TH、TR TCKN/VKN、TW、HKID、IR、SG S/T/F/G、IL 个人 Luhn） |
| `algorithms` | `{}` | 按算法 ID 覆盖：`{ th_mod11 = true }` 启用，`{ cn_resident_id_mod11_2 = false }` 关闭默认算法 |
| `sg_m_series_experimental` | `false` | 评估有争议的新加坡 M 系列对照表；`secondary_checksums` 本身不解锁 M |
| `kr_rrn_regime` | `"unknown"` | `"legacy_pre_2020_10"` 运行旧公式；`"current_post_2020_10"` → `not_applicable`；`unknown` → `unknown`。不能由出生日期推断 |
| `historical_import` | `false` | 承认 `historical_syntax` 规则（去掉提醒），不改变判定 |
| `ir_reject_repeated_digits` | `true` | 伊朗国民号全同数字反占位策略（语义层，与算术分开） |
| `normalize` | `false` | 执行规则声明的展示归一化 |
| `ascii_uppercase` | `false` | 与 `normalize` 配合，允许 ASCII 小写转大写（CN 身份证仅末位 x） |
| `semantic` | `true` | 置 `false` 跳过语义层（`not_evaluated`） |
| `reference_date` | `nil` | `"YYYY-MM-DD"`；提供后 CN/KR 出生日期晚于该日 → 语义失败；不提供则不检查未来日期 |
| `max_input_length` | `128` | 字节长度上限 |

## 归一化 `pii.normalize(rule_id, value, options) -> normalized, transformations`

只做规则 JSON `normalization` 列表中声明的变换，每个变换只在输入**精确**符合其布局时生效：

| 变换 | 规则 | 行为 |
|---|---|---|
| `strip_fixed_separators` | `MY.nric` | `NNNNNN-NN-NNNN` 位置上的连字符；位置不对则原样返回 |
| `strip_trailing_parenthesised_check` | `HK.hkid` | 仅末尾一对括号内单字符 `A123456(3)` → `A1234563` |
| `strip_print_format_spaces` | 全部 IBAN | 仅“每 4 位一个空格”的打印格式；双空格、首尾空格、制表符不处理 |
| `sg_foreign_company_legacy_spaces` | `SG.foreign_company_tax_ref` | 仅 `F␣␣␣NNNNNA` → `F000NNNNNA` |
| `ascii_uppercase` / `ascii_uppercase_last_char` | 含字母的规则 / `CN.resident_id` | 需 `options.ascii_uppercase = true` |

不做的事：全局去空白/标点、去首个 0、NFKC/全角折叠、电话格式互换。

## 校验码模块（纯算术）

```lua
local cs = require("pii.checksums")
cs.verify(algorithm_id, value)   --> true | false, reason
cs.ids()                         --> 17 个算法 ID
```

| 模块 | 算法 | 额外函数 |
|---|---|---|
| `pii.checksums.east_asia` | `cn_resident_id_mod11_2`, `cn_uscc_mod31`, `jp_mynumber`, `jp_corporate_number`, `kr_rrn_legacy`, `tw_citizen_new_ui`, `hkid_mod11` | `check_character(body)` / `check_digit(body)` |
| `pii.checksums.southeast_asia` | `th_mod11`, `sg_nric_fin_reconstructed` | `th.check_digit(body12)`；`sg.check_letter(prefix, digits7)`、`sg.series_of`、`sg.is_experimental_series` |
| `pii.checksums.west_central_asia` | `tr_tckn`, `tr_vkn`, `ir_national_mod11`, `kz_iin` | `tckn.complete(body9)`；`vkn.check_digit`；`ir.check_digit`、`ir.is_repeated_digits`；`kz.check_digit`（两轮均为 10 时返回 `nil, "no_valid_check_digit"`） |
| `pii.checksums.luhn` | `luhn` | `check_digit(body)` |
| `pii.checksums.verhoeff` | `verhoeff` | `check_digit(body)`（生成后用校验器复核） |
| `pii.checksums.iban` | `iban_mod97` | `registry`（16 国长度/BBAN 段）、`validate_structure`、`mod97`（逐字节流式）、`check_digits(cc, bban)`、`strip_print_format_spaces` |
| `pii.checksums.icao9303` | `icao9303_check_digit` | `check_digit(field)`、`verify(field, digit)`、`verify_with_trailing_digit(s)`；复合检查位由调用方按文档布局切片拼接 |

原因码：`not_a_string`、`bad_length`、`bad_character`、`check_mismatch`、`no_valid_check_digit`（KZ）、`leading_zero_not_allowed`（TR TCKN）、`check_digits_out_of_range`（IBAN 00/01/99）、`country_not_in_registry_subset`（IBAN 非 16 国）、`bad_check_character`（ICAO）。

这些函数只回答“算术是否一致”。它们不知道策略、年代或证据等级；那些在 `pii.policies` 与规则 JSON 里。

## 其他

- `pii.rules()` 返回 registry：`:get(id)`、`:ids()`、`:rules_for(jurisdiction, pii_type)`、`:algorithm(id)`、`:count_by_status()`、`.jurisdictions[code]`。
- `pii.syntax_match(rule_id, value)` 只跑语法层（受限子集匹配器）。
- `pii.redact(result)` 去掉 `normalized_value`，用于日志。生产日志应只保留规则 ID、分层结果和原因码，不记录输入。
- `pii.version` 库版本；每条规则另有 `rule_version`（规则文件版本 `2026.11.13`）。

## 结果示例

```lua
pii.validate("IR.national_code", "1111111111", { secondary_checksums = true })
--> syntax="pass", checksum="pass"（算术成立）, semantic="fail"（repeated_digits_placeholder）, summary="fail",
--  warnings = { "rule_status:candidate_profile_not_authoritative_do_not_hard_reject",
--               "checksum:evidence_reconstructed_not_issuer_certified" }

pii.validate("KZ.iin", "123456000480")
--> syntax="pass", checksum="fail", checksum_reason="no_valid_check_digit"（两轮余数均为 10，不能把 10 mod 10 当 0）

pii.validate("CN.resident_id", "11010519900230001X")
--> syntax="pass", checksum="pass", semantic="fail"（1990-02-30 不存在）, summary="fail"
```
