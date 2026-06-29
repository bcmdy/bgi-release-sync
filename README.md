# BGI Release Sync

该项目用于定时检测 `kaedelcb/better-genshin-impact` 的 `publish.yml` 工作流是否存在最新成功构建；如果存在新的 `BetterGI_7z` Artifact，则下载并发布到本仓库 Release，同时记录已发布版本。

需求文档见：[docs/requirements.md](docs/requirements.md)

## 实现方式

- `.github/workflows/sync-bettergi.yml` 每小时运行一次，也支持手动触发。
- `scripts/sync-bettergi.ps1` 使用 GitHub CLI 查询上游 workflow，并通过 nightly.link 的指定 run 链接下载 `BetterGI_7z` Artifact。
- 脚本会解压 `BetterGI_7z.zip`，自动识别其中的 `BetterGI_*.7z` 文件作为发布包，并从文件名提取版本号。
- Release tag 使用识别出的版本号，例如 `v0.61.3+lcb.22.4-OnLine-test22`，Release 资产为 `BetterGI_v0.61.3+lcb.22.4-OnLine-test22.7z`。
- `state/latest.json` 只会在 Release 和资产发布成功后更新，用于避免重复发布同一个上游构建。

GitHub Actions 的定时任务使用 UTC 时间；当前配置为每小时第 13 和 43 分钟尝试触发，以降低 GitHub schedule 延迟或丢弃的影响。同步脚本是幂等的，重复运行不会重复发布同一个上游构建。

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

## Ubuntu 服务器下载最新发布包

服务器只需要安装 `bash`、`curl` 和 `python3`：

```bash
curl -fsSL https://raw.githubusercontent.com/bcmdy/bgi-release-sync/main/scripts/download-latest-bettergi.sh -o download-latest-bettergi.sh
chmod +x download-latest-bettergi.sh
./download-latest-bettergi.sh -d /opt/bettergi
```

脚本会读取 `https://github.com/bcmdy/bgi-release-sync/releases.atom` 的第一条记录获取最新版本号，并按 `BetterGI_{tag}.7z` 规则下载对应 Release 资产到指定目录。若服务器无法直连 GitHub，脚本会按内置镜像列表逐个测试 `releases.atom` 和发布资产下载地址，选择第一个可用镜像下载。资产镜像已包含 `https://gh.sevencdn.com/https://github.com`。

可选参数示例：

```bash
BGI_TEST_TIMEOUT=8 ./download-latest-bettergi.sh -d /opt/bettergi --force
```

如果服务器访问默认 Atom 地址不稳定，可以指定一个你测试可用的 Atom 镜像；也可以分别覆盖 Atom feed 和资产下载镜像列表：

```bash
BGI_ATOM_URL="https://你的镜像/..." \
BGI_FEED_MIRRORS="https://gh.jasonzeng.dev/https://github.com https://github.com" \
BGI_ASSET_MIRRORS="https://gh.sevencdn.com/https://github.com https://gh.jasonzeng.dev/https://github.com" \
./download-latest-bettergi.sh -d /opt/bettergi
```

## Windows 下载最新发布包

Windows 10/11 可直接使用自带 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\download-latest-bettergi.ps1 -Dir C:\BetterGI
```

也可以从 `cmd.exe` 调用包装脚本：

```cmd
scripts\download-latest-bettergi.cmd -Dir C:\BetterGI
```

脚本参数与 Ubuntu 版本保持一致：默认读取 `bcmdy/bgi-release-sync` 的最新 Release，按 `BetterGI_{tag}.7z` 规则下载到指定目录；如果文件已存在则跳过，使用 `-Force` 可覆盖。镜像和超时配置同样支持环境变量，例如：

```powershell
$env:BGI_TEST_TIMEOUT = "8"
$env:BGI_ASSET_MIRRORS = "https://gh.sevencdn.com/https://github.com https://github.com"
powershell -ExecutionPolicy Bypass -File .\scripts\download-latest-bettergi.ps1 -Dir C:\BetterGI -Force
```
