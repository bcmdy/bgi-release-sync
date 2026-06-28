# BGI Release Sync 需求文档

## 1. 项目背景

需要在本仓库中通过 GitHub Actions 每 1 小时自动检测一次上游仓库 `kaedelcb/better-genshin-impact` 的发布工作流：

- 上游仓库：https://github.com/kaedelcb/better-genshin-impact
- 目标工作流：https://github.com/kaedelcb/better-genshin-impact/actions/workflows/publish.yml
- 目标 Artifact 名称：`BetterGI_7z`
- 示例 Artifact 链接：https://github.com/kaedelcb/better-genshin-impact/actions/runs/28296071177/artifacts/7926519828

当检测到上游存在新的成功编译产物时，本项目需要下载该 Artifact，并在当前仓库创建 Release，同时将已处理的版本信息保存到本地状态文件，避免重复发布。

## 2. 项目目标

1. 每 1 小时自动检测上游 `publish.yml` 是否存在最新成功运行。
2. 只处理 `conclusion=success` 且包含 `BetterGI_7z` Artifact 的工作流运行。
3. 当检测到未发布过的新构建时，自动下载 `BetterGI_7z`。
4. 解压下载到的 Artifact zip，将其中的 `BetterGI_*.7z` 作为当前仓库 Release 资产发布。
5. 将已发布版本号或构建标识保存到本地文件。
6. 支持手动触发检测，方便调试和补发。

## 3. 功能范围

### 3.1 定时检测

使用 GitHub Actions 的 `schedule` 触发器：

```yaml
schedule:
  - cron: "0 * * * *"
```

同时提供 `workflow_dispatch` 手动触发入口。

### 3.2 上游构建查询

系统需要通过 GitHub REST API 查询上游仓库指定工作流的运行记录：

```text
GET /repos/kaedelcb/better-genshin-impact/actions/workflows/publish.yml/runs?status=success&per_page=10
```

筛选规则：

- `status` 必须为 `completed`。
- `conclusion` 必须为 `success`。
- 优先选择 `created_at` 或 `run_started_at` 最新的一条。
- 该运行必须存在名为 `BetterGI_7z` 的 Artifact。

### 3.3 Artifact 下载

系统需要查询目标运行的 Artifact 列表：

```text
GET /repos/kaedelcb/better-genshin-impact/actions/runs/{run_id}/artifacts
```

找到名称为 `BetterGI_7z` 的 Artifact 后，优先通过 nightly.link 的指定 run 链接下载，避免直接调用 GitHub Artifact ZIP API 时遇到限流或登录权限问题：

```text
https://nightly.link/kaedelcb/better-genshin-impact/actions/runs/{run_id}/BetterGI_7z.zip
```

实现中不依赖 nightly.link 的 workflow/latest 链接，例如 `https://nightly.link/kaedelcb/better-genshin-impact/actions/workflows/publish.yml`，因为该路径可能无法稳定获取目标产物。

下载文件建议命名为：

```text
BetterGI_7z-{version}.zip
```

下载得到的 Artifact zip 不是最终发布包。系统需要解压该 zip，找到其中唯一的 `BetterGI_*.7z` 文件，并将该 `.7z` 文件作为 Release 资产发布。

若 Artifact 已过期或下载失败，本次任务应失败并输出明确日志，不应更新本地版本状态。

### 3.4 版本识别

优先版本号来源：

1. 如果 Artifact 内部存在形如 `BetterGI_v0.61.3+lcb.22.4-OnLine-test22.7z` 的文件，则从文件名中解析 BetterGI 版本号，例如 `v0.61.3+lcb.22.4-OnLine-test22`。
2. 如果无法找到或无法解析内部 `BetterGI_*.7z` 发布包，则本次任务失败并保留原状态，避免发布错误资产。

解析到内部 `.7z` 文件名时，建议 Release tag 格式：

```text
{version}
```

解析到内部 `.7z` 文件名时，建议 Release 标题格式：

```text
BetterGI {version}
```

### 3.5 本地状态存储

项目需要维护本地状态文件：

```text
state/latest.json
```

字段建议：

```json
{
  "upstream_owner": "kaedelcb",
  "upstream_repo": "better-genshin-impact",
  "workflow": "publish.yml",
  "artifact_name": "BetterGI_7z",
  "last_published_version": "v0.61.3+lcb.22.4-OnLine-test22",
  "last_published_run_id": 28296071177,
  "last_published_artifact_id": 7926519828,
  "last_published_at": "2026-06-28T00:00:00Z"
}
```

