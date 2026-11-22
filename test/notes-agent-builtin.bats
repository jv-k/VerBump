#!/usr/bin/env bats

# Built-in notes agents (#164, ADR-24, R-REL-16..18): RELEASE_NOTES_AGENT=claude
# or =codex names a built-in agent. VerBump asks the CLI's login-status
# command with the provider key unset: a login means a subscription, and the
# agent runs with the key unset in its own process only. Otherwise a set key
# runs the agent with the key; otherwise the release falls back with a
# warning. These tests run a live --release through the full CLI with stub
# `claude` and `codex` executables on PATH. Each stub answers its status
# command as STUB_AUTH says (subscription, key or out) and records under
# AGENT_REC the flags it got, whether the provider key was set, and its stdin.

load 'test_helper'
load 'release_notes_helper'

# An account email and org name the stubs print with their status, so a test
# can show that VerBump never repeats them.
STUB_EMAIL="stub-account@example.com"
STUB_ORG="Stub Org Ltd"

# Write stub `claude` and `codex` executables into <dir>. A run (not a status
# check) writes its arguments one per line to $AGENT_REC/argv, "set" or
# nothing for its provider key to $AGENT_REC/key, and its stdin to
# $AGENT_REC/stdin. It prints progress on stdout and stderr, and its final
# message ($AGENT_OUT) the way the real CLI does: claude as the result field
# of its --output-format json object, codex to the --output-last-message
# file (and to stdout, like codex exec).
builtin_agent_stubs() {
  local dir=$1
  cat > "${dir}/claude" <<'SH'
#!/bin/sh
if [ "$1" = auth ] && [ "$2" = status ]; then
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY+set}" >> "${AGENT_REC}/status"
  logged=false method=none
  case "${STUB_AUTH-}" in
    subscription) logged=true method=claude.ai ;;
    key) [ -n "${ANTHROPIC_API_KEY-}" ] && logged=true method=api_key ;;
  esac
  printf '{"loggedIn":%s,"authMethod":"%s","email":"%s","orgName":"%s"}\n' \
    "$logged" "$method" "$STUB_EMAIL" "$STUB_ORG"
  echo "account ${STUB_EMAIL} (${STUB_ORG})" >&2
  [ "$logged" = true ]
  exit
fi
for a in "$@"; do printf '%s\n' "$a"; done > "${AGENT_REC}/argv"
printf '%s' "${ANTHROPIC_API_KEY+set}" > "${AGENT_REC}/key"
cat > "${AGENT_REC}/stdin"
echo "claude progress on stdout"
echo "claude progress on stderr" >&2
jq -cn --arg r "${AGENT_OUT-}" '{type:"result",subtype:"success",is_error:false,result:$r}'
exit "${AGENT_RC:-0}"
SH
  cat > "${dir}/codex" <<'SH'
#!/bin/sh
if [ "$1" = login ] && [ "$2" = status ]; then
  echo "OPENAI_API_KEY=${OPENAI_API_KEY+set}" >> "${AGENT_REC}/status"
  case "${STUB_AUTH-}" in
    subscription)
      echo "Logged in using ChatGPT (${STUB_EMAIL}, ${STUB_ORG})" >&2
      exit 0 ;;
    key)
      if [ -n "${OPENAI_API_KEY-}" ]; then
        echo "Logged in using an API key - sk-stub*** (${STUB_EMAIL})" >&2
        exit 0
      fi ;;
  esac
  echo "Not logged in" >&2
  exit 1
fi
for a in "$@"; do printf '%s\n' "$a"; done > "${AGENT_REC}/argv"
printf '%s' "${OPENAI_API_KEY+set}" > "${AGENT_REC}/key"
cat > "${AGENT_REC}/stdin"
last="" prev=""
for a in "$@"; do
  [ "$prev" = "--output-last-message" ] && last=$a
  prev=$a
done
echo "codex progress on stdout"
echo "codex progress on stderr" >&2
printf '%s\n' "${AGENT_OUT-}"
[ -n "$last" ] && printf '%s' "${AGENT_OUT-}" > "$last"
exit "${AGENT_RC:-0}"
SH
  chmod +x "${dir}/claude" "${dir}/codex"
}

# releasable_repo with an extra commit, a bare remote (REMOTE), the gh argv
# shim and the stubs (SHIM, one PATH entry for both) and AGENT_REC.
builtin_agent_repo() {
  releasable_repo
  printf 'feature\n' > feature.txt
  git add feature.txt
  git commit -qm "feat: add the feature file"
  REMOTE=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${REMOTE}")
  git init -q --bare "$REMOTE"
  SHIM=$(gh_argv_shim)
  CLEANUP_CMDS+=("rm -rf ${SHIM}")
  builtin_agent_stubs "$SHIM"
  AGENT_REC=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${AGENT_REC}")
}

