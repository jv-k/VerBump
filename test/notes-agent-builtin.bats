#!/usr/bin/env bats

# Built-in notes agents (#164, ADR-24, R-REL-16..18): RELEASE_NOTES_AGENT=claude
# or =codex names a built-in agent. VerBump asks the CLI's login-status
# command with the provider key unset: a login means a subscription, and the
# agent runs with the key unset in its own process only. Otherwise a set key
# runs the agent with the key; otherwise the release falls back with a
# warning. These tests run a live --release through the full CLI with stub
# `claude` and `codex` executables on PATH. Each stub answers its status
# command as STUB_AUTH says (subscription, key or out), or as STUB_AUTH_CLAUDE
# / STUB_AUTH_CODEX says for that agent alone, and records under AGENT_REC
# the flags it got, whether the provider key was set, and its stdin.

load 'test_helper'
load 'release_notes_helper'

# run --separate-stderr (the --json tests) needs bats 1.5.
bats_require_minimum_version 1.5.0

# An account email and org name the stubs print with their status, so a test
# can show that VerBump never repeats them.
STUB_EMAIL="stub-account@example.com"
STUB_ORG="Stub Org Ltd"

# Write stub `claude` and `codex` executables into <dir>. A run (not a status
# check) appends its name to $AGENT_REC/ran, writes its arguments one per
# line to $AGENT_REC/argv, "set" or nothing for its provider key to
# $AGENT_REC/key, and its stdin to $AGENT_REC/stdin. It prints progress on
# stdout and stderr, and its final message ($AGENT_OUT) the way the real CLI
# does: claude as the result field of its --output-format json object, codex
# to the --output-last-message file (and to stdout, like codex exec).
builtin_agent_stubs() {
  local dir=$1
  cat > "${dir}/claude" <<'SH'
#!/bin/sh
if [ "$1" = auth ] && [ "$2" = status ]; then
  echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY+set}" >> "${AGENT_REC}/status"
  logged=false method=none
  case "${STUB_AUTH_CLAUDE-${STUB_AUTH-}}" in
    subscription) logged=true method=claude.ai ;;
    key) [ -n "${ANTHROPIC_API_KEY-}" ] && logged=true method=api_key ;;
  esac
  printf '{"loggedIn":%s,"authMethod":"%s","email":"%s","orgName":"%s"}\n' \
    "$logged" "$method" "$STUB_EMAIL" "$STUB_ORG"
  echo "account ${STUB_EMAIL} (${STUB_ORG})" >&2
  [ "$logged" = true ]
  exit
