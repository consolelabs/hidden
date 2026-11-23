#!/bin/bash
# scripts/test-publish-release.sh : offline tests for scripts/publish-release.sh.
#
#   bash scripts/test-publish-release.sh
#
# No network and no GitHub: gh, git, curl and trash are PATH stubs that record every call, and
# publish-release.sh runs under `env -i PATH=<stubs>:/usr/bin:/bin`, so the real gh is unreachable.
# Each stub exits 9 on a call it does not know. The script runs from a fixture repo built under
# $TMPDIR (its ROOT follows its own path). The fixture checks.md and SHA256SUMS come from
# release.sh's own write_report, so a change to that format breaks these tests.
# Covers: the dry run makes no write, each preflight refusal fires on its own bad input, the
# --apply happy path calls the steps in order, a failed upload stops before publish and prints
# the steps left, allow_merge_commit is restored after a failed merge, --skip-master stops after
# the verify step, and no write in the script bypasses its mut wrapper.
# One PASS/FAIL line per case; exit 0 only when no case failed.

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hb-publish-test.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
PASSED=0; FAILED_N=0; FAILED_NAMES=""
SHA="45966562c4678062ac74bd228e18a46512780004"

result() { # name rc [reason]
  if [ "$2" = 0 ]; then echo "PASS $1"; PASSED=$((PASSED + 1))
  else echo "FAIL $1${3:+: $3}"; FAILED_N=$((FAILED_N + 1)); FAILED_NAMES="$FAILED_NAMES $1"; fi
}
t() { local name="$1"; shift; "$@" >"$WORK/case.log" 2>&1; result "$name" $? "$(tail -1 "$WORK/case.log")"; }

STUBS="$WORK/stubs"; mkdir -p "$STUBS"
stub() { cat > "$STUBS/$1"; chmod +x "$STUBS/$1"; }

# gh: GitHub state lives in files under $STUB_MARKS; STUB_* env vars pick the scenario.
stub gh <<'EOF'
#!/bin/bash
M="$STUB_MARKS"; echo "gh $*" >> "$M/calls"
fails() { [ "${STUB_FAIL:-}" = "$1" ]; }
rel() { cat "$M/release" 2>/dev/null || echo "${STUB_RELEASE:-absent}"; }
amc() { cat "$M/amc" 2>/dev/null || echo "${STUB_AMC:-false}"; }
case "$*" in
  "auth status") [ -z "${STUB_AUTH_FAIL:-}" ] || { echo "You are not logged into any GitHub hosts" >&2; exit 1; } ;;
  "api repos/consolelabs/hidden --jq \"\(.permissions.push) \(.permissions.admin) \(.allow_merge_commit)\"") echo "$(printf %s "${STUB_PERMS:-true_true}" | tr _ " ") $(amc)" ;;
  "api repos/consolelabs/hidden --jq .allow_merge_commit") amc ;;
  "api -X PATCH repos/consolelabs/hidden -F allow_merge_commit="*)
    all="$*"; v="${all##*allow_merge_commit=}"; v="${v%% *}"
    [ "$v" = true ] && fails patch-true-lands && { echo true > "$M/amc"; echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    [ "$v" = false ] && fails patch-false && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    echo "$v" > "$M/amc"; echo "$v" ;;
  "api repos/consolelabs/hidden/compare/"*"...develop --jq .status") echo "${STUB_COMPARE:-ahead}" ;;
  "release view v"*" --json isDraft --jq .isDraft")
    case "$(rel)" in absent) echo "release not found" >&2; exit 1 ;; draft) echo true ;; published) echo false ;; *) echo "HTTP 502" >&2; exit 1 ;; esac ;;
  "release view -R consolelabs/hidden --json tagName,isDraft --jq "*)
    if [ "$(cat "$M/release" 2>/dev/null)" = published ]; then echo "v1.13.4 false"; else echo "${STUB_LATEST:-v1.13.3} false"; fi ;;
  "release create v1.13.4 "*) fails create && { echo "HTTP 422" >&2; exit 1; }; echo draft > "$M/release"; echo "https://github.com/consolelabs/hidden/releases/tag/untagged-x" ;;
  "release upload v1.13.4 "*)
    fails upload && { echo "HTTP 502: Bad Gateway (upload)" >&2; exit 1; }
    shift 4; for f in "$@"; do echo "$(basename "$f") $(stat -f %z "$f")" >> "$M/assets"; done ;;
  "release view v1.13.4 -R consolelabs/hidden --json assets "*) cat "$M/assets" ;;
  "release edit v1.13.4 -R consolelabs/hidden --draft=false --latest") echo published > "$M/release"; echo "https://github.com/consolelabs/hidden/releases/tag/v1.13.4" ;;
  "pr create -R consolelabs/hidden --base master --head release/v1.13.4 "*) echo "https://github.com/consolelabs/hidden/pull/600" ;;
  "pr checks 600 -R consolelabs/hidden --json bucket --jq .[].bucket")
    case "${STUB_CHECKS:-pass}" in empty) exit 0 ;; none) echo "no checks reported on the 'release/v1.13.4' branch" >&2; exit 1 ;; fail) printf 'pass\nfail\n'; exit 1 ;; *) printf 'pass\npass\npass\n' ;; esac ;;
  "pr view 600 -R consolelabs/hidden --json mergeable,headRefOid --jq "*) echo "MERGEABLE $STUB_SHA" ;;
  "pr merge 600 -R consolelabs/hidden --merge --match-head-commit $STUB_SHA")
    fails merge && { echo "GraphQL: Pull request is not mergeable" >&2; exit 1; }
    fails signal && { for c in $(pgrep -P "$PPID"); do pkill -x -P "$c" tee && : > "$M/tee-killed"; done; kill -TERM "$PPID"; sleep 0.3; exit 1; }
    [ "$(amc)" = true ] || { echo "merge commits disabled" >&2; exit 1; }; : > "$M/merged" ;;
  "pr view 600 -R consolelabs/hidden --json state --jq .state") echo MERGED ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 9 ;;
