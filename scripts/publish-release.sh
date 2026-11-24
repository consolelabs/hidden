#!/bin/bash
# scripts/publish-release.sh : publish the direct release that scripts/release.sh built and verified.
#
#   scripts/publish-release.sh --title "<short title>" [--dir build/release-<version>] [--dry-run|--apply] [--skip-master]
#   scripts/publish-release.sh --help
#
# Dry run is the default: the read-only preflight, then every command the publish would run and
# every check it would make, as text. Nothing is tagged, pushed, created, uploaded or changed.
# --apply runs the steps, one result line each:
#   1  body     the CHANGELOG section `## v<version> (<date>)` at the release commit, up to the next
#               `## v`, written to <dir>/publish-notes.md
#   2  tag      v<version> (lightweight, like the earlier tags) at the HEAD checks.md records; pushed
#   3  draft    gh release create --draft --verify-tag --title "v<version>: <short title>"
#   4  upload   both zips and appcast.xml; names and sizes read back
#   5  publish  gh release edit --draft=false --latest; the latest release read back
#   6  verify   releases/latest/download/appcast.xml is 200, its first shortVersionString is the
#               version, its sha256 and Hidden-Bar-macos.zip's equal SHA256SUMS
#   7a-7f       master: branch release/v<version> at the tag, PR to master, wait for its checks,
#               allow_merge_commit on, merge commit, allow_merge_commit off (EXIT trap backstop),
#               master contains the tag, delete the release branch on origin and locally
# --skip-master stops after step 6.
#
# Preflight (exit 2 before any write; every check runs and prints one line): checks.md passed;
# its version, build, the project file, the zip names and the appcast agree; SHA256SUMS verifies;
# origin is the repo; gh auth works with push (and admin for the master leg); the recorded HEAD is
# local and an ancestor of develop; the CHANGELOG section is non-empty; no v<version> tag locally
# or on origin and no release of that name; the latest published release is the one the appcast
# was built against; no release/v<version> branch (master leg).
#
# A failed step stops the run (exit 1) and prints what was done and the commands left. It never
# force-pushes, never deletes a tag or a release, and never retries a write; reads (feed checks,
# PR check polling) retry within a bound. Secrets: none beyond gh auth, whose output is discarded.
#
# Env: HB_PUBLISH_POLL (s between PR check polls, 15), HB_PUBLISH_CHECKS_TIMEOUT (s, 1800),
# HB_PUBLISH_NOCHECKS_GRACE (s with no checks reported, 120), HB_PUBLISH_VERIFY_WAIT (s, 10).
# Exit: 0 dry run clean or publish done | 1 a step failed | 2 usage or preflight refusal.
# Offline tests: scripts/test-publish-release.sh. Bash 3.2 compatible (macOS /bin/bash).

set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PBXPROJ="$ROOT/Hidden Bar.xcodeproj/project.pbxproj"
REPO_SLUG="consolelabs/hidden"
FEED_URL="https://github.com/$REPO_SLUG/releases/latest/download/appcast.xml"
LATEST_ZIP_URL="https://github.com/$REPO_SLUG/releases/latest/download/Hidden-Bar-macos.zip"
POLL="${HB_PUBLISH_POLL:-15}"
CHECKS_TIMEOUT="${HB_PUBLISH_CHECKS_TIMEOUT:-1800}"
NOCHECKS_GRACE="${HB_PUBLISH_NOCHECKS_GRACE:-120}"
VERIFY_WAIT="${HB_PUBLISH_VERIFY_WAIT:-10}"
VERIFY_TRIES=3

ME="publish-release.sh"
MODE=dry-run; SKIP_MASTER=0; TITLE=""; DIR=""
T=""; VER=""; BUILD=""; HEAD_SHA=""; PRIOR_TAG=""; NOTES=""; VZIP=""; SZIP=""
PRE_FAILS=0; PRE_FAILED_NAMES=""; STARTED=0; CUR=""; SUMMARY_DONE=0; FAIL_REASON=""
PR_NUM=""; TOGGLE_ARMED=0; TOGGLE_RESTORED=0; RESTORE_FAILED=0

say() { printf '%s\n' "$*"; }

q() { # args... : the command line, shell-quoted for display and copy-paste
  local a out=""
  for a in "$@"; do
    case "$a" in ""|*[!A-Za-z0-9_./:=@%+,-]*) a="'$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'" ;; esac
    out="$out${out:+ }$a"
  done
  printf '%s' "$out"
}

# ---- temp dir and exit ----------------------------------------------------------------------

make_tmp() {
  T="$(mktemp -d "${TMPDIR:-/tmp}/hb-publish.XXXXXX")" || { echo "$ME: mktemp failed" >&2; exit 2; }
  : > "$T/done.log"
}

