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
  local tag_new="${TAG_PREFIX}${V_NEW}" tag_prev="${TAG_PREFIX}${V_PREV-}"
  local end log_span diff_from
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")

  # The agent runs after the push, so the new tag exists; HEAD keeps a direct
  # call (tests, a future preview) from failing when it does not.
  end="HEAD"
  git rev-parse --verify --quiet "refs/tags/${tag_new}" >/dev/null && end="$tag_new"
  if [ -n "${V_PREV-}" ] && git rev-parse --verify --quiet "refs/tags/${tag_prev}" >/dev/null; then
    log_span="${tag_prev}..${end}"
    diff_from="$tag_prev"
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
  printf '\n<diffstat>\n%s\n</diffstat>\n' \
    "$(git diff --stat "$diff_from" "$end" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null \
       | _notes-truncate "$_NOTES_DIFFSTAT_MAX_LINES")"
}

# Run the notes agent <cmd> on the built prompt. The command is eval'd, like
# VERBUMP_RELEASE_NOTES_CMD, so a value such as 'gemini -p' or
# 'llm -m mymodel' splits into its arguments. It reads the prompt on stdin and
# runs in a fresh empty temporary directory, so it has no repo to read or
# change. Its stderr is discarded: an agent CLI's progress chatter is not run
# output. On success, sets NOTES_AGENT_OUTPUT and returns 0. On a non-zero
# exit, or on empty or whitespace-only output, sets NOTES_AGENT_ERROR to the
# cause and returns 1; the caller warns and falls back.
# SC2034: NOTES_AGENT_ERROR is read by resolve-release-notes in another file.
# shellcheck disable=SC2034
run-notes-agent() {
  local cmd=$1 scratch workdir rc
  NOTES_AGENT_OUTPUT="" NOTES_AGENT_ERROR=""

  # Prompt and output live outside the agent's directory, so it starts empty.
  scratch=$(mktemp -d)
  workdir=$(mktemp -d)
  build-notes-prompt > "${scratch}/prompt"
  ( cd "$workdir" && eval "$cmd" ) < "${scratch}/prompt" > "${scratch}/out" 2>/dev/null
  rc=$?
  NOTES_AGENT_OUTPUT=$(cat "${scratch}/out")
  rm -rf "$scratch" "$workdir"

  if [ "$rc" -ne 0 ]; then
    NOTES_AGENT_ERROR="exited ${rc}"
    NOTES_AGENT_OUTPUT=""
    return 1
  fi
  if [ -z "${NOTES_AGENT_OUTPUT//[[:space:]]/}" ]; then
    NOTES_AGENT_ERROR="returned empty output"
    NOTES_AGENT_OUTPUT=""
    return 1
  fi
  return 0
}
