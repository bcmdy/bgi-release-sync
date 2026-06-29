param(
    [Alias("d")]
    [string]$Dir = $(if ($env:BGI_DOWNLOAD_DIR) { $env:BGI_DOWNLOAD_DIR } else { "." }),

    [Alias("r")]
    [string]$Repo = $(if ($env:BGI_RELEASE_SYNC_REPO) { $env:BGI_RELEASE_SYNC_REPO } else { "bcmdy/bgi-release-sync" }),

    [switch]$Force,

    [string]$AssetTemplate = $(if ($env:BGI_ASSET_TEMPLATE) { $env:BGI_ASSET_TEMPLATE } else { "BetterGI_{tag}.7z" }),

    [string]$AtomUrl = $env:BGI_ATOM_URL,

    [int]$ConnectTimeout = $(if ($env:BGI_CONNECT_TIMEOUT) { [int]$env:BGI_CONNECT_TIMEOUT } else { 10 }),

    [int]$TestTimeout = $(if ($env:BGI_TEST_TIMEOUT) { [int]$env:BGI_TEST_TIMEOUT } else { 20 }),

    [int]$DownloadTimeout = $(if ($env:BGI_DOWNLOAD_TIMEOUT) { [int]$env:BGI_DOWNLOAD_TIMEOUT } else { 0 })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DefaultFeedMirrors = @(
    "https://gh.jasonzeng.dev/https://github.com",
    "https://cdn.crashmc.com/https://github.com",
    "https://gh.idayer.com/https://github.com",
    "https://github.com",
    "https://gh.sevencdn.com/https://github.com",
    "https://edgeone.gh-proxy.org/https://github.com",
    "https://cdn.gh-proxy.org/https://github.com",
    "https://gh-proxy.org/https://github.com",
    "https://github.ednovas.xyz/https://github.com",
    "https://gh.monlor.com/https://github.com",
    "https://gh.ddlc.top/https://github.com",
    "https://raw.ihtw.moe/github.com",
    "https://gitproxy.mrhjx.cn/https://github.com",
    "https://git.yylx.win/https://github.com",
    "https://cors.isteed.cc/github.com",
    "https://ghfast.top/https://github.com",
    "https://wget.la/https://github.com",
    "https://hk.gh-proxy.org/https://github.com"
)

$DefaultAssetMirrors = @(
    "https://gh.jasonzeng.dev/https://github.com",
    "https://edgeone.gh-proxy.org/https://github.com",
    "https://cdn.gh-proxy.org/https://github.com",
    "https://gh-proxy.org/https://github.com",
    "https://cdn.crashmc.com/https://github.com",
    "https://github.com",
    "https://github.ednovas.xyz/https://github.com",
    "https://gh.idayer.com/https://github.com",
    "https://gh.monlor.com/https://github.com",
    "https://gh.ddlc.top/https://github.com",
    "https://raw.ihtw.moe/github.com",
    "https://gitproxy.mrhjx.cn/https://github.com",
    "https://git.yylx.win/https://github.com",
    "https://ghproxy.monkeyray.net/https://github.com",
    "https://cors.isteed.cc/github.com",
    "https://ghproxy.it/https://github.com",
    "https://gh.zwy.one/https://github.com",
    "https://github.tbedu.top/https://github.com",
    "https://wget.la/https://github.com",
    "https://ghfile.geekertao.top/https://github.com",
    "https://ghfast.top/https://github.com",
    "https://hk.gh-proxy.org/https://github.com",
    "https://ghproxy.net/https://github.com",
    "https://gh.sevencdn.com/https://github.com",
    "https://gh.h233.eu.org/https://github.com",
    "https://rapidgit.jjda.de5.net/https://github.com",
    "https://github.boki.moe/https://github.com",
    "https://github.geekery.cn/https://github.com",
    "https://ghp.keleyaa.com/https://github.com",
    "https://gh.chjina.com/https://github.com",
    "https://ghpxy.hwinzniej.top/https://github.com",
    "https://ghproxy.cxkpro.top/https://github.com",
    "https://gh.xxooo.cf/https://github.com",
    "https://down.npee.cn/?https://github.com",
    "https://xget.xi-xu.me/gh",
    "https://githubfast.com"
)

function Write-Log {
    param([string]$Message)
    Write-Host "[bgi-download] $Message"
}

function Split-MirrorList {
    param(
        [string]$Value,
        [string[]]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    return @($Value -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-GitHubMirrorUrl {
    param(
        [string]$OriginalUrl,
        [string]$Mirror
    )

    if (-not $OriginalUrl.StartsWith("https://github.com/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $OriginalUrl
    }

    if ($Mirror -eq "https://github.com") {
        return $OriginalUrl
    }

    return "$Mirror$($OriginalUrl.Substring("https://github.com".Length))"
}

function Invoke-WebDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$TimeoutSeconds
    )

    $parameters = @{
        Uri                = $Url
        OutFile            = $OutFile
        MaximumRedirection = 10
        TimeoutSec         = $TimeoutSeconds
        UseBasicParsing    = $true
    }

    Invoke-WebRequest @parameters
}

function Test-DownloadUrl {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "HEAD"
        $request.AllowAutoRedirect = $true
        $request.Timeout = $TimeoutSeconds * 1000
        $request.ReadWriteTimeout = $TimeoutSeconds * 1000
        $response = $request.GetResponse()
        $response.Dispose()
        return $true
    }
    catch {
        try {
            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.Method = "GET"
            $request.AddRange(0, 0)
            $request.AllowAutoRedirect = $true
            $request.Timeout = $TimeoutSeconds * 1000
            $request.ReadWriteTimeout = $TimeoutSeconds * 1000
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $buffer = [byte[]]::new(1)
            [void]$stream.Read($buffer, 0, 1)
            $stream.Dispose()
            $response.Dispose()
            return $true
        }
        catch {
            return $false
        }
    }
}

function Get-LatestReleaseInfo {
    param(
        [string]$FeedPath,
        [string]$Repository,
        [string]$Template
    )

    [xml]$feed = Get-Content -Raw -Encoding UTF8 -LiteralPath $FeedPath
    $namespace = New-Object System.Xml.XmlNamespaceManager($feed.NameTable)
    $namespace.AddNamespace("atom", "http://www.w3.org/2005/Atom")

    $entry = $feed.SelectSingleNode("/atom:feed/atom:entry", $namespace)
    if (-not $entry) {
        throw "No release entries found in releases.atom"
    }

    $link = $entry.SelectSingleNode("atom:link[@rel='alternate']", $namespace)
    $href = if ($link -and $link.Attributes["href"]) { $link.Attributes["href"].Value } else { "" }
    $tag = ""
    if (-not [string]::IsNullOrWhiteSpace($href)) {
        $tag = [System.Uri]::UnescapeDataString(($href.TrimEnd("/") -split "/")[-1])
    }

    if ([string]::IsNullOrWhiteSpace($tag)) {
        $title = $entry.SelectSingleNode("atom:title", $namespace)
        if ($title -and -not [string]::IsNullOrWhiteSpace($title.InnerText)) {
            $tag = ($title.InnerText.Trim() -split "\s+")[-1]
        }
    }

    if ([string]::IsNullOrWhiteSpace($tag)) {
        throw "Could not determine latest release tag from releases.atom"
    }

    $assetName = $Template.Replace("{tag}", $tag)
    $encodedTag = [System.Uri]::EscapeDataString($tag)
    $encodedAssetName = [System.Uri]::EscapeDataString($assetName).Replace("%2B", "+")
    $downloadUrl = "https://github.com/$Repository/releases/download/$encodedTag/$encodedAssetName"

    return [pscustomobject]@{
        Tag         = $tag
        AssetName   = $assetName
        DownloadUrl = $downloadUrl
    }
}

function Get-ReleaseInfoFromFeedMirrors {
    param(
        [string]$OriginalUrl,
        [string[]]$Mirrors,
        [string]$FeedPath
    )

    if (-not $OriginalUrl.StartsWith("https://github.com/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Log "Testing release feed URL: $OriginalUrl"
        Invoke-WebDownload -Url $OriginalUrl -OutFile $FeedPath -TimeoutSeconds $TestTimeout
        return Get-LatestReleaseInfo -FeedPath $FeedPath -Repository $Repo -Template $AssetTemplate
    }

    foreach ($mirror in $Mirrors) {
        $url = Get-GitHubMirrorUrl -OriginalUrl $OriginalUrl -Mirror $mirror
        Write-Log "Testing release feed mirror: $url"

        try {
            Invoke-WebDownload -Url $url -OutFile $FeedPath -TimeoutSeconds $TestTimeout
            $info = Get-LatestReleaseInfo -FeedPath $FeedPath -Repository $Repo -Template $AssetTemplate
            Write-Log "Using release feed mirror: $url"
            return $info
        }
        catch {
            Write-Log "Release feed mirror failed or returned invalid feed: $url"
        }
    }

    throw "Could not fetch a valid releases.atom through any mirror"
}

function Select-AssetDownloadUrl {
    param(
        [string]$OriginalUrl,
        [string[]]$Mirrors
    )

    foreach ($mirror in $Mirrors) {
        $url = Get-GitHubMirrorUrl -OriginalUrl $OriginalUrl -Mirror $mirror
        Write-Log "Testing asset mirror: $url"
        if (Test-DownloadUrl -Url $url -TimeoutSeconds $TestTimeout) {
            return $url
        }
    }

    throw "Could not find a reachable mirror for $OriginalUrl"
}

if ($Repo -notmatch "^[^/]+/[^/]+$") {
    throw "Repository must be in OWNER/REPO format: $Repo"
}

$feedMirrors = Split-MirrorList -Value $env:BGI_GITHUB_MIRRORS -Default $DefaultFeedMirrors
$assetMirrors = Split-MirrorList -Value $env:BGI_GITHUB_MIRRORS -Default $DefaultAssetMirrors
$feedMirrors = Split-MirrorList -Value $env:BGI_FEED_MIRRORS -Default $feedMirrors
$assetMirrors = Split-MirrorList -Value $env:BGI_ASSET_MIRRORS -Default $assetMirrors

if ([string]::IsNullOrWhiteSpace($AtomUrl)) {
    $AtomUrl = "https://github.com/$Repo/releases.atom"
}

$targetDirectory = if ([System.IO.Path]::IsPathRooted($Dir)) {
    $Dir
}
else {
    Join-Path (Get-Location) $Dir
}
New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null

$temporaryFeed = Join-Path ([System.IO.Path]::GetTempPath()) "bgi-release-feed-$([System.Guid]::NewGuid()).xml"
$temporaryDownload = $null

try {
    Write-Log "Fetching latest release feed from $AtomUrl"
    $releaseInfo = Get-ReleaseInfoFromFeedMirrors -OriginalUrl $AtomUrl -Mirrors $feedMirrors -FeedPath $temporaryFeed

    $targetPath = Join-Path $targetDirectory $releaseInfo.AssetName
    Write-Log "Latest release: $($releaseInfo.Tag)"
    Write-Log "Selected asset: $($releaseInfo.AssetName)"

    if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
        Write-Log "File already exists, skipping download: $targetPath"
        Write-Log "Use -Force to overwrite."
        Write-Output $targetPath
        exit 0
    }

    Write-Log "Selecting asset download mirror"
    $selectedDownloadUrl = Select-AssetDownloadUrl -OriginalUrl $releaseInfo.DownloadUrl -Mirrors $assetMirrors

    $temporaryDownload = Join-Path $targetDirectory "$($releaseInfo.AssetName).tmp.$([System.Guid]::NewGuid().ToString("N"))"
    Write-Log "Downloading to $targetPath"
    $downloadTimeoutForRequest = if ($DownloadTimeout -gt 0) { $DownloadTimeout } else { 86400 }
    Invoke-WebDownload -Url $selectedDownloadUrl -OutFile $temporaryDownload -TimeoutSeconds ([int]$downloadTimeoutForRequest)

    $downloadedFile = Get-Item -LiteralPath $temporaryDownload
    if ($downloadedFile.Length -le 0) {
        throw "Downloaded file is empty"
    }

    Move-Item -LiteralPath $temporaryDownload -Destination $targetPath -Force
    $temporaryDownload = $null

    Write-Log "Done: $targetPath"
    Write-Output $targetPath
}
finally {
    if (Test-Path -LiteralPath $temporaryFeed) {
        Remove-Item -LiteralPath $temporaryFeed -Force
    }
    if ($temporaryDownload -and (Test-Path -LiteralPath $temporaryDownload)) {
        Remove-Item -LiteralPath $temporaryDownload -Force
    }
}
