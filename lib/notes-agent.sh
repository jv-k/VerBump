#!/bin/bash

# shellcheck disable=SC2288
true

# Notes agent (ADR-24, R-REL-10..14): an external LLM command, named by the
# opt-in RELEASE_NOTES_AGENT key, that writes the --release notes. It is an
# improvement, never a requirement: every way it can fail ends in a warning
# and the notes the release publishes without one, never in a non-zero exit.
# This module builds the prompt and runs the command; resolve-release-notes
# (lib/git-actions.sh) decides when to call it and what to fall back to.

# Size limits, in lines, for the two context blocks that grow with the
# release: a long history must not make the agent run slow or overflow its
# context window. The changelog entry is not cut — it is one line per commit
# and is the agent's primary source.
_NOTES_COMMITS_MAX_LINES=400
_NOTES_DIFFSTAT_MAX_LINES=200

# The built-in prompt. RELEASE_NOTES_PROMPT appends to it; nothing replaces it.
_NOTES_AGENT_PROMPT="Write the GitHub release notes for this release, in Markdown, for the people who use this project.
Use only facts from the context below. Do not invent changes, and say nothing about a change the context does not show.
Keep every #N issue and pull request reference.
Do not add a title or a version heading.
Output only the notes body: no preamble, no closing remarks, no code fence around the whole answer."

# Copy stdin to stdout, keeping at most <max> lines. When it cuts, it ends
# with one marker line that says how many lines VerBump removed, so the agent
# knows the block is partial.
_notes-truncate() {
  awk -v max="$1" '
    NR <= max { print }
    END { if (NR > max) printf "[VerBump cut %d more lines from this block]\n", NR - max }
  '
}

# Print the full stdin text for the notes agent: the built-in prompt, then the
# RELEASE_NOTES_PROMPT guidance, then the context in delimited blocks — the
# changelog entry (render-release-notes, the same grouped rendering as the
# scoped fallback), the commit list (subject and body) and the diffstat. The
# range runs from the previous tag to the new one; with no previous tag it is
# the full history up to the new tag. Under a package scope every block covers
# only the scope.
build-notes-prompt() {
  local end from log_span diff_from
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")

  read -r end from <<< "$(release-notes-range)"
  if [ -n "$from" ]; then
    log_span="${from}..${end}"
    diff_from="$from"
  else
    # No previous tag: diff against the empty tree, i.e. the full history.
    log_span="$end"
    diff_from=$(git hash-object -t tree /dev/null)
  fi

  printf '%s\n' "$_NOTES_AGENT_PROMPT"
  if [ -n "${RELEASE_NOTES_PROMPT-}" ]; then
    printf '\nProject guidance from the maintainer:\n%s\n' "$RELEASE_NOTES_PROMPT"
  fi

  printf '\n<changelog-entry>\n%s\n</changelog-entry>\n' "$(render-release-notes)"
  # %w(0,4,4) indents each body under its subject, so commits stay apart.
  printf '\n<commits range="%s">\n%s\n</commits>\n' "$log_span" \
    "$(git log --format='%h %s%n%w(0,4,4)%b' "$log_span" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null \
       | _notes-truncate "$_NOTES_COMMITS_MAX_LINES")"
  # The per-file lines are cut; git's "N files changed" totals line (its
  # last line, re-read with --shortstat) always survives the cut.
  printf '\n<diffstat>\n%s\n%s\n</diffstat>\n' \
    "$(git diff --stat "$diff_from" "$end" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null \
       | sed '$d' | _notes-truncate "$_NOTES_DIFFSTAT_MAX_LINES")" \
    "$(git diff --shortstat "$diff_from" "$end" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null)"
}

# The timeout a RELEASE_NOTES_AGENT_TIMEOUT that is not a positive integer
# falls back to (R-REL-15).
_NOTES_AGENT_TIMEOUT_DEFAULT=120

# Watchdog state, global so the interrupt trap can reach it: the PIDs of the
# agent and the timer (each leads its own process group) and the run's
# temporary directories. Empty when no agent runs.
_NOTES_AGENT_PID=""
_NOTES_TIMER_PID=""
_NOTES_AGENT_TMP=()

# Set _NOTES_AGENT_TIMEOUT_S to RELEASE_NOTES_AGENT_TIMEOUT when it is a
# positive integer; otherwise warn and use the default. Leading zeros are
# stripped as text, not by arithmetic, so "08" is 8, not an octal error.
_notes-agent-timeout() {
  local value="${RELEASE_NOTES_AGENT_TIMEOUT-}" digits
  case "$value" in
    ''|*[!0-9]*) digits="" ;;
    *) digits="${value#"${value%%[!0]*}"}" ;;
  esac
  if [ -z "$digits" ]; then
    log_warn "RELEASE_NOTES_AGENT_TIMEOUT '${S_VAL-}${value}${RESET-}' is not a positive integer — using ${_NOTES_AGENT_TIMEOUT_DEFAULT} seconds."
    digits=$_NOTES_AGENT_TIMEOUT_DEFAULT
  fi
  _NOTES_AGENT_TIMEOUT_S=$digits
}

