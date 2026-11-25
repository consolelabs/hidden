# #242 permanent icon loss: repro on a throwaway profile

Verdict: **not reproduced on 1.13.4** (macOS 27.2.1, native engine). No icon was lost for good in six attempts. The original report is the macOS 13 separator-length engine, which this build does not run on macOS 27, so the run answers "does 1.13.4 on macOS 27 lose icons", not "was the 2023 report real".

## Question

`docs/BACKLOG.md` (Decisions) says #242 needs a throwaway defaults profile, because a live repro risks losing real menu-bar icons, and that the repro is required before the always-hidden decouple lands. The question: with the always-hidden section on, can a user end up with icons, or Hidden Bar's own items, that stay unreachable after a relaunch, after Hidden Bar is quit, or after it is removed?

The report (Ventura 13.1, 2023): permanent hiding worked, then the always-hidden icons and the second divider were gone, still gone after uninstalling, shown for a split second at every login, and a reinstall showed no Hidden Bar item at all. The maintainer's reply names the cause as the legacy engine: a dragged icon can get an off-screen position that macOS persists per app. A later retest on 1.13.1 and macOS 26.6.2 could not lose icons either.

## Method

Evidence folder `repro-242-2721-2026-11-25` on the maintainer test host (README, build identity, screenshots, tables, log slices, the exports before and after).

- Guest `hb-macos2721`, macOS 27.2.1. Build under test: the released 1.13.4 (build 25, Developer ID, CDHash `27796c72e3ab538c3ca24f85b4a0a27b620eb998`) already installed in the guest. No host build, no swap. The guest had no usable network, so the run went through the gate kit's shared-folder runner.
- Throwaway profile: bundle id `com.dwarvesv.minimalbar`, addressed by path (`$HOME/Library/Preferences/com.dwarvesv.minimalbar`) because the guest has a sandbox container for the id. Before anything: `defaults export` to a file. Between attempts: `defaults delete` of the domain or `defaults write` of a crafted shape. At the end: `defaults import` of the export and a read-back.
- Other domains edited for attempt 3 (`com.apple.controlcenter`, the SideNotes domain) were exported first and restored the same way.
- Per attempt: menu bar strip before and after, the `pinnedSections` and `nativeVisibilityLastSections` tables, the `/tmp/hb.log` slice.

## Attempts

| # | Profile and steps | Result |
|---|---|---|
| 1 | Fresh profile, first launch, always-hidden on. iStat pinned Always hidden in Settings > Icons, collapse, expand, relaunch, quit. | Not lost. Expand brings the hidden icons back; the always-hidden icon stays hidden by design; quitting Hidden Bar brings everything back. iStat is also hidden by macOS itself (it runs from Application Support), which is the known limit, not this issue. |
| 2 | Old preferences shape: always-hidden on, separators hidden, Hidden Bar's own three status items persisted at position 6000 to 6100. | Not lost. The arrow drew at its normal place; the engine took the two separators out of the bar and kept the arrow. |
| 3 | Control Center Sound and Wi-Fi and the SideNotes item written at position 6000 to 6100, Hidden Bar running, quit, running again. | Not lost. The icons stayed on screen with the keys in place. The SideNotes key name (`Item-0`) is an assumption. |
| 4 | Overflowing bar (Terminal in front, SideNotes, NotchNook, Synology Drive, iStat), `pinnedSections` written from outside with always-hidden entries, relaunch. | No icon lost. The table was rewritten at the launch (always hidden to hidden, two rows dropped), log `always hidden []`. |
| 5 | Control for 4 without the off-screen position keys. | Same rewrite. The off-screen keys are not the cause. |
| 6 | Pins set through Settings > Icons, four relaunches, then force quit. | Not lost. Table and `always hidden [...]` log line identical on all four launches; force quit brings everything back. |

Not run: a display change (the kit has no step for it), an Option-click reveal of the always-hidden zone (the VNC modifier did not register in the gate run of the same day, not retried), the legacy engine.

Attempts 4 and 5 are the #593 class: the always-hidden section read as empty, so always-hidden apps read as hidden and the table follows. They are not icon loss (the apps came back on expand), and 1.13.4 has no guard; the guard is on develop. The crafted table is also an artificial start: the pins were never physically moved across the separator, so the next read of the real positions wins, as the "a drag is a change between two reads" rule says (`pinned-sections.md`, phase 1).

Restore check: the Hidden Bar domain and the SideNotes domain read back identical to their exports (xml diff); the two keys attempt 3 added to the Control Center domain were deleted (import merges and does not remove added keys) and the second diff was identical. The installed app was never replaced.

## What this run could not show

- The reported mechanism. On a macOS 27 direct build Hidden Bar hides by restriction, not by inflating a separator, and the domain reads show it writes no position for other apps. The legacy engine runs on macOS 26 and earlier, and in the App Store build. This guest cannot run it.
- Whether a real drag on 26 or earlier can persist an off-screen position. Hand-written positions on 27.2.1 did not hide the items.
- The notch case (icons behind the camera housing): the guest has no notch.
- A drag across the always-hidden separator, because the Option-click reveal did not register.

## What it means for the always-hidden decouple

- The macOS 27 side is not blocked by #242. The native engine holds the always-hidden section hidden at every collapse regardless of the "hide separators" state (`pinned-sections.md`, phase 2), and in six attempts no icon was lost for good. The only misbehaviour seen is the #593 table rewrite, which is a separate fix.
- The legacy decouple (phase 3 of the same note, macOS 26 and earlier) is the part that can persist positions, and this run cannot clear it. Its precondition stays what BACKLOG already lists: a run on a macOS 26 guest. `hb-macos26` exists; the same throwaway-profile method applies there, with the exports and read-back above. The 2026-11 retest on 26.6.2 with 1.13.1 did not lose icons, which is weak evidence for the decouple, not proof.
- Recovery wording stays accurate on both engines: expand, "Show Everything" (legacy engine), or quit Hidden Bar.
- Decision for the maintainer, not made here: keep #242 closed and treat the macOS 26 run as the gate for the legacy decouple only.
