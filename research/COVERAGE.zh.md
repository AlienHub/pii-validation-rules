# 覆盖矩阵（自动生成，勿手改）

由 `python3 tools/gen_coverage_docs.py` 从 `rules/*.json` 与 `research/coverage.json` 生成。

## 分类计数

| 规则状态 | 数量 |
|---|---|
| `syntax_supported` 现行官方结构（仅语法） | 72 |
| `official_scoped_syntax` 官方但产品/渠道限定 | 30 |
| `processor_scoped_profile` 处理商接入剖面（默认不启用） | 3 |
| `dated_bank_generation_profile` 银行代际/产品年代剖面 | 3 |
| `dated_channel_profile` 渠道输入剖面 | 1 |
| `standard_announcement_envelope` 标准公告外壳（非发卡目录） | 1 |
| `syntax_plus_required_allocation_lookup` 语法+分配表查找（表外unknown） | 1 |
| `candidate_profile` 候选剖面 | 11 |
| `historical_syntax` 历史格式 | 10 |
| `dated_numbering_profile` 带年代的电话编号剖面 | 9 |
| `country_code_envelope_only` 仅国家区号外壳 | 39 |
| **合计** | **180** |

129 条规则中只有 `syntax_supported` 具备现行官方结构证据，且仍只是语法；其余为候选、历史、年代快照或区号外壳。

| 校验算法默认策略 | 数量 |
|---|---|
| `enabled` | 9 |
| `explicit_legacy_regime` | 1 |
| `opt_in_secondary` | 6 |
| `opt_in_secondary_m_series_experimental` | 1 |
| **合计** | **17** |

| 辖区分组 | 数量 |
|---|---|
| `additional_asia` | 19 |
| `core` | 6 |
| `geographic_edge_inventory_only` | 1 |
| `middle_east` | 14 |
| `remaining_asia_inventory_only` | 13 |
| **合计** | **53**（指定 39） |

## 逐辖区矩阵

单元格：覆盖状态 + 规则 ID（括号内为规则状态缩写：S=syntax_supported，C=candidate_profile，H=historical_syntax，D=dated_numbering_profile，E=country_code_envelope_only；`✓ck` 表示默认启用的官方校验算法，`?ck` 表示需显式启用的二级/重建算法，`~ck` 表示年代门控）。

