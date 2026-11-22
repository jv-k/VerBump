#!/bin/bash

# shellcheck disable=SC2288
true

get-commit-msg() {
  local CMD
  CMD=$([ ! "${V_PREV}" = "${V_NEW}" ] && echo "${V_PREV} ->" || echo "to")
  echo bumped "$CMD" "$V_NEW"
}

# Render the final bump-commit message (R-TPL-1..3, issue #69).
#   $1 = the accumulated changed-file list ("updated package.json, ..."),
#        i.e. GIT_MSG before the trailing "bumped ..." summary is appended.
#
# COMMIT_MSG_TEMPLATE unset/empty → legacy output, byte-identical to 1.x:
# COMMIT_MSG_PREFIX + file list + get-commit-msg (R-TPL-1).
#
# COMMIT_MSG_TEMPLATE set → the template owns the WHOLE message and
# COMMIT_MSG_PREFIX is ignored (R-TPL-2). Placeholders are replaced with
# plain bash string substitution — the template is never eval'd, so
# $(...) or `...` inside it stays literal text (R-TPL-3):
#   ${version}       the new version                   (V_NEW)
#   ${prev_version}  the previous version              (V_PREV)
#   ${tag}           the new tag                       (TAG_PREFIX + V_NEW)
#   ${files}         the generated changed-file list, without the
#                    trailing ", " the legacy assembly relies on
# Unknown placeholders pass through untouched. ${files} is substituted
# LAST so a file name that happens to contain placeholder text can't be
# substituted a second time.
#
# Both do-commit (the real commit) and do-changelog (the manual bump entry,
# written before that commit exists) MUST render through here — one
# renderer is what keeps the CHANGELOG entry and the actual commit message
# from drifting apart.
# shellcheck disable=SC2016 # the single-quoted ${...} placeholders below are literal search patterns, not expansions
render-commit-msg() {
  local files=$1

  if [ -z "${COMMIT_MSG_TEMPLATE-}" ]; then
    printf '%s' "${COMMIT_MSG_PREFIX}${files}$(get-commit-msg)"
    return 0
  fi

  # Pattern lives in a variable and is quoted at expansion, so bash treats
  # it as a literal string, not a glob — safe on bash 3.2.
  local msg="$COMMIT_MSG_TEMPLATE" ph
  local version="$V_NEW" prev="$V_PREV"
  local tag="${TAG_PREFIX}${V_NEW}" files_trimmed="${files%, }"

  # bash 5.2+ enables patsub_replacement by default, which makes `&` and
  # `\` special on the REPLACEMENT side of ${var//pat/rep} — a bumped file
  # named "R&D.json" would splice the matched placeholder back into the
  # message. Escape the values, but only when that option is active: bash
  # 3.2 substitutes replacements literally and must NOT get the extra
  # backslashes (its shopt doesn't know the option, so the block is
  # skipped). The escape expansions use double-quoted replacements, which
  # both bash generations treat literally.
  if shopt -q patsub_replacement 2>/dev/null; then
    local bs=$'\\'
    version=${version//"$bs"/"$bs$bs"};             version=${version//&/"$bs&"}
    prev=${prev//"$bs"/"$bs$bs"};                   prev=${prev//&/"$bs&"}
    tag=${tag//"$bs"/"$bs$bs"};                     tag=${tag//&/"$bs&"}
    files_trimmed=${files_trimmed//"$bs"/"$bs$bs"}; files_trimmed=${files_trimmed//&/"$bs&"}
  fi

  ph='${version}';      msg=${msg//"$ph"/$version}
  ph='${prev_version}'; msg=${msg//"$ph"/$prev}
  ph='${tag}';          msg=${msg//"$ph"/$tag}
  ph='${files}';        msg=${msg//"$ph"/$files_trimmed}
  printf '%s' "$msg"
}

capitalise() {
  echo "$(tr '[:lower:]' '[:upper:]' <<< "${1:0:1}")${1:1}"
}

# Resolve the https base URL of the GitHub remote, e.g.
# https://github.com/owner/repo — used by the grouped changelog to build
# commit and compare links (R-CHLOG-3). Prefers PUSH_DEST (where the
# release lands), falling back to origin. Handles the SSH scp form
# (git@github.com:o/r.git), ssh:// and https:// forms. Non-GitHub remote
# or no remote → return 1; callers must render plain text instead of
# links, never fail (R-CHLOG-4).
_forge-base-url() {
  local url owner_repo
  url=$(git remote get-url "${PUSH_DEST:-origin}" 2>/dev/null) \
    || url=$(git remote get-url origin 2>/dev/null) \
    || return 1

  case "$url" in
    git@github.com:*)       owner_repo="${url#git@github.com:}" ;;
    ssh://git@github.com/*) owner_repo="${url#ssh://git@github.com/}" ;;
    https://github.com/*)   owner_repo="${url#https://github.com/}" ;;
    http://github.com/*)    owner_repo="${url#http://github.com/}" ;;
    *) return 1 ;;
  esac

  owner_repo="${owner_repo%.git}"
  owner_repo="${owner_repo%/}"
  [ -n "$owner_repo" ] || return 1
  printf 'https://github.com/%s' "$owner_repo"
}

# Minimal URL-encoding for a git ref used as a path segment of a GitHub
# compare URL: "%" first (so the escapes below aren't double-encoded),
# then "/" — TAG_PREFIX may legitimately contain one (e.g. rel/), which
# would otherwise break the compare path. Other ref-legal characters are
# URL-safe in this position.
_url-encode-ref() {
  local ref=$1
  ref=${ref//%/%25}
  ref=${ref//\//%2F}
  printf '%s' "$ref"
}

# Render one subject line for the grouped changelog. A Conventional Commit
# "type(scope)!?:" prefix is stripped — the section heading already carries
# the type — and the scope becomes a bold "**scope:**" prefix (R-CHLOG-2).
# Anything that doesn't parse as a Conventional Commit renders verbatim, so
# no message is ever dropped or truncated.
_changelog-render-subject() {
  local subject=$1 scope desc
  local re='^[a-zA-Z]+(\(([^)]*)\))?!?:[[:space:]]*(.+)$'
  if [[ "$subject" =~ $re ]]; then
    scope="${BASH_REMATCH[2]}"
    desc="${BASH_REMATCH[3]}"
    if [ -n "$scope" ]; then
      printf '**%s:** %s' "$scope" "$desc"
    else
      printf '%s' "$desc"
    fi
  else
    printf '%s' "$subject"
  fi
}

# Emit the grouped (Conventional-Commit-aware) section for V_NEW on stdout.
#   $1 = git log records ("%h RS %s RS %b US" — the same RS/US record
#        discipline as suggest-bump-level, so a body that quotes a subject
#        can't split a record)
#   $2 = synthetic entry for the tool's own bump commit (that commit is
#        created after this write, so it has no SHA to link yet — same
#        manual-entry behaviour as the flat format)
#   $3 = the git-log range; non-empty exactly when the previous version's
#        tag exists, which is also the compare-link condition (R-CHLOG-3)
#
# Sections render in fixed order — Breaking Changes, Features, Fixes,
# Other — and empty sections are omitted. "Other" is the catch-all: any
# commit that isn't breaking/feat/fix lands there, including
# non-conventional messages, so nothing is ever dropped (R-CHLOG-2).
_changelog-grouped-section() {
  local records=$1 bump_entry=$2 range=$3
  local base_url record sha subject body rest entry
  local breaking="" feats="" fixes="" others=""

  base_url=$(_forge-base-url) || base_url=""

  # Version heading: link the prev...new compare view when both a previous
  # tag and a recognised forge exist; otherwise the same text as flat.
  if [ -n "$range" ] && [ -n "$base_url" ]; then
    printf '## [%s](%s/compare/%s...%s) (%s)\n' \
      "$V_NEW" "$base_url" \
      "$(_url-encode-ref "${TAG_PREFIX}${V_PREV}")" \
      "$(_url-encode-ref "${TAG_PREFIX}${V_NEW}")" "$NOW"
  else
    printf '## %s (%s)\n' "$V_NEW" "$NOW"
  fi

  # The bump commit is classified like any other commit (its section
  # follows the rendered message — the default "chore: " prefix, or a
  # COMMIT_MSG_TEMPLATE's leading type, lands it in Other/feat/fix/…).
  # Empty = no synthetic entry: render-release-notes passes "" once the real
  # bump commit exists in the range with its own SHA (R-MONO-9).
  if [ -n "$bump_entry" ]; then
    entry="- $(_changelog-render-subject "$bump_entry")"$'\n'
    case "$(classify-commit "$bump_entry" "")" in
      breaking) breaking+="$entry" ;;
      feat)     feats+="$entry" ;;
      fix)      fixes+="$entry" ;;
      *)        others+="$entry" ;;
    esac
  fi

  while IFS= read -r -d $'\x1f' record; do
    # Trim the newline git inserts between format records.
    record="${record#$'\n'}"
    [ -z "$record" ] && continue
    sha="${record%%$'\x1e'*}"
    rest="${record#*$'\x1e'}"
    subject="${rest%%$'\x1e'*}"
    if [[ "$rest" == *$'\x1e'* ]]; then
      body="${rest#*$'\x1e'}"
    else
      body=""
    fi

    entry="- $(_changelog-render-subject "$subject")"
    if [ -n "$base_url" ]; then
      # Short SHA linked to its commit. "(#N)" PR refs stay verbatim in
      # the subject — GitHub auto-links them in rendered markdown.
      entry+=" ([${sha}](${base_url}/commit/${sha}))"
    else
      entry+=" (${sha})"
    fi
    entry+=$'\n'

    case "$(classify-commit "$subject" "$body")" in
      breaking) breaking+="$entry" ;;
      feat)     feats+="$entry" ;;
      fix)      fixes+="$entry" ;;
      *)        others+="$entry" ;;
    esac
  done <<< "$records"

  [ -n "$breaking" ] && printf '\n### Breaking Changes\n\n%s' "$breaking"
  [ -n "$feats" ]    && printf '\n### Features\n\n%s' "$feats"
  [ -n "$fixes" ]    && printf '\n### Fixes\n\n%s' "$fixes"
  [ -n "$others" ]   && printf '\n### Other\n\n%s' "$others"
  return 0
}

