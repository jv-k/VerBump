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

# The default RELEASE_NOTES_AGENT_TIMEOUT, in seconds, and the value a
# timeout that is not a positive integer falls back to (R-REL-15). The one
# copy of the number: apply-config-defaults and the verbump.sh `:=` line
# read it too.
NOTES_AGENT_TIMEOUT_DEFAULT=120

# The timeout the current run uses, set by _resolve-notes-agent-timeout.
_NOTES_AGENT_TIMEOUT_S=""
# Watchdog state, global so the interrupt trap can reach it: the PID of the
# watchdog, which leads the process group that holds the agent and the
# timer, the run's temporary directories, and the caller's INT and TERM
# traps (`trap -p` output) to put back afterwards. Empty when no agent runs.
_NOTES_WATCHDOG_PID=""
_NOTES_AGENT_TMP=()
_NOTES_CALLER_TRAPS=""
# The run's scratch directory (prompt, output), outside the agent's own
# empty directory; the codex adapter writes its final message there.
_NOTES_AGENT_SCRATCH=""
# Set by pick-notes-agent: the command that runs the picked agent.
_NOTES_AGENT_CMD=""
# Set by pick-notes-agent: the agent that runs or was tried, for the lines
# that name it — the built-in agent auto picked, else RELEASE_NOTES_AGENT as
# given — and, for a built-in agent, the auth mode those lines name
# ("subscription" or "API key"; empty for a custom command).
NOTES_AGENT_NAME=""
NOTES_AGENT_AUTH=""

# Set _NOTES_AGENT_TIMEOUT_S to RELEASE_NOTES_AGENT_TIMEOUT when it is a
# positive integer; otherwise warn and use the default. Leading zeros are
# stripped as text, not by arithmetic, so "08" is 8, not an octal error.
_resolve-notes-agent-timeout() {
  local value="${RELEASE_NOTES_AGENT_TIMEOUT-}" seconds
  case "$value" in
    ''|*[!0-9]*) seconds="" ;;
    *) seconds="${value#"${value%%[!0]*}"}" ;;
  esac
  if [ -z "$seconds" ]; then
    log_warn "RELEASE_NOTES_AGENT_TIMEOUT '${S_VAL-}${value}${RESET-}' is not a positive integer — using ${NOTES_AGENT_TIMEOUT_DEFAULT} seconds."
    seconds=$NOTES_AGENT_TIMEOUT_DEFAULT
  fi
  _NOTES_AGENT_TIMEOUT_S=$seconds
}

# Stop whatever the watchdog still has running and remove its temporary
# directories. Killing a process group is safe only while its leader is not
# yet reaped (a reaped PID can be reused), so the caller clears
# _NOTES_WATCHDOG_PID once it has waited for the watchdog. This KILL, sent
# on an interrupt, is the one group signal sent from outside the group:
# bash reaps a child as soon as it exits, so a watchdog that ended a moment
# before the interrupt leaves a small window this does not close.
_notes-agent-cleanup() {
  if [ -n "$_NOTES_WATCHDOG_PID" ]; then
    kill -KILL -- "-${_NOTES_WATCHDOG_PID}" 2>/dev/null
    wait "$_NOTES_WATCHDOG_PID" 2>/dev/null
  fi
  [ "${#_NOTES_AGENT_TMP[@]}" -gt 0 ] && rm -rf "${_NOTES_AGENT_TMP[@]}"
  _NOTES_WATCHDOG_PID="" _NOTES_AGENT_TMP=() _NOTES_AGENT_SCRATCH=""
}

# Print the command of one `trap -p <signal>` line (empty for no trap). The
# line is shell-quoted by bash, so eval splits it exactly: after
# `set -- -- '<command>' SIG<name>`, $2 is the command.
_notes-trap-command() {
  eval "set -- ${1#trap }"
  printf '%s' "${2-}"
}

# End the watchdog's run: stop what it still has running, remove its
# temporary files, and put back the caller's INT and TERM traps.
_notes-agent-finish() {
  _notes-agent-cleanup
  trap - INT TERM
  eval "$_NOTES_CALLER_TRAPS"
  _NOTES_CALLER_TRAPS=""
}

