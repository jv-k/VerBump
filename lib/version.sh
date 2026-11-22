#!/bin/bash

# shellcheck disable=SC2288
true

# Suggests version from the source file (VER_FILE), the latest matching git
# tag, or grabs from user supplied -v <version>.

# - If -v specified, set version from that
# - Else,
#   - Grab from the source file (package.json by default, --source overrides)
#   - If the source file is absent, derive from the latest matching git tag
#   - Suggest incremented number
#   - Give prompt to user to modify
# - Set globally

# According to SemVer 2.0.0, given a version number MAJOR.MINOR.PATCH, suggest incremented value:
# — MAJOR version when you make incompatible API changes,
# — MINOR version when you add functionality in a backwards compatible manner, and
# — PATCH version when you make backwards compatible bug fixes.
process-version() {
  # Read V_PREV from VER_FILE (the resolved --source / SOURCE_FILE target,
  # package.json by default) for display + same-version dedup. When the file
  # is absent, fall back to the latest matching release tag (R-SRC-2) — the
  # suggestion machinery then works unchanged. Without -v we need a version
  # to bump, so no file AND no tag is a hard error (R-SRC-4). With -v both
  # reads are best-effort: the user already gave us V_NEW.
  if [ -f "$VER_FILE" ] && [ -s "$VER_FILE" ]; then
    V_PREV=$( jq -r '.version // empty' "$VER_FILE" 2>/dev/null )

    if [ -n "$V_PREV" ]; then
      # No leading blank: this is the first line under the Verify pill (or it
      # follows the remote-sync warning) — keep it tight to the header.
      echo -e "Current version read from <${S_VAL}${VER_FILE}${RESET}>: ${S_VAL}$V_PREV${RESET}"
      # Only compute a suggestion when we'll actually prompt for it. With -v,
      # --major/--minor/--patch, or --preid the suggestion is discarded;
      # running it anyway printed a contradictory "suggesting <level> bump"
      # line and an extra git log.
      if [ -z "$V_USR_SUPPLIED" ] && [ -z "${BUMP_LEVEL-}" ] && [ -z "${PRE_ID-}" ]; then
        set-v-suggest "$V_PREV" # check + compute next version from conventional commits (or patch +1)
      fi
    elif [ -z "$V_USR_SUPPLIED" ]; then
      fail 3 \
        "<${VER_FILE}> doesn't contain a 'version' field." \
        "Add a top-level \"version\" key to ${VER_FILE}, or pass an explicit version with -v <version>."
    fi
  else
    local reason derived_tag
    if [ ! -f "$VER_FILE" ]; then
      reason="was not found"
    elif [ ! -s "$VER_FILE" ]; then
      reason="is empty"
    else
      reason="could not be read"
    fi

    # Source file absent: derive V_PREV from the latest release tag reachable
    # from HEAD (R-SRC-2). The match glob "${TAG_PREFIX}[0-9]*" keeps
    # unrelated tags (e.g. 'nightly') out. The derivation also runs with -v —
    # it feeds the changelog range, the commit message, and the no-op guard
    # (check-releasable-commits) — but stays best-effort there: an unusable
    # tag is discarded, never fatal.
    if derived_tag=$(git describe --tags --abbrev=0 --match "${TAG_PREFIX}[0-9]*" 2>/dev/null) \
       && [ -n "$derived_tag" ]; then
      V_PREV="${derived_tag#"${TAG_PREFIX}"}"
      if ! is_semver "$V_PREV"; then
        if [ -z "$V_USR_SUPPLIED" ]; then
          fail 3 \
            "<${VER_FILE}> ${reason} and the latest matching tag '${derived_tag}' is not '${TAG_PREFIX}' + a SemVer 2.0 version." \
            "Tag releases as ${TAG_PREFIX}MAJOR.MINOR.PATCH, pass -v <version>, or create ${VER_FILE} with a \"version\" field."
        fi
        V_PREV=""
      else
        echo -e "<${S_VAL}${VER_FILE}${RESET}> ${reason} — current version derived from git tag <${S_VAL}${derived_tag}${RESET}>: ${S_VAL}$V_PREV${RESET}"
        if [ -z "$V_USR_SUPPLIED" ] && [ -z "${BUMP_LEVEL-}" ] && [ -z "${PRE_ID-}" ]; then
          set-v-suggest "$V_PREV" # full suggestion machinery, unchanged (R-SRC-2)
        fi
      fi
    elif [ -z "$V_USR_SUPPLIED" ]; then
      # No source file and no tag to derive from (R-SRC-4): name both escape
      # routes — -v for a first release, or create the file.
      fail 3 \
        "<${VER_FILE}> ${reason} and no '${TAG_PREFIX}*' release tag exists to derive the current version from." \
        "First release? Pass -v <version>. Otherwise create ${VER_FILE} with a \"version\" field, or point --source / SOURCE_FILE at the right file."
    fi
  fi

  # If a version number is supplied by the user with [-v <version number>] — use it!
  if [ -n "$V_USR_SUPPLIED" ]; then
    echo -e "\nVersion supplied via [-v]: ${S_VAL}${V_USR_SUPPLIED}${RESET}"
    V_NEW="${V_USR_SUPPLIED}"
  elif [ -n "${BUMP_LEVEL-}" ] || [ -n "${PRE_ID-}" ]; then
    # Forced bump via --major / --minor / --patch, and/or entering or
    # advancing a prerelease line via --preid (R-PRE bucket, issue #64).
    # Needs a SemVer V_PREV to bump from; argument-parse-time conflict
    # checks already prevent combining either with -v.
    if [ -z "$V_PREV" ] || ! is_semver "$V_PREV"; then
      fail 3 \
        "Cannot apply --${BUMP_LEVEL:-preid}: current version '${V_PREV}' is not a valid SemVer 2.0 version." \
        "Ensure ${VER_FILE} contains a SemVer \"version\" field, or pass an explicit -v <version>."
    fi

    if [ -n "${BUMP_LEVEL-}" ]; then
      # force-bump returns 1 (empty output) on an unknown level. With the reset
      # in process-arguments BUMP_LEVEL is always major/minor/patch here, but
      # guard anyway so a bad value can never propagate an empty V_NEW into
      # the tag/commit.
      if ! V_NEW=$(force-bump "$V_PREV" "$BUMP_LEVEL") || [ -z "$V_NEW" ]; then
        fail 3 \
          "Cannot compute a '${BUMP_LEVEL}' bump from '${V_PREV}'." \
          "Use --major, --minor, or --patch, or pass an explicit -v <version>."
      fi
      if [ -n "${PRE_ID-}" ]; then
        # R-PRE-1: bump the level (force-bump already dropped any prerelease
        # / build metadata), then enter the prerelease at <preid>.1.
        V_NEW="${V_NEW}-${PRE_ID}.1"
        echo -e "\n${S_LIGHT}Forced ${S_VAL}${BUMP_LEVEL}${RESET}${S_LIGHT} bump into prerelease ${S_VAL}${PRE_ID}${RESET}${S_LIGHT}: ${S_VAL}${V_PREV}${RESET}${S_LIGHT} ${I_ARROW-→} ${S_VAL}${V_NEW}${RESET}"
      else
        echo -e "\n${S_LIGHT}Forced ${S_VAL}${BUMP_LEVEL}${RESET}${S_LIGHT} bump: ${S_VAL}${V_PREV}${RESET}${S_LIGHT} ${I_ARROW-→} ${S_VAL}${V_NEW}${RESET}"
      fi
    else
      # --preid alone, no --major/--minor/--patch (R-PRE-2 / R-PRE-3). Only
      # meaningful on a version that already has a prerelease — strip build
      # metadata first so a hyphen inside +build.info can't masquerade as one.
      case "${V_PREV%%+*}" in
        *-*)
          V_NEW=$(bump-preid "$V_PREV" "$PRE_ID")
          echo -e "\n${S_LIGHT}Prerelease ${S_VAL}${PRE_ID}${RESET}${S_LIGHT}: ${S_VAL}${V_PREV}${RESET}${S_LIGHT} ${I_ARROW-→} ${S_VAL}${V_NEW}${RESET}"
        ;;
        *)
          fail 2 \
            "--preid on a stable version ('${V_PREV}') is ambiguous." \
            "Combine with --major, --minor, or --patch to enter a prerelease, e.g. --major --preid ${PRE_ID}."
        ;;
      esac
    fi
  elif [ "${FLAG_YES:-false}" = true ]; then
    # --yes takes the suggestion without reading stdin (R-YES-1). Without
    # this branch the prompt below still ran: a closed stdin happened to
    # accept the suggestion, but a terminal waited for a key and piped input
    # was read as the version.
    V_NEW=$V_SUGGEST
    echo -e "\nSuggested version accepted via [--yes]: ${S_VAL}${V_NEW}${RESET}"
  else
    # Display a suggested version
    prompt_input
    printf 'Enter a new version number, %b<enter> for [%b%s%b], or <esc> to quit:%b ' \
      "${S_DIM-}" \
      "${S_VAL-}" "$V_SUGGEST" "${RESET-}${S_DIM-}" \
      "${RESET-}"

    # Two-stage read:
    #   1. Capture a single keystroke silently. If ESC → abort instantly.
    #      If Enter → accept default. Anything else → fall through.
    #   2. Hand off to readline (`read -e -i "$_first"`) so the first char
    #      is pre-filled and the whole line stays editable (backspace works).
    # Requires bash 4+ for `read -i`.
    local _first
    IFS= read -rsn1 _first
    if [ "$_first" = $'\e' ]; then
      # Terminate the (no-newline) prompt line, then abort via fail so the
      # exit code honours the contract: user abort = 5, never a raw exit.
      printf '\n'
      fail 5 \
        "version prompt aborted" \
        "Re-run and enter a version (or <enter> for the suggestion), or pass -v <version> to skip the prompt."
    fi
    if [ -z "$_first" ]; then
      # Enter accepted the suggestion, but the silent read swallowed the
      # keystroke unechoed — terminate the (no-newline) prompt line so the
      # next section header keeps its blank line above.
      printf '\n'
      V_USR_INPUT=""
    elif [ -t 0 ] && (( ${BASH_VERSINFO[0]:-0} >= 4 )); then
      # Interactive on bash 4+: pre-fill readline so the first char stays
      # editable (backspace works). `read -i` requires both readline (-e)
      # and bash 4+; the script's #!/bin/bash on macOS resolves to bash
      # 3.2, which doesn't have it.
      read -e -r -i "$_first" V_USR_INPUT
    else
      # Bash 3.2 or piped stdin: readline unavailable — echo the first
      # char and concatenate the rest. Trade-off: backspacing past that
      # first char looks odd in the terminal but doesn't lose data.
      printf '%s' "$_first"
      read -r V_USR_INPUT
      V_USR_INPUT="${_first}${V_USR_INPUT}"
    fi

    if [ "$V_USR_INPUT" = "" ]; then
      # User accepted the suggested version
      V_NEW=$V_SUGGEST
    else
      V_NEW=$V_USR_INPUT
    fi

    # Validate whatever we end up with (suggested or entered) as SemVer.
    # This only runs in interactive path; -v already validates at parse time.
    if ! is_semver "$V_NEW"; then
      fail 3 \
        "Version '$V_NEW' is not a valid SemVer 2.0 version." \
        "Enter a SemVer 2.0 version (MAJOR.MINOR.PATCH[-prerelease][+build]), e.g. 1.2.3 or 1.2.3-rc.1."
    fi
  fi
}

