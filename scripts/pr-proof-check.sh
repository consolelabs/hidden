#!/bin/bash
# scripts/pr-proof-check.sh : the "PR proof" check. A pull request that changes what users see
# must show proof on screen. No network: the caller (.github/workflows/pr-proof.yml) fetches the
# data with gh and passes it in.
#
#   bash scripts/pr-proof-check.sh --body FILE --files FILE [--base BRANCH] [--author LOGIN] [--bot]
#
#   --body FILE     the pull request description, as text
#   --files FILE    the changed paths, one per line
#   --base BRANCH   the base branch; anything but develop passes (default: develop)
#   --author LOGIN  the author login; a bot login passes
#   --bot           the author is a bot (gh author.is_bot); passes
#
# A path "looks like UI" when it is one of:
#   hidden/Features/**/*.swift whose path contains Settings, Preferences, StatusBar, Notice,
#                      Palette, Presentation, Arrivals or About
#   *.storyboard, *.xib, anything under *.xcassets/, *.lproj/*.strings
#
# A UI change passes when ANY of these holds:
#   1. the body ticks "- [x] This PR changes nothing users see" (x in either case)
#   2. the body has an image or video: a markdown image, <img, <video, or a user-attachments/assets/ URL
#   3. the changed paths include an image or video under docs/verification/
#
# Exit 0 pass, 1 proof missing, 2 bad usage.

body_file=""; files_file=""; base="develop"; author=""; is_bot=0
while [ $# -gt 0 ]; do
  case "$1" in
    --body|--files|--base|--author)
      [ $# -ge 2 ] || { echo "pr-proof-check: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --body)   body_file="$2"; shift 2 ;;
    --files)  files_file="$2"; shift 2 ;;
    --base)   base="$2"; shift 2 ;;
    --author) author="$2"; shift 2 ;;
    --bot)    is_bot=1; shift ;;
    *) echo "pr-proof-check: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -r "$body_file" ] && [ -r "$files_file" ] || { echo "pr-proof-check: --body and --files must be readable files" >&2; exit 2; }

if [ "$base" != "develop" ]; then
  echo "PR proof: base is $base, not develop. Nothing to check."
  exit 0
fi
case "$author" in
  *"[bot]"|app/*) is_bot=1 ;;
esac
if [ "$is_bot" -eq 1 ]; then
  echo "PR proof: bot author. Nothing to check."
  exit 0
fi

is_ui_path() {
  case "$1" in
    hidden/Features/*.swift)
      case "$1" in
        *Settings*|*Preferences*|*StatusBar*|*Notice*|*Palette*|*Presentation*|*Arrivals*|*About*) return 0 ;;
      esac
      return 1 ;;
    *.storyboard|*.xib|*.xcassets/*|*.lproj/*.strings) return 0 ;;
  esac
  return 1
}

is_proof_path() {
  case "$1" in
    docs/verification/*)
      case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.mp4|*.mov) return 0 ;;
      esac ;;
  esac
  return 1
}

ui_files=""; proof_in_diff=0
while IFS= read -r path || [ -n "$path" ]; do
  path="${path%$'\r'}"
  [ -n "$path" ] || continue
  if is_ui_path "$path"; then ui_files="$ui_files$path"$'\n'; fi
  if is_proof_path "$path"; then proof_in_diff=1; fi
done < "$files_file"

if [ -z "$ui_files" ]; then
  echo "PR proof: no changed path looks like UI. Pass."
  exit 0
fi

body="$(tr -d '\r' < "$body_file")"

if printf '%s\n' "$body" | grep -Eiq '^[[:space:]]*[-*][[:space:]]+\[x\][[:space:]]+This PR changes nothing users see'; then
  echo "PR proof: the box 'changes nothing users see' is ticked. Pass."
  exit 0
fi
if printf '%s\n' "$body" | grep -Eiq '!\[[^]]*\]\([^)]+\)|<img[[:space:]>]|<video[[:space:]>]|user-attachments/assets/'; then
  echo "PR proof: the description has an image or video. Pass."
  exit 0
fi
if [ "$proof_in_diff" -eq 1 ]; then
  echo "PR proof: the diff adds proof under docs/verification/. Pass."
  exit 0
fi

echo "PR proof: FAILED. This PR changes files that look like UI, and shows no proof."
echo
echo "Changed files that look like UI:"
while IFS= read -r ui_path; do
  [ -n "$ui_path" ] && printf '  - %q\n' "$ui_path"
done <<EOF_UI
$ui_files
EOF_UI
echo
echo "Satisfy this check in one of three ways:"
echo "  1. Add a screenshot or short recording to the PR description (light and dark where the"
echo "     look changes, one non-English locale where text changes)."
echo "  2. Commit PNG files under docs/verification/<short-name>/ in this PR."
echo "  3. If users see no change (a refactor, a rename), tick the box"
echo "     '- [x] This PR changes nothing users see' in the description."
echo
echo "The check runs again when you edit the description or push. See the UI proof section of CONTRIBUTING.md."
exit 1
