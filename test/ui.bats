#!/usr/bin/env bats

# UI / colour discipline regression guards. These tests do not exercise
# behaviour — they lock in the "plain narrative, colour for values only"
# convention so future edits don't drift back to fixed-fg tokens or
# whole-line colour wraps.
#
# Rule of thumb:
#   - Narrative text       → no style token
#   - Emphasis              → S_NORM (bold of the terminal's own fg — never
#                              a fixed colour like the old WHITE/1;37)
#   - Interpolated values  → S_VAL (green)
#   - Soft prompts          → magenta INPUT/CONFIRM pill (prompt_input /
#                              prompt_confirm), then default-fg question
#                              text, value in S_VAL, choice hint (e.g.
#                              "[N/y]") in S_DIM
#   - Warning bodies        → S_WARN "Warning:" prefix + plain body
#   - Errors                → via fail helper (S_ERROR label, S_NORM body)
#   - Dim markers            → S_LIGHT ("[dry-run]", "Option set:") — a
#                              theme-adaptive dim, never the old fixed
#                              LIGHTGRAY/0;37
#
# `S_NOTICE` and raw `GREEN`/`WHITE`/`LIGHTGRAY` are all forbidden on call
# sites outside styles.sh. Help output in usage() is out of scope and
# allowed to keep BOLD headers.

load 'test_helper'

# Scratch repo with a committed package.json at 1.0.0 — clean tree, no
# tags, so a full live/dry-run release can proceed through do-push.
ui_repo() {
  local repo
  repo="$(scratch_repo)"
  cd "$repo" || exit 1
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"
}

@test "UI: no S_NOTICE references in lib/*.sh (except styles.sh) or verbump.sh" {
  # S_NOTICE was the whole-line green narrative token. The refactor stripped
  # it; ensure it doesn't creep back. styles.sh still defines S_NOTICE as a
  # deprecated alias to $GREEN — that's intentional and out of scope.
  run bash -c "grep -rln --include='*.sh' 'S_NOTICE' '${repo_dir}/lib' '${repo_dir}/verbump.sh' | grep -v '/lib/styles.sh\$'"
  assert_failure
}

@test "UI: no raw GREEN references outside lib/styles.sh" {
  # GREEN is defined in styles.sh (fine) but must not be used directly in
  # narrative echoes anywhere else.
  run bash -c "grep -rln --include='*.sh' 'GREEN' '${repo_dir}/lib' '${repo_dir}/verbump.sh' | grep -v '/lib/styles.sh\$'"
  assert_failure
}

@test "UI: no raw WHITE or LIGHTGRAY references outside lib/styles.sh" {
  # WHITE (bold fixed-white, 1;37) and LIGHTGRAY (fixed 0;37) were the
  # tokens S_NORM/S_LIGHT used to hardcode — they fought the terminal's own
  # theme. S_NORM/S_LIGHT now alias BOLD/DIM instead; guard against a raw
  # fixed-fg reference creeping back into a call site.
  #
  # -w (whole-word), NOT '\b': \b is not a POSIX ERE metacharacter, so its
  # meaning varies by grep (GNU vs BSD) — a guard built on it can silently
  # stop matching. -w matches WHITE/LIGHTGRAY only as complete identifiers,
  # so ${WHITE} is caught while a longer name like LIGHTWHITE is not.
  run bash -c "grep -rlnwE --include='*.sh' 'WHITE|LIGHTGRAY' '${repo_dir}/lib' '${repo_dir}/verbump.sh' | grep -v '/lib/styles.sh\$'"
  assert_failure
}

@test "UI: 'Option set:' banners keep S_LIGHT dim prefix + reset" {
  # Option-set acknowledgements are secondary info; the prefix stays dim
  # ($S_LIGHT) and the narrative body is plain.
  run grep -rh --include='*.sh' -c 'S_LIGHT}Option set:${RESET}' "${repo_dir}/lib"
  assert_success
  # At least the 9 option handlers that still emit a set-banner (-m, -f, -p,
  # -t, -B, -d, -n, -c, -l). -b/--no-branch is a deprecation note as of 2.0.
  local total=0 line
  while IFS= read -r line; do total=$((total + line)); done <<< "${output}"
  [ "${total}" -ge 9 ]
}

@test "UI: dry-run lines keep [dry-run] dim marker" {
  # [dry-run] stays dim so it reads as a marker, not narrative.
  run grep -rh --include='*.sh' -c 'S_LIGHT}\[dry-run\]${RESET}' "${repo_dir}/lib"
  assert_success
  local total=0 line
  while IFS= read -r line; do total=$((total + line)); done <<< "${output}"
  [ "${total}" -ge 6 ]
}

# ── Runtime ANSI assertions — force colour, decode real escape bytes ──────

@test "UI: fail() emphasises the message in bold, not fixed-white (1;37)" {
  run env CLICOLOR_FORCE=1 "${profile_script}" --release=yes
  assert_failure 2
  # Assert the STYLING only, not the wording: the red inverted ERROR pill
  # sits on its own line, then the body opens in S_NORM = bold (\e[1m) and
  # is never wrapped in the old fixed bold-white (\e[1;37m). Unrelated copy
  # changes to the message must not break this guard.
  assert_output --partial $'\033[7;1;31m ERROR \033[0m\n\033[1m'
  refute_output --partial $'\033[1;37m'
}

@test "UI: [dry-run] marker renders dim (\\e[2m), not fixed grey (0;37)" {
  ui_repo
  run env CLICOLOR_FORCE=1 "${profile_script}" -d -p origin -y -v 1.0.1
  assert_success
  assert_output --partial $'\033[2m[dry-run]\033[0m'
  refute_output --partial $'\033[0;37m'
}

@test "UI: push prompt shows the magenta CONFIRM pill + default-fg question text" {
  ui_repo
  # A live run with no -p and no --yes is the only path that still asks:
  # --yes answers the prompt and --dry-run never shows it (R-YES-1, R-DRY-5).
  run bash -c "echo n | env CLICOLOR_FORCE=1 '${profile_script}' -v 1.0.1"
  assert_failure 5
  # Magenta inverted pill on its own line, flush to the margin, then the
  # question in the terminal's own default fg (no colour wrap, no leading
  # glyph) up to the S_VAL-accented PUSH_DEST value.
  assert_output --partial $'\n\033[7;1;35m CONFIRM \033[0m\nPush branch + tags to <\033[0;32morigin\033[0m>? \033[2m[N/y]\033[0m'
  # No more cyan "?" glyph (old S_PROMPT+I_PROMPT) on this prompt.
  refute_output --partial $'\033[0;36m?\033[0m Push branch'
  # No more whole-line yellow (old S_QUESTION) wrap on this prompt.
  refute_output --partial $'\033[1;33mPush branch'
}

@test "UI: changelog step emits a green CHANGELOG subsection pill" {
  ui_repo
  run env CLICOLOR_FORCE=1 "${profile_script}" -d -y -v 1.0.1
  assert_success
  # subsection() renders an inverted bold-green pill, flush to the margin:
  # "\e[7;1;32m TEXT \e[0m"
  assert_output --partial $'\n\033[7;1;32m CHANGELOG \033[0m'
}

@test "UI: NO_COLOR strips all ANSI, including the new tokens" {
  ui_repo
  # Live run declined at the push prompt, so the CONFIRM pill is covered too.
  run bash -c "echo n | env NO_COLOR=1 CLICOLOR_FORCE=1 '${profile_script}' -v 1.0.1"
  assert_failure 5
  refute_output --partial $'\033['
}
