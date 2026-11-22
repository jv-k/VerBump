#!/usr/bin/env bats

# --release flag: publish a GitHub release for the newly-created tag via the
# `gh` CLI. Notes default to `gh release create --generate-notes`; setting
# $VERBUMP_RELEASE_NOTES_CMD captures that command's stdout via --notes.
# Conditional dependency — `gh` is only required when --release is passed (a
# custom notes command may add more); the default VerBump path stays
# bash + git + jq only.

load 'test_helper'

@test "release: process-arguments sets DO_RELEASE=true" {
  source ${profile_script}
  process-arguments --release
  assert_equal "${DO_RELEASE}" "true"
}

@test "release: --release=value is rejected" {
  source ${profile_script}
  run process-arguments --release=yes
  assert_failure 2
  assert_output --partial "Option --release doesn't take a value"
}

@test "release: --release without -p exits 2" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  run ${profile_script} --release -d -b -c -v 1.0.1
  assert_failure 2
  strip_ansi_output
  assert_output --partial "--release requires"
}

@test "release: --release with -p but gh missing exits 3" {
  source ${profile_script}
  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  # PATH contains git + jq but no gh
  cat > "${shim}/git" <<'SH'
#!/bin/sh
exec /usr/bin/env git "$@"
SH
  cat > "${shim}/jq" <<'SH'
#!/bin/sh
exec /usr/bin/env jq "$@"
SH
  chmod +x "${shim}/git" "${shim}/jq"

  DO_RELEASE=true FLAG_PUSH=true PATH="${shim}" run check-release-deps
  assert_failure 3
  assert_output --partial "gh"
}

@test "release: --release --dry-run -p origin -v 1.2.3 prints resolved gh release create" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='printf %s STUB-NOTES' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_success
  strip_ansi_output
  assert_output --partial "[dry-run]"
  assert_output --partial "gh release create v1.2.3"
  assert_output --partial "STUB-NOTES"
}

@test "release: default notes path uses gh --generate-notes (dry-run preview)" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_success
  strip_ansi_output
  assert_output --partial "gh release create v1.2.3"
  assert_output --partial "--generate-notes"
  refute_output --partial "--notes"
}

@test "release: --release --dry-run leaves working tree byte-identical" {
  local repo before after
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"
  git add package.json && git commit -qm "seed"

  before=$(git status --porcelain)
  VERBUMP_RELEASE_NOTES_CMD='echo NOTES' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_success
  after=$(git status --porcelain)
  assert_equal "$before" "$after"
}

@test "release: VERBUMP_RELEASE_NOTES_CMD override surfaces custom output" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='echo CUSTOM-NOTES-MARKER' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_success
  strip_ansi_output
  assert_output --partial "CUSTOM-NOTES-MARKER"
}

@test "release: notes-cmd failure exits 1 and skips gh call" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='false' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_failure 1
  strip_ansi_output
  assert_output --partial "release notes command failed"
  refute_output --partial "gh release create"
}

@test "release: do-github-release noop when DO_RELEASE unset" {
  source ${profile_script}
  unset DO_RELEASE
  run do-github-release
  assert_success
  refute_output --partial "gh release create"
}

@test "release: do-github-release noop when FLAG_NOCOMMIT=true" {
  source ${profile_script}
  DO_RELEASE=true FLAG_NOCOMMIT=true FLAG_DRYRUN=true \
    V_NEW="1.2.3" TAG_PREFIX="v" run do-github-release
  assert_success
  refute_output --partial "gh release create"
}

@test "completions: bash completion lists --release" {
  run ${profile_script} --completions bash
  assert_success
  assert_output --partial "--release"
}

@test "completions: zsh completion lists --release" {
  run ${profile_script} --completions zsh
  assert_success
  assert_output --partial "--release"
}

@test "completions: fish completion lists --release" {
  run ${profile_script} --completions fish
  assert_success
  assert_output --partial "-l release"
}

# ── Pass-2 review regression tests: release-pipeline safety ─────────────

@test "release: --release with -n / --no-commit exits 2" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  run ${profile_script} --release -p origin -n -v 1.0.1
  assert_failure 2
  strip_ansi_output
  assert_output --partial "incompatible with -n"
}

@test "release: gh present but unauthenticated exits 3" {
  source ${profile_script}
  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 1
exit 0
SH
  chmod +x "${shim}/gh"

  DO_RELEASE=true FLAG_PUSH=true FLAG_DRYRUN=false PATH="${shim}:$PATH" \
    run check-release-deps
  assert_failure 3
  assert_output --partial "authenticated"
}

@test "release: --dry-run skips the gh auth check" {
  source ${profile_script}
  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 1
exit 0
SH
  chmod +x "${shim}/gh"

  DO_RELEASE=true FLAG_PUSH=true FLAG_DRYRUN=true PATH="${shim}:$PATH" \
    run check-release-deps
  assert_success
}

@test "release: a failed push skips the GitHub release" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"
  git add package.json && git commit -qm "feat: seed"

  local shim
  shim=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${shim}")
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 0
echo "GH-RELEASE-CALLED $*"
exit 0
SH
  chmod +x "${shim}/gh"

  # 'origin' is not configured, so the push fails. Live run (no -d).
  PATH="${shim}:$PATH" VERBUMP_RELEASE_NOTES_CMD='echo NOTES' \
    run ${profile_script} --release -p origin -b -c -v 1.2.5
  assert_failure 1
  strip_ansi_output
  assert_output --partial "Push to <origin> failed"
  # The hint names the command that publishes the release once the push works.
  assert_output --partial "gh release create v1.2.5"
  refute_output --partial "GH-RELEASE-CALLED"
}

@test "release: live path runs gh release create with tag + notes" {
  local repo remote
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"
  git add package.json && git commit -qm "feat: seed"

  remote=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "${remote}"

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

  PATH="${shim}:$PATH" VERBUMP_RELEASE_NOTES_CMD='printf %s LIVE-NOTES' \
    run ${profile_script} --release -p "${remote}" -b -c -v 1.2.5
  strip_ansi_output
  assert_output --partial "GH-CALL: release create v1.2.5"
  assert_output --partial "LIVE-NOTES"
  assert_output --partial "Published GitHub release"
}

@test "release: live default path runs gh release create with --generate-notes" {
  local repo remote
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"
  git add package.json && git commit -qm "feat: seed"

  remote=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "${remote}"

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

  PATH="${shim}:$PATH" VERBUMP_RELEASE_NOTES_CMD='' \
    run ${profile_script} --release -p "${remote}" -b -c -v 1.2.5
  strip_ansi_output
  assert_output --partial "GH-CALL: release create v1.2.5"
  assert_output --partial "--generate-notes"
  assert_output --partial "Published GitHub release"
}

# ── Pass-2 review regression tests: prerelease handling ─────────────────

@test "release: prerelease version adds --prerelease (dry-run preview)" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='printf %s NOTES' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3-rc.1
  assert_success
  strip_ansi_output
  assert_output --partial "gh release create v1.2.3-rc.1"
  assert_output --partial "--prerelease"
}

@test "release: stable version omits --prerelease (dry-run preview)" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  VERBUMP_RELEASE_NOTES_CMD='printf %s NOTES' \
    run ${profile_script} --release -d -b -c -p origin -v 1.2.3
  assert_success
  strip_ansi_output
  refute_output --partial "--prerelease"
}
