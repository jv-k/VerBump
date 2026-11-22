#!/usr/bin/env bats

# Non-interactive runs (R-YES-1, R-DRY-5, R-FLOW-8): --yes answers both the
# version prompt and the push prompt without reading stdin, a dry run never
# asks to push, and a failed push ends the run with exit 1. Together they let
# CI (US-4) run VerBump with no prompts and trust the exit code.

load 'test_helper'

# A repo tagged v1.0.0 with one feat: commit since, pushed to a bare
# 'origin'. The suggested version is 1.1.0.
ci_repo() {
  local repo remote
  repo="$(scratch_repo)"
  cd "$repo" || exit 1
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"
  git tag v1.0.0
  git commit -q --allow-empty -m "feat: add a thing"

  remote=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "$remote"
  git remote add origin "$remote"
  git push -qu origin "$(git symbolic-ref --short HEAD)" v1.0.0 2>/dev/null
  REMOTE="$remote"
}

# ── R-YES-1: --yes answers the version prompt ──────────────────────────────

@test "non-interactive: --yes takes the suggestion without reading stdin (R-YES-1)" {
  ci_repo

  # Before the fix the prompt still ran and read this line as the version.
  run bash -c 'printf "9.9.9\n" | "$1" --yes -n -c' _ "${profile_script}"
  assert_success
  strip_ansi_output
  assert_output --partial "Suggested version accepted via [--yes]: 1.1.0"
  run jq -r '.version' package.json
  assert_output "1.1.0"
}

@test "non-interactive: without --yes the version prompt still reads stdin" {
  ci_repo

  run bash -c 'printf "2.0.0\n" | "$1" -n -c' _ "${profile_script}"
  assert_success
  run jq -r '.version' package.json
  assert_output "2.0.0"
}

# ── R-YES-1: --yes answers the push prompt ─────────────────────────────────

@test "non-interactive: --yes without -p pushes to the default remote (R-YES-1)" {
  ci_repo

  # A 'n' on stdin must not be read: --yes already answered the prompt.
  run bash -c 'printf "n\n" | "$1" --yes -c' _ "${profile_script}"
  assert_success
  strip_ansi_output
  refute_output --partial "Push branch + tags to"
  run git --git-dir="$REMOTE" tag -l v1.1.0
  assert_output "v1.1.0"
}

@test "non-interactive: --yes --quiet without -p prints the version and pushes" {
  ci_repo

  run bash -c '"$1" --quiet --yes -c >"$2/out" 2>"$2/err" </dev/null' _ \
    "${profile_script}" "$BATS_TEST_TMPDIR"
  assert_success
  run cat "$BATS_TEST_TMPDIR/out"
  assert_output "1.1.0"
  run git --git-dir="$REMOTE" tag -l v1.1.0
  assert_output "v1.1.0"
}

# ── R-DRY-5: a dry run never asks to push ──────────────────────────────────

@test "non-interactive: dry run without -p or --yes leaves the push out, exit 0 (R-DRY-5)" {
  ci_repo

  # Before the fix this asked to push, read 'n' and exited 5.
  run bash -c 'printf "n\n" | "$1" -d -c -v 1.0.1' _ "${profile_script}"
  assert_success
  strip_ansi_output
  refute_output --partial "Push branch + tags to"
  assert_output --partial "push not planned"
  refute_output --partial "would run: git push"
}

@test "non-interactive: dry run with --yes plans the push to the default remote" {
  ci_repo

  run ${profile_script} -d -y -c </dev/null
  assert_success
  strip_ansi_output
  assert_output --partial "would run: git push -u origin"
}

@test "non-interactive: --minor --dry-run --json without -p emits a plan with no push (R-DRY-5)" {
  ci_repo

  run bash -c '"$1" --minor --dry-run --json 2>/dev/null </dev/null' _ "${profile_script}"
  assert_success
  # Valid JSON, and no push effect: nothing on the command line chose one.
  run jq -r '.version.to' <<< "$output"
  assert_output "1.1.0"
  run jq '[.effects[] | select(.action == "push")] | length' <<< "$(
    "${profile_script}" --minor --dry-run --json 2>/dev/null </dev/null)"
  assert_output "0"
}

# ── R-FLOW-8: a failed push exits 1 ────────────────────────────────────────

@test "non-interactive: a failed push exits 1 and keeps the local commit and tag (R-FLOW-8)" {
  ci_repo
  # Make the remote refuse every push.
  printf '#!/bin/sh\nexit 1\n' > "$REMOTE/hooks/pre-receive"
  chmod +x "$REMOTE/hooks/pre-receive"

  run ${profile_script} -y -c -p origin </dev/null
  assert_failure 1
  strip_ansi_output
  assert_output --partial "Push to <origin> failed"
  assert_output --partial "git push -u origin main v1.1.0"
  assert_output --partial "verbump --undo 1.1.0"
  # The run stops at the push: no "Done" section.
  refute_output --partial " DONE "
  run git tag -l v1.1.0
  assert_output "v1.1.0"
}

@test "non-interactive: a push from a detached HEAD exits 1 with a detached hint (R-FLOW-8)" {
  ci_repo
  git checkout -q --detach

  run ${profile_script} -y -c -p origin </dev/null
  assert_failure 1
  strip_ansi_output
  assert_output --partial "HEAD is detached"
}