# Classify a single commit per Conventional Commits. $1 = subject (first
# line), $2 = body (may be empty / multi-line). Echoes exactly one of:
# breaking | feat | fix | other. Shared by suggest-bump-level (bump
# inference) and the grouped changelog (lib/changelog.sh) so the parsing
# rules can never drift apart.
#
# Subject vs. body handling: only the subject is matched against the
# "<type>:" / "<type>!:" patterns, so a commit body that quotes a prior
# subject can't change the class. "BREAKING CHANGE:" /
# "BREAKING-CHANGE:" is matched only when it appears as a footer —
# start-of-line followed by the token and a colon.
classify-commit() {
  local subject=$1 body=${2-} line
  local re_breaking_subject='^[a-zA-Z]+(\([^)]*\))?!:'
  local re_feat='^feat(\([^)]*\))?:'
  local re_fix='^fix(\([^)]*\))?:'
  local re_breaking_footer='^BREAKING[ -]CHANGE:'

  # Breaking change via "<type>!:" — subject only.
  if [[ "$subject" =~ $re_breaking_subject ]]; then
    echo "breaking"; return
  fi

  # Breaking change footer — anchored at start of a body line.
  if [ -n "$body" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ $re_breaking_footer ]]; then
        echo "breaking"; return
      fi
    done <<< "$body"
  fi

  if [[ "$subject" =~ $re_feat ]]; then
    echo "feat"; return
  fi
  if [[ "$subject" =~ $re_fix ]]; then
    echo "fix"; return
  fi
  echo "other"
}