状态更新规则：

- 只有 Release 创建成功且资产上传成功后，才允许更新 `state/latest.json`。
- 若检测到的 `run_id` 与 `last_published_run_id` 相同，则直接跳过。
- 若 Release 已存在但状态文件未更新，应尝试补写状态文件。

### 3.6 Release 发布

在当前仓库创建 GitHub Release：

- Tag：`{version}`，例如 `v0.61.3+lcb.22.4-OnLine-test22`
- Release 名称：`BetterGI {version}`
- Release 说明需包含：
  - 上游仓库链接
  - 上游 workflow run 链接
  - Artifact ID
  - BetterGI 版本号
  - Release 资产文件名
  - 上游 commit SHA
  - 同步时间

Release 资产：

- 上传从 `BetterGI_7z.zip` 中解压得到的 `BetterGI_*.7z`

如果同名 Release 或 Tag 已存在：

- 如果资产也已存在，则视为已发布，跳过。
- 如果 Release 存在但资产缺失，则补传资产。

## 4. 非功能需求

### 4.1 安全性

- 使用 GitHub Actions 内置 `GITHUB_TOKEN` 发布当前仓库 Release。
- 若访问上游公开仓库 API 触发限流，可配置 `GH_TOKEN` 或使用 `GITHUB_TOKEN`。
- 不应在日志中输出任何 token。

### 4.2 权限

GitHub Actions workflow 需要以下权限：

```yaml
permissions:
  contents: write
  actions: read
```

### 4.3 幂等性

同一个上游 `run_id` 不应重复创建 Release 或重复更新状态。

### 4.4 可观测性

每次运行需要输出：

- 当前检测的上游工作流。
- 找到的最新成功 run ID。
- 是否找到 `BetterGI_7z`。
- 当前本地已发布版本。
- 是否跳过、发布或失败。

### 4.5 失败处理

以下情况应失败并保留原状态：

- GitHub API 请求失败。
- 没有权限下载 Artifact。
- Artifact 已过期。
- Release 创建失败。
- Release 资产上传失败。

以下情况可正常跳过：

- 没有任何成功的上游工作流运行。
- 最新成功运行没有 `BetterGI_7z` Artifact。
- 最新成功运行已经发布过。

## 5. 推荐项目结构

```text
bgi-release-sync/
  .github/
    workflows/
      sync-bettergi.yml
  docs/
    requirements.md
  scripts/
    sync-bettergi.ps1
  state/
    latest.json
  README.md
```

## 6. 推荐实现方案

优先使用 GitHub CLI `gh` 实现，减少手写鉴权逻辑：

1. `gh api` 查询上游 workflow runs。
2. `gh api` 查询目标 run 的 artifacts。
3. 使用 nightly.link 的指定 run 链接下载 Artifact，避免直接请求 GitHub Artifact ZIP API。
4. 解压 Artifact zip，识别 `BetterGI_*.7z` 发布包和版本号。
5. `gh release create` 创建 Release。
6. `gh release upload` 上传资产。
7. 使用脚本更新 `state/latest.json`。
8. 将状态文件提交回仓库。

状态文件提交建议：

```text
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add state/latest.json
git commit -m "chore: update BetterGI sync state"
git push
```

若没有状态变化，则不提交。

## 7. GitHub Actions 触发设计

Workflow 文件建议命名：

```text
.github/workflows/sync-bettergi.yml
```

触发器：

```yaml
on:
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch:
```

运行环境：

```yaml
runs-on: ubuntu-latest
```

并发控制：

```yaml
concurrency:
  group: sync-bettergi
  cancel-in-progress: false
```

## 8. 验收标准

1. 仓库中存在完整需求文档。
2. GitHub Actions 可每 1 小时自动运行一次。
3. 手动触发 Actions 后可完成一次检测。
4. 当上游最新成功构建包含 `BetterGI_7z` 且未发布过时，本仓库生成新的 Release。
5. Release 中包含从 `BetterGI_7z.zip` 解压得到的 `BetterGI_*.7z` 发布包。
6. `state/latest.json` 记录最新已发布版本。
7. 重复运行不会重复发布同一个上游构建。

## 9. 后续可选增强

1. 支持只保留最近 N 个 Release。
2. 支持将 Release 标记为 prerelease。
3. 支持解析 BetterGI 真实版本号并使用语义化 tag。
4. 支持在发布失败时发送通知。
5. 支持校验 Artifact 解压后的文件结构或哈希值。
