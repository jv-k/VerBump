#!/usr/bin/env bats

# Config file loader (.verbumprc) — Task 1.1 of the v2.0 Foundation.
# Covers walk-up discovery, safety (world-writable refusal), and the
# precedence chain CLI > env > file > default. Shared setup lives in
# test/test_helper.bash.

load 'test_helper'

# Helpers ######################################################################

# Clear every CLI-settable config key from the env inside the bats harness
# itself, so our tests can assert "default" paths deterministically. Does NOT
# unset the generic shell-inherited ones (those never are).
_clear_config_env() {
  unset TAG_PREFIX REL_PREFIX PUSH_DEST COMMIT_MSG_PREFIX COMMIT_MSG_TEMPLATE \
        CHANGELOG_STYLE FLAG_NOBRANCH FLAG_NOCHANGELOG FLAG_CHANGELOG_PAUSE
}

# Absent file ##################################################################

@test "load-config: absent .verbumprc is a silent no-op" {
  source ${profile_script}
  cd "$(scratch_repo)"
  _clear_config_env

  run load-config
  assert_success
  refute_output
}

# Discovery ####################################################################

@test "load-config: finds .verbumprc at repo root" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  printf 'TAG_PREFIX=x\n' > "$repo/.verbumprc"

  load-config
  assert_equal "$TAG_PREFIX" "x"
}

# Unknown-key heuristic warning (ADR-05, R-CFG-7) ##############################

@test "load-config: warns (non-fatal) on an unknown .verbumprc key" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  printf 'TAG_PREFIX=ok\nTAG_PREFX=typo\n' > "$repo/.verbumprc"

  run load-config
  assert_success
  strip_ansi_output
  assert_output --partial "Unknown .verbumprc key 'TAG_PREFX'"
  refute_output --partial "key 'TAG_PREFIX'"
}

@test "load-config: all-known keys (incl. deprecated) emit no unknown-key warning" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  printf 'TAG_PREFIX=v\nREL_PREFIX=rel-\nFLAG_NOBRANCH=true\n' > "$repo/.verbumprc"

  run load-config
  assert_success
  refute_output --partial "Unknown .verbumprc key"
}

@test "load-config: walks up to find .verbumprc in an ancestor directory" {
  source ${profile_script}
  local repo sub
  repo="$(scratch_repo)"
  printf 'TAG_PREFIX=ancestor-v\nREL_PREFIX=ancestor-rel-\n' > "$repo/.verbumprc"

  sub="$repo/nested/deeper"
  mkdir -p "$sub"
  cd "$sub"
  _clear_config_env

  load-config
  assert_equal "$TAG_PREFIX" "ancestor-v"
  assert_equal "$REL_PREFIX" "ancestor-rel-"
}

# Precedence ###################################################################

@test "load-config: env wins over file" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"

  _clear_config_env
  printf 'TAG_PREFIX=file-value\n' > "$repo/.verbumprc"
  export TAG_PREFIX="env-wins"
  CLEANUP_CMDS+=("unset TAG_PREFIX")

  load-config
  assert_equal "$TAG_PREFIX" "env-wins"
}

@test "apply-config-defaults: file value beats default when neither env nor CLI set it" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  printf 'TAG_PREFIX=T-from-file\n' > "$repo/.verbumprc"

  load-config
  apply-config-defaults
  assert_equal "$TAG_PREFIX" "T-from-file"
}

@test "apply-config-defaults: supplies the builtin defaults when nothing sets the keys" {
  source ${profile_script}
  cd "$(scratch_repo)"
  _clear_config_env

  load-config
  apply-config-defaults
  assert_equal "$TAG_PREFIX" "v"
  assert_equal "$REL_PREFIX" "release-"
  assert_equal "$PUSH_DEST" "origin"
  assert_equal "$COMMIT_MSG_PREFIX" "chore: "
  assert_equal "$CHANGELOG_STYLE" "flat"
  # Tag-in-place is the default; the release branch is opt-in.
  assert_equal "$FLAG_BRANCH" "false"
}