# INT / TERM while the agent runs: the agent and the timer sit in their own
# process group, so a Ctrl-C at the terminal never reaches them. Finish the
# run, then run the caller's trap for this signal here, directly: bash 3.2
# does not run a trap for a signal raised inside another trap's handler, so
# re-signalling would skip it. The caller's trap runs with no positional
# parameters, inside this function. If it does not exit, die of the same
# signal so the exit status says so (the exit is the fallback if the signal
# is ignored).
_notes-agent-interrupt() {
  local sig=$1 code=$2 handler
  _notes-agent-finish
  handler=$(_notes-trap-command "$(trap -p "$sig")")
  set --
  [ -n "$handler" ] && eval "$handler"
  trap - "$sig"
  kill -s "$sig" "$$"
  exit "$code"
}

# ── Built-in notes agents (R-REL-16..19) ─────────────────────────────────────
# RELEASE_NOTES_AGENT=claude or =codex names a built-in agent: VerBump knows
# its flags, how to read its final message, and how to tell whether it bills
# a subscription or an API key. auto picks the first available one, claude
# then codex. Any other value is a custom command, run as-is with the
# caller's environment.

# The provider API key a built-in agent's CLI bills when it is set.
_notes-builtin-key-var() {
  case $1 in
    claude) printf 'ANTHROPIC_API_KEY' ;;
    codex)  printf 'OPENAI_API_KEY' ;;
  esac
}

# Succeed when <agent>'s login-status command reports a login. All of its
# output is discarded: claude's JSON is read only for its loggedIn field,
# codex's status only by its exit code, so no account email or org name can
# reach the run output.
_notes-builtin-logged-in() {
  case $1 in
    claude) claude auth status --json 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1 ;;
    codex)  codex login status >/dev/null 2>&1 ;;
  esac
}

# Decide how the built-in <agent> runs. The status check runs first with the
# provider key unset, in a subshell: a login then means a subscription, and
# the agent runs with the key unset in its own process only, so the
# subscription is billed, not the key. Otherwise a set key runs the agent
# with the key (CI). Sets NOTES_AGENT_AUTH to "subscription" or "API key"
# and _NOTES_AGENT_CMD to the command to eval; or, when the agent is not
# installed or has neither, sets NOTES_AGENT_ERROR and returns 1 (a warning
# and the fallback, never exit 3).
# SC2034: NOTES_AGENT_AUTH is read by do-github-release in another file.
# shellcheck disable=SC2034
_resolve-notes-builtin() {
  local agent=$1 key_var
  key_var=$(_notes-builtin-key-var "$agent")
  if ! command -v "$agent" >/dev/null 2>&1; then
    NOTES_AGENT_ERROR="is not installed (no '${agent}' on PATH)"
    return 1
  fi
  if ( unset "$key_var"; _notes-builtin-logged-in "$agent" ); then
    NOTES_AGENT_AUTH="subscription"
    _NOTES_AGENT_CMD="unset ${key_var}; _notes-agent-${agent}"
  elif [ -n "${!key_var-}" ]; then
    NOTES_AGENT_AUTH="API key"
    _NOTES_AGENT_CMD="_notes-agent-${agent}"
  else
    NOTES_AGENT_ERROR="is not logged in and ${key_var} is not set"
    return 1
  fi
}

# RELEASE_NOTES_AGENT=auto (R-REL-19): pick the first available built-in
# agent, claude then codex, by the rules of _resolve-notes-builtin. Sets
# NOTES_AGENT_NAME to it, with NOTES_AGENT_AUTH / _NOTES_AGENT_CMD as
# _resolve-notes-builtin left them; or returns 1 when neither is available.
# An unavailable agent is not an error here, so its NOTES_AGENT_ERROR is
# cleared. Only the pick moves on to codex: once an agent is picked, a
# failed run falls back to the notes without an agent, never to codex.
_resolve-notes-auto() {
  local agent
  for agent in claude codex; do
    if _resolve-notes-builtin "$agent"; then
      NOTES_AGENT_NAME=$agent
      return 0
    fi
    NOTES_AGENT_ERROR=""
  done
  return 1
}

