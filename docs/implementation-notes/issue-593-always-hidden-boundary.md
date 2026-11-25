# Always-hidden boundary misread (#593)

Refs #593. Related: #584, #591 (the same kind of misread, for the arrow).

## Diagnosis

Proven by the code and the log signature:

- `NativeVisibilityEngine.withLayout` took the always-hidden boundary from the separator item's window frame with no check. When that frame has nothing left of it (a frame at the display's left edge, no frame, or an item taken out of the bar), `MenuBarLayoutResolver.section(of:...)` returns `.hidden` for every app left of the arrow, so every always-hidden app reads as hidden.
- With pinned sections on, `PinnedSectionResolver.resolve` counts a section that differs from the last observed one as a drag, so the table is rewritten from always hidden to hidden. A later read with a good frame counts as a drag back. That is the "and back" in the report.
- The report's log has the signature: the arrow reads as placed, `always hidden []` while the hidden list holds every app, no `pinned sections changed` line, and the table correct again after one read.

Not proven: why AppKit reported a wrong separator frame. The report's log never printed it, and the wrong state lasted over four reads and two minutes, so it is not a one-off transient. Two engine paths do read the bar with the separator out of it, which would make its frame meaningless: a collapse during a clock lift (`pressClock` releases the restriction, and `collapse` skips `setSeparatorsVisible(true)` while the always-hidden section is hidden), and a collapse whose activation fails (the restriction is released and the state returns to expanded with the separator still out). Whether the reporter hit either is not known. A frame that looks plausible but is wrong would pass the check; every read with the section on now logs the frame so that case shows up.

## Change

- `NativeVisibilityEngine.alwaysHiddenSeparatorDistrust`: the separator frame counts as a boundary only when the item is in the bar, the frame is on the arrow's display, placed like the arrow (`isPlaced(arrow:displays:)`), and on the hidden side of the arrow. It returns the reason, or nil.
- "In the bar" is the engine's own record: `setSeparatorsVisible` is the only place that takes the item out and puts it back, and it now stores which. The first version read `NSStatusItem.isVisible`; the engine tests' fake items do not report visible, so five existing tests failed in CI (a fresh read distrusted a good frame). The real getter is logged beside the record, so a report shows whether they agree.
- When the check fails, `withLayout` reads with no always-hidden boundary and `MenuBarLayoutResolver.keepingAlwaysHidden` gives the apps last read as always hidden (`sectionMemory`) that section again. A read is still taken and a move across the arrow still counts. Nothing returns `nil`, so the bar still collapses.
- Because the section stays the remembered one, `observed` is unchanged for those apps: the next good read is not a drag, and a pin set in Settings is not lost either.
- Every read with the section on adds to the `arrow at x=` line: the separator verdict (`trusted` or `NOT trusted: <reason>`), its frame, the item's `isVisible` and `length`, the taken-out record, the arrow frame, and whether the read was incomplete.

## Decisions

- No `return body(nil)` as for the arrow (#591): the misread lasted minutes, and a layout of nil would keep the bar from ever collapsing.
- The check uses the injected `itemFrame` and the item's `isVisible` and `length`, not `MenuBarOrder.isItem` (it reads real windows and would bypass the test seam).
- A first read with nothing remembered cannot keep a section: it reads as before and the next good read corrects it (`testAFirstLaunchMisreadHealsAtTheNextGoodRead`). The launch collapse does not wait for the separator as it does for the arrow.
- Only with the always-hidden section on and its item present: the controller removes the item when the section is turned off before the engine is told, and that read (nil frame) must read as a disabled section, not as a distrusted one. (`alwaysHiddenEnabled`). With the section off the frame is nil by design and nothing changes.
- The check runs after the Debug override, so `always-hidden-boundary <x>` can force it (`always-hidden-boundary 6` reads the separator at the left edge).
- No CHANGELOG line: the repo keeps no Unreleased section, and open PR #594 edits that file.
- The unmerged branch `fix/unplaced-arrow-frame` has no diff against develop under `hidden/` or `HiddenBarTests/` (only a VM gate record under `docs/verification/`), so there is no file overlap with this change.

## Tests

`AlwaysHiddenBoundaryTests` (HiddenBarTests/MenuBarEngineTests.swift), 12 tests. CI is the proof so far, in `docs/verification/always-hidden-boundary/results.md`: all green with the change, and 5 of them fail with the handling switched off.