# run_builtin <agent> [VAR=value …]: `run` a live --release with
# RELEASE_NOTES_AGENT=<agent>, both provider keys unset unless a VAR=value
# sets one, and STUB_AUTH / AGENT_OUT from the caller's prefix. VB_PATH
# replaces PATH when set (the not-installed case).
run_builtin() {
  local agent=$1
  shift
  run env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY \
    PATH="${VB_PATH:-${SHIM}:$PATH}" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
    STUB_AUTH="${STUB_AUTH-}" AGENT_OUT="${AGENT_OUT-}" \
    STUB_EMAIL="$STUB_EMAIL" STUB_ORG="$STUB_ORG" \
    VERBUMP_RELEASE_NOTES_CMD='' RELEASE_NOTES_AGENT="$agent" "$@" \
    "${profile_script}" --release -p "$REMOTE" -b -c -v 1.3.0 </dev/null
}

# Fail unless the stub's run (not its status check) got the flag <flag>,
# and, when given, <value> as the argument right after it.
assert_agent_flag() {
  local flag=$1
  grep -q -x -F -- "$flag" "${AGENT_REC}/argv" || bats_fail "the agent did not get ${flag}"
  if [ "$#" -ge 2 ]; then
    run grep -A1 -x -F -- "$flag" "${AGENT_REC}/argv"
    assert_output "$(printf '%s\n%s' "$flag" "$2")"
  fi
}

assert_no_account_details() {
  refute_output --partial "$STUB_EMAIL"
  refute_output --partial "$STUB_ORG"
}

@test "builtin agent: claude with a subscription runs without the API key the caller exported (#164)" {
  builtin_agent_repo
  local notes=$'## Highlights\n\n- A feature file arrives (#12)'

  STUB_AUTH=subscription AGENT_OUT="$notes" run_builtin claude ANTHROPIC_API_KEY=sk-caller
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: claude (subscription)"
  # The status check and the agent both ran without the key …
  run cat "${AGENT_REC}/status"
  assert_output "ANTHROPIC_API_KEY="
  run cat "${AGENT_REC}/key"
  assert_output ""
  # … and only the final message is published.
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes "$notes"
}

@test "builtin agent: codex with a subscription runs without the API key the caller exported (#164)" {
  builtin_agent_repo
  local notes=$'## Highlights\n\n- A feature file arrives (#12)'

  STUB_AUTH=subscription AGENT_OUT="$notes" run_builtin codex OPENAI_API_KEY=sk-caller
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: codex (subscription)"
  run cat "${AGENT_REC}/status"
  assert_output "OPENAI_API_KEY="
  run cat "${AGENT_REC}/key"
  assert_output ""
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes "$notes"
}

@test "builtin agent: claude runs non-interactively with no tools and no saved session (#164)" {
  builtin_agent_repo

  STUB_AUTH=subscription AGENT_OUT="NOTES" run_builtin claude
  assert_success

  assert_agent_flag -p
  assert_agent_flag --output-format json
  assert_agent_flag --tools ""
  assert_agent_flag --no-session-persistence
  grep -q -F "Write the GitHub release notes" "${AGENT_REC}/stdin" || bats_fail "claude did not get the built-in prompt"
}

@test "builtin agent: codex runs non-interactively in a read-only sandbox with no tools and no saved session (#164)" {
  builtin_agent_repo

  STUB_AUTH=subscription AGENT_OUT="NOTES" run_builtin codex
  assert_success

  run head -n1 "${AGENT_REC}/argv"
  assert_output "exec"
  assert_agent_flag --sandbox read-only
  assert_agent_flag --skip-git-repo-check
  assert_agent_flag --ephemeral
  assert_agent_flag --disable shell_tool
  assert_agent_flag -c 'web_search="disabled"'
  assert_agent_flag --output-last-message
  # The prompt comes on stdin ("-"), as the last argument.
  # (assert_output "-" would read the expected text from stdin.)
  assert_equal "$(tail -n1 "${AGENT_REC}/argv")" "-"
  grep -q -F "Write the GitHub release notes" "${AGENT_REC}/stdin" || bats_fail "codex did not get the built-in prompt"
}

@test "builtin agent: claude with only an API key runs with the key (#164)" {
  builtin_agent_repo

  STUB_AUTH=key AGENT_OUT="KEY-NOTES" run_builtin claude ANTHROPIC_API_KEY=sk-ci
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: claude (API key)"
  run cat "${AGENT_REC}/key"
  assert_output "set"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes KEY-NOTES
}

