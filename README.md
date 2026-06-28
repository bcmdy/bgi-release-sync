# BGI Release Sync

该项目用于定时检测 `kaedelcb/better-genshin-impact` 的 `publish.yml` 工作流是否存在最新成功构建；如果存在新的 `BetterGI_7z` Artifact，则下载并发布到本仓库 Release，同时记录已发布版本。

需求文档见：[docs/requirements.md](docs/requirements.md)

## 实现方式

- `.github/workflows/sync-bettergi.yml` 每小时运行一次，也支持手动触发。
- `scripts/sync-bettergi.ps1` 使用 GitHub CLI 查询上游 workflow、下载 `BetterGI_7z` Artifact、创建或补全本仓库 Release。
- `state/latest.json` 只会在 Release 和资产发布成功后更新，用于避免重复发布同一个上游构建。

## 本地调试

需要先安装并登录 GitHub CLI：

```powershell
gh auth login
pwsh ./scripts/sync-bettergi.ps1 -TargetRepository owner/repo
```

在 GitHub Actions 中会自动使用仓库的 `GITHUB_TOKEN`，无需额外配置。
如遇到上游 API 限流或 Artifact 访问权限问题，可额外配置仓库 secret `GH_TOKEN`。