esac
EOF

stub git <<'EOF'
#!/bin/bash
M="$STUB_MARKS"; echo "git $*" >> "$M/calls"
[ "$1" = -C ] && shift 2
case "$*" in
  "remote get-url origin") echo "${STUB_ORIGIN:-https://github.com/consolelabs/hidden.git}" ;;
  "cat-file -e $STUB_SHA^{commit}") [ -z "${STUB_NO_COMMIT:-}" ] ;;
  "show $STUB_SHA:CHANGELOG.md") cat "$STUB_CHANGELOG" ;;
  "rev-parse -q --verify refs/tags/v1.13.4") { [ -n "${STUB_LOCAL_TAG:-}" ] || [ -e "$M/tag" ]; } && echo "$STUB_SHA" ;;
  "rev-parse -q --verify refs/heads/release/v1.13.4") [ -n "${STUB_LOCAL_BRANCH:-}" ] && echo "$STUB_SHA" ;;
  "ls-remote --tags origin refs/tags/v1.13.4")
    [ -n "${STUB_LSREMOTE_FAIL:-}" ] && { echo "fatal: unable to access 'https://github.com/consolelabs/hidden.git/'" >&2; exit 128; }
    { [ -n "${STUB_REMOTE_TAG:-}" ] || [ -e "$M/tag-pushed" ]; } && printf '%s\trefs/tags/v1.13.4\n' "$STUB_SHA"; exit 0 ;;
  "ls-remote --heads origin refs/heads/release/v1.13.4") [ -n "${STUB_REMOTE_BRANCH:-}" ] && printf '%s\trefs/heads/release/v1.13.4\n' "$STUB_SHA"; exit 0 ;;
  "tag v1.13.4 $STUB_SHA") : > "$M/tag" ;;
  "push origin refs/tags/v1.13.4:refs/tags/v1.13.4") : > "$M/tag-pushed" ;;
  "branch release/v1.13.4 refs/tags/v1.13.4") : > "$M/branch" ;;
  "push origin refs/heads/release/v1.13.4:refs/heads/release/v1.13.4") : ;;
  "fetch origin master") : ;;
  "merge-base --is-ancestor v1.13.4 origin/master") [ -e "$M/merged" ] ;;
  "push origin --delete refs/heads/release/v1.13.4") : ;;
  "branch -d release/v1.13.4") : ;;
  *) echo "stub git: unexpected: $*" >&2; exit 9 ;;
