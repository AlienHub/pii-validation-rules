# 实现阶段对研究交接包的核对与修订

交接包（`handoff-specs.zip`：README、RESEARCH-NOTES、IMPLEMENTATION-HANDOFF、rule-specs/checksum-specs/checksum-fixtures/coverage/sources/research-regex-test-report）是研究起点，不是不可质疑的事实。实现阶段逐项核对后的结论与改动如下。交接包本身与其 `sources/`、`extracts/` 均未提交。

## 1. 算法正确性独立核对

对 16 个算法规格逐条按一手描述复核权重、下标基、取模与映射表，并用独立编写的 Python 参考实现（`tools/reference_impl.py`，与 Lua 代码不同语言、不同写法）复算交接包 `checksum-fixtures.json` 的全部 44 组正例/检查位变异用例与 10 个边界用例：**全部一致，未发现算术错误**。具体确认点：

| 算法 | 核对结论 |
|---|---|
| `cn_resident_id_mod11_2` | 权重与 `10X98765432` 映射符合 GB 11643-1999；附录示例 `11010519491231002X` 复算一致 |
| `cn_uscc_mod31` | 31 字符集与权重符合 GB 32100-2015；`(31 − S mod 31) mod 31` 与标准“结果为 31 时取 0”等价 |
| `th_mod11` | 权重 13..2、`(11 − S mod 11) mod 10`；余数 0/1/10 三个边界用例的“首轮余数”声明与复算一致 |
| `jp_mynumber` | 交接包左→右权重 6,5,4,3,2,7,6,5,4,3,2 与省令 Pn/Qn 定义一致（n≤6 取 n+1，n≥7 取 n−5）；余数 ≤1 → 0 经 e-Gov 法令文本确认 |
| `kz_iin` | 两轮权重与“第二轮仍 10 则无合法检查位”一致；边界用例 r1=10/r2=5 与 r1=10/r2=10 复算一致 |
| `luhn` / `verhoeff` / `iban_mod97` / `icao9303_check_digit` | 标准算法；Verhoeff D/P 表逐项核对为标准表；ICAO 样本 `L898902C3`→6 一致，另补 Doc 9303 TD3 样本行的日期字段与复合检查位 |
| `tr_tckn` | 两段公式与常见重建一致；注意 d10 需非负取模 |
| `tr_vkn` | 交接包 1 基下标写法 `a=(d_i+10−i) mod 10`、`b=(a·2^(10−i)) mod 9` 与常见 0 基实现等价；夹具 `0010213576` 复算一致 |
| `sg_nric_fin_reconstructed` | S/T、F/G 表与偏移为公开重建；M 表 `XWUTRQPNJLK` + 偏移 3 对 ICA 示例数字 1234567 给出 K，不是 B——与交接包“官方示例不是重建算法正例”一致 |
| `tw_citizen_new_ui` | 字母值表（I=34、O=35、W=32、X=30、Y=31、Z=33）与权重 1,9,8,7,6,5,4,3,2,1,1 一致 |
| `hkid_mod11` | 单字母前缀补 36 的处理与两组夹具一致 |
| `ir_national_mod11` / `kr_rrn_legacy` | 与常见描述一致 |

此外用 Python 参考实现生成 3400 个随机向量（`fixtures/reference-vectors.json`，固定种子），Lua 实现对全部向量通过“接受正确检查位 / 复现检查位 / 拒绝检查位的所有其他取值”三项断言（3 个运行时各 81 217 个断言）。两套实现一致只证明它们实现了同一书面规格，不证明规格官方。

## 2. 新增（有官方来源）

- **`jp_corporate_number`**：交接包将法人番号列为“仅形状、算法未研究、不要猜”。实现阶段取得两条一手来源：《法人番号の指定等に関する省令》（平成 26 年財務省令第 70 号）第 2 条（e-Gov 法令 API 文本：Pn 为基础番号自右起第 n 位，Qn 奇数位 1、偶数位 2）与国税厅 `checkdigit.pdf`（检查位 = 9 − (Σ mod 9)，示例基础番号 700110005901 → 检查位 8 → 法人番号 8700110005901）。据此新增官方算法，默认启用，`JP.corporate_number` 规则由 `not_established` 改为 `algorithm_available`。已记录其固有盲点：mod 9 无法区分 0 与 9 的单字符替换（测试 `suite_checksum_properties` 明示）。
- `jp.checksum` 来源的 `retrieval` 补注：实现阶段经 e-Gov 法令 API 再次确认第 5 条 Pn/Qn 定义与余数规则（公式本体为图片，不可机读）。

