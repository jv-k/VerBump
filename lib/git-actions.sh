#!/bin/bash

# shellcheck disable=SC2288
true

# Dry-run helper: runs $@ if not in dry-run mode, otherwise prints what would run.
dryrun() {
  if [ "$FLAG_DRYRUN" = true ]; then
    echo -e "${S_LIGHT}[dry-run]${RESET} $*" >&2
    return 0
  fi
  "$@"
}

do-branch() {
  [ "$FLAG_BRANCH" = true ] || return 0

  local BRANCH_MSG

  echo -e "\nCreating release branch..."

  if [ "$FLAG_DRYRUN" = true ]; then
    record-effect action branch ref "${REL_PREFIX}${V_NEW}"
    echo -e "${S_LIGHT}[dry-run]${RESET} would run: git branch ${S_VAL}${REL_PREFIX}${V_NEW}${RESET} && git checkout ${S_VAL}${REL_PREFIX}${V_NEW}${RESET}" >&2
    log_success "Switched to (dry-run) branch '${S_VAL}${REL_PREFIX}${V_NEW}${RESET}'"
    return
  fi

  BRANCH_MSG=$(git branch "${REL_PREFIX}${V_NEW}" 2>&1)
  if [ -z "$BRANCH_MSG" ]; then
    BRANCH_MSG=$(git checkout "${REL_PREFIX}${V_NEW}" 2>&1)
    log_success "${BRANCH_MSG}"
  else
    fail 1 \
      "Failed to create release branch: ${BRANCH_MSG}" \
      "Resolve the git branch error above, or drop --branch/--pr to tag in place instead."
  fi
}

# Stage & commit all files modified by this script
do-commit() {
  [ "$FLAG_NOCOMMIT" = true ] && return

  local COMMIT_MSG COMMIT_RC FINAL_MSG

  # Tag-only release (R-SRC-3): when this run staged nothing — tag-derived
  # source (nothing to write), -c, no -f extras — `git commit` would die
  # with "nothing to commit". Skip the commit; do-tag then tags the current
  # HEAD, which is a valid release output here. GIT_MSG is the staging ledger
  # (every path that stages a file appends to it); the `git diff --cached`
  # check reads the real index in both live and dry-run, so anything staged
  # outside this run (possible under --allow-dirty) is still committed and
  # previewed identically — no dry-run-only early return that would diverge
  # from a live run's behaviour.
  if [ -z "$GIT_MSG" ] && git diff --cached --quiet 2>/dev/null; then
    log_info "Nothing staged to commit — skipping the commit; the tag will point at the current HEAD."
    return 0
  fi

  # ONE renderer, shared with do-changelog's manual bump entry, so the
  # CHANGELOG and the commit can't disagree — see render-commit-msg in
  # lib/changelog.sh (R-TPL-1..3). Applies to this bump commit only; the
  # tag message has its own knob, -m/--message (R-TPL-4).
  FINAL_MSG=$(render-commit-msg "$GIT_MSG")
  echo -e "\nCommitting..."

  if [ "$FLAG_DRYRUN" = true ]; then
    # No `paths` field: the file effects recorded before this one already
    # enumerate every path this commit would stage, in order (R-OUT-5).
    record-effect action commit message "$FINAL_MSG"
    # %q shell-quotes the message so the preview stays copy-pasteable even
    # when a template carries quotes, backslashes, or $(...) text.
    printf '%b[dry-run]%b would run: git commit -m %b%q%b\n' \
      "${S_LIGHT}" "${RESET}" "${S_VAL}" "${FINAL_MSG}" "${RESET}" >&2
    log_success "(dry-run) commit prepared"
    return
  fi

  COMMIT_MSG=$( git commit -m "${FINAL_MSG}" 2>&1 ); COMMIT_RC=$?
  if [ "$COMMIT_RC" -ne 0 ]; then
    fail 1 \
      "git commit failed: ${COMMIT_MSG}" \
      "Resolve the git commit error above, or pass -n/--no-commit to skip committing."
  else
    log_success "$COMMIT_MSG"
  fi
}