esac
EOF

stub curl <<'EOF'
#!/bin/bash
# copies STUB_FEED or STUB_ZIP to the -o target and prints the http code for -w
M="$STUB_MARKS"; echo "curl $*" >> "$M/calls"
out=""; prev=""; for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
url="${!#}"
case "$url" in
  https://github.com/consolelabs/hidden/releases/latest/download/appcast.xml)
    if [ -n "${STUB_STALE_ONCE:-}" ] && [ ! -e "$M/stale-served" ]; then : > "$M/stale-served"; cp "$STUB_STALE_ONCE" "$out"; else cp "$STUB_FEED" "$out"; fi ;;
  https://github.com/consolelabs/hidden/releases/latest/download/Hidden-Bar-macos.zip) cp "$STUB_ZIP" "$out" ;;
  *) echo "stub curl: unexpected: $*" >&2; exit 9 ;;
esac
printf '%s' "${STUB_HTTP:-200}"
EOF

stub trash <<'EOF'
#!/bin/bash
mkdir -p "$STUB_MARKS/trashed" && mv "$1" "$STUB_MARKS/trashed/" 2>/dev/null
EOF

PATH_UNDER_TEST="$STUBS:/usr/bin:/bin"
for tool in gh git curl trash; do
  [ "$(PATH="$PATH_UNDER_TEST" command -v "$tool")" = "$STUBS/$tool" ] || { echo "FAIL stub-shadowing ($tool resolves to $(PATH="$PATH_UNDER_TEST" command -v "$tool"))"; exit 1; }
done

# ---- fixtures ------------------------------------------------------------------------------

appcast() { # short build : a two-item appcast in release.sh's layout
  cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Hidden Bar</title>
        <item>
            <title>$1</title>
            <sparkle:version>$2</sparkle:version>
            <sparkle:shortVersionString>$1</sparkle:shortVersionString>
        </item>
        <item>
            <title>1.13.3</title>
            <sparkle:version>24</sparkle:version>
            <sparkle:shortVersionString>1.13.3</sparkle:shortVersionString>
        </item>
    </channel>
</rss>
XML
}

fixture() { # name [write_report-code] : a repo copy plus build/release-1.13.4, made by release.sh's write_report
  local d="$WORK/$1" out code="${2:-0}"
  out="$d/build/release-1.13.4"
  mkdir -p "$d/scripts" "$d/Hidden Bar.xcodeproj" "$out" "$d.marks"
  cp "$ROOT/scripts/publish-release.sh" "$d/scripts/"
  printf 'MARKETING_VERSION = 1.13.4;\nCURRENT_PROJECT_VERSION = 25;\nMARKETING_VERSION = 1.13.4;\nCURRENT_PROJECT_VERSION = 25;\n' > "$d/Hidden Bar.xcodeproj/project.pbxproj"
  printf '# Changelog\n\n## v1.13.4 (2026-11-23)\n\n### Fixed\n- A fixture fix.\n\n## v1.13.3 (2026-11-23)\n\n### Fixed\n- Older.\n' > "$d/CHANGELOG.md"
  head -c 4096 /dev/urandom > "$out/Hidden-Bar-v1.13.4-macos.zip"
  cp "$out/Hidden-Bar-v1.13.4-macos.zip" "$out/Hidden-Bar-macos.zip"
  appcast 1.13.4 25 > "$out/appcast.xml"
  printf '<ul><li>x</li></ul>\n' > "$out/release-notes.html"
  ( RELEASE_SH_SOURCE_ONLY=1; . "$ROOT/scripts/release.sh"
    T="$WORK/$1.rt"; mkdir -p "$T"; ROWS_FILE="$T/rows.md"; : > "$ROWS_FILE"
    OUT="$out"; VER=1.13.4; BUILD=25; HEAD_SHA="$SHA"; TREE_NOTE="clean at preflight"; PRIOR_TAG=v1.13.3
    row "Tools" "command -v" "all present"
    [ "$code" = 0 ] || fail_row "Notarization" "xcrun notarytool" "Invalid"
    write_report "$code" ) >/dev/null 2>&1
  echo "$d"
}

