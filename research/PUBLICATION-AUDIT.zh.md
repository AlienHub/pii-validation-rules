# 公开前审计（PII 仓库）

审计时间：2026-11-13（本机工作树 + 可达 git 历史：`main`、`cursor/pii-validation-rules-impl-9e79`）。  
范围：仅 `AlienHub/pii-validation-rules`。本报告**不打印**任何疑似密钥或标识符正文。

## 结论（可公开状态）

**在已检查范围内，当前分支适合在去掉私有可见性后公开**，前提是：

1. 仅公开本仓库（不牵连其他仓库/账号）；
2. 网站与文档继续声明：样本为合成或官方说明性、不做发证/归属核验、无在线试号；
3. 不打包 PDF / 抓取全文目录 / 完整 UOB·OFCA 提取表（当前未提交）。

本审计**不是**法律合规或 PCI/隐私法的穷尽保证。

## 检查项与结果

| 检查 | 结果 |
|---|---|
| 密钥模式扫描（AKIA、PEM、GitHub PAT、Slack、Bearer JWT、DB URL、api_key 赋值等） | **0** 命中（工作树） |
| 邮箱样字符串 | **0** |
| `*.pdf` / `sources/` / `extracts/`（工作树与 git 对象路径） | **无** |
| 完整 UOB Appendix / 完整 OFCA·澳门号段表 | **未提交**；仅 `fixtures/directories/synthetic-*`（UOB 3 条前缀样例、HK/MO 各数条范围） |
| `LICENSE` 文件 | **无**（未擅自新增；公开后许可仍由仓库所有者决定） |
| 规则 `examples[].provenance` | 合成研究夹具为主；少量 `official_*_illustrative_example*`（GB11643 / NIA / TCMB / NTA 等**已发表说明性**样本），无“真实客户资料”标签 |
| CI / 现有校验器 | 与公开无关；公开不改变测试夹具语义 |

## 数据性质说明

- 规则 JSON、Lua 源码、研究笔记、覆盖矩阵：研究/工程产物，可公开。
- 测试夹具中的号码字符串：按 provenance 为合成或官方说明性；**偶然与真实号码相同的可能无法完全排除**，文档已声明不得用于线上支付/实名核验。
- `research/sources.json`：公开 URL 与引用元数据，不是密钥库。

## Agent Atlas 设计参考确认

| 项 | 值 |
|---|---|
| 参考仓库（只读） | https://github.com/AlienHub/agent-catalog （公开） |
| 项目展示名 | **Agent Atlas** |
| 已验证线上 URL | **https://agent-atlas.pindo.page/** （HTTP 200，标题 `Agent Atlas · 应用数据集`） |
| 许可 | `UNLICENSED` / 私有专有声明；本仓库网站仅在**同一所有者授权复用视觉风格**下仿作，并保留出处说明 |

未发现其他冲突的 “Agent Atlas” 品牌站点需二选一；若用户本意是别的产品，请在启用 Pages 前澄清。

## 公开操作边界

- 可见性变更：由仓库所有者在 GitHub UI 执行（Settings → General → Danger Zone → Change repository visibility → Public）。
- 本代理**不会**改其他仓库可见性、不会 merge PR、不会 force-push 改写历史。
- 站点部署：拟用 **GitHub Pages（project site）** 发布本仓库构建产物；**不**改动 `agent-catalog` 的 Cloudflare 项目。
