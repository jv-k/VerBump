#!/bin/bash

# shellcheck disable=SC2288
true

# Emit a shell completion script to stdout. Supported: bash, zsh, fish.
# Usage: verbump --completions <shell>
emit-completions() {
  case "$1" in
    bash) _emit-bash-completion ;;
    zsh)  _emit-zsh-completion  ;;
    fish) _emit-fish-completion ;;
    ''|-h|--help)
      echo "Usage: verbump --completions <bash|zsh|fish>"
      echo
      echo "Install:"
      echo "  bash: verbump --completions bash > /usr/local/etc/bash_completion.d/verbump"
      echo "  zsh:  verbump --completions zsh  > \"\${fpath[1]}/_verbump\"  # then autoload"
      echo "  fish: verbump --completions fish > ~/.config/fish/completions/verbump.fish"
      return 0
    ;;
    *)
      echo "Unknown shell: $1 (supported: bash, zsh, fish)" >&2
      return 1
    ;;
  esac
}

# detect-shell — print bash|zsh|fish for the user's login shell, or return 1.
# Primary signal: $SHELL basename. Fallback: parent process name. Strips any
# leading '-' (login-shell argv[0] convention).
detect-shell() {
  local shell
  if [ -n "${SHELL-}" ]; then
    shell="$(basename "$SHELL")"
  fi
  if [ -z "${shell-}" ] && command -v ps >/dev/null 2>&1; then
    shell="$(ps -p "$PPID" -o comm= 2>/dev/null | tr -d ' ')"
    shell="$(basename "$shell")"
  fi
  shell="${shell#-}"
  case "$shell" in
    bash|zsh|fish) printf '%s' "$shell" ;;
    *) return 1 ;;
  esac
}

# install-completions <shell> — generate the matching completion script and
# write it to a user-scope location that each shell is already configured to
# read. Supports bash / zsh / fish. Overwrites an existing file (content is
# deterministic). Honours FLAG_DRYRUN by printing the target path only.
install-completions() {
  local shell="$1" dir dest content
  case "$shell" in
    bash)
      dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
      dest="${dir}/verbump"
      content=$(_emit-bash-completion)
      ;;
    zsh)
      # User-scope XDG-style path. Consistent with the bash target
      # ($XDG_DATA_HOME/bash-completion/completions/) and with common
      # project-local conventions elsewhere.
      dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
      dest="${dir}/_verbump"
      content=$(_emit-zsh-completion)
      ;;
    fish)
      dir="${__fish_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/fish}/completions"
      dest="${dir}/verbump.fish"
      content=$(_emit-fish-completion)
      ;;
    *)
      fail 2 \
        "Unsupported shell: '${shell}'." \
        "Supported: bash, zsh, fish. Pass --install-completions=<shell> explicitly."
      ;;
  esac

  if [ "${FLAG_DRYRUN:-false}" = true ]; then
    printf '%b[dry-run]%b would write %s\n' "${S_LIGHT-}" "${RESET-}" "$dest" >&2
    return 0
  fi

  mkdir -p "$dir" || fail 3 \
    "Cannot create directory: ${dir}" \
    "Check filesystem permissions on the parent path."

  printf '%s\n' "$content" > "$dest" || fail 3 \
    "Cannot write to: ${dest}" \
    "Check filesystem permissions or use a writable HOME."

  log_success "Installed ${shell} completion → ${S_VAL}${dest}${RESET-}"

  if [ "$shell" = zsh ]; then
    # Probe the live zsh $fpath to see if the install dir is already on it.
    # If yes, the user just needs to rebuild the compdump cache. If no, they
    # need to prepend the dir to fpath in .zshrc — and crucially, BEFORE any
    # `source $ZSH/oh-my-zsh.sh` line, otherwise omz's compinit runs first
    # and the new entry is never scanned.
    local on_fpath=0
    if command -v zsh >/dev/null 2>&1; then
      if zsh -c "print -rl -- \$fpath" 2>/dev/null | grep -qxF "$dir"; then
        on_fpath=1
      fi
    fi
    if [ "$on_fpath" = 1 ]; then
      log_info "Rebuild zsh's completion cache to pick it up:"
      # Printed literally — the user's zsh expands ZDOTDIR (not exported to
      # us), and the (N) null-glob keeps a miss from erroring under NOMATCH.
      # shellcheck disable=SC2016
      log_trace 'rm -f ${ZDOTDIR:-$HOME}/.zcompdump*(N); exec zsh'
    else
      local dir_pretty
      if [[ "$dir" == "$HOME"* ]]; then
        dir_pretty="~${dir#"$HOME"}"
      else
        dir_pretty="$dir"
      fi
      log_info "Add this to ~/.zshrc BEFORE any 'source \$ZSH/oh-my-zsh.sh' line:"
      log_trace "fpath=(${dir_pretty} \$fpath)"
      log_info "Then rebuild the completion cache:"
      # Printed literally — the user's zsh expands ZDOTDIR (not exported to
      # us), and the (N) null-glob keeps a miss from erroring under NOMATCH.
      # shellcheck disable=SC2016
      log_trace 'rm -f ${ZDOTDIR:-$HOME}/.zcompdump*(N); exec zsh'
    fi
  fi
}