# Pick the notes agent <agent> names, without running it: the first step of
# run-notes-agent, and all that a dry run does (ADR-24, R-REL-20). A built-in
# name (claude, codex) resolves as _resolve-notes-builtin decides, so its
# status check runs; auto picks as _resolve-notes-auto does; any other value
# is a custom command, picked as given and never checked. Sets
# NOTES_AGENT_NAME, NOTES_AGENT_AUTH and _NOTES_AGENT_CMD, and returns 0.
# When a built-in agent is not available, sets NOTES_AGENT_ERROR and returns
# 1; when auto finds no agent, returns 2 with no error.
# SC2034: NOTES_AGENT_ERROR, NOTES_AGENT_NAME and NOTES_AGENT_AUTH are read in
# lib/git-actions.sh.
# shellcheck disable=SC2034
pick-notes-agent() {
  local agent=$1
  NOTES_AGENT_ERROR="" NOTES_AGENT_NAME=$agent NOTES_AGENT_AUTH=""
  _NOTES_AGENT_CMD=$agent
  case $agent in
    auto) _resolve-notes-auto || return 2 ;;
    claude|codex) _resolve-notes-builtin "$agent" || return 1 ;;
  esac
}

# Run claude on the prompt (stdin): print mode, no built-in tools, no MCP
# servers (--strict-mcp-config with no --mcp-config), no saved session.
# Its stdout carries one JSON object per line next to anything else it
# prints, so only the result field of the "result" object is kept — the
# final message, never the progress.
_notes-agent-claude() {
  local out
  out=$(claude -p --output-format json --tools '' --strict-mcp-config \
    --no-session-persistence) || return
  printf '%s\n' "$out" \
    | jq -R -r 'fromjson? | select(type == "object" and .type == "result") | .result // empty'
}

# Run codex on the prompt (stdin): exec mode in a read-only sandbox, outside
# a git repo, with no shell or web-search tool, without the user's
# config.toml (so none of its MCP servers) and no saved session. codex
# writes its final message to the --output-last-message file; its stdout
# (progress, then that message again) is discarded.
_notes-agent-codex() {
  local last="${_NOTES_AGENT_SCRATCH}/codex-last-message"
  codex exec --sandbox read-only --skip-git-repo-check --ephemeral --ignore-user-config \
    --disable shell_tool -c 'web_search="disabled"' \
    --output-last-message "$last" - >/dev/null || return
  cat "$last"
}

# The watchdog: run in the background by run-notes-agent, as the leader of
# its own process group. It runs the agent <cmd> in <workdir> on
# <scratch>/prompt, writes the output to <scratch>/out and the exit status
# to <scratch>/rc. Its timer, also in the group, writes <scratch>/timed-out
# after RELEASE_NOTES_AGENT_TIMEOUT seconds, then sends TERM to the group,
# then KILL 2 s later for whatever ignored TERM. Every group signal is sent
# by a member of the group, from inside it: the group cannot end, and its
# ID be reused, while a member that sends to it is still alive. So the
# watchdog outlives the agent: it ignores the timer's TERM (bash runs the
# `:` trap only after the agent exits), and on a timeout it waits for the
# timer's KILL, so an agent's child that ignores TERM still gets the KILL.
# Otherwise it sends KILL to the group as soon as the agent exits, which
# stops the unused timer and any process the agent left behind. Either way
# the watchdog ends by that KILL.
_notes-agent-watchdog() {
  local cmd=$1 workdir=$2 scratch=$3
  set +m
  trap : TERM
  ( trap '' TERM
    sleep "$_NOTES_AGENT_TIMEOUT_S"
    : > "${scratch}/timed-out"
    kill -TERM 0
    sleep 2
    kill -KILL 0
  ) &
  ( cd "$workdir" && eval "$cmd" ) < "${scratch}/prompt" > "${scratch}/out"
  echo "$?" > "${scratch}/rc"
  [ -f "${scratch}/timed-out" ] && wait
  kill -KILL 0
}

