# 证据等级与默认策略

本仓库对每条规则、每个算法、每个来源分别标注证据等级。等级决定默认行为：只有官方/标准来源的算法默认运行；其余一律需要调用方显式启用，否则结果是 `unknown`——既不是通过也不是失败。

## 规则状态（结构证据）

| 状态 | 证据 | 典型例子 |
|---|---|---|
| `syntax_supported` | 发证机关/法律/标准/辖区向 OECD 提交的 TIN 说明/监管机构编号计划/SWIFT 注册表给出的结构 | CN 身份证、SG NRIC、JP 个人番号、16 国 IBAN |
| `candidate_profile` | 结构有线索但缺少规范性边界 | MY 税号 IG+9..11、LK NIC、NP PAN、BD e-TIN、MN 税号、IR 国民号 |
| `historical_syntax` | 已被替代的格式 | ID 15 位 NPWP、MY SG/OG、TW 旧式 UI、LA 2007 税号、6 位 IIN 时期 PAN |
| `dated_numbering_profile` | 带日期的监管编号文件 | SG IMDA 2019、TH NBTC 2024、MY MCMC 2010、TR ICTA 2018 |
| `country_code_envelope_only` | 仅 ITU E.164 国家区号与 15 位上限 | 39 个辖区的电话外壳 |

## 校验算法证据 → 默认策略

| 证据 | 默认策略 | 算法 |
|---|---|---|
| `official`（法律/国家标准/注册机构原文） | `enabled` | `cn_resident_id_mod11_2`（GB 11643-1999）、`cn_uscc_mod31`（GB 32100-2015）、`jp_mynumber`（総務省令 §5）、`jp_corporate_number`（財務省令 §2 + 国税厅示例）、`kz_iin`（2023 年部长令）、`iban_mod97`（ISO 13616 / SWIFT）、`icao9303_check_digit`（Doc 9303 Part 3） |
| `standard_algorithm` | `enabled` 仅限支付卡 PAN；`IL.id_tin` 规则级降为 `opt_in_secondary` | `luhn` |
| `official_algorithm_name_secondary_tables` | `enabled` | `verhoeff`（UIDAI 指明算法名，表格为标准算术） |
| `official_structure_secondary_formula` | `opt_in_secondary` | `th_mod11`（官方确认存在检查位与方法相同，完整公式来自二级文章） |
| `official_structure_secondary_algorithm` | `opt_in_secondary` | `tw_citizen_new_ui`、`hkid_mod11` |
| `reconstructed` | `opt_in_secondary` | `tr_tckn`、`tr_vkn`、`ir_national_mod11` |
| `reconstructed_disputed_M` | S/T/F/G `opt_in_secondary`；M `sg_m_series_experimental` | `sg_nric_fin_reconstructed` |
| `legacy_secondary_algorithm` | `explicit_legacy_regime` | `kr_rrn_legacy` |

规则级 `checksum.status`：

- `not_established`（47 条）：研究未取得算法或算法未经证实（AE Emirates ID、SA 身份号、PK CNIC、IN PAN 检查字母、SG UEN/ASGD 检查字母、KZ BIN、TR YKN、CN 护照等）→ `unknown`。
- `none_per_source`（2 条）：澳门商业税号，OECD 明确无检查位 → `not_applicable`。
- `not_applicable`（44 条）：电话外壳/剖面、MRZ 字段规则（检查位是另一字段）。

## 来源质量（`research/sources.json`）

`quality` 记录来源身份（`primary_*`、`secondary_*`、`industry_association`），`retrieval` 记录实际读取方式：`downloaded_and_text_reviewed`、`opened`、`search_index`（仅在检索索引中读到内容，未完整打开原文）、`webfetch_text_reviewed`、`e-Gov law API XML text reviewed (implementation session)` 等。**primary 不等于最新或完整**；`search_index` 条目在正式发布前应补全文阅读。

## 发证核验

永远是 `unknown`。本仓库不访问任何实名、税务、公安、银行或支付接口，也不提供此类适配器。
