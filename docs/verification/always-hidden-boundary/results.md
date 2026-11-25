# Always-hidden boundary fix: proof

Status: unit proof pending. The mac-ui guest could not compile asset catalogs when this was written, so no test has run on this branch yet. The lines below are filled in when the run happens; nothing here is a result until then.

## Unit tests (mac-ui VM, `scripts/test.sh --scheme direct`, selected classes)

| Run | Tree | Result line |
|---|---|---|
| Red (negative control) | develop engine and layout files, the new tests | pending |
| Green | this branch | pending |

Classes: AlwaysHiddenBoundaryTests (new), UnplacedArrowTests, PinnedSectionsTests, NativeVisibilityEngineTests, MenuBarLayoutResolverTests, MultiDisplayLayoutTests, AppsLaunchedWhileHidingTests, UnrestrictedReadHookTests, HiddenTests/MenuBarLayoutResolverTests.

## VM click gate (`hb-macos2721`)

Not run. The plan is in the PR description; it needs a build of this branch and a control build of its merge base. The kit builds `Release-Direct`, which has no Debug hooks, so the misread can be forced only with an extra Debug-Direct build.
