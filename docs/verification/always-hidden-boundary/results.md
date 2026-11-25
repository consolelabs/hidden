# Always-hidden boundary fix: proof

Unit proof is from CI (GitHub runners, both schemes), because the mac-ui guest was down. The VM click gate on a real menu bar has not run.

| Run | Head | What it was | Result |
|---|---|---|---|
| [45526581286](https://github.com/consolelabs/hidden/actions/runs/45526581286) | 6d35cd8 | first version of the fix | Direct 833 passed, 5 failed; App Store 5 failed. The 5 were existing tests: a fresh read distrusted a good frame because the fake item did not report `isVisible`. A regression in the change, not a negative control |
| [45529170913](https://github.com/consolelabs/hidden/actions/runs/45529170913) | 8557e6f | the fix, with the in-bar record, the display check, the logging and 11 tests in `AlwaysHiddenBoundaryTests` | Direct 843 passed, 0 failed; App Store 537 passed, 0 failed |
| [45529950255](https://github.com/consolelabs/hidden/actions/runs/45529950255) | 8f5c029 | negative control: same tests, distrust handling switched off (`if distrust != nil, false`), so the engine behaves as develop's | Direct 838 passed, 5 failed; App Store 532 passed, 5 failed. Failed: `testAnUnplacedSeparatorDoesNotMoveAlwaysHiddenAppsToHidden`, `testAPinSetInSettingsSurvivesAMisreadSeparator`, `testWithoutPinsAMisreadSeparatorKeepsTheRememberedSplit`, `testADragDuringAMisreadIsRecordedWhenTheBoundaryReturns`, `testASeparatorTakenOutOfTheBarIsNotABoundaryAfterAFailedCollapse` (Direct xcresult). Passed as designed: the helper tests, `testAReadableSeparatorStillRecordsDrags`, `testASeparatorInTheBarIsTrustedOnTheFirstReadWithSeparatorsHidden`, `testAFirstLaunchMisreadHealsAtTheNextGoodRead` |
| final head | see the PR | the control reverted | filled in from the last CI run |

What the unit tests show: a frame the engine cannot use as a boundary (left edge, separator out of the bar, another display) keeps always-hidden apps always hidden, a pin set in Settings survives a bad then a good read, a real drag is recorded when a boundary is back, and a good frame still records drags. They inject the frame; they do not show that AppKit ever reports a bad one.

## VM click gate (`hb-macos2721`)

Not run. The plan is in the PR description. The kit builds `Release-Direct`, which has no Debug hooks, so a run on kit builds can show "guarded, no regression" (table never flips, the new log fields appear, standard checks pass) but cannot force the misread.