# Create a Git tag using the SemVer
do-tag() {
  # If we skipped committing, the version bumps are not persisted, so tagging
  # would point at the wrong (pre-bump) commit. Skip the tag too.
  [ "$FLAG_NOCOMMIT" = true ] && return

  local tag_msg tag_opt
  tag_msg="${REL_NOTE:-Tag version ${V_NEW}.}"
  # -a (annotated, default) vs -s (signed, R-SIGN-1): --sign / TAG_SIGN=true
  # opts into `git tag -s`. Key + program selection stays entirely in git's
  # own config (user.signingkey, gpg.format) — no preflight here; a signing
  # failure surfaces git's own error via the abort path below (R-SIGN-2).
  tag_opt="-a"
  [ "${TAG_SIGN:-false}" = true ] && tag_opt="-s"

  if [ "$FLAG_DRYRUN" = true ]; then
    # `signed` is a real boolean (record-effect-raw); a -s tag is annotated
    # too in git's model, so annotated stays true either way.
    if [ "${FLAG_JSON:-false}" = true ]; then
      record-effect-raw "$(jq -nc \
        --arg ref "${TAG_PREFIX}${V_NEW}" \
        --arg message "$tag_msg" \
        --argjson signed "$([ "$tag_opt" = "-s" ] && echo true || echo false)" \
        '{action:"tag", ref:$ref, annotated:true, signed:$signed, message:$message}')"
    fi
    # printf, not echo -e: tag_msg is user-supplied (-m/REL_NOTE) and must
    # print verbatim — %s never interprets backslash escapes.
    printf "%b[dry-run]%b would run: git tag %s %b%s%b -m '%s'\n" \
      "${S_LIGHT-}" "${RESET-}" "$tag_opt" "${S_VAL-}" "${TAG_PREFIX}${V_NEW}" "${RESET-}" "$tag_msg" >&2
    log_success "Tagged ${S_VAL}${TAG_PREFIX}${V_NEW}${RESET}"
    return
  fi

  # A failed `git tag` (e.g. bad object, signing failure, or a tag that
  # slipped past check-tag-exists) must abort — otherwise we'd report a false
  # "Tagged" success and push a branch whose tag was never created.
  if ! git tag "$tag_opt" "${TAG_PREFIX}${V_NEW}" -m "${tag_msg}"; then
    fail 1 \
      "Failed to create git tag ${TAG_PREFIX}${V_NEW} (see git output above)." \
      "If a previous run left a partial release, check 'git tag -l ${TAG_PREFIX}${V_NEW}' and your release branch, then retry."
  fi
  log_success "Tagged ${S_VAL}${TAG_PREFIX}${V_NEW}${RESET}"
}

# Pushes branch + tag to remote repo. Changes are staged by earlier functions
do-push() {
  [ "$FLAG_NOCOMMIT" = true ] && return

  local CONFIRM PUSH_MSG PUSH_RC REMOTE_REF

  if [ "$FLAG_PUSH" = true ]; then
    CONFIRM="Y"
  else
    prompt_confirm
    printf 'Push branch + tags to <%b%s%b>? %b[N/y]%b ' \
      "${S_VAL-}" "${PUSH_DEST}" "${RESET-}" "${S_DIM-}" "${RESET-}"
    read -r CONFIRM
  fi

  case "$CONFIRM" in
    [yY][eE][sS]|[yY] )
      echo -e "\nPushing branch + tag to <${S_VAL}${PUSH_DEST}${RESET}>..."
      if [ "$FLAG_BRANCH" = true ]; then
        REMOTE_REF="${REL_PREFIX}${V_NEW}"
      else
        REMOTE_REF=$(git rev-parse --abbrev-ref HEAD)
      fi

      if [ "$FLAG_DRYRUN" = true ]; then
        record-effect action push remote "${PUSH_DEST}" branch "${REMOTE_REF}" tag "${TAG_PREFIX}${V_NEW}"
        echo -e "${S_LIGHT}[dry-run]${RESET} would run: git push -u ${S_VAL}${PUSH_DEST}${RESET} ${S_VAL}${REMOTE_REF}${RESET} ${S_VAL}${TAG_PREFIX}${V_NEW}${RESET}" >&2
        log_success "(dry-run) push prepared"
        return
      fi

      PUSH_MSG=$( git push -u "${PUSH_DEST}" "${REMOTE_REF}" "${TAG_PREFIX}${V_NEW}" 2>&1 ); PUSH_RC=$?
      if [ "$PUSH_RC" -ne 0 ]; then
        # Record the failure so do-github-release won't publish a release for a
        # tag that never reached the remote (gh would otherwise auto-create the
        # tag at the wrong commit). Push stays best-effort (non-fatal) here.
        PUSH_OK=false
        log_warn "Push failed"
        log_trace "$PUSH_MSG"
      else
        log_success "$PUSH_MSG"
      fi
    ;;
    * )
      fail 5 \
        "push declined" \
        "Re-run and answer 'y' when prompted, or pass -p/--push <remote> to skip the prompt."
    ;;
  esac
}

