#!/usr/bin/env bash

# Shared helpers for the --release notes tests (release-notes.bats,
# notes-agent-builtin.bats, notes-agent-timeout.bats). Load after
# test_helper:
#
#   load 'test_helper'
#   load 'release_notes_helper'

# gh shim: `auth status` succeeds; every other call writes each argument to
# its own file under $GH_ARGV_DIR (1, 2, …) so multi-line notes survive
# intact, and it records in $GH_ARGV_DIR/env which provider keys are set,
# so a test can see VerBump's own environment after the notes agent ran.
# Prints the shim's directory; the caller prepends it to PATH and registers
# its cleanup, because a CLEANUP_CMDS entry made here is lost in the
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
printf 'ANTHROPIC_API_KEY=%s OPENAI_API_KEY=%s\n' \
  "${ANTHROPIC_API_KEY+set}" "${OPENAI_API_KEY+set}" > "${GH_ARGV_DIR}/env"
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

# Stub notes agent: records its PID, stdin, working directory and directory
# listing under $AGENT_REC, sleeps $AGENT_SLEEP seconds when set, then prints
# $AGENT_OUT and exits $AGENT_RC. A never-written $AGENT_REC/stdin means it
# was never invoked. With $AGENT_AWAIT_SLEEP=<n> it first waits (a bounded
# busy loop, so it starts no sleep of its own) until the shim has seen a
# `sleep <n>`: a fast agent would otherwise finish before VerBump's timer
# starts its sleep, and the test could not see which timeout it used. With
# $AGENT_CHILD_SLEEP=<n> it first starts a child that ignores TERM and sleeps
# <n> seconds, and records the child's PID in $AGENT_REC/child.
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
if [ -n "${AGENT_CHILD_SLEEP-}" ]; then
  ( trap '' TERM; exec sleep "$AGENT_CHILD_SLEEP" ) &
  echo "$!" > "${AGENT_REC}/child"
fi
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
