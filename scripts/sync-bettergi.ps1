param(
    [string]$StatePath = "state/latest.json",
    [string]$DownloadDir = "dist",
    [string]$TargetRepository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DefaultState = [ordered]@{
    upstream_owner             = "kaedelcb"
    upstream_repo              = "better-genshin-impact"
    workflow                   = "publish.yml"
    artifact_name              = "BetterGI_7z"
    last_published_version     = $null
    last_published_run_id      = $null
    last_published_artifact_id = $null
    last_published_at          = $null
}

function Write-Log {
    param([string]$Message)
    Write-Host "[bgi-sync] $Message"
}

function Read-State {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$DefaultState
    }

    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($content)) {
        return [pscustomobject]$DefaultState
    }

    $state = $content | ConvertFrom-Json
    foreach ($key in $DefaultState.Keys) {
        if (-not ($state.PSObject.Properties.Name -contains $key)) {
            $state | Add-Member -NotePropertyName $key -NotePropertyValue $DefaultState[$key]
        }
    }

    return $state
}

function Write-State {
    param(
        [string]$Path,
        [object]$State
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path (Get-Location) $Path
    }

    $directory = Split-Path -Parent $fullPath
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $json = $State | ConvertTo-Json -Depth 10
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($fullPath, "$json`n", $utf8NoBom)
}

function Invoke-GhApiJson {
    param([string[]]$Arguments)

    $output = & gh api @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        throw "gh api failed: gh api $($Arguments -join ' ')`n$text"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json -Depth 100
}

function Invoke-GhJson {
    param([string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    return [pscustomobject]@{
        ExitCode = $exitCode
        Text     = $text
        Json     = if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($text)) { $text | ConvertFrom-Json -Depth 100 } else { $null }
    }
}

function Get-TargetRepository {
    param([string]$Repository)

    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        return $Repository
    }

    $result = Invoke-GhJson -Arguments @("repo", "view", "--json", "nameWithOwner")
    if ($result.ExitCode -ne 0) {
        throw "Target repository is not set. Run in GitHub Actions or pass -TargetRepository owner/repo."
    }

    return $result.Json.nameWithOwner
}

function Get-Release {
    param(
        [string]$Repository,
        [string]$Tag
    )

    $result = Invoke-GhJson -Arguments @("release", "view", $Tag, "--repo", $Repository, "--json", "tagName,name,url,assets")
    if ($result.ExitCode -eq 0) {
        return $result.Json
    }

    if ($result.Text -match "not found|HTTP 404|release not found") {
        return $null
    }

    throw "Failed to inspect release $Tag in ${Repository}: $($result.Text)"
}