| 辖区 | 分组 | 国民/居民身份号 | 税号 | 电话 | 护照 | 银行/IBAN |
|---|---|---|---|---|---|---|
| CN 中国大陆 | `core` | 部分<br>`CN.resident_id`(S ✓ck)<br>`CN.foreign_permanent_resident2023`(O ✓ck)<br>`CN.foreign_permanent_resident_legacy`(H)<br>`CN.hk_mainland_residence`(O ✓ck)<br>`CN.mo_mainland_residence`(O ✓ck) | 部分<br>`CN.uscc`(S ✓ck) | 部分<br>`CN.phone_country_envelope`(E) | 部分<br>`CN.ordinary_passport`(S)<br>`CN.travel_hkmo_electronic`(O) | 部分<br>`CN.pan.jrt0008_2000`(H ✓ck)<br>`CN.boc.passbook12`(Bg)<br>`CN.cnaps.routing`(O)<br>`CN.cmb.professional_legacy_card`(H) |
| TH 泰国 | `core` | 部分<br>`TH.citizen_id`(S ?ck) | 部分<br>`TH.tin_envelope`(S ?ck) | 部分<br>`TH.phone_country_envelope`(E)<br>`TH.phone_mobile_profile`(D) | 未支持 | 部分<br>`TH.bbl.personal_deposit`(O)<br>`TH.bbl.atm_be1st`(O)<br>`TH.kbank.cdm_account`(O)<br>`TH.scb.company_add_account`(O) |
| ID 印度尼西亚 | `core` | 部分<br>`ID.nik`(S) | 部分<br>`ID.npwp16`(S)<br>`ID.npwp15_legacy`(H) | 部分<br>`ID.phone_country_envelope`(E) | 未支持 | 未支持 |
| MY 马来西亚 | `core` | 部分<br>`MY.nric`(S) | 部分<br>`MY.tin_individual`(C)<br>`MY.tin_individual_legacy`(H)<br>`MY.tin_entity`(C) | 部分<br>`MY.phone_country_envelope`(E)<br>`MY.phone_011_profile`(D) | 未支持 | 未支持 |
| SG 新加坡 | `core` | 部分<br>`SG.nric`(S ?ck)<br>`SG.fin`(S ?ck) | 部分<br>`SG.iras_asgd`(S)<br>`SG.uen_rob`(S)<br>`SG.uen_roc`(S)<br>`SG.uen_others`(S)<br>`SG.foreign_company_tax_ref`(S)<br>`SG.itr`(S) | 部分<br>`SG.phone_country_envelope`(E)<br>`SG.phone_nsn_profile`(D)<br>`SG.phone.radio_network`(D)<br>`SG.phone.pstn_ipt`(D)<br>`SG.phone.ipt_ucdo`(D) | 未支持 | 部分<br>`SG.dbs.account`(O)<br>`SG.posb.account`(O)<br>`SG.hsbc.account`(O)<br>`SG.sbi.account`(O)<br>`SG.uob.account`(O)<br>`SG.standard_chartered.account`(O)<br>`SG.ocbc.full_account`(O)<br>`SG.uob.van`(O)<br>`SG.ach.bank_code`(O)<br>`SG.ach.branch_code`(O)<br>`SG.paynow.corporate_suffix`(O) |
| TR 土耳其 | `core` | 部分<br>`TR.tckn`(S ?ck)<br>`TR.ykn`(S) | 部分<br>`TR.vkn`(S ?ck) | 部分<br>`TR.phone_country_envelope`(E)<br>`TR.phone_nsn_profile`(D) | 未支持 | 部分<br>`TR.iban`(S ✓ck) |
| SA 沙特阿拉伯 | `middle_east` | 部分<br>`SA.national_id`(S)<br>`SA.iqama`(S) | 部分<br>`SA.tin`(S) | 部分<br>`SA.phone_country_envelope`(E) | 未支持 | 部分<br>`SA.iban`(S ✓ck) |
| AE 阿联酋 | `middle_east` | 部分<br>`AE.emirates_id`(S) | 未支持 | 部分<br>`AE.phone_country_envelope`(E) | 未支持 | 部分<br>`AE.iban`(S ✓ck) |
| QA 卡塔尔 | `middle_east` | 未支持 | 部分<br>`QA.gta_tin`(S)<br>`QA.qfc_tin`(S) | 部分<br>`QA.phone_country_envelope`(E) | 未支持 | 部分<br>`QA.iban`(S ✓ck) |
| KW 科威特 | `middle_east` | 部分<br>`KW.civil_id`(S) | 部分<br>`KW.entity_tin`(S) | 部分<br>`KW.phone_country_envelope`(E) | 未支持 | 部分<br>`KW.iban`(S ✓ck) |
| BH 巴林 | `middle_east` | 未支持 | 未支持 | 部分<br>`BH.phone_country_envelope`(E) | 未支持 | 部分<br>`BH.iban`(S ✓ck) |
| OM 阿曼 | `middle_east` | 未支持 | 部分<br>`OM.tin`(S) | 部分<br>`OM.phone_country_envelope`(E) | 未支持 | 部分<br>`OM.iban`(S ✓ck) |
| IL 以色列 | `middle_east` | 部分<br>`IL.id_tin`(S ?ck) | 部分<br>`IL.entity_tin`(S) | 部分<br>`IL.phone_country_envelope`(E) | 未支持 | 部分<br>`IL.iban`(S ✓ck) |
| IR 伊朗 | `middle_east` | 部分<br>`IR.national_code`(C ?ck) | 未支持 | 部分<br>`IR.phone_country_envelope`(E) | 未支持 | 未支持 |
| IQ 伊拉克 | `middle_east` | 未支持 | 未支持 | 部分<br>`IQ.phone_country_envelope`(E) | 未支持 | 部分<br>`IQ.iban`(S ✓ck) |
| JO 约旦 | `middle_east` | 未支持 | 未支持 | 部分<br>`JO.phone_country_envelope`(E) | 未支持 | 部分<br>`JO.iban`(S ✓ck) |
| LB 黎巴嫩 | `middle_east` | 未支持 | 未支持 | 部分<br>`LB.phone_country_envelope`(E) | 未支持 | 部分<br>`LB.iban`(S ✓ck) |
| SY 叙利亚 | `middle_east` | 未支持 | 未支持 | 部分<br>`SY.phone_country_envelope`(E) | 未支持 | 未支持 |
| YE 也门 | `middle_east` | 未支持 | 未支持 | 部分<br>`YE.phone_country_envelope`(E) | 未支持 | 部分<br>`YE.iban`(S ✓ck) |
| PS 巴勒斯坦 | `middle_east` | 未支持 | 未支持 | 部分<br>`PS.phone_country_envelope`(E) | 未支持 | 部分<br>`PS.iban`(S ✓ck) |
| JP 日本 | `additional_asia` | 部分<br>`JP.my_number`(S ✓ck) | 部分<br>`JP.corporate_number`(S ✓ck) | 部分<br>`JP.phone_country_envelope`(E) | 未支持 | 未支持 |
| KR 韩国 | `additional_asia` | 部分<br>`KR.rrn`(S ~ck) | 部分<br>`KR.business_registration`(S)<br>`KR.corporation_registration`(S) | 部分<br>`KR.phone_country_envelope`(E) | 未支持 | 未支持 |
| TW 台湾 | `additional_asia` | 部分<br>`TW.citizen_id`(S ?ck)<br>`TW.new_ui`(S ?ck)<br>`TW.old_ui`(H) | 未支持 | 部分<br>`TW.phone_country_envelope`(E) | 未支持 | 未支持 |
| HK 香港 | `additional_asia` | 部分<br>`HK.hkid`(S ?ck)<br>`HK.hkid.identifier_field`(O)<br>`HK.hkid.check_field`(O) | 部分<br>`HK.business_registration`(S) | 部分<br>`HK.phone_country_envelope`(E)<br>`HK.phone.mobile_candidate`(L) | 部分<br>`HK.mainland_travel_permit`(O) | 部分<br>`HK.hsbc.full_account`(O)<br>`HK.bochk.payroll_account`(O)<br>`HK.clearing.bank_code`(C)<br>`HK.clearing.branch_code`(C)<br>`HK.fps.id`(O) |
| MO 澳门 | `additional_asia` | 部分<br>`MO.resident_id`(O) | 部分<br>`MO.individual_commercial_tin`(S)<br>`MO.entity_tin`(S) | 部分<br>`MO.phone_country_envelope`(E)<br>`MO.phone.mobile_series`(D)<br>`MO.phone.fixed28`(D) | 部分<br>`MO.mainland_travel_permit`(O) | 部分<br>`MO.bnu.eapplication_savings`(O)<br>`MO.icbc.ebanking_main`(O)<br>`MO.boc.standard17`(Bg)<br>`MO.boc.selfservice15`(Ch)<br>`MO.boc.old12`(H)<br>`MO.boc.loan15`(Bg) |
| IN 印度 | `additional_asia` | 部分<br>`IN.aadhaar`(S ✓ck) | 部分<br>`IN.pan`(S) | 部分<br>`IN.phone_country_envelope`(E) | 未支持 | 未支持 |
| PK 巴基斯坦 | `additional_asia` | 部分<br>`PK.cnic`(S) | 部分<br>`PK.entity_ntn`(S) | 部分<br>`PK.phone_country_envelope`(E) | 未支持 | 部分<br>`PK.iban`(S ✓ck) |
| BD 孟加拉国 | `additional_asia` | 未支持 | 部分<br>`BD.etin`(C) | 部分<br>`BD.phone_country_envelope`(E) | 未支持 | 未支持 |
| LK 斯里兰卡 | `additional_asia` | 部分<br>`LK.nic_old`(C)<br>`LK.nic_new`(C) | 部分<br>`LK.tin`(C) | 部分<br>`LK.phone_country_envelope`(E) | 未支持 | 未支持 |
| NP 尼泊尔 | `additional_asia` | 未支持 | 部分<br>`NP.pan`(C) | 部分<br>`NP.phone_country_envelope`(E) | 未支持 | 未支持 |
| VN 越南 | `additional_asia` | 部分<br>`VN.personal_id`(S) | 未支持 | 部分<br>`VN.phone_country_envelope`(E) | 未支持 | 未支持 |
| PH 菲律宾 | `additional_asia` | 部分<br>`PH.psn`(S)<br>`PH.pcn`(S) | 部分<br>`PH.tin_base`(S) | 部分<br>`PH.phone_country_envelope`(E) | 未支持 | 未支持 |
| KH 柬埔寨 | `additional_asia` | 未支持 | 未支持 | 部分<br>`KH.phone_country_envelope`(E) | 未支持 | 未支持 |
| LA 老挝 | `additional_asia` | 未支持 | 部分<br>`LA.tin_2007`(H) | 部分<br>`LA.phone_country_envelope`(E) | 未支持 | 未支持 |
| MM 缅甸 | `additional_asia` | 未支持 | 未支持 | 部分<br>`MM.phone_country_envelope`(E) | 未支持 | 未支持 |
| BN 文莱 | `additional_asia` | 部分<br>`BN.nric`(S) | 部分<br>`BN.entity_equivalent`(S) | 部分<br>`BN.phone_country_envelope`(E) | 未支持 | 未支持 |
| MN 蒙古 | `additional_asia` | 未支持 | 部分<br>`MN.civil_tin`(C) | 部分<br>`MN.phone_country_envelope`(E) | 未支持 | 部分<br>`MN.iban`(S ✓ck) |
| KZ 哈萨克斯坦 | `additional_asia` | 部分<br>`KZ.iin`(S ✓ck) | 部分<br>`KZ.bin`(S) | 部分<br>`KZ.phone_country_envelope`(E) | 未支持 | 部分<br>`KZ.iban`(S ✓ck) |
| UZ 乌兹别克斯坦 | `additional_asia` | 部分<br>`UZ.pinfl`(S) | 未支持 | 部分<br>`UZ.phone_country_envelope`(E) | 未支持 | 未支持 |
| AF 阿富汗 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| AM 亚美尼亚 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| AZ 阿塞拜疆 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| BT 不丹 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| CY 塞浦路斯 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| GE 格鲁吉亚 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| KG 吉尔吉斯斯坦 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| MV 马尔代夫 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| TL 东帝汶 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| TJ 塔吉克斯坦 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| TM 土库曼斯坦 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| KP 朝鲜 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| RU 俄罗斯，跨洲补充 | `remaining_asia_inventory_only` | 待办 | 待办 | 待办 | 待办 | 待办 |
| EG 埃及，西奈半岛跨洲补充 | `geographic_edge_inventory_only` | 范围外待办 | 范围外待办 | 范围外待办 | 范围外待办 | 范围外待办 |

