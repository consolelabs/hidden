# #535 pinned FAQ: macOS 27 known limits

Verdict: **OS limit, documented.** The issue text was stale against 1.13.4 and is refreshed in `docs/macos27-known-limits.md`.

## What was stale

| Issue text | 1.13.4 fact | Source |
|---|---|---|
| "The next release lists such apps in Settings > Advanced" | shipped in 1.13.1 | CHANGELOG 1.13.1, "macOS 27 also hides" |
| "In 1.13.0 it reads ... The next release renames it" | renamed in 1.13.1 | CHANGELOG 1.13.1, `c3-7b-advanced.png` shows the current label |
| no default stated for the pause switch | off by default | `AppDelegate.defaultPreferenceValues` has no entry, `c3-7b-advanced.png` |
| no mention of the note under the arrow | 1.13.3 explains a click that hides nothing | CHANGELOG 1.13.3, `docs/verification/arrow-says-why/` |
| no mention of the clock | clicking the clock expands the bar for a moment, #583 | this change, `issue-583-clock-click.md` |
| comments: `~/Applications` counts or not | does not count; moving to `/Applications` fixes it (user reports) | code comment in `NativeVisibilityEngine.isInApplicationsFolder` comment, comments on #535 |

## Claims re-checked on 1.13.4

Folder `/Volumes/data-mini/lume/hb-shots/issue-verdicts-2721-2026-11-25/`, macOS 27.2.1, build 25.

| Claim | Result |
|---|---|
| An allowed app outside `/Applications` is hidden at collapse | Holds. iStat Menus Menubar, log line in `f-B-log-off.txt` |
| Pause switch keeps it visible, at the price of hiding nothing | Holds. `f-D1-pause-on-after-start-strip.png`, `f-D-log-on.txt` |
| Clock click expands and re-collapses | Holds, about one second after the panel closes. `clkb-*` |

## Claims not re-measured on 1.13.4

Reused from earlier evidence, same macOS 27.2.1 unless noted:

- Focus and User cannot be kept visible by any allow-list entry, and an item that appears while collapsed is invisible to every signal until the restriction lifts: `system-items-probe/README.txt` (mac-ui guest, 2026-11-17).
- Live Activity pill disappears on collapse and stays with the pause switch on: `issue-469-2026-11-18/` (27.3 beta).
- Now Playing, Camera controls, Siri, Stage Manager: stated in the issue and CHANGELOG 1.11.2, no 1.13.4 cell.
- `~/Applications` does not count, Itsycal fix, Background Sounds: user comments on #535, plus the code comment. Not run.
- A user's measurement that macOS accepts nine system item ids: comment on #535, not run.

## Next action

1. Replace the issue body with the doc, with `gh issue edit 535 -R consolelabs/hidden --body-file <file>` where the file is `docs/macos27-known-limits.md` minus its first two lines (the title stays on the issue). Lead hands this over; not run by the investigator.
2. Keep the issue pinned; the page is the single place to update after each release.
3. If a future 1.13.x changes the pause default or adds the "allowed app was hidden" note (see `issue-592-istat-menus.md`), edit the doc, then the issue.
