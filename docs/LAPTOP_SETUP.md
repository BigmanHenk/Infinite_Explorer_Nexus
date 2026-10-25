# Setting up a laptop for Infinite Explorer Nexus

Written for **Claude Code on the new laptop**, which carries out the steps. Steps marked
**👤 YOU** need the owner: logins, the iPhone, the Apple ID.

---

## Step 0 — 👤 YOU, before Claude can help (about 10 minutes)

1. Install **VS Code** from https://code.visualstudio.com and open it.
2. In VS Code open Extensions (Ctrl+Shift+X), search **Claude Code**, install it and sign in
   with your Claude account.
3. Make a folder for projects, e.g. `C:\Users\<you>\Projects`, then File → Open Folder → that
   folder.
4. Open the Claude Code panel and paste this message:

   > Clone https://github.com/BigmanHenk/Infinite_Explorer_Nexus into this folder, open it,
   > then read docs/LAPTOP_SETUP.md and set up this laptop for me, step by step. Ask me
   > whenever a step needs me.

Avast, if this laptop has it: it blocked `api.anthropic.com` as "malicious" on the old PC
(false positive) and broke pip's HTTPS. Add exceptions for `api.anthropic.com`, `pypi.org` and
`files.pythonhosted.org`, or switch off HTTPS scanning, before you start.

---

## Step 1 — Claude: install the tools (winget)

Run in PowerShell. Accept prompts with `--accept-source-agreements --accept-package-agreements`.
Skip anything already installed (`winget list <id>`).

```powershell
winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
winget install --id Apple.iTunes -e --accept-source-agreements --accept-package-agreements
```

- **Git** brings Git Credential Manager, which stores the GitHub login.
- **Python 3.12** runs the content build tools.
- **iTunes** provides the Apple USB drivers that Sideloadly needs. It must be the version
  from Apple or winget, NOT the Microsoft Store version. If winget's iTunes fails, tell the
  owner to install it from https://www.apple.com/itunes/download/win64 ("Windows 64-bit").

Restart the terminal afterwards so `git` and `python` are on PATH. Check with:
```powershell
git --version; python --version
```

Set the commit identity used by this public repo (never the owner's Gmail):
```powershell
git config --global user.name "BigmanHenk"
git config --global user.email "232571103+BigmanHenk@users.noreply.github.com"
```

## Step 2 — Claude: the project

If Step 0 didn't clone it yet:
```powershell
git clone https://github.com/BigmanHenk/Infinite_Explorer_Nexus.git
cd Infinite_Explorer_Nexus
```
Python environment:
```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```
- **If pip fails with SSL / certificate errors:** add
  `--trusted-host pypi.org --trusted-host files.pythonhosted.org`.
- **If Activate.ps1 is blocked:** run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Step 3 — 👤 YOU + Claude: GitHub login

Claude makes a harmless commit and pushes it. Git Credential Manager then opens a browser
window. **👤 YOU sign in to GitHub as BigmanHenk** and approve.

```powershell
git commit --allow-empty -m "Laptop set up"
git push
```
Check: `python tools/ci_download.py` must print the latest build (it reuses that login). This
also downloads the current `Explorer.ipa` to `Desktop\Explorer iPhone\`.

## Step 4 — Claude + 👤 YOU: Sideloadly (installing the app on the iPhone)

1. **Claude** installs Sideloadly itself:
   - First try `winget search Sideloadly`. If a package from the official publisher exists,
     install it with winget.
   - Otherwise fetch the official page https://sideloadly.io and find the **Windows**
     download link on it. Only use a link served from the sideloadly.io domain; never a
     mirror or another download site.
   - Download the installer to the Downloads folder and start it with `Start-Process`.
   - **👤 YOU** click **Yes** on the Windows "allow changes" prompt, then Next / Install.
   - Claude checks that Sideloadly appears in the Start menu or under Program Files.
2. **👤 YOU** plug the iPhone into the laptop with a cable, unlock it and tap **Trust This
   Computer**. iTunes may need to be opened once so the drivers load.
3. **👤 YOU** in Sideloadly:
   - drag `Desktop\Explorer iPhone\Explorer.ipa` in;
   - type your Apple ID;
   - Advanced options → **Bundle ID = `com.infiniteaperture.explorernexus`**, with "automatic
     bundle ID" OFF. A different ID installs over another app (Nexus or Myco);
   - press **Start** and enter the Apple ID password / 2-factor code when asked.
4. **👤 YOU** on the iPhone:
   - Settings → General → VPN & Device Management → your Apple ID → **Trust**.
   - If iOS asks: Settings → Privacy & Security → **Developer Mode** → On, then restart.
5. Free Apple ID signing lasts **7 days**. To renew, press Start again with the same file.
   The app's plans and settings are kept.

Bundle IDs of all three apps:
- **Nexus:** `com.infiniteaperture.nexusphone`
- **Myco:** `com.infiniteaperture.myconexus`
- **Explorer:** `com.infiniteaperture.explorernexus`

## Step 5 — Claude: optional, the map and content tools

Only needed to rebuild the map or the content database. The app builds without them.
```powershell
mkdir tools\osm -Force
curl.exe -L -o tools/osm/kent.osm.pbf https://download.geofabrik.de/europe/united-kingdom/england/kent-latest.osm.pbf
python tools/build/s01_extract.py
python tools/build/s02_tiles.py
```
After that `python tools/publish_site.py` can update the PC planner web page.

## Step 6 — Claude: check everything and report

- `git status` is clean and `git log -1` shows the latest commit.
- `python tools/build/s06_pc_planner.py` runs, and the `planner\Explorer Planner.html` it
  rewrites opens in the browser.
- `python tools/ci_download.py` downloads `Explorer.ipa`.
- Sideloadly sees the iPhone.

Then read `docs/HANDOVER.md` (open items in section 7) and tell the owner what is ready and
what's next.

---

## Everyday use afterwards

| You want to… | Ask Claude / do |
|---|---|
| Change the app | Describe it. Claude edits, commits and pushes; GitHub builds it. |
| Get the new app on the phone | Claude runs `python tools/ci_download.py`, then **👤 YOU** press Start in Sideloadly. |
| Update the PC planner page | Claude runs s06, then `tools/publish_site.py`; open https://bigmanhenk.github.io/Infinite_Explorer_Nexus/ |
| Plan on the laptop | Open the page above, plan, press **Send to iPhone**, scan the QR code with the phone. |
