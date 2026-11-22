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

# Stub notes agent: records its PID, stdin, working directory and directory
# listing under $AGENT_REC, sleeps $AGENT_SLEEP seconds when set, then prints
# $AGENT_OUT and exits $AGENT_RC. A never-written $AGENT_REC/stdin means it
# was never invoked. With $AGENT_AWAIT_SLEEP=<n> it first waits (a bounded
# busy loop, so it starts no sleep of its own) until the shim has seen a
# `sleep <n>`: a fast agent would otherwise finish before VerBump's timer
# starts its sleep, and the test could not see which timeout it used.
# Beside it, a `sleep` shim that appends "<pid> <seconds>" to
# $AGENT_REC/sleeps and then execs the real sleep under the same PID, so a
# test can find every sleep the run started (the stub's and VerBump's timer)
# and check that none is left alive.
agent_stub() {
  local shim=$1 real_sleep
  real_sleep=$(command -v sleep)
  cat > "${shim}/notes-agent-stub" <<'SH'
#!/bin/sh
echo "$$" > "${AGENT_REC}/pid"
cat > "${AGENT_REC}/stdin"
pwd -P > "${AGENT_REC}/pwd"
ls -A > "${AGENT_REC}/ls"
if [ -n "${AGENT_AWAIT_SLEEP-}" ]; then
  i=0
  until grep -q -x "[0-9]* ${AGENT_AWAIT_SLEEP}" "${AGENT_REC}/sleeps" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 5000 ] && break
  done
fi
[ -n "${AGENT_SLEEP-}" ] && sleep "$AGENT_SLEEP"
printf '%s' "${AGENT_OUT-}"
exit "${AGENT_RC:-0}"
SH
  chmod +x "${shim}/notes-agent-stub"
  cat > "${shim}/sleep" <<SH
#!/bin/sh
[ -n "\${AGENT_REC-}" ] && echo "\$\$ \$*" >> "\${AGENT_REC}/sleeps"
exec "${real_sleep}" "\$@"
SH
  chmod +x "${shim}/sleep"
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

  # 'nowhere' is no remote: the push fails (non-fatal) and the release is
  # skipped, so the run still exits 0.
  AGENT_OUT="NOTES" run_with_agent --release -p nowhere -b -c -v 1.3.0
  assert_success
  strip_ansi_output
  assert_output --partial "Skipping GitHub release"
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

# ── Notes agent timeout (#163, ADR-24) ───────────────────────────────────────

# Fail unless every process the run started and recorded is gone: the stub
# agent and every sleep the shim saw (the stub's own and VerBump's timer).
# A killed process can take a moment to be reaped, so poll for up to 2 s.
assert_no_agent_processes() {
  local pids pid tries
  pids=$(cat "${AGENT_REC}/pid" 2>/dev/null; cut -d' ' -f1 "${AGENT_REC}/sleeps" 2>/dev/null)
  for pid in $pids; do
    tries=0
    while kill -0 "$pid" 2>/dev/null; do
      tries=$((tries + 1))
      [ "$tries" -le 20 ] || bats_fail "process ${pid} is still running after the run"
      sleep 0.1
    done
  done
}

# A fresh, empty TMPDIR for the VerBump run, so the test can show that the
# notes agent leaves no temporary file behind. Sets VB_TMP.
vb_tmpdir() {
  VB_TMP="${BATS_TEST_TMPDIR}/vb-tmp"
  mkdir -p "$VB_TMP"
}

assert_vb_tmpdir_empty() {
  run ls -A "$VB_TMP"
  assert_output ""
}

# Fail unless the sleep shim saw exactly one `sleep <seconds>` in the run.
assert_slept_once() {
  run grep -c -x "[0-9]* $1" "${AGENT_REC}/sleeps"
  assert_output "1"
}

