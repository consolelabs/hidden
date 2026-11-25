# Backlog

Durable, committed index of open work. The detailed planning layer
(`_meta/megagoals/issue-list-clearing/` and `.claude/`) is local-only and gitignored,
so this file is the version that survives a machine switch and a fresh clone. Keep it
short: one line per item, pointing at the issue, PR, or file that holds the detail.
For live numbers use `gh pr list` and `gh issue list`, not this file.

Source of the current state: develop after v1.13.4 (build 25, published 2026-11-23), plus the merges listed under "Merged, not yet a GitHub release". Core-model changes (separator length math, collapse state machine) are HIGH RISK and require a mandatory review-team pass.

## Merged, not yet a GitHub release

- **Unplaced arrow, #584:** the native engine no longer reads sections from an arrow macOS has not placed yet (AppKit reports it at the display's left edge on a crowded 27.2.1 bar). That read made nothing hide, showed "Nothing to hide", and could cost a pin (#591). #584 stays open: the PR is "Refs", not "Fixes", because the code cannot show whether the reporter's later clicks used the cached launch read; one log line decides it (the `NativeVisibility: arrow at x=` line after a click, once launch is over).
- **German restart prompt** uses the informal du (#588).
- **`scripts/publish-release.sh`** for the direct release publish (#590).

## Shipped

- **1.13.4 (2026-11-23, build 25):** Settings › General "App language" override (#567); Settings › Advanced "Restore settings from the App Store version", a private copy of those settings, and an import offer that can no longer be lost (#585); build bump (#586).
- **1.13.3 (2026-11-23, build 24):** a short note under the arrow says why when a click hides nothing on macOS 27 (#576); a notification banner no longer holds auto-hide on macOS 26 (#580, issue #579); the held list survives a refused launch swap (#575); locale coverage test (#570); UI proof asked for in the PR template and CONTRIBUTING (#578); build bump (#581).
- **1.13.2 (2026-11-19, build 23):** auto-hide fixes (popup guard, screen-edge and side-panel windows, windows already on screen before an expand, recovery on overflowing bars, readable hold and failure log lines) and clock clicks (#549, #552, #554, #556, #558, #561, #562); the legacy login item reset also covers upgrades through 1.11 and 1.11.1 (#553, issue #456); every language complete (#559, #563, #564, #565, #566); App Store release path script (#546); build bump (#568).
- **1.13.1 (2026-11-18, build 22):** pause switch wording (#515); legacy login item fix, #456: one SMAppService off/on reset removes the launcher-era `LauncherApplication` record (#517); test host isolated from the real prefs domain (#518); notice when expanding pushes icons into the macOS 27 « overflow (#519); apps that turn Accessibility off stay visible, Little Snitch (#520); a collapse macOS never answers is abandoned (#530); capture listeners removed, the memory growth in #386 (#531); full menu bar option takes focus on macOS 14 and later (#532); apps run outside Applications are named (#533); Notification Center from the clock while a notification shows (#537); right-click on the arrow setting (#538); rebrand to Console Labs and support email (#539, #536); App Store to direct migration loses nothing on macOS 27 (#541); `release.sh` (#529); build bump (#544).
- **1.13.0 (2026-11-16, build 21):** reveal without aiming, scroll, empty click, shake (#493); type-to-find palette (#505); arrivals inbox (#503); presentation mode with manual start and a mirror trigger (#504, #509, #511); shortcut recorder, hotkey registry and app catalog (#497); the General pane scrolls (#504). Notarized zip, Sparkle appcast (`docs/RUNBOOK.md`).
- **1.12.0:** never released on its own; ships inside 1.13.0. Redesigned Settings, pinned sections (beta) on macOS 27, Ignore drags, Icons list clean-up, Shift-click full bar, the system overflow notice (#473, #481, #487, #488, #495, #498).
- **1.11.2:** the macOS 27 fixes, Sparkle auto-update, arrow styles, the microphone and camera
  fix. v1.11.1 shipped without Sparkle; the first Sparkle-capable release carried the signed zip
  and `appcast.xml` (`docs/RUNBOOK.md`).

## Open after 1.13.4

- **Direct build bundle id.** 1.13.0 shipped Release-Direct as `com.dwarvesv.minimalbar`, the same as the App Store build (shared prefs, the two cannot coexist). **Ruled 2026-11-25 under the owner's delegation: it stays.** The App Store to direct migration (#541) and "Restore settings from the App Store version" (#585) both rely on the shared id; a move to `com.dwarvesv.minimalbar.direct` would need a new migration.
- **Upgrade-path BTM check, #456: FAIL on 1.13.0, PASS with the fix (2026-11-16, mac-ui VM, macOS 27.2.1 26B131). The fix shipped in 1.13.1 (#517), widened in 1.13.2 (#553); #456 is closed (2026-11-19).** 1.13.0: after v1.9 with Start at login on, an upgrade and a login, `sfltool dumpbtm` still lists `4.com.dwarvesv.LauncherApplication` and every launch logs error 22 from `SMLoginItemSetEnabled`. The fix (#517) resets the main app item once instead; on the same ghosted 1.13.0 state its first launch logs `Unregister error: 0`, `Register error: 0`, status 1, and the legacy record is gone, still gone after a fresh login, one Hidden Bar under Open at Login. A fresh install (no old container) is marked done without touching login items. System Settings has no row of its own for the legacy record: it sits inside the "Hidden Bar" Allow in the Background row, which an SMAppService app has anyway. Release step 7 still owes one run on real hardware before the next release. Evidence: `docs/implementation-notes/upgrade-btm-check-proof/` (`btm-dumps.txt` first run, `retest.txt` the fix).
- **Presentation keeps all system items.** Measure the clock and battery system item ids live,
  then narrow `NativeVisibilityEngine.presentationSystemItems` from all (0..<64) to those two.
- **Slideshow automatic trigger.** Dropped for 1.13.0; needs a live Keynote or PowerPoint check
  (frontmost app plus a whole-display window it owns) before any code.
- **Shortcuts action for presentation mode.** Needs App Intents; not built. Build or drop is under "Decisions for Han".
- **Manual presentation mode does not survive a relaunch.** **Ruled 2026-11-25 under the owner's delegation: it stays that way.** The spike chose it so a crash plus relaunch never re-hides on its own (`docs/implementation-notes/presentation-mode-spike.md`, fix list item 6).
- **Arrivals dot under the new app's own icon.** Needs an overlay window over another app's
  status item; the arrow dot and the NEW tag carry the signal for now.
- **Arrivals 24 hour lapse** is checked only at launch and when the prompt opens, not on a timer.
- **Reveal polish.** A first-use tip, and a live tune of the empty-space hit test (`HitClassifier`
  was written without a live menu bar).
- **Palette polish.** Bundle id second line, matched-letter weight, a primary "Open System
  Settings" button, panel width 379 vs 360 pt, footer wrap.
- **Tests share the real prefs domain: fixed (#518, shipped in 1.13.1).** The app reads and writes preferences through `AppDefaults.store`, a dedicated suite (`com.dwarvesv.minimalbar.tests`, wiped at first use) under XCTest. A test host also skips Sparkle, the move and migration offers, and status item autosave; login items and the second-copy quit were already skipped. `HiddenTests/PrefsIsolationTests.swift` checks the real domain is unchanged. A test opts back in with `AppDefaults.sideEffectsOptIn` or `HIDDEN_BAR_TEST_HOST_SIDE_EFFECTS=1`.
- **macOS 27 menu extras belong to `com.apple.MenuBarAgent`.** The overflow spike probed the wrong
  process; re-measure against MenuBarAgent.

## macOS 27 (#360, closed)

- **App Store build cannot hide on 27.** The sandbox denies `mach-lookup
  com.apple.axserver`, so the sections cannot be read even with Accessibility granted.
  v1.11.2 ships a notice that points to the direct build (`MacOS27Notice`). Still open:
  a user-picked list of visible apps instead of ⌘-drag (no Accessibility, still private
  API), or a public mechanism if Apple ships one.
- **Live Activities on macOS 27.3, #469.** Closed as not planned (2026-11-18), as is the related #327 (2026-11-17). We reproduced it on our test Macs: it is a macOS 27 limit, and the 1.13.1 workaround is Settings › Advanced "Pause hiding while macOS shows Now Playing, Focus and similar items". It reopens only if the reporter says the workaround fails. No owner step.

## Open reports and PRs (no fix merged)

- **#583** clicking the macOS date or time expands the bar. **#592** iStat Menus cannot remain unhidden. **#593** pinned sections: always-hidden apps flip to hidden and back when the always-hidden separator is misread (macOS 27.2.1). **#589** double-press the shortcut or double-click the arrow to also open the macOS 27 « overflow (request). **#535** known limits and workaround for macOS 27 items that stay hidden. **#584** see "Merged, not yet a GitHub release". **#366** the epic, below.
- **PR #594** adds Brazilian Portuguese (pt-BR), from a contributor; open, needs review.

## Needs hardware (not yet run)

Han only: each check below needs a real Mac, a second display, a live slideshow or a signed update. The one exception is the memory soak, which an agent reads after it ends.

- **#351 external monitor.** Closed, but the 26.4 external-display reproduction was never
  run. The multi-display rework is in #468; a real hot-plug and a second monitor are
  untested.
- **24h memory dogfood, #361 / #386.** Instruments stress-cycling found no leak. The Air
  now runs the v1.11.2 candidate; read `footprint -p "Hidden Bar"` after a day. #386 (memory grew with every audio or camera change) is closed: the leaked capture listeners were removed in #531, shipped in 1.13.1. #361 is closed as not planned. The hourly soak script is `scripts/memory-soak` (#522, heartbeat #542). The 14-day soak on the Mini ends 2026-11-30; `scripts/memory-soak/summarize` then gives the answer, and no hands are needed for it.

## Unverified on hardware for v1.11.2

- **Mic and camera indicator.** The bar stays whole while an app records (#432, #438).
- **Faded arrow and arrow styles.** Stealth mode (#173) and the arrow style popup (#310),
  in light and dark menu bars.
- **Clock expands the bar, on screen.** A click on the clock opens Notification Center
  (#410, #467).
- **A real Sparkle update.** An installed build fetching the appcast and updating.

## Decisions for Han

- **Release 1.13.5.** Han only: pick the scope (#599 and #594 in or out), then run `docs/RUNBOOK.md` "Release" steps 1 to 7 (step 7 owes one run on real hardware) and `scripts/publish-release.sh --apply`.
- **Shortcuts action for presentation mode (App Intents).** Han only: say build or drop. No doc recommends either.
- **A user-picked list of visible apps for the App Store build** (see "macOS 27" above). Han only: say build or drop. It still needs a private API.
- **Old branches: closed 2026-11-25, nothing to discard.** Neither `feature/menubarDetection` (PR #115, from a fork) nor `feature/ghost-mode` (PR #57) is a branch on origin. GitHub keeps the commits under each closed PR. Both ideas shipped under other names: "Rest the pointer on the menu bar" (`hoverToExpand`) and "Fade the arrow when icons are hidden" (`stealthExpandIconEnabled`).
- **#242 permanent icon-loss repro.** Needs a throwaway defaults profile (a live repro
  risks losing real menu-bar icons). Required before the always-hidden decouple lands.

## Architectural epic (#366, decided: option B, pinned sections)

- **Decided.** Option B, pinned sections, shipped in 6e33618 (beta, macOS 27 direct build):
  a per-app section table in place of positions. Brief: `docs/briefs/DECISION-BRIEF-366-overflow-bar.md`;
  notes: `docs/implementation-notes/pinned-sections.md`. The cluster list lives in the epic
  body (`gh issue view 366`, then `gh issue list`).
- **Remains.** Hidden-items menu (phase 4, thin A). Per-app drag lock for apps that recreate
  their icon without relaunching: shipped as "Ignore drags" (#487, 1.13.0; #107 closed). macOS 26 run of the legacy patches
  (always-hidden decoupled from "hide separators", "Show everything"). A 27.3 inventory dump
  for #469 (closed as not planned, 2026-11-18).
- **What already landed that the epic builds on.** Native hiding on 27 (#403), notch
  overflow menu (#420, in #468). The community second-bar PR (#358) was closed as
  superseded: its window capture no longer works on macOS 27, so the idea continues here.
- Design and the folded M1 (pin icons, persist order) / M2 (decouple always-hidden from
  `areSeparatorsHidden`, recover stuck items) are in SPEC-003 (local planning layer).
