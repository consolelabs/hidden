# Always-hidden boundary misread (#593)

Refs #593. Related: #584, #591 (the same kind of misread, for the arrow).

## Diagnosis

Proven by the code and the log signature:

- `NativeVisibilityEngine.withLayout` took the always-hidden boundary from the separator item's window frame with no check. When that frame has nothing left of it (a frame at the display's left edge, no frame, or an item taken out of the bar), `MenuBarLayoutResolver.section(of:...)` returns `.hidden` for every app left of the arrow, so every always-hidden app reads as hidden.
- With pinned sections on, `PinnedSectionResolver.resolve` counts a section that differs from the last observed one as a drag, so the table is rewritten from always hidden to hidden. A later read with a good frame counts as a drag back. That is the "and back" in the report.
- The report's log has the signature: the arrow reads as placed, `always hidden []` while the hidden list holds every app, no `pinned sections changed` line, and the table correct again after one read.

Not proven: why AppKit reported a wrong separator frame. The report's log never printed it, the wrong state lasted over four reads and two minutes (so it is not a one-off transient), and no code path was found that reads the bar while the engine itself has the separator out of the bar (a failed activation, a clock press and the capture reveal all end with the separator in or the cache in use). The fix does not depend on the reason, and it logs the frame and the reason so the next report settles it.

## Change

- `NativeVisibilityEngine.alwaysHiddenSeparatorDistrust`: the separator frame counts as a boundary only when the item is in the bar (visible, length above 0), the frame is on a display, placed like the arrow (`isPlaced(arrow:displays:)`), and on the hidden side of the arrow. It returns the reason, or nil.
- When it does not hold, `withLayout` logs one line (the frame and the reason), reads with no always-hidden boundary, and `MenuBarLayoutResolver.keepingAlwaysHidden` gives the apps last read as always hidden (`sectionMemory`) that section again. A read is still taken and a move across the arrow still counts. Nothing returns `nil`, so the bar still collapses.
- Because the section stays the remembered one, `observed` is unchanged for those apps: the next good read is not a drag, so a pin set in Settings is not lost either.

## Decisions

- No `return body(nil)` as for the arrow (#591): the misread lasted minutes, and a layout of nil would keep the bar from ever collapsing.
- The check uses the injected `itemFrame` and the item's `isVisible` and `length`, not `MenuBarOrder.isItem` (it reads real windows and would bypass the test seam).
- Only with the always-hidden section on (`alwaysHiddenEnabled`). With the section off the frame is nil by design and nothing changes.
- The check runs after the Debug override, so `always-hidden-boundary <x>` can force it (`always-hidden-boundary 6` reads the separator at the left edge).
- No CHANGELOG line: the repo keeps no Unreleased section, and open PR #594 edits that file.
- The unmerged branch `fix/unplaced-arrow-frame` has no diff against develop under `hidden/` or `HiddenBarTests/` (only a VM gate record under `docs/verification/`), so there is no file overlap with this change.

## Tests

`AlwaysHiddenBoundaryTests` (HiddenBarTests/MenuBarEngineTests.swift): always-hidden apps stay with the separator at the left edge (pins on, pins off); a pin set in Settings survives a bad then a good read; a good read still records drags; the distrust rules (also right to left); `keepingAlwaysHidden`. Results: `docs/verification/always-hidden-boundary/results.md`.
