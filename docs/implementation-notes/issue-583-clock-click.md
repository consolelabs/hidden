# #583 clicking the macOS date or time expands the bar

Verdict: **OS limit, documented.** The expand is intended on macOS 27 and unchanged on 1.13.4; the bar collapses about a second after the panel closes. Neither #410 nor #467 removes the expand: they are what made Notification Center open at all.

## Claim

Reported on 1.13.3, macOS 27.2.1, auto-hide on: with the bar collapsed, clicking the time or date opens Notification Center and Hidden Bar also expands. Expected: Hidden Bar reacts only to its own arrow.

The reporter's recording (opened, frames at 1.5 per second, 1.13.3): collapsed bar, click on the clock, Notification Center opens and the hidden icons appear (19:18:01), a second click on the clock closes the panel (19:18:03), and the bar is collapsed again one frame later (19:18:04). A third click at 19:18:05 repeats the cycle and the bar is collapsed again at 19:18:07. So the recording itself shows the designed cycle and the collapse within about a second; the icons shown are the expand for the clock click, not a reaction to the date text.

## Why it is intended

`NativeVisibilityEngine` header comment and `docs/MANUAL.md` ("Native hiding blocks Notification Center"): hiding runs through an assertion mode in which macOS ignores clicks on the clock. A click on the clock while collapsed therefore lifts the restriction, presses the clock again and re-applies the restriction when the panel closes (`NotificationCenterSession` in `MenuBarClock.swift`). The pre-1.11.2 behaviour was a dead clock. Changelog 1.11.2 (#410, #421, #435, #454, #467).

## Evidence on 1.13.4

Evidence folder `issue-verdicts-2721-2026-11-25` on the maintainer test host (1.13.4 build 25, CDHash 27796c72..., macOS 27.2.1).

| Cell | Result | File |
|---|---|---|
| Clock AX frame | x=814 w=126, centre 877 pt | README, `hb-ax` line |
| Collapsed, one `mclick` at the clock centre, close by a click on the desktop | Notification Center panel open ("No recent notifications", Edit Widgets), arrow shows expanded; log `a click on the clock while collapsed; expanding` then `lifting the restriction for a click on the clock`; NC window gone at 472.185; arrow back to collapsed in burst frame f0034 at 472.34 (about 0.9 s after the close click) | `clkb-1-desktop-*` |
| Same, close by clicking the clock again | NC gone at 585.76; collapsed in burst frame f0021 at 586.21 (about 0.7 s after the close click); pointer stayed on the clock (877,15), no jump | `clkb-2-clock-*` |

So the answer to the first question in the maintainer reply on #583 is yes: the bar collapses again by itself, within about a second of the panel closing. The pointer-jump fix (1.13.2) holds.

Not re-run on 1.13.4: the edge-offset grid. The clock path for macOS 27 is unchanged between 1.13.2 and 1.13.4 (`git diff v1.13.2 v1.13.4 -- hidden/Features/StatusBar/Engine/Native/MenuBarClock.swift` changes only the macOS 26 "window alone is the panel" flag). Offsets: `verify-clock-padding-2721-2026-11-19`, `verify-c7fce14-2721-2026-11-19`.

First pair of cells in the folder (`contaminated/`) is invalid: a Terminal sheet from `hb-ax` was on screen.

## Next action

1. Reply (draft: scratch `reply-583.md`): 1.13.4 result, the one-second collapse, and the one open question already asked, whether the reporter wants a setting that makes the clock open nothing while collapsed.
2. If the reporter says yes: a settings switch that leaves the clock alone while collapsed (clock click does nothing, as before 1.11.2). Engine change, not done here: `NativeVisibilityEngine.clockClicked` and the `watchClock` hook are where it would go.
3. Manual and the refreshed #535 text state the behaviour (`docs/macos27-known-limits.md`).
