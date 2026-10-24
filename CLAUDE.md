# Infinite Explorer Nexus

The offline iPhone sightseeing and week-planner app "Explorer" (Birchington / Thanet / East
Kent), plus a PC planner web page.

**New laptop? Follow `docs/LAPTOP_SETUP.md` step by step (it says which steps need the owner).**

**Read `docs/HANDOVER.md` first.** It covers setup, workflow, the repository map, the content
pipeline, the decisions to keep to, and the open items.

Rules in short:
- There is no Mac, so Swift is only compiled by GitHub Actions on push. Review Swift by eye:
  keep expressions short (type-checker timeouts) and remember `import Combine` with
  `ObservableObject`.
- After a push, `python tools/ci_download.py` fetches `Explorer.ipa` or prints the build
  errors.
- Content changes run s04, then s06, then `tools/publish_site.py`.
- Never copy TripAdvisor or Google reviews; link to them. Research text is in our own words,
  with sources, and nothing is invented.
- Commit as `BigmanHenk <232571103+BigmanHenk@users.noreply.github.com>` (the repo is public).
- Write Python patch scripts to files, not into bash heredocs, which mangle escapes.
