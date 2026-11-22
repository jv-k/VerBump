# Code Style & Contribution Standards

<!-- Canonical standards doc.
     Derived from verbump.sh, lib/*, test/*, and git history. -->

VerBump is a Bash release tool. Standards below reflect the conventions
already in the tree — new code should match, not invent.

## Style

### Bash

- **Target: Bash 3.2+** (macOS default). No associative arrays; use parallel
  indexed arrays (`_CONFIG_KEYS` in [lib/config.sh](../lib/config.sh) is the
  reference pattern).
- **Shebang:** every `.sh` file begins with `#!/bin/bash`. Sourced libs that
  aren't executed may follow with `# shellcheck disable=...` and `true` as
  the first statement.
- **Indent:** 2 spaces, no tabs.
- **Naming:**
  - Public / script-level functions: **kebab-case** (`process-arguments`,
    `check-dependencies`, `do-changelog`, `set-v-suggest`).
  - Reusable predicates / log helpers: **snake_case**
    (`is_number`, `is_semver`, `jq_inplace`, `log_success`, `log_warn`).
  - Internal helpers: leading underscore (`_find-rc-upward`,
    `_assert-rc-safe`, `_render_pill`, `_emit-bash-completion`).
  - Globals / env-settable config: **UPPER_SNAKE_CASE**
    (`VER_FILE`, `TAG_PREFIX`, `FLAG_DRYRUN`, `JSON_FILES`).
  - Boolean flags: `FLAG_*`, checked with `[ "$FLAG_X" = true ]`.
- **Quoting:** quote all expansions (`"$var"`, `"$@"`). Arrays expand with
  `"${arr[@]}"`. `${var-}` / `${var:-default}` is required in any path that
  may run under `set -u` or when referenced before defaults are applied.
- **Config defaults:** use `:=` assignment (`: "${TAG_PREFIX:=v}"`) in the
  entrypoint so exported env values survive sourcing. The canonical
  defaults live in `apply-config-defaults` ([lib/config.sh](../lib/config.sh));
  the entrypoint `:=` lines exist only to keep direct `source` from tests
  sane. Never overwrite a config key unconditionally.
- **Output:** prefer `printf` over `echo -e` for anything with format
  specifiers. Use `%b` for interpolated style tokens so call sites don't
  each re-`printf`.
- **Temp files:** use `mktemp`, write-then-rename for atomic updates
  (`jq_inplace` in [lib/json.sh](../lib/json.sh) is the template). Clean up
  on failure.
- **ShellCheck:** runs in CI. Suppress with inline `# shellcheck disable=SCxxxx`
  only with a comment explaining why. Never blanket-disable at file scope
  unless the suppression applies to every line (e.g. `SC2034` in
  [lib/styles.sh](../lib/styles.sh) because vars are exported for call sites).
- **Line endings:** LF only — [`.gitattributes`](../.gitattributes) pins
  `*.sh` / `*.bash` / `*.bats` to `eol=lf`; don't override it with
  `core.autocrlf`, because CRLF breaks shellcheck parsing and the bats suite.

### UI / colour discipline

Locked in by [test/ui.bats](../test/ui.bats) — changes here require updating
those regression tests.

- **Never** reference raw colour vars (`GREEN`, `RED`, `WHITE`, `LIGHTGRAY`, …)
  outside [lib/styles.sh](../lib/styles.sh). Use the semantic `S_*` tokens.
- **Narrative text = no colour.** Colour is reserved for:
  - interpolated values → `S_VAL` (green)
  - emphasis → `S_NORM` (bold of the terminal's own fg — never a fixed
    colour; the old `WHITE`/`1;37` hardcode fought light/dark themes)
  - interactive prompts → a magenta pill heading (`prompt_input` for
    free-text entry, `prompt_confirm` for y/N or press-enter pauses), then
    default-fg question text on the next line, the value in `S_VAL`, and
    the choice hint (e.g. `[N/y]`) in `S_DIM` — no leading glyph, not a
    whole-line colour wrap
  - warnings → `S_ATTN` / `S_WARN` + plain body
  - errors → via `fail` (uses `S_ERROR`)
  - dim markers → `S_LIGHT` (`[dry-run]`, `Option set:`) — theme-adaptive
    dim, never the old fixed `LIGHTGRAY`/`0;37`
- **`S_NOTICE` is deprecated** — do not use on new lines.
- Every style variable must be gated by the `USE_COLOR` check in
  [lib/styles.sh](../lib/styles.sh) so `NO_COLOR` / piping / non-TTY strips
  ANSI (`CLICOLOR_FORCE` / `FORCE_COLOR` force it on).
- Use `log_success` / `log_warn` / `log_error` / `log_info` / `log_trace`
  instead of ad-hoc `echo -e` with inline tokens. Reach for `section` /
  `subsection` pills for headings, not `echo "------"` — one pill per grouped
  step (e.g. the changelog write), not a pill for every micro-step.

### Comments

- Document **why**, not what. Headers on non-obvious functions explain the
  invariant, the edge case, or the interop contract (see `fail`,
  `suggest-bump-level`, `load-config`).
- Exit-code table, Conventional-Commits parsing rules, and config
  precedence are documented in-file — keep those in sync when behaviour
  changes.
- Remove stale comments rather than layering corrections.

### Errors and exit codes

Canonical table (from `fail` in [lib/errors.sh](../lib/errors.sh)):

| Code | Meaning                                                                 |
|------|-------------------------------------------------------------------------|
| 0    | success                                                                 |
| 1    | generic error                                                           |
| 2    | usage / arg-parse error                                                 |
| 3    | precondition (dirty tree, missing tag, SemVer parse, missing dep, …)    |
| 4    | hook failure (`PRE_BUMP_CMD` / `POST_TAG_CMD` exited non-zero)          |
| 5    | user abort (declined prompt)                                            |

Always exit via `fail <code> "<message>" "<hint>"`. The hint is optional
but preferred — it turns an error into self-service. Errors go to stderr;
normal output (completion scripts, `--help`) stays on stdout so users can
pipe them cleanly.

Hint style:

- Complete imperative sentence(s), ending with a period.
- Runnable commands use the installed command name `verbump` (lowercase).
  `VerBump` is the display brand (banner, `--about`, prose) — never what
  the user types.
- Name an escape hatch when one exists (`or drop --x`, `or pass --y`, the
  matching `.verbumprc` key). If the guard has a one-shot bypass, show it.
- After a mutation, state what survived before the recovery command
  (e.g. "The tag was pushed; re-run 'gh release create <tag>' …").
- Version examples say "SemVer 2.0", not "MAJOR.MINOR.PATCH", wherever
  prerelease/build forms are accepted (`is_semver` takes the full grammar).

Every `fail` site is catalogued in the docs-site
[Errors reference](../packages/docs-site/content/docs/reference/errors.mdx)
— add a row there (and a case in `test/errors.bats`) when you add one.

## Testing

### Framework

- **bats-core** with **bats-support** + **bats-assert** (vendored under
  `test/test_helper/`, installed via `pnpm tests:install`).
- Shared setup in [test/test_helper.bash](../test/test_helper.bash). Every
  `.bats` file begins with `load 'test_helper'` — do not duplicate setup.
- Run locally: `pnpm tests:run`. Tests are expected to pass **100%**
  before any commit that changes behaviour.

### Structure

- **One `.bats` file per feature** (`args.bats`, `config.bats`,
  `install-completions.bats`, `undo.bats`, `release.bats`, `ui.bats`, …).
  Don't grow a monolith; split when a file exceeds ~30 cases or when a new
  subsystem lands.
- **Isolate git state:** anything that mutates a repo must run inside
  `scratch_repo` (a `mktemp -d`-backed throwaway with its own `git init`).
  Never `cd` into the project checkout from a test.
- **Sourcing vs running:** test helpers by `source ${profile_script}`
  then calling functions directly. Test end-to-end behaviour via
  `run ${profile_script} …`.

### Assertions

- Use `assert_success` / `assert_failure [code]` / `assert_output --partial`
  over bespoke `[ "$status" -eq 0 ]`. Exit codes on failures must be
  asserted explicitly — a test that only checks "fails" will pass on the
  wrong error.
- For user-facing output assertions, call `strip_ansi_output` immediately
  after `run` so ANSI escapes don't break `--partial` matches.
- Test the **error path with the hint** when `fail` is involved —
  regressions in hints are the easiest way to degrade UX silently.
- Inside a test body, use `bats_fail "<message>"` to force a failure
  through bats' reporter — not bare `fail`. Once a test `source`s
  VerBump's libs, `fail` is VerBump's own `<code> <msg> [<hint>]`
  error helper (asserted via `run`), which shadows bats-support's
  `fail <message>`. `test_helper.bash` captures bats-support's original
  as `bats_fail` before that can happen (see `test/fail-shadowing.bats`).

### What requires tests

- Every new flag → coverage in `args.bats` (short, long space-separated,
  `--name=value`, and error paths for missing/empty value).
- Every new exit code or `fail` site → a test in `errors.bats` asserting
  both the code and the message substring.
- UI-discipline changes → extend `ui.bats` so the regression guard keeps
  working.
- Pure helpers (`is_semver`, `bump-prerelease`, `suggest-bump-level`) →
  table-style cases covering valid, invalid, and edge inputs.

## Architecture

### Module boundaries

```text
verbump.sh          entrypoint: globals, main() orchestration
lib/args.sh          long-opt normalization, getopts parsing, pre-scanned
                     modes (--about, --undo, --completions, --release, …)
lib/version.sh       version read/suggest/prompt, prerelease iteration,
                     bump-level logic
lib/validate.sh      pure predicates (is_number, is_semver, …)
lib/changelog.sh     CHANGELOG.md generation + commit-message assembly
lib/git-checks.sh    repo preconditions (commits exist, tree clean, …)
lib/git-actions.sh   side-effecting git ops (branch, commit, tag, push,
                     GitHub release, undo) + the dryrun helper
lib/notes-agent.sh   notes agent for --release notes: prompt + context
                     build, run in an empty dir, failure → fallback (ADR-24)
lib/config.sh        .verbumprc discovery, safety checks, precedence
lib/json.sh          atomic jq_inplace JSON writes
lib/effects.sh       --dry-run --json effects accumulator + emitter (R-OUT-5)
lib/errors.sh        fail + the exit-code contract
lib/completions.sh   completion emit + --install-completions installer
lib/usage.sh         --help output
lib/ui.sh            log_* helpers, section pills, version_block
lib/styles.sh        colour/style tokens, USE_COLOR gate, header pills
lib/icons.sh         icon glyph vocabulary (I_OK, I_ERROR, …)
```

Rules:

- **[verbump.sh](../verbump.sh) orchestrates; it does not implement.** New
  behaviour goes into a `lib/*.sh` function; `main()` just calls it.
- **One module, one reason to change.** Behaviour goes in the module that
  owns its domain (version logic in `version.sh`, git side-effects in
  `git-actions.sh`); don't grow a new grab-bag helpers file.
- **[lib/styles.sh](../lib/styles.sh) is load-last** in the execute path, but
  must be safe to skip when sourced from tests (tests use default-safe
  expansions like `${S_OK-}`). Never reference a style token without the
  `${TOK-}` default form in library code.
- **Config precedence is invariant:** CLI > env > file > default, enforced
  by call ordering in `main()` (`load-config` → `apply-config-defaults` →
  `process-arguments`). Don't reorder. Don't add a fifth tier.

### Data-flow conventions

- Globals are the integration surface between phases. Document any new
  global at the top of [verbump.sh](../verbump.sh) with a one-line comment.
- Dry-run is a first-class mode: every side-effecting call goes through
  `dryrun <cmd>` (or an explicit `if [ "$FLAG_DRYRUN" = true ]` check).
  No exceptions — if a new step touches the filesystem, network, or git,
  it must honour dry-run, and the preview line goes to **stderr** with the
  `[dry-run]` prefix (PRD R-DRY-2).
- Commit-message / changelog generation is driven by **Conventional
  Commits**. The parser in `suggest-bump-level` uses
  subject-vs-body splitting via RS/US separators — if you extend it,
  preserve that discipline (never match `BREAKING CHANGE:` in a quoted
  body line).

### Dependencies

- Required external tools: `git`, `jq`. Add to `check-dependencies` if
  you introduce a new one, with an install hint. `gh` is a *conditional*
  dependency — only when `--release` is used (PRD R-REL-4).
- Node dependencies are dev-only and must not be required to run
  `verbump.sh` itself (the tool ships as a standalone script).
- **Package manager: pnpm.** `pnpm-lock.yaml` is canonical; treat
  `package-lock.json` as stale if it appears.

## Pull requests

### Title

- **Conventional Commits**, scoped: `<type>(<scope>): <subject>`.
  Types in use: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`, `ci`.
  Scopes in use: `ui`, `errors`, `config`, `args`, `version`, `git-actions`,
  `completions`, `tests`, `docs`, `publish`.
- Imperative mood, lowercase subject, no trailing period, ≤ 70 chars.
- Examples from history:
  - `feat(completions): --install-completions with shell auto-detection`
  - `fix(config): reject group-writable or attacker-owned .verbumprc`
  - `refactor(ui): strip narrative colour, reserve accents for values`

### Body

Structure mirrors the project's actual PR/commit bodies:

```text
<one-paragraph summary of what and why>

<bullet list of concrete changes, grouped by area if multi-scope>

<behavioural notes / edge cases / precedence rules touched>

Tests: <what was added — file + case count. "Full suite: N/N." when green.>

Refs #<issue>.
```

- Explain **why** in prose; leave the **what** to the bullets and the diff.
- When you hit a subtle bug during the work (e.g. ANSI sequence
  cancellation, arg-order bug), document it in the body — this is where
  future archaeologists look.
- Reference the issue. PRs without a linked issue need a justifying
  paragraph.
- Agent-authored commits/PRs use `Refs #N.`, never `Closes #N.` — a human
  closes the issue after review.

### Hygiene

- No `--no-verify`. Hooks exist for a reason.
- Release PRs use `release-<version>` branches (see `REL_PREFIX` default).
  Non-release work uses `feat/*`, `fix/*`, `refactor/*`, or
  `chore/*` to match the commit type.
- Keep the PR scoped. If you touch unrelated UI while fixing a bug,
  split the refactor into its own PR.
- **Git worktrees live inside the repo, under `.worktrees/`** (already
  gitignored, so worktree contents never show up in the parent's status).
  Name the sub-directory after the branch, e.g.
  `git worktree add .worktrees/dry-run-json -b feat/dry-run-json`. Remove it
  with `git worktree remove .worktrees/<name>` when the branch merges; don't
  scatter worktrees across `$HOME` or sibling paths.

## GitHub issues

### Templates

Two templates live in [.github/ISSUE_TEMPLATE/](../.github/ISSUE_TEMPLATE/):
`bug_report.md` and `feature_request.md`. Use them — issues opened
without a template should be rewritten to fit one before triage.

### Issue title

- Short, declarative, no type prefix (labels carry the type). Imperative
  or noun-phrase both acceptable.
- Good: `Completion script misses --about on zsh`.
- Avoid: `bug: weird thing with zsh`.

### Body expectations

- **Bugs:** what you ran, what happened, what you expected, OS +
  bash version, `verbump --about` output. A minimal reproducer
  (a scratch repo + the exact command) closes issues faster than any
  amount of prose.
- **Features:** lead with the user-facing problem, then the proposed
  shape. Mention alternatives considered — the reviewer will ask.
- Paste output inside fenced blocks; strip ANSI or note that colour is
  relevant.

### Labels

Pick **exactly one type** + any applicable area/milestone labels.

**Type** (one, required):

- `bug` — something isn't working
- `feature` — new feature or enhancement
- `docs` — README / inline docs / CHANGELOG
- `chore` — maintenance, tooling, hygiene
- `question` — user question, not an action item
- `invalid` — doesn't reproduce / not a VerBump issue
- `duplicate` — already tracked elsewhere (link the original)
- `wontfix` — out of scope by design

**Area** (zero or more):

- `tests` — bats suite, coverage, CI test runs
- `ci/cd` — workflows, release automation
- `release` — release mechanics (tagging, CHANGELOG, branch strategy)
- `distribution` — packaging, install paths, completions install

**Milestone** (one, when applicable):

- `v2.0` — targeting the 2.0.0 release
- `post-2.0` — backlog beyond 2.0.0

**Triage:**

- `help wanted` — ready for contributors, scope is clear
- (no "good first issue" yet — add if the backlog grows)

### Workflow expectations

- An issue should name a single outcome. Multi-part proposals get split
  into tracking issue + children before work starts.
- Close with a commit / PR reference. Humans close issues; agents
  reference them with `Refs #N.` and leave closing to review. If a fix
  landed without closing, comment with the commit SHA and close manually —
  don't leave resolved issues open.
