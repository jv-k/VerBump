#!/usr/bin/env bats

# --pr flag: after the branch + tag are pushed, open a GitHub pull request for
# the release branch via the `gh` CLI (head = release-<v>, base = $PR_BASE).
# --pr implies --branch and a push, and — like --release — only needs `gh` when
# it's passed; the default VerBump path stays bash + git + jq only. Mirrors the
# gh-shim-on-PATH pattern from release.bats.

load 'test_helper'

# Write a fake `gh` onto a fresh PATH dir. `gh auth …` succeeds; every other
# call echoes "GH-CALL: <args>" so tests can assert the exact invocation.
_gh_shim() {
  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 0
echo "GH-CALL: $*"
exit 0
SH
  chmod +x "${shim}/gh"
  printf '%s' "$shim"
}

@test "pr: --pr but gh missing exits 3" {
  source ${profile_script}
  cd "$(scratch_repo)"
  local shim
  shim=$(mktemp -d); CLEANUP_CMDS+=("rm -rf ${shim}")
  # git on PATH but no gh
  cat > "${shim}/git" <<'SH'
#!/bin/sh
exec /usr/bin/env git "$@"
SH
  chmod +x "${shim}/git"

  DO_PR=true V_NEW=1.2.3 PATH="${shim}" run check-pr-deps
  assert_failure 3
  assert_output --partial "gh"
}

@test "pr: --pr with -n / --no-commit exits 2" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  run ${profile_script} --pr -n -v 1.0.1
  assert_failure 2
  strip_ansi_output
  assert_output --partial "incompatible with -n"
}

@test "pr: gh present but unauthenticated exits 3" {
  source ${profile_script}
  cd "$(scratch_repo)"
  local shim
  shim=$(mktemp -d); CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 1
exit 0
SH
  chmod +x "${shim}/gh"

  DO_PR=true FLAG_DRYRUN=false V_NEW=1.2.3 PATH="${shim}:$PATH" run check-pr-deps
  assert_failure 3
  assert_output --partial "authenticated"
}

@test "pr: --dry-run skips the gh auth check" {
  source ${profile_script}
  cd "$(scratch_repo)"
  local shim
  shim=$(mktemp -d); CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 1
exit 0
SH
  chmod +x "${shim}/gh"

  DO_PR=true FLAG_DRYRUN=true V_NEW=1.2.3 PATH="${shim}:$PATH" run check-pr-deps
  assert_success
}

@test "pr: --base equal to the release head is rejected" {
  local repo shim
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"
  shim="$(_gh_shim)"

  PATH="${shim}:$PATH" run ${profile_script} --pr -d -c -v 1.2.3 --base release-1.2.3
  assert_failure 2
  strip_ansi_output
  assert_output --partial "same as the release branch head"
}

@test "pr: --pr --dry-run prints resolved gh pr create with head + base" {
  local repo shim
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"
  shim="$(_gh_shim)"

  PATH="${shim}:$PATH" run ${profile_script} --pr -d -c -v 1.2.3 --base main
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run]"
  assert_output --partial "gh pr create --head release-1.2.3 --base main"
}

@test "pr: base auto-detects the invocation branch when --base omitted" {
  local repo shim
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"
  git checkout -q -b develop
  shim="$(_gh_shim)"

  PATH="${shim}:$PATH" run ${profile_script} --pr -d -c -v 1.2.3
  assert_success
  strip_ansi_output
  assert_output --partial "gh pr create --head release-1.2.3 --base develop"
}

@test "pr: --pr --dry-run leaves the working tree byte-identical" {
  local repo shim before after
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"
  shim="$(_gh_shim)"

  before=$(git status --porcelain)
  PATH="${shim}:$PATH" run ${profile_script} --pr -d -c -v 1.2.3 --base main
  assert_success
  after=$(git status --porcelain)
  assert_equal "$before" "$after"
}

@test "pr: a failed push exits 1 before the release PR (R-FLOW-8)" {
  local repo shim
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"
  shim="$(_gh_shim)"

  # 'origin' is not configured, so the push fails. Live run (no -d).
  PATH="${shim}:$PATH" run ${profile_script} --pr -p origin -c -v 1.2.5 --base main
  assert_failure 1
  strip_ansi_output
  assert_output --partial "Push to <origin> failed"
  # The hint names the command that opens the PR once the push works.
  assert_output --partial "gh pr create --head release-1.2.5 --base main"
  refute_output --partial "GH-CALL: pr create"
}

@test "pr: live path runs gh pr create with head + base" {
  local repo remote shim
  repo="$(scratch_repo)"; cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "feat: seed"

  remote=$(mktemp -d); CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "${remote}"
  shim="$(_gh_shim)"

  PATH="${shim}:$PATH" run ${profile_script} --pr -p "${remote}" -c -v 1.2.5 --base main
  strip_ansi_output
  assert_output --partial "GH-CALL: pr create --head release-1.2.5 --base main"
  assert_output --partial "Opened release PR"
}

@test "pr: do-pr noop when DO_PR unset" {
  source ${profile_script}
  unset DO_PR
  run do-pr
  assert_success
  refute_output --partial "gh pr create"
}

@test "completions: bash completion lists --pr / --branch / --base" {
  run ${profile_script} --completions bash
  assert_success
  assert_output --partial "--pr"
  assert_output --partial "--branch"
  assert_output --partial "--base"
}

@test "completions: zsh completion lists --pr" {
  run ${profile_script} --completions zsh
  assert_success
  assert_output --partial "--pr"
}

@test "completions: fish completion lists --pr" {
  run ${profile_script} --completions fish
  assert_success
  assert_output --partial "-l pr"
}