pub() { # fixture-dir args... : run the fixture's publish-release.sh with stubs only, polls at 0 s
  local d="$1"; shift
  ( cd "$d" && env -i PATH="$PATH_UNDER_TEST" HOME="$d" TMPDIR="$WORK" STUB_MARKS="$d.marks" STUB_SHA="$SHA" \
      STUB_CHANGELOG="$d/CHANGELOG.md" STUB_FEED="${STUB_FEED:-$d/build/release-1.13.4/appcast.xml}" \
      STUB_ZIP="$d/build/release-1.13.4/Hidden-Bar-macos.zip" ${STUB_STALE_ONCE:+STUB_STALE_ONCE=$STUB_STALE_ONCE} HB_PUBLISH_POLL=0 HB_PUBLISH_VERIFY_WAIT=0 HB_PUBLISH_NOCHECKS_GRACE=0 \
      ${EXTRA_ENV:-} bash scripts/publish-release.sh --title "fixture title" "$@" )
}

WRITES='^(git (-C [^ ]+ )?(tag|push|branch)|gh (release (create|upload|edit|delete)|pr (create|merge)|api -X))'
writes_of() { grep -E "$WRITES" "$1.marks/calls" 2>/dev/null | sed -E 's/^git -C [^ ]+ /git /'; } # fixture : the write calls, in order

# ---- usage ---------------------------------------------------------------------------------

D="$(fixture args)"
help_ok() { local o; o="$(bash "$ROOT/scripts/publish-release.sh" --help)"; [ $? = 0 ] && for v in --title --dir --apply --skip-master HB_PUBLISH_POLL; do printf '%s' "$o" | grep -qF -- "$v" || { echo "help lacks $v"; return 1; }; done; }
t help-exits-0-and-documents-flags help_ok
rc_of() { local want="$1"; shift; "$@" >/dev/null 2>&1; [ $? = "$want" ]; }
t unknown-argument-exits-2 rc_of 2 pub "$D" --frobnicate
no_title() { ( cd "$D" && env -i PATH="$PATH_UNDER_TEST" STUB_MARKS="$D.marks" bash scripts/publish-release.sh ) 2>&1 | grep -q -- '--title is required'; }
t missing-title-exits-2 no_title
syntax() { bash -n "$ROOT/scripts/publish-release.sh" && bash -n "$ROOT/scripts/test-publish-release.sh"; }
t bash-n-both-scripts syntax

# ---- dry run -------------------------------------------------------------------------------

dry_run() {
  local d o rc needle; d="$(fixture dry)"
  o="$(pub "$d" 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "rc $rc: $(printf '%s' "$o" | grep REFUSED | head -2)"; return 1; }
  printf '%s' "$o" | grep -q 'dry run, nothing was changed' || { echo "no dry-run line"; return 1; }
  for needle in "git -C $d tag v1.13.4 $SHA" "gh release create v1.13.4 -R consolelabs/hidden --draft --verify-tag --title 'v1.13.4: fixture title'" \
      "gh release upload v1.13.4" "gh release edit v1.13.4 -R consolelabs/hidden --draft=false --latest" "check: curl https://github.com/consolelabs/hidden/releases/latest/download/appcast.xml" \
      "gh pr merge '<pr-number>'" "allow_merge_commit=true" "allow_merge_commit=false" "  | - A fixture fix."; do
    printf '%s' "$o" | grep -qF -- "$needle" || { echo "plan lacks: $needle"; return 1; }
  done
  [ -z "$(writes_of "$d")" ] || { echo "dry run made writes: $(writes_of "$d" | head -2 | tr '\n' ';')"; return 1; }
  ! grep -qE '^(git (-C [^ ]+ )?fetch|curl )' "$d.marks/calls" || { echo "dry run fetched or downloaded"; return 1; }
  [ ! -e "$d/build/release-1.13.4/publish-notes.md" ] && [ ! -e "$d/build/release-1.13.4/publish.log" ] || { echo "dry run wrote files"; return 1; }
}
t dry-run-makes-no-write-and-prints-every-step dry_run

# ---- preflight refusals: each bad input alone trips exactly its own check --------------------

