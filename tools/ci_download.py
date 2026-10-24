"""Wait for the latest GitHub Actions "iOS build" and download Explorer.ipa.

    python tools/ci_download.py [--out "C:/Users/<you>/Desktop/Explorer iPhone"]

Uses the GitHub login that git already has (git credential fill), so no token to set up.
On failure it downloads the xcodebuild log and prints the compiler errors.
"""
import argparse
import io
import json
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

REPO = "BigmanHenk/Infinite_Explorer_Nexus"


def token():
    r = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                       capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    sys.exit("No GitHub login found - run any git push once so Git Credential Manager stores it.")


def api(url, tok, raw=False):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read() if raw else json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path.home() / "Desktop" / "Explorer iPhone"))
    args = ap.parse_args()
    tok = token()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    while True:
        run = api(f"https://api.github.com/repos/{REPO}/actions/runs?per_page=1", tok)["workflow_runs"][0]
        print(time.strftime("%H:%M:%S"), run["id"], run["status"], run["conclusion"], run["head_commit"]["message"][:60], flush=True)
        if run["status"] == "completed":
            break
        time.sleep(30)
    want = "Explorer-ipa" if run["conclusion"] == "success" else "xcodebuild-log"
    arts = api(f"https://api.github.com/repos/{REPO}/actions/runs/{run['id']}/artifacts", tok)["artifacts"]
    art = next((a for a in arts if a["name"] == want), None)
    if not art:
        sys.exit(f"Build {run['conclusion']} and no {want} artifact - see the Actions page on GitHub.")
    data = api(art["archive_download_url"], tok, raw=True)
    zipfile.ZipFile(io.BytesIO(data)).extractall(out)
    if want == "Explorer-ipa":
        print("Downloaded", out / "Explorer.ipa")
    else:
        log = (out / "xcodebuild.log").read_text(errors="replace")
        print("\n".join(sorted({l for l in log.splitlines() if "error:" in l})[:40]))
        sys.exit("Build failed - errors above.")


if __name__ == "__main__":
    main()