on_exit() {
  local rc=$?
  restore_toggle || rc=1
  if [ "$STARTED" = 1 ] && [ "$SUMMARY_DONE" = 0 ] && [ "$rc" != 0 ]; then
    FAIL_REASON="${FAIL_REASON:-interrupted (exit $rc)}"; print_summary
  fi
  if [ -n "$T" ] && [ -d "$T" ]; then trash "$T" >/dev/null 2>&1 || true; fi
  exit "$rc"
}

setup_traps() {
  # a dead log pipe (tee gone after a HUP or a dropped ssh) must not kill the run before the
  # EXIT trap restores allow_merge_commit: ignore SIGPIPE, so a failed print is only an error
  trap '' PIPE
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

# ---- writes ---------------------------------------------------------------------------------

mut() { # cmd... : one write, run once and never retried; logged to done.log on success
  local rc
  [ "$MODE" = apply ] || { echo "$ME: internal error: a write outside --apply: $(q "$@")" >&2; exit 2; }
  say "  run: $(q "$@")"
  "$@" > "$T/mut.out" 2>&1; rc=$?
  sed -n '1,8s/^/    /p' "$T/mut.out"
  if [ "$rc" = 0 ]; then q "$@" >> "$T/done.log"; echo >> "$T/done.log"
  else FAIL_REASON="exit $rc from $(q "$@"): $(tail -2 "$T/mut.out" | tr '\n' ' ')"; fi
  return "$rc"
}

act() { # plan|run cmd... : print the write (plan) or run it through mut (run)
  local m="$1"; shift
  if [ "$m" = plan ]; then say "      $(q "$@")"; return 0; fi
  mut "$@"
}

chk() { say "      check: $*"; } # plan text for a read-back

restore_toggle() { # allow_merge_commit back to false when this run turned it on; prints the read-back
  local v
  [ "$TOGGLE_ARMED" = 1 ] && [ "$TOGGLE_RESTORED" = 0 ] || return 0
  TOGGLE_RESTORED=1
  mut gh api -X PATCH "repos/$REPO_SLUG" -F allow_merge_commit=false --jq .allow_merge_commit
  v="$(gh api "repos/$REPO_SLUG" --jq .allow_merge_commit 2>/dev/null)"
  if [ "$v" = false ]; then say "$ME: allow_merge_commit is false (read back)"; return 0; fi
  RESTORE_FAILED=1
  say "$ME: WARNING: allow_merge_commit reads '${v:-unreadable}', not false. Restore it by hand:"
  say "      $(q gh api -X PATCH "repos/$REPO_SLUG" -F allow_merge_commit=false)"
  return 1
}

# ---- inputs ---------------------------------------------------------------------------------

read_versions() { # pbxproj : prints "<marketing> <build>", rc 1 when the values disagree (as release.sh)
  local mv cv
  mv="$(grep -o 'MARKETING_VERSION = [^;]*;' "$1" | sed 's/.*= //; s/;$//' | sort | uniq -c)"
  cv="$(grep -o 'CURRENT_PROJECT_VERSION = [^;]*;' "$1" | sed 's/.*= //; s/;$//' | sort | uniq -c)"
  if [ "$(printf '%s\n' "$mv" | grep -c .)" != 1 ] || [ "$(printf '%s\n' "$cv" | grep -c .)" != 1 ]; then
    echo "versions disagree: MARKETING_VERSION [$(echo $mv)], CURRENT_PROJECT_VERSION [$(echo $cv)]"; return 1
  fi
  mv="$(echo $mv | awk '{print $2}')"; cv="$(echo $cv | awk '{print $2}')"
  case "$mv" in *[!0-9.]*|"") echo "MARKETING_VERSION '$mv' is not numeric"; return 1 ;; esac
  case "$cv" in *[!0-9]*|"") echo "CURRENT_PROJECT_VERSION '$cv' is not an integer"; return 1 ;; esac
  echo "$mv $cv"
}

changelog_section() { # version < CHANGELOG : the body under `## v<version> (`, blank edge lines trimmed
  awk -v h="## v$1 (" '
    index($0, h) == 1 && !s { s = 1; next }
    s && /^## v/ { exit }
    s { buf[++n] = $0 }
    END {
      a = 1; while (a <= n && buf[a] ~ /^[[:space:]]*$/) a++
      b = n; while (b >= a && buf[b] ~ /^[[:space:]]*$/) b--
      for (i = a; i <= b; i++) print buf[i]
    }'
}

sum_of() { awk -v n="$2" '$2 == n { print $1; exit }' "$1"; } # SHA256SUMS name : its digest
sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }
first_tag_value() { grep -m1 -o "<$2>[^<]*</$2>" "$1" | sed "s#<$2>##; s#</$2>##"; } # file tag