refuses() { # name needle setup-fn [args...] : rc 2, exactly one refused check naming the needle, no write
  local d o rc n="$1" needle="$2" setup="$3"; shift 3; d="$(fixture "$n")"
  "$setup" "$d"
  o="$(pub "$d" "$@" 2>&1)"; rc=$?
  [ "$rc" = 2 ] || { echo "rc $rc, expected 2"; return 1; }
  printf '%s' "$o" | grep -qF -- "$needle" || { echo "no '$needle' in: $(printf '%s' "$o" | grep REFUSED | head -2 | tr '\n' ' ')"; return 1; }
  [ "$(printf '%s\n' "$o" | grep -c ': REFUSED, ')" = 1 ] || { echo "more than one refusal: $(printf '%s\n' "$o" | grep ': REFUSED, ' | tr '\n' ' ')"; return 1; }
  [ -z "$(writes_of "$d")" ] || { echo "writes before refusal"; return 1; }
}
nothing() { :; }
refuse_env() { EXTRA_ENV="$3" refuses "$1" "$2" nothing; } # name needle env : the bad input is a stub scenario
bump_project() { sed -i '' 's/1\.13\.4/1.13.5/' "$1/Hidden Bar.xcodeproj/project.pbxproj"; }
zip_stray() { cp "$1/build/release-1.13.4/Hidden-Bar-v1.13.4-macos.zip" "$1/build/release-1.13.4/Hidden-Bar-v1.13.5-macos.zip"; }
zip_tampered() { printf 'x' >> "$1/build/release-1.13.4/Hidden-Bar-macos.zip"; }
section_missing() { printf '# Changelog\n\n## v1.13.3 (2026-11-23)\n\n- Older.\n' > "$1/CHANGELOG.md"; }
section_empty() { printf '# Changelog\n\n## v1.13.4 (2026-11-23)\n\n\n## v1.13.3 (2026-11-23)\n\n- Older.\n' > "$1/CHANGELOG.md"; }

failed_fixture_refuses() {
  local d o rc; d="$(fixture failedrun 1)"
  grep -q '^Result: FAILED' "$d/build/release-1.13.4/checks.md" || { echo "fixture is not a failed checks.md"; return 1; }
  o="$(pub "$d" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s' "$o" | grep -q 'checks.md result: REFUSED' && [ "$(printf '%s\n' "$o" | grep -c ': REFUSED, ')" = 1 ] && [ -z "$(writes_of "$d")" ] \
    || { echo "rc $rc: $(printf '%s\n' "$o" | grep REFUSED | tr '\n' ' ')"; return 1; }
}
t refuse-checks-md-not-all-passed failed_fixture_refuses
t refuse-project-version-disagrees refuses projver 'Versions: REFUSED, project file is 1.13.5' bump_project --dir build/release-1.13.4
t refuse-zip-name-disagrees refuses zipname 'Versions: REFUSED, stray Hidden-Bar-v1.13.5-macos.zip' zip_stray
t refuse-sha256sums-mismatch refuses sums 'SHA256SUMS: REFUSED' zip_tampered
t refuse-changelog-section-missing refuses nosection "no '## v1.13.4 (<date>)' heading" section_missing
t refuse-changelog-section-empty refuses emptysection "section at 4596656 is empty" section_empty
t refuse-local-tag-exists refuse_env localtag 'Tag (local): REFUSED' STUB_LOCAL_TAG=1
t refuse-origin-tag-exists refuse_env remotetag 'Tag (origin): REFUSED, tag v1.13.4 already exists' STUB_REMOTE_TAG=1
t refuse-origin-unreachable-fails-closed refuse_env lsfail 'Tag (origin): REFUSED, git ls-remote failed' STUB_LSREMOTE_FAIL=1
t refuse-draft-release-exists refuse_env draft 'Release: REFUSED, a draft release v1.13.4 already exists' STUB_RELEASE=draft
t refuse-published-release-exists refuse_env published 'Release: REFUSED, release v1.13.4 already exists' STUB_RELEASE=published
t refuse-release-lookup-error-fails-closed refuse_env relerr 'Release: REFUSED, gh release view failed' STUB_RELEASE=error
t refuse-head-not-in-develop refuse_env diverged "Release commit: REFUSED, $SHA is not an ancestor" STUB_COMPARE=diverged
t refuse-head-not-local refuse_env nocommit "Release commit: REFUSED, $SHA is not in the local repo" STUB_NO_COMMIT=1
t refuse-gh-auth-failed refuse_env auth 'gh auth: REFUSED, gh auth status failed' STUB_AUTH_FAIL=1
t refuse-no-admin-for-master-leg refuse_env noadmin 'gh auth: REFUSED, no admin permission' STUB_PERMS=true_false
t refuse-latest-release-moved refuse_env latest "Latest release: REFUSED, latest is 'v1.13.5'" STUB_LATEST=v1.13.5
t refuse-release-branch-exists refuse_env branch 'Release branch: REFUSED, release/v1.13.4 exists on origin' STUB_REMOTE_BRANCH=1
t refuse-origin-is-another-repo refuse_env origin "Origin: REFUSED, git remote origin is 'https://github.com/someone/fork.git'" STUB_ORIGIN=https://github.com/someone/fork.git