## 国际统一类型（GLOBAL）

| 规则 | 类型 | 状态 | 校验 |
|---|---|---|---|
| `GLOBAL.payment_pan_current` | payment_card | `syntax_supported` | `luhn` (enabled) |
| `GLOBAL.payment_pan_legacy` | payment_card | `historical_syntax` | `luhn` (enabled) |
| `GLOBAL.icao_mrz_field` | passport_mrz_field | `syntax_supported` | not_applicable |
| `GLOBAL.pan.iso8iin` | payment_card | `standard_announcement_envelope` | not_established |
| `GLOBAL.pan.iso6iin.legacy` | payment_card | `historical_syntax` | not_established |
| `GLOBAL.pan.visa.worldpay` | payment_card | `processor_scoped_profile` | `luhn` (opt_in_processor_profile) |
| `GLOBAL.pan.mastercard.worldpay` | payment_card | `processor_scoped_profile` | `luhn` (opt_in_processor_profile) |
| `GLOBAL.pan.amex.worldpay` | payment_card | `processor_scoped_profile` | `luhn` (opt_in_processor_profile) |

## 校验算法清单

| 算法 | Lua 模块 | 证据等级 | 默认策略 | 使用规则 |
|---|---|---|---|---|
| `cn_resident_id_mod11_2` | `pii.checksums.east_asia` | `official` | `enabled` | `CN.resident_id`, `CN.foreign_permanent_resident2023`, `CN.hk_mainland_residence`, `CN.mo_mainland_residence` |
| `cn_uscc_mod31` | `pii.checksums.east_asia` | `official` | `enabled` | `CN.uscc` |
| `th_mod11` | `pii.checksums.southeast_asia` | `official_structure_secondary_formula` | `opt_in_secondary` | `TH.citizen_id`, `TH.tin_envelope` |
| `jp_mynumber` | `pii.checksums.east_asia` | `official` | `enabled` | `JP.my_number` |
| `jp_corporate_number` | `pii.checksums.east_asia` | `official` | `enabled` | `JP.corporate_number` |
| `kz_iin` | `pii.checksums.west_central_asia` | `official` | `enabled` | `KZ.iin` |
| `luhn` | `pii.checksums.luhn` | `standard_algorithm` | `enabled` | `CN.pan.jrt0008_2000`, `GLOBAL.payment_pan_current`, `GLOBAL.payment_pan_legacy`, `GLOBAL.pan.visa.worldpay`, `GLOBAL.pan.mastercard.worldpay`, `GLOBAL.pan.amex.worldpay`, `IL.id_tin` |
| `iban_mod97` | `pii.checksums.iban` | `official` | `enabled` | `AE.iban`, `BH.iban`, `IL.iban`, `IQ.iban`, `JO.iban`, `KW.iban`, `KZ.iban`, `LB.iban`, `MN.iban`, `OM.iban`, `PK.iban`, `PS.iban`, `QA.iban`, `SA.iban`, `TR.iban`, `YE.iban` |
| `icao9303_check_digit` | `pii.checksums.icao9303` | `official` | `enabled` |  |
| `verhoeff` | `pii.checksums.verhoeff` | `official_algorithm_name_secondary_tables` | `enabled` | `IN.aadhaar` |
| `tr_tckn` | `pii.checksums.west_central_asia` | `reconstructed` | `opt_in_secondary` | `TR.tckn` |
| `tr_vkn` | `pii.checksums.west_central_asia` | `reconstructed` | `opt_in_secondary` | `TR.vkn` |
| `sg_nric_fin_reconstructed` | `pii.checksums.southeast_asia` | `reconstructed_disputed_M` | `opt_in_secondary_m_series_experimental` | `SG.nric`, `SG.fin` |
| `tw_citizen_new_ui` | `pii.checksums.east_asia` | `official_structure_secondary_algorithm` | `opt_in_secondary` | `TW.citizen_id`, `TW.new_ui` |
| `hkid_mod11` | `pii.checksums.east_asia` | `official_structure_secondary_algorithm` | `opt_in_secondary` | `HK.hkid` |
| `ir_national_mod11` | `pii.checksums.west_central_asia` | `reconstructed` | `opt_in_secondary` | `IR.national_code` |
| `kr_rrn_legacy` | `pii.checksums.east_asia` | `legacy_secondary_algorithm` | `explicit_legacy_regime` | `KR.rrn` |

