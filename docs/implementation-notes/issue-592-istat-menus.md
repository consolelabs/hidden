# #592 iStat Menus cannot remain unhidden

Verdict: **OS limit, documented.** Reproduced on 1.13.4. Not a Hidden Bar bug; the docs did not say so for iStat until this change.

## Claim

On macOS 27 with the Homebrew build, iStat Menus disappears whenever Hidden Bar is collapsed, even with Settings > Icons set to Visible and "Ignore drags" ticked. Reporter's screenshots: expanded bar shows the iStat items right of the arrow, collapsed bar shows none, Icons tab lists "iStat Menus Menubar" as Visible. No version, macOS build or log given; the Icons tab has "Ignore drags", so 1.12 or later.

## Evidence

Evidence folder `issue-verdicts-2721-2026-11-25` on the maintainer test host (1.13.4 build 25, CDHash 27796c72..., macOS 27.2.1; see its `README.txt` and `build-identity.txt`).

| Cell | Result | File |
|---|---|---|
| Control, Hidden Bar quit, iStat running | CPU, network, SSD and MEM items visible | `f-A0-control-hb-quit-strip.png` |
| iStat process path | `~/Library/Application Support/iStat Menus 7/iStat Menus Menubar.app`, not an Applications folder | `ps` line in the run, README |
| 1.13.4 collapsed, iStat set to Visible in Icons, pause switch off | iStat items gone | `f-B1-pause-off-collapsed-strip.png` |
| Same cell, log | `NativeVisibility: macOS hides ["iStat Menus Menubar"] although they are allowed: they run from outside an Applications folder` | `f-B-log-off.txt` line 12 |
| Pause switch on, collapse | Bar stays whole, iStat visible | `f-D1-pause-on-after-start-strip.png` |
| Same cell, log | `hiding unavailable: an icon right of the arrow cannot be kept visible, so the bar stays whole` | `f-D-log-on.txt` lines 13 and 14 |

The pause switch is off by default (`pauseHidingForUnkeepableItems` has no registered default; `c3-7b-advanced.png`). The reporter's pause setting is unknown.

Earlier background, not 1.13.4: `issue-521-option1/` (pause off hides iStat, pause on keeps it; dev build, no README) and `issue-521-fix/` (a probe app run from Application Support is hidden although allowed, the same app from /Applications is kept).

Open points from the run, not resolved: after an expand with the switch off, iStat's items were absent from the strip in three runs and present in one (`contaminated/clk-1-desktop-1-strip.png`). iStat re-lays out its items on its own schedule; the reporter's expanded screenshot shows them. The "Seen on this Mac: iStat Menus Menubar" caption in Settings > Advanced was not captured (code: `AdvancedSettingsViewController.refreshMacOSAlsoHides`; older capture `issue-521-option1/06-advanced-lists-istat.png`).

## Cause

macOS 27 hides an allowed app that runs from outside `/Applications` and its subfolders. iStat Menus 7 starts its menu bar part from `~/Library/Application Support`. Hidden Bar allows the bundle id (the log line says so) and macOS ignores it. Code: `AccessibilityMenuBarInventory.runsOutsideApplicationsFolder`, `NativeVisibilityEngine.isInApplicationsFolder`. Changelog 1.13.1 already says it.

## Next action

1. Reply (draft: scratch `reply-592.md`): the cause, the log line to look for, the pause switch and its price (nothing hides while iStat runs), and the one thing to send if the pause switch is on and iStat still vanishes (version, macOS build, a log from "Capture a log").
2. Refreshed text of #535 and the manual now name iStat and `~/Applications` (`docs/macos27-known-limits.md`).
3. Code option, not done here: with the pause switch off nothing tells the user why iStat vanished except the Advanced caption after the first collapse. A note under the arrow for a collapse that hides an allowed app would match the 1.13.3 note for the pause-on case (`NoHideNotice`). Needs a decision; it changes the engine, so it is outside this docs change.