# Validate --release preconditions. No-op unless DO_RELEASE=true.
#   - Requires -p / --push (otherwise the tag never reaches the remote and
#     `gh release create` would point at a tag that doesn't exist there).
#   - Requires `gh` on PATH. R-DEP-1/2 keep `gh` out of the default path,
#     so this is the only place VerBump cares about it.
check-release-deps() {
  [ "${DO_RELEASE:-false}" = true ] || return 0

  if [ "${FLAG_NOCOMMIT:-false}" = true ]; then
    fail 2 \
      "--release is incompatible with -n / --no-commit (no commit, tag, or push is made to release)." \
      "Drop -n / --no-commit, or drop --release."
  fi

  if [ "${FLAG_PUSH:-false}" != true ]; then
    fail 2 \
      "--release requires -p / --push <remote> (the tag must be pushed before publishing)." \
      "Add -p <remote>, e.g. verbump --release -p origin."
  fi

  if ! command -v gh >/dev/null 2>&1; then
    fail 3 \
      "--release requires the GitHub CLI (gh), but it isn't on PATH." \
      "Install gh (https://cli.github.com) or drop --release."
  fi

  # gh on PATH isn't enough: an unauthenticated gh sails through commit/tag/push
  # (git push uses its own credentials) and only fails at `gh release create`,
  # after the tag is already on the remote. Fail fast here instead. Skipped under
  # --dry-run — a preview shouldn't require live credentials.
  if [ "${FLAG_DRYRUN:-false}" != true ] && ! gh auth status >/dev/null 2>&1; then
    fail 3 \
      "--release requires an authenticated GitHub CLI, but 'gh auth status' failed." \
      "Run 'gh auth login' (or set GH_TOKEN) and retry."
  fi
}

# Validate --pr preconditions and resolve the PR base branch. No-op unless
# DO_PR=true. Mirrors check-release-deps (needs a commit + an authenticated gh).
# Must run AFTER process-version (needs V_NEW) but BEFORE do-branch, while HEAD
# is still the invocation branch — so the auto-detected base is the branch the
# release was cut from. Resolution order: --base / PR_BASE (env/.verbumprc) >
# invocation branch > remote default (<remote>/HEAD).
check-pr-deps() {
  [ "${DO_PR:-false}" = true ] || return 0

  if [ "${FLAG_NOCOMMIT:-false}" = true ]; then
    fail 2 \
      "--pr is incompatible with -n / --no-commit (a PR needs a commit to propose)." \
      "Drop -n / --no-commit, or drop --pr."
  fi

  if ! command -v gh >/dev/null 2>&1; then
    fail 3 \
      "--pr requires the GitHub CLI (gh), but it isn't on PATH." \
      "Install gh (https://cli.github.com) or drop --pr."
  fi

  # As with --release: gh on PATH isn't enough — an unauthenticated gh only
  # fails at `gh pr create`, after the branch is already pushed. Fail fast.
  # Skipped under --dry-run (a preview shouldn't require live credentials).
  if [ "${FLAG_DRYRUN:-false}" != true ] && ! gh auth status >/dev/null 2>&1; then
    fail 3 \
      "--pr requires an authenticated GitHub CLI, but 'gh auth status' failed." \
      "Run 'gh auth login' (or set GH_TOKEN) and retry."
  fi

  if [ -z "${PR_BASE:-}" ]; then
    PR_BASE=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  fi
  if [ -z "${PR_BASE:-}" ]; then
    PR_BASE=$(git symbolic-ref --quiet --short "refs/remotes/${PUSH_DEST}/HEAD" 2>/dev/null || true)
    PR_BASE="${PR_BASE#"${PUSH_DEST}/"}"
  fi
  if [ -z "${PR_BASE:-}" ]; then
    fail 3 \
      "--pr could not determine a base branch (detached HEAD and no ${PUSH_DEST}/HEAD)." \
      "Pass one explicitly: --base <branch>."
  fi

  # The PR head is the release branch; a PR into itself is invalid.
  if [ "$PR_BASE" = "${REL_PREFIX}${V_NEW}" ]; then
    fail 2 \
      "--pr base branch '${PR_BASE}' is the same as the release branch head." \
      "Pass a different base: --base <branch>."
  fi
}