# ---- --apply -------------------------------------------------------------------------------

EXPECTED_ALL="git tag v1.13.4 $SHA
git push origin refs/tags/v1.13.4:refs/tags/v1.13.4
gh release create v1.13.4 -R consolelabs/hidden --draft --verify-tag --title v1.13.4: fixture title --notes-file DIR/publish-notes.md
gh release upload v1.13.4 -R consolelabs/hidden DIR/Hidden-Bar-v1.13.4-macos.zip DIR/Hidden-Bar-macos.zip DIR/appcast.xml
gh release edit v1.13.4 -R consolelabs/hidden --draft=false --latest
git branch release/v1.13.4 refs/tags/v1.13.4
git push origin refs/heads/release/v1.13.4:refs/heads/release/v1.13.4
gh pr create -R consolelabs/hidden --base master --head release/v1.13.4 --title Release v1.13.4 to master --body Release merge: brings master to the v1.13.4 tag (4596656). Merged with a merge commit to keep master's release-merge history.
gh api -X PATCH repos/consolelabs/hidden -F allow_merge_commit=true --jq .allow_merge_commit
gh pr merge 600 -R consolelabs/hidden --merge --match-head-commit $SHA
gh api -X PATCH repos/consolelabs/hidden -F allow_merge_commit=false --jq .allow_merge_commit
git push origin --delete refs/heads/release/v1.13.4
git branch -d release/v1.13.4"

writes_match() { # fixture expected : the recorded writes equal the expected list (DIR = the release dir)
  local got want
  got="$(writes_of "$1")"; want="$(printf '%s\n' "$2" | sed "s#DIR#$1/build/release-1.13.4#g")"
  [ "$got" = "$want" ] && return 0
  echo "writes differ:"; /usr/bin/diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -6; return 1
}

happy_path() {
  local d o rc s; d="$(fixture happy)"
  o="$(pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "rc $rc: $(printf '%s' "$o" | grep -E 'FAILED|REFUSED' | head -2)"; return 1; }
  writes_match "$d" "$EXPECTED_ALL" || return 1
  for s in 1 2 3 4 5 6 7a 7b 7c 7d 7e 7f; do printf '%s' "$o" | grep -qE "^publish-release.sh: \[$s\] [^:]+(: [^:]+)?: ok, " || { echo "no result line for step $s"; return 1; }; done
  printf '%s' "$o" | grep -q 'allow_merge_commit is false (read back)' && [ "$(cat "$d.marks/amc")" = false ] || { echo "toggle not restored"; return 1; }
  grep -qx -- '- A fixture fix.' "$d/build/release-1.13.4/publish-notes.md" && ! grep -q '^## v' "$d/build/release-1.13.4/publish-notes.md" || { echo "notes file wrong"; return 1; }
  [ "$(grep -c '^curl ' "$d.marks/calls")" = 2 ] || { echo "expected 2 curl reads"; return 1; }
  grep -q 'published v1.13.4' "$d/build/release-1.13.4/publish.log" || { echo "publish.log lacks the result"; return 1; }
}
t apply-happy-path-runs-every-step-in-order happy_path