fi
echo claude >> "${AGENT_REC}/ran"
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
  case "${STUB_AUTH_CODEX-${STUB_AUTH-}}" in
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
echo codex >> "${AGENT_REC}/ran"
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
  # One "version" line, so the bump makes no unrelated warning and a test
  # can assert that a run prints no warning at all.
  printf '{\n  "version": "1.2.3"\n}\n' > package.json
  git commit -qam "chore: format package.json"
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
# sets one, and STUB_AUTH / STUB_AUTH_CLAUDE / STUB_AUTH_CODEX / AGENT_OUT /
# AGENT_RC from the caller's prefix (an unset per-agent auth stays unset, so
# the stub falls back to STUB_AUTH). VB_PATH replaces PATH when set (the
# not-installed case). RUN_FLAGS (an array) adds VerBump flags, such as -d;
# with RUN_SEPARATE set, stdout and stderr land in $output and $stderr.
run_builtin() {
  local agent=$1
  shift
  run ${RUN_SEPARATE:+--separate-stderr} env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY \
    PATH="${VB_PATH:-${SHIM}:$PATH}" GH_ARGV_DIR="${SHIM}/argv" AGENT_REC="$AGENT_REC" \
    STUB_AUTH="${STUB_AUTH-}" ${STUB_AUTH_CLAUDE+STUB_AUTH_CLAUDE="$STUB_AUTH_CLAUDE"} \
    ${STUB_AUTH_CODEX+STUB_AUTH_CODEX="$STUB_AUTH_CODEX"} \
    AGENT_OUT="${AGENT_OUT-}" AGENT_RC="${AGENT_RC:-0}" \
    STUB_EMAIL="$STUB_EMAIL" STUB_ORG="$STUB_ORG" \
    VERBUMP_RELEASE_NOTES_CMD='' RELEASE_NOTES_AGENT="$agent" "$@" \
    "${profile_script}" --release -p "$REMOTE" -b -c -v 1.3.0 \
    ${RUN_FLAGS[@]+"${RUN_FLAGS[@]}"} </dev/null
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

@test "builtin agent: claude runs non-interactively with no tools, no MCP servers and no saved session (#164)" {
  builtin_agent_repo

  STUB_AUTH=subscription AGENT_OUT="NOTES" run_builtin claude
  assert_success

  assert_agent_flag -p
  assert_agent_flag --output-format json
  assert_agent_flag --tools ""
  assert_agent_flag --no-session-persistence
  assert_agent_flag --strict-mcp-config
  grep -q -F "Write the GitHub release notes" "${AGENT_REC}/stdin" || bats_fail "claude did not get the built-in prompt"
}

@test "builtin agent: codex runs non-interactively in a read-only sandbox with no tools, no user config and no saved session (#164)" {
  builtin_agent_repo

  STUB_AUTH=subscription AGENT_OUT="NOTES" run_builtin codex
  assert_success

  run head -n1 "${AGENT_REC}/argv"
  assert_output "exec"
  assert_agent_flag --sandbox read-only
  assert_agent_flag --skip-git-repo-check
  assert_agent_flag --ephemeral
  assert_agent_flag --ignore-user-config
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
  local agent

  # Each agent cuts the same release in a fresh repo.
  for agent in claude codex; do
    builtin_agent_repo
    rm "${SHIM}/claude" "${SHIM}/codex"

    VB_PATH=$(path_without_agents) run_builtin "$agent" ANTHROPIC_API_KEY=sk-caller OPENAI_API_KEY=sk-caller
    assert_success
    strip_ansi_output
    assert_output --partial "Notes agent '${agent}' is not installed (no '${agent}' on PATH)"
    assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
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

# ── RELEASE_NOTES_AGENT=auto (#165, R-REL-19) ───────────────────────────────
# auto tries claude, then codex, with the availability rules above; the
# first available agent writes the notes. $AGENT_REC/ran names every agent
# that ran (a status check is not a run).

@test "auto agent: with claude and codex both logged in, claude writes the notes (#165)" {
  builtin_agent_repo

  STUB_AUTH=subscription AGENT_OUT="AUTO-NOTES" run_builtin auto
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: claude (subscription)"
  assert_output --partial "Release notes written by notes agent 'claude':"
  run cat "${AGENT_REC}/ran"
  assert_output "claude"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes AUTO-NOTES
}

@test "auto agent: with claude logged out and codex logged in, codex writes the notes (#165)" {
  builtin_agent_repo

  STUB_AUTH_CLAUDE=out STUB_AUTH_CODEX=subscription AGENT_OUT="AUTO-NOTES" run_builtin auto
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: codex (subscription)"
  assert_output --partial "Release notes written by notes agent 'codex':"
  # Passing over claude is not a failure: no warning names it.
  refute_output --partial "Notes agent 'claude'"
  run cat "${AGENT_REC}/ran"
  assert_output "codex"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes AUTO-NOTES
}

@test "auto agent: with claude not installed and codex logged in, codex writes the notes (#165)" {
  builtin_agent_repo
  rm "${SHIM}/claude"

  STUB_AUTH=subscription AGENT_OUT="AUTO-NOTES" VB_PATH=$(path_without_agents) run_builtin auto
  assert_success
  strip_ansi_output

  assert_output --partial "Notes agent: codex (subscription)"
  refute_output --partial "is not installed"
  run cat "${AGENT_REC}/ran"
  assert_output "codex"
  assert_gh_argv "${SHIM}/argv" release create v1.3.0 --notes AUTO-NOTES
}

@test "auto agent: with neither agent available, one info line and no warning, the fallback notes and exit 0 (#165)" {
  local setup

  # Both logged out with no key, then neither installed: each in a fresh repo.
  for setup in logged-out not-installed; do
    builtin_agent_repo
    if [ "$setup" = not-installed ]; then
      rm "${SHIM}/claude" "${SHIM}/codex"
      VB_PATH=$(path_without_agents)
    fi

    STUB_AUTH=out AGENT_OUT="NOTES" run_builtin auto
    VB_PATH=""
    assert_success
    strip_ansi_output

    assert_line --partial "No notes agent found (RELEASE_NOTES_AGENT=auto)"
    # Keep the run's output: each `run` below replaces $output.
    local release_out=$output
    run grep -c "No notes agent found" <<< "$release_out"
    assert_output 1
    # No line in the run is a warning ("!" after the gutter).
    run grep -E '^[[:space:]]*! ' <<< "$release_out"
    assert_failure 1
    [ ! -f "${AGENT_REC}/ran" ] || bats_fail "an agent ran (${setup})"
    assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
  done
}

@test "auto agent: a picked agent that fails warns, publishes the fallback, and the other agent never runs (#165)" {
  local cause

  # claude is picked (both logged in); its run fails in each way R-REL-13
  # names. codex is never asked, not even for its login status.
  local -a causes=(exit empty timeout)
  local -a warnings=("exited 3" "returned empty or whitespace-only output" "timed out after 1s")
  local i
  for i in 0 1 2; do
    cause=${causes[$i]}
    builtin_agent_repo
    case $cause in
      exit)
        STUB_AUTH=subscription AGENT_OUT="NOTES" AGENT_RC=3 run_builtin auto
        ;;
      empty)
        STUB_AUTH=subscription AGENT_OUT="" run_builtin auto
        ;;
      timeout)
        # A claude that hangs past a 1 s timeout.
        printf '#!/bin/sh\n[ "$1" = auth ] && { echo "{\\"loggedIn\\":true}"; exit 0; }\necho claude >> "${AGENT_REC}/ran"\nsleep 30\n' > "${SHIM}/claude"
        STUB_AUTH=subscription run_builtin auto RELEASE_NOTES_AGENT_TIMEOUT=1
        ;;
    esac
    assert_success
    strip_ansi_output

    assert_output --partial "Notes agent 'claude' ${warnings[$i]}"
    refute_output --partial "Notes agent: codex"
    run cat "${AGENT_REC}/ran"
    assert_output "claude"
    if [ -f "${AGENT_REC}/status" ]; then
      run grep -c OPENAI_API_KEY "${AGENT_REC}/status"
      assert_output 0
    fi
    assert_gh_argv "${SHIM}/argv" release create v1.3.0 --generate-notes --notes-start-tag v1.2.3
  done
}

