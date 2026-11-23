# VM click gate: unplaced arrow fix (PR 591)

Build: `fix/unplaced-arrow-frame` at 6938b0949393b908ccae02f240a46be91094f009, version 1.13.4 (25), Developer ID signed, CDHash eeb9dd129fa16f3633601fa99c9451bfe97f73b5 (`build-identity.txt`).
Guest: `hb-macos2721`, macOS 27.2.1 (26B131), build installed in `/Applications`, stderr from `open --stderr /tmp/hb.log`. The guest had no usable network (Lume reported a stale address), so every command ran through the shared-folder runner (`hb: path=share`). Expected results were written first: `expected.md`.

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Launch collapse, SideNotes and iStat CPU left of the arrow | PASS | Log `arrow at x=556.0 ... hidden ["com.apptorium.SideNotes-paddle"]` 1.1 s after the launch, no "not placed" line. `c1-launch-t1.png` (expanded at launch), `c1-launch-after5s.png` (collapsed, icons gone), `c1-launch.log` |
| 2 | Click the arrow twice | PASS | Collapse at 06:30:32 and 06:30:39, each with a fresh `arrow at x=556.0`, SideNotes under `hidden`. `c2b-collapse-1.png`, `c2b-expand-2.png` (icons back), `c2b-collapse-2.png`, `c2-after.log`. A first attempt mis-clicked the iStat MEM item (my aim, the arrow had moved); redone |
| 3 | Move the arrow, collapse | PASS | Arrow dragged right of the "?" and network items: `arrow at x=636.0`, SideNotes hidden (`c3-after-drag.png`, `c3-collapsed.png`, `c3-after.log`). Arrow dragged left of SideNotes: `arrow at x=477.0`, `hidden []`, SideNotes stays on the bar and the "Nothing to hide" notice shows, which is correct for a placed arrow (`c3b-after-drag.png`, `c3b-collapsed.png`, `c3b-after.log`) |
| 4 | Quit and relaunch twice | PASS | Launch collapse at 06:33:22 and 06:33:38, each `arrow at x=556.0`, SideNotes hidden, collapsed in the 6 s frame. `c4-run1-t6s.png`, `c4-run2-t6s.png`, `c4-run1.log`, `c4-run2.log` |
| 5 | Always-hidden section on, expand and collapse twice | PASS with caveats | Always-hidden SideNotes: off the bar when expanded, log `always hidden ["com.apptorium.SideNotes-paddle"]` (`c5-ah-on.png`, `c5-expand1-late.png`, `c5c-after1.log`, `c5-relaunch.log`). Hidden-section toggling with the section on, set in Settings > Icons (SideNotes Hidden, iStat Always hidden): two cycles, SideNotes shows on expand and leaves on collapse, iStat stays off (`c5d-icons-tab.png`, `c5e-exp1.png`, `c5e-col1.png`, `c5e-exp2.png`, `c5e-col2.png`, `c5e-after.log`) |
| 6 | "is not placed in the menu bar yet" at launch | Not observed | Five launches (06:21, 06:27, 06:33 twice, 06:37) and no such line in any log; every launch collapsed. The retry path was not exercised in this guest, only the placed path |

Caveats and surprises:

- Command-drag over VNC did not move an icon on this guest (it opened the SideNotes panel). Option-drag (`lalt`) did. Every placement used Option-drag.
- The iStat items run from `~/Library/Application Support`, so macOS 27.2.1 hides them on every collapse, and with the always-hidden restriction held also when expanded. SideNotes (from `/Applications`) is the icon that tells the arrow's hiding from that quirk.
- With the always-hidden restriction held, a collapse reuses the cached read: no new `arrow at x=` line, and an icon added later (Sound) was not hidden until a relaunch. Control Center items (Sound, Wi-Fi) are classed as visible system items and never hide. Neither is code this PR touches.
- The first launch (06:21, before any icon was moved left of the arrow) read `arrow at x=515.0`, `hidden []`: nothing left of the arrow, nothing to hide. That log was overwritten by the next launch, so it is not saved.
- Guest changes left behind: always-hidden section on, SideNotes pinned Hidden and iStat pinned Always hidden in Settings > Icons, SideNotes running. Control Center Sound and Wi-Fi keys were set back to 8. The released copy was swapped back into `/Applications`.