upload_fails() {
  local d o rc needle; d="$(fixture upfail)"
  o="$(EXTRA_ENV=STUB_FAIL=upload pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "rc $rc, expected 1"; return 1; }
  writes_match "$d" "$(printf '%s\n' "$EXPECTED_ALL" | head -4)" || return 1
  printf '%s' "$o" | grep -q '\[4\] upload: FAILED, exit 1 from gh release upload' || { echo "no failure line"; return 1; }
  printf '%s' "$o" | sed -n '/Done so far:/,/left to do by hand/p' | grep -qF "gh release create v1.13.4" || { echo "done list lacks the draft"; return 1; }
  for needle in "  [4] upload" "gh release upload v1.13.4" "  [5] publish" "gh release edit v1.13.4 -R consolelabs/hidden --draft=false --latest" "  [6] verify" "  [7d] master: merge" "gh pr merge '<pr-number>'"; do
    printf '%s' "$o" | sed -n '/left to do by hand/,$p' | grep -qF -- "$needle" || { echo "left list lacks: $needle"; return 1; }
  done
  ! grep -q '^gh release edit' "$d.marks/calls" || { echo "published after a failed upload"; return 1; }
}
t upload-failure-stops-before-publish-and-prints-the-rest upload_fails

merge_fails() {
  local d o rc; d="$(fixture mergefail)"
  o="$(EXTRA_ENV=STUB_FAIL=merge pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "rc $rc, expected 1"; return 1; }
  writes_match "$d" "$(printf '%s\n' "$EXPECTED_ALL" | head -11)" || return 1
  [ "$(cat "$d.marks/amc")" = false ] || { echo "allow_merge_commit left $(cat "$d.marks/amc")"; return 1; }
  printf '%s' "$o" | grep -q 'allow_merge_commit is false (read back)' && printf '%s' "$o" | grep -q '\[7d\] master: merge: FAILED' || { echo "no read-back or failure line"; return 1; }
  printf '%s' "$o" | sed -n '/left to do by hand/,$p' | grep -qF "gh pr merge 600 -R consolelabs/hidden --merge" || { echo "left list lacks the merge"; return 1; }
}
t merge-failure-restores-allow-merge-commit merge_fails

patch_lands_then_errors() { # the PATCH to true lands on GitHub but errors here: the trap flag is already set
  local d o rc; d="$(fixture patchland)"
  o="$(EXTRA_ENV=STUB_FAIL=patch-true-lands pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$d.marks/amc")" = false ] && ! grep -q '^gh pr merge' "$d.marks/calls" \
    && printf '%s' "$o" | grep -q 'allow_merge_commit is false (read back)' || { echo "rc $rc, amc $(cat "$d.marks/amc")"; return 1; }
}
t patch-error-after-landing-still-restores patch_lands_then_errors

restore_fails() { # the restore itself fails: exit 1, a warning with the manual command
  local d o rc; d="$(fixture restorefail)"
  o="$(EXTRA_ENV=STUB_FAIL=patch-false pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "WARNING: allow_merge_commit reads 'true', not false" \
    && printf '%s' "$o" | grep -qF "gh api -X PATCH repos/consolelabs/hidden -F allow_merge_commit=false" || { echo "rc $rc: $(printf '%s' "$o" | tail -2)"; return 1; }
}
t failed-restore-warns-and-exits-1 restore_fails

checks_fail() {
  local d o rc; d="$(fixture checksfail)"
  o="$(EXTRA_ENV=STUB_CHECKS=fail pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q '\[7c\] master: PR checks: FAILED, PR #600 checks: 1 fail, 1 pass' && ! grep -q -- '-X PATCH' "$d.marks/calls" \
    || { echo "rc $rc: $(printf '%s' "$o" | grep FAILED)"; return 1; }
}
t failing-pr-checks-stop-before-the-toggle checks_fail

no_checks() {
  local d o rc; d="$(fixture nochecks)"
  o="$(EXTRA_ENV=STUB_CHECKS=none pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q 'no checks reported on PR #600' && ! grep -q -- '-X PATCH' "$d.marks/calls" || { echo "rc $rc"; return 1; }
}
t no-pr-checks-stop-before-the-toggle no_checks

empty_checks() { # zero checks with exit 0 is not a pass
  local d o rc; d="$(fixture emptychecks)"
  o="$(EXTRA_ENV=STUB_CHECKS=empty pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q 'no checks reported on PR #600' && ! grep -q -- '-X PATCH' "$d.marks/calls" || { echo "rc $rc: $(printf '%s' "$o" | grep -E 'FAILED|7c' | head -1)"; return 1; }
}
t zero-pr-checks-stop-before-the-toggle empty_checks

