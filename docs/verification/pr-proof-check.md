# PR proof check: verification

Run with macOS `/bin/bash` 3.2.57 on the branch `chore/pr-ui-proof-rule`, after merging `origin/develop`. No app, no Xcode build. Inputs are throwaway files: a PR body and a list of changed paths (`ui.txt` holds `hidden/Features/Settings/SettingsViews.swift`, `nonui.txt` holds `HiddenTests/NoHideNoticeTests.swift`).

| Case | Command | Result |
|---|---|---|
| UI PR without proof fails | `bash scripts/pr-proof-check.sh --body empty.md --files ui.txt` | exit 1, `PR proof: FAILED. This PR changes files that look like UI, and shows no proof.` |
| UI PR with an image passes | `bash scripts/pr-proof-check.sh --body image.md --files ui.txt` | exit 0, `PR proof: the description has an image or video. Pass.` |
| Opt-out tick passes | `bash scripts/pr-proof-check.sh --body tick.md --files ui.txt` | exit 0, `PR proof: the box 'changes nothing users see' is ticked. Pass.` |
| Non-UI PR passes | `bash scripts/pr-proof-check.sh --body empty.md --files nonui.txt` | exit 0, `PR proof: no changed path looks like UI. Pass.` |
| Bot passes | `bash scripts/pr-proof-check.sh --body empty.md --files ui.txt --bot` | exit 0, `PR proof: bot author. Nothing to check.` |
| Non-develop base passes | `bash scripts/pr-proof-check.sh --body empty.md --files ui.txt --base release/v1.13` | exit 0, `PR proof: base is release/v1.13, not develop. Nothing to check.` |
| Full suite, unmodified script | `bash scripts/test-pr-proof-check.sh` | `passed checks: 31  failed checks: 0`, `ALL GREEN` |
| Negative control A | final `exit 1` of `scripts/pr-proof-check.sh` changed to `exit 0`, then `bash scripts/test-pr-proof-check.sh` | exit 1, `passed checks: 20  failed checks: 11` |
| Negative control B | the missing-value guard in the argument loop removed, then `bash scripts/test-pr-proof-check.sh` | exit 1, `passed checks: 30  failed checks: 1`, `FAILED: [a flag with no value exits 2, not a hang]` |
| Restored, rerun | `bash scripts/test-pr-proof-check.sh` | `passed checks: 31  failed checks: 0`, `ALL GREEN` |
| Open PR #594 dry run | body, author and file list fetched with `gh pr view 594 --json body,author,baseRefName` and `gh api repos/dwarvesf/hidden/pulls/594/files --paginate`, then the script | exit 0, `PR proof: the description has an image or video. Pass.` (13 files, author `xgustavu`, base `develop`) |

## Notes

- Both negative controls were restored from a saved copy of the file, and the suite was rerun green. The committed script is the unmodified version plus the argument guard.
- A defect found and fixed: `pr-proof-check.sh --body` with no value looped forever, because `shift 2` fails on a single remaining argument and does not consume it. It now exits 2 with `pr-proof-check: --body needs a value`. The suite has a case for it.
- The pinned `actions/checkout` SHA `3d3c42e5aac5ba805825da76410c181273ba90b1` is the commit that the tag `v7.0.1` points to (`gh api repos/actions/checkout/git/ref/tags/v7.0.1`), and the same SHA is pinned in `.github/workflows/ci.yml`.
- The check runs the script from the PR's own checkout, so a PR that edits `scripts/pr-proof-check.sh` is judged by its own edited rule. The check helps reviewers; it does not stop a deliberate bypass. A reviewer sees any change to the script in the diff.
- The workflow's own run on the PR that adds it is recorded in the PR description, not here.
