#!/usr/bin/env bats

# Notes agent timeout (#163, ADR-24, R-REL-15): RELEASE_NOTES_AGENT_TIMEOUT
# caps the notes agent's run. A watchdog stops a hung agent and every
# process it started, the release publishes the fallback notes, and nothing
# is left behind, also when the run is interrupted. These tests run a live
# --release through the full CLI with the stub agent and a `sleep` shim
# from release_notes_helper, or call run-notes-agent from a caller script.

load 'test_helper'
load 'release_notes_helper'

# Fail unless every process the run started and recorded is gone: the stub
# agent, its child (when it started one) and every sleep the shim saw (the
# stub's own and VerBump's timer). A killed process can take a moment to be
# reaped, so poll for up to 2 s.
assert_no_agent_processes() {
  local pids pid tries
  pids=$(cat "${AGENT_REC}/pid" "${AGENT_REC}/child" 2>/dev/null
         cut -d' ' -f1 "${AGENT_REC}/sleeps" 2>/dev/null)
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

@test "notes agent: a timed-out agent's child that ignores TERM does not outlive the run (#163)" {
  local child
  agent_release_repo
  vb_tmpdir

  # The agent dies of the timeout's TERM; its child ignores TERM, so only
  # the KILL escalation can stop it.
  AGENT_SLEEP=30 AGENT_CHILD_SLEEP=40 RELEASE_NOTES_AGENT_TIMEOUT=1 TMPDIR="$VB_TMP" \
    run_with_agent --release -p "$REMOTE" -b -c -v 1.3.0
  child=$(cat "${AGENT_REC}/child" 2>/dev/null) || bats_fail "the stub started no child"
  CLEANUP_CMDS+=("kill -KILL ${child} 2>/dev/null || true")
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent 'notes-agent-stub' timed out after 1s (RELEASE_NOTES_AGENT_TIMEOUT)"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
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

# Wait until the background job <pid> has a hung agent (the stub's `sleep
# 30`) and the timer (`sleep 60`) running, send it <signal>, and wait for it
# to end. Sets SIGNAL_RC to its exit status.
signal_once_agent_runs() {
  local pid=$1 signal=$2 tries=0
  until grep -q -x "[0-9]* 30" "${AGENT_REC}/sleeps" 2>/dev/null \
     && grep -q -x "[0-9]* 60" "${AGENT_REC}/sleeps" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le 100 ] || { kill -KILL "$pid"; bats_fail "the agent and the timer never started"; }
    sleep 0.1
  done

  kill -s "$signal" "$pid"
  SIGNAL_RC=0
  wait "$pid" 2>/dev/null || SIGNAL_RC=$?
}

# Start VerBump as a background job with a hung agent and a 60 s timeout,
# send it <signal> once the agent and the timer are both running, and check
# that it dies of that signal (exit <code>) leaving no agent, timer or
# temporary file and no release. The job starts under job control (set -m):
# a non-interactive shell otherwise starts background jobs with SIGINT
# ignored, and a Ctrl-C could not be simulated.
assert_interrupt_cleans_up() {
  local signal=$1 code=$2 vb
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
  signal_once_agent_runs "$vb" "$signal"

  assert_equal "$SIGNAL_RC" "$code"
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

# Run run-notes-agent from a caller script that sources VerBump and sets its
# own <signal> trap, <handler>, then send the caller <signal> while the agent
# hangs. The caller runs under /bin/bash, the interpreter verbump.sh names,
# so on macOS this is bash 3.2. The handler runs with HANDLER_MARK set to a
# file it can write. Sets SIGNAL_RC to the caller's exit status.
interrupt_trapping_caller() {
  local signal=$1 handler=$2 caller="${BATS_TEST_TMPDIR}/caller.sh" pid
  agent_tools
  vb_tmpdir
  HANDLER_MARK="${BATS_TEST_TMPDIR}/handler-ran"
  cat > "$caller" <<'SH'
source "$1"
# The prompt's content does not matter here, and building it needs a release.
build-notes-prompt() { echo "prompt"; }
trap "$2" "$3"
run-notes-agent notes-agent-stub
echo "run-notes-agent returned"
SH

  set -m
  ( PATH="${SHIM}:$PATH" AGENT_REC="$AGENT_REC" HANDLER_MARK="$HANDLER_MARK" \
      AGENT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=60 TMPDIR="$VB_TMP" \
      exec /bin/bash "$caller" "$profile_script" "$handler" "$signal" \
      </dev/null >"${BATS_TEST_TMPDIR}/out" 2>&1 ) &
  pid=$!
  set +m
  signal_once_agent_runs "$pid" "$signal"

  assert_no_agent_processes
  assert_vb_tmpdir_empty
  run cat "${BATS_TEST_TMPDIR}/out"
  refute_output --partial "run-notes-agent returned"
}

@test "notes agent: Ctrl-C (SIGINT) runs the caller's INT trap, then ends the run with 130 (#163)" {
  interrupt_trapping_caller INT 'echo "INT handler ran" > "$HANDLER_MARK"'

  assert_equal "$SIGNAL_RC" 130
  run cat "$HANDLER_MARK"
  assert_output "INT handler ran"
}

@test "notes agent: SIGTERM runs the caller's TERM trap, which sets the exit status (#163)" {
  interrupt_trapping_caller TERM 'echo "TERM handler ran" > "$HANDLER_MARK"; exit 7'

  assert_equal "$SIGNAL_RC" 7
  run cat "$HANDLER_MARK"
  assert_output "TERM handler ran"
}

@test "notes agent: a fast run and a timed-out run put back the caller's INT and TERM traps (#163)" {
  agent_tools
  # Each run-notes-agent call prints the caller's traps after it returns.
  run env PATH="${SHIM}:$PATH" AGENT_REC="$AGENT_REC" AGENT_OUT="NOTES" \
    /bin/bash -c '
      source "$1"
      build-notes-prompt() { echo "prompt"; }
      trap "echo int" INT
      trap "echo term" TERM
      RELEASE_NOTES_AGENT_TIMEOUT=30 run-notes-agent notes-agent-stub
      echo "fast rc=$? $NOTES_AGENT_OUTPUT"; trap -p INT TERM
      AGENT_SLEEP=30 RELEASE_NOTES_AGENT_TIMEOUT=1 run-notes-agent notes-agent-stub
      echo "slow rc=$? $NOTES_AGENT_ERROR"; trap -p INT TERM
    ' _ "$profile_script" </dev/null
  assert_success
  assert_output "fast rc=0 NOTES
trap -- 'echo int' SIGINT
trap -- 'echo term' SIGTERM
slow rc=1 timed out after 1s (RELEASE_NOTES_AGENT_TIMEOUT)
trap -- 'echo int' SIGINT
trap -- 'echo term' SIGTERM"
  assert_no_agent_processes
}
