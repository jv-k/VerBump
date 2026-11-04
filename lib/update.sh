#!/bin/bash

# shellcheck disable=SC2288
true

# --update [version] — update VerBump in place (R-UPD-1..5).
#
# VerBump ships through four channels, and only one of them is VerBump's to
# update. The channel is read from where the running script lives
# (MODULE_DIR, already realpath-resolved by the entrypoint):
#
#   git     a source checkout          → the user owns it: 'git pull'
#   brew    …/Cellar/verbump/…         → brew owns it:     'brew upgrade'
#   npm     …/node_modules/@jv-k/verbump → npm owns it:    'npm install -g'
#   curl    <prefix>/share/verbump     → ours: re-run the installer
#   unknown anything else              → re-run the curl one-liner
#
# Only the curl channel is updated in place, and it goes through the same
# checksummed install.sh path as a fresh install: the release tarball ships
# install.sh beside verbump.sh, so the update never pipes unverified code
# from the network into bash. The other channels exit 3 with the command
# that does update them — running another tool's package manager on the
# user's behalf would be a surprise mutation (ADR-15: the network call is
# opt-in because the user typed --update).

VB_UPDATE_REPO_SLUG="jv-k/VerBump"
VB_UPDATE_NPM_PKG="@jv-k/verbump"
VB_UPDATE_BREW_FORMULA="jv-k/tap/verbump"

# detect-install-channel <dir> — print git | brew | npm | curl | unknown for
# a VerBump tree at <dir>. Pure path inspection, so it is table-testable.
# A source checkout wins first: a clone placed under a Cellar or
# node_modules path is still the user's checkout, not a package.
detect-install-channel() {
  local dir=$1
  if [ -e "$dir/.git" ]; then
    printf 'git\n'
    return 0
  fi
  case "$dir" in
    */Cellar/verbump/*)                printf 'brew\n' ;;
    */node_modules/@jv-k/verbump|*/node_modules/@jv-k/verbump/*)
                                       printf 'npm\n' ;;
    */share/verbump)                   printf 'curl\n' ;;
    *)                                 printf 'unknown\n' ;;
  esac
}

# _update-read-version <dir> — the "version" field of <dir>/package.json,
# parsed with bash alone so --update works even where jq is missing (the
# installer it drives has no jq dependency either). Prints "unknown" when
# the field cannot be read: the version is shown to the user, never acted on.
_update-read-version() {
  local line re='"version"[[:space:]]*:[[:space:]]*"([^"]+)"'
  if [ -f "$1/package.json" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ $re ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
      fi
    done < "$1/package.json"
  fi
  printf 'unknown\n'
}

# _update-run-installer <installer> <args…> — the single process seam. Tests
# override this function so the suite never touches the network.
_update-run-installer() {
  bash "$@"
}

# do-update [version] — entry point for --update. An empty <version> means
# the latest stable release; a leading "v" is accepted (tags are v-prefixed).
# Honours FLAG_DRYRUN, which the pre-scan in normalize-long-opts sets.
do-update() {
  local want=${1-} channel from to prefix installer tmp rc
  local -a args

  want="${want#v}"
  if [ -n "$want" ] && ! is_semver "$want"; then
    fail 2 \
      "--update: not a valid SemVer 2.0 version: '${want}'." \
      "Pass a release version, e.g. 'verbump --update 4.2.0', or drop the version to get the latest release."
  fi

  channel=$(detect-install-channel "$MODULE_DIR")
  from=$(_update-read-version "$MODULE_DIR")

  case "$channel" in
    git)
      fail 3 \
        "VerBump is running from a git checkout (${MODULE_DIR}), so --update will not change it." \
        "Run 'git -C \"${MODULE_DIR}\" pull' to update the checkout."
      ;;
    brew)
      fail 3 \
        "VerBump was installed with Homebrew, so Homebrew must update it." \
        "Run 'brew upgrade ${VB_UPDATE_BREW_FORMULA}'."
      ;;
    npm)
      fail 3 \
        "VerBump was installed from npm, so your package manager must update it." \
        "Run 'npm install -g ${VB_UPDATE_NPM_PKG}@${want:-latest}', or 'pnpm add -g ${VB_UPDATE_NPM_PKG}@${want:-latest}' for a pnpm install."
      ;;
    unknown)
      fail 3 \
        "VerBump cannot tell how it was installed (${MODULE_DIR}), so it cannot update itself." \
        "Re-run the installer: curl -fsSL https://raw.githubusercontent.com/${VB_UPDATE_REPO_SLUG}/main/install.sh | bash"
      ;;
  esac

  # curl channel: MODULE_DIR is <prefix>/share/verbump.
  prefix="${MODULE_DIR%/share/verbump}"
  installer="$MODULE_DIR/install.sh"
  if [ ! -f "$installer" ]; then
    fail 3 \
      "This install has no copy of install.sh, so it cannot update itself." \
      "Re-run the installer once: curl -fsSL https://raw.githubusercontent.com/${VB_UPDATE_REPO_SLUG}/main/install.sh | bash"
  fi

  args=(--prefix "$prefix")
  [ -n "$want" ] && args+=(--version "$want")

  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    printf '%b[dry-run]%b would run: bash %s %s\n' \
      "${S_LIGHT-}" "${RESET-}" "$installer" "${args[*]}" >&2
    log_success "VerBump ${S_VAL-}${from}${RESET-} would update to ${S_VAL-}${want:-the latest release}${RESET-} (dry-run)"
    return 0
  fi

  # Run a copy, not the file itself: the installer swaps out the very
  # directory it lives in. The env pin is cleared so a stray
  # VERBUMP_INSTALL_VERSION in the user's shell can't override "latest";
  # an explicit pin travels as --version, which the installer prefers anyway.
  tmp=$(mktemp "${TMPDIR:-/tmp}/verbump-update.XXXXXX") || \
    fail 1 "--update could not create a temporary file." \
           "Check that \$TMPDIR (or /tmp) is writable, then re-run 'verbump --update'."
  if ! cp "$installer" "$tmp"; then
    rm -f "$tmp"
    fail 1 "--update could not copy the installer to ${tmp}." \
           "Check that \$TMPDIR (or /tmp) is writable, then re-run 'verbump --update'."
  fi

  rc=0
  VERBUMP_INSTALL_VERSION="" VERBUMP_PREFIX="" \
    _update-run-installer "$tmp" "${args[@]}" || rc=$?
  rm -f "$tmp"

  if [ "$rc" -ne 0 ]; then
    fail "$rc" \
      "--update failed: the installer exited with code ${rc}." \
      "The installer keeps your previous install when it fails; its message is above. Re-run 'verbump --update' to retry."
  fi

  to=$(_update-read-version "$MODULE_DIR")
  if [ "$to" = "$from" ]; then
    log_success "VerBump ${S_VAL-}${to}${RESET-} was already installed; the version is unchanged"
  else
    log_success "Updated VerBump ${S_VAL-}${from}${RESET-} → ${S_VAL-}${to}${RESET-}"
  fi
}