# ---- preflight ------------------------------------------------------------------------------

pre_ok() { say "$ME: [preflight] $1: ok, $2"; }
pre_no() { say "$ME: [preflight] $1: REFUSED, $2"; PRE_FAILS=$((PRE_FAILS + 1)); PRE_FAILED_NAMES="$PRE_FAILED_NAMES; $1"; }
pre_stop() { say "$ME: [preflight] $1: REFUSED, $2"; say "$ME: refused before any write (exit 2)"; exit 2; }

preflight() {
  local t missing="" c f vb pv pb short sver bad out rc perms push admin amc st lt

  for t in gh git curl shasum awk sed grep; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  [ -z "$missing" ] || pre_stop "Tools" "missing:$missing"
  pre_ok "Tools" "gh git curl shasum present"

  [ -d "$DIR" ] && [ ! -L "$DIR" ] || pre_stop "Release dir" "$DIR is not a directory (run scripts/release.sh first)"
  missing=""
  for f in checks.md SHA256SUMS appcast.xml Hidden-Bar-macos.zip; do [ -f "$DIR/$f" ] || missing="$missing $f"; done
  [ -z "$missing" ] || pre_stop "Release dir" "$DIR lacks:$missing"
  pre_ok "Release dir" "$DIR"
  c="$DIR/checks.md"

  if grep -q '^Result: every check passed' "$c" && ! grep -q '| FAIL: ' "$c"; then
    pre_ok "checks.md result" "$(grep -m1 '^Result:' "$c" | sed 's/ Checksums:.*//')"
  else
    pre_no "checks.md result" "checks.md does not say every check passed: $(grep -m1 '^Result:' "$c" || echo 'no Result line')"
  fi

  # checks.md is data: each field must match a strict shape before it reaches a command
  VER="$(sed -n '1s/^# Hidden Bar v\([0-9][0-9.]*\) release checks$/\1/p' "$c")"
  HEAD_SHA="$(sed -n 's/.*, HEAD `\([0-9a-f]\{40\}\)`.*/\1/p' "$c" | head -1)"
  BUILD="$(sed -n 's/.*\. Build \([0-9][0-9]*\)\. .*/\1/p' "$c" | head -1)"
  PRIOR_TAG="$(sed -n 's/.*latest published release is `\(v[0-9][0-9.]*\)`.*/\1/p' "$c" | head -1)"
  bad=""
  printf '%s' "$VER" | grep -qE '^[0-9]+(\.[0-9]+)+$' || bad="$bad version"
  [ -n "$HEAD_SHA" ] || bad="$bad HEAD"
  [ -n "$BUILD" ] || bad="$bad build"
  printf '%s' "$PRIOR_TAG" | grep -qE '^v[0-9]+(\.[0-9]+)+$' || bad="$bad prior-release"
  [ -z "$bad" ] || pre_stop "checks.md fields" "cannot read:$bad (expected the format scripts/release.sh writes)"
  pre_ok "checks.md fields" "v$VER build $BUILD, HEAD $HEAD_SHA, built against $PRIOR_TAG"
  VZIP="$DIR/Hidden-Bar-v$VER-macos.zip"; SZIP="$DIR/Hidden-Bar-macos.zip"; NOTES="$DIR/publish-notes.md"

  bad=""
  if vb="$(read_versions "$PBXPROJ")"; then
    pv="${vb% *}"; pb="${vb#* }"
    [ "$pv" = "$VER" ] || bad="$bad; project file is $pv, checks.md is $VER"
    [ "$pb" = "$BUILD" ] || bad="$bad; project build is $pb, checks.md is $BUILD"
  else bad="$bad; project file: $vb"; fi
  [ -f "$VZIP" ] || bad="$bad; no $(basename "$VZIP")"
  for f in "$DIR"/Hidden-Bar-v*-macos.zip; do
    [ -e "$f" ] && [ "$f" != "$VZIP" ] && bad="$bad; stray $(basename "$f")"
  done
  short="$(first_tag_value "$DIR/appcast.xml" sparkle:shortVersionString)"
  sver="$(first_tag_value "$DIR/appcast.xml" sparkle:version)"
  [ "$short" = "$VER" ] && [ "$sver" = "$BUILD" ] || bad="$bad; appcast item 1 is ${short:-?} (${sver:-?})"
  if [ -z "$bad" ]; then pre_ok "Versions" "checks.md, project file, zip name and appcast item 1 all say $VER ($BUILD)"
  else pre_no "Versions" "${bad#; }"; fi

  bad=""
  for f in "$(basename "$VZIP")" Hidden-Bar-macos.zip appcast.xml; do [ -n "$(sum_of "$DIR/SHA256SUMS" "$f")" ] || bad="$bad $f"; done
  if [ -n "$bad" ]; then pre_no "SHA256SUMS" "does not list:$bad"
  elif ! out="$(cd "$DIR" && shasum -a 256 -c SHA256SUMS 2>&1)"; then pre_no "SHA256SUMS" "$(printf '%s\n' "$out" | grep -v ': OK$' | head -3 | tr '\n' ' ')"
  elif [ "$(sum_of "$DIR/SHA256SUMS" "$(basename "$VZIP")")" != "$(sum_of "$DIR/SHA256SUMS" Hidden-Bar-macos.zip)" ]; then pre_no "SHA256SUMS" "the two zips differ"
  else pre_ok "SHA256SUMS" "shasum -a 256 -c passes; both zips $(sum_of "$DIR/SHA256SUMS" Hidden-Bar-macos.zip | cut -c1-12)..."; fi

  out="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
  case "$out" in
    "https://github.com/$REPO_SLUG"|"https://github.com/$REPO_SLUG.git"|"git@github.com:$REPO_SLUG.git"|"git@github.com:$REPO_SLUG"|"ssh://git@github.com/$REPO_SLUG.git") pre_ok "Origin" "$REPO_SLUG" ;;
    *) pre_stop "Origin" "git remote origin is '${out:-unset}', not $REPO_SLUG" ;;
  esac

  gh auth status >/dev/null 2>&1 || pre_stop "gh auth" "gh auth status failed; run gh auth login"
  perms="$(gh api "repos/$REPO_SLUG" --jq '"\(.permissions.push) \(.permissions.admin) \(.allow_merge_commit)"' 2>/dev/null)" \
    || pre_stop "gh auth" "gh api repos/$REPO_SLUG failed"
  read -r push admin amc <<EOF