# Inspect commit messages since the previous version's tag and suggest the
# appropriate bump per Conventional Commits:
#   - BREAKING CHANGE / <type>! → major
#   - feat:                     → minor
#   - anything else             → patch
# Falls back to patch if no tag for previous version exists, or if parsing fails.
# Parsing rules (subject-vs-body discipline) live in classify-commit above.
suggest-bump-level() {
  local prev_tag log level="patch" record subject body
  prev_tag="${TAG_PREFIX}${1}"

  if ! git rev-parse --verify "refs/tags/${prev_tag}" >/dev/null 2>&1; then
    echo "patch"; return
  fi

  # Package scope (R-MONO-2): only commits touching the scope may drive the
  # suggestion — a sibling package's feat: must not inflate this one's bump.
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")

  # %s = subject, %b = body. RS (0x1e) separates subject/body; US (0x1f)
  # separates commits. Both are unlikely in any sane commit message.
  log=$(git log --format='%s%x1e%b%x1f' "${prev_tag}..HEAD" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null) || {
    echo "patch"; return
  }

  while IFS= read -r -d $'\x1f' record; do
    # Trim the newline git inserts between format records.
    record="${record#$'\n'}"
    [ -z "$record" ] && continue
    subject="${record%%$'\x1e'*}"
    if [[ "$record" == *$'\x1e'* ]]; then
      body="${record#*$'\x1e'}"
    else
      body=""
    fi

    case "$(classify-commit "$subject" "$body")" in
      breaking) echo "major"; return ;;
      feat)     level="minor" ;;  # never downgrade
    esac
  done <<< "$log"

  echo "$level"
}