# Stop whatever the watchdog still has running and remove its temporary
# directories. Killing a process group is safe only while its leader is not
# yet reaped (a reaped PID can be reused), so the caller clears
# _NOTES_AGENT_PID once it has waited for the agent; the timer is always
# killed before it is waited for.
_notes-agent-cleanup() {
  if [ -n "$_NOTES_TIMER_PID" ]; then
    kill -TERM -- "-${_NOTES_TIMER_PID}" 2>/dev/null
    wait "$_NOTES_TIMER_PID" 2>/dev/null
  fi
  if [ -n "$_NOTES_AGENT_PID" ]; then
    kill -KILL -- "-${_NOTES_AGENT_PID}" 2>/dev/null
    wait "$_NOTES_AGENT_PID" 2>/dev/null
  fi
  [ "${#_NOTES_AGENT_TMP[@]}" -gt 0 ] && rm -rf "${_NOTES_AGENT_TMP[@]}"
  _NOTES_AGENT_PID="" _NOTES_TIMER_PID="" _NOTES_AGENT_TMP=()
}

# INT / TERM while the agent runs: the agent and the timer sit in their own
# process groups, so a Ctrl-C at the terminal never reaches them. Stop them,
# remove the temporary files, then die of the same signal so the exit status
# says so (the exit is the fallback if the signal was ignored at startup).
_notes-agent-interrupt() {
  _notes-agent-cleanup
  trap - INT TERM
  kill -s "$1" "$$"
  exit "$2"
}

# Run the notes agent <cmd> on the built prompt. The command is eval'd, like
# VERBUMP_RELEASE_NOTES_CMD, so a value such as 'gemini -p' or
# 'llm -m mymodel' splits into its arguments. It reads the prompt on stdin and
# runs in a fresh empty temporary directory, so it has no repo to read or
# change. Its stderr is discarded: an agent CLI's progress chatter is not run
# output. On success, sets NOTES_AGENT_OUTPUT and returns 0. On a non-zero
# exit, a timeout, or empty or whitespace-only output, sets NOTES_AGENT_ERROR
# to the cause and returns 1; the caller warns and falls back.
#
# Watchdog (R-REL-15): macOS has no coreutils `timeout`, so the agent runs in
# the background and a background timer stops it after
# RELEASE_NOTES_AGENT_TIMEOUT seconds — TERM, then KILL 2 s later for an
# agent that ignores TERM. Job control (set -m) starts each in its own
# process group, so one kill reaches every process the agent or the timer
# started (an agent CLI's children, the timer's sleep). The timer writes a
# marker before it kills, which is how a timeout is told apart from an agent
# that exits non-zero by itself. The timer, the agent and the temporary files
# are cleaned up on every path, an interrupt included.
# SC2034: NOTES_AGENT_ERROR is read by resolve-release-notes in another file.
# shellcheck disable=SC2034
run-notes-agent() {
  local cmd=$1 scratch workdir rc had_monitor=false saved_traps
  NOTES_AGENT_OUTPUT="" NOTES_AGENT_ERROR=""
  _notes-agent-timeout

  # Prompt and output live outside the agent's directory, so it starts empty.
  scratch=$(mktemp -d) || { NOTES_AGENT_ERROR="could not start (mktemp failed)"; return 1; }
  workdir=$(mktemp -d) || {
    rm -rf "$scratch"
    NOTES_AGENT_ERROR="could not start (mktemp failed)"
    return 1
  }
  _NOTES_AGENT_TMP=("$scratch" "$workdir")
  saved_traps=$(trap -p INT TERM)
  trap '_notes-agent-interrupt INT 130' INT
  trap '_notes-agent-interrupt TERM 143' TERM

  build-notes-prompt > "${scratch}/prompt"

  case $- in *m*) had_monitor=true ;; esac
  set -m
  ( cd "$workdir" && eval "$cmd" ) < "${scratch}/prompt" > "${scratch}/out" 2>/dev/null &
  _NOTES_AGENT_PID=$!
  ( sleep "$_NOTES_AGENT_TIMEOUT_S"
    : > "${scratch}/timed-out"
    kill -TERM -- "-${_NOTES_AGENT_PID}" 2>/dev/null
    sleep 2
    kill -KILL -- "-${_NOTES_AGENT_PID}" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  _NOTES_TIMER_PID=$!
  [ "$had_monitor" = true ] || set +m

  # stderr off: bash reports a job killed by a signal ("Terminated") here.
  wait "$_NOTES_AGENT_PID" 2>/dev/null
  rc=$?
  _NOTES_AGENT_PID=""
  NOTES_AGENT_OUTPUT=$(cat "${scratch}/out")
  if [ -f "${scratch}/timed-out" ]; then
    NOTES_AGENT_ERROR="timed out after ${_NOTES_AGENT_TIMEOUT_S}s (RELEASE_NOTES_AGENT_TIMEOUT)"
  fi
  _notes-agent-cleanup
  trap - INT TERM
  eval "$saved_traps"

  if [ -n "$NOTES_AGENT_ERROR" ]; then
    NOTES_AGENT_OUTPUT=""
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    NOTES_AGENT_ERROR="exited ${rc}"
    NOTES_AGENT_OUTPUT=""
    return 1
  fi
  if [ -z "${NOTES_AGENT_OUTPUT//[[:space:]]/}" ]; then
    NOTES_AGENT_ERROR="returned empty or whitespace-only output"
    NOTES_AGENT_OUTPUT=""
    return 1
  fi
  return 0
}