$perms
EOF
  if [ "$push" != true ]; then pre_no "gh auth" "no push permission on $REPO_SLUG"
  elif [ "$SKIP_MASTER" = 0 ] && [ "$admin" != true ]; then pre_no "gh auth" "no admin permission (needed to toggle allow_merge_commit); use --skip-master"
  else pre_ok "gh auth" "logged in; push, admin=$admin; allow_merge_commit=$amc"; fi

  if ! git -C "$ROOT" cat-file -e "$HEAD_SHA^{commit}" 2>/dev/null; then
    pre_no "Release commit" "$HEAD_SHA is not in the local repo; git fetch origin first"
  else
    st="$(gh api "repos/$REPO_SLUG/compare/$HEAD_SHA...develop" --jq .status 2>&1)"; rc=$?
    case "$rc:$st" in
      0:identical|0:ahead) pre_ok "Release commit" "$HEAD_SHA is local and in develop ($st)" ;;
      0:*) pre_no "Release commit" "$HEAD_SHA is not an ancestor of origin/develop (compare: $st)" ;;
      *) pre_no "Release commit" "GitHub compare failed: $(printf '%s' "$st" | head -1)" ;;
    esac
  fi

  if git -C "$ROOT" show "$HEAD_SHA:CHANGELOG.md" > "$T/changelog.md" 2>/dev/null; then
    changelog_section "$VER" < "$T/changelog.md" > "$T/body.md"
    if grep -q '[^[:space:]]' "$T/body.md"; then pre_ok "CHANGELOG" "'## v$VER (' at ${HEAD_SHA:0:7}: $(grep -c . "$T/body.md") lines"
    elif grep -q "^## v$VER (" "$T/changelog.md"; then pre_no "CHANGELOG" "the '## v$VER (' section at ${HEAD_SHA:0:7} is empty"
    else pre_no "CHANGELOG" "no '## v$VER (<date>)' heading in CHANGELOG.md at ${HEAD_SHA:0:7}"; fi
  else pre_no "CHANGELOG" "git show $HEAD_SHA:CHANGELOG.md failed"; fi

  if git -C "$ROOT" rev-parse -q --verify "refs/tags/v$VER" >/dev/null 2>&1; then pre_no "Tag (local)" "tag v$VER already exists locally"
  else pre_ok "Tag (local)" "no tag v$VER"; fi
  out="$(git -C "$ROOT" ls-remote --tags origin "refs/tags/v$VER" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then pre_no "Tag (origin)" "git ls-remote failed: $(printf '%s' "$out" | head -1)"
  elif [ -n "$out" ]; then pre_no "Tag (origin)" "tag v$VER already exists on origin"
  else pre_ok "Tag (origin)" "no tag v$VER"; fi
  out="$(gh release view "v$VER" -R "$REPO_SLUG" --json isDraft --jq .isDraft 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    case "$out" in true) pre_no "Release" "a draft release v$VER already exists; finish or remove it by hand" ;;
      *) pre_no "Release" "release v$VER already exists (published)" ;; esac
  else
    case "$out" in *"release not found"*|*"Not Found"*) pre_ok "Release" "no release v$VER" ;;
      *) pre_no "Release" "gh release view failed: $(printf '%s' "$out" | head -1)" ;; esac
  fi

  lt="$(gh release view -R "$REPO_SLUG" --json tagName,isDraft --jq '"\(.tagName) \(.isDraft)"' 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then pre_no "Latest release" "gh release view (latest) failed: $(printf '%s' "$lt" | head -1)"
  elif [ "$lt" = "$PRIOR_TAG false" ]; then pre_ok "Latest release" "$PRIOR_TAG, the release the appcast was built against"
  else pre_no "Latest release" "latest is '${lt% *}', but the appcast was built against $PRIOR_TAG (it keeps the prior items); rerun scripts/release.sh"; fi

  if [ "$SKIP_MASTER" = 0 ]; then
    bad=""
    git -C "$ROOT" rev-parse -q --verify "refs/heads/release/v$VER" >/dev/null 2>&1 && bad="$bad; release/v$VER exists locally"
    out="$(git -C "$ROOT" ls-remote --heads origin "refs/heads/release/v$VER" 2>&1)"; rc=$?
    if [ "$rc" != 0 ]; then bad="$bad; git ls-remote failed: $(printf '%s' "$out" | head -1)"
    elif [ -n "$out" ]; then bad="$bad; release/v$VER exists on origin"; fi
    if [ -z "$bad" ]; then pre_ok "Release branch" "no release/v$VER locally or on origin"; else pre_no "Release branch" "${bad#; }"; fi
  fi

  [ "$PRE_FAILS" = 0 ] || { say "$ME: refused: $PRE_FAILS preflight check(s) failed (${PRE_FAILED_NAMES#; }); nothing was changed (exit 2)"; exit 2; }
}