function Invoke-Gh {
    param([string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        throw "gh command failed: gh $($Arguments -join ' ')`n$text"
    }

    return $text
}

function Get-GitHubToken {
    foreach ($name in @("GH_TOKEN", "GITHUB_TOKEN")) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return $null
}

function Download-Artifact {
    param(
        [string]$Owner,
        [string]$Repo,
        [long]$ArtifactId,
        [string]$OutFile
    )

    $token = Get-GitHubToken
    $headers = @{
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }

    $uri = "https://api.github.com/repos/$Owner/$Repo/actions/artifacts/$ArtifactId/zip"
    Write-Log "Downloading artifact $ArtifactId to $OutFile"
    Invoke-WebRequest -Uri $uri -Headers $headers -OutFile $OutFile -MaximumRedirection 10
}

function Get-AssetNames {
    param([object]$Release)

    if (-not $Release -or -not ($Release.PSObject.Properties.Name -contains "assets") -or -not $Release.assets) {
        return @()
    }

    return @($Release.assets | ForEach-Object { $_.name })
}

$state = Read-State -Path $StatePath
$targetRepository = Get-TargetRepository -Repository $TargetRepository

$upstreamOwner = $state.upstream_owner
$upstreamRepo = $state.upstream_repo
$workflow = $state.workflow
$artifactName = $state.artifact_name
$upstreamSlug = "$upstreamOwner/$upstreamRepo"

Write-Log "Checking upstream workflow $upstreamSlug/$workflow"
Write-Log "Current published run: $($state.last_published_run_id)"
Write-Log "Target release repository: $targetRepository"

$runsResponse = Invoke-GhApiJson -Arguments @(
    "--method", "GET",
    "repos/$upstreamOwner/$upstreamRepo/actions/workflows/$workflow/runs",
    "-f", "status=success",
    "-f", "per_page=10"
)

$runs = @($runsResponse.workflow_runs | Where-Object {
        $_.status -eq "completed" -and $_.conclusion -eq "success"
    } | Sort-Object -Property @{ Expression = {
            if ($_.run_started_at) { [datetime]$_.run_started_at } else { [datetime]$_.created_at }
        }; Descending = $true })

if ($runs.Count -eq 0) {
    Write-Log "No successful upstream workflow runs found. Skipping."
    exit 0
}

$selectedRun = $runs[0]
Write-Log "Latest successful run: $($selectedRun.id)"

$artifactsResponse = Invoke-GhApiJson -Arguments @(
    "--method", "GET",
    "repos/$upstreamOwner/$upstreamRepo/actions/runs/$($selectedRun.id)/artifacts",
    "-f", "per_page=100"
)

$artifact = @($artifactsResponse.artifacts | Where-Object { $_.name -eq $artifactName } | Select-Object -First 1)
if ($artifact.Count -eq 0) {
    Write-Log "Latest successful run $($selectedRun.id) does not contain artifact $artifactName. Skipping."
    exit 0
}
$selectedArtifact = $artifact[0]

$runId = [long]$selectedRun.id
$artifactId = [long]$selectedArtifact.id
$version = "upstream-run-$runId"
$tag = $version
$assetName = "$artifactName-$version.zip"
$releaseTitle = "BetterGI build $runId"
$syncedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Log "Latest publishable run: $runId"
Write-Log "Found artifact: $artifactName ($artifactId)"

if ($state.last_published_run_id -eq $runId) {
    Write-Log "Run $runId is already recorded in $StatePath. Skipping."
    exit 0
}

$release = Get-Release -Repository $targetRepository -Tag $tag
$assetNames = Get-AssetNames -Release $release
$assetAlreadyUploaded = $assetNames -contains $assetName

if ($release -and $assetAlreadyUploaded) {
    Write-Log "Release $tag and asset $assetName already exist. Updating local state only."
    $newState = [ordered]@{
        upstream_owner             = $upstreamOwner
        upstream_repo              = $upstreamRepo
        workflow                   = $workflow
        artifact_name              = $artifactName
        last_published_version     = $version
        last_published_run_id      = $runId
        last_published_artifact_id = $artifactId
        last_published_at          = $syncedAt
    }
    Write-State -Path $StatePath -State $newState
    exit 0
}

if ($selectedArtifact.expired -eq $true) {
    throw "Artifact $artifactId for run $runId is expired. State was not updated."
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$assetPath = Join-Path $DownloadDir $assetName
if (Test-Path -LiteralPath $assetPath) {
    Remove-Item -LiteralPath $assetPath -Force
}

Download-Artifact -Owner $upstreamOwner -Repo $upstreamRepo -ArtifactId $artifactId -OutFile $assetPath

if (-not (Test-Path -LiteralPath $assetPath) -or ((Get-Item -LiteralPath $assetPath).Length -le 0)) {
    throw "Downloaded artifact is missing or empty: $assetPath"
}

$releaseNotes = @"
Synced from upstream BetterGI workflow.

- Upstream repository: https://github.com/$upstreamSlug
- Workflow run: $($selectedRun.html_url)
- Artifact ID: $artifactId
- Upstream commit: $($selectedRun.head_sha)
- Synced at: $syncedAt
"@

if (-not $release) {
    Write-Log "Creating release $tag"
    Invoke-Gh -Arguments @(
        "release", "create", $tag, $assetPath,
        "--repo", $targetRepository,
        "--title", $releaseTitle,
        "--notes", $releaseNotes
    ) | Out-Null
}
else {
    Write-Log "Release $tag exists but asset $assetName is missing. Uploading asset."
    Invoke-Gh -Arguments @(
        "release", "upload", $tag, $assetPath,
        "--repo", $targetRepository
    ) | Out-Null
}

$newState = [ordered]@{
    upstream_owner             = $upstreamOwner
    upstream_repo              = $upstreamRepo
    workflow                   = $workflow
    artifact_name              = $artifactName
    last_published_version     = $version
    last_published_run_id      = $runId
    last_published_artifact_id = $artifactId
    last_published_at          = $syncedAt
}

Write-State -Path $StatePath -State $newState
Write-Log "Published $tag and updated $StatePath"