# ── Dry-run preview of the notes agent (#166, ADR-24, R-REL-20) ──────────────

# Fail when the stubs show that a notes agent got a prompt: a built-in stub
# writes $AGENT_REC/ran, the custom stub $AGENT_REC/stdin. A status check
# writes neither.
assert_no_agent_prompt() {
  [ ! -e "${AGENT_REC}/ran" ] || bats_fail "a built-in notes agent ran: $(cat "${AGENT_REC}/ran")"
  [ ! -e "${AGENT_REC}/stdin" ] || bats_fail "a notes agent got a prompt"
}

@test "dry-run agent: --dry-run never prompts auto, claude, codex or a custom command (#166)" {
  local agent
  local -a RUN_FLAGS=(-d)
  for agent in auto claude codex notes-agent-stub; do
    builtin_agent_repo
    agent_stub "$SHIM"
    STUB_AUTH=subscription AGENT_OUT="NOTES" run_builtin "$agent"
    assert_success
    assert_no_agent_prompt
    [ ! -e "${SHIM}/argv/1" ] || bats_fail "gh ran under --dry-run with ${agent}"
  done
}

@test "dry-run agent: the [dry-run] line names the picked agent, its auth mode and the fallback (#166)" {
  local -a RUN_FLAGS=(-d)
  local fallback="gh release create v1.3.0 --generate-notes --notes-start-tag v1.2.3"

  builtin_agent_repo
  STUB_AUTH=subscription run_builtin claude ANTHROPIC_API_KEY=sk-caller
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run] notes agent: claude (subscription) — would run: gh release create v1.3.0 --notes '<notes from claude>'; fallback: ${fallback}"
  # The live info line is for a run that calls the agent.
  refute_output --partial "Notes agent: claude"
  # The status check may run, and runs as it does live: without the key.
  run cat "${AGENT_REC}/status"
  assert_output "ANTHROPIC_API_KEY="

  builtin_agent_repo
  STUB_AUTH_CLAUDE=out STUB_AUTH_CODEX=key run_builtin auto OPENAI_API_KEY=sk-ci
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run] notes agent: codex (API key) — would run: gh release create v1.3.0 --notes '<notes from codex>'; fallback: ${fallback}"

  builtin_agent_repo
  run_builtin "my-llm --fast"
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run] notes agent: my-llm --fast (custom command) — would run: gh release create v1.3.0 --notes '<notes from my-llm --fast>'; fallback: ${fallback}"
  assert_no_agent_prompt
}

@test "dry-run agent: with no notes agent found the [dry-run] line says so and shows the fallback (#166)" {
  local -a RUN_FLAGS=(-d)
  local fallback="gh release create v1.3.0 --generate-notes --notes-start-tag v1.2.3"

  # auto: the [dry-run] line takes the place of the live info line.
  builtin_agent_repo
  STUB_AUTH=out run_builtin auto
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run] no notes agent found (RELEASE_NOTES_AGENT=auto) — would run: ${fallback}"
  refute_output --partial "No notes agent found (RELEASE_NOTES_AGENT=auto) — publishing"
  # No line in the run is a warning ("!" after the gutter).
  run grep -E '^[[:space:]]*! ' <<< "$output"
  assert_failure 1
  assert_no_agent_prompt

  # A named agent that is not available warns as a live run does.
  builtin_agent_repo
  rm "${SHIM}/claude" "${SHIM}/codex"
  VB_PATH=$(path_without_agents) run_builtin claude
  assert_success
  strip_ansi_output
  assert_output --partial "Notes agent 'claude' is not installed (no 'claude' on PATH)"
  assert_output --partial "[dry-run] no notes agent found (RELEASE_NOTES_AGENT=claude) — would run: ${fallback}"
}

