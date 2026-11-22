#!/usr/bin/env bats

# Release notes source (#161, ADR-24): the --release publish step picks its
# notes in one place, resolve-release-notes. Its --fallback mode returns the
# notes a release publishes without a notes agent — gh --generate-notes with
# --notes-start-tag at whole-repo scope, the package's changelog entry under
# a package scope — so a later notes-agent branch can fall back to it. These
# tests run a live --release through the full CLI with a gh shim that records
# its argv, then resolve the fallback in the same repo and compare.

load 'test_helper'

# gh shim: `auth status` succeeds; every other call writes each argument to
# its own file under $GH_ARGV_DIR (1, 2, …) so multi-line notes survive
# intact. Prints the shim's directory; the caller prepends it to PATH.
gh_argv_shim() {
  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  mkdir -p "${shim}/argv"
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 0
i=0
for a in "$@"; do
  i=$((i + 1))
  printf '%s' "$a" > "${GH_ARGV_DIR}/${i}"
done
echo "https://github.com/acme/repo/releases/tag/shim"
exit 0
SH
  chmod +x "${shim}/gh"
  printf '%s' "$shim"
}

# Assert the argv the gh shim recorded equals the arguments given, one by one.
assert_gh_argv() {
  local dir="$1" i=0 want got
  shift
  for want in "$@"; do
    i=$((i + 1))
    [ -f "${dir}/${i}" ] || bats_fail "gh argv has no argument ${i} (wanted '${want}')"
    got=$(cat "${dir}/${i}"; printf x)
    got="${got%x}"
    assert_equal "$got" "$want"
  done
  [ ! -f "${dir}/$((i + 1))" ] || bats_fail "gh argv has more than ${i} arguments"
}

@test "release notes: fallback matches what a live --release publishes at whole-repo scope (#161)" {
  local remote shim
  releasable_repo
  remote=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "$remote"
  shim=$(gh_argv_shim)

  PATH="${shim}:$PATH" GH_ARGV_DIR="${shim}/argv" VERBUMP_RELEASE_NOTES_CMD='' \
    run ${profile_script} --release -p "$remote" -b -c -v 1.3.0 </dev/null
  assert_success

  source ${profile_script}
  TAG_PREFIX=v V_PREV=1.2.3 V_NEW=1.3.0
  resolve-release-notes --fallback

  assert_equal "$RELEASE_NOTES_KIND" "generated"
  assert_gh_argv "${shim}/argv" release create v1.3.0 "${RELEASE_NOTES_ARGS[@]}"
  assert_gh_argv "${shim}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

@test "release notes: fallback matches what a live --release publishes under a package scope (#161)" {
  local shim
  monorepo_fixture
  cd packages/pkg-a
  shim=$(gh_argv_shim)

  PATH="${shim}:$PATH" GH_ARGV_DIR="${shim}/argv" VERBUMP_RELEASE_NOTES_CMD='' \
    run ${profile_script} --release -p origin -b -c -v 1.2.4 </dev/null
  assert_success

  source ${profile_script}
  load-config
  apply-config-defaults
  resolve-commit-scope
  V_PREV=1.2.3 V_NEW=1.2.4
  resolve-release-notes --fallback

  assert_equal "$RELEASE_NOTES_KIND" "changelog"
  # The scoped entry, not a vacuous match: pkg-a's fix, never pkg-b's feat.
  [[ "$RELEASE_NOTES_TEXT" == *"correct rounding"* ]] || bats_fail "notes miss pkg-a's fix"
  [[ "$RELEASE_NOTES_TEXT" != *"add widget"* ]] || bats_fail "notes leak pkg-b's feat"
  assert_gh_argv "${shim}/argv" release create pkg-a-v1.2.4 --notes "$RELEASE_NOTES_TEXT"
}

@test "release notes: fallback ignores VERBUMP_RELEASE_NOTES_CMD (#161)" {
  source ${profile_script}
  releasable_repo

  TAG_PREFIX=v V_PREV=1.2.3 V_NEW=1.3.0 VERBUMP_RELEASE_NOTES_CMD='echo CUSTOM'
  resolve-release-notes --fallback

  assert_equal "$RELEASE_NOTES_KIND" "generated"
  assert_equal "$RELEASE_NOTES_TEXT" ""
  assert_equal "${RELEASE_NOTES_ARGS[*]}" "--generate-notes --notes-start-tag v1.2.3"
}

@test "release notes: a custom VERBUMP_RELEASE_NOTES_CMD wins without --fallback (#161)" {
  source ${profile_script}
  releasable_repo

  TAG_PREFIX=v V_PREV=1.2.3 V_NEW=1.3.0 VERBUMP_RELEASE_NOTES_CMD='printf %s CUSTOM'
  resolve-release-notes

  assert_equal "$RELEASE_NOTES_KIND" "command"
  assert_equal "$RELEASE_NOTES_TEXT" "CUSTOM"
  assert_equal "${RELEASE_NOTES_ARGS[*]}" "--notes CUSTOM"
}

@test "release notes: fallback without a previous tag omits --notes-start-tag (#161)" {
  source ${profile_script}
  releasable_repo

  TAG_PREFIX=v V_PREV=9.9.9 V_NEW=10.0.0 VERBUMP_RELEASE_NOTES_CMD=''
  resolve-release-notes --fallback

  assert_equal "$RELEASE_NOTES_KIND" "generated"
  assert_equal "${RELEASE_NOTES_ARGS[*]}" "--generate-notes"
}
