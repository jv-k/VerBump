#!/bin/bash

# shellcheck disable=SC2288
true

# --update [version] — update VerBump in place (R-UPD-1..7).
#
# VerBump ships through several channels. The channel is read from where the
# running script lives (MODULE_DIR, already realpath-resolved by the
# entrypoint), and --update drives whatever tool owns that channel:
#
#   curl    <prefix>/share/verbump       → the install.sh shipped in the tree
#   brew    …/Cellar/verbump/…           → brew update + brew upgrade
#   npm     …/node_modules/@jv-k/verbump → npm, pnpm, yarn or bun, read from
#                                          the same path
#   git     a source checkout            → not touched: 'git pull' is printed
#   unknown anything else                → not touched: the one-liner is printed
#
# A git checkout is left alone on purpose: it may be the user's own working
# clone with local commits, and pulling it is not an "update" they asked for.
# The curl channel goes through the checksummed install.sh path that ships
# inside the release tarball, so the update never pipes unverified code from
# the network into bash. The network is touched only because the user typed
# --update (ADR-15).

VB_UPDATE_REPO_SLUG="jv-k/VerBump"
VB_UPDATE_NPM_PKG="@jv-k/verbump"
VB_UPDATE_BREW_FORMULA="jv-k/tap/verbump"

# detect-install-channel <dir> — print git | brew | npm | curl | unknown for
# a VerBump tree at <dir>. Pure path inspection, so it is table-testable.
# A source checkout wins first: a clone placed under a Cellar or
# node_modules path, or at the install script's ~/.local/share/verbump, is
# still the user's checkout, not a package.
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