# Resolve the notes the --release step publishes — the one place that picks
# the notes source (R-MONO-9, ADR-24). Sets, for the caller to consume:
#   RELEASE_NOTES_KIND       "command" | "agent" | "changelog" | "generated"
#                            (the --json `notes` value; never "agent" there,
#                            because dry-run never runs the agent)
#   RELEASE_NOTES_TEXT       the notes body; empty when gh generates it
#   RELEASE_NOTES_ARGS       the matching `gh release create` notes flags
# Sources, in precedence order: a custom $VERBUMP_RELEASE_NOTES_CMD beats
# everything; then the notes agent named by RELEASE_NOTES_AGENT (live runs
# only, R-REL-10); under a package scope the package's own changelog entry via
# render-release-notes (gh's generator can't path-scope — it would list
# foreign packages' PRs); otherwise gh --generate-notes, anchored to this tag
# series' previous tag so GitHub can't auto-pick a baseline from another
# series (amends ADR-18).
# With --fallback, skip the custom command and the agent and resolve only the
# notes a release publishes without a notes agent (ADR-24). A notes agent that
# fails prints one warning naming the cause and falls through to those notes
# (R-REL-13). A custom command runs in dry-run too, so the preview reflects
# real output (R-REL-5). If it exits non-zero, fail 1 with its stderr; the tag
# push already happened and is intentionally NOT rolled back (R-REL-6). Call it
# directly, never in $(...): the results are globals and `fail` must exit.
resolve-release-notes() {
  local notes_cmd="${VERBUMP_RELEASE_NOTES_CMD:-}"
  local agent="${RELEASE_NOTES_AGENT:-off}"
  [ "${1-}" = --fallback ] && notes_cmd="" agent=off
  # Dry-run never calls the agent (ADR-24): a preview spends no tokens.
  [ "${FLAG_DRYRUN:-false}" = true ] && agent=off
  RELEASE_NOTES_KIND="" RELEASE_NOTES_TEXT=""
  RELEASE_NOTES_ARGS=()

  if [ -z "$notes_cmd" ] && [ "$agent" != off ]; then
    if run-notes-agent "$agent"; then
      RELEASE_NOTES_KIND="agent"
      RELEASE_NOTES_TEXT="$NOTES_AGENT_OUTPUT"
      RELEASE_NOTES_ARGS=(--notes "$RELEASE_NOTES_TEXT")
      return 0
    fi
    log_warn "Notes agent '${S_VAL-}${agent}${RESET-}' ${NOTES_AGENT_ERROR} — publishing the release notes VerBump writes without it."
  fi

  if [ -n "$notes_cmd" ]; then
    # Capture stdout (notes) and stderr separately so a failure can surface a
    # useful error. `eval` so users can pass pipelines / arg lists via the env
    # var (e.g. 'echo X | tr a-z A-Z').
    local notes_err notes_rc
    notes_err=$(mktemp)
    RELEASE_NOTES_TEXT=$(eval "$notes_cmd" 2>"$notes_err"); notes_rc=$?
    if [ "$notes_rc" -ne 0 ]; then
      local err
      err=$(cat "$notes_err")
      rm -f "$notes_err"
      fail 1 \
        "release notes command failed (exit ${notes_rc}): ${notes_cmd}${err:+ — ${err}}" \
        "Fix the notes command, or unset VERBUMP_RELEASE_NOTES_CMD to use gh --generate-notes."
    fi
    rm -f "$notes_err"
    RELEASE_NOTES_KIND="command"
    RELEASE_NOTES_ARGS=(--notes "$RELEASE_NOTES_TEXT")
  elif [ "${VB_SCOPE_ACTIVE:-false}" = true ]; then
    RELEASE_NOTES_TEXT=$(render-release-notes)
    RELEASE_NOTES_KIND="changelog"
    RELEASE_NOTES_ARGS=(--notes "$RELEASE_NOTES_TEXT")
  else
    RELEASE_NOTES_KIND="generated"
    RELEASE_NOTES_ARGS=(--generate-notes)
    if [ -n "${V_PREV:-}" ] \
       && git rev-parse --verify --quiet "refs/tags/${TAG_PREFIX}${V_PREV}" >/dev/null; then
      RELEASE_NOTES_ARGS+=(--notes-start-tag "${TAG_PREFIX}${V_PREV}")
    fi
  fi
}

