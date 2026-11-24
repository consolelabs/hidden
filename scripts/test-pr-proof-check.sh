#!/bin/bash
# scripts/test-pr-proof-check.sh : offline tests for scripts/pr-proof-check.sh.
#
#   bash scripts/test-pr-proof-check.sh
#
# No network, no gh. Every case writes a body file and a changed-file list into a throwaway
# directory and checks the exit code and the message. The directory is left in $TMPDIR for the
# OS to clean.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/pr-proof-check.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-pr-proof-test.XXXXXX")"

pass=0; fail=0; failed_names=""

UI_SWIFT="hidden/Features/Settings/SettingsViews.swift"
STRINGS="hidden/en.lproj/Localizable.strings"
NON_UI="HiddenTests/NoHideNoticeTests.swift"
BODY_EMPTY="## What and why

Adds a thing.

## UI proof

- [ ] This PR changes something users see, and the proof is above
- [ ] This PR changes nothing users see
"

# body_with MARK_A MARK_B : the template with the two boxes marked (a space, x or X)
body_with() {
  printf '## What and why\n\nAdds a thing.\n\n## UI proof\n\n- [%s] This PR changes something users see, and the proof is above\n- [%s] This PR changes nothing users see\n' "$1" "$2"
}

# run_check BODY FILES... : write both inputs, run the script; sets RC and OUT
run_check() {
  local body="$1"; shift
  printf '%s\n' "$body" > "$WORK/body.md"
  : > "$WORK/files.txt"
  local f
  for f in "$@"; do printf '%s\n' "$f" >> "$WORK/files.txt"; done
  OUT="$(bash "$SCRIPT" --body "$WORK/body.md" --files "$WORK/files.txt" ${EXTRA[@]+"${EXTRA[@]}"} 2>&1)"
  RC=$?
}

check() { # description, then a command
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); failed_names="$failed_names [$desc]"
    echo "  FAIL: $desc"
  fi
}
rc_is() { [ "$RC" -eq "$1" ]; }
out_has() { printf '%s\n' "$OUT" | grep -Fq -- "$1"; }

EXTRA=()

echo "== no UI files"
run_check "$BODY_EMPTY" "$NON_UI" "docs/MANUAL.md" "scripts/test.sh"
check "tests and docs only pass" rc_is 0
run_check "$BODY_EMPTY" "HiddenTests/LocaleCoverageTests.swift" "hidden/Common/LanguagePreferences.swift"
check "non-UI Swift passes" rc_is 0

echo "== UI file, no proof"
run_check "$BODY_EMPTY" "$UI_SWIFT" "$NON_UI"
check "fails" rc_is 1
check "names the UI file" out_has "$UI_SWIFT"
check "does not name the non-UI file" test -z "$(printf '%s\n' "$OUT" | grep -F "$NON_UI")"
check "points at CONTRIBUTING.md" out_has "CONTRIBUTING.md"