_emit-bash-completion() {
  cat <<'BASH_EOF'
# VerBump bash completion — source this or drop it in your bash_completion.d
# shellcheck disable=SC2207
_verbump() {
    local cur prev opts
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Options that take a file argument → complete .json paths
    case "$prev" in
        -f|--file|--source)
            COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
            return 0
            ;;
        --completions|--install-completions)
            COMPREPLY=( $(compgen -W 'bash zsh fish' -- "$cur") )
            return 0
            ;;
        # Options that take a free-form argument — no completion
        -v|--version|-m|--message|-p|--push|-t|--tag-prefix|-B|--branch-prefix|--undo|--update|--base|--preid|--bump)
            return 0
            ;;
    esac

    opts="--version --message --file --source --bump --push --tag-prefix --branch-prefix \
          --dry-run --no-commit --no-branch --no-changelog --pause-changelog \
          --yes --quiet --json --undo --branch --pr --base --major --minor --patch --preid --release \
          --sign --allow-dirty --allow-empty --no-fetch --no-hooks \
          --help --completions --install-completions --update --about \
          -v -m -f -p -t -B -d -n -b -c -l -y -q -h"
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}
# VerBump kept alongside verbump: pre-rename installs (npm bin, old brew
# Cellar) exposed the capitalised command, and completion matches the
# literal word typed.
complete -F _verbump verbump
complete -F _verbump verbump.sh
complete -F _verbump VerBump
BASH_EOF
}

_emit-zsh-completion() {
  cat <<'ZSH_EOF'
#compdef verbump verbump.sh VerBump
# VerBump zsh completion — put this file as _verbump in a dir on $fpath,
# then `autoload -U compinit && compinit`. (capitalised VerBump is
# registered too: pre-rename installs exposed that command name, and
# completion matches the literal word typed.)

_verbump() {
  _arguments -s -S \
    '(-v --version)'{-v,--version}'[print tool version (no arg) or set manual SemVer]::version:' \
    '(-m --message)'{-m,--message}'[custom annotated-tag message]:message:' \
    '(-f --file)'{-f,--file}'[bump version in extra JSON file]:file:_files -g "*.json"' \
    '--source[version source + primary bump target (default package.json)]:file:_files -g "*.json"' \
    '*--bump[bump a JSON/TOML/YAML/text file: <file>, <file>:@<path>, or <file>:<pattern with {{version}}>]:spec:' \
    '(-p --push)'{-p,--push}'[push branch + tag to <remote>]:remote:' \
    '(-t --tag-prefix)'{-t,--tag-prefix}'[override tag prefix]:prefix:' \
    '(-B --branch-prefix)'{-B,--branch-prefix}'[override branch prefix]:prefix:' \
    '(-d --dry-run)'{-d,--dry-run}'[print side-effects without executing]' \
    '(-n --no-commit)'{-n,--no-commit}'[disable commit (and tag + push)]' \
    '(-b --no-branch)'{-b,--no-branch}'[disable creating release branch]' \
    '(-c --no-changelog)'{-c,--no-changelog}'[disable CHANGELOG.md update]' \
    '(-l --pause-changelog)'{-l,--pause-changelog}'[pause before commit]' \
    '(-h --help)'{-h,--help}'[show help]' \
    '(-y --yes)'{-y,--yes}'[skip interactive confirmation prompts]' \
    '(-q --quiet)'{-q,--quiet}'[suppress decoration; print only the new version on stdout]' \
    '--json[with --dry-run: print the release plan as JSON on stdout]' \
    '--undo[locally delete release branch + tag for <version>]::version:' \
    '--branch[cut a release-x.x.x branch (else tag in place)]' \
    '--pr[branch + push + open a release PR via gh]' \
    '--base[base branch for --pr]:branch:' \
    '(--major --minor --patch -v --version)--major[force a major bump from the current version]' \
    '(--major --minor --patch -v --version)--minor[force a minor bump from the current version]' \
    '(--major --minor --patch -v --version)--patch[force a patch bump from the current version]' \
    '(-v --version)--preid[start or advance a prerelease line]:id:' \
    '--release[publish a GitHub release for the new tag via gh]' \
    '--sign[create a signed tag (git tag -s) instead of annotated]' \
    '--allow-dirty[skip the clean-working-tree preflight]' \
    '--allow-empty[release even with no new commits since the previous tag]' \
    '--no-fetch[skip the remote-sync preflight]' \
    '--no-hooks[skip the PRE_BUMP_CMD / POST_TAG_CMD release hooks]' \
    '--completions[emit completion script]:shell:(bash zsh fish)' \
    '--install-completions[install completion script for detected / specified shell]::shell:(bash zsh fish)' \
    '--update[update VerBump itself to the latest or a given release]::version:' \
    '--about[print branded version info and exit]'
}

_verbump "$@"
ZSH_EOF
}