# Pick the notes agent <cmd> with pick-notes-agent, then run it on the built
# prompt. A built-in name (claude, codex) runs that CLI as
# _resolve-notes-builtin decides, after an info line that names the agent and
# the auth mode; auto runs the one it picked. Any other value is eval'd, like
# VERBUMP_RELEASE_NOTES_CMD, so a value such as 'gemini -p' or
# 'llm -m mymodel' splits into its arguments. It reads the prompt on stdin and
# runs in a fresh empty temporary directory, so it has no repo to read or
# change. Its stderr is discarded: an agent CLI's progress chatter is not run
# output. On success, sets NOTES_AGENT_OUTPUT and returns 0. When a built-in
# agent cannot run, or on a non-zero exit, a timeout, or empty or
# whitespace-only output, sets NOTES_AGENT_ERROR to the cause and returns 1;
# the caller warns and falls back. When auto finds no agent, returns 2 with
# no error: that is not a failure, so the caller prints an info line, not a
# warning, and falls back (R-REL-19). NOTES_AGENT_NAME names the agent.
#
# Watchdog (R-REL-15): macOS has no coreutils `timeout`, so the agent runs
# under _notes-agent-watchdog, a background job that job control (set -m)
# starts in its own process group, with a timer that stops the agent after
# RELEASE_NOTES_AGENT_TIMEOUT seconds. The timer writes a marker before it
# kills, which is how a timeout is told apart from an agent that exits
# non-zero by itself. The timer, the agent and the temporary files are
# cleaned up on every path, an interrupt included.
# SC2034: NOTES_AGENT_ERROR is read by resolve-release-notes in another file.
# shellcheck disable=SC2034
run-notes-agent() {
  local cmd scratch workdir rc had_monitor=false
  NOTES_AGENT_OUTPUT=""

  # The pick comes before the timeout is read: when no agent is available,
  # nothing runs, so the run prints only the caller's info line or warning.
  pick-notes-agent "$1" || return
  _resolve-notes-agent-timeout
  [ -n "$NOTES_AGENT_AUTH" ] \
    && log_info "Notes agent: ${S_VAL-}${NOTES_AGENT_NAME}${RESET-} (${NOTES_AGENT_AUTH})"
  cmd=$_NOTES_AGENT_CMD

  # Prompt and output live outside the agent's directory, so it starts empty.
  scratch=$(mktemp -d) || { NOTES_AGENT_ERROR="could not start (mktemp failed)"; return 1; }
  workdir=$(mktemp -d) || {
    rm -rf "$scratch"
    NOTES_AGENT_ERROR="could not start (mktemp failed)"
    return 1
  }
  _NOTES_AGENT_TMP=("$scratch" "$workdir")
  _NOTES_AGENT_SCRATCH=$scratch
  _NOTES_CALLER_TRAPS=$(trap -p INT TERM)
  trap '_notes-agent-interrupt INT 130' INT
  trap '_notes-agent-interrupt TERM 143' TERM

  build-notes-prompt > "${scratch}/prompt"

  case $- in *m*) had_monitor=true ;; esac
  set -m
  _notes-agent-watchdog "$cmd" "$workdir" "$scratch" </dev/null >/dev/null 2>&1 &
  _NOTES_WATCHDOG_PID=$!
  [ "$had_monitor" = true ] || set +m

  # The watchdog ends only by a KILL to its whole group, so once it is
  # waited for, nothing the agent started in the group is left. stderr off:
  # bash reports a job killed by a signal ("Killed") here.
  wait "$_NOTES_WATCHDOG_PID" 2>/dev/null
  _NOTES_WATCHDOG_PID=""
  # No rc file: the timer's KILL stopped an agent that ignored TERM.
  rc=$(cat "${scratch}/rc" 2>/dev/null) || rc=137
  NOTES_AGENT_OUTPUT=$(cat "${scratch}/out")
  if [ -f "${scratch}/timed-out" ]; then
    NOTES_AGENT_ERROR="timed out after ${_NOTES_AGENT_TIMEOUT_S}s (RELEASE_NOTES_AGENT_TIMEOUT)"
  fi
  _notes-agent-finish

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
