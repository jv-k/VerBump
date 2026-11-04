#!/usr/bin/env bats

# --update (R-UPD-1..7): channel detection is driven as a pure function by
# sourcing verbump.sh. End-to-end runs copy the runtime tree into a fake
# install layout and replace its install.sh with a stub that records its
# argv and rewrites the version. Package managers (brew, npm, pnpm, yarn,
# bun) and the `verbump` the update reads back are stubs on PATH, so no test
# touches the network or the machine's real tools.

load 'test_helper'

setup() {
  load './test_helper/bats-support/load'
  load './test_helper/bats-assert/load'

  repo_dir=$PWD
  profile_script="$repo_dir/verbump.sh"

  # realpath: macOS mktemp hands out /var/…, which the entrypoint resolves
  # to /private/var/…; compare against the resolved form.
  WORK=$(realpath "$(mktemp -d)")
  STUB_LOG="$WORK/stub.log"
  export STUB_LOG
  mkdir -p "$WORK/bin"
  export PATH="$WORK/bin:$PATH"

  F_TEMPS=()
  CLEANUP_CMDS=( "rm -rf ${WORK}" )
}

teardown() {
  run_cleanup_cmds
  unset WORK STUB_LOG STUB_RC STUB_VERSION VERBUMP_INSTALL_VERSION HOMEBREW_NO_AUTO_UPDATE
}

# make_tree <dir> — copy the runtime file set (what CI tars up) into <dir>,
# with a stub install.sh. The stub logs its argv and the inherited
# VERBUMP_INSTALL_VERSION, rewrites package.json's version to $STUB_VERSION
# (default 9.9.9), and exits $STUB_RC (default 0).
make_tree() {
  mkdir -p "$1"
  cp -R "$repo_dir/verbump.sh" "$repo_dir/lib" "$repo_dir/package.json" "$1/"
  cat > "$1/install.sh" <<'STUB'
#!/bin/bash
printf 'args=%s\n' "$*" >> "$STUB_LOG"
printf 'env_pin=[%s]\n' "${VERBUMP_INSTALL_VERSION-unset}" >> "$STUB_LOG"
[ "${STUB_RC:-0}" -eq 0 ] || exit "$STUB_RC"
pj="$2/share/verbump/package.json"
sed -i.bak -E "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]+\"/\"version\": \"${STUB_VERSION:-9.9.9}\"/" "$pj"
rm -f "$pj.bak"
STUB
}

# stub_tool <name>… — fake package-manager commands on PATH. Each logs
# "<name> <argv>" and the HOMEBREW_NO_AUTO_UPDATE it inherited, then exits
# $STUB_RC (default 0).
stub_tool() {
  local t
  for t in "$@"; do
    cat > "$WORK/bin/$t" <<STUB
#!/bin/bash
printf '%s %s [no_auto=%s]\n' "$t" "\$*" "\${HOMEBREW_NO_AUTO_UPDATE-}" >> "\$STUB_LOG"
exit "\${STUB_RC:-0}"
STUB
    chmod +x "$WORK/bin/$t"
  done
}

# stub_verbump <version-line> — the `verbump` on PATH that the update reads
# its new version back from.
stub_verbump() {
  printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "$1" > "$WORK/bin/verbump"
  chmod +x "$WORK/bin/verbump"
}

current_version() {
  sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$repo_dir/package.json" | head -1
}

# ── channel detection (pure) ────────────────────────────────────────────

@test "update: detect-install-channel classifies each install layout" {
  source "$profile_script"
  mkdir -p "$WORK/clone" && touch "$WORK/clone/.git"

  run detect-install-channel "$WORK/clone"
  assert_output "git"
  run detect-install-channel "/opt/homebrew/Cellar/verbump/4.2.0/libexec"
  assert_output "brew"
  run detect-install-channel "/usr/local/lib/node_modules/@jv-k/verbump"
  assert_output "npm"
  run detect-install-channel "$HOME/Library/pnpm/global/5/.pnpm/@jv-k+verbump@4.2.0/node_modules/@jv-k/verbump"
  assert_output "npm"
  run detect-install-channel "$HOME/.local/share/verbump"
  assert_output "curl"
  run detect-install-channel "/opt/tools/verbump"
  assert_output "unknown"
}

# ── curl channel ────────────────────────────────────────────────────────

@test "update: curl install runs its own installer against its prefix" {
  make_tree "$WORK/prefix/share/verbump"
  cd "$WORK"   # not a git repo: --update must not need one

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  strip_ansi_output
  assert_success
  assert_output --partial "Updated VerBump $(current_version) → 9.9.9"
  run cat "$STUB_LOG"
  assert_line "args=--prefix $WORK/prefix"
}