set-v-suggest() {
  local V_PREV_LIST V_MAJOR V_MINOR V_PATCH BUMP

  # Dispatch on whether the input is a valid SemVer 2.0 string first.
  # Semver inputs take the prerelease-counter or conventional-commits branch.
  # Anything else is treated as best-effort "dotted numeric" and only bumped
  # when every component is a decimal integer.
  if is_semver "$1"; then
    # Prerelease counter bumping: if the previous version has a prerelease
    # identifier (e.g. 4.0.0-dev.6, 1.2.3-rc.1, 1.0.0-alpha), bump the
    # trailing numeric counter — or append ".1" if there isn't one. Takes
    # precedence over conventional-commit bumping because pre-release
    # workflows iterate on the same MAJOR.MINOR.PATCH.
    if [[ "$1" == *-* ]]; then
      V_SUGGEST=$(bump-prerelease "$1")
      echo -e "${S_LIGHT}Detected prerelease — bumping trailing counter → ${S_VAL}$V_SUGGEST${RESET}"
      return
    fi

    # Pristine MAJOR.MINOR.PATCH (+build): bump per conventional commits.
    # is_semver already guarantees numeric components, so we can strip any
    # build metadata and bash-arithmetic the rest without re-validating.
    IFS='.' read -r V_MAJOR V_MINOR V_PATCH <<< "${1%%+*}"
    BUMP=$(suggest-bump-level "$1")
    case "$BUMP" in
      major)
        V_MAJOR=$((V_MAJOR + 1)); V_MINOR=0; V_PATCH=0
        echo -e "${S_LIGHT}Detected breaking change — suggesting ${S_VAL}major${RESET}${S_LIGHT} bump.${RESET}"
      ;;
      minor)
        V_MINOR=$((V_MINOR + 1)); V_PATCH=0
        echo -e "${S_LIGHT}Detected feat: commits — suggesting ${S_VAL}minor${RESET}${S_LIGHT} bump.${RESET}"
      ;;
      *)
        V_PATCH=$((V_PATCH + 1))
      ;;
    esac
    V_SUGGEST="$V_MAJOR.$V_MINOR.$V_PATCH"
    return
  fi

  # Non-SemVer input: best-effort dotted-numeric bump. Split via IFS read so
  # globbing can't kick in (silences ShellCheck SC2207 too). Only bump when
  # every component is a decimal integer; otherwise keep the input verbatim.
  local -a V_PREV_LIST
  IFS='.' read -r -a V_PREV_LIST <<< "$1"
  V_MAJOR=${V_PREV_LIST[0]-}
  V_MINOR=${V_PREV_LIST[1]-}
  V_PATCH=${V_PREV_LIST[2]-}

  if [ "${#V_PREV_LIST[@]}" -eq 3 ] \
     && is_number "$V_MAJOR" \
     && is_number "$V_MINOR" \
     && is_number "$V_PATCH"; then
    V_PATCH=$((V_PATCH + 1))
    V_SUGGEST="$V_MAJOR.$V_MINOR.$V_PATCH"
    return
  fi

  log_warn "${S_VAL}${1}${RESET} doesn't look like a SemVer-compatible version — couldn't bump automatically."
  # Keep the input as-is
  V_SUGGEST="$1"
}

