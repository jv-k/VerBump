#!/bin/bash

# shellcheck disable=SC2288
true

# _help_pack <width> <token>... — greedily pack atomic tokens into lines no
# wider than <width>, one line per output line, joining tokens with a single
# space. A token is never split, so a token longer than <width> gets its own
# (overflowing) line. Callers own any prefix/indent. This is the shared engine
# behind both prose wrapping (_help_wrap) and the USAGE synopsis, where the
# atomic tokens are bracket groups like "[--major | --minor | --patch]".
_help_pack() {
  local width="$1"; shift
  local line="" tok
  for tok in "$@"; do
    if [ -z "$line" ]; then
      line="$tok"
    elif (( ${#line} + 1 + ${#tok} <= width )); then
      line="$line $tok"
    else
      printf '%s\n' "$line"
      line="$tok"
    fi
  done
  [ -n "$line" ] && printf '%s\n' "$line"
}

# _help_wrap <width> <text> — word-wrap prose to <width> columns by splitting on
# spaces (a word longer than <width> overflows its own line rather than being
# hard-cut). Splitting goes through `read -ra` so no globbing/brace expansion
# touches the text. Callers own indentation.
_help_wrap() {
  local width="$1" text="$2"
  local -a words
  read -ra words <<< "$text"
  _help_pack "$width" "${words[@]}"
}

# Show --help.
usage() {
  local SCRIPT_VER SCRIPT_NAME SCRIPT_AUTH SCRIPT_HOME SCRIPT_DESC env_var env_var_val
  local env_vars=( SCRIPT_VER SCRIPT_NAME SCRIPT_AUTH SCRIPT_HOME )

  # Tagline comes from the repo's package.json ".description"; this literal is
  # only a fallback for a package.json without one (or when jq is absent).
  SCRIPT_DESC="Release tool for any Git repo: reads your Conventional Commits to suggest a SemVer bump, then updates the changelog, tags, and pushes. Optional release-branch and PR workflows — no Node toolchain, just git + jq."

  if command -v jq >/dev/null 2>&1; then
    SCRIPT_VER=$(  jq -r '.version  // ""'         "$MODULE_DIR/package.json" )
    SCRIPT_NAME=$( jq -r '.name     // "verbump"' "$MODULE_DIR/package.json" )
    SCRIPT_AUTH=$( jq -r '.author   // ""'         "$MODULE_DIR/package.json" )
    SCRIPT_HOME=$( jq -r '.homepage // ""'         "$MODULE_DIR/package.json" )
    local _desc; _desc=$( jq -r '.description // ""' "$MODULE_DIR/package.json" )
    [ -n "$_desc" ] && SCRIPT_DESC="$_desc"
  else
    # Fallback: grep + trim (works without jq for --help alone)
    SCRIPT_VER=$(  cd "$MODULE_DIR" && grep version  package.json | head -1 )
    SCRIPT_NAME=$( cd "$MODULE_DIR" && grep name     package.json | head -1 )
    SCRIPT_AUTH=$( cd "$MODULE_DIR" && grep author   package.json | head -1 )
    SCRIPT_HOME=$( cd "$MODULE_DIR" && grep homepage package.json | head -1 | sed -ne 's/.*\(http[^"]*\).*/\1/p' )

    for env_var in "${env_vars[@]}"; do
      env_var_val=$( printf '%s' "${!env_var}" | awk -F: '{ print $2 }' | sed 's/[",]//g' | sed "s/^[ \t]*//" )
      printf -v "$env_var" '%s' "$env_var_val"
    done
  fi

  # Display brand shown in the banner is "VerBump"; the command the user
  # actually types (USAGE synopsis, EXAMPLES) is lowercase "verbump" —
  # matching the installed bin name across brew, npm, and install.sh.
  SCRIPT_NAME="VerBump"
  local SCRIPT_CMD="verbump"

  # Fluid layout: on a real terminal, wrap output to the actual width so long
  # lines don't overflow. TERM_COLS=0 disables wrapping — piped / redirected
  # output (tests, `| less`, files) keeps the historic single-line layout,
  # stable for grepping. Width detection: an exported COLUMNS wins; otherwise
  # read the controlling terminal with `stty size </dev/tty`. Plain `tput cols`
  # is WRONG here — usage() computes width inside command substitution, where
  # stdout is a pipe, so tput's ioctl misreads the size as 80; /dev/tty is the
  # real terminal regardless of fd redirection. tput then 80 are the backstops.
  local TERM_COLS=0
  if [ -n "${_VB_HELP_COLS:-}" ] && [ -z "${_VB_HELP_COLS//[0-9]/}" ]; then
    # Forced width: show-help renders into a pager, so our stdout is a pipe and
    # the [ -t 1 ] checks below would fail — it passes the real terminal width.
    TERM_COLS="$_VB_HELP_COLS"
  elif [ -t 1 ]; then
    if [ -n "${COLUMNS:-}" ] && [ -z "${COLUMNS//[0-9]/}" ]; then
      TERM_COLS="$COLUMNS"
    else
      local _size
      _size=$(stty size </dev/tty 2>/dev/null) && TERM_COLS=${_size##* }
      case "$TERM_COLS" in ''|0|*[!0-9]*) TERM_COLS=$(tput cols 2>/dev/null) ;; esac
    fi
    case "$TERM_COLS" in ''|*[!0-9]*) TERM_COLS=80 ;; esac
  fi

  # figlet "future" (via pyfiglet), one array element per cell so the
  # gradient can colour each cell without splitting multibyte glyphs (which
  # would depend on the locale). With colour off WORDMARK_GRAD is empty and
  # the rows print plain.
  local -a _wm_r0=( '╻' ' ' '╻' '┏' '━' '╸' '┏' '━' '┓' '┏' '┓' ' ' '╻' ' ' '╻' '┏' '┳' '┓' '┏' '━' '┓' )
  local -a _wm_r1=( '┗' '┓' '┃' '┣' '╸' ' ' '┣' '┳' '┛' '┣' '┻' '┓' '┃' ' ' '┃' '┃' '┃' '┃' '┣' '━' '┛' )
  local -a _wm_r2=( ' ' '┗' '┛' '┗' '━' '╸' '╹' '┗' '╸' '┗' '━' '┛' '┗' '━' '┛' '╹' ' ' '╹' '╹' ' ' ' ' )
  _wordmark_row() {
    local y="$1" x=0 line="" cell; shift
    for cell in "$@"; do
      line+="${WORDMARK_GRAD[x + WORDMARK_SHIFT * y]-}$cell"
      x=$(( x + 1 ))
    done
    printf '%s%s\n' "$line" "${WORDMARK_RST-}"
  }
  _wordmark_row 0 "${_wm_r0[@]}"
  _wordmark_row 1 "${_wm_r1[@]}"
  _wordmark_row 2 "${_wm_r2[@]}"

  # Branded header pill + author/homepage bullets + dim tagline. No blank line
  # after the pill — the author bullet sits directly beneath it.
  printf '\n%b %s v%s %b\n' "${S_HDR_SUB-}" "${SCRIPT_NAME}" "${SCRIPT_VER}" "${S_HDR_END-}"
  printf ' %b%s%b Author:   %s\n'   "${S_BULLET-}" "${I_BULLET-}" "${RESET-}" "${SCRIPT_AUTH}"
  printf ' %b%s%b Homepage: %s\n\n' "${S_BULLET-}" "${I_BULLET-}" "${RESET-}" "${SCRIPT_HOME}"
  # Tool description (from package.json), dim and wrapped to the terminal.
  if (( TERM_COLS > 0 )); then
    local _dline
    while IFS= read -r _dline; do
      printf '  %b%s%b\n' "${S_DIM-}" "$_dline" "${RESET-}"
    done < <(_help_wrap $(( TERM_COLS > 2 ? TERM_COLS - 2 : 20 )) "$SCRIPT_DESC")
  else
    printf '  %b%s%b\n' "${S_DIM-}" "${SCRIPT_DESC}" "${RESET-}"
  fi

  # USAGE — a concise synopsis (à la `gh`), not an enumeration of every flag.
  # The version is an OPTION value (-v <version>), not a positional, so it is
  # shown as such; the rest of the flag list lives in OPTIONS below.
  printf '\n%b USAGE %b\n' "${S_HDR_CYAN-}" "${S_HDR_END-}"
  printf '  %b%s%b [-v <version>] [options]\n' "${BOLD-}" "${SCRIPT_CMD}" "${RESET-}"

  # Column width for label + 2-space gutter. Longest label is
  # "  --install-completions [=<shell>]" = 34 chars. OPT_COL 40 gives a
  # comfortable description column start.
  local OPT_COL=40

  # _help_desc_avail — columns available for the description/continuation text
  # to the right of OPT_COL, floored so a very narrow terminal still wraps
  # somewhere sane rather than at 0.
  _help_desc_avail() {
    local avail=$(( TERM_COLS - OPT_COL ))
    (( avail < 20 )) && avail=20
    printf '%s' "$avail"
  }

  # print-opt-row <short> <long> <arg-or-empty> <description>
  # 2-space left gutter on every row. The short alias ("-x") leads, dimmed
  # (S_DIM) so it reads as secondary; the long flag ("--noun") follows in bold.
  # Long-only rows indent to align their long flag under the others'.
  print-opt-row() {
    local short="$1" long="$2" arg="$3" desc="$4"
    local plain label pad head_plain head_label
    if [ -n "$short" ]; then
      head_plain="  ${short}, ${long}"
      head_label="  ${S_DIM-}${short}${RESET-}, ${BOLD-}${long}${RESET-}"
    else
      # Align long-only rows under the long-flag column: 2-space gutter + "-x, " = 6 chars.
      head_plain="      ${long}"
      head_label="      ${BOLD-}${long}${RESET-}"
    fi
    if [ -n "$arg" ]; then
      plain="${head_plain} ${arg}"
      label="${head_label} ${arg}"
    else
      plain="${head_plain}"
      label="${head_label}"
    fi
    # If the label reaches the description column, it would crowd (touch) the
    # description — stack it instead: label alone, description on the next
    # line(s) at OPT_COL. Same rule as print-example-row.
    if (( ${#plain} >= OPT_COL )); then
      echo -e "${label}"
      [ -n "$desc" ] && print-opt-cont "$desc"
      return
    fi
    printf -v pad '%*s' $((OPT_COL - ${#plain})) ''
    # Fluid: wrap the description and hang continuations under OPT_COL. Rows
    # with runs of 2+ spaces are pre-aligned (never reflowed); descriptions are
    # plain single-spaced prose so they always wrap cleanly.
    if (( TERM_COLS > 0 )) && [ -n "$desc" ] && [[ "$desc" != *"  "* ]]; then
      local wline first=1
      while IFS= read -r wline; do
        if (( first )); then
          echo -e "${label}${pad}${wline}"
          first=0
        else
          print-opt-cont "$wline"
        fi
      done < <(_help_wrap "$(_help_desc_avail)" "$desc")
    else
      echo -e "${label}${pad}${desc}"
    fi
  }

  # print-opt-cont <text> — continuation row, aligned under the description
  # column. Free prose is word-wrapped to the terminal width; rows with runs of
  # 2+ spaces are pre-aligned inner tables (e.g. the --bump spec list) and are
  # emitted verbatim so their own columns survive.
  print-opt-cont() {
    if (( TERM_COLS > 0 )) && [[ "$1" != *"  "* ]]; then
      local wline
      while IFS= read -r wline; do
        printf '%*s' "$OPT_COL" ''
        echo -e "$wline"
      done < <(_help_wrap "$(_help_desc_avail)" "$1")
    else
      printf '%*s' "$OPT_COL" ''
      echo -e "$1"
    fi
  }

  # _print-example-desc <text> — the description half of an example row, wrapped
  # (on a TTY) and hung under OPT_COL. Dimmed (S_DIM) — the whole EXAMPLES
  # section is demoted relative to OPTIONS. Shared by the inline/stacked layouts.
  _print-example-desc() {
    if (( TERM_COLS > 0 )) && [[ "$1" != *"  "* ]]; then
      local wline
      while IFS= read -r wline; do
        printf '%*s%b%s%b\n' "$OPT_COL" '' "${S_DIM-}" "$wline" "${RESET-}"
      done < <(_help_wrap "$(_help_desc_avail)" "$1")
    else
      printf '%*s%b%s%b\n' "$OPT_COL" '' "${S_DIM-}" "$1" "${RESET-}"
    fi
  }

  # print-opt-subitem <text> — a sub-entry beneath an option's description (the
  # --bump spec forms). Renders at OPT_COL and wraps free prose with a DEEPER
  # (+2) hanging indent, so a wrapped line reads as subordinate to its form and
  # successive forms stay visually distinct. Non-TTY: one line, at OPT_COL.
  print-opt-subitem() {
    if (( TERM_COLS > 0 )); then
      local avail=$(( TERM_COLS - OPT_COL - 2 ))
      (( avail < 18 )) && avail=18
      local wline first=1
      while IFS= read -r wline; do
        if (( first )); then
          printf '%*s%b\n' "$OPT_COL" '' "$wline"; first=0
        else
          printf '%*s%b\n' "$((OPT_COL + 2))" '' "$wline"
        fi
      done < <(_help_wrap "$avail" "$1")
    else
      printf '%*s%b\n' "$OPT_COL" '' "$1"
    fi
  }

  # print-example-row <command> <description> — 2-space gutter. The whole
  # EXAMPLES section is dimmed (S_DIM) so it reads as demoted relative to
  # OPTIONS. A command that fits the column gets a clean two-column row
  # (description wraps and hangs under OPT_COL). A command longer than the
  # column would shove its description out of alignment — and, once wrapped,
  # zig-zag back to the column — so it is stacked instead: the command sits
  # alone on its line (easier to copy) and the description hangs below.
  print-example-row() {
    local cmd="$1" desc="$2"
    local plain="  ${cmd}"

    if (( ${#plain} >= OPT_COL )); then
      printf '  %b%s%b\n' "${S_DIM-}" "${cmd}" "${RESET-}"
      [ -n "$desc" ] && _print-example-desc "$desc"
      return
    fi

    local pad; printf -v pad '%*s' $((OPT_COL - ${#plain})) ''
    if (( TERM_COLS > 0 )) && [ -n "$desc" ] && [[ "$desc" != *"  "* ]]; then
      local wline first=1
      while IFS= read -r wline; do
        if (( first )); then
          printf '  %b%s%s%s%b\n' "${S_DIM-}" "${cmd}" "${pad}" "${wline}" "${RESET-}"
          first=0
        else
          printf '%*s%b%s%b\n' "$OPT_COL" '' "${S_DIM-}" "$wline" "${RESET-}"
        fi
      done < <(_help_wrap "$(_help_desc_avail)" "$desc")
    else
      printf '  %b%s%s%s%b\n' "${S_DIM-}" "${cmd}" "${pad}" "${desc}" "${RESET-}"
    fi
  }

  # print-opt-group <label> — a subdued gray pill heading inside OPTIONS that
  # clusters related flags. A blank line precedes every group except the first
  # (which sits directly under the pill — no blank line after a header pill).
  # _optgrp tracks whether a group has already been emitted this run. Plain
  # (no-colour) output keeps the historic bare-uppercase form — parseable, no
  # stray pill padding.
  local _optgrp=""
  print-opt-group() {
    [ -n "$_optgrp" ] && printf '\n'
    _optgrp=1
    local upper
    upper=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    if [ "${USE_COLOR:-0}" = 1 ]; then
      printf '  %b %s %b\n' "${S_HDR_GRAY-}" "$upper" "${S_HDR_END-}"
    else
      printf '  %s\n' "$upper"
    fi
  }

  # OPTIONS — grouped by task, in the order you meet them during a release.
  # --about is intentionally not listed here (it still works). The "long forms
  # accept …" note is at the bottom.
  printf '\n%b OPTIONS %b\n' "${S_HDR_CYAN-}" "${S_HDR_END-}"

  print-opt-group "Choose the new version"
  print-opt-row "-v" "--version"       "[<version>]" "Without a value: print tool version and exit. With a value: set manual SemVer."
  print-opt-row ""   "--major"         ""            "Force a major bump from the current version."
  print-opt-row ""   "--minor"         ""            "Force a minor bump from the current version."
  print-opt-row ""   "--patch"         ""            "Force a patch bump from the current version."
  print-opt-cont "Without --preid, any of the three drops an existing prerelease/build and bumps the stable core (1.2.3-dev.5 --patch -> 1.2.4)."
  print-opt-row ""   "--preid"         "<id>"        "Start or advance a prerelease line; conflicts with -v."
  print-opt-cont "With --major/--minor/--patch: bump that level, then enter <id>.1 (1.2.3 --major --preid rc -> 2.0.0-rc.1)."
  print-opt-cont "Alone, on a version that already has a prerelease: same id increments the counter, a different id resets it to .1."
  print-opt-cont "Alone, on a stable version: ambiguous -> exit 2 (combine with --major/--minor/--patch)."

  print-opt-group "Files to bump"
  print-opt-row ""   "--source"        "<file.json>" "Version source + primary bump target (default: package.json)."
  print-opt-cont "If the file is missing, the current version derives from the latest matching git tag."
  print-opt-row ""   "--bump"          "<spec>"      "Also bump a JSON / TOML / YAML / text file. Repeatable. <spec> is one of:"
  print-opt-subitem "<file> — structured, top-level .version by file type (jq / tomlq / yq)"
  print-opt-subitem "<file>:@<path> — structured, explicit dotted path (e.g. pyproject.toml:@tool.poetry.version)"
  print-opt-subitem "'<file>:<pattern>' — text search/replace; the pattern must contain {{version}}"
  print-opt-cont "e.g. verbump --bump 'main.go:Version = \"{{version}}\"' --bump Chart.yaml:@version"
  print-opt-row "-f" "--file"          "<file.json>" "Also bump \"version\" in this JSON file. Repeatable:"
  print-opt-cont "verbump -f src/plugin/package.json -f composer.json"

  print-opt-group "Commit, tag & changelog"
  print-opt-row "-m" "--message"       "<message>"   "Custom annotated-tag release message."
  print-opt-row "-t" "--tag-prefix"    "<prefix>"    "Override tag prefix (default: v)."
  print-opt-row ""   "--sign"          ""            "Create a signed tag (git tag -s; uses your git signing config)."
  print-opt-row "-c" "--no-changelog"  ""            "Disable updating CHANGELOG.md automatically."
  print-opt-row "-l" "--pause-changelog" ""          "Pause before commit so CHANGELOG.md can be edited."
  print-opt-row "-n" "--no-commit"     ""            "Disable commit (and tag + push) after bumping files."

  print-opt-group "Push, branch & publish"
  print-opt-row "-p" "--push"          "<remote>"    "Push release branch + tag to <remote> at end of run."
  print-opt-row ""   "--pr"            ""            "Branch + push + open a release PR via 'gh' (GitHub-only; implies push to origin)."
  print-opt-row ""   "--base"          "<branch>"    "Base branch for --pr (GitHub-only; default: the branch you ran VerBump from)."
  print-opt-row ""   "--release"       ""            "Publish a GitHub release for the new tag (GitHub-only; requires -p, uses 'gh')."
  print-opt-row ""   "--branch"        ""            "Cut a release-x.x.x branch (pre-2.0 default); otherwise tag in place."
  print-opt-row "-B" "--branch-prefix" "<prefix>"    "Override branch prefix (default: release-)."
  print-opt-row "-b" "--no-branch"     ""            "(deprecated) Tag-in-place is the default now; this is a no-op."

  print-opt-group "Skip preflight checks"
  print-opt-row ""   "--allow-dirty"   ""            "Skip the clean-working-tree check (untracked files never trigger it)."
  print-opt-row ""   "--allow-empty"   ""            "Release even with no new commits since the previous tag."
  print-opt-row ""   "--no-fetch"      ""            "Skip the remote-sync preflight (no fetch / behind-upstream check)."
  print-opt-row ""   "--no-hooks"      ""            "Skip the PRE_BUMP_CMD / POST_TAG_CMD release hooks for this run."

  print-opt-group "Undo a release"
  print-opt-row ""   "--undo"          "[<version>]" "Locally delete release-X.Y.Z + tag vX.Y.Z (refuses if pushed/dirty)."

  print-opt-group "Run mode & output"
  print-opt-row "-d" "--dry-run"       ""            "Dry-run: print every side-effect without executing."
  print-opt-row "-y" "--yes"           ""            "Skip interactive confirmation prompts."
  print-opt-row "-q" "--quiet"         ""            "Suppress decoration; print only the new version on stdout (needs -y, -v, a bump level, or --preid)."
  print-opt-row ""   "--json"          ""            "With --dry-run: print the release plan as one JSON object on stdout (needs -y, -v, a bump level, or --preid)."

  print-opt-group "Help & completions"
  print-opt-row "-h" "--help"          ""            "Show this help message."
  print-opt-row ""   "--completions"   "<shell>"     "Emit completion script for bash, zsh, or fish."
  print-opt-row ""   "--install-completions" "[=<shell>]" "Install completion script (auto-detects shell)."

  # EXAMPLES section pill
  printf '\n%b EXAMPLES %b\n' "${S_HDR_CYAN-}" "${S_HDR_END-}"
  print-example-row "${SCRIPT_CMD}"                       "Interactive — reads commits, suggests bump, prompts."
  print-example-row "${SCRIPT_CMD} -v 2.0.0"              "Non-interactive, explicit version."
  print-example-row "${SCRIPT_CMD} --dry-run"             "Preview every side-effect without executing."
  print-example-row "${SCRIPT_CMD} --minor --dry-run --json" "Print the release plan as JSON (for scripts, CI, agents)."
  print-example-row "${SCRIPT_CMD} -p origin"             "Push the release branch + tag when done."
  print-example-row "${SCRIPT_CMD} --pr"                  "Branch, push, and open a release PR (needs gh)."
  print-example-row "${SCRIPT_CMD} -t release/"           "Use a custom tag prefix (e.g. release/1.2.3)."
  print-example-row "${SCRIPT_CMD} -f composer.json"      "Also bump version in an extra JSON file."
  print-example-row "${SCRIPT_CMD} --source composer.json" "Use composer.json as the version source (non-Node repo)."
  print-example-row "${SCRIPT_CMD} --bump pyproject.toml:@project.version" "Also bump a Python project's version (needs tomlq)."
  print-example-row "${SCRIPT_CMD} --bump 'pkg/__init__.py:__version__ = \"{{version}}\"'" "Also bump a Python __version__ via a text pattern (no extra tool)."
  print-example-row "${SCRIPT_CMD} --bump 'main.go:Version = \"{{version}}\"'" "Also bump a Go const via a text pattern (no extra tool)."
  print-example-row "${SCRIPT_CMD} --install-completions" "Install shell completions (auto-detects shell)."

  printf '\n  %b(long forms accept --name value or --name=value)%b\n\n' "${S_DIM-}" "${RESET-}"
}

# show-help — the entry point for --help. Renders usage() through a pager when
# the output is taller than the terminal (like `git help` / `man`), so a short
# window doesn't scroll the top off-screen. Only pages on an interactive stdout
# with a usable pager; piped / redirected output (`VerBump --help | cat`, the
# tests) prints straight through, unchanged. Colour still works in the pager:
# USE_COLOR was fixed at startup from the real stdout, and less gets -R.
show-help() {
  # Not a terminal (pipe/file/CI), or no size → print straight through.
  [ -t 1 ] || { usage; return; }

  local size rows cols pager
  size=$(stty size </dev/tty 2>/dev/null)
  rows=${size%% *}; cols=${size##* }
  case "$rows" in ''|*[!0-9]*) rows=0 ;; esac
  case "$cols" in ''|*[!0-9]*) cols=0 ;; esac

  # Use the standard *nix pager — less (with -R so ANSI colour passes through),
  # else more. Deliberately IGNORE $PAGER: a "fancy" pager (bat, most, delta …)
  # can mangle the coloured, pre-wrapped output, so pick the predictable one.
  if   command -v less >/dev/null 2>&1; then pager="less -R"
  elif command -v more >/dev/null 2>&1; then pager="more"
  else                                  pager=""
  fi

  if [ -z "$pager" ] || [ "$rows" -le 0 ]; then usage; return; fi

  # Render once at the real width (our stdout becomes a pipe), then page only
  # when it's taller than the window.
  local tmp; tmp=$(mktemp "${TMPDIR:-/tmp}/verbump-help.XXXXXX") || { usage; return; }
  _VB_HELP_COLS="$cols" usage > "$tmp"
  if [ "$(grep -c '' "$tmp")" -gt "$rows" ]; then
    eval "$pager" < "$tmp"
  else
    cat "$tmp"
  fi
  rm -f "$tmp"
}
