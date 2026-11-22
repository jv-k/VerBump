#!/usr/bin/env bats

# Release hooks (R-HOOK-1..6, issue #62): PRE_BUMP_CMD runs after all Verify
# preflights and before any mutation; POST_TAG_CMD runs after the tag and
# before push / --pr / --release. Non-zero exits 4 — the first real user of
# the code reserved since the 2.0 exit contract (PRD §5.6). Keys come from
# env or .verbumprc only; --no-hooks skips both for a run.

load 'test_helper'

# Scratch repo with a committed package.json at 1.0.0 — clean tree, no tags,
# so every preflight passes and a full live release can run end-to-end.
hooks_repo() {
  local repo
  repo="$(scratch_repo)"
  cd "$repo" || exit 1
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"
}

# ── R-HOOK-1: PRE_BUMP_CMD ───────────────────────────────────────────────

@test "hooks: failing PRE_BUMP_CMD exits 4 and mutates nothing (R-HOOK-1)" {
  hooks_repo

  PRE_BUMP_CMD="exit 7" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
  strip_ansi_output
  assert_output --partial "pre-bump hook failed (exit 7)"
  assert_output --partial "--no-hooks"

  # Nothing mutated: porcelain-clean tree, no tag, version untouched.
  run git status --porcelain
  assert_output ""
  run git tag -l
  assert_output ""
  run jq -r '.version' package.json
  assert_output "1.0.0"
  assert_equal "$(git rev-list --count HEAD)" "2"
}

@test "hooks: PRE_BUMP_CMD runs via bash -c (pipeline works) and streams output (R-HOOK-1/4)" {
  hooks_repo

  PRE_BUMP_CMD="echo hook-street-cred | tr a-z A-Z" \
    run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  strip_ansi_output
  # Resolved command logged before running, hook stdout streamed through.
  assert_output --partial "Running pre-bump hook"
  assert_output --partial "echo hook-street-cred | tr a-z A-Z"
  assert_output --partial "HOOK-STREET-CRED"
}

@test "hooks: passing PRE_BUMP_CMD lets the release proceed (R-HOOK-1)" {
  hooks_repo

  PRE_BUMP_CMD="true" run ${profile_script} -v 1.0.1 -c -n
  assert_success
  run jq -r '.version' package.json
  assert_output "1.0.1"
}

# ── R-HOOK-2: POST_TAG_CMD ───────────────────────────────────────────────

@test "hooks: failing POST_TAG_CMD exits 4, keeps commit + tag, points at --undo (R-HOOK-2)" {
  hooks_repo

  POST_TAG_CMD="exit 3" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
  strip_ansi_output
  assert_output --partial "post-tag hook failed (exit 3)"
  assert_output --partial "--undo 1.0.1"

  # The bump commit and tag were kept; nothing was pushed (no remote exists).
  run git tag -l
  assert_output "v1.0.1"
  run jq -r '.version' package.json
  assert_output "1.0.1"
  assert_equal "$(git rev-list --count HEAD)" "3"
}

@test "hooks: POST_TAG_CMD failure stops the run before the push prompt (R-HOOK-2)" {
  hooks_repo

  # No -p and no piped answer: reaching do-push would block on the prompt /
  # exit 5. Exit 4 proves the run stopped at the hook, before any push path.
  POST_TAG_CMD="false" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
  strip_ansi_output
  refute_output --partial "Push branch + tags"
}

@test "hooks: POST_TAG_CMD is skipped under -n/--no-commit (no tag exists)" {
  hooks_repo

  POST_TAG_CMD="false" run ${profile_script} -v 1.0.1 -c -n
  assert_success
  strip_ansi_output
  refute_output --partial "post-tag hook"
}

# ── R-HOOK-3: env / rc sourcing + precedence ─────────────────────────────

@test "hooks: PRE_BUMP_CMD from .verbumprc is honoured (R-HOOK-3)" {
  hooks_repo
  printf 'PRE_BUMP_CMD="touch rc-hook-ran"\n' > .verbumprc

  run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  [ -f rc-hook-ran ]
}

@test "hooks: env PRE_BUMP_CMD beats .verbumprc (R-HOOK-3 / R-CFG-3)" {
  hooks_repo
  printf 'PRE_BUMP_CMD="touch from-file"\n' > .verbumprc

  PRE_BUMP_CMD="touch from-env" run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  [ -f from-env ]
  [ ! -f from-file ]
}

@test "hooks: empty env PRE_BUMP_CMD disables an rc-defined hook (R-HOOK-3)" {
  hooks_repo
  printf 'PRE_BUMP_CMD="touch from-file"\n' > .verbumprc

  PRE_BUMP_CMD="" run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  [ ! -f from-file ]
}

@test "hooks: env POST_TAG_CMD beats .verbumprc (R-HOOK-3 / R-CFG-3)" {
  hooks_repo
  printf 'POST_TAG_CMD="touch from-file; exit 1"\n' > .verbumprc

  POST_TAG_CMD="touch from-env; exit 1" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
  [ -f from-env ]
  [ ! -f from-file ]
}

# ── R-HOOK-4: logging + dry-run ──────────────────────────────────────────

@test "hooks: --dry-run prints both hooks with [dry-run] prefix, executes neither (R-HOOK-4)" {
  hooks_repo

  PRE_BUMP_CMD="touch pre-ran" POST_TAG_CMD="touch post-ran" \
    run ${profile_script} -v 1.0.1 -d -c -p origin
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run] would run pre-bump hook: bash -c 'touch pre-ran'"
  assert_output --partial "[dry-run] would run post-tag hook: bash -c 'touch post-ran'"
  [ ! -f pre-ran ]
  [ ! -f post-ran ]
  run git status --porcelain
  assert_output ""
}