# Bump the resolved version source (VER_FILE — package.json by default, or
# whatever --source / SOURCE_FILE points at, R-SRC-1). The built-in
# package-lock.json companion bump (R-OPT-7) applies only when the source is
# actually package.json — a --source composer.json run must not touch a
# stray lock file.
do-packagefile-bump() {
  local NOTICE_MSG BUMP_LOCK=false LOCK_PREV
  NOTICE_MSG="<${S_VAL}${VER_FILE}${RESET}>"

  # Skip entirely if the source file is absent. In tag-derived mode
  # (R-SRC-2/3) there is nothing to write, and with -v + -f the user may be
  # bumping only auxiliary JSON files — process-version already allowed the
  # missing file in both paths.
  if [ ! -f "$VER_FILE" ]; then
    log_warn "${NOTICE_MSG} not found — skipping."
    return
  fi

  if [ "$V_NEW" = "$V_PREV" ]; then
    log_warn "${NOTICE_MSG} already contains version ${S_VAL}${V_PREV}${RESET}."
    return
  fi

  [ "$VER_FILE" = "package.json" ] && [ -f package-lock.json ] && BUMP_LOCK=true

  if [ "$FLAG_DRYRUN" = true ]; then
    record-effect action bump-json target "$VER_FILE" from "$V_PREV" to "$V_NEW" role source
    echo -e "${S_LIGHT}[dry-run]${RESET} would set .version = '${S_VAL}$V_NEW${RESET}' in ${VER_FILE}" >&2
    if [ "$BUMP_LOCK" = true ]; then
      # The lock file can drift from package.json — the plan records the
      # lock's actual current version (falling back to V_PREV when it can't
      # be read). Guarded so non-json dry-runs skip the extra jq read.
      if [ "${FLAG_JSON:-false}" = true ]; then
        LOCK_PREV=$(jq -r '.version // empty' package-lock.json 2>/dev/null)
        record-effect action bump-json target package-lock.json from "${LOCK_PREV:-$V_PREV}" to "$V_NEW" role lock
      fi
      echo -e "${S_LIGHT}[dry-run]${RESET} would set .version = '${S_VAL}$V_NEW${RESET}' in package-lock.json" >&2
    fi
  else
    # Bump the source file via jq (no npm dependency), preserving the file's
    # own formatting where possible (R-FMT-1..3, lib/json.sh).
    if ! json_set_version "$VER_FILE" "$V_NEW"; then
      fail 1 \
        "Error updating <${VER_FILE}>." \
        "Check that ${VER_FILE} is valid JSON (run: jq . \"${VER_FILE}\") and that the file is writable."
    fi
    # package-lock.json: update both top-level .version and (if present) the
    # root package entry .packages[""].version — matches npm's own behaviour.
    if [ "$BUMP_LOCK" = true ]; then
      # shellcheck disable=SC2016
      if ! jq_inplace package-lock.json '
        .version = $V
        | if has("packages") and (.packages | has("")) then
            .packages[""].version = $V
          else . end
      ' --arg V "$V_NEW"; then
        fail 1 \
          "Error updating <package-lock.json>." \
          "Check that package-lock.json is valid JSON (run: jq . package-lock.json) and that the file is writable."
      fi
    fi
  fi

  dryrun git add "$VER_FILE"
  GIT_MSG+="updated ${VER_FILE}, "
  if [ "$BUMP_LOCK" = true ]; then
    dryrun git add package-lock.json
    GIT_MSG+="updated package-lock.json, "
    NOTICE_MSG+=" and <${S_VAL}package-lock.json${RESET}>"
  fi

  log_success "Bumped version in ${NOTICE_MSG}."
}

