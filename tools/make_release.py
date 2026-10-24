"""Put the current Explorer.ipa and the PC planner page on the GitHub release "latest", so both
can be downloaded from any computer:

    python tools/make_release.py [--ipa "C:/Users/<you>/Desktop/Explorer iPhone/Explorer.ipa"]

Page: https://github.com/BigmanHenk/Infinite_Explorer_Nexus/releases/latest
Run tools/ci_download.py first so the .ipa is the newest build.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = "BigmanHenk/Infinite_Explorer_Nexus"
ROOT = Path(__file__).resolve().parents[1]


def token():
    r = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    sys.exit("No GitHub login found - push once so Git Credential Manager stores it.")


def call(method, url, tok, body=None, data=None, ctype="application/json"):
    headers = {"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"}
    payload = None
    if body is not None:
        payload = json.dumps(body).encode()
    elif data is not None:
        payload = data
    if payload is not None:
        headers["Content-Type"] = ctype
    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipa", default=str(Path.home() / "Desktop" / "Explorer iPhone" / "Explorer.ipa"))
    args = ap.parse_args()
    tok = token()
    ipa = Path(args.ipa)
    page = ROOT / "planner" / "Explorer Planner.html"
    setup = ROOT / "docs" / "LAPTOP_SETUP.md"
    for f in (ipa, page):
        if not f.exists():
            sys.exit(f"missing {f}")
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    notes = (f"Latest build ({time.strftime('%Y-%m-%d %H:%M')}, commit {commit}).\n\n"
             "- **Explorer.ipa** - install on the iPhone with Sideloadly (Bundle ID `com.infiniteaperture.explorernexus`).\n"
             "- **Explorer.Planner.html** - the PC planner; open in any browser (maps and photos need internet). "
             "Always-current online copy: https://bigmanhenk.github.io/Infinite_Explorer_Nexus/\n"
             "- **LAPTOP_SETUP.md** - how to set up a computer for this project.\n")
    rel = call("GET", f"https://api.github.com/repos/{REPO}/releases/tags/latest", tok)
    if rel is None:
        rel = call("POST", f"https://api.github.com/repos/{REPO}/releases", tok,
                   {"tag_name": "latest", "name": "Explorer - latest build", "body": notes, "make_latest": "true"})
    else:
        call("PATCH", f"https://api.github.com/repos/{REPO}/releases/{rel['id']}", tok, {"body": notes, "make_latest": "true"})
        # move the tag to the current commit
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        call("PATCH", f"https://api.github.com/repos/{REPO}/git/refs/tags/latest", tok, {"sha": sha, "force": True})
    for a in rel.get("assets", []):
        call("DELETE", f"https://api.github.com/repos/{REPO}/releases/assets/{a['id']}", tok)
    upload = rel["upload_url"].split("{")[0]
    for f, name, ctype in ((ipa, "Explorer.ipa", "application/octet-stream"),
                           (page, "Explorer.Planner.html", "text/html"),
                           (setup, "LAPTOP_SETUP.md", "text/markdown")):
        print(f"uploading {name} ({f.stat().st_size / 1e6:.0f} MB) ...", flush=True)
        call("POST", f"{upload}?name={name}", tok, data=f.read_bytes(), ctype=ctype)
    print(f"Done: https://github.com/{REPO}/releases/latest")


if __name__ == "__main__":
    main()