@test "hooks: dry-run hook preview goes to stderr (R-DRY-2)" {
  hooks_repo

  run bash -c \
    'PRE_BUMP_CMD="touch pre-ran" "$1" -v 1.0.1 -d -c -p origin >"$2/out" 2>"$2/err"' _ \
    "${profile_script}" "$BATS_TEST_TMPDIR"
  assert_success
  run grep 'would run pre-bump hook' "$BATS_TEST_TMPDIR/err"
  assert_success
}

@test "hooks: failing hook's own stderr streams through (R-HOOK-4)" {
  hooks_repo

  PRE_BUMP_CMD="echo boom-diagnostic >&2; exit 1" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
  strip_ansi_output
  assert_output --partial "boom-diagnostic"
}

# ── R-HOOK-5: --no-hooks ─────────────────────────────────────────────────

@test "hooks: --no-hooks skips both hooks (R-HOOK-5)" {
  hooks_repo
  local remote
  remote=$(mktemp -d); CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "$remote"
  git remote add origin "$remote"

  # -y answers the push prompt (R-YES-1), so the run pushes to the bare
  # remote and completes.
  PRE_BUMP_CMD="touch pre-ran; exit 1" POST_TAG_CMD="touch post-ran; exit 1" \
    run ${profile_script} -v 1.0.1 -y --no-hooks </dev/null
  assert_success
  [ ! -f pre-ran ]
  [ ! -f post-ran ]
  # The release itself went through: bump commit + tag exist.
  run git tag -l
  assert_output "v1.0.1"
}

@test "hooks: env FLAG_NOHOOKS cannot skip hooks (CLI-only reset)" {
  hooks_repo

  FLAG_NOHOOKS=true PRE_BUMP_CMD="exit 1" run ${profile_script} -v 1.0.1 -y
  assert_failure 4
}

@test "hooks: .verbumprc FLAG_NOHOOKS cannot skip hooks (CLI-only reset)" {
  hooks_repo
  printf 'FLAG_NOHOOKS=true\nPRE_BUMP_CMD="exit 1"\n' > .verbumprc

  run ${profile_script} -v 1.0.1 -y
  assert_failure 4
}

# ── R-HOOK-6: exported environment ───────────────────────────────────────

@test "hooks: PRE_BUMP_CMD sees VERBUMP_VERSION / _PREV_VERSION / _TAG (R-HOOK-6)" {
  hooks_repo

  PRE_BUMP_CMD='printf "%s|%s|%s" "$VERBUMP_VERSION" "$VERBUMP_PREV_VERSION" "$VERBUMP_TAG" > hook-env' \
    run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  run cat hook-env
  assert_output "1.0.1|1.0.0|v1.0.1"
}

@test "hooks: single-quoted rc hook defers VERBUMP_* expansion to run time (R-HOOK-6)" {
  hooks_repo
  # Single quotes in the rc are load-bearing: the rc is shell-sourced, so a
  # double-quoted string would expand $VERBUMP_* at load time (still empty).
  cat > .verbumprc <<'RC'
PRE_BUMP_CMD='printf "%s" "$VERBUMP_TAG" > hook-env'
RC

  run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  run cat hook-env
  assert_output "v1.0.1"
}

@test "hooks: POST_TAG_CMD sees the same env, custom tag prefix honoured (R-HOOK-6)" {
  hooks_repo

  # Hook writes its env then fails, so the run exits 4 before the push prompt.
  POST_TAG_CMD='printf "%s|%s" "$VERBUMP_VERSION" "$VERBUMP_TAG" > hook-env; exit 1' \
    run ${profile_script} -v 1.0.1 -y -t rel/
  assert_failure 4
  run cat hook-env
  assert_output "1.0.1|rel/1.0.1"
}

@test "hooks: VERBUMP_* vars are exported to the hook only, not leaked" {
  hooks_repo

  # Sanitize first: when this suite itself runs as a VerBump PRE_BUMP_CMD
  # hook (dogfooding — see the repo's own .verbumprc), the OUTER VerBump
  # legitimately exports VERBUMP_* to us. Clear them so the leak assertion
  # below tests this run, not the inherited hook context.
  unset VERBUMP_VERSION VERBUMP_PREV_VERSION VERBUMP_TAG

  # After a successful hooked run, the parent environment written by the
  # release itself (git config, files) must not contain VERBUMP_VERSION —
  # verify via a second hook that runs in the same VerBump process ordering.
  PRE_BUMP_CMD='env | grep -c "^VERBUMP_" > hook-env' \
    run ${profile_script} -v 1.0.1 -y -n -c
  assert_success
  run cat hook-env
  assert_output "3"
  # And the bats process env is untouched.
  [ -z "${VERBUMP_VERSION-}" ]
}

# ── Regression pin: hooks absent = zero behaviour change ─────────────────

@test "hooks: unset hooks leave a release byte-identical (regression pin)" {
  hooks_repo

  run ${profile_script} -v 1.0.1 -c -n
  assert_success
  strip_ansi_output
  refute_output --partial "hook"
  run jq -r '.version' package.json
  assert_output "1.0.1"
}

@test "hooks: unset hooks + dry-run print no hook lines (regression pin)" {
  hooks_repo

  run ${profile_script} -v 1.0.1 -d -c -p origin
  assert_success
  strip_ansi_output
  refute_output --partial "hook"
}

# ── Surface: completions ─────────────────────────────────────────────────

@test "hooks: completions list --no-hooks in bash/zsh/fish" {
  run ${profile_script} --completions bash
  assert_success
  assert_output --partial -- "--no-hooks"
  run ${profile_script} --completions zsh
  assert_success
  assert_output --partial -- "--no-hooks"
  run ${profile_script} --completions fish
  assert_success
  assert_output --partial -- "-l no-hooks"
}