# Publish a GitHub release for the just-pushed tag, with the notes
# resolve-release-notes picks. Honours FLAG_DRYRUN by printing the resolved
# `gh release create` invocation to stderr instead of executing it.
do-github-release() {
  [ "${DO_RELEASE:-false}" = true ] || return 0
  # Tag was skipped, so there's nothing to publish a release against.
  [ "${FLAG_NOCOMMIT:-false}" = true ] && return 0
  # The push must have actually reached the remote. If it failed, do-push set
  # PUSH_OK=false; publishing now would make `gh release create` auto-create the
  # tag at the remote default-branch HEAD — a release at the wrong commit.
  if [ "${PUSH_OK:-true}" != true ]; then
    log_warn "Skipping GitHub release — the push did not succeed, so the tag isn't on the remote."
    log_trace "Fix the push, then run: gh release create ${TAG_PREFIX}${V_NEW}"
    return 0
  fi

  local tag pre_flag=""
  tag="${TAG_PREFIX}${V_NEW}"
  # Mark SemVer prereleases (e.g. 1.2.3-rc.1) as GitHub prereleases; gh does not
  # infer this from the tag name. Strip build metadata first so a '-' inside
  # +build-7 can't be mistaken for a prerelease segment.
  [[ "${V_NEW%%+*}" == *-* ]] && pre_flag="--prerelease"

  echo -e "\nPublishing GitHub release..."

  resolve-release-notes

  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    # notes: RELEASE_NOTES_KIND (see resolve-release-notes); prerelease is a
    # real boolean.
    if [ "${FLAG_JSON:-false}" = true ]; then
      record-effect-raw "$(jq -nc \
        --arg tag "$tag" \
        --arg notes "$RELEASE_NOTES_KIND" \
        --argjson prerelease "$([ -n "$pre_flag" ] && echo true || echo false)" \
        '{action:"github-release", tag:$tag, notes:$notes, prerelease:$prerelease}')"
    fi
    # The generated flags print as-is; a notes body prints quoted.
    local notes_preview="${RELEASE_NOTES_ARGS[*]}"
    [ "$RELEASE_NOTES_KIND" != "generated" ] && notes_preview="--notes '${RELEASE_NOTES_TEXT}'"
    echo -e "${S_LIGHT}[dry-run]${RESET} would run: gh release create ${S_VAL}${tag}${RESET} ${pre_flag:+${pre_flag} }${notes_preview}" >&2
    log_success "(dry-run) GitHub release prepared for ${S_VAL}${tag}${RESET}"
    return
  fi

  # Agent notes are printed before they are published (R-REL-12): no review
  # prompt, so the run output is where the maintainer reads them.
  if [ "$RELEASE_NOTES_KIND" = agent ]; then
    log_info "Release notes written by notes agent '${S_VAL-}${RELEASE_NOTES_AGENT}${RESET-}':"
    printf '%s\n' "$RELEASE_NOTES_TEXT"
  fi

  local gh_msg gh_rc
  local -a gh_args=("$tag" "${RELEASE_NOTES_ARGS[@]}")
  [ -n "$pre_flag" ] && gh_args+=("$pre_flag")
  gh_msg=$(gh release create "${gh_args[@]}" 2>&1); gh_rc=$?
  if [ "$gh_rc" -ne 0 ]; then
    fail 1 \
      "gh release create failed: ${gh_msg}" \
      "The tag was pushed; re-run 'gh release create ${tag}' manually once the underlying issue is fixed."
  fi
  log_success "Published GitHub release: ${gh_msg}"
}

