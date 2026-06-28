# BGI Release Sync

该项目用于定时检测 `kaedelcb/better-genshin-impact` 的 `publish.yml` 工作流是否存在最新成功构建；如果存在新的 `BetterGI_7z` Artifact，则下载并发布到本仓库 Release，同时记录已发布版本。

需求文档见：[docs/requirements.md](docs/requirements.md)

## 实现方式

- `.github/workflows/sync-bettergi.yml` 每小时运行一次，也支持手动触发。
- `scripts/sync-bettergi.ps1` 使用 GitHub CLI 查询上游 workflow，并通过 nightly.link 的指定 run 链接下载 `BetterGI_7z` Artifact。
- 脚本会解压 `BetterGI_7z.zip`，自动识别其中的 `BetterGI_*.7z` 文件作为发布包，并从文件名提取版本号。
- Release tag 使用识别出的版本号，例如 `v0.61.3+lcb.22.4-OnLine-test22`，Release 资产为 `BetterGI_v0.61.3+lcb.22.4-OnLine-test22.7z`。
- `state/latest.json` 只会在 Release 和资产发布成功后更新，用于避免重复发布同一个上游构建。

## 本地调试

需要先安装并登录 GitHub CLI：

```powershell
gh auth login
pwsh ./scripts/sync-bettergi.ps1 -TargetRepository owner/repo
```

在 GitHub Actions 中会自动使用仓库的 `GITHUB_TOKEN`，无需额外配置。Artifact 下载不走 GitHub Artifact ZIP API，而是使用类似下面的 nightly.link run 链接：

```text
https://nightly.link/kaedelcb/better-genshin-impact/actions/runs/{run_id}/BetterGI_7z.zip
```

不使用 nightly.link 的 workflow/latest 链接，避免 `publish.yml` 路径无法获取的问题。如遇到上游元数据 API 限流，可额外配置仓库 secret `GH_TOKEN`。