# The github-release effect of the --dry-run --json plan in $output, as
# compact JSON.
github_release_effect() {
  jq -c '.effects[] | select(.action == "github-release")' <<< "$output"
}

@test "dry-run agent: the --json effect names the agent and the fallback when an agent would run (#166)" {
  local -a RUN_FLAGS=(-d --json)
  local RUN_SEPARATE=1

  builtin_agent_repo
  STUB_AUTH=subscription run_builtin claude
  assert_success
  run github_release_effect
  assert_output '{"action":"github-release","tag":"v1.3.0","notes":"agent","prerelease":false,"agent":"claude","fallback":"generated"}'

  builtin_agent_repo
  STUB_AUTH_CLAUDE=out STUB_AUTH_CODEX=subscription run_builtin auto
  assert_success
  run github_release_effect
  assert_output '{"action":"github-release","tag":"v1.3.0","notes":"agent","prerelease":false,"agent":"codex","fallback":"generated"}'

  builtin_agent_repo
  run_builtin "my-llm --fast"
  assert_success
  run github_release_effect
  assert_output '{"action":"github-release","tag":"v1.3.0","notes":"agent","prerelease":false,"agent":"my-llm --fast","fallback":"generated"}'
}

@test "dry-run agent: the --json effect has agent null and today's notes when the feature is off or no agent is found (#166)" {
  local -a RUN_FLAGS=(-d --json)
  local RUN_SEPARATE=1 agent
  local want='{"action":"github-release","tag":"v1.3.0","notes":"generated","prerelease":false,"agent":null,"fallback":"generated"}'

  for agent in off auto claude; do
    builtin_agent_repo
    STUB_AUTH=out run_builtin "$agent"
    assert_success
    run github_release_effect
    assert_output "$want"
  done

  # A custom VERBUMP_RELEASE_NOTES_CMD still runs and beats the agent.
  builtin_agent_repo
  STUB_AUTH=subscription run_builtin claude VERBUMP_RELEASE_NOTES_CMD='echo CMD-NOTES'
  assert_success
  run github_release_effect
  assert_output '{"action":"github-release","tag":"v1.3.0","notes":"command","prerelease":false,"agent":null,"fallback":"generated"}'
  assert_no_agent_prompt
}

@test "dry-run agent: under a package scope the fallback is the package's changelog entry (#166)" {
  agent_monorepo
  local RUN_SEPARATE=1 err

  run_with_agent --release -d --json -p "$REMOTE" -b -c -v 1.2.4
  assert_success
  assert_no_agent_prompt
  # Keep the run's stderr: the next `run` replaces it.
  err=$stderr
  run jq -r '.effects[] | select(.action == "github-release") | "\(.notes) \(.agent) \(.fallback)"' <<< "$output"
  assert_output "agent notes-agent-stub changelog"
  # The fallback prints the package's changelog entry as its notes.
  run grep -c -F "[dry-run] notes agent: notes-agent-stub (custom command) — would run: gh release create pkg-a-v1.2.4 --notes '<notes from notes-agent-stub>'; fallback: gh release create pkg-a-v1.2.4 --notes '" <<< "$err"
  assert_output 1
  run grep -c -F "correct rounding" <<< "$err"
  refute_output 0
}

@test "dry-run agent: with RELEASE_NOTES_AGENT=off the dry-run release lines are today's (#166)" {
  local -a RUN_FLAGS=(-d)
  local agent

  for agent in off auto; do
    builtin_agent_repo
    # auto with a custom VERBUMP_RELEASE_NOTES_CMD: the command wins, as today.
    if [ "$agent" = auto ]; then
      STUB_AUTH=subscription run_builtin auto VERBUMP_RELEASE_NOTES_CMD='echo CMD-NOTES'
    else
      STUB_AUTH=subscription run_builtin off
    fi
    assert_success
    strip_ansi_output
    if [ "$agent" = auto ]; then
      assert_line "[dry-run] would run: gh release create v1.3.0 --notes 'CMD-NOTES'"
    else
      assert_line "[dry-run] would run: gh release create v1.3.0 --generate-notes --notes-start-tag v1.2.3"
    fi
    refute_output --partial "notes agent"
    refute_output --partial "Notes agent"
    # off never asks for a login status.
    [ "$agent" = auto ] || [ ! -e "${AGENT_REC}/status" ] || bats_fail "off ran a status check"
  done
}