signal_mid_merge() { # TERM during the merge with the log pipe gone: the EXIT trap alone restores the setting
  local d rc; d="$(fixture signal)"
  EXTRA_ENV=STUB_FAIL=signal pub "$d" --apply >/dev/null 2>&1; rc=$?
  [ -e "$d.marks/tee-killed" ] || { echo "the stub did not find the log pipe's tee"; return 1; }
  [ "$rc" != 0 ] && [ "$(cat "$d.marks/amc")" = false ] && [ "$(grep -c 'allow_merge_commit=false' "$d.marks/calls")" = 1 ] \
    || { echo "rc $rc, amc $(cat "$d.marks/amc"), restores $(grep -c 'allow_merge_commit=false' "$d.marks/calls")"; return 1; }
}
t term-mid-merge-trap-restores-allow-merge-commit signal_mid_merge

skip_master() {
  local d o rc; d="$(fixture skip)"
  o="$(pub "$d" --apply --skip-master 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "rc $rc"; return 1; }
  writes_match "$d" "$(printf '%s\n' "$EXPECTED_ALL" | head -5)" || return 1
  [ "$(grep -c '^curl ' "$d.marks/calls")" = 2 ] && printf '%s' "$o" | grep -q '\[6\] verify: ok' || { echo "verify did not run"; return 1; }
  ! grep -qE '^gh (pr|api -X)|release/' "$d.marks/calls" || { echo "master leg touched"; return 1; }
}
t skip-master-stops-after-verify skip_master

stale_feed() { # the live feed still serves the prior release: verify fails, the master leg is listed as left
  local d o rc; d="$(fixture stale)"
  appcast 1.13.3 24 > "$d.stale.xml"
  o="$(STUB_FEED="$d.stale.xml" pub "$d" --apply 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "\[6\] verify: FAILED, the live feed's first shortVersionString is '1.13.3'" \
    && printf '%s' "$o" | sed -n '/left to do by hand/,$p' | grep -q '\[7a\] master: release branch' && ! grep -q '^git -C [^ ]* branch' "$d.marks/calls" || { echo "rc $rc"; return 1; }
}
t verify-failure-stops-before-master stale_feed

stale_then_fresh() { # a cached old feed on the first read is retried, not a stop
  local d o rc; d="$(fixture stalefresh)"
  appcast 1.13.3 24 > "$d.stale.xml"
  o="$(STUB_STALE_ONCE="$d.stale.xml" pub "$d" --apply --skip-master 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -e "$d.marks/stale-served" ] && [ "$(grep -c '^curl ' "$d.marks/calls")" = 3 ] || { echo "rc $rc: $(printf '%s' "$o" | grep FAILED)"; return 1; }
}
t verify-retries-a-stale-200-read stale_then_fresh

# ---- structure -----------------------------------------------------------------------------

writes_only_via_mut() { # every git/gh write verb in the code sits behind act or mut
  local bad
  bad="$(grep -nE '(git -C "\$ROOT" (tag|push|branch)|gh (release (create|upload|edit|delete)|pr (create|merge)|api -X))' "$ROOT/scripts/publish-release.sh" \
    | grep -v '^[0-9]*:#' | grep -vE '(act "\$1"|act plan|mut|q) (git|gh) ')"
  [ -z "$bad" ] || { echo "write outside mut: $bad"; return 1; }
}
t no-write-bypasses-mut writes_only_via_mut
no_force() { ! grep -nE -- '--force|push -f|\+refs/|tag -d|tag -f|branch -D|release delete|--clobber|--delete-branch|--admin' "$ROOT/scripts/publish-release.sh"; }
t no-force-no-tag-or-release-deletion no_force
no_secret_shapes() { ! grep -nE '[A-Za-z0-9+/=]{64,}|gh[pousr]_[A-Za-z0-9]{20,}|op://|/Users/|scratchpad' "$ROOT/scripts/publish-release.sh"; }
t no-secret-or-home-paths-hardcoded no_secret_shapes

echo
echo "test-publish-release: $PASSED passed, $FAILED_N failed${FAILED_NAMES:+ (failed:$FAILED_NAMES)}"
[ "$FAILED_N" = 0 ]