# ---- steps ----------------------------------------------------------------------------------
# Each step takes plan|run. plan prints its commands and checks and runs nothing; run acts.

step_name() {
  case "$1" in
    1) echo "release body" ;; 2) echo "tag" ;; 3) echo "draft release" ;; 4) echo "upload" ;;
    5) echo "publish" ;; 6) echo "verify" ;; 7a) echo "master: release branch" ;; 7b) echo "master: PR" ;;
    7c) echo "master: PR checks" ;; 7d) echo "master: merge" ;; 7e) echo "master: ancestry" ;; 7f) echo "master: cleanup" ;;
  esac
}

ok() { say "$ME: [$1] $(step_name "$1"): ok, $2"; }
pr_ref() { printf '%s' "${PR_NUM:-<pr-number>}"; }

step_1() {
  if [ "$1" = plan ]; then say "      write $NOTES: the '## v$VER (' section of CHANGELOG.md at ${HEAD_SHA:0:7}"; return 0; fi
  cp "$T/body.md" "$NOTES" || { FAIL_REASON="cannot write $NOTES"; return 1; }
  ok 1 "$NOTES, $(grep -c . "$NOTES") lines"
}

step_2() {
  local out
  act "$1" git -C "$ROOT" tag "v$VER" "$HEAD_SHA" || return 1
  act "$1" git -C "$ROOT" push origin "refs/tags/v$VER:refs/tags/v$VER" || return 1
  [ "$1" = plan ] && { chk "git ls-remote --tags origin refs/tags/v$VER points at $HEAD_SHA"; return 0; }
  out="$(git -C "$ROOT" ls-remote --tags origin "refs/tags/v$VER" 2>&1)"
  [ "${out%%[[:space:]]*}" = "$HEAD_SHA" ] || { FAIL_REASON="origin's v$VER reads '${out%%[[:space:]]*}', not $HEAD_SHA"; return 1; }
  ok 2 "v$VER at $HEAD_SHA, on origin"
}

step_3() {
  local out
  act "$1" gh release create "v$VER" -R "$REPO_SLUG" --draft --verify-tag --title "v$VER: $TITLE" --notes-file "$NOTES" || return 1
  [ "$1" = plan ] && { chk "gh release view v$VER is a draft"; return 0; }
  out="$(gh release view "v$VER" -R "$REPO_SLUG" --json isDraft --jq .isDraft 2>&1)"
  [ "$out" = true ] || { FAIL_REASON="gh release view v$VER: isDraft '$out', expected true"; return 1; }
  ok 3 "draft v$VER: $TITLE"
}

