#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${BGI_RELEASE_SYNC_REPO:-bcmdy/bgi-release-sync}"
OUTPUT_DIR="${BGI_DOWNLOAD_DIR:-.}"
ASSET_TEMPLATE="${BGI_ASSET_TEMPLATE:-BetterGI_{tag}.7z}"
FORCE=0
CONNECT_TIMEOUT="${BGI_CONNECT_TIMEOUT:-10}"
TEST_TIMEOUT="${BGI_TEST_TIMEOUT:-20}"
DOWNLOAD_TIMEOUT="${BGI_DOWNLOAD_TIMEOUT:-0}"

GITHUB_FEED_MIRRORS=(
  "https://gh.jasonzeng.dev/https://github.com"
  "https://cdn.crashmc.com/https://github.com"
  "https://gh.idayer.com/https://github.com"
  "https://github.com"
  "https://gh.sevencdn.com/https://github.com"
  "https://edgeone.gh-proxy.org/https://github.com"
  "https://cdn.gh-proxy.org/https://github.com"
  "https://gh-proxy.org/https://github.com"
  "https://github.ednovas.xyz/https://github.com"
  "https://gh.monlor.com/https://github.com"
  "https://gh.ddlc.top/https://github.com"
  "https://raw.ihtw.moe/github.com"
  "https://gitproxy.mrhjx.cn/https://github.com"
  "https://git.yylx.win/https://github.com"
  "https://cors.isteed.cc/github.com"
  "https://ghfast.top/https://github.com"
  "https://wget.la/https://github.com"
  "https://hk.gh-proxy.org/https://github.com"
)

GITHUB_ASSET_MIRRORS=(
  "https://gh.jasonzeng.dev/https://github.com"
  "https://edgeone.gh-proxy.org/https://github.com"
  "https://cdn.gh-proxy.org/https://github.com"
  "https://gh-proxy.org/https://github.com"
  "https://cdn.crashmc.com/https://github.com"
  "https://github.com"
  "https://github.ednovas.xyz/https://github.com"
  "https://gh.idayer.com/https://github.com"
  "https://gh.monlor.com/https://github.com"
  "https://gh.ddlc.top/https://github.com"
  "https://raw.ihtw.moe/github.com"
  "https://gitproxy.mrhjx.cn/https://github.com"
  "https://git.yylx.win/https://github.com"
  "https://ghproxy.monkeyray.net/https://github.com"
  "https://cors.isteed.cc/github.com"
  "https://ghproxy.it/https://github.com"
  "https://gh.zwy.one/https://github.com"
  "https://github.tbedu.top/https://github.com"
  "https://wget.la/https://github.com"
  "https://ghfile.geekertao.top/https://github.com"
  "https://ghfast.top/https://github.com"
  "https://hk.gh-proxy.org/https://github.com"
  "https://ghproxy.net/https://github.com"
  "https://gh.sevencdn.com/https://github.com"
  "https://gh.h233.eu.org/https://github.com"
  "https://rapidgit.jjda.de5.net/https://github.com"
  "https://github.boki.moe/https://github.com"
  "https://github.geekery.cn/https://github.com"
  "https://ghp.keleyaa.com/https://github.com"
  "https://gh.chjina.com/https://github.com"
  "https://ghpxy.hwinzniej.top/https://github.com"
  "https://ghproxy.cxkpro.top/https://github.com"
  "https://gh.xxooo.cf/https://github.com"
  "https://down.npee.cn/?https://github.com"
  "https://xget.xi-xu.me/gh"
  "https://githubfast.com"
)

if [[ -n "${BGI_GITHUB_MIRRORS:-}" ]]; then
  read -r -a GITHUB_FEED_MIRRORS <<< "$BGI_GITHUB_MIRRORS"
  read -r -a GITHUB_ASSET_MIRRORS <<< "$BGI_GITHUB_MIRRORS"
fi
if [[ -n "${BGI_FEED_MIRRORS:-}" ]]; then
  read -r -a GITHUB_FEED_MIRRORS <<< "$BGI_FEED_MIRRORS"
fi
if [[ -n "${BGI_ASSET_MIRRORS:-}" ]]; then
  read -r -a GITHUB_ASSET_MIRRORS <<< "$BGI_ASSET_MIRRORS"
fi

usage() {
  cat <<'EOF'
Download the latest BetterGI package from bcmdy/bgi-release-sync releases.

Usage:
  download-latest-bettergi.sh [-d DIR] [--repo OWNER/REPO] [--force]

Options:
  -d, --dir DIR        Directory to save the downloaded package. Default: current directory.
  -r, --repo REPO      GitHub repository. Default: bcmdy/bgi-release-sync.
  -f, --force          Overwrite the local file if it already exists.
  -h, --help           Show this help.

Environment:
  BGI_DOWNLOAD_DIR     Default download directory.
  BGI_RELEASE_SYNC_REPO Default source repository.
  BGI_ASSET_TEMPLATE   Asset name template. Default: BetterGI_{tag}.7z.
  BGI_ATOM_URL         Override release Atom feed URL.
  BGI_GITHUB_MIRRORS   Space-separated mirror prefixes for both feed and assets.
  BGI_FEED_MIRRORS     Space-separated mirror prefixes for releases.atom.
  BGI_ASSET_MIRRORS    Space-separated mirror prefixes for release assets.
  BGI_CONNECT_TIMEOUT  Curl connect timeout in seconds. Default: 10.
  BGI_TEST_TIMEOUT     Mirror test timeout in seconds. Default: 20.
  BGI_DOWNLOAD_TIMEOUT Curl download max time in seconds. Default: 0, unlimited.
EOF
}

log() {
  printf '[bgi-download] %s\n' "$*"
}

