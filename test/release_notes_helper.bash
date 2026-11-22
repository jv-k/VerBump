#!/usr/bin/env bash

# Shared helpers for the --release notes tests (release-notes.bats,
# notes-agent-builtin.bats). Load after test_helper:
#
#   load 'test_helper'
#   load 'release_notes_helper'

# gh shim: `auth status` succeeds; every other call writes each argument to
# its own file under $GH_ARGV_DIR (1, 2, …) so multi-line notes survive
# intact, and it records in $GH_ARGV_DIR/env which provider keys are set,
# so a test can see VerBump's own environment after the notes agent ran.
# Prints the shim's directory; the caller prepends it to PATH and registers
# its cleanup, because a CLEANUP_CMDS entry made here is lost in the
# caller's $(...) subshell.
gh_argv_shim() {
  local shim
  shim=$(mktemp -d)
  mkdir -p "${shim}/argv"
  cat > "${shim}/gh" <<'SH'
#!/bin/sh
[ "$1" = "auth" ] && exit 0
i=0
for a in "$@"; do
  i=$((i + 1))
  printf '%s' "$a" > "${GH_ARGV_DIR}/${i}"
done
printf 'ANTHROPIC_API_KEY=%s OPENAI_API_KEY=%s\n' \
  "${ANTHROPIC_API_KEY+set}" "${OPENAI_API_KEY+set}" > "${GH_ARGV_DIR}/env"
echo "https://github.com/acme/repo/releases/tag/shim"
exit 0
SH
  chmod +x "${shim}/gh"
  printf '%s' "$shim"
}

# Assert the argv the gh shim recorded equals the arguments given, one by one.
assert_gh_argv() {
  local dir="$1" i=0 want got
  shift
  for want in "$@"; do
    i=$((i + 1))
    [ -f "${dir}/${i}" ] || bats_fail "gh argv has no argument ${i} (wanted '${want}')"
    got=$(cat "${dir}/${i}"; printf x)
    got="${got%x}"
    assert_equal "$got" "$want"
  done
  [ ! -f "${dir}/$((i + 1))" ] || bats_fail "gh argv has more than ${i} arguments"
}
