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

3. Pages 已启用后，向 `cursor/pii-validation-rules-impl-9e79`（或 `main`）推送会自动跑 `pages` build+deploy。也可在 Actions → **pages** → **Run workflow**（需所选 ref 上已有该 workflow 文件）。

4. 站点 URL：`https://alienhub.github.io/pii-validation-rules/`  
   验证：标题 **PII Atlas**，可加载 `catalog.json`，相对资源路径在 project base path 下可用。

## 本代理不会做的事

- 不 merge / 不关闭 PR #1  
- 不修改 `AlienHub/agent-catalog` 或其 Cloudflare 项目  
- 不付费、不改 DNS、不写 history rewrite / force-push  

## 本地预览

```sh
python3 tools/build_website.py
python3 -m http.server 4173 --directory website-dist
```
