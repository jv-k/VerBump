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
# intact. Prints the shim's directory; the caller prepends it to PATH and
# registers its cleanup, because a CLEANUP_CMDS entry made here is lost in the
# caller's $(...) subshell.
gh_argv_shim() {
  local shim
  shim=$(mktemp -d)
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
  CLEANUP_CMDS+=("rm -rf ${shim}")

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
  CLEANUP_CMDS+=("rm -rf ${shim}")

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

# ── Notes agent: a user-named command (#162, ADR-24) ─────────────────────────

# Stub notes agent: records its stdin, working directory and directory listing
# under $AGENT_REC, then prints $AGENT_OUT and exits $AGENT_RC. A never-written
# $AGENT_REC/stdin means it was never invoked.
agent_stub() {
  local shim=$1
  cat > "${shim}/notes-agent-stub" <<'SH'
#!/bin/sh
cat > "${AGENT_REC}/stdin"
pwd -P > "${AGENT_REC}/pwd"
ls -A > "${AGENT_REC}/ls"
printf '%s' "${AGENT_OUT-}"
exit "${AGENT_RC:-0}"
SH
  chmod +x "${shim}/notes-agent-stub"
}

# Set SHIM (a gh argv shim plus the agent stub, one PATH entry for both) and
# AGENT_REC (the stub's record directory) for the test body.
agent_tools() {
  SHIM=$(gh_argv_shim)
  CLEANUP_CMDS+=("rm -rf ${SHIM}")
  agent_stub "$SHIM"
  AGENT_REC=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${AGENT_REC}")
}

# releasable_repo plus a bare remote and agent_tools. Sets REMOTE too. The
# extra commit carries a body and a file, so the commit list and the diffstat
# have something to show.
agent_release_repo() {
  releasable_repo
  printf 'feature\n' > feature.txt
  git add feature.txt
  git commit -qm "feat: add the feature file" -m "Body line for the agent."
  REMOTE=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${REMOTE}")
  git init -q --bare "$REMOTE"
  agent_tools
}

# monorepo_fixture from inside packages/pkg-a, plus agent_tools. REMOTE is the
# fixture's origin.
agent_monorepo() {
  monorepo_fixture
  cd packages/pkg-a
  REMOTE=origin
  agent_tools
}

# `run` verbump with SHIM on PATH and the stub as RELEASE_NOTES_AGENT (unless
# the caller sets it). The stub's AGENT_OUT / AGENT_RC, RELEASE_NOTES_PROMPT
# and NOTES_CMD (the VERBUMP_RELEASE_NOTES_CMD to use, empty by default so the
# host's own setting can't leak in) come from the caller's VAR=… prefix.
run_with_agent() {
  PATH="${SHIM}:$PATH" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
    VERBUMP_RELEASE_NOTES_CMD="${NOTES_CMD-}" \
    RELEASE_NOTES_AGENT="${RELEASE_NOTES_AGENT-notes-agent-stub}" \
    run ${profile_script} "$@" </dev/null
}

# Line number of the first line of file $1 that contains the fixed string $2,
# or fail the test when no line does.
line_of() {
  local n
  n=$(grep -n -F -m1 -- "$2" "$1" | cut -d: -f1)
  [ -n "$n" ] || bats_fail "'$2' is not in $1"
  printf '%s' "$n"
}

assert_agent_not_run() {
  [ ! -f "${AGENT_REC}/stdin" ] || bats_fail "the notes agent ran"
}

@test "notes agent: publishes and prints the agent's notes (#162)" {
  agent_release_repo
  local notes=$'## Highlights\n\n- A feature file arrives (#12)'

  AGENT_OUT="$notes" run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  strip_ansi_output

  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes "$notes"
  assert_output --partial "notes agent 'notes-agent-stub'"
  assert_output --partial "- A feature file arrives (#12)"
}

@test "notes agent: stdin holds the prompt, the guidance, then the context for the range (#162)" {
  agent_release_repo
  local stdin_file="${AGENT_REC}/stdin"

  AGENT_OUT="NOTES" RELEASE_NOTES_PROMPT="GUIDANCE: group by user impact." \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success

  # The built-in prompt comes first, and asks for the agreed shape.
  run head -n1 "$stdin_file"
  assert_output --partial "Write the GitHub release notes"
  run cat "$stdin_file"
  assert_output --partial "Use only facts from the context"
  assert_output --partial "Keep every #N"
  assert_output --partial "Do not add a title or a version heading"
  assert_output --partial "Output only the notes body"

  # Order: prompt < guidance < changelog entry < commits < diffstat.
  [ "$(line_of "$stdin_file" "Write the GitHub release notes")" -lt "$(line_of "$stdin_file" "GUIDANCE: group by user impact.")" ] \
    || bats_fail "guidance precedes the built-in prompt"
  [ "$(line_of "$stdin_file" "GUIDANCE:")" -lt "$(line_of "$stdin_file" "<changelog-entry>")" ] \
    || bats_fail "context precedes the guidance"
  [ "$(line_of "$stdin_file" "<changelog-entry>")" -lt "$(line_of "$stdin_file" "<commits")" ] \
    || bats_fail "commits precede the changelog entry"
  [ "$(line_of "$stdin_file" "<commits")" -lt "$(line_of "$stdin_file" "<diffstat>")" ] \
    || bats_fail "diffstat precedes the commits"

  # Range v1.2.3..v1.3.0: the grouped changelog entry, subjects and bodies,
  # and the files changed with git's totals line — nothing from before the
  # previous tag.
  line_of "$stdin_file" "### Features" >/dev/null
  line_of "$stdin_file" '<commits range="v1.2.3..v1.3.0">' >/dev/null
  line_of "$stdin_file" "feat: add the feature file" >/dev/null
  line_of "$stdin_file" "Body line for the agent." >/dev/null
  line_of "$stdin_file" "feature.txt" >/dev/null
  line_of "$stdin_file" "files changed" >/dev/null
  run grep -c -F "bumped to 1.2.3" "$stdin_file"
  assert_output "0"
}

@test "notes agent: under a package scope the context leaves out other packages (#162)" {
  agent_monorepo

  AGENT_OUT="NOTES" run_with_agent --release -p "$REMOTE" -b -c -v 1.2.4
  assert_success

  line_of "${AGENT_REC}/stdin" "correct rounding" >/dev/null
  line_of "${AGENT_REC}/stdin" "rounding.txt" >/dev/null
  run grep -c -e "add widget" -e "widget.txt" "${AGENT_REC}/stdin"
  assert_output "0"
  assert_gh_argv "${SHIM}/argv" release create pkg-a-v1.2.4 --notes NOTES
}

@test "notes agent: with no previous tag the context covers the full history (#162)" {
  cd "$(scratch_repo)"
  printf '{ "version": "1.2.3" }\n' > package.json
  git add package.json && git commit -qm "feat: first package"
  REMOTE=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${REMOTE}")
  git init -q --bare "$REMOTE"
  agent_tools

  AGENT_OUT="NOTES" run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success

  line_of "${AGENT_REC}/stdin" '<commits range="v1.3.0">' >/dev/null
  line_of "${AGENT_REC}/stdin" "initial" >/dev/null
  line_of "${AGENT_REC}/stdin" "feat: first package" >/dev/null
  line_of "${AGENT_REC}/stdin" "package.json" >/dev/null
}

@test "notes agent: runs in an empty directory that is not the repo (#162)" {
  agent_release_repo
  local repo
  repo=$(pwd -P)

  AGENT_OUT="NOTES" run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success

  run cat "${AGENT_REC}/pwd"
  refute_output "$repo"
  refute_output --partial "${repo}/"
  run cat "${AGENT_REC}/ls"
  assert_output ""
}

@test "notes agent: a non-zero exit warns, publishes the fallback and exits 0 (#162)" {
  agent_release_repo

  AGENT_OUT="PARTIAL" AGENT_RC=3 run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent 'notes-agent-stub' exited 3"
  refute_output --partial "PARTIAL"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

@test "notes agent: empty or whitespace-only output warns and publishes the fallback (#162)" {
  agent_release_repo

  AGENT_OUT=$'  \n\t\n' run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent 'notes-agent-stub' returned empty or whitespace-only output"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

@test "notes agent: a failing agent under a package scope falls back to the changelog entry (#162)" {
  agent_monorepo

  AGENT_RC=1 run_with_agent --release -p "$REMOTE" -b -c -v 1.2.4
  assert_success

  source ${profile_script}
  load-config
  apply-config-defaults
  resolve-commit-scope
  V_PREV=1.2.3 V_NEW=1.2.4
  resolve-release-notes --fallback
  assert_equal "$RELEASE_NOTES_KIND" "changelog"
  assert_gh_argv "${SHIM}/argv" release create pkg-a-v1.2.4 --notes "$RELEASE_NOTES_TEXT"
}

# The same release, run once per RELEASE_NOTES_AGENT setting in a fresh repo
# with pinned git dates, so SHAs match and the outputs can be compared whole.
# Prints the run output with the temp paths replaced by placeholders. Redirect
# it to a file, never call it in $(...): the fixture's CLEANUP_CMDS entries
# would be lost in the subshell.
release_output_with_agent() {
  local mode=$1 out
  export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
  agent_release_repo
  if [ "$mode" = unset ]; then
    out=$(PATH="${SHIM}:$PATH" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
      VERBUMP_RELEASE_NOTES_CMD='' NO_COLOR=1 \
      env -u RELEASE_NOTES_AGENT ${profile_script} --release -p "$REMOTE" -b -c -v 1.3.0 2>&1 </dev/null)
  else
    out=$(PATH="${SHIM}:$PATH" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
      VERBUMP_RELEASE_NOTES_CMD='' NO_COLOR=1 RELEASE_NOTES_AGENT="$mode" \
      ${profile_script} --release -p "$REMOTE" -b -c -v 1.3.0 2>&1 </dev/null)
  fi
  assert_agent_not_run
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
  out="${out//"$REMOTE"/REMOTE}"
  printf '%s' "${out//"$(pwd -P)"/REPO}"
}

@test "notes agent: RELEASE_NOTES_AGENT=off and unset give the same output (#162)" {
  local unset_out off_out
  release_output_with_agent unset > "$BATS_TEST_TMPDIR/unset.out"
  release_output_with_agent off > "$BATS_TEST_TMPDIR/off.out"
  unset_out=$(cat "$BATS_TEST_TMPDIR/unset.out")
  off_out=$(cat "$BATS_TEST_TMPDIR/off.out")
  [ -n "$unset_out" ] || bats_fail "the unset run printed nothing"
  assert_equal "$off_out" "$unset_out"
  [[ "$off_out" != *"otes agent"* ]] || bats_fail "the off run mentions the notes agent"
}

@test "notes agent: VERBUMP_RELEASE_NOTES_CMD wins when both are set (#162)" {
  agent_release_repo

  AGENT_OUT="AGENT" NOTES_CMD='printf %s CUSTOM' \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success

  assert_agent_not_run
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes CUSTOM
}

@test "notes agent: with --quiet stdout holds only the version (#162)" {
  agent_release_repo

  PATH="${SHIM}:$PATH" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
    AGENT_OUT="QUIET-NOTES" VERBUMP_RELEASE_NOTES_CMD='' \
    RELEASE_NOTES_AGENT=notes-agent-stub \
    run bash -c '"$1" --quiet --release -p "$2" -b -c -v 1.3.0 >"$3/out" 2>"$3/err" </dev/null' _ \
      "${profile_script}" "$REMOTE" "$BATS_TEST_TMPDIR"
  assert_success

  printf '1.3.0\n' > "$BATS_TEST_TMPDIR/want"
  run cmp "$BATS_TEST_TMPDIR/out" "$BATS_TEST_TMPDIR/want"
  assert_success
  run grep -c -e "QUIET-NOTES" -e "notes agent 'notes-agent-stub'" "$BATS_TEST_TMPDIR/err"
  assert_output "2"
}

@test "notes agent: a failed push never invokes the agent (#162)" {
  agent_release_repo

  # 'nowhere' is no remote: the push fails, which ends the run with exit 1
  # before the release step (R-FLOW-8).
  AGENT_OUT="NOTES" run_with_agent --release -p nowhere -b -c -v 1.3.0
  assert_failure 1
  strip_ansi_output
  assert_output --partial "Push to <nowhere> failed"
  assert_agent_not_run
}

@test "notes agent: without --release the agent is never invoked (#162)" {
  agent_release_repo

  AGENT_OUT="NOTES" run_with_agent -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  assert_agent_not_run
}

@test "notes agent: --dry-run never invokes the agent (#162)" {
  agent_release_repo

  AGENT_OUT="NOTES" run_with_agent --release -d -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  assert_agent_not_run
}

@test "notes agent: a prerelease still passes --prerelease (#162)" {
  agent_release_repo

  AGENT_OUT="RC-NOTES" run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0-rc.1
  assert_success
  assert_gh_argv "${SHIM}/argv" release create v1.3.0-rc.1 --notes RC-NOTES --prerelease
}

@test "notes agent: the context size limit keeps the head and marks the cut (#162)" {
  run bash -c 'source "$1"; seq 1 10 | _notes-truncate 3' _ "${profile_script}"
  assert_success
  assert_output $'1\n2\n3\n[VerBump cut 7 more lines from this block]'

  run bash -c 'source "$1"; seq 1 3 | _notes-truncate 3' _ "${profile_script}"
  assert_success
  assert_output $'1\n2\n3'
}