@test "verbump.sh: CLI -t beats .verbumprc TAG_PREFIX (end-to-end dry-run)" {
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  printf 'TAG_PREFIX=from-file\n' > "$repo/.verbumprc"
  # Need a package.json with a version so process-version is happy
  printf '{ "version": "1.0.0" }\n' > "$repo/package.json"

  # Non-interactive end-to-end dry run: -v avoids the interactive prompt,
  # -d dry-run means nothing is actually written/committed/pushed, -b -c
  # skip branch + changelog so we get past check-branch-notexist. -p origin
  # makes do-push non-interactive. The "git tag -a" dry-run line is what
  # carries TAG_PREFIX and is what we assert against.
  run ${profile_script} -d -b -c -p origin -t y -v 1.0.1
  strip_ansi_output
  assert_success
  # With TAG_PREFIX=y the dry-run tag line should show "y1.0.1", not "from-file1.0.1"
  assert_output --partial "git tag -a y1.0.1"
  refute_output --partial "from-file1.0.1"
}

# Safety #######################################################################

@test "load-config: refuses world-writable .verbumprc (exit code 3)" {
  source ${profile_script}
  local repo rc
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  rc="$repo/.verbumprc"
  printf 'TAG_PREFIX=unsafe\n' > "$rc"
  # Force-set o+w; use 666 to bypass any umask stripping on macOS.
  chmod 666 "$rc"
  # Sanity-check the permission actually took (guards against weird FS).
  [ "$(stat -c '%a' "$rc" 2>/dev/null || stat -f '%Lp' "$rc" 2>/dev/null)" = "666" ]

  CLEANUP_CMDS+=("chmod 644 '$rc' 2>/dev/null || true")

  run load-config
  assert_failure 3
  assert_output --partial "world-writable"
  assert_output --partial " HINT "
}

@test "load-config: refuses group-writable .verbumprc (exit code 3)" {
  source ${profile_script}
  local repo rc
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  rc="$repo/.verbumprc"
  printf 'TAG_PREFIX=unsafe\n' > "$rc"
  chmod 664 "$rc"
  [ "$(stat -c '%a' "$rc" 2>/dev/null || stat -f '%Lp' "$rc" 2>/dev/null)" = "664" ]

  CLEANUP_CMDS+=("chmod 644 '$rc' 2>/dev/null || true")

  run load-config
  assert_failure 3
  assert_output --partial "group-writable"
  assert_output --partial " HINT "
}

@test "load-config: refuses .verbumprc not owned by current user (exit code 3)" {
  # Needs root to chown to another user; skip unless available.
  if [ "$(id -u)" != "0" ] && ! command -v sudo >/dev/null 2>&1; then
    skip "needs root or sudo to chown to a different user"
  fi
  # Pick a uid that isn't ours. 'nobody' is uid 65534 on most *nixes,
  # but on macOS it's -2 (4294967294). Resolve via id if present.
  local other_uid
  other_uid=$(id -u nobody 2>/dev/null || echo 65534)
  [ "$other_uid" != "$(id -u)" ] || skip "cannot find a non-self uid"

  source ${profile_script}
  local repo rc
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  rc="$repo/.verbumprc"
  printf 'TAG_PREFIX=unsafe\n' > "$rc"
  # shellcheck disable=SC2015
  if [ "$(id -u)" = "0" ]; then
    chown "$other_uid" "$rc" || skip "chown failed"
  else
    sudo -n chown "$other_uid" "$rc" 2>/dev/null || skip "passwordless sudo not available"
  fi
  CLEANUP_CMDS+=("sudo -n chown $(id -u) '$rc' 2>/dev/null || chown $(id -u) '$rc' 2>/dev/null || true")

  run load-config
  assert_failure 3
  assert_output --partial "not owned by the current user"
  assert_output --partial " HINT "
}

# Round-trip all keys ##########################################################

@test "load-config: round-trips every supported key from the file" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  _clear_config_env

  cat > "$repo/.verbumprc" <<'EOF'
TAG_PREFIX=rel/
REL_PREFIX=hotfix-
PUSH_DEST=upstream
COMMIT_MSG_PREFIX="release: "
CHANGELOG_STYLE=grouped
FLAG_NOBRANCH=true
FLAG_NOCHANGELOG=true
FLAG_CHANGELOG_PAUSE=true
EOF

  load-config
  assert_equal "$TAG_PREFIX" "rel/"
  assert_equal "$REL_PREFIX" "hotfix-"
  assert_equal "$PUSH_DEST" "upstream"
  assert_equal "$COMMIT_MSG_PREFIX" "release: "
  assert_equal "$CHANGELOG_STYLE" "grouped"
  assert_equal "$FLAG_NOBRANCH" "true"
  assert_equal "$FLAG_NOCHANGELOG" "true"
  assert_equal "$FLAG_CHANGELOG_PAUSE" "true"
}