# Dump git log history to CHANGELOG.md
#
# Two styles (R-CHLOG-1): the default "flat" bullet dump, byte-identical
# to the 1.x output, and the opt-in CHANGELOG_STYLE=grouped Conventional-
# Commit sections. Both share the same temp-file build, prepend, dry-run,
# pause and staging behaviour (R-CHLOG-5).
do-changelog() {
  [ "$FLAG_NOCHANGELOG" = true ] && return
  subsection "changelog"
  local ACTION_MSG COMMITS_MSG LOG_MSG LOG_RC RANGE TMP _chlog_line _chlog_entries

  RANGE=$([ "$(git tag -l "${TAG_PREFIX}${V_PREV}")" ] && echo "${TAG_PREFIX}${V_PREV}..HEAD")
  # Package scope (R-MONO-3): the entry lists only commits touching the
  # scope, so a sibling package's changes never pollute this changelog.
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")
  if [ "${CHANGELOG_STYLE-}" = "grouped" ]; then
    # SHA + subject + body records for grouping — see
    # _changelog-grouped-section for the separator discipline.
    # shellcheck disable=SC2086
    COMMITS_MSG=$( git log --format='%h%x1e%s%x1e%b%x1f' ${RANGE} ${scope_args[@]+"${scope_args[@]}"} 2>&1 ); LOG_RC=$?
  else
    # shellcheck disable=SC2086
    COMMITS_MSG=$( git log --pretty=format:"- %s" ${RANGE} ${scope_args[@]+"${scope_args[@]}"} 2>&1 ); LOG_RC=$?
  fi
  if [ "$LOG_RC" -ne 0 ]; then
    fail 1 \
      "Error getting commit history since last version bump for logging to CHANGELOG: ${COMMITS_MSG}" \
      "Verify the previous tag exists (git tag -l) and that 'git log ${RANGE}' runs successfully, or pass -c/--no-changelog to skip."
  fi

  if [ -f CHANGELOG.md ]; then
    ACTION_MSG="updated"
  else
    ACTION_MSG="created"
  fi
  # Add info to commit message for later:
  GIT_MSG+="${ACTION_MSG} CHANGELOG.md, "

  # Build new CHANGELOG content in a temp file next to the target, so a
  # partial write can't leave garbage in the repo root.
  TMP=$(mktemp "./CHANGELOG.md.XXXXXX")

  # The bump commit's own entry:
  # - The final commit is done after do-changelog(), so we need to create the log entry for it manually.
  # - render-commit-msg is the ONE renderer shared with do-commit, so this
  #   entry and the eventual commit message cannot drift (R-TPL-1/2). Only
  #   the first line is logged — the same subject-only view `git log %s`
  #   gives every other entry (a template may carry a multi-line body).
  LOG_MSG=$(render-commit-msg "$GIT_MSG")
  LOG_MSG="${LOG_MSG%%$'\n'*}"

  if [ "${CHANGELOG_STYLE-}" = "grouped" ]; then
    _changelog-grouped-section "$COMMITS_MSG" "${LOG_MSG}" "$RANGE" > "$TMP"
  else
    # Heading
    echo "## $V_NEW ($NOW)" > "$TMP"
    # Log the bumping commit
    echo "- ${LOG_MSG}" >> "$TMP"
    # Add previous commits
    [ -n "$COMMITS_MSG" ] && echo "$COMMITS_MSG" >> "$TMP"
  fi

  printf '\n' >> "$TMP"

  if [ -f CHANGELOG.md ]; then
    # Append existing log
    cat CHANGELOG.md >> "$TMP"
  else
    printf 'No existing [%bCHANGELOG.md%b] found — creating one.\n' "${S_VAL}" "${RESET}"
  fi

  if [ "$FLAG_DRYRUN" = true ]; then
    # Structured sibling of the preview below (R-OUT-5). `entries` counts the
    # commit bullets plus the bump commit's own entry — typed via
    # record-effect-raw so consumers get a number, not a string. Guarded by
    # FLAG_JSON so the counting work only happens when the payload is wanted.
    if [ "${FLAG_JSON:-false}" = true ]; then
      if [ "${CHANGELOG_STYLE-}" = "grouped" ]; then
        # Grouped records are \x1f-terminated — count the separators.
        _chlog_entries=$(printf '%s' "$COMMITS_MSG" | tr -cd '\037' | wc -c | tr -d ' ')
      else
        _chlog_entries=$(grep -c '^- ' <<<"$COMMITS_MSG" || true)
      fi
      record-effect-raw "$(jq -nc \
        --arg op "$ACTION_MSG" \
        --arg heading "$(head -n1 "$TMP")" \
        --argjson entries "$((_chlog_entries + 1))" \
        '{action:"changelog", target:"CHANGELOG.md", op:$op, heading:$heading, entries:$entries}')"
    fi
    # Subordinate to the "changelog" pill above: header via log_trace (dim
    # ↳, keeps the "[dry-run]" marker text R-DRY-2 requires), preview body
    # as a dim, 2-space-indented block — so the whole changelog step reads
    # as one grouped unit rather than narrative-coloured output.
    log_trace "[dry-run] would replace CHANGELOG.md with:" >&2
    while IFS= read -r _chlog_line || [ -n "$_chlog_line" ]; do
      printf '  %b%s%b\n' "${S_DIM-}" "$_chlog_line" "${RESET-}" >&2
    done < "$TMP"
    rm -f "$TMP"
  else
    mv -f "$TMP" CHANGELOG.md
  fi

  log_success "$( capitalise "${ACTION_MSG}" ) [${S_VAL}CHANGELOG.md${RESET}]."

  # Optionally pause & allow user to open and edit the file:
  if [ "$FLAG_CHANGELOG_PAUSE" = true ] && [ "$FLAG_DRYRUN" != true ]; then
    prompt_confirm
    printf 'Make adjustments to [%bCHANGELOG.md%b] if required now. Press <enter> to continue. ' "${S_VAL-}" "${RESET-}"
    read -r
  fi

  # Stage log file, to commit later
  dryrun git add CHANGELOG.md
}

