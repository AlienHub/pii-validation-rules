# pii-validation-rules

亚洲与中东地区个人/实体标识符（身份号、税号、护照号、电话、IBAN、支付卡 PAN、MRZ 字段）的**格式与校验码一致性**规则库：按辖区组织的 JSON 规则（PCRE2 全串正则 + 证据等级 + 来源）、纯 Lua 校验码模块、合成测试数据、可复现的 PCRE2 与 Lua 测试，以及研究笔记与覆盖矩阵。

> **本仓库不做身份核验。** 任何结果都只说明“字符串形状/算术与已收录规则一致”，不说明号码已发放、仍有效或属于某人。每个结果都带 `issuer_verification = "unknown"`。

English summary: [docs/README.en.md](docs/README.en.md)

**PII Atlas 静态站**：`website/` 源码 → `python3 tools/build_website.py` → `website-dist/`。视觉风格对齐同一所有者的 [Agent Atlas](https://agent-atlas.pindo.page/)（仓库 `AlienHub/agent-catalog`，只读参考）。站点只浏览规则元数据与合成/说明性样本，**无在线试号、无登录、无支付**。公开前审计见 [`research/PUBLICATION-AUDIT.zh.md`](research/PUBLICATION-AUDIT.zh.md)。

---

## 1. 覆盖范围（按证据等级分类，不是一个总数）

数字由 `python3 tools/gen_coverage_docs.py` 从规则文件统计，见 [`reports/coverage-summary.json`](reports/coverage-summary.json) 与 [`research/COVERAGE.zh.md`](research/COVERAGE.zh.md)。

| 正则规则状态 | 数量 | 含义 |
|---|---|---|
| `syntax_supported` | 72 | 有**现行官方结构**证据，但只覆盖语法；并非所有限制都写进正则 |
| `official_scoped_syntax` | 30 | 官方但**产品/渠道限定**（银行账户、别名、部分证件） |
| `processor_scoped_profile` | 3 | Worldpay 等处理商接入；默认不启用 |
| `dated_bank_generation_profile` / `dated_channel_profile` | 3+1 | 银行代际/渠道输入（如澳中银 17/15） |
| `standard_announcement_envelope` / `syntax_plus_required_allocation_lookup` | 1+1 | ISO PAN 外壳；HK 手机需分配表 |
| `candidate_profile` | 11 | 候选剖面（含未核验 HK 清算码） |
| `historical_syntax` | 10 | 历史格式（含旧永居/旧卡/旧账号代际） |
| `dated_numbering_profile` | 9 | 带资料年代的电话编号剖面 |
| `country_code_envelope_only` | 39 | **仅“+国家区号 + 最多 15 位数字”外壳**，不是手机号验证器 |
| 合计 | **180** | **不得宣传为 180 条官方完整 PII 验证**；其中约 9 条为组件/路由（`rule_role`），不单计为完整 PII 类型 |

| 校验算法 | 数量 | 默认策略 |
|---|---|---|
| 官方/标准来源，默认启用 | 9 | `cn_resident_id_mod11_2`、`cn_uscc_mod31`、`jp_mynumber`、`jp_corporate_number`、`kz_iin`、`iban_mod97`、`luhn`（仅支付卡 PAN 默认）、`verhoeff`、`icao9303_check_digit` |
| 二级/重建来源，默认**不运行**（`checksum = "unknown"`） | 6 | `th_mod11`、`tr_tckn`、`tr_vkn`、`tw_citizen_new_ui`、`hkid_mod11`、`ir_national_mod11`；另 `IL.id_tin` 的 Luhn 为规则级可选 |
| 重建且 M 系列有争议 | 1 | `sg_nric_fin_reconstructed`：S/T/F/G 需显式启用，M 另需实验开关 |
| 年代门控 | 1 | `kr_rrn_legacy`：仅 `kr_rrn_regime = "legacy_pre_2020_10"` 时运行 |
| 合计 | 17 | 36 条规则挂接算法；47 条规则校验码**未建立**（`unknown`）；2 条来源明确无校验位；44 条类型不适用（电话外壳、MRZ 字段规则） |

| 辖区 | 数量 |
|---|---|
| 指定技术辖区（core 6 + middle_east 14 + additional_asia 19） | 39 |
| 其余亚洲/跨洲清单（AF AM AZ BT CY GE KG MV TL TJ TM KP RU），**仅列待办、未研究、未实现** | 13 |
| 地理边界条目（EG），范围外待办 | 1 |
| 清单合计 | 53 |

39 个指定辖区 + 14 个待办**不是**“全亚洲覆盖”。护照仍非穷尽；多家大行国内账号仍为 **`unsupported_insufficient_primary_spec`**（见银行矩阵）。逐格矩阵见 [`research/COVERAGE.zh.md`](research/COVERAGE.zh.md)；六地银行逐产品表见 [`research/banking-2026-11/coverage-by-country-bank.csv`](research/banking-2026-11/coverage-by-country-bank.csv)。

### 六地银行 / 证件增量清单（摘要）

| 辖区 | 本轮银行相关规则 | 其他高价值增量 | 仍明确不做 |
|---|---|---|---|
| TH | BBL 存款10 / ATM卡16；KBank CDM10；SCB 公司添加账户 **10或13** | — | Krungthai/Krungsri/ttb 等无一手长度；不伪造更严手机号 |
| TR | `TR.iban`：26 位、保留位0、末16字母数字、MOD97、PSP 可非银行 | — | 各行 native 账号长度；YKN≠TCKN |
| SG | DBS10、POSB9、OCBC10\|12、UOB10、UOB VAN 变长、HSBC12、SBI14、渣打、ACH 行/分行码、PayNow 后缀组件 | 电话 radio/PSTN/IPT 分系列 | 完整 UOB Appendix A 不打包；旧昵称≠归属 |
| CN | 中行存折12限定、CNAPS12路由、招行历史一卡通、JR/T0008 历史 PAN | 2023 五星卡、旧永居兼容、港澳居住证、C 系列往来港澳通行证 | **无全国账号长度**；物联网号段附件未取 |
| HK | HSBC **10或12**、BOCHK 工资14、FPS ID 7\|9、清算行/分行候选 | 回乡证 H 本体；HKID 字段拆分组件；手机分配查找 | 清算目录正文未核验；完整 OFCA 表自备注入 |
| MO | BNU10、ICBC 网银19、中银17/15渠道/15贷款/12旧 | 回乡证 M 本体；BIR 仅结构；手机系列+分配查找 | 澳门 FPS ID；BIR 校验公式不发明 |
| GLOBAL | ISO6/8 外壳；Worldpay Visa/MC/Amex（opt-in） | — | 无全球 BIN 库；MC19 非卡组织全产品权威 |

## 2. 仓库结构

```
README.md                         本文（中文）
docs/README.en.md                 简明英文说明
docs/API.zh.md                    Lua API、结果模型、选项、归一化、日志约束
docs/RULES-SCHEMA.zh.md           rules/*.json 字段说明与状态词汇
docs/REGEX-SUBSET.zh.md           Lua 子集匹配器支持的正则构造（不是 PCRE2）
docs/EVIDENCE-GRADES.zh.md        证据等级与默认策略
research/RESEARCH-NOTES.zh.md     研究笔记：范围、核心结论、逐辖区例外
research/CHANGE-NOTES.zh.md       实现阶段对研究交接包的修订与理由
research/COVERAGE.zh.md           覆盖矩阵（自动生成）
research/coverage.json            逐辖区、逐类型状态（含明确未支持项）
research/sources.json             86 条来源：URL、查阅日期、质量、读取方式、局限
rules/<辖区>.json                  39 个辖区 + GLOBAL，共 180 条规则（PCRE2 正则、状态、校验、来源、样本、归一化）
rules/algorithms.json             17 个校验算法规格（步骤、参数、证据、默认策略）
lua/pii/init.lua                  pii.validate / pii.normalize / pii.rules（syntax/checksum/semantic/registry/ownership）
lua/pii/syntax.lua                受限正则子集匹配器（字节级，全串）
lua/pii/checksums/                luhn、verhoeff、iban、icao9303、east_asia、southeast_asia、west_central_asia
lua/pii/policies.lua              证据等级 → 是否运行算法（含 processor_profiles）
lua/pii/directories.lua           可注入离线目录（UOB 前缀、HK/MO 号段）；缺表→unknown
lua/pii/normalize.lua             显式展示归一化（仅字段特定分隔符；澳中银渠道 00 映射）
lua/pii/semantic.lua              日期/世纪/占位符/目录查找等语义层
lua/pii/json.lua                  纯 Lua JSON（加载规则与夹具、写报告）
fixtures/                         合成/官方说明性样本、参考向量、边界用例、差分语料、banking 458+62、合成目录
research/banking-2026-11/         银行深度调研实现笔记与银行矩阵 CSV
tests/pcre2/                      原生 PCRE2（ctypes）+ pcre2test CLI + banking 夹具 + Python re 对照
tests/lua/                        Lua 测试运行器与 11 个套件（含 suite_banking）
tools/                            参考实现、夹具生成、规则 lint、覆盖文档、报告汇总、banking 导入器
reports/                          已提交的机器可读测试报告与 SUMMARY.md
.github/workflows/ci.yml          CI：lint → PCRE2 → banking → Lua(5.4/5.1/LuaJIT) → 差分 → 覆盖/报告漂移检查
Makefile                          make test / make reports / make fixtures
```

## 3. 快速开始（Lua）

```lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local pii = require("pii")
pii.load("rules")                                   -- 默认即 "rules"

local r = pii.validate("CN.resident_id", "11010519491231002X")
-- r.syntax = "pass", r.checksum = "pass" (GB 11643 官方算法), r.semantic = "pass" (1949-12-31 合法日期)
-- r.issuer_verification = "unknown"（永远）, r.summary = "pass"
-- r.warnings = { "semantic:region_code_not_verified_no_gb2260_history_table" }

local t = pii.validate("TH.citizen_id", "1234567890121")
-- t.checksum = "unknown"：th_mod11 为二级来源公式，默认不运行；unknown 不是通过也不是失败
local t2 = pii.validate("TH.citizen_id", "1234567890121", { secondary_checksums = true })
-- t2.checksum = "pass"，并附 warning "checksum:evidence_official_structure_secondary_formula_not_issuer_certified"

local m = pii.validate("SG.fin", "M1234567B")       -- ICA 官方格式示例
-- m.checksum = "unknown"，原因 sg_m_series_table_disputed_experimental_flag_not_set

local k = pii.validate("KR.rrn", "9001011234560", { kr_rrn_regime = "current_post_2020_10" })
-- k.checksum = "not_applicable"：2020-10 后新号随机化，没有公开校验位

local n = pii.validate("MY.nric", "900101-01-0001", { normalize = true })
-- n.transformations = { "strip_fixed_separators" }, n.normalized_value = "900101010001"
```

结果四层：`syntax` / `checksum` / `semantic` / `issuer_verification`，取值 `pass | fail | unknown | not_applicable | not_evaluated`。`summary` 只有 `pass`（可运行的层都没失败且没有 unknown）、`pass_with_unknowns`、`fail` 三种，**没有“valid”**。完整说明见 [docs/API.zh.md](docs/API.zh.md)。

直接调用算法（纯算术，不经过策略层）：

```lua
local cs = require("pii.checksums")
cs.verify("iban_mod97", "AE151111111111111111111")           --> true
cs.iban.check_digits("AE", "1111111111111111111")             --> "15"
cs.east_asia.jp_corporate_number.check_digit("700110005901")  --> "8"（国税厅示例 8700110005901）
cs.west_central_asia.kz_iin.check_digit("12345600048")        --> nil, "no_valid_check_digit"
cs.icao9303.check_digit("L898902C3")                          --> "6"
```

## 4. 运行测试（真实命令）

依赖：Python 3（标准库即可）、系统 `libpcre2-8`、`pcre2test`（Debian/Ubuntu 包 `pcre2-utils`）、至少一个 Lua 解释器（`lua5.4` / `lua5.1` / `luajit`，均无需第三方库）。

```bash
sudo apt-get install -y lua5.4 lua5.1 luajit libpcre2-8-0 pcre2-utils   # Debian/Ubuntu

make test        # lint → PCRE2 原生 + pcre2test + Python re → Lua 全部运行时 → Lua vs PCRE2 差分 → 覆盖文档漂移检查
make reports     # 同上，并重写 reports/SUMMARY.md
make fixtures    # 重新生成参考向量 / 差分语料 / 覆盖文档（确定性种子，CI 会比对）

# 单项
python3 tools/check_rules.py
python3 tests/pcre2/run_pcre2_tests.py --report reports/pcre2-regex-report.json
python3 tests/pcre2/run_pcre2test_cli.py --report reports/pcre2test-cli-report.json
lua5.4 tests/lua/run.lua --report reports/lua-test-report-lua5.4.json --syntax-verdicts reports/lua-syntax-verdicts-lua5.4.json
python3 tools/compare_syntax_verdicts.py --pcre2 reports/pcre2-corpus-verdicts.json --lua reports/lua-syntax-verdicts-lua5.4.json --out reports/lua-vs-pcre2-differential-lua5.4.json
lua5.4 tests/lua/run.lua --only edge_cases
```

### 4.1 本次提交的实际测试结果（摘自 [`reports/SUMMARY.md`](reports/SUMMARY.md)）

| 检查 | 结果 |
|---|---|
| 原生 PCRE2 10.42（ctypes，options=0 与 PCRE2_UTF）+ Python 3.12 `re.fullmatch` | 129 条规则编译；1176 个带预期用例全部通过；7363 个差分语料输入三引擎零分歧；0.04 s |
| `pcre2test` CLI 二次核对 | 1176 个主题串 0 处不一致 |
| Lua 5.4 / Lua 5.1 / LuaJIT 2.1 | 各 299 个用例、89 032 个断言，全部通过（CPU 0.18–0.47 s） |
| Lua 子集匹配器 vs PCRE2 差分 | 7363 输入 × 3 运行时，0 分歧 |

Lua 套件覆盖：每个算法的正例、检查位全替换变异、坏长度、非法字符、Unicode 数字（全角/阿拉伯-印度/泰文/天城文）、零宽与双向控制符、nil/数字/布尔/表输入、前导 0 保持；与**独立 Python 参考实现**（`tools/reference_impl.py`）生成的 3400 个随机向量的生成器/校验器差分；专项边界（CN 02-30 日期但校验正确、JP 余数 0/1/10、TH 余数 0/1/10、KZ 两轮为 10、SG M 官方示例、KR 三种年代、TR YKN 不套 TCKN、IBAN 检查位 00/01/99、Luhn 09↔90 与 JP 法人号 0↔9 盲点）。

## 5. 正则合同

- 规范形式 `\A(?:body)\z`，不用 `^...$`（后者接受末尾换行）。字符类一律显式 `[0-9]`、ASCII 大写，不用 `\d`。所有重复都有上界，无嵌套回溯。
- **权威引擎是 PCRE2。** Python `re.fullmatch(python_fullmatch_body, value)` 只是兼容对照。
- **Lua 自带 pattern 不是正则。** `lua/pii/syntax.lua` 是一个独立的、受限子集的字节级匹配器，只实现规则用到的构造（类、有界重复、非捕获分组、顶层交替），遇到子集外构造直接报错；CI 用 7363 个输入与原生 PCRE2 做差分。若需在 Lua 中运行任意 PCRE2，请自行绑定 `lrexlib-pcre2` 之类的库并测试依赖，本仓库不隐式依赖它。见 [docs/REGEX-SUBSET.zh.md](docs/REGEX-SUBSET.zh.md)。

## 6. 归一化与安全约束

- 输入始终按字符串处理，绝不 `tonumber`；前导 0 保持。
- 默认**不改写输入**。`options.normalize = true` 时只执行规则声明的字段特定变换（MY NRIC 的 6-2-4 连字符、HKID 末尾一对括号、IBAN 每 4 位空格、SG 旧外国公司税号 `F␣␣␣` → `F000`），并在 `transformations` 中逐项返回；ASCII 小写转大写需额外 `options.ascii_uppercase = true`；不做 NFKC，全角字符直接在语法层失败。
- 电话由调用方选择国际格式；国内 0、00、011 不互换。
- 长度上限（默认 128）、NUL/控制符、零宽/双向格式符显式拒绝并给出 `syntax_error` 分类。
- 生产日志只应记录 `pii.redact(result)`（去掉 `normalized_value`）中的规则 ID、分层结果与原因码；本库任何路径都不打印输入。
- 测试数据仅为合成值或官方/处理商公开的说明性样本（GB 11643 附录示例、ICAO Doc 9303 样本 MRZ、国税厅法人番号示例、Stripe 测试卡号）。合成号码可能与真实号码偶然相同，**绝不可**提交到实名、税务或支付验证接口。仓库不含任何来源原文、PDF、证件图片或联系人信息。

## 7. 不能据此宣称的事项

- 不能宣称全亚洲/全中东覆盖；13 个清单辖区和 EG 完全未实现，38 个指定辖区护照未支持。
- 不能宣称任何样本未被发放。
- 不能宣称 SG、HK、TW、TR、IR、IL、TH 的校验公式是官方公布的：它们来自二级或重建来源，默认不运行。
- 不能把 IBAN MOD 97 通过当作账户存在，不能把 Luhn 通过当作卡/银行账户有效，不能把电话外壳当作手机号验证。
- 不能把 `candidate_profile`、`historical_syntax` 规则当作现行权威。
- 本仓库未添加许可证文件（未被要求）；校验算法实现均为按公开数学描述独立编写，未复制任何第三方实现代码。

## 8. 研究与修订

- 研究方法、逐辖区结论与来源索引：[research/RESEARCH-NOTES.zh.md](research/RESEARCH-NOTES.zh.md)
- 实现阶段对交接规格的核对结论与改动（含新增官方来源的日本法人番号算法、修正的来源 URL、修正的夹具）：[research/CHANGE-NOTES.zh.md](research/CHANGE-NOTES.zh.md)
- 发布前仍需补的证据（护照代际、完整电话计划、MY 税号长度、Aadhaar 首位、SG 官方算法等）同见研究笔记第 8 节。