# Notes agent keys (#162, ADR-24) ##############################################

@test "load-config: round-trips RELEASE_NOTES_AGENT and RELEASE_NOTES_PROMPT" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  unset RELEASE_NOTES_AGENT RELEASE_NOTES_PROMPT

  cat > "$repo/.verbumprc" <<'RC'
RELEASE_NOTES_AGENT="gemini -p"
RELEASE_NOTES_PROMPT="Group changes by user impact."
RC

  run load-config
  assert_success
  refute_output --partial "Unknown .verbumprc key"

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT" "gemini -p"
  assert_equal "$RELEASE_NOTES_PROMPT" "Group changes by user impact."
}

@test "load-config: env RELEASE_NOTES_AGENT and RELEASE_NOTES_PROMPT win over the file" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"

  printf 'RELEASE_NOTES_AGENT=from-file\nRELEASE_NOTES_PROMPT=from-file\n' > "$repo/.verbumprc"
  export RELEASE_NOTES_AGENT=from-env RELEASE_NOTES_PROMPT=from-env
  CLEANUP_CMDS+=("unset RELEASE_NOTES_AGENT RELEASE_NOTES_PROMPT")

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT" "from-env"
  assert_equal "$RELEASE_NOTES_PROMPT" "from-env"
}

@test "apply-config-defaults: RELEASE_NOTES_AGENT defaults to off" {
  source ${profile_script}
  cd "$(scratch_repo)"
  unset RELEASE_NOTES_AGENT RELEASE_NOTES_PROMPT

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT" "off"
  assert_equal "${RELEASE_NOTES_PROMPT-}" ""
}

@test "load-config: a misspelt notes-agent key gets the unknown-key warning" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"

  printf 'RELEASE_NOTE_AGENT=auto\nRELEASE_NOTES_PROMT=x\n' > "$repo/.verbumprc"

  run load-config
  assert_success
  strip_ansi_output
  assert_output --partial "Unknown .verbumprc key 'RELEASE_NOTE_AGENT'"
  assert_output --partial "Unknown .verbumprc key 'RELEASE_NOTES_PROMT'"
}

# Notes agent timeout key (#163, ADR-24) #######################################

@test "load-config: round-trips RELEASE_NOTES_AGENT_TIMEOUT without the unknown-key warning" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"
  unset RELEASE_NOTES_AGENT_TIMEOUT

  printf 'RELEASE_NOTES_AGENT_TIMEOUT=45\n' > "$repo/.verbumprc"

  run load-config
  assert_success
  strip_ansi_output
  refute_output --partial "Unknown .verbumprc key"

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT_TIMEOUT" "45"
}

@test "load-config: env RELEASE_NOTES_AGENT_TIMEOUT wins over the file" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"

  printf 'RELEASE_NOTES_AGENT_TIMEOUT=45\n' > "$repo/.verbumprc"
  export RELEASE_NOTES_AGENT_TIMEOUT=7
  CLEANUP_CMDS+=("unset RELEASE_NOTES_AGENT_TIMEOUT")

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT_TIMEOUT" "7"
}

@test "apply-config-defaults: RELEASE_NOTES_AGENT_TIMEOUT defaults to 120" {
  source ${profile_script}
  cd "$(scratch_repo)"
  unset RELEASE_NOTES_AGENT_TIMEOUT

  load-config
  apply-config-defaults
  assert_equal "$RELEASE_NOTES_AGENT_TIMEOUT" "120"
}

@test "load-config: a misspelt notes-agent timeout key gets the unknown-key warning" {
  source ${profile_script}
  local repo
  repo="$(scratch_repo)"
  cd "$repo"

  printf 'RELEASE_NOTES_AGENT_TIMOUT=30\n' > "$repo/.verbumprc"

  run load-config
  assert_success
  strip_ansi_output
  assert_output --partial "Unknown .verbumprc key 'RELEASE_NOTES_AGENT_TIMOUT'"
}