# The commit range a release's notes cover, shared by render-release-notes
# and build-notes-prompt (lib/notes-agent.sh) so the two can't drift. Prints
# "<end> <from>". <end> is the new tag when it exists (the live path, after
# do-tag), else HEAD (dry-run, before any tag). <from> is the previous tag
# when it exists, else empty: no previous tag means the full history up to
# <end>. Tag names cannot contain spaces, so `read -r end from` splits it.
release-notes-range() {
  local tag_new="${TAG_PREFIX}${V_NEW}" tag_prev="${TAG_PREFIX}${V_PREV-}"
  local end="HEAD" from=""
  git rev-parse --verify --quiet "refs/tags/${tag_new}" >/dev/null && end="$tag_new"
  if [ -n "${V_PREV-}" ] && git rev-parse --verify --quiet "refs/tags/${tag_prev}" >/dev/null; then
    from="$tag_prev"
  fi
  printf '%s %s\n' "$end" "$from"
}

# Render the GitHub release-notes body for a package-scoped release
# (R-MONO-9): the package's changelog entry in the GROUPED style — heading,
# sections, commit links, compare link — regardless of CHANGELOG_STYLE.
# The style key governs the CHANGELOG.md file; release notes are a GitHub
# page, where the rich form is strictly better and is what the spec
# promises (#128 story 14). Rendered in-memory, so -c/--no-changelog
# degrades nothing. On the live path the new tag already exists: the range
# ends at the tag and the bump commit appears with its real SHA (no
# synthetic entry). Under --dry-run no tag exists yet: the range ends at
# HEAD and the bump commit's entry is synthesised exactly as do-changelog
# does.
render-release-notes() {
  local end from synth="" range="" span records
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")

  read -r end from <<< "$(release-notes-range)"
  if [ "$end" = HEAD ]; then
    synth=$(render-commit-msg "$GIT_MSG")
    synth="${synth%%$'\n'*}"
  fi
  if [ -n "$from" ]; then
    span="${from}..${end}"
    range="$span" # non-empty = the compare-link condition (R-CHLOG-3)
  else
    span="$end"
  fi

  records=$(git log --format='%h%x1e%s%x1e%b%x1f' "$span" ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null)
  _changelog-grouped-section "$records" "$synth" "$range"
}