_emit-fish-completion() {
  cat <<'FISH_EOF'
# VerBump fish completion — save to ~/.config/fish/completions/verbump.fish
for _cmd in verbump verbump.sh VerBump
    complete -c $_cmd -s v -l version        -d 'Print tool version (no arg) or set manual SemVer'
    complete -c $_cmd -s m -l message        -r -d 'Custom annotated-tag message'
    complete -c $_cmd -s f -l file           -r -a '(__fish_complete_suffix .json)' -d 'Bump version in extra JSON file'
    complete -c $_cmd      -l source         -r -a '(__fish_complete_suffix .json)' -d 'Version source + primary bump target'
    complete -c $_cmd      -l bump           -r -d 'Bump a JSON/TOML/YAML/text file: <file>[:@<path>|:<pattern with {{version}}>]'
    complete -c $_cmd -s p -l push           -r -d 'Push branch + tag to <remote>'
    complete -c $_cmd -s t -l tag-prefix     -r -d 'Override tag prefix'
    complete -c $_cmd -s B -l branch-prefix  -r -d 'Override branch prefix'
    complete -c $_cmd -s d -l dry-run        -d 'Print side-effects without executing'
    complete -c $_cmd -s n -l no-commit      -d 'Disable commit (and tag + push)'
    complete -c $_cmd -s b -l no-branch      -d 'Disable creating release branch'
    complete -c $_cmd -s c -l no-changelog   -d 'Disable CHANGELOG.md update'
    complete -c $_cmd -s l -l pause-changelog -d 'Pause before commit'
    complete -c $_cmd -s h -l help           -d 'Show help'
    complete -c $_cmd -s y -l yes            -d 'Skip interactive confirmation prompts'
    complete -c $_cmd -s q -l quiet          -d 'Suppress decoration; print only the new version on stdout'
    complete -c $_cmd      -l json           -d 'With --dry-run: print the release plan as JSON on stdout'
    complete -c $_cmd      -l undo           -d 'Locally delete release branch + tag for <version>'
    complete -c $_cmd      -l branch         -d 'Cut a release-x.x.x branch (else tag in place)'
    complete -c $_cmd      -l pr             -d 'Branch + push + open a release PR via gh'
    complete -c $_cmd      -l base           -r -d 'Base branch for --pr'
    complete -c $_cmd      -l major          -d 'Force a major bump from the current version'
    complete -c $_cmd      -l minor          -d 'Force a minor bump from the current version'
    complete -c $_cmd      -l patch          -d 'Force a patch bump from the current version'
    complete -c $_cmd      -l preid          -r -d 'Start or advance a prerelease line'
    complete -c $_cmd      -l release        -d 'Publish a GitHub release for the new tag via gh'
    complete -c $_cmd      -l sign           -d 'Create a signed tag (git tag -s) instead of annotated'
    complete -c $_cmd      -l allow-dirty    -d 'Skip the clean-working-tree preflight'
    complete -c $_cmd      -l allow-empty    -d 'Release even with no new commits since the previous tag'
    complete -c $_cmd      -l no-fetch       -d 'Skip the remote-sync preflight'
    complete -c $_cmd      -l no-hooks       -d 'Skip the PRE_BUMP_CMD / POST_TAG_CMD release hooks'
    complete -c $_cmd      -l completions    -x -a 'bash zsh fish' -d 'Emit completion script'
    complete -c $_cmd      -l install-completions -a 'bash zsh fish' -d 'Install completions for detected/specified shell'
    complete -c $_cmd      -l update         -d 'Update VerBump itself to the latest or a given release'
    complete -c $_cmd      -l about          -d 'Print branded version info and exit'
end
FISH_EOF
}
