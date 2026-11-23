# Expected results (written before the run)

Build under test: branch `fix/unplaced-arrow-frame`, commit 6938b0949393b908ccae02f240a46be91094f009, Developer ID signed, CDHash eeb9dd129fa16f3633601fa99c9451bfe97f73b5, version 1.13.4 (25).
Guest: `hb-macos2721`, macOS 27.2.1 (26B131), app installed in `/Applications`, stderr captured with `open --stderr /tmp/hb.log`.

| # | Check | Expected |
|---|---|---|
| 1 | Launch with the arrow mid-bar and at least two third-party icons left of it | Within about 5 s of launch the bar collapses and those icons disappear. `NativeVisibility: arrow at x=<value well above 0>` is logged. No "is not placed in the menu bar yet" line, or if one shows it is followed by a successful `arrow at x=` line. |
| 2 | Click the arrow, then click it again | First click: the hidden icons reappear. Second click: they hide again and a fresh `arrow at x=` line is logged. |
| 3 | Command-drag the arrow to a new position with a different icon left of it, then collapse | The icons now left of the arrow hide. The log shows a new `arrow at x=` with the new set in `hidden [...]`. |
| 4 | Quit and relaunch twice | Each launch collapses by itself and hides the hidden section. |
| 5 | Always-hidden section on (Settings > General), one icon in it; expand and collapse twice | The always-hidden icon stays hidden while expanded; the hidden section toggles normally. |
| 6 | Any "is not placed in the menu bar yet" line at launch | If it appears, the launch collapse must succeed on retry within about 4 s. A line with no later successful collapse is a FAIL. |

Pass rule: every check observed on screen (VNC frames) and in `/tmp/hb.log`, not from one source alone.

## Setup notes (recorded after the check 1 launch and before check 2; the check 1 expectation above was written before it)

- Command-drag over VNC did not move an icon on this guest (the click opened the SideNotes panel instead); Option-drag (`lalt`) did, as the kit docs predict. Placement used Option-drag.
- Test icons left of the arrow: SideNotes (runs from `/Applications`, honoured by macOS) and iStat CPU. iStat runs from `~/Library/Application Support`, so macOS 27.2.1 hides it on every collapse whichever side of the arrow it sits on; SideNotes is the icon that tells the arrow's hiding apart from that quirk.
- Expected midX of the expanded arrow: far from 0 (the guest bar showed it at about 515 to 556 pt).

## Check 2 expected (written before running)

Click the collapsed arrow (about x 710 pt, y 15 pt): SideNotes and the iStat icons reappear. Click again: they hide again and a fresh `arrow at x=` line appears in the log, with SideNotes under `hidden`.

## Check 3 expected (written before running)

Expand, then Option-drag the arrow right past the "?" item and the iStat network item (to about x 648 pt). Collapse. The icons now left of the arrow, SideNotes, iStat CPU, the "?" item and iStat network, leave the bar. The log shows a new `arrow at x=` with a value well above 0 and larger than the earlier 556, and SideNotes still under `hidden`. No "not placed" line.

## Check 3b expected (written before running)

Expand, Option-drag the arrow left of SideNotes and CPU (to about x 465 pt). Collapse. SideNotes now sits right of the arrow, so it stays on the bar: the log shows `arrow at x=` well above 0 with `hidden []` and no SideNotes under it, and SideNotes is visible in the frame. Then drag the arrow back right of SideNotes for checks 4 and 5.

## Check 4 expected (written before running)

After restoring the check 1 layout (arrow right of SideNotes and CPU), quit Hidden Bar and launch it twice more. Each launch: the bar collapses by itself within about 5 s, SideNotes leaves the bar, the log has one `arrow at x=` line well above 0 with SideNotes under `hidden`. A "not placed" line is acceptable only when followed by that successful line.

## Check 5 expected (written before running)

Turn on the always-hidden section in Settings > General. Place SideNotes left of the new always-hidden separator and iStat CPU between that separator and the arrow. Expand: SideNotes stays off the bar (always hidden), CPU shows (hidden section). Collapse: CPU leaves. Repeat once. Log: `arrow at x=` lines well above 0 with SideNotes under `always hidden` and no "not placed" line.

Check 5 setup change (recorded before the cycles): with the always-hidden restriction held, macOS also hides the iStat items on expand (they run outside `/Applications`), so iStat cannot show the hidden section toggling. Sound and Wi-Fi Control Center items were switched on (`defaults -currentHost write com.apple.controlcenter Sound/WiFi -int 18`, then `killall ControlCenter`) as honoured icons. Layout used: SideNotes always hidden (left of the always-hidden separator), Sound in the hidden section (right of that separator, left of the arrow), Wi-Fi right of the arrow. Expected over two expand/collapse cycles: expanded shows Sound and not SideNotes; collapsed shows neither; Wi-Fi stays on the bar in both states.

Check 5 revised arrangement (recorded before the cycles). Sound and Wi-Fi are Control Center items: the log classes them as visible system items and a collapse never hides them, so they cannot show a hidden section. Placement by Option-drag is also unreliable while the always-hidden restriction is held (the always-hidden area is off the bar). The arrangement was set in Settings > Icons instead: SideNotes = Hidden, iStat Menus = Always hidden, always-hidden section on. Expected over two expand/collapse cycles: collapsed, SideNotes is off the bar; expanded, SideNotes shows and the iStat items stay off (always hidden, and macOS also keeps them off); the log shows `hidden ["com.apptorium.SideNotes-paddle"]` and `always hidden` holding iStat, `arrow at x=` well above 0, no "not placed" line.

## Control: Sound on the released build (written before running)

The branch build left the Sound item visible, left of a placed arrow, through a collapse. Control on the released 1.13.4 (CDHash read from the guest copy): with Sound switched on (`defaults -currentHost write com.apple.controlcenter Sound -int 18`, `killall ControlCenter`) and the same layout, expected result is the same, Sound stays visible after collapse and the log never lists it under `hidden`. If Sound hides on the released build, check 5 fails.
