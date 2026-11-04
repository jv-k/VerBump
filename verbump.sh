#!/bin/bash
#  _ _  ___  ___       ___  _ _  __ __  ___
# | | || __>| . \ ___ | . >| | ||  \  \| . \
# | ' || _> |   /|___|| . \| ' ||     ||  _/
# |__/ |___>|_\_\     |___/\___/|_|_|_||_|
#
# Author:
#   John Valai <git@jvk.to>
# Homepage: 
#   https://github.com/jv-k/VerBump
#
# Description:
#   An opinionated release tool for Git projects with a `package.json` —
#   primarily Node / JS / TS projects, but also usable for any SemVer repo:
#   `--source <file>.json` swaps the version source / bump target, and with
#   no version file at all the current version is derived from the latest
#   release tag. It automates the mechanical
#   parts of cutting a release (SemVer bump, CHANGELOG, release branch,
#   tag, push), driven by Conventional Commits, and leaves the integration
#   step (merge back to `develop` / `main`) to the human.
#

# shellcheck disable=SC1090,SC2034,SC1017
true

MODULE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

source "$MODULE_DIR/lib/icons.sh"
source "$MODULE_DIR/lib/errors.sh"
source "$MODULE_DIR/lib/ui.sh"
source "$MODULE_DIR/lib/validate.sh"
source "$MODULE_DIR/lib/json.sh"
source "$MODULE_DIR/lib/effects.sh"
source "$MODULE_DIR/lib/textbump.sh"

source "$MODULE_DIR/lib/usage.sh"
source "$MODULE_DIR/lib/completions.sh"
source "$MODULE_DIR/lib/update.sh"
source "$MODULE_DIR/lib/args.sh"

source "$MODULE_DIR/lib/git-checks.sh"
source "$MODULE_DIR/lib/version.sh"
source "$MODULE_DIR/lib/changelog.sh"
source "$MODULE_DIR/lib/git-actions.sh"
source "$MODULE_DIR/lib/hooks.sh"

source "$MODULE_DIR/lib/config.sh"

NOW="$(date +%F)"

V_SUGGEST="0.1.0" # This is suggested in case VERSION file or user supplied version via -v is missing
GIT_MSG=""
REL_NOTE=""
FLAG_DRYRUN=false
FLAG_QUIET=false # -q/--quiet: decoration to stderr, bare new version on stdout (R-OUT-1). CLI-only; reset in process-arguments.
FLAG_JSON=false # --json: with --dry-run, emit the release plan as one JSON object on stdout (R-OUT-5). CLI-only; reset in process-arguments.
# VB_EFFECTS (declared in lib/effects.sh): JSON-array text of recorded release
# effects for --json; reset per run in process-arguments via reset-effects.
# VB_RC_DIR / VB_SCOPE_ACTIVE / VB_SCOPE_PATHS / VB_SCOPE_REL (declared in
# lib/config.sh): the package scope resolved from COMMIT_PATHS (R-MONO-1) —
# active only when narrower than the repo root; scoped call sites check
# VB_SCOPE_ACTIVE so whole-repo runs stay byte-identical.

# Config-keyed defaults use `:=` so exported env values survive. An
# unconditional assignment (e.g. `TAG_PREFIX="v"`) would clobber
# `export TAG_PREFIX=from-env` here — load-config's env-vs-file snapshot
# would then see the default, and env would silently lose to .verbumprc.
# apply-config-defaults (lib/config.sh) is the canonical source of defaults;
# these `:=` lines just keep sourcing verbump.sh directly (from tests) sane.
: "${REL_PREFIX:=release-}"
: "${TAG_PREFIX:=v}"
: "${COMMIT_MSG_PREFIX:=chore: }" # Commit msg prefix for the file changes this script makes
: "${PUSH_DEST:=origin}"
: "${CHANGELOG_STYLE:=flat}" # CHANGELOG.md style: flat (1.x-identical, default) | grouped
: "${SOURCE_FILE:=package.json}" # Version source + primary bump target (R-SRC-1/5)

# Internal alias for the resolved version source. Everything downstream reads
# VER_FILE; main() re-derives it from SOURCE_FILE once config + CLI are final.
VER_FILE="$SOURCE_FILE"

JSON_FILES=()

# --bump specs collected from the CLI (repeatable). Merged with the newline-
# separated BUMP_FILES config/env key by resolve-bump-targets (lib/textbump.sh).
BUMP_TARGETS=()

# ── Initiate Script ────────────────────────────────────────────────────

main() {
  # Load .verbumprc (if any) and apply defaults BEFORE parsing CLI args.
  # Precedence: CLI (process-arguments below) > env (preserved in load-config)
  #             > file (.verbumprc) > default (apply-config-defaults).
  load-config
  apply-config-defaults

  # Process and prepare
  process-arguments "$@"
  # SOURCE_FILE is final here (CLI --source > env > .verbumprc > default);
  # point the internal VER_FILE alias at it (R-SRC-1/5).
  VER_FILE="$SOURCE_FILE"
  check-dependencies
  check-release-deps
  check-bump-deps # validate --bump / BUMP_FILES specs + conditional tomlq/yq (R-TGT-4)
  resolve-commit-scope # package scope from COMMIT_PATHS — precedence is final here (R-MONO-1)

  section "Verify"
  check-commits-exist
  check-worktree-clean
  check-release-branch
  check-remote-sync # must precede check-tag-exists so remote tags are visible
  process-version
  check-releasable-commits # needs V_PREV + TAG_PREFIX, so after process-version
  check-branch-notexist
  check-tag-exists
  check-pr-deps

  section "Release"
  run-pre-bump-hook # PRE_BUMP_CMD: all preflights passed, nothing mutated yet (R-HOOK-1)
  do-packagefile-bump
  bump-json-files
  bump-target-files # --bump / BUMP_FILES: non-JSON + arbitrary-path targets (R-TGT)
  do-versionfile
  do-changelog
  do-branch
  do-commit
  do-tag
  run-post-tag-hook # POST_TAG_CMD: tag exists, nothing pushed yet (R-HOOK-2)
  do-push
  do-pr
  do-github-release

  section "Done"
  log_success "$( capitalise "$( get-commit-msg )" )"
  echo

  # Machine-readable success line (R-OUT-1): under --quiet, FD 3 is the real
  # stdout saved by process-arguments (everything else was rerouted to
  # stderr), and it receives exactly one line — the new version, bare: no
  # tag prefix, no colour. A no-op run never reaches this point
  # (check-releasable-commits exits 0 first), so quiet stdout stays empty
  # for "no release happened" (R-OUT-4).
  # Under --json the payload owns stdout: the bare-version line is skipped
  # (its information lives at .version.to), so `--quiet --json` still yields
  # a stream that is exactly one JSON object.
  if [ "$FLAG_QUIET" = true ] && [ "$FLAG_JSON" != true ]; then
    printf '%s\n' "$V_NEW" >&3
  fi

  # --dry-run --json: one JSON object with the recorded release plan on FD 3
  # (R-OUT-5). Self-guarded — a no-op without --json.
  emit-effects-json
}

# Execute script when it is executed as a script, and when it is brought into the environment with source (so it can be tested)
# shellcheck disable=SC2128
if [[ "$0" = "$BASH_SOURCE" ]]; then
  source "$MODULE_DIR/lib/styles.sh" # only load when not sourced, for tests to work
  main "$@"
fi
