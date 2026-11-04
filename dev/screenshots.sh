#!/usr/bin/env bash
#
# dev/screenshots.sh — regenerate img/screenshot.png, img/verbump-demo.gif
# (plus its final-frame still img/verbump-demo-final.png), and
# img/social-preview.png via vhs, and the README's img/wordmark-dark.png and
# img/wordmark-light.png via dev/wordmark.js and rsvg-convert. (img/demo.gif is the frozen legacy
# recording hotlinked by old ver-bump npm READMEs — never regenerated or
# cleaned here.)
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
#
# Requires: vhs (https://github.com/charmbracelet/vhs).  Install: brew install vhs
# The wordmark also needs node and rsvg-convert (librsvg).  Install: brew install librsvg

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
case "$target" in wordmark|all)
  need node "brew install node"
  need rsvg-convert "brew install librsvg"
;; esac

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
    echo "  expected: help | demo | social | wordmark | all" >&2
    exit 2
  ;;
esac

# vhs' `Output` directive always produces a file even when we only care about
# the `Screenshot` frame — for help.tape that throwaway gif lands in img/tmp/.
echo "screenshots: wrote -> img/ (discarded intermediate gifs in img/tmp/)"
