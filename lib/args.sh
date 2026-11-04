#!/bin/bash

# Flags set here are consumed in other lib/*.sh modules. shellcheck lints each
# file in isolation, so it can't see the cross-module reads — silence SC2034
# for this file and rely on the modules that *read* the flags to fail loudly
# if a name drifts.
# shellcheck disable=SC2034,SC2288
true

# Translate GNU-style long options (--dry-run, --version=1.2.3, --file foo.json)
# into their short-form equivalents so getopts can process them uniformly.
# Writes the translated argv to the global array NORMALIZED_ARGV. On an
# unknown long option or a missing required value, prints an error and exits 1.
normalize-long-opts() {
  local arg name val has_val short needs_arg
  NORMALIZED_ARGV=()

  while (( $# )); do
    arg="$1"; shift
    # Bare "--" stops option processing; pass it and remaining args through
    if [ "$arg" = "--" ]; then
      NORMALIZED_ARGV+=("--" "$@")
      return 0
    fi

    # Special case: --about — print the branded version block and exit 0,
    # so users can check what they have installed without needing a
    # package.json or a git repo in the working directory.
    if [ "$arg" = "--about" ]; then
      version_block
      exit 0
    fi

    # Special case: bare --version / -v (no following value) — print the
    # branded version block and exit. With a value, fall through to the
    # generic translation so it acts as the manual SemVer setter.
    if [ "$arg" = "--version" ] || [ "$arg" = "-v" ]; then
      if (( $# == 0 )) || [ "${1:0:1}" = "-" ]; then
        local _ver
        if command -v jq >/dev/null 2>&1; then
          _ver=$(jq -r '.version // ""' "$MODULE_DIR/package.json")
        else
          _ver=$(grep -m1 '"version"' "$MODULE_DIR/package.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        fi
        # Branded pill when colour is on; a plain, parseable "VerBump X.Y.Z"
        # (program name + version, no stray pill padding) when it isn't —
        # so `verbump --version` piped into a script yields a clean token.
        if [ "${USE_COLOR:-0}" = 1 ]; then
          printf '%b VerBump v%s %b\n' "${S_HDR_SUB-}" "${_ver}" "${S_HDR_END-}"
        else
          printf 'VerBump %s\n' "${_ver}"
        fi
        exit 0
      fi
    fi

    # Special case: --install-completions[=shell] — detect the user's shell
    # (or accept an explicit override) and drop the matching completion
    # script into a user-scope location. Exits immediately.
    if [ "$arg" = "--install-completions" ] || [[ "$arg" == "--install-completions="* ]]; then
      local ic_shell ic_a
      # getopts hasn't run yet, so FLAG_DRYRUN is unset even if --dry-run
      # was seen earlier. Walk both already-normalized and remaining args
      # so install-completions can honour dry-run in either order.
      for ic_a in "$@" "${NORMALIZED_ARGV[@]}"; do
        case "$ic_a" in --dry-run|-d) FLAG_DRYRUN=true; break ;; esac
      done
      if [[ "$arg" == "--install-completions="* ]]; then
        ic_shell="${arg#--install-completions=}"
        [ -z "$ic_shell" ] && fail 2 \
          "--install-completions= requires a shell name." \
          "Supported: bash, zsh, fish."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        # Space form: --install-completions bash (mirrors --completions / --undo).
        ic_shell="$1"; shift
      else
        ic_shell=$(detect-shell) || fail 2 \
          "Could not auto-detect your shell from \$SHELL." \
          "Pass --install-completions=<bash|zsh|fish> explicitly."
      fi
      install-completions "$ic_shell"
      exit $?
    fi

    # Special case: --update [version] — update VerBump itself (R-UPD-1).
    # Runs outside a git repo, so it exits here before any preflight. Honours
    # --dry-run seen earlier or later in argv.
    if [ "$arg" = "--update" ] || [[ "$arg" == "--update="* ]]; then
      local upd_ver upd_a
      for upd_a in "$@" "${NORMALIZED_ARGV[@]}"; do
        case "$upd_a" in --dry-run|-d) FLAG_DRYRUN=true; break ;; esac
      done
      if [[ "$arg" == "--update="* ]]; then
        upd_ver="${arg#--update=}"
        [ -z "$upd_ver" ] && fail 2 \
          "--update= requires a version." \
          "Pass a SemVer 2.0 version, e.g. --update=4.2.0, or use bare --update for the latest release."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        upd_ver="$1"; shift
      else
        upd_ver=""
      fi
      do-update "$upd_ver"
      exit $?
    fi

    # Special case: --undo [version] — locally delete the release branch
    # and tag for <version>. Honours --dry-run and --yes seen earlier or
    # later in argv. Exits immediately.
    if [ "$arg" = "--undo" ] || [[ "$arg" == "--undo="* ]]; then
      local undo_ver undo_a undo_capture=""
      # do-undo runs and exits from here, before the getopts loop ever sees
      # -t/-B. Pre-scan the rest of argv for the flags it needs. -t/-B take a
      # value, so honour "-t v" / "--tag-prefix v" and "--tag-prefix=v" forms.
      for undo_a in "$@" "${NORMALIZED_ARGV[@]}"; do
        if [ -n "$undo_capture" ]; then
          case "$undo_capture" in
            t) TAG_PREFIX="$undo_a" ;;
            B) REL_PREFIX="$undo_a" ;;
          esac
          undo_capture=""
          continue
        fi
        case "$undo_a" in
          --dry-run|-d)       FLAG_DRYRUN=true ;;
          --yes|-y)           FLAG_YES=true ;;
          --quiet|-q)         FLAG_QUIET=true ;;
          -t|--tag-prefix)    undo_capture=t ;;
          -B|--branch-prefix) undo_capture=B ;;
          --tag-prefix=*)     TAG_PREFIX="${undo_a#*=}" ;;
          --branch-prefix=*)  REL_PREFIX="${undo_a#*=}" ;;
        esac
      done
      # --quiet + --undo (R-OUT-2): do-undo's confirmation prompt is
      # interactive, so --yes is mandatory. There is no "new version" to
      # report for an undo, so stdout stays completely empty: route all
      # decoration to stderr and print nothing.
      if [ "${FLAG_QUIET:-false}" = true ]; then
        if [ "${FLAG_YES:-false}" != true ]; then
          fail 2 \
            "--quiet with --undo requires --yes (the undo confirmation prompt is interactive)." \
            "Add --yes to auto-confirm the undo, or drop --quiet."
        fi
        exec 1>&2
      fi
      if [[ "$arg" == "--undo="* ]]; then
        undo_ver="${arg#--undo=}"
        [ -z "$undo_ver" ] && fail 2 \
          "--undo= requires a version." \
          "Pass a SemVer 2.0 version, e.g. --undo=1.2.0."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        undo_ver="$1"; shift
      else
        undo_ver=""
      fi
      do-undo "$undo_ver"
      exit $?
    fi

    # Special case: --completions [shell] — emit and exit immediately, so
    # users can run this without a package.json or a git repo present.
    if [ "$arg" = "--completions" ] || [[ "$arg" == "--completions="* ]]; then
      local shell
      if [[ "$arg" == "--completions="* ]]; then
        shell="${arg#--completions=}"
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        shell="$1"; shift
      else
        shell=""
      fi
      emit-completions "$shell"
      exit $?
    fi

    # --release is a long-only boolean with no short form. Set the global
    # directly and skip the getopts pipeline (which only handles single-char
    # short flags). --release=value is rejected — see the boolean-flag
    # check at the bottom of this loop for the same treatment of -d/--dry-run.
    if [ "$arg" = "--release" ]; then
      DO_RELEASE=true
      continue
    elif [[ "$arg" == "--release="* ]]; then
      fail 2 \
        "Option --release doesn't take a value." \
        "Drop the '=<value>' — --release is a boolean flag."
    fi

    # --pr — long-only boolean: open a release PR via `gh`. A PR needs its head
    # branch on the remote, so --pr implies a release branch (--branch) and a
    # push (-p origin by default; override the remote with -p). --pr=value rejected.
    if [ "$arg" = "--pr" ]; then
      DO_PR=true
      FLAG_BRANCH=true
      FLAG_PUSH=true
      continue
    elif [[ "$arg" == "--pr="* ]]; then
      fail 2 \
        "Option --pr doesn't take a value." \
        "Drop the '=<value>' — --pr is a boolean flag (use --base <branch> to set the PR target)."
    fi

    # --branch — long-only boolean: opt into cutting a release-<v> branch (the
    # pre-2.0 default). Without it (or --pr), VerBump tags the current branch.
    if [ "$arg" = "--branch" ]; then
      FLAG_BRANCH=true
      continue
    elif [[ "$arg" == "--branch="* ]]; then
      fail 2 \
        "Option --branch doesn't take a value." \
        "Drop the '=<value>' — --branch is a boolean flag (did you mean --branch-prefix=?)."
    fi

    # --allow-dirty — long-only boolean: skip the clean-working-tree preflight
    # (R-SAFE-2). Sets the ALLOW_DIRTY config key directly, so the CLI wins
    # over env / .verbumprc per R-CFG-3 (process-arguments runs last).
    if [ "$arg" = "--allow-dirty" ]; then
      ALLOW_DIRTY=true
      continue
    elif [[ "$arg" == "--allow-dirty="* ]]; then
      fail 2 \
        "Option --allow-dirty doesn't take a value." \
        "Drop the '=<value>' — --allow-dirty is a boolean flag."
    fi

    # --allow-empty — long-only boolean: force a release even when there are
    # no new commits since the previous tag (R-SAFE-16). CLI-only — no env /
    # .verbumprc contract (see the reset in process-arguments): a deliberate
    # empty release must be an explicit per-invocation choice, like --yes.
    if [ "$arg" = "--allow-empty" ]; then
      ALLOW_EMPTY=true
      continue
    elif [[ "$arg" == "--allow-empty="* ]]; then
      fail 2 \
        "Option --allow-empty doesn't take a value." \
        "Drop the '=<value>' — --allow-empty is a boolean flag."
    fi

    # --no-fetch — long-only boolean: skip the remote-sync preflight
    # (R-SAFE-8). Sets the NO_FETCH config key directly, so the CLI wins
    # over env / .verbumprc per R-CFG-3 (process-arguments runs last).
    if [ "$arg" = "--no-fetch" ]; then
      NO_FETCH=true
      continue
    elif [[ "$arg" == "--no-fetch="* ]]; then
      fail 2 \
        "Option --no-fetch doesn't take a value." \
        "Drop the '=<value>' — --no-fetch is a boolean flag."
    fi

    # --source <file.json> / --source=<file.json> — the version source and
    # primary bump target (R-SRC-1). Long-only value flag captured here like
    # --base, so it needs no getopts slot. Sets the SOURCE_FILE config key
    # directly, so the CLI wins over env / .verbumprc per R-CFG-3.
    if [ "$arg" = "--source" ] || [[ "$arg" == "--source="* ]]; then
      if [[ "$arg" == "--source="* ]]; then
        SOURCE_FILE="${arg#--source=}"
        [ -z "$SOURCE_FILE" ] && fail 2 \
          "--source= requires a file path." \
          "Pass a JSON file: --source <file.json> or --source=<file.json>."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        SOURCE_FILE="$1"; shift
      else
        fail 2 \
          "Option --source requires a file path." \
          "Pass a JSON file: --source <file.json> or --source=<file.json>."
      fi
      # To stderr: this runs in the same normalize loop as --completions, so a
      # stdout write here would corrupt `--source X --completions <shell>`.
      echo -e "\n${S_LIGHT}Option set:${RESET} version source: <${S_VAL}${SOURCE_FILE}${RESET}>" >&2
      continue
    fi

    # --bump <spec> / --bump=<spec> — register a multi-format bump target
    # (R-TGT). Long-only, repeatable, value flag (same shape as --source);
    # captured here so it needs no getopts slot. Each spec is
    # <file>[:@<path> | :<pattern with {{version}}>]. Grammar is validated
    # later in check-bump-deps (which also covers BUMP_FILES from the rc),
    # before any mutation — here we only reject an empty value.
    if [ "$arg" = "--bump" ] || [[ "$arg" == "--bump="* ]]; then
      local bump_spec
      if [[ "$arg" == "--bump="* ]]; then
        bump_spec="${arg#--bump=}"
        [ -z "$bump_spec" ] && fail 2 \
          "--bump= requires a spec." \
          "Pass <file>, <file>:@<path>, or '<file>:<pattern with {{version}}>'."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        bump_spec="$1"; shift
      else
        fail 2 \
          "Option --bump requires a spec." \
          "Pass <file>, <file>:@<path>, or '<file>:<pattern with {{version}}>'."
      fi
      BUMP_TARGETS+=("$bump_spec")
      # To stderr (same reasoning as --source): keeps stdout clean when --bump
      # precedes --completions / --quiet.
      echo -e "\n${S_LIGHT}Option set:${RESET} bump target: <${S_VAL}${bump_spec}${RESET}>" >&2
      continue
    fi

    # --json — long-only boolean: with --dry-run, emit the release plan as one
    # JSON object on stdout (R-OUT-5). CLI-only like --quiet (reset in
    # process-arguments): a machine-output mode must be an explicit
    # per-invocation choice. The --dry-run requirement and the prompt guard
    # are enforced after parsing, once FLAG_DRYRUN is known.
    if [ "$arg" = "--json" ]; then
      FLAG_JSON=true
      continue
    elif [[ "$arg" == "--json="* ]]; then
      fail 2 \
        "Option --json doesn't take a value." \
        "Drop the '=<value>' — --json is a boolean flag."
    fi

    # --no-hooks — long-only boolean: skip both release hooks (PRE_BUMP_CMD /
    # POST_TAG_CMD) for this run (R-HOOK-5) — git's --no-verify convention.
    # CLI-only like --allow-empty (reset in process-arguments): an rc or env
    # assignment must never silently disable hooks the team relies on. The
    # one-shot env bypass is emptying the key itself (PRE_BUMP_CMD= verbump …).
    if [ "$arg" = "--no-hooks" ]; then
      FLAG_NOHOOKS=true
      continue
    elif [[ "$arg" == "--no-hooks="* ]]; then
      fail 2 \
        "Option --no-hooks doesn't take a value." \
        "Drop the '=<value>' — --no-hooks is a boolean flag."
    fi

    # --sign — long-only boolean: create a signed release tag (`git tag -s`,
    # R-SIGN-1). Sets the TAG_SIGN config key directly, so the CLI wins over
    # env / .verbumprc per R-CFG-3 (process-arguments runs last). Key and
    # signing program stay in git's own config (user.signingkey, gpg.format) —
    # VerBump adds no key management; git's own error is the error surface.
    if [ "$arg" = "--sign" ]; then
      TAG_SIGN=true
      continue
    elif [[ "$arg" == "--sign="* ]]; then
      fail 2 \
        "Option --sign doesn't take a value." \
        "Drop the '=<value>' — --sign is a boolean flag."
    fi

    # --base <branch> / --base=<branch> — explicit base branch for --pr. Long-only
    # value flag (no short form), captured here like --undo so it needs no getopts slot.
    if [ "$arg" = "--base" ] || [[ "$arg" == "--base="* ]]; then
      if [[ "$arg" == "--base="* ]]; then
        PR_BASE="${arg#--base=}"
        [ -z "$PR_BASE" ] && fail 2 \
          "--base= requires a branch name." \
          "Pass a base branch: --base <branch> or --base=<branch>."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        PR_BASE="$1"; shift
      else
        fail 2 \
          "Option --base requires a branch name." \
          "Pass a base branch: --base <branch> or --base=<branch>."
      fi
      continue
    fi

    # --major / --minor / --patch — long-only boolean bump-level switches.
    # Mutually exclusive with each other; the -v / --version conflict is
    # caught later when getopts processes -v (BUMP_LEVEL is already set
    # by the time normalize-long-opts has emitted -v into NORMALIZED_ARGV).
    case "$arg" in
      --major|--minor|--patch)
        local lvl="${arg#--}"
        if [ -n "${BUMP_LEVEL-}" ]; then
          fail 2 \
            "Conflicting bump-level flags: --${BUMP_LEVEL} and ${arg} are mutually exclusive." \
            "Pass only one of --major, --minor, --patch."
        fi
        BUMP_LEVEL="$lvl"
        continue
      ;;
      --major=*|--minor=*|--patch=*)
        fail 2 \
          "Option ${arg%%=*} doesn't take a value." \
          "Drop the '=<value>' — ${arg%%=*} is a boolean flag."
      ;;
    esac

    # --preid <id> / --preid=<id> — start or advance a prerelease line
    # (R-PRE bucket, issue #64). Long-only value flag, same shape as
    # --source. Grammar-validated against the SemVer prerelease identifier
    # chain before any mutation (R-PRE-5) — is_prerelease_id lives in
    # lib/validate.sh, sourced before lib/args.sh. The -v / --version
    # conflict (R-PRE-4) is caught later when getopts processes -v, mirroring
    # the --major/--minor/--patch-vs-v check above: PRE_ID is already set by
    # the time normalize-long-opts has emitted -v into NORMALIZED_ARGV,
    # regardless of which flag appeared first on the command line.
    if [ "$arg" = "--preid" ] || [[ "$arg" == "--preid="* ]]; then
      if [[ "$arg" == "--preid="* ]]; then
        PRE_ID="${arg#--preid=}"
        [ -z "$PRE_ID" ] && fail 2 \
          "--preid= requires a value." \
          "Pass a prerelease id: --preid <id> or --preid=<id>."
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        PRE_ID="$1"; shift
      else
        fail 2 \
          "Option --preid requires a value." \
          "Pass a prerelease id: --preid <id> or --preid=<id>."
      fi
      if ! is_prerelease_id "$PRE_ID"; then
        fail 2 \
          "Invalid --preid value '${PRE_ID}': not a valid SemVer prerelease identifier." \
          "Use dot-separated alphanumeric/hyphen identifiers with no leading-zero numeric parts, e.g. rc, beta, dev-2."
      fi
      continue
    fi

    if [[ "$arg" == --*=* ]]; then
      name="${arg%%=*}"; name="${name#--}"
      val="${arg#*=}"
      has_val=1
    elif [[ "$arg" == --?* ]]; then
      name="${arg#--}"
      val=""
      has_val=0
    else
      NORMALIZED_ARGV+=("$arg")
      continue
    fi

    case "$name" in
      version)         short="-v"; needs_arg=1 ;;
      message)         short="-m"; needs_arg=1 ;;
      file)            short="-f"; needs_arg=1 ;;
      push)            short="-p"; needs_arg=1 ;;
      tag-prefix)      short="-t"; needs_arg=1 ;;
      branch-prefix)   short="-B"; needs_arg=1 ;;
      dry-run)         short="-d"; needs_arg=0 ;;
      no-commit)       short="-n"; needs_arg=0 ;;
      no-branch)       short="-b"; needs_arg=0 ;;
      no-changelog)    short="-c"; needs_arg=0 ;;
      pause-changelog) short="-l"; needs_arg=0 ;;
      help)            short="-h"; needs_arg=0 ;;
      yes)             short="-y"; needs_arg=0 ;;
      quiet)           short="-q"; needs_arg=0 ;;
      *)
        fail 2 \
          "Invalid option: --${name}" \
          "Run 'verbump --help' to see the list of supported options."
      ;;
    esac

    NORMALIZED_ARGV+=("$short")
    if (( needs_arg )); then
      if (( has_val )); then
        # Reject --name= (empty value after '='). Without this, getopts would
        # silently consume the next positional as the flag's value.
        if [ -z "$val" ]; then
          fail 2 \
            "Option --${name} requires a non-empty value." \
            "Pass a value: --${name} <value> or --${name}=<value>."
        fi
        NORMALIZED_ARGV+=("$val")
      elif (( $# )) && [ "${1:0:1}" != "-" ]; then
        NORMALIZED_ARGV+=("$1"); shift
      else
        fail 2 \
          "Option --${name} requires an argument." \
          "Pass a value: --${name} <value> or --${name}=<value>."
      fi
    elif (( has_val )); then
      fail 2 \
        "Option --${name} doesn't take a value." \
        "Drop the '=<value>' — --${name} is a boolean flag."
    fi
  done
}

# Shared guard for the machine-output modes (--quiet R-OUT-2, --json
# R-OUT-6): both capture stdout, where an interactive version prompt is a
# hung pipeline. Exits 2 with the caller's message unless the version choice
# is already non-interactive (--yes, -v, a forced level, or --preid).
_require-noninteractive-version() {
  if [ "${FLAG_YES:-false}" != true ] && [ -z "${V_USR_SUPPLIED-}" ] && [ -z "${BUMP_LEVEL-}" ] && [ -z "${PRE_ID-}" ]; then
    fail 2 \
      "$1" \
      "Add --yes to accept the suggested version, pass -v <version>, or force a level with --major/--minor/--patch/--preid."
  fi
}

# Process script options
process-arguments() {
  local OPTIONS OPTIND OPTARG

  # DO_RELEASE, BUMP_LEVEL, PRE_ID, ALLOW_EMPTY, FLAG_QUIET, and FLAG_NOHOOKS
  # are CLI-only switches with no env / .verbumprc contract. Reset them
  # before parsing so an inherited exported var — or a .verbumprc assignment
  # (load-config sources the rc as raw shell) — can't silently force a bump,
  # start/advance a prerelease, publish a release, push an empty release,
  # hide the run's output, or disable the release hooks with no flag on the
  # command line. FLAG_QUIET follows the FLAG_YES rationale (R-YES-3): a
  # hidden-output mode must be an explicit per-invocation choice.
  DO_RELEASE=false
  DO_PR=false
  BUMP_LEVEL=
  PRE_ID=
  ALLOW_EMPTY=false
  FLAG_QUIET=false
  FLAG_JSON=false
  FLAG_NOHOOKS=false
  # Effects accumulator (lib/effects.sh): reset alongside FLAG_JSON so a
  # sourced VerBump running main() twice can't leak run-1 effects into
  # run-2's --json payload (R-OUT-5).
  reset-effects

  normalize-long-opts "$@"
  set -- ${NORMALIZED_ARGV[@]+"${NORMALIZED_ARGV[@]}"}

  # -q/--quiet stream discipline (R-OUT-1): redirect BEFORE getopts runs,
  # otherwise the "Option set:" echoes below would leak to stdout whenever
  # another flag precedes -q in argv. FD 3 keeps a handle on the real stdout
  # for the single bare-version line main() prints at the end; everything
  # else — decoration, prompts, dry-run previews — lands on stderr. One
  # redirect here beats guarding every log_*/echo call site: no current or
  # future decoration line can ever leak into the captured pipeline.
  # Like the --undo pre-scan, this scan reads flag positions approximately:
  # an option *value* that begins with '-' and contains a 'q' (e.g.
  # -m "-quote") is a false positive — same accepted trade-off as the other
  # pre-scans in this file. --quiet has already been normalized to -q, and
  # clustered shorts (-yq) are matched too.
  local _qscan
  for _qscan in "$@"; do
    case "$_qscan" in
      --) break ;;
      -q*|-[!-]*q*) FLAG_QUIET=true; break ;;
    esac
  done
  # --json shares the same stream discipline (R-OUT-5): the single JSON
  # object main() emits at the end goes to the saved real stdout on FD 3,
  # everything else to stderr — so `VerBump --dry-run --json >plan.json`
  # captures nothing but JSON. FLAG_JSON is already final here
  # (normalize-long-opts set it above; it has no short form to pre-scan).
  if [ "$FLAG_QUIET" = true ] || [ "$FLAG_JSON" = true ]; then
    exec 3>&1 1>&2
  fi

  # Get positional parameters
  while getopts ":v:p:m:f:t:B:hbncdlyq" OPTIONS; do # Note: Adding the first : before the flags takes control of flags and prevents default error msgs.
    case "$OPTIONS" in
      h )
        # Show help (paged when the terminal is too short — see show-help).
        show-help
        exit 0
      ;;
      v )
        # User has supplied a version number — validate SemVer
        if ! is_semver "$OPTARG"; then
          fail 2 \
            "Version '$OPTARG' is not a valid SemVer 2.0 version (expected MAJOR.MINOR.PATCH[-prerelease][+build])." \
            "Pass a SemVer 2.0 version, e.g. -v 1.2.3 or -v 1.2.3-rc.1+build.42."
        fi
        if [ -n "${BUMP_LEVEL-}" ]; then
          fail 2 \
            "Conflicting flags: -v / --version and --${BUMP_LEVEL} are mutually exclusive." \
            "Pass either an explicit version (-v X.Y.Z) or a bump level (--${BUMP_LEVEL}), not both."
        fi
        if [ -n "${PRE_ID-}" ]; then
          fail 2 \
            "Conflicting flags: -v / --version and --preid are mutually exclusive." \
            "Pass either an explicit version (-v X.Y.Z) or --preid (optionally with --major/--minor/--patch), not both."
        fi
        V_USR_SUPPLIED=$OPTARG
      ;;
      m )
        REL_NOTE=$OPTARG
        # Custom release note
        echo -e "\n${S_LIGHT}Option set:${RESET} release note: ${S_VAL}'$REL_NOTE'${RESET}"
      ;;
      f )
        echo -e "\n${S_LIGHT}Option set:${RESET} JSON file via [-f]: <${S_VAL}${OPTARG}${RESET}>"
        # Store JSON filenames(s)
        JSON_FILES+=("$OPTARG")
      ;;
      p )
        FLAG_PUSH=true
        PUSH_DEST=${OPTARG} # Replace default with user input
        echo -e "\n${S_LIGHT}Option set:${RESET} push to <${S_VAL}${PUSH_DEST}${RESET}> as the last step."
      ;;
      t )
        TAG_PREFIX=$OPTARG
        echo -e "\n${S_LIGHT}Option set:${RESET} tag prefix: <${S_VAL}${TAG_PREFIX}${RESET}>"
      ;;
      B )
        REL_PREFIX=$OPTARG
        echo -e "\n${S_LIGHT}Option set:${RESET} branch prefix: <${S_VAL}${REL_PREFIX}${RESET}>"
      ;;
      d )
        FLAG_DRYRUN=true
        echo -e "\n${S_LIGHT}Option set:${RESET} dry-run — no files, commits, tags, or pushes will be made."
      ;;
      n )
        FLAG_NOCOMMIT=true
        echo -e "\n${S_LIGHT}Option set:${RESET} disable commit (and tag + push) after bumping files."
      ;;
      b )
        # Deprecated as of 2.0: tag-in-place is the default, so -b/--no-branch is
        # a no-op. Kept so existing scripts/CI don't hard-fail. Use --branch to opt in.
        echo -e "\n${S_LIGHT}Note:${RESET} -b/--no-branch is deprecated — tag-in-place is the default now; use --branch to cut a release branch." >&2
      ;;
      c )
        FLAG_NOCHANGELOG=true
        echo -e "\n${S_LIGHT}Option set:${RESET} disable updating CHANGELOG.md automatically."
      ;;
      l )
        FLAG_CHANGELOG_PAUSE=true
        echo -e "\n${S_LIGHT}Option set:${RESET} pause to allow amending CHANGELOG.md."
      ;;
      y )
        FLAG_YES=true
      ;;
      q )
        # Already set by the pre-scan above (which also performed the FD
        # redirect); kept here so getopts accepts the flag and direct unit
        # calls remain honest.
        FLAG_QUIET=true
      ;;
      \? )
        fail 2 \
          "Invalid option: -$OPTARG" \
          "Run 'verbump --help' to see the list of supported options."
      ;;
      : )
        fail 2 \
          "Option -$OPTARG requires an argument." \
          "Pass a value after the flag, e.g. -$OPTARG <value>."
      ;;
    esac
  done

  # -f/--file is the JSON-only forerunner of --bump. It still works exactly as
  # before (routed to bump-json-files); when it is used, nudge the user toward
  # --bump once — same JSON behaviour, plus TOML / YAML / text. Deliberately a
  # soft suggestion, not a loud "deprecated" banner.
  if [ "${#JSON_FILES[@]}" -gt 0 ]; then
    log_warn "Consider ${S_VAL}--bump${RESET} instead of -f/--file — it bumps JSON the same way, and also handles TOML / YAML / text."
  fi

  # --quiet and interactive prompts are incompatible by construction — a
  # hidden prompt is a hung pipeline (R-OUT-2). Fail fast at parse time
  # rather than mid-release. FLAG_CHANGELOG_PAUSE is checked here (not in
  # the -l getopts case) so a .verbumprc-set pause is caught too — the rc
  # was already sourced by load-config before process-arguments ran.
  if [ "$FLAG_QUIET" = true ]; then
    if [ "${FLAG_CHANGELOG_PAUSE:-false}" = true ]; then
      fail 2 \
        "--quiet is incompatible with -l/--pause-changelog (an interactive pause would hang a captured pipeline)." \
        "Drop -l/--pause-changelog (or unset FLAG_CHANGELOG_PAUSE in .verbumprc), or drop --quiet."
    fi
    _require-noninteractive-version \
      "--quiet would hide the interactive version prompt (a hidden prompt is a hung pipeline)."
  fi

  # --json is preview-only in v1 (R-OUT-6): it describes what a release
  # *would* do, so it is meaningful only with --dry-run. A post-run result
  # object is a possible later extension — rejecting now keeps that door
  # open without a breaking change.
  if [ "$FLAG_JSON" = true ]; then
    if [ "${FLAG_DRYRUN:-false}" != true ]; then
      fail 2 \
        "--json requires --dry-run (it emits a preview of the release plan; real runs keep their normal output)." \
        "Add -d/--dry-run, or drop --json."
    fi
    _require-noninteractive-version \
      "--json needs a non-interactive version choice (a JSON pipeline must not stop at a prompt)."
  fi
}