# Open a GitHub pull request for the release branch (head = release-<v>,
# base = $PR_BASE resolved by check-pr-deps). No-op unless DO_PR=true. Like
# do-github-release, it needs a commit and a successful push (the head branch
# must be on the remote). Honours FLAG_DRYRUN by printing the resolved
# `gh pr create` invocation instead of executing it.
do-pr() {
  [ "${DO_PR:-false}" = true ] || return 0
  # No commit → no release branch content to propose.
  [ "${FLAG_NOCOMMIT:-false}" = true ] && return 0
  # The push must have reached the remote; otherwise the head branch isn't there.
  if [ "${PUSH_OK:-true}" != true ]; then
    log_warn "Skipping release PR — the push did not succeed, so the branch isn't on the remote."
    log_trace "Fix the push, then run: gh pr create --head ${REL_PREFIX}${V_NEW} --base ${PR_BASE}"
    return 0
  fi

  local head title body RANGE
  head="${REL_PREFIX}${V_NEW}"
  title="Release ${TAG_PREFIX}${V_NEW}"
  # Body mirrors the changelog entry: commits since the previous tag (same range
  # do-changelog uses), so the PR description is useful even when -c was passed.
  # Package scope (R-MONO-3): same restriction as the changelog scan.
  local -a scope_args=()
  [ "${VB_SCOPE_ACTIVE:-false}" = true ] && scope_args=(-- "${VB_SCOPE_PATHS[@]}")
  RANGE=$([ "$(git tag -l "${TAG_PREFIX}${V_PREV}")" ] && echo "${TAG_PREFIX}${V_PREV}..HEAD")
  # shellcheck disable=SC2086
  body=$( git log --pretty=format:"- %s" ${RANGE} ${scope_args[@]+"${scope_args[@]}"} 2>/dev/null )
  [ -z "$body" ] && body="Release ${TAG_PREFIX}${V_NEW} (${V_PREV} → ${V_NEW})."

  echo -e "\nOpening release PR..."

  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    record-effect action open-pr head "$head" base "$PR_BASE" title "$title"
    echo -e "${S_LIGHT}[dry-run]${RESET} would run: gh pr create --head ${S_VAL}${head}${RESET} --base ${S_VAL}${PR_BASE}${RESET} --title '${title}'" >&2
    log_success "(dry-run) release PR prepared: ${S_VAL}${head}${RESET} → ${S_VAL}${PR_BASE}${RESET}"
    return
  fi

  local pr_msg pr_rc
  pr_msg=$( gh pr create --head "$head" --base "$PR_BASE" --title "$title" --body "$body" 2>&1 ); pr_rc=$?
  if [ "$pr_rc" -ne 0 ]; then
    fail 1 \
      "gh pr create failed: ${pr_msg}" \
      "The branch + tag were pushed; re-run 'gh pr create --head ${head} --base ${PR_BASE}' once the issue is fixed."
  fi
  log_success "Opened release PR: ${pr_msg}"
}

