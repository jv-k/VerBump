#!/usr/bin/env bats

# check-remote-sync (R-SAFE-5..9, issue #58): fetch (with tags) from the
# configured PUSH_DEST remote during Verify, refuse a behind-upstream HEAD,
# and — because the fetch runs BEFORE check-tag-exists — surface remote-only
# tag collisions preflight instead of at push time. All remotes in these
# tests are local bare repos, so fetch failures are instant and no network
# is touched.

load 'test_helper'

# Scratch repo with a committed package.json, a local bare "origin" remote,
# and the current branch pushed with upstream tracking configured.
synced_repo() {
  local repo remote
  repo="$(scratch_repo)"
  cd "$repo" || exit 1
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"

  remote=$(mktemp -d)
  CLEANUP_CMDS+=("rm -rf ${remote}")
  git init -q --bare "$remote"
  git remote add origin "$remote"
  git push -qu origin "$(git symbolic-ref --short HEAD)" 2>/dev/null
}

@test "remote-sync: tag existing only on the remote -> 3 before any file writes (R-SAFE-7)" {
  synced_repo
  # Put v1.0.1 on the remote but not locally.
  git tag v1.0.1
  git push -q origin v1.0.1
  git tag -d v1.0.1 >/dev/null

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_failure 3
  strip_ansi_output
  assert_output --partial "A release with that tag"
  # Nothing was previewed/mutated after the failure.
  refute_output --partial "[dry-run] would"
}

@test "remote-sync: branch behind upstream -> 3 (R-SAFE-6)" {
  synced_repo
  git commit -q --allow-empty -m "feat: newer work"
  git push -q origin HEAD
  git reset -q --hard HEAD~1   # local is now 1 behind origin

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_failure 3
  strip_ansi_output
  assert_output --partial "behind"
  assert_output --partial "git pull --rebase"
}

@test "remote-sync: no remote configured -> proceeds silently, no fetch attempted" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_success
  strip_ansi_output
  refute_output --partial "Could not fetch"
}

@test "remote-sync: unreachable remote URL -> warning, run proceeds (R-SAFE-5)" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf '{ "version": "1.0.0" }\n' > package.json
  git add package.json && git commit -qm "chore: seed package.json"
  git remote add origin /nonexistent/verbump-remote.git

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_success
  strip_ansi_output
  assert_output --partial "Could not fetch"
}

@test "remote-sync: diverged local tag -> warning explains the clobber, run proceeds" {
  synced_repo
  # Same tag name on both sides but pointing at different commits: v1.0.1 on
  # the remote, then moved locally to a newer commit. A --tags fetch would have
  # to overwrite the local tag, which git refuses ("would clobber existing
  # tag") and the whole fetch exits non-zero.
  git tag v1.0.1
  git push -q origin v1.0.1
  git commit -q --allow-empty -m "feat: newer work"
  git push -q origin HEAD
  git tag -f v1.0.1 >/dev/null   # local v1.0.1 now differs from the remote's

  run ${profile_script} -d -b -c -p origin -v 1.0.2
  assert_success
  strip_ansi_output
  assert_output --partial "Could not fetch"
  assert_output --partial "local tags differ"
  assert_output --partial "git fetch origin --tags --force"
}

@test "remote-sync: --no-fetch skips the preflight — remote-only collision undetected (R-SAFE-8)" {
  synced_repo
  git tag v1.0.1
  git push -q origin v1.0.1
  git tag -d v1.0.1 >/dev/null

  # Documented tradeoff: with --no-fetch the remote-only tag is invisible to
  # the preflight, so the dry-run pipeline sails through.
  run ${profile_script} -d -b -c -p origin -v 1.0.1 --no-fetch
  assert_success
}

@test "remote-sync: --no-fetch live run still fails safely at push time" {
  synced_repo
  git tag v1.0.1
  git push -q origin v1.0.1
  git tag -d v1.0.1 >/dev/null

  # Live run: the collision only surfaces at the push, which now fails the
  # run with exit 1 (R-FLOW-8) and keeps the local commit and tag.
  run ${profile_script} -c -p origin -v 1.0.1 --no-fetch
  assert_failure 1
  strip_ansi_output
  assert_output --partial "Push to <origin> failed"
  assert_output --partial "git push -u origin main v1.0.1"
}

@test "remote-sync: NO_FETCH=true in .verbumprc skips the preflight" {
  synced_repo
  printf 'NO_FETCH=true\n' > .verbumprc
  git tag v1.0.1
  git push -q origin v1.0.1
  git tag -d v1.0.1 >/dev/null

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_success
}

@test "remote-sync: behind-upstream check passes when in sync" {
  synced_repo

  run ${profile_script} -d -b -c -p origin -v 1.0.1
  assert_success
}

@test "remote-sync: fetch runs under --dry-run and makes remote tags visible (R-SAFE-9)" {
  synced_repo
  git tag v9.9.9
  git push -q origin v9.9.9
  git tag -d v9.9.9 >/dev/null

  # The dry-run fetch is read-only but real: after the failed preflight the
  # remote tag now exists locally (proof the fetch actually ran).
  run ${profile_script} -d -b -c -p origin -v 9.9.9
  assert_failure 3
  run git tag -l v9.9.9
  assert_output "v9.9.9"
}

@test "remote-sync: unit — no upstream configured skips the behind check" {
  source ${profile_script}
  synced_repo
  git checkout -qb no-upstream-branch

  PUSH_DEST=origin run check-remote-sync
  assert_success
}

@test "remote-sync: completions list --no-fetch in bash/zsh/fish" {
  run ${profile_script} --completions bash
  assert_success
  assert_output --partial -- "--no-fetch"
  run ${profile_script} --completions zsh
  assert_success
  assert_output --partial -- "--no-fetch"
  run ${profile_script} --completions fish
  assert_success
  assert_output --partial -- "-l no-fetch"
}