# detect-node-manager <dir> — print pnpm | yarn | bun | npm for an npm-channel
# tree at <dir>. Each manager keeps its global packages under a path of its
# own; npm's plain lib/node_modules is the fallback. Updating with a
# different manager than the one that installed VerBump would leave two
# copies, with the old one still first on PATH.
detect-node-manager() {
  case "$1" in
    */.pnpm/*|*/pnpm/global/*)  printf 'pnpm\n' ;;
    */.bun/install/global/*)    printf 'bun\n' ;;
    */yarn/global/*)            printf 'yarn\n' ;;
    *)                          printf 'npm\n' ;;
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

# _update-path-version — the version of the `verbump` that is first on PATH,
# read by running it. A package manager may install the new version at a new
# path (Homebrew's Cellar/<version>, pnpm's store), so MODULE_DIR cannot be
# re-read; what the user's next `verbump` runs is the honest answer. Prints
# "unknown" when there is no verbump on PATH or its output can't be parsed.
_update-path-version() {
  local out
  if command -v verbump >/dev/null 2>&1 && \
     out=$(NO_COLOR=1 verbump --version 2>/dev/null) && \
     [[ "$out" =~ ^VerBump\ v?([^[:space:]]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf 'unknown\n'
  fi
}

# _update-exec <cmd…> — the single process seam. Every update command runs
# through it, so tests can stub the commands on PATH and assert on argv.
_update-exec() {
  "$@"
}

# _update-require-tool <tool> <channel label> <manual command> — fail 3 when
# the tool that owns the channel is not on PATH.
_update-require-tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  fail 3 \
    "VerBump was installed with ${2}, but '${1}' is not on your PATH." \
    "Put '${1}' on your PATH and re-run 'verbump --update', or run '${3}' yourself."
}

# _update-run <cmd…> — run one update command, or preview it under dry-run.
# A failure exits with the command's own exit code.
_update-run() {
  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    printf '%b[dry-run]%b would run: %s\n' "${S_LIGHT-}" "${RESET-}" "$*" >&2
    return 0
  fi
  local rc=0
  _update-exec "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$rc" \
      "--update failed: '$*' exited with code ${rc}." \
      "Its message is above; your previous install is still in place. Fix the cause and re-run 'verbump --update'."
  fi
}

# _update-report <from> <to> <via> — the closing line. <to> "unknown" means
# the new version could not be read back after a package-manager update.
_update-report() {
  local from=$1 to=$2 via=$3
  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    log_success "VerBump ${S_VAL-}${from}${RESET-} would update with ${via} (dry-run)"
  elif [ "$to" = "unknown" ]; then
    log_success "Updated VerBump with ${via}. Run 'verbump --version' to see the installed version."
  elif [ "$to" = "$from" ]; then
    log_success "VerBump ${S_VAL-}${to}${RESET-} was already installed; nothing changed"
  else
    log_success "Updated VerBump ${S_VAL-}${from}${RESET-} → ${S_VAL-}${to}${RESET-}"
  fi
}

# do-update [version] — entry point for --update. An empty <version> means
# the latest stable release; a leading "v" is accepted (tags are v-prefixed).
# Honours FLAG_DRYRUN, which the pre-scan in normalize-long-opts sets.
do-update() {
  local want=${1-} channel from

  want="${want#v}"
  if [ -n "$want" ] && ! is_semver "$want"; then
    fail 2 \
      "--update: not a valid SemVer 2.0 version: '${want}'." \
      "Pass a release version, e.g. 'verbump --update 4.2.0', or drop the version to get the latest release."
  fi

  channel=$(detect-install-channel "$MODULE_DIR")
  from=$(_update-read-version "$MODULE_DIR")

  case "$channel" in
    git)     _update-git ;;
    unknown) _update-unknown ;;
    brew)    _update-brew "$want" "$from" ;;
    npm)     _update-node "$want" "$from" ;;
    curl)    _update-curl "$want" "$from" ;;
  esac
}

_update-git() {
  fail 3 \
    "VerBump is running from a git checkout (${MODULE_DIR}), so --update will not change it." \
    "Run 'git -C \"${MODULE_DIR}\" pull' to update the checkout."
}

_update-unknown() {
  fail 3 \
    "VerBump cannot tell how it was installed (${MODULE_DIR}), so it cannot update itself." \
    "Re-run the installer: curl -fsSL https://raw.githubusercontent.com/${VB_UPDATE_REPO_SLUG}/main/install.sh | bash"
}

# Homebrew: refresh the taps first, so the upgrade sees the newest formula
# even when the user has HOMEBREW_NO_AUTO_UPDATE set; the upgrade then skips
# its own auto-update, which would only repeat the fetch. A tap formula has
# no per-version install, so a pinned version is refused up front.
_update-brew() {
  local want=$1 from=$2
  if [ -n "$want" ]; then
    fail 2 \
      "Homebrew cannot install a chosen VerBump version, so --update ${want} does not work for a Homebrew install." \
      "Run 'verbump --update' with no version to get the latest release."
  fi
  _update-require-tool brew "Homebrew" "brew update && brew upgrade ${VB_UPDATE_BREW_FORMULA}"

  _update-run brew update
  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    _update-run brew upgrade "$VB_UPDATE_BREW_FORMULA"
  else
    HOMEBREW_NO_AUTO_UPDATE=1 _update-run brew upgrade "$VB_UPDATE_BREW_FORMULA"
  fi
  _update-report "$from" "$(_update-path-version)" "Homebrew"
}

# npm channel: re-install the package globally with the manager that owns
# the install. @latest (or @<version>) is explicit so every manager moves to
# the requested release rather than whatever range it recorded.
_update-node() {
  local want=$1 from=$2 pm spec
  local -a cmd
  pm=$(detect-node-manager "$MODULE_DIR")
  spec="${VB_UPDATE_NPM_PKG}@${want:-latest}"
  case "$pm" in
    pnpm) cmd=(pnpm add -g "$spec") ;;
    yarn) cmd=(yarn global add "$spec") ;;
    bun)  cmd=(bun add -g "$spec") ;;
    *)    cmd=(npm install -g "$spec") ;;
  esac
  _update-require-tool "$pm" "$pm" "${cmd[*]}"

  _update-run "${cmd[@]}"
  _update-report "$from" "$(_update-path-version)" "$pm"
}

# Install-script channel: run a temp copy of the install.sh shipped in the
# tree, not the file itself — the installer swaps out the very directory it
# lives in. The env pin is cleared so a stray VERBUMP_INSTALL_VERSION or
# VERBUMP_PREFIX in the user's shell can't redirect the update; an explicit
# pin travels as --version, which the installer prefers anyway.
_update-curl() {
  local want=$1 from=$2 prefix installer tmp
  local -a args
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
    _update-run bash "$installer" "${args[@]}"
    _update-report "$from" "" "the install script"
    return 0
  fi

  tmp=$(mktemp "${TMPDIR:-/tmp}/verbump-update.XXXXXX") || \
    fail 1 "--update could not create a temporary file." \
           "Check that \$TMPDIR (or /tmp) is writable, then re-run 'verbump --update'."
  if ! cp "$installer" "$tmp"; then
    rm -f "$tmp"
    fail 1 "--update could not copy the installer to ${tmp}." \
           "Check that \$TMPDIR (or /tmp) is writable, then re-run 'verbump --update'."
  fi

  local rc=0
  VERBUMP_INSTALL_VERSION="" VERBUMP_PREFIX="" \
    _update-exec bash "$tmp" "${args[@]}" || rc=$?
  rm -f "$tmp"
  if [ "$rc" -ne 0 ]; then
    fail "$rc" \
      "--update failed: the installer exited with code ${rc}." \
      "The installer keeps your previous install when it fails; its message is above. Re-run 'verbump --update' to retry."
  fi

  _update-report "$from" "$(_update-read-version "$MODULE_DIR")" "the install script"
}