# do-undo [<version>] — locally undo the artefacts of a prior VerBump run.
# Branch-mode release: delete the release branch + tag. Tag-in-place release
# (no branch, the 2.0 default): delete the tag and leave the bump commit in
# place. Refuses if the working tree is dirty, if the tag/branch were pushed,
# or if the branch was merged.
# Honours FLAG_DRYRUN (print plan only) and FLAG_YES (skip confirmation).
#
# Resolution order for <version>:
#   1. explicit arg ("--undo 1.2.0")
#   2. derived from current branch if it matches "${REL_PREFIX}X.Y.Z"
#   3. fail with hint
do-undo() {
  local ver="$1" branch tag remote parent_branch reply
  local -a remote_hits=()

  command -v git >/dev/null 2>&1 || fail 3 \
    "git is not installed." "Install git and retry."

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 3 \
    "Not inside a git repository." "Run --undo from inside the repo."

  if [ -z "$ver" ]; then
    local cur
    cur=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [[ -n "$cur" && "$cur" == "${REL_PREFIX}"* ]]; then
      ver="${cur#"${REL_PREFIX}"}"
    else
      fail 2 \
        "No version supplied and current branch '${cur:-<detached>}' isn't a '${REL_PREFIX}X.Y.Z' branch." \
        "Pass the version explicitly: verbump --undo <version>."
    fi
  fi

  is_semver "$ver" || fail 2 \
    "'$ver' is not a valid SemVer 2.0 version." \
    "Pass a SemVer 2.0 version, e.g. --undo 1.2.0."

  branch="${REL_PREFIX}${ver}"
  tag="${TAG_PREFIX}${ver}"

  # Refuse on dirty tree — a reset/branch-delete could destroy the user's WIP.
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    fail 3 \
      "Working tree has uncommitted changes." \
      "Stash or commit unrelated work before running --undo (untracked files are ignored)."
  fi

  git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null || fail 3 \
    "Tag '${tag}' does not exist locally — nothing to undo." \
    "Check 'git tag -l ${TAG_PREFIX}*' for what's available."

  # The release branch is optional: tag-in-place releases (the 2.0 default) have
  # a tag but no release branch. Branch present → full undo (delete branch + tag);
  # branch absent → tag-only undo (delete the tag; the bump commit stays put).
  local branch_exists=false
  if git rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null; then
    branch_exists=true
  fi

  # Pushed-state check across all remotes. If either the tag or the branch
  # exists on any remote, refuse and print the manual cleanup commands.
  while read -r remote; do
    [ -z "$remote" ] && continue
    if git ls-remote --tags "$remote" "refs/tags/${tag}" 2>/dev/null | grep -q "${tag}$"; then
      remote_hits+=("$remote: tag ${tag}")
    fi
    if git ls-remote --heads "$remote" "refs/heads/${branch}" 2>/dev/null | grep -q "${branch}$"; then
      remote_hits+=("$remote: branch ${branch}")
    fi
  done < <(git remote)

  if (( ${#remote_hits[@]} > 0 )); then
    local hit
    for hit in "${remote_hits[@]}"; do
      log_trace "$hit"
    done
    log_info "Undo manually if you really mean it:"
    log_trace "git push origin :refs/tags/${tag}      # delete remote tag"
    log_trace "git push origin --delete ${branch}    # delete remote branch"
    log_trace "git tag -d ${tag} && git branch -D ${branch}"
    fail 3 \
      "Refusing to undo — release artefacts are present on remote(s): ${remote_hits[*]}." \
      "Delete the remote tag/branch first (commands above), then re-run --undo."
  fi

  # Refuse if the release branch's tip has already been merged into another
  # branch. At that point an undo is the wrong tool; a revert commit is.
  # `--contains` returns branches whose tip has <branch>'s tip as an
  # ancestor — exactly the "already merged in" relationship we care about.
  local merged_into=()
  local b
  while read -r b; do
    [ -z "$b" ] && continue
    # Strip git's branch-line markers: '* ' (current), '+ ' (checked out in a
    # linked worktree), and any leading indent. Without the '+ ' strip, a
    # release branch live in another worktree looks like a foreign branch and
    # trips a false "already merged" refusal.
    b="${b## }"; b="${b#\* }"; b="${b#+ }"
    [[ "$b" == "$branch" ]] && continue
    [[ "$b" == "${REL_PREFIX}"* ]] && continue
    merged_into+=("$b")
  done < <(git branch --contains "$branch" 2>/dev/null)

  if (( ${#merged_into[@]} > 0 )); then
    fail 3 \
      "Branch '${branch}' is already merged into: ${merged_into[*]}" \
      "Use 'git revert' on the merge or bump commit instead — undo would lose history."
  fi

  # Branch-mode only: find a branch to switch to before deleting the release
  # branch. Skipped for tag-in-place (there's no branch to leave or delete).
  if [ "$branch_exists" = true ]; then
    # Pick a parent branch to switch to before deleting. Strategy:
    #   1. reflog — the branch checked out immediately before 'release-X.Y.Z'
    #   2. fallback — first non-release branch containing the bump's parent
    parent_branch=$(
      git reflog show --pretty='%gs' HEAD 2>/dev/null \
        | awk -v b="$branch" '
            /^checkout: moving from / {
              from=$4; to=$6
              if (to==b && from!=b) { print from; exit }
            }'
    )
    if [ -z "$parent_branch" ] || ! git rev-parse --verify --quiet "refs/heads/${parent_branch}" >/dev/null; then
      local parent_sha
      parent_sha=$(git rev-parse "${branch}^" 2>/dev/null) || parent_sha=""
      if [ -n "$parent_sha" ]; then
        while read -r b; do
          b="${b## }"; b="${b#\* }"; b="${b#+ }"
          [[ -z "$b" || "$b" == "$branch" || "$b" == "${REL_PREFIX}"* ]] && continue
          parent_branch="$b"; break
        done < <(git branch --contains "$parent_sha" 2>/dev/null)
      fi
    fi
    if [ -z "$parent_branch" ]; then
      fail 3 \
        "Could not determine which branch to switch to before deleting '${branch}'." \
        "Checkout your intended branch first, then re-run --undo."
    fi
  fi

  section "Undo"
  log_info "Plan:"
  if [ "$branch_exists" = true ]; then
    log_trace "git checkout ${parent_branch}"
    log_trace "git branch -D ${branch}"
  fi
  log_trace "git tag -d ${tag}"
  if [ "$branch_exists" != true ]; then
    log_info "Tag-in-place release: the version-bump commit stays on your current branch."
    log_trace "git reset --hard HEAD~1   # also drop the bump commit — only if it's HEAD and unpushed"
  fi

  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    printf '\n%b[dry-run]%b no changes made.\n' "${S_LIGHT-}" "${RESET-}" >&2
    return 0
  fi

  if [ "${FLAG_YES:-false}" != true ]; then
    prompt_confirm
    printf 'Proceed? %b[y/N]%b ' "${S_DIM-}" "${RESET-}"
    read -r reply
    case "${reply}" in
      y|Y|yes|YES) ;;
      *) fail 5 "undo declined" "Re-run with --yes to skip the prompt." ;;
    esac
  fi

  if [ "$branch_exists" = true ]; then
    git checkout "$parent_branch" >/dev/null 2>&1 || fail 1 \
      "Failed to checkout '${parent_branch}'." \
      "Resolve the issue manually, then re-run --undo."

    git branch -D "$branch" >/dev/null 2>&1 || fail 1 \
      "Failed to delete branch '${branch}'." \
      "Delete it manually with: git branch -D ${branch}"
  fi

  git tag -d "$tag" >/dev/null 2>&1 || fail 1 \
    "Failed to delete tag '${tag}'." \
    "Delete it manually with: git tag -d ${tag}"

  if [ "$branch_exists" = true ]; then
    log_success "Undid release ${S_VAL}${ver}${RESET-} — back on ${S_VAL}${parent_branch}${RESET-}"
  else
    log_success "Undid release ${S_VAL}${ver}${RESET-} — deleted tag ${S_VAL}${tag}${RESET-} (bump commit left in place)."
  fi
}