## 明确未支持 / 待办

以下单元格没有任何规则。这不是“格式不存在”，而是本仓库没有取得足够的一手规范，拒绝编造严格正则。

- **TH 泰国**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **ID 印度尼西亚**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **MY 马来西亚**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **SG 新加坡**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **TR 土耳其**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **SA 沙特阿拉伯**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **AE 阿联酋**：税号、护照。OECD 2021 年称无 CRS TIN 且 VAT 号不是 TIN；不得由此推断 2026 年没有公司税 TRN/VAT 号，需另行研究 FTA。
- **QA 卡塔尔**：国民/居民身份号、护照。QID 11 位/世纪/国籍说法无发证机关原文支持，保持 unsupported。
- **KW 科威特**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **BH 巴林**：国民/居民身份号、税号、护照。旧 OECD 材料“CRS 无 TIN”不等于没有 VAT/TRN。CPR 9 位说法为二级来源；校验未建立。
- **OM 阿曼**：国民/居民身份号、护照。民事/居留 ID 8 位与 9 位说法未经发证机关核实。税号最多 7 位，不是民事 ID。
- **IL 以色列**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **IR 伊朗**：税号、护照、银行/IBAN。IR26 Sheba 不在 SWIFT 103 注册表；央行来源待取。国民号算法仅二级来源。
- **IQ 伊拉克**：国民/居民身份号、税号、护照。国民卡 12 位说法仅二级来源；旧民事身份卡不同；TIN 未建立。
- **JO 约旦**：国民/居民身份号、税号、护照。国民号 10 位说法仅二级来源；无官方编码/算法。
- **LB 黎巴嫩**：国民/居民身份号、税号、护照。OECD 只说数字序列及 VAT 后缀 601/603/604，无确切总长；不编造严格正则。
- **SY 叙利亚**：国民/居民身份号、税号、护照、银行/IBAN。国民号 11 位说法未验证；无官方格式/校验。
- **YE 也门**：国民/居民身份号、税号、护照。国民 ID/护照/TIN 未建立；2024 年 7 月新 IBAN 有文档。
- **PS 巴勒斯坦**：国民/居民身份号、税号、护照。9 位 ID/Luhn 说法常见但未取得发证机关规范；不得从以色列推断。
- **JP 日本**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **KR 韩国**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **TW 台湾**：税号、护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **IN 印度**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **PK 巴基斯坦**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **BD 孟加拉国**：国民/居民身份号、护照、银行/IBAN。NID 10/13/17 位说法需选举委员会原始格式；TIN 不是 NID。
- **LK 斯里兰卡**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **NP 尼泊尔**：国民/居民身份号、护照、银行/IBAN。公民证多种编码与 10 位 NIN 未经发证机关核实；PAN 仅候选。
- **VN 越南**：税号、护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **PH 菲律宾**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **KH 柬埔寨**：国民/居民身份号、税号、护照、银行/IBAN。国民 ID 9/10 位代际与 TIN P/T 前缀变体未解决；不做硬拒正则。
- **LA 老挝**：国民/居民身份号、护照、银行/IBAN。仅 2007 年 TIN 结构；现行法律与监控位算法未知；国民 ID/护照未知。
- **MM 缅甸**：国民/居民身份号、税号、护照、银行/IBAN。NRC/CSC 含邦/省、乡镇、身份类别与缅文/转写变体；乡镇表、类别与 ASCII 编码未验证。不发布玩具 ASCII 正则。
- **BN 文莱**：护照、银行/IBAN。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **MN 蒙古**：国民/居民身份号、护照。西里尔字母 2 字母 + 8 位登记号与 12 位民事税号不同；Unicode 模式不在当前 ASCII 剖面内。
- **KZ 哈萨克斯坦**：护照。历史/外国人/非本地证件变体不完整；逐条规则读 notes_zh。
- **UZ 乌兹别克斯坦**：税号、护照、银行/IBAN。PINFL 14 位形状已知；生成/校验、税务实体码与护照未解决。
- **AF 阿富汗**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **AM 亚美尼亚**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **AZ 阿塞拜疆**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **BT 不丹**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **CY 塞浦路斯**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **GE 格鲁吉亚**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **KG 吉尔吉斯斯坦**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **MV 马尔代夫**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **TL 东帝汶**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **TJ 塔吉克斯坦**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **TM 土库曼斯坦**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **KP 朝鲜**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **RU 俄罗斯，跨洲补充**：国民/居民身份号、税号、电话、护照、银行/IBAN。明确待办，不是对亚洲全覆盖的声明。AZ/CY/GE/TL 在 SWIFT 注册表有 IBAN 条目但不在本范围实现。KZ 与 RU 共用 +7。
- **EG 埃及，西奈半岛跨洲补充**：国民/居民身份号、税号、电话、护照、银行/IBAN。UN M49 将埃及列为北非；因地理上亚洲/中东范围界定不一而显式列出，属范围外待办。