step_4() {
  local out f bad=""
  act "$1" gh release upload "v$VER" -R "$REPO_SLUG" "$VZIP" "$SZIP" "$DIR/appcast.xml" || return 1
  [ "$1" = plan ] && { chk "gh release view v$VER lists the three assets with the local sizes"; return 0; }
  out="$(gh release view "v$VER" -R "$REPO_SLUG" --json assets --jq '.assets[] | "\(.name) \(.size)"' 2>&1)" \
    || { FAIL_REASON="gh release view v$VER --json assets failed"; return 1; }
  for f in "$VZIP" "$SZIP" "$DIR/appcast.xml"; do
    printf '%s\n' "$out" | grep -qxF "$(basename "$f") $(stat -f %z "$f")" || bad="$bad $(basename "$f")"
  done
  [ -z "$bad" ] || { FAIL_REASON="assets missing or wrong size:$bad"; return 1; }
  ok 4 "3 assets on the draft, sizes match"
}

step_5() {
  local out
  act "$1" gh release edit "v$VER" -R "$REPO_SLUG" --draft=false --latest || return 1
  [ "$1" = plan ] && { chk "gh release view (latest) is v$VER, not a draft"; return 0; }
  retry_read latest_is_new || return 1
  ok 5 "v$VER is the latest published release"
}

retry_read() { # check-fn : a read-back that may see a stale cache just after a write; up to VERIFY_TRIES
  local i=1
  while :; do
    "$1" && return 0
    [ "$i" -ge "$VERIFY_TRIES" ] && { FAIL_REASON="$FAIL_REASON (after $i tries)"; return 1; }
    i=$((i + 1)); sleep "$VERIFY_WAIT"
  done
}

latest_is_new() {
  local out
  out="$(gh release view -R "$REPO_SLUG" --json tagName,isDraft --jq '"\(.tagName) \(.isDraft)"' 2>&1)"
  [ "$out" = "v$VER false" ] || { FAIL_REASON="latest release reads '$out', expected 'v$VER false'"; return 1; }
}

fetch_200() { # url dest : one GET; rc 1 and FAIL_REASON when not 200
  local code
  code="$(curl -sSL --proto '=https' --proto-redir '=https' --max-time 300 -o "$2" -w '%{http_code}' "$1" 2>/dev/null)"
  [ "$code" = 200 ] || { FAIL_REASON="$1 returned ${code:-no response}"; return 1; }
}

live_feed_ok() {
  local short got want
  fetch_200 "$FEED_URL" "$T/feed.xml" || return 1
  short="$(first_tag_value "$T/feed.xml" sparkle:shortVersionString)"
  [ "$short" = "$VER" ] || { FAIL_REASON="the live feed's first shortVersionString is '$short', not $VER"; return 1; }
  got="$(sha_of "$T/feed.xml")"; want="$(sum_of "$DIR/SHA256SUMS" appcast.xml)"
  [ "$got" = "$want" ] || { FAIL_REASON="the live appcast.xml sha256 $got is not SHA256SUMS's $want"; return 1; }
}

live_zip_ok() {
  local got want
  fetch_200 "$LATEST_ZIP_URL" "$T/latest.zip" || return 1
  got="$(sha_of "$T/latest.zip")"; want="$(sum_of "$DIR/SHA256SUMS" Hidden-Bar-macos.zip)"
  [ "$got" = "$want" ] || { FAIL_REASON="the live Hidden-Bar-macos.zip sha256 $got is not SHA256SUMS's $want"; return 1; }
}

step_6() {
  if [ "$1" = plan ]; then
    chk "curl $FEED_URL is 200, its first sparkle:shortVersionString is $VER, its sha256 equals SHA256SUMS"
    chk "curl $LATEST_ZIP_URL is 200, its sha256 equals SHA256SUMS"
    return 0
  fi
  retry_read live_feed_ok || return 1
  retry_read live_zip_ok || return 1
  ok 6 "feed 200, item 1 is $VER, appcast and zip sha256 equal SHA256SUMS"
}

step_7a() {
  act "$1" git -C "$ROOT" branch "release/v$VER" "refs/tags/v$VER" || return 1
  act "$1" git -C "$ROOT" push origin "refs/heads/release/v$VER:refs/heads/release/v$VER" || return 1
  [ "$1" = plan ] && return 0
  ok 7a "release/v$VER at v$VER, on origin"
}

step_7b() {
  local body="Release merge: brings master to the v$VER tag (${HEAD_SHA:0:7}). Merged with a merge commit to keep master's release-merge history."
  act "$1" gh pr create -R "$REPO_SLUG" --base master --head "release/v$VER" --title "Release v$VER to master" --body "$body" || return 1
  [ "$1" = plan ] && return 0
  PR_NUM="$(sed -n 's#.*/pull/\([0-9][0-9]*\)[[:space:]]*$#\1#p' "$T/mut.out" | tail -1)"
  [ -n "$PR_NUM" ] || { FAIL_REASON="the PR was created but its number was not in gh's output; find it on GitHub"; return 1; }
  ok 7b "PR #$PR_NUM"
}