@test "notes agent: a hung agent is stopped after RELEASE_NOTES_AGENT_TIMEOUT and the fallback is published (#163)" {
  agent_release_repo
  vb_tmpdir
  local start=$SECONDS

  AGENT_OUT="LATE" AGENT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=1 TMPDIR="$VB_TMP" \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  [ $((SECONDS - start)) -lt 10 ] || bats_fail "the run took $((SECONDS - start)) s"
  strip_ansi_output

  assert_output --partial "Notes agent 'notes-agent-stub' timed out after 1s (RELEASE_NOTES_AGENT_TIMEOUT)"
  refute_output --partial "LATE"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

@test "notes agent: a timed-out run leaves no agent, timer or temporary file behind (#163)" {
  agent_release_repo
  vb_tmpdir

  AGENT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=1 TMPDIR="$VB_TMP" \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success

  # The timer slept the configured timeout, and the stub's sleep was seen too.
  assert_slept_once 1
  assert_slept_once 30
  assert_no_agent_processes
  assert_vb_tmpdir_empty
}

@test "notes agent: a fast agent is not affected by the timeout and leaves nothing behind (#163)" {
  agent_release_repo
  vb_tmpdir
  local start=$SECONDS

  AGENT_OUT="FAST-NOTES" AGENT_AWAIT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=30 TMPDIR="$VB_TMP" \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  [ $((SECONDS - start)) -lt 10 ] || bats_fail "the run waited for the timer"
  strip_ansi_output

  refute_output --partial "timed out"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes FAST-NOTES
  assert_slept_once 30
  assert_no_agent_processes
  assert_vb_tmpdir_empty
}

# Run a fast agent with RELEASE_NOTES_AGENT_TIMEOUT=<value> and check the
# warning, that the timer used the 120 s default, and that the notes publish.
assert_invalid_timeout_uses_default() {
  local value=$1
  agent_release_repo

  AGENT_OUT="NOTES" AGENT_AWAIT_SLEEP=120 RELEASE_NOTES_AGENT_TIMEOUT="$value" \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  strip_ansi_output

  assert_output --partial "RELEASE_NOTES_AGENT_TIMEOUT '${value}' is not a positive integer — using 120 seconds"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes NOTES
  assert_slept_once 120
  assert_no_agent_processes
}

@test "notes agent: RELEASE_NOTES_AGENT_TIMEOUT=abc warns and uses 120 (#163)" {
  assert_invalid_timeout_uses_default abc
}

@test "notes agent: RELEASE_NOTES_AGENT_TIMEOUT=0 warns and uses 120 (#163)" {
  assert_invalid_timeout_uses_default 0
}

@test "notes agent: RELEASE_NOTES_AGENT_TIMEOUT=-5 warns and uses 120 (#163)" {
  assert_invalid_timeout_uses_default -5
}

@test "notes agent: a valid timeout prints no timeout warning (#163)" {
  agent_release_repo

  AGENT_OUT="NOTES" RELEASE_NOTES_AGENT_TIMEOUT=45 \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  assert_success
  strip_ansi_output

  refute_output --partial "RELEASE_NOTES_AGENT_TIMEOUT"
}

# Start VerBump as a background job with a hung agent and a 60 s timeout,
# send it <signal> once the agent and the timer are both running, and check
# that it dies of that signal (exit <code>) leaving no agent, timer or
# temporary file and no release. The job starts under job control (set -m):
# a non-interactive shell otherwise starts background jobs with SIGINT
# ignored, and a Ctrl-C could not be simulated.
assert_interrupt_cleans_up() {
  local signal=$1 code=$2 vb rc tries=0
  agent_release_repo
  vb_tmpdir

  set -m
  ( PATH="${SHIM}:$PATH" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
      VERBUMP_RELEASE_NOTES_CMD='' RELEASE_NOTES_AGENT=notes-agent-stub \
      AGENT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=60 TMPDIR="$VB_TMP" \
      exec ${profile_script} --release -p "$REMOTE" -b -c -v 1.3.0 \
      </dev/null >"${BATS_TEST_TMPDIR}/out" 2>&1 ) &
  vb=$!
  set +m
  until grep -q -x "[0-9]* 30" "${AGENT_REC}/sleeps" 2>/dev/null \
     && grep -q -x "[0-9]* 60" "${AGENT_REC}/sleeps" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le 100 ] || { kill -KILL "$vb"; bats_fail "the agent and the timer never started"; }
    sleep 0.1
  done

  kill -s "$signal" "$vb"
  rc=0
  wait "$vb" 2>/dev/null || rc=$?

  assert_equal "$rc" "$code"
  [ ! -f "${SHIM}/argv/1" ] || bats_fail "an interrupted run published a release"
  assert_no_agent_processes
  assert_vb_tmpdir_empty
}

@test "notes agent: Ctrl-C (SIGINT) stops the agent and the timer and removes the temporary files (#163)" {
  assert_interrupt_cleans_up INT 130
}

@test "notes agent: SIGTERM stops the agent and the timer and removes the temporary files (#163)" {
  assert_interrupt_cleans_up TERM 143
}