# Change `version:` value in JSON files, like packager.json, composer.json, etc
bump-json-files() {
  local FILE FILE_V_PREV
  local JSON_PROCESSED=( ) # holds filenames after they've been changed

  for FILE in "${JSON_FILES[@]}"; do
    if [ -f "$FILE" ]; then
      # Get the existing version number (top-level .version only)
      FILE_V_PREV=$( jq -r '.version // empty' "$FILE" 2>/dev/null )

      if [ -z "$FILE_V_PREV" ]; then
        log_error "no .version field in <${S_VAL}$FILE${RESET}> to replace."
      elif [ "$FILE_V_PREV" = "$V_NEW" ]; then
        log_warn "<${S_VAL}$FILE${RESET}> already contains version ${S_VAL}$FILE_V_PREV${RESET}."
      elif [ "$FLAG_DRYRUN" = true ]; then
        record-effect action bump-json target "$FILE" from "$FILE_V_PREV" to "$V_NEW" role extra
        echo -e "${S_LIGHT}[dry-run]${RESET} would set .version = '${S_VAL}$V_NEW${RESET}' in ${S_VAL}$FILE${RESET} (was ${S_VAL}$FILE_V_PREV${RESET})" >&2
        GIT_MSG+="updated $FILE, "
      else
        # Preserves the file's own formatting where possible (R-FMT-1..3).
        if json_set_version "$FILE" "$V_NEW"; then
          log_success "Updated <${S_VAL}$FILE${RESET}>: ${S_VAL}$FILE_V_PREV${RESET} ${I_ARROW} ${S_VAL}$V_NEW${RESET}"
          # Add file change to commit message:
          GIT_MSG+="updated $FILE, "
        else
          log_error "failed to update <${S_VAL}$FILE${RESET}> via jq."
        fi
      fi

      JSON_PROCESSED+=("$FILE")
    else
      log_warn "file <${S_VAL}$FILE${RESET}> not found."
    fi
  done
  # Stage files that were changed:
  ((${#JSON_PROCESSED[@]})) && dryrun git add "${JSON_PROCESSED[@]}"
}

# Handle VERSION file - for backward compatibility
do-versionfile() {
  if [ -f VERSION ]; then
    GIT_MSG+="updated VERSION, "
    if [ "$FLAG_DRYRUN" = true ]; then
      record-effect action write target VERSION to "$V_NEW"
      echo -e "${S_LIGHT}[dry-run]${RESET} would write '${S_VAL}$V_NEW${RESET}' to VERSION" >&2
    else
      echo "$V_NEW" > VERSION # Overwrite file
    fi
    # Stage file for commit
    dryrun git add VERSION

    log_success "Updated [${S_VAL}VERSION${RESET}] file."
    log_warn "Deprecation: the <${S_VAL}VERSION${RESET}> file is deprecated since v0.2.0 — support will be removed in a future version."
  fi
}
