#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


GITHUB_DIRECT = "https://github.com"
USER_AGENT = "bgi-release-sync-mirror-benchmark/1.0"
DOWNLOAD_SCRIPT_NAMES = (
    "download-latest-bettergi.sh",
    "download-latest-bettergi.ps1",
)

DEFAULT_FEED_MIRRORS = [
    "https://github.com",
    "https://gh.jasonzeng.dev/https://github.com",
    "https://cdn.crashmc.com/https://github.com",
    "https://gh.idayer.com/https://github.com",
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
    "https://hk.gh-proxy.org/https://github.com",
]

DEFAULT_ASSET_MIRRORS = [
    "https://github.com",
    "https://gh.jasonzeng.dev/https://github.com",
    "https://edgeone.gh-proxy.org/https://github.com",
    "https://cdn.gh-proxy.org/https://github.com",
    "https://gh-proxy.org/https://github.com",
    "https://cdn.crashmc.com/https://github.com",
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
    "https://githubfast.com",
]


@dataclass
class MirrorResult:
    mirror: str
    url: str
    ok: bool
    bytes_read: int
    seconds: float
    speed_bps: float
    error: str = ""

    @property
    def speed_mib_s(self):
        return self.speed_bps / 1024 / 1024


def log(message):
    print(f"[mirror-benchmark] {message}", file=sys.stderr)


def normalize_mirror(mirror):
    return mirror.strip().rstrip("/")


def move_github_first(mirrors):
    result = [GITHUB_DIRECT]
    seen = {GITHUB_DIRECT}

    for mirror in mirrors:
        mirror = normalize_mirror(mirror)
        if not mirror or mirror in seen:
            continue
        result.append(mirror)
        seen.add(mirror)

    return result


def github_mirror_url(original_url, mirror):
    if not original_url.lower().startswith(f"{GITHUB_DIRECT}/"):
        return original_url
    if mirror == GITHUB_DIRECT:
        return original_url
    return f"{mirror}{original_url[len(GITHUB_DIRECT):]}"


def request_bytes(url, timeout):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def parse_release_feed(feed_bytes, repo, asset_template):
    root = ET.fromstring(feed_bytes)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    entry = root.find("atom:entry", ns)
    if entry is None:
        raise ValueError("No release entries found in releases.atom")

    href = ""
    link = entry.find("atom:link[@rel='alternate']", ns)
    if link is not None:
        href = link.attrib.get("href", "")

    tag = urllib.parse.unquote(href.rstrip("/").split("/")[-1]) if href else ""
    if not tag:
        title = entry.findtext("atom:title", default="", namespaces=ns).strip()
        tag = title.split()[-1] if title else ""
    if not tag:
        raise ValueError("Could not determine latest release tag from releases.atom")

    asset_name = asset_template.replace("{tag}", tag)
    download_url = (
        f"{GITHUB_DIRECT}/{repo}/releases/download/"
        f"{urllib.parse.quote(tag, safe='')}/"
        f"{urllib.parse.quote(asset_name, safe='+')}"
    )
    return tag, asset_name, download_url


def fetch_latest_asset_url(repo, asset_template, atom_url, timeout):
    atom_url = atom_url or f"{GITHUB_DIRECT}/{repo}/releases.atom"
    feed_mirrors = move_github_first(DEFAULT_FEED_MIRRORS)

    if not atom_url.lower().startswith(f"{GITHUB_DIRECT}/"):
        feed_mirrors = [GITHUB_DIRECT]

    for mirror in feed_mirrors:
        url = github_mirror_url(atom_url, mirror)
        try:
            feed_bytes = request_bytes(url, timeout)
            tag, asset_name, download_url = parse_release_feed(
                feed_bytes,
                repo,
                asset_template,
            )
            log(f"Using release feed: {url}")
            log(f"Latest release: {tag}; asset: {asset_name}")
            return download_url
        except Exception as exc:
            log(f"Release feed failed: {url} ({exc})")

    raise RuntimeError("Could not fetch a valid releases.atom through any mirror")


def benchmark_once(mirror, original_url, sample_bytes, timeout, max_seconds, chunk_size):
    url = github_mirror_url(original_url, mirror)
    request = urllib.request.Request(
        url,
        headers={
            "Range": f"bytes=0-{sample_bytes - 1}",
            "User-Agent": USER_AGENT,
        },
    )

    total = 0
    started = None
    finished = None
    error = ""

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            started = time.perf_counter()
            deadline = started + max_seconds
            while total < sample_bytes:
                if time.perf_counter() >= deadline:
                    error = "sample window reached"
                    break

                chunk = response.read(min(chunk_size, sample_bytes - total))
                if not chunk:
                    break

                total += len(chunk)
            finished = time.perf_counter()
    except Exception as exc:
        error = str(exc)
        finished = time.perf_counter()

    if total <= 0 or started is None:
        return MirrorResult(
            mirror=mirror,
            url=url,
            ok=False,
            bytes_read=total,
            seconds=0,
            speed_bps=0,
            error=error or "no bytes read",
        )

    seconds = max(finished - started, 1e-9)
    return MirrorResult(
        mirror=mirror,
        url=url,
        ok=not error,
        bytes_read=total,
        seconds=seconds,
        speed_bps=total / seconds,
        error=error,
    )