step_7c() {
  local start now out rc buckets errs=0 m
  if [ "$1" = plan ]; then
    chk "gh pr checks $(pr_ref) -R $REPO_SLUG: every check passes (poll ${POLL}s, up to ${CHECKS_TIMEOUT}s)"
    chk "gh pr view $(pr_ref): mergeable, head is $HEAD_SHA"
    return 0
  fi
  start="$(date +%s)"
  while :; do
    now="$(date +%s)"
    out="$(gh pr checks "$PR_NUM" -R "$REPO_SLUG" --json bucket --jq '.[].bucket' 2>&1)"; rc=$?
    buckets="$(printf '%s\n' "$out" | grep -xE 'pass|fail|pending|skipping|cancel' | sort | uniq -c | awk '{printf "%s%s %s", (NR>1?", ":""), $1, $2}')"
    if printf '%s\n' "$out" | grep -qxE 'pass|fail|pending|skipping|cancel'; then
      errs=0
      printf '%s\n' "$out" | grep -qxE 'fail|cancel' && { FAIL_REASON="PR #$PR_NUM checks: $buckets"; return 1; }
      if ! printf '%s\n' "$out" | grep -qx pending; then
        printf '%s\n' "$out" | grep -qx pass && break
        # only skipped checks: nothing actually ran, so treat it like no checks
        [ $((now - start)) -ge "$NOCHECKS_GRACE" ] && { FAIL_REASON="PR #$PR_NUM has only skipped checks ($buckets); check it by hand before merging"; return 1; }
      fi
    elif [ "$rc" = 0 ] || printf '%s' "$out" | grep -q 'no checks reported'; then
      [ $((now - start)) -ge "$NOCHECKS_GRACE" ] && { FAIL_REASON="no checks reported on PR #$PR_NUM after ${NOCHECKS_GRACE}s; check it by hand before merging"; return 1; }
    else
      errs=$((errs + 1)); [ "$errs" -ge 3 ] && { FAIL_REASON="gh pr checks failed 3 times: $(printf '%s' "$out" | head -1)"; return 1; }
    fi
    [ $((now - start)) -ge "$CHECKS_TIMEOUT" ] && { FAIL_REASON="PR #$PR_NUM checks still pending after ${CHECKS_TIMEOUT}s ($buckets)"; return 1; }
    sleep "$POLL"
  done
  for m in 1 2 3 4 5 6; do
    out="$(gh pr view "$PR_NUM" -R "$REPO_SLUG" --json mergeable,headRefOid --jq '"\(.mergeable) \(.headRefOid)"' 2>&1)"
    case "$out" in MERGEABLE\ *) break ;; CONFLICTING\ *) FAIL_REASON="PR #$PR_NUM conflicts with master"; return 1 ;; esac
    sleep "$POLL"
  done
  case "$out" in "MERGEABLE $HEAD_SHA") ;; *) FAIL_REASON="PR #$PR_NUM is not mergeable at $HEAD_SHA: '$out'"; return 1 ;; esac
  ok 7c "PR #$PR_NUM checks: $buckets; mergeable at ${HEAD_SHA:0:7}"
}

step_7d() {
  local v rc
  if [ "$1" = plan ]; then
    chk "gh api repos/$REPO_SLUG --jq .allow_merge_commit (false is expected; when true, no toggle)"
    act plan gh api -X PATCH "repos/$REPO_SLUG" -F allow_merge_commit=true --jq .allow_merge_commit
    act plan gh pr merge "$(pr_ref)" -R "$REPO_SLUG" --merge --match-head-commit "$HEAD_SHA"
    act plan gh api -X PATCH "repos/$REPO_SLUG" -F allow_merge_commit=false --jq .allow_merge_commit
    chk "gh api repos/$REPO_SLUG --jq .allow_merge_commit reads false (restored by an EXIT trap on every path)"
    return 0
  fi
  v="$(gh api "repos/$REPO_SLUG" --jq .allow_merge_commit 2>&1)" || { FAIL_REASON="cannot read allow_merge_commit"; return 1; }
  case "$v" in
    false)
      TOGGLE_ARMED=1 # before the PATCH: it can land on GitHub and still fail here
      mut gh api -X PATCH "repos/$REPO_SLUG" -F allow_merge_commit=true --jq .allow_merge_commit
      rc=$?
      if [ "$rc" != 0 ] || [ "$(tail -1 "$T/mut.out")" != true ]; then
        FAIL_REASON="${FAIL_REASON:-allow_merge_commit did not read true after the PATCH}"; restore_toggle; return 1
      fi ;;
    true) say "$ME: allow_merge_commit was already true before this run; leaving it as found" ;;
    *) FAIL_REASON="allow_merge_commit reads '$v'"; return 1 ;;
  esac
  mut gh pr merge "$PR_NUM" -R "$REPO_SLUG" --merge --match-head-commit "$HEAD_SHA"; rc=$?
  restore_toggle || { [ "$rc" = 0 ] && FAIL_REASON="merged, but allow_merge_commit was not restored"; rc=1; }
  [ "$rc" = 0 ] || return 1
  ok 7d "PR #$PR_NUM merged with a merge commit"
}