@test "update: a version pins the release, in space and = forms, v optional" {
  make_tree "$WORK/prefix/share/verbump"

  run "$WORK/prefix/share/verbump/verbump.sh" --update 4.0.0
  assert_success
  run "$WORK/prefix/share/verbump/verbump.sh" --update=v4.1.0
  assert_success
  run cat "$STUB_LOG"
  assert_line "args=--prefix $WORK/prefix --version 4.0.0"
  assert_line "args=--prefix $WORK/prefix --version 4.1.0"
}

@test "update: a stray VERBUMP_INSTALL_VERSION in the env does not pin the update" {
  make_tree "$WORK/prefix/share/verbump"
  export VERBUMP_INSTALL_VERSION=1.0.0

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  assert_success
  run cat "$STUB_LOG"
  assert_line "args=--prefix $WORK/prefix"
  assert_line "env_pin=[]"
}

@test "update: reports an unchanged version when already on that release" {
  make_tree "$WORK/prefix/share/verbump"
  export STUB_VERSION
  STUB_VERSION=$(current_version)

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  strip_ansi_output
  assert_success
  assert_output --partial "VerBump ${STUB_VERSION} was already installed; nothing changed"
}

@test "update: --dry-run (either side) previews the installer run and changes nothing" {
  make_tree "$WORK/prefix/share/verbump"

  run "$WORK/prefix/share/verbump/verbump.sh" --dry-run --update
  strip_ansi_output
  assert_success
  assert_output --partial "[dry-run] would run: bash $WORK/prefix/share/verbump/install.sh --prefix $WORK/prefix"

  run "$WORK/prefix/share/verbump/verbump.sh" --update 4.0.0 -d
  strip_ansi_output
  assert_success
  assert_output --partial "--prefix $WORK/prefix --version 4.0.0"

  [ ! -e "$STUB_LOG" ] || bats_fail "dry-run invoked the installer"
}

@test "update: an installer failure exits with its code and a retry hint" {
  make_tree "$WORK/prefix/share/verbump"
  export STUB_RC=3

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "--update failed: the installer exited with code 3."
  assert_output --partial "Re-run 'verbump --update' to retry."
}

@test "update: a curl tree without install.sh exits 3 with the one-liner" {
  make_tree "$WORK/prefix/share/verbump"
  rm "$WORK/prefix/share/verbump/install.sh"

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "has no copy of install.sh"
  assert_output --partial "install.sh | bash"
}

# ── channels VerBump does not own ───────────────────────────────────────

@test "update: Homebrew runs brew update, then brew upgrade without a second auto-update" {
  make_tree "$WORK/Cellar/verbump/4.2.0/libexec"
  stub_tool brew
  stub_verbump "VerBump 9.9.9"

  run "$WORK/Cellar/verbump/4.2.0/libexec/verbump.sh" --update
  strip_ansi_output
  assert_success
  assert_output --partial "Updated VerBump $(current_version) → 9.9.9"
  run cat "$STUB_LOG"
  assert_line --index 0 "brew update [no_auto=]"
  assert_line --index 1 "brew upgrade jv-k/tap/verbump [no_auto=1]"
}

@test "update: Homebrew refuses a pinned version with exit 2 and runs nothing" {
  make_tree "$WORK/Cellar/verbump/4.2.0/libexec"
  stub_tool brew

  run "$WORK/Cellar/verbump/4.2.0/libexec/verbump.sh" --update 4.0.0
  strip_ansi_output
  assert_failure 2
  assert_output --partial "Homebrew cannot install a chosen VerBump version"
  [ ! -e "$STUB_LOG" ] || bats_fail "a pinned brew update ran brew"
}

@test "update: Homebrew --dry-run previews both brew commands and runs nothing" {
  make_tree "$WORK/Cellar/verbump/4.2.0/libexec"
  stub_tool brew

  run "$WORK/Cellar/verbump/4.2.0/libexec/verbump.sh" --update --dry-run
  strip_ansi_output
  assert_success
  assert_output --partial "[dry-run] would run: brew update"
  assert_output --partial "[dry-run] would run: brew upgrade jv-k/tap/verbump"
  [ ! -e "$STUB_LOG" ] || bats_fail "dry-run ran brew"
}

@test "update: a failing brew exits with its code and names the command" {
  make_tree "$WORK/Cellar/verbump/4.2.0/libexec"
  stub_tool brew
  export STUB_RC=1

  run "$WORK/Cellar/verbump/4.2.0/libexec/verbump.sh" --update
  strip_ansi_output
  assert_failure 1
  assert_output --partial "--update failed: 'brew update' exited with code 1."
}

