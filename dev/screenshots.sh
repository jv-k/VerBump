#!/usr/bin/env bash
#
# dev/screenshots.sh — regenerate img/screenshot.png, img/verbump-demo.gif
# (plus its final-frame still img/verbump-demo-final.png), and
# img/social-preview.png via vhs, and the README's img/wordmark-dark.png and
# img/wordmark-light.png via dev/wordmark.js and rsvg-convert. (img/demo.gif
# is the frozen legacy recording hotlinked by old ver-bump npm READMEs —
# never regenerated or cleaned here.)
#
# The social card is also copied to packages/docs-site/public/ — the user
# docs site serves its own copy, and this keeps the two in lock-step.
#
# Usage:
#   ./dev/screenshots.sh           # all of them
#   ./dev/screenshots.sh help      # just the --help PNG
#   ./dev/screenshots.sh demo      # just the sandbox-bump GIF
#   ./dev/screenshots.sh social    # just the 1280x640 social card
#   ./dev/screenshots.sh wordmark  # just the README's wordmark pictures
#   ./dev/screenshots.sh release   # all of them for the release in progress
#
# `release` is what .verbumprc's PRE_BUMP_CMD runs, so every release commit
# carries pictures that show its own version. VerBump runs the hook before it
# bumps package.json, so the version the help and the social card print comes
# from VERBUMP_VERSION instead: the pictures are drawn in a temporary copy of
# HEAD whose package.json has that version, then copied back and staged. The
# release commit includes whatever is staged.
#
# Requires: vhs (https://github.com/charmbracelet/vhs).  Install: brew install vhs
# The wordmark also needs node and rsvg-convert (librsvg).  Install: brew install librsvg
# `release` also needs jq and gifsicle.  Install: brew install jq gifsicle

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

target="${1:-all}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "screenshots: $1 not found on PATH. Install with: $2" >&2
    exit 127
  fi
}
[ "$target" = wordmark ] || need vhs "brew install vhs"
case "$target" in wordmark|all|release)
  need node "brew install node"
  need rsvg-convert "brew install librsvg"
;; esac
if [ "$target" = release ]; then
  need jq "brew install jq"
  need gifsicle "brew install gifsicle"
fi

# Every picture this script writes, for `release` to copy back and stage.
OUTPUTS=(
  img/screenshot.png img/verbump-demo.gif img/verbump-demo-final.png
  img/social-preview.png img/wordmark-dark.png img/wordmark-light.png
  packages/docs-site/public/social-preview.png
)

mkdir -p img img/tmp

# Remove stale outputs so vhs can overwrite cleanly. Notably, earlier runs
# of vhs on `Output *.png` produced a *directory* of frames at that path —
# if one is still around, vhs can't write a plain file there. Nuke both
# possible shapes (file or dir) before re-rendering.
clean() {
  local p
  for p in "$@"; do rm -rf -- "$p"; done
}

sync_social() {
  cp -f img/social-preview.png packages/docs-site/public/social-preview.png
  echo "screenshots: synced social card -> packages/docs-site/public/"
}

# The README's wordmark, from the rows --help prints, in the CLI's gradient:
# one picture for a dark page and one for a light page.
wordmark() {
  local variant
  for variant in dark light; do
    node dev/wordmark.js "$variant" | rsvg-convert -o "img/wordmark-$variant.png"
  done
  echo "screenshots: wrote img/wordmark-dark.png and img/wordmark-light.png"
}
case "$target" in
  help)
    clean img/screenshot.png img/tmp/help.gif
    vhs dev/help.tape
  ;;
  demo)
    clean img/verbump-demo.gif img/verbump-demo-final.png
    vhs dev/demo.tape
  ;;
  social)
    clean img/social-preview.png img/tmp/social.gif
    vhs dev/social.tape
    sync_social
  ;;
  wordmark)
    wordmark
  ;;
  release)
    ver="${VERBUMP_VERSION:-}"
    if [ -z "$ver" ]; then
      echo "screenshots: release needs VERBUMP_VERSION, which VerBump sets for PRE_BUMP_CMD." >&2
      exit 2
    fi
    work=$(mktemp -d "${TMPDIR:-/tmp}/verbump-screenshots.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    git archive HEAD | tar -x -C "$work"
    jq --arg v "$ver" '.version = $v' "$work/package.json" > "$work/package.json.tmp"
    mv "$work/package.json.tmp" "$work/package.json"
    echo "screenshots: drawing the pictures for v$ver in $work"
    "$work/dev/screenshots.sh" all
    # Lossless, as the Screenshots workflow does.
    gifsicle -O3 "$work/img/verbump-demo.gif" -o "$work/img/verbump-demo.gif"
    for p in "${OUTPUTS[@]}"; do cp -f "$work/$p" "$p"; done
    git add -- "${OUTPUTS[@]}"
    echo "screenshots: staged the pictures for v$ver"
    exit 0
  ;;
  all)
    clean img/screenshot.png img/verbump-demo.gif img/verbump-demo-final.png \
          img/social-preview.png img/tmp/help.gif img/tmp/social.gif
    vhs dev/help.tape
    vhs dev/demo.tape
    vhs dev/social.tape
    sync_social
    wordmark
  ;;
  *)
    echo "screenshots: unknown target '$target'" >&2
    echo "  expected: help | demo | social | wordmark | all | release" >&2
    exit 2
  ;;
esac

# vhs' `Output` directive always produces a file even when we only care about
# the `Screenshot` frame — for help.tape that throwaway gif lands in img/tmp/.
echo "screenshots: wrote -> img/ (discarded intermediate gifs in img/tmp/)"