echo "== the three ways"
run_check "$(body_with ' ' x)" "$UI_SWIFT"
check "ticked 'changes nothing users see' passes" rc_is 0
run_check "$(body_with ' ' X)" "$UI_SWIFT"
check "capital X passes" rc_is 0
run_check "$BODY_EMPTY
![light](https://github.com/consolelabs/hidden/blob/abc/docs/verification/x/a.png?raw=true)" "$UI_SWIFT"
check "markdown image passes" rc_is 0
run_check "$BODY_EMPTY
<img width=\"400\" src=\"https://example.com/a.png\">" "$UI_SWIFT"
check "img tag passes" rc_is 0
run_check "$BODY_EMPTY
<video src=\"https://example.com/a.mp4\"></video>" "$UI_SWIFT"
check "video tag passes" rc_is 0
run_check "$BODY_EMPTY
https://github.com/user-attachments/assets/1234abcd-0000-0000-0000-000000000000" "$UI_SWIFT"
check "user-attachments URL passes" rc_is 0
run_check "$BODY_EMPTY" "$UI_SWIFT" "docs/verification/lang-picker/settings-dark.png"
check "PNG under docs/verification passes" rc_is 0
run_check "$BODY_EMPTY" "$UI_SWIFT" "docs/verification/lang-picker/Settings-Dark.PNG"
check "upper-case .PNG under docs/verification passes" rc_is 0
run_check "$(body_with ' ' x | sed $'s/$/\r/')" "$UI_SWIFT"
check "CRLF body with the ticked opt-out passes" rc_is 0

echo "== things that must not count"
run_check "$(body_with x ' ')" "$UI_SWIFT"
check "ticking 'changes something users see' alone fails" rc_is 1
run_check "$BODY_EMPTY" "$UI_SWIFT" "docs/verification/memory-soak-heartbeat.md"
check "a text file under docs/verification fails" rc_is 1
run_check "$BODY_EMPTY" "$UI_SWIFT" "img/screenshot.png"
check "a PNG outside docs/verification fails" rc_is 1
run_check "See [the link](https://example.com/shot) for the screenshot." "$UI_SWIFT"
check "a plain link is not an image" rc_is 1
run_check "" "$UI_SWIFT"
check "an empty body fails" rc_is 1

echo "== strings and assets count as UI"
run_check "$BODY_EMPTY" "$STRINGS"
check "strings-only change fails" rc_is 1
check "strings-only names the file" out_has "$STRINGS"
run_check "$BODY_EMPTY" "hidden/Assets.xcassets/AppIcon.appiconset/Contents.json"
check "xcassets change fails" rc_is 1
run_check "$BODY_EMPTY" "hidden/Base.lproj/Main.storyboard"
check "storyboard change fails" rc_is 1
run_check "$BODY_EMPTY" "hidden/Features/Palette/PaletteContentView.swift"
check "Palette Swift file counts as UI" rc_is 1
run_check "$BODY_EMPTY" "hidden/Features/Reveal/RevealSession.swift"
check "other Features Swift file is not UI" rc_is 0
run_check "$BODY_EMPTY" "hidden/Features/Settings/My View.swift"
check "a UI path with a space is read whole" rc_is 1
check "a UI path with a space is named escaped" out_has 'My\ View.swift'
run_check "$BODY_EMPTY" "Hidden Bar.xcodeproj/project.pbxproj"
check "a non-UI path with spaces passes" rc_is 0
run_check "$BODY_EMPTY" "hidden/Base.lproj/Main.xib"
check "xib change fails" rc_is 1
run_check "$BODY_EMPTY" "::error::fake.storyboard"
check "a path that looks like a workflow command is not printed at line start" test -z "$(printf '%s\n' "$OUT" | grep -E '^::')"

echo "== bots and other bases"
EXTRA=(--author "foo[bot]")
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "bot login passes" rc_is 0
EXTRA=(--bot)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "--bot passes" rc_is 0
EXTRA=(--base release/v1.13)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "base other than develop passes" rc_is 0
EXTRA=(--base develop --author tieubao)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "human author on develop is checked" rc_is 1
EXTRA=(--author dependabot-fan)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "a human login that starts with dependabot is checked" rc_is 1
EXTRA=(--author renovate-fan)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "a human login that starts with renovate is checked" rc_is 1
EXTRA=(--author app/dependabot)
run_check "$BODY_EMPTY" "$UI_SWIFT"
check "an app/ login passes" rc_is 0
EXTRA=()

echo "== usage"
EXTRA=()
bash "$SCRIPT" --body "$WORK/nope" --files "$WORK/nope" >/dev/null 2>&1; RC=$?
check "missing input files exit 2" rc_is 2
bash "$SCRIPT" --body >/dev/null 2>&1 &
hang_pid=$!; waited=0
while kill -0 "$hang_pid" 2>/dev/null && [ "$waited" -lt 20 ]; do sleep 0.25; waited=$((waited + 1)); done
if kill -0 "$hang_pid" 2>/dev/null; then kill "$hang_pid" 2>/dev/null; RC=124; else wait "$hang_pid"; RC=$?; fi
check "a flag with no value exits 2, not a hang" rc_is 2

echo
echo "passed checks: $pass  failed checks: $fail"
if [ "$fail" -ne 0 ]; then
  echo "FAILED:$failed_names"
  exit 1
fi
echo "ALL GREEN"