@test "update: Homebrew install without brew on PATH exits 3" {
  make_tree "$WORK/Cellar/verbump/4.2.0/libexec"
  PATH="$WORK/bin:/usr/bin:/bin"

  run "$WORK/Cellar/verbump/4.2.0/libexec/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "'brew' is not on your PATH"
  assert_output --partial "brew update && brew upgrade jv-k/tap/verbump"
}

@test "update: detect-node-manager reads the manager from the install path" {
  source "$profile_script"
  run detect-node-manager "/usr/local/lib/node_modules/@jv-k/verbump"
  assert_output "npm"
  run detect-node-manager "$HOME/Library/pnpm/global/5/.pnpm/@jv-k+verbump@4.2.0/node_modules/@jv-k/verbump"
  assert_output "pnpm"
  run detect-node-manager "$HOME/.config/yarn/global/node_modules/@jv-k/verbump"
  assert_output "yarn"
  run detect-node-manager "$HOME/.bun/install/global/node_modules/@jv-k/verbump"
  assert_output "bun"
}

@test "update: npm install runs npm install -g @latest and reports the new version" {
  make_tree "$WORK/lib/node_modules/@jv-k/verbump"
  stub_tool npm
  stub_verbump "VerBump 9.9.9"

  run "$WORK/lib/node_modules/@jv-k/verbump/verbump.sh" --update
  strip_ansi_output
  assert_success
  assert_output --partial "Updated VerBump $(current_version) → 9.9.9"
  run cat "$STUB_LOG"
  assert_line "npm install -g @jv-k/verbump@latest [no_auto=]"
}

@test "update: pnpm, yarn and bun installs use their own manager, carrying a pin" {
  stub_tool pnpm yarn bun
  make_tree "$WORK/pnpm/global/5/.pnpm/x/node_modules/@jv-k/verbump"
  make_tree "$WORK/yarn/global/node_modules/@jv-k/verbump"
  make_tree "$WORK/.bun/install/global/node_modules/@jv-k/verbump"

  run "$WORK/pnpm/global/5/.pnpm/x/node_modules/@jv-k/verbump/verbump.sh" --update 4.0.0
  assert_success
  run "$WORK/yarn/global/node_modules/@jv-k/verbump/verbump.sh" --update 4.0.0
  assert_success
  run "$WORK/.bun/install/global/node_modules/@jv-k/verbump/verbump.sh" --update 4.0.0
  assert_success
  run cat "$STUB_LOG"
  assert_line "pnpm add -g @jv-k/verbump@4.0.0 [no_auto=]"
  assert_line "yarn global add @jv-k/verbump@4.0.0 [no_auto=]"
  assert_line "bun add -g @jv-k/verbump@4.0.0 [no_auto=]"
}

@test "update: an unreadable new version falls back to a --version hint" {
  make_tree "$WORK/lib/node_modules/@jv-k/verbump"
  stub_tool npm
  stub_verbump "garbage"

  run "$WORK/lib/node_modules/@jv-k/verbump/verbump.sh" --update
  strip_ansi_output
  assert_success
  assert_output --partial "Updated VerBump with npm. Run 'verbump --version' to see the installed version."
}

@test "update: git checkout exits 3 and names git pull" {
  make_tree "$WORK/src/verbump"
  touch "$WORK/src/verbump/.git"

  run "$WORK/src/verbump/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "running from a git checkout"
  assert_output --partial "pull"
}

@test "update: unknown layout exits 3 and names the curl installer" {
  make_tree "$WORK/opt/verbump"

  run "$WORK/opt/verbump/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "cannot tell how it was installed"
  assert_output --partial "install.sh | bash"
}

# ── argument errors ─────────────────────────────────────────────────────

@test "update: invalid version exits 2" {
  make_tree "$WORK/prefix/share/verbump"

  run "$WORK/prefix/share/verbump/verbump.sh" --update 4.x
  strip_ansi_output
  assert_failure 2
  assert_output --partial "not a valid SemVer 2.0 version: '4.x'"
}

@test "update: --update= with no value exits 2" {
  run "$profile_script" --update=
  strip_ansi_output
  assert_failure 2
  assert_output --partial "--update= requires a version."
}

@test "update: a manual clone at ~/.local/share/verbump is a git checkout, not a curl install" {
  # installation.mdx's manual install clones to the same path the install
  # script uses; the .git check must win so --update never swaps a clone.
  make_tree "$WORK/prefix/share/verbump"
  mkdir "$WORK/prefix/share/verbump/.git"

  run "$WORK/prefix/share/verbump/verbump.sh" --update
  strip_ansi_output
  assert_failure 3
  assert_output --partial "running from a git checkout"
  [ ! -e "$STUB_LOG" ] || bats_fail "a git checkout invoked the installer"
}