## 3. 修正

- **`cn.uscc` 来源 URL**：交接包为 `https://u002fwww.cods.org.cn/...`（`u002f` 为转义残留），修正为 `https://www.cods.org.cn/cods/2020-10/29/12575hi/2026052817531155415.pdf`；实现阶段确认 200 / `application/pdf`，为扫描件（文本不可提取，沿用交接包的看图核对结论）。
- **`KR.rrn` 样本预期**：交接包两个样本的 `expected_checksum` 为字符串 `"not_asserted"`。改为显式布尔：`9001011234568` 旧公式一致（true），`9001011234560` 旧公式不一致（false），并在规则中标注；默认策略下两者的 checksum 均为 `unknown`。
- **交接包文本**：多处 JSON `notes`/`limit` 字段与 Markdown 片段丢失空格（如 `Noissuer-existence/ownershipvalidation.`）。规则 `notes_zh`、覆盖 `limit_zh`/`notes_zh` 全部重写为可读中文，语义保持。
- **TH 语义项**：交接包无；实现阶段曾考虑把“类别首位 1..8”列为语义检查，因其已由正则覆盖、不构成独立检查而移除，避免虚假的“语义通过”。
- **IR 反占位策略**：交接包要求与算术分开。实现为语义层检查 `repeated_digits_placeholder`（可用 `ir_reject_repeated_digits=false` 关闭），算术函数 `ir_national_mod11.verify` 保持纯净。
- **ICAO 规则级校验状态**：`GLOBAL.icao_mrz_field` 标为 `checksum.status = not_applicable`（检查位是另一字段），算法通过 `pii.checksums.icao9303` 提供，而不是把字段规则伪装成完整 MRZ 校验。

## 4. 未采纳 / 保持保守的项

- **KZ BIN**：常见说法为与 IIN 同一控制位算法，但 adilet 页面为 JS 渲染、本次未取得法令正文，`KZ.bin` 保持 `not_established`。
- **CN USCC 正则收紧**（第 1–2 位部门/类别、第 3–8 位行政区划数字）：标准确有此结构，但部门/类别清单需分配表且会随修订变化，按交接包建议保持 18 位字符集正则，结构约束写入 `notes_zh`。
- **AE Emirates ID 784 + Luhn、SA 国民号 Luhn、PS 9 位 Luhn、QID 11 位、BH CPR 9 位、IQ 12 位、JO 10 位、SY 11 位**：均无发证机关公式/规范，全部保持 unsupported 或 `not_established`，不以“网上常见”升级。
- **护照与电话**：除中国普通护照外未新增护照规则，未扩展任何电话剖面（无新的监管原文）。
- **IN Aadhaar 首位 2..9**：保留交接包的 `[2-9]`（UIDAI 手册线索），未放宽也未声称已读原文。

## 5. 测试报告处理

交接包的 `research-regex-test-report.json`（PCRE2 10.46 / Python 3.13.5，1175 用例）**未复制进仓库**。实现阶段在本机以 PCRE2 10.42（ctypes 原生调用，options=0 与 PCRE2_UTF 双编译）、`pcre2test` 10.42、Python 3.12.3 重新执行，用例数因新增法人番号官方示例变为 1176，并新增 7363 个差分语料输入；结果与命令见 `reports/`。交接包明确“未编写、未执行 Lua”，Lua 测试全部为本阶段实际运行（Lua 5.4 / 5.1 / LuaJIT 2.1）。

## 6. 规则与覆盖统计的变化

| 项 | 交接包 | 本仓库 |
|---|---|---|
| 正则规则 | 129（72/5/9/39/4） | 129（相同分布） |
| 校验算法规格 | 16 | 17（+`jp_corporate_number`） |
| 挂接算法的规则 | 34 | 36（+`JP.corporate_number`；`KR.rrn` 显式挂接年代门控的 `kr_rrn_legacy`，交接包中该规则未挂接算法） |
| 来源 | 84 | 86（+2 日本法人番号来源） |
| 辖区清单 | 39 指定 + 14 其余 = 53 | 相同 |
| 明确未支持的覆盖格子 | 同交接包 | 同交接包（见 COVERAGE.zh.md 末节） |