fail() {
  printf '[bgi-download] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

github_mirror_url() {
  local original_url="$1"
  local mirror="$2"

  if [[ "$original_url" != https://github.com/* ]]; then
    printf '%s\n' "$original_url"
    return
  fi

  if [[ "$mirror" == "https://github.com" ]]; then
    printf '%s\n' "$original_url"
  else
    printf '%s%s\n' "$mirror" "${original_url#https://github.com}"
  fi
}

parse_release_feed() {
  python3 - "$1" "$REPO" "$ASSET_TEMPLATE" <<'PY'
import sys
import urllib.parse
import xml.etree.ElementTree as ET

feed_path, repo, asset_template = sys.argv[1], sys.argv[2], sys.argv[3]
ns = {"atom": "http://www.w3.org/2005/Atom"}
root = ET.parse(feed_path).getroot()
entry = root.find("atom:entry", ns)
if entry is None:
    print("No release entries found in releases.atom", file=sys.stderr)
    sys.exit(2)

link = entry.find("atom:link[@rel='alternate']", ns)
href = link.attrib.get("href", "") if link is not None else ""
tag = urllib.parse.unquote(href.rstrip("/").split("/")[-1]) if href else ""
if not tag:
    title = entry.findtext("atom:title", default="", namespaces=ns).strip()
    tag = title.split()[-1] if title else ""
if not tag:
    print("Could not determine latest release tag from releases.atom", file=sys.stderr)
    sys.exit(2)

asset_name = asset_template.replace("{tag}", tag)
download_url = (
    f"https://github.com/{repo}/releases/download/"
    f"{urllib.parse.quote(tag, safe='')}/"
    f"{urllib.parse.quote(asset_name, safe='+')}"
)

print(tag)
print(asset_name)
print(download_url)
PY
}

fetch_latest_release_feed() {
  local original_url="$1"
  local output_file="$2"
  local mirror url info

  if [[ "$original_url" != https://github.com/* ]]; then
    log "Testing release feed URL: $original_url" >&2
    curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$TEST_TIMEOUT" "$original_url" -o "$output_file"
    parse_release_feed "$output_file"
    return
  fi

  for mirror in "${GITHUB_FEED_MIRRORS[@]}"; do
    url="$(github_mirror_url "$original_url" "$mirror")"
    log "Testing release feed mirror: $url" >&2
    if curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$TEST_TIMEOUT" "$url" -o "$output_file"; then
      if info="$(parse_release_feed "$output_file")"; then
        printf '%s\n' "$info"
        log "Using release feed mirror: $url" >&2
        return 0
      fi
      log "Mirror returned an invalid release feed: $url" >&2
    fi
  done

  return 1
}

test_download_url() {
  local url="$1"

  curl -fsSIL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$TEST_TIMEOUT" "$url" -o /dev/null ||
    curl -fsSL --range 0-0 --connect-timeout "$CONNECT_TIMEOUT" --max-time "$TEST_TIMEOUT" "$url" -o /dev/null
}

select_download_url() {
  local original_url="$1"
  local mirror url

  for mirror in "${GITHUB_ASSET_MIRRORS[@]}"; do
    url="$(github_mirror_url "$original_url" "$mirror")"
    log "Testing asset mirror: $url" >&2
    if test_download_url "$url"; then
      printf '%s\n' "$url"
      return 0
    fi
  done

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || fail "$1 requires a directory"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -r|--repo)
      [[ $# -ge 2 ]] || fail "$1 requires OWNER/REPO"
      REPO="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$REPO" == */* ]] || fail "Repository must be in OWNER/REPO format: $REPO"

require_command curl
require_command python3

mkdir -p "$OUTPUT_DIR"

ATOM_URL="${BGI_ATOM_URL:-https://github.com/${REPO}/releases.atom}"
TMP_FEED="$(mktemp)"
trap 'rm -f "$TMP_FEED" "${TMP_DOWNLOAD:-}"' EXIT

log "Fetching latest release feed from ${ATOM_URL}"
RELEASE_INFO_TEXT="$(fetch_latest_release_feed "$ATOM_URL" "$TMP_FEED")" || fail "Could not fetch a valid releases.atom through any mirror"
mapfile -t RELEASE_INFO <<< "$RELEASE_INFO_TEXT"
[[ "${#RELEASE_INFO[@]}" -ge 3 ]] || fail "Could not parse release information from releases.atom"

TAG="${RELEASE_INFO[0]}"
ASSET_NAME="${RELEASE_INFO[1]}"
DOWNLOAD_URL="${RELEASE_INFO[2]}"
TARGET_PATH="${OUTPUT_DIR%/}/${ASSET_NAME}"

log "Latest release: ${TAG}"
log "Selected asset: ${ASSET_NAME}"

if [[ -f "$TARGET_PATH" && "$FORCE" -ne 1 ]]; then
  log "File already exists, skipping download: ${TARGET_PATH}"
  log "Use --force to overwrite."
  printf '%s\n' "$TARGET_PATH"
  exit 0
fi

TMP_DOWNLOAD="$(mktemp "${TARGET_PATH}.tmp.XXXXXX")"
log "Selecting asset download mirror"
SELECTED_DOWNLOAD_URL="$(select_download_url "$DOWNLOAD_URL")" || fail "Could not find a reachable mirror for ${DOWNLOAD_URL}"

log "Downloading to ${TARGET_PATH}"
curl -fL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$DOWNLOAD_TIMEOUT" "$SELECTED_DOWNLOAD_URL" -o "$TMP_DOWNLOAD"

if [[ ! -s "$TMP_DOWNLOAD" ]]; then
  fail "Downloaded file is empty"
fi

mv -f "$TMP_DOWNLOAD" "$TARGET_PATH"
log "Done: ${TARGET_PATH}"
printf '%s\n' "$TARGET_PATH"