step_7e() {
  local st
  if [ "$1" = plan ]; then
    say "      $(q git -C "$ROOT" fetch origin master)"
    chk "git merge-base --is-ancestor v$VER origin/master"
    return 0
  fi
  git -C "$ROOT" fetch origin master >/dev/null 2>&1 || { FAIL_REASON="git fetch origin master failed"; return 1; }
  git -C "$ROOT" merge-base --is-ancestor "v$VER" origin/master || { FAIL_REASON="v$VER is not an ancestor of origin/master"; return 1; }
  st="$(gh pr view "$PR_NUM" -R "$REPO_SLUG" --json state --jq .state 2>&1)"
  ok 7e "origin/master contains v$VER; PR #$PR_NUM $st"
}

step_7f() {
  act "$1" git -C "$ROOT" push origin --delete "refs/heads/release/v$VER" || return 1
  act "$1" git -C "$ROOT" branch -d "release/v$VER" || return 1
  [ "$1" = plan ] && return 0
  ok 7f "release/v$VER deleted on origin and locally"
}

all_steps() { if [ "$SKIP_MASTER" = 1 ]; then echo "1 2 3 4 5 6"; else echo "1 2 3 4 5 6 7a 7b 7c 7d 7e 7f"; fi; }

print_plan() { # from-step : the plan of that step and every later one
  local s on=0
  for s in $(all_steps); do
    [ "$s" = "$1" ] && on=1
    [ "$on" = 1 ] || continue
    say "  [$s] $(step_name "$s")"
    "step_$s" plan
  done
}

print_summary() {
  SUMMARY_DONE=1
  say "$ME: [$CUR] $(step_name "$CUR"): FAILED, $FAIL_REASON"
  say "$ME: stopped at step $CUR. Done so far:"
  if [ -s "$T/done.log" ]; then sed 's/^/      /' "$T/done.log"; else say "      nothing was changed"; fi
  say "$ME: left to do by hand, in order (step $CUR may be partly done: check it first):"
  print_plan "$CUR"
  [ "$RESTORE_FAILED" = 0 ] || say "$ME: WARNING: allow_merge_commit is not confirmed false; see above"
}

# ---- main -----------------------------------------------------------------------------------

usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local s
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) [ $# -ge 2 ] || { usage >&2; exit 2; }; DIR="$2"; shift ;;
      --title) [ $# -ge 2 ] || { usage >&2; exit 2; }; TITLE="$2"; shift ;;
      --dry-run) MODE=dry-run ;;
      --apply) MODE=apply ;;
      --skip-master) SKIP_MASTER=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "$ME: unknown argument $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done
  [ -n "$TITLE" ] || { echo "$ME: --title is required (the release is titled \"v<version>: <title>\")" >&2; exit 2; }
  case "$TITLE" in *[[:cntrl:]]*) echo "$ME: --title must be one line" >&2; exit 2 ;; esac
  if [ -z "$DIR" ]; then
    s="$(read_versions "$PBXPROJ")" || { echo "$ME: $s" >&2; exit 2; }
    DIR="$ROOT/build/release-${s% *}"
  fi
  case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
  DIR="${DIR%/}"
  cd "$ROOT" || exit 2
  make_tmp; setup_traps

  say "$ME: $MODE for $DIR$([ "$SKIP_MASTER" = 1 ] && echo ' (--skip-master)')"
  preflight

  if [ "$MODE" = dry-run ]; then
    say "$ME: preflight passed. Release body ($NOTES):"
    sed 's/^/  | /' "$T/body.md"
    say "$ME: dry run, nothing was changed. --apply would run, in order:"
    print_plan 1
    exit 0
  fi

  exec > >(tee -a "$DIR/publish.log") 2>&1
  STARTED=1
  for s in $(all_steps); do
    CUR="$s"; FAIL_REASON=""
    "step_$s" run || { print_summary; exit 1; }
  done
  say "$ME: published v$VER$([ "$SKIP_MASTER" = 1 ] && echo ' (master leg skipped)'). Homebrew cask and App Store stay manual."
}

main "$@"
