# GitHub Pages 启用交接（父代理 / 仓库所有者）

目标公开 URL（启用后）：`https://alienhub.github.io/pii-validation-rules/`  
（若组织自定义 Pages 域名策略不同，以 GitHub Settings 显示为准。）

## 已完成的仓库侧准备

- 静态站源码：`website/`
- 构建产物：`website-dist/`（`python3 tools/build_website.py`）
- Actions 工作流：`.github/workflows/pages.yml`（push 到本分支/`main` 或 `workflow_dispatch`）
- 公开前审计：`research/PUBLICATION-AUDIT.zh.md` → **可公开（已检查范围内）**

## 你需要在 GitHub UI 执行的步骤

1. **仅将本仓库改为 Public**（不要动其他仓库）  
   `AlienHub/pii-validation-rules` → Settings → General → Danger Zone → Change repository visibility → **Public** → 按提示确认。

2. **启用 GitHub Pages（GitHub Actions 来源）**  
   Settings → Pages → Build and deployment → Source: **GitHub Actions**.

3. 打开 Actions → **pages** → **Run workflow**（选 `main` 或已合并的默认分支；当前 PR 分支上的自动 deploy 已关闭，避免 Pages 未启用时出现 404 红叉）。  
   若希望从本 PR 分支直接发布：Pages 启用后，可临时把 `.github/workflows/pages.yml` 的 `on.push.branches` 加回功能分支，或先 merge 再依赖 `main` 推送。

4. 验证：浏览器打开 Pages URL，确认标题为 **PII Atlas**，可加载 `catalog.json`，无登录墙。  
   先前失败日志原文：`Failed to create deployment (status: 404) … Ensure GitHub Pages has been enabled` — **构建已成功**，仅 deploy 因 Pages 未开启而失败；validator `ci` 工作流为成功。

## 本代理不会做的事

- 不 merge / 不关闭 PR #1  
- 不修改 `AlienHub/agent-catalog` 或其 Cloudflare 项目  
- 不付费、不改 DNS、不写 history rewrite / force-push  

## 本地预览

```sh
python3 tools/build_website.py
python3 -m http.server 4173 --directory website-dist
```