def benchmark_mirror(mirror, original_url, sample_bytes, timeout, max_seconds, chunk_size, rounds):
    best = None
    for _ in range(rounds):
        result = benchmark_once(mirror, original_url, sample_bytes, timeout, max_seconds, chunk_size)
        if best is None or result.speed_bps > best.speed_bps:
            best = result
    return best


def result_sort_key(result):
    if result.mirror == GITHUB_DIRECT:
        return (2, 0)
    return (1 if result.bytes_read > 0 else 0, result.speed_bps)


def order_results(results):
    direct = [result for result in results if result.mirror == GITHUB_DIRECT]
    others = [result for result in results if result.mirror != GITHUB_DIRECT]
    others.sort(key=result_sort_key, reverse=True)
    return (direct[:1] or [MirrorResult(GITHUB_DIRECT, "", False, 0, 0, 0, "not tested")]) + others


def format_speed(result):
    if result.bytes_read <= 0:
        return "-"
    return f"{result.speed_mib_s:.2f} MiB/s"


def print_table(results, original_url):
    print(f"Asset URL: {original_url}")
    print()
    print(f"{'#':>2}  {'speed':>12}  {'bytes':>10}  {'seconds':>8}  mirror")
    for index, result in enumerate(results, 1):
        seconds = "-" if result.seconds <= 0 else f"{result.seconds:.2f}"
        status = "" if result.ok else f"  ({result.error})"
        print(
            f"{index:>2}  {format_speed(result):>12}  "
            f"{result.bytes_read:>10}  {seconds:>8}  {result.mirror}{status}"
        )

    print()
    print("BGI_ASSET_MIRRORS=" + " ".join(result.mirror for result in results))


def print_output(results, original_url, output_format):
    mirrors = [result.mirror for result in results]

    if output_format == "table":
        print_table(results, original_url)
    elif output_format == "list":
        print("\n".join(mirrors))
    elif output_format == "env":
        print(f'BGI_ASSET_MIRRORS="{" ".join(mirrors)}"')
    elif output_format == "bash":
        print(f'export BGI_ASSET_MIRRORS="{" ".join(mirrors)}"')
    elif output_format == "powershell":
        print(f'$env:BGI_ASSET_MIRRORS = "{" ".join(mirrors)}"')
    elif output_format == "json":
        print(
            json.dumps(
                {
                    "asset_url": original_url,
                    "mirrors": [
                        {
                            "mirror": result.mirror,
                            "url": result.url,
                            "ok": result.ok,
                            "bytes_read": result.bytes_read,
                            "seconds": result.seconds,
                            "speed_bps": result.speed_bps,
                            "speed_mib_s": result.speed_mib_s,
                            "error": result.error,
                        }
                        for result in results
                    ],
                },
                ensure_ascii=False,
                indent=2,
            )
        )


def read_mirror_file(path):
    mirrors = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            mirrors.extend(line.split())
    return mirrors


def format_shell_asset_mirrors(mirrors):
    lines = ["GITHUB_ASSET_MIRRORS=("]
    lines.extend(f'  "{mirror}"' for mirror in mirrors)
    lines.append(")")
    return "\n".join(lines)


def format_powershell_asset_mirrors(mirrors):
    lines = ["$DefaultAssetMirrors = @("]
    for index, mirror in enumerate(mirrors):
        suffix = "," if index < len(mirrors) - 1 else ""
        lines.append(f'    "{mirror}"{suffix}')
    lines.append(")")
    return "\n".join(lines)


def replace_block(text, pattern, replacement, path):
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise ValueError(f"Could not find asset mirror block in {path}")
    return new_text


def update_download_script(path, mirrors):
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    suffix = path.suffix.lower()

    if suffix == ".sh":
        replacement = format_shell_asset_mirrors(mirrors)
        pattern = r"GITHUB_ASSET_MIRRORS=\(\n.*?\n\)"
    elif suffix == ".ps1":
        replacement = format_powershell_asset_mirrors(mirrors)
        pattern = r"\$DefaultAssetMirrors = @\(\n.*?\n\)"
    else:
        raise ValueError(f"Unsupported download script type: {path}")

    new_text = replace_block(text, pattern, replacement, path)
    if new_text == text:
        log(f"No mirror order changes needed in {path}")
        return False

    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(new_text)
    log(f"Updated asset mirror order in {path}")
    return True