@test "builtin agent: codex with only an API key runs with the key (#164)" {
  builtin_agent_repo

  STUB_AUTH=key AGENT_OUT="KEY-NOTES" run_builtin codex OPENAI_API_KEY=sk-ci
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: codex (API key)"
  run cat "${AGENT_REC}/key"
  assert_output "set"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes KEY-NOTES
}

@test "builtin agent: claude logged out with no key warns, publishes the fallback and exits 0 (#164)" {
  builtin_agent_repo

  STUB_AUTH=out AGENT_OUT="NOTES" run_builtin claude
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent 'claude' is not logged in and ANTHROPIC_API_KEY is not set"
  refute_output --partial "Notes agent: claude"
  [ ! -f "${AGENT_REC}/argv" ] || bats_fail "the agent ran"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

@test "builtin agent: codex logged out with no key warns, publishes the fallback and exits 0 (#164)" {
  builtin_agent_repo

  STUB_AUTH=out AGENT_OUT="NOTES" run_builtin codex
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent 'codex' is not logged in and OPENAI_API_KEY is not set"
  [ ! -f "${AGENT_REC}/argv" ] || bats_fail "the agent ran"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
}

# Print a PATH with no `claude` or `codex` on it: SHIM (gh only, once the
# caller removed the stubs) then the current PATH, where every directory
# that holds a real claude or codex is replaced by a directory of links to
# its other entries.
path_without_agents() {
  local out="$SHIM" dir entry clean
  local IFS=:
  for dir in $PATH; do
    if [ -e "${dir}/claude" ] || [ -e "${dir}/codex" ]; then
      clean=$(mktemp -d "${BATS_TEST_TMPDIR}/path.XXXXXX")
      for entry in "$dir"/*; do
        case "${entry##*/}" in claude|codex) continue ;; esac
        ln -s "$entry" "${clean}/${entry##*/}"
      done
      dir=$clean
    fi
    out="${out}:${dir}"
  done
  printf '%s' "$out"
}

@test "builtin agent: a built-in agent that is not installed warns, publishes the fallback and exits 0, never 3 (#164)" {
  builtin_agent_repo
  rm "${SHIM}/claude" "${SHIM}/codex"
  local agent

  for agent in claude codex; do
    VB_PATH=$(path_without_agents) run_builtin "$agent" ANTHROPIC_API_KEY=sk-caller OPENAI_API_KEY=sk-caller
    assert_success
    strip_ansi_output
    assert_output --partial "Notes agent '${agent}' is not installed (no '${agent}' on PATH)"
    assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
    # The next agent cuts the same release again in a fresh repo.
    rm -f "${SHIM}/argv/"*
    cd "$repo_dir"
    builtin_agent_repo
    rm "${SHIM}/claude" "${SHIM}/codex"
  done
}

@test "builtin agent: progress on stdout or stderr never reaches the notes or the run output (#164)" {
  local agent
  for agent in claude codex; do
    builtin_agent_repo

    STUB_AUTH=subscription AGENT_OUT="FINAL" run_builtin "$agent"
    assert_success

    refute_output --partial "progress on stdout"
    refute_output --partial "progress on stderr"
    assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes FINAL
    cd "$repo_dir"
  done
}

@test "builtin agent: VerBump's own environment keeps the caller's keys after the agent ran (#164)" {
  local agent
  for agent in claude codex; do
    builtin_agent_repo

    STUB_AUTH=subscription AGENT_OUT="NOTES" \
      run_builtin "$agent" ANTHROPIC_API_KEY=sk-caller OPENAI_API_KEY=sk-caller
    assert_success

    # gh release create runs after the agent, in VerBump's own environment.
    run cat "${SHIM}/argv/env"
    assert_output "ANTHROPIC_API_KEY=set OPENAI_API_KEY=set"
    cd "$repo_dir"
  done
}

@test "builtin agent: no account email or org name appears in the output (#164)" {
  local agent auth
  for agent in claude codex; do
    for auth in subscription key out; do
      builtin_agent_repo

      STUB_AUTH=$auth AGENT_OUT="NOTES" \
        run_builtin "$agent" ANTHROPIC_API_KEY=sk-caller OPENAI_API_KEY=sk-caller
      assert_success
      assert_no_account_details
      cd "$repo_dir"
    done
  done
}

@test "builtin agent: a custom command keeps the caller's environment (#164)" {
  builtin_agent_repo

  # shellcheck disable=SC2016 # expanded by the agent's shell, not here
  STUB_AUTH=subscription \
    run_builtin 'printf "KEY=%s" "${ANTHROPIC_API_KEY-unset}"' ANTHROPIC_API_KEY=sk-caller
  assert_success
  strip_ansi_output

  refute_output --partial "Notes agent:"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes KEY=sk-caller
}