def default_download_script_paths():
    script_dir = Path(__file__).resolve().parent
    return [script_dir / name for name in DOWNLOAD_SCRIPT_NAMES]


def write_download_scripts(results, paths):
    mirrors = [result.mirror for result in results]
    updated = []
    for path in paths:
        if update_download_script(path, mirrors):
            updated.append(str(path))
    return updated


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark GitHub mirror download throughput and sort mirrors. "
            "Connection setup and response-header time are not used as the speed score."
        )
    )
    parser.add_argument(
        "mirrors",
        nargs="*",
        help="Mirror prefixes to test. Defaults to BGI_ASSET_MIRRORS, BGI_GITHUB_MIRRORS, then built-ins.",
    )
    parser.add_argument("--mirror-file", help="Read mirror prefixes from a whitespace-separated text file.")
    parser.add_argument("--url", help="GitHub asset URL to benchmark. Defaults to the latest BetterGI release asset.")
    parser.add_argument("--repo", default=os.environ.get("BGI_RELEASE_SYNC_REPO", "bcmdy/bgi-release-sync"))
    parser.add_argument("--asset-template", default=os.environ.get("BGI_ASSET_TEMPLATE", "BetterGI_{tag}.7z"))
    parser.add_argument("--atom-url", default=os.environ.get("BGI_ATOM_URL"))
    parser.add_argument("--sample-mib", type=float, default=4.0, help="Bytes to read from each mirror, in MiB.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Socket timeout in seconds.")
    parser.add_argument("--max-seconds", type=float, default=20.0, help="Max body-read seconds per mirror round.")
    parser.add_argument("--chunk-kib", type=int, default=256, help="Read chunk size in KiB.")
    parser.add_argument("--rounds", type=int, default=1, help="Rounds per mirror; the best throughput is kept.")
    parser.add_argument("--workers", type=int, default=8, help="Concurrent mirror tests.")
    parser.add_argument(
        "--write-download-scripts",
        action="store_true",
        help="Write the sorted asset mirror list back into download-latest-bettergi.sh and .ps1.",
    )
    parser.add_argument(
        "--download-script",
        action="append",
        dest="download_scripts",
        help=(
            "Download script path to update when --write-download-scripts is set. "
            "May be passed more than once. Defaults to scripts/download-latest-bettergi.sh and .ps1."
        ),
    )
    parser.add_argument(
        "--format",
        choices=("table", "list", "env", "bash", "powershell", "json"),
        default="table",
    )
    return parser


def get_input_mirrors(args):
    mirrors = []
    if args.mirror_file:
        mirrors.extend(read_mirror_file(args.mirror_file))
    mirrors.extend(args.mirrors)

    if not mirrors:
        env_mirrors = os.environ.get("BGI_ASSET_MIRRORS") or os.environ.get("BGI_GITHUB_MIRRORS")
        mirrors = env_mirrors.split() if env_mirrors else DEFAULT_ASSET_MIRRORS

    return move_github_first(mirrors)


def main():
    args = build_parser().parse_args()

    if args.sample_mib <= 0:
        raise SystemExit("--sample-mib must be greater than 0")
    if args.rounds < 1:
        raise SystemExit("--rounds must be at least 1")
    if args.workers < 1:
        raise SystemExit("--workers must be at least 1")

    original_url = args.url or fetch_latest_asset_url(
        repo=args.repo,
        asset_template=args.asset_template,
        atom_url=args.atom_url,
        timeout=args.timeout,
    )
    mirrors = get_input_mirrors(args)
    sample_bytes = max(1, int(args.sample_mib * 1024 * 1024))
    chunk_size = max(1024, args.chunk_kib * 1024)

    log(f"Benchmarking {len(mirrors)} mirrors with {args.sample_mib:g} MiB sample")
    log("Sorting score is download throughput only; GitHub direct stays first")

    results = []
    with ThreadPoolExecutor(max_workers=min(args.workers, len(mirrors))) as executor:
        futures = {
            executor.submit(
                benchmark_mirror,
                mirror,
                original_url,
                sample_bytes,
                args.timeout,
                args.max_seconds,
                chunk_size,
                args.rounds,
            ): mirror
            for mirror in mirrors
        }
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            if result.bytes_read > 0:
                log(f"{result.mirror}: {result.speed_mib_s:.2f} MiB/s")
            else:
                log(f"{result.mirror}: failed ({result.error})")

    ordered_results = order_results(results)
    if args.write_download_scripts:
        script_paths = args.download_scripts or default_download_script_paths()
        write_download_scripts(ordered_results, script_paths)

    print_output(ordered_results, original_url, args.format)


if __name__ == "__main__":
    main()
