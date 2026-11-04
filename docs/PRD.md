# VerBump — Product Requirements Document

| | |
| --- | --- |
| **Status** | Reconciled — matches code on `develop` |
| **Target release** | `2.0.0` |
| **Owner** | John Valai ([@jv-k](https://github.com/jv-k)) |
| **Last updated** | 2026-07-13 |
| **Supersedes** | `1.1.8` |

> Living, per-feature requirements (with test mapping and open gaps) are
> maintained in [`docs/features/`](./features/). This PRD is the release-level
> contract for `2.0.0`; architectural decisions are recorded in
> [`docs/ADR.md`](./ADR.md).

---

## 1. Summary

`VerBump` is **an opinionated release tool for Git projects with a
`package.json`** — primarily Node / JS / TS, but also usable for any SemVer
repo via `--source <file>` (or a git-tag fallback) for the version source,
plus `-f` / `--bump` for extra bump targets. It automates the mechanical
parts of cutting a release (SemVer bump, CHANGELOG, commit, tag, push),
driven by Conventional Commits, across three selectable workflows:
**tag-in-place** (default), **release branch** (`--branch`), or **release
PR** (`--pr` — opens the pull request via `gh`). See §5.14.

`2.0.0` is a correctness, ergonomics, and trust release: a long-standing
`-p` flag bug is fixed, the tool drops its hidden `npm` runtime dependency,
and it gains first-class support for SemVer validation, prerelease iteration,
conventional-commit bump suggestion, dry-run mode, GNU-style long options,
shell completions (and a one-shot `--install-completions` installer with
shell auto-detection), a branded `--about` block, a structured log
vocabulary + inverse-video section headers, and a stable exit-code contract.
It also gains a `.verbumprc` config file with strict precedence and
permission checks (§5.10), a `-y`/`--yes` non-interactive mode (§5.11),
explicit `--major`/`--minor`/`--patch` bump switches (§5.12), a local
`--undo` for reverting a release before it is pushed (§5.13), opt-in
GitHub-release publishing via `--release` (§5.8), and the three release
workflows above (§5.14).
A `dev/` sandbox harness lands alongside so changes can be exercised
end-to-end without polluting a real repo.

The release is **mostly non-additive in behaviour**: every existing short
flag keeps its argument contract, with two deliberate exceptions — bare
`-v` now prints the tool version (B-4), and the default workflow changed
from release-branch to tag-in-place (B-5; `-b`/`--no-branch` becomes a
no-op). Everything else is the tool finally doing what the original README
*said* it did, rather than whatever the 2021 implementation happened to
execute.

---

## 2. Background & motivation

`VerBump` lives in a crowded niche (`semantic-release`, `release-please`,
`release-it`, `bumpversion`, `changeset`, `goreleaser`). Its defensible pitch
is **plain bash, no Node ecosystem lock-in — `git` + `jq` only** for solo devs and
small teams that want a predictable release script.

That pitch was undermined by several issues in `1.1.x`:

| Area | `1.1.x` behaviour | Consequence |
| --- | --- | --- |
| Dependency claim | README said "pure bash"; code required `npm` to bump `package.json` | Credibility gap; dev-env friction |
| `-p` flag | README documented it as a boolean; implementation required an argument; tests expected an argument | Undefined user experience |
| `-v` validation | Accepted any string, happily tagged `vbanana` | Easy to corrupt a repo with a typo |
| Prerelease bump | Fell through to a warning and kept the input unchanged (e.g. `4.0.0-dev.6` → `4.0.0-dev.6`) | Pre-release workflows unusable without `-v` |
| Bump suggestion | Always `+1` on patch, even when commits were `feat!:` | Suggestion always wrong for meaningful releases |
| Safety | No way to preview a release; version bump commits happened unconditionally | Hard to build confidence / trust |
| File writes | `tmpfile` in CWD, `.temp` files left on failure | Dirty tree after aborted runs |
| Error surface | Hard-coded `exit 1` everywhere; no convention for scripted callers | CI wrappers couldn't distinguish bug vs. user error vs. precondition |
| Discoverability | Short flags only; no completions | High friction vs. modern CLI tools |

`2.0.0` closes every row above and adds the things that are table stakes in
comparable tools (long flags, completions, dry-run).

---

## 3. Goals

**G1 — Truthful pitch.** "Pure bash, `git` + `jq` only" must be literally
true at runtime. No `npm`, no `node`.

**G2 — Safe-by-default semantics.** Every mutating step must be previewable
via `--dry-run`. Interactive input that looks wrong must be rejected before
mutations begin, not after.

**G3 — Workflow parity with modern release tools** for the features that
matter to the target user: conventional-commit bump suggestion, prerelease
iteration, long options, shell completions.

**G4 — Stable machine contract.** Exit codes, flag semantics, and public
behaviour are documented and tested so CI wrappers and contributors can
depend on them.

**G5 — Developer ergonomics.** Contributors must be able to exercise the
real script (not just dry-run) without touching their working repo.

### 3.1 Non-goals

- **Not a CHANGELOG rewriter.** The existing `git log` dump is preserved as-is. A grouped, conventional-commit-aware changelog is scope for a later release.
- ~~**Not a monorepo release manager.**~~ *Superseded by ADR-23 (2026-07-21, issue #96/#128): VerBump supports monorepos as a **per-package** release tool — run from inside a package with a per-package `.verbumprc` (`TAG_PREFIX` + `COMMIT_PATHS`-scoped commit analysis, R-MONO). Orchestration — which packages, when, in what order — stays with the user's scripts; dependency-graph bumping and "release everything that changed" remain non-goals.*
- **Not an npm publisher.** Registry publishing stays in the user's CI. (GitHub-release creation *did* land in 2.0, behind the opt-in `--release` flag — see §5.8; it is off by default and adds no default-path dependencies.)
- **No plugin system** in this release. *Post-2.0, issue #62 added a deliberately minimal two-hook surface — `PRE_BUMP_CMD` / `POST_TAG_CMD` (R-HOOK-1..6, [`docs/features/hooks`](features/hooks/requirements.md)) — which stays short of a plugin system; exit code `4`, previously reserved, is now in use for hook failures.*

---

## 4. Target users

1. **Solo maintainer / small team lead**, Git-native, shell-comfortable, wants a predictable release step in a plain-bash script they can read.
2. **CI author** embedding `VerBump` in a GitHub Actions / GitLab CI step, needs stable exit codes and non-interactive flags.
3. **Contributor to `VerBump` itself**, needs to exercise the tool end-to-end during development.

Out of audience: users who want a GUI, users who want the tool to also publish to a registry, users who want a plugin marketplace.

---

## 5. Requirements

Each requirement has an ID so tests and PRs can reference it.

### 5.1 Dependency surface

| ID | Requirement |
| --- | --- |
| **R-DEP-1** | Runtime dependencies are exactly `bash`, `git`, `jq`. Calling `verbump.sh` on a clean machine with only those three installed must succeed. |
| **R-DEP-2** | `npm` / `node` MUST NOT be invoked at runtime. Installing via `npm -g` remains supported but is one of several install paths, not a requirement. |
| **R-DEP-3** | Missing dependencies must exit `3` with a single-line error identifying the missing tool(s) and a hint on how to install them. |

### 5.2 Version input

| ID | Requirement |
| --- | --- |
| **R-VER-1** | `-v <value>` / `--version <value>` rejects any input that is not valid SemVer 2.0 before any mutation. |
| **R-VER-2** | Interactive prompt input is validated identically to `-v`. |
| **R-VER-3** | SemVer validation accepts prerelease (`-alpha.1`) and build metadata (`+sha.abc`). |

### 5.3 Bump suggestion

| ID | Requirement |
| --- | --- |
| **R-BUMP-1** | If the current version has a prerelease identifier, the suggestion is the current version with the trailing numeric counter incremented (or `.1` appended if there is no numeric counter). Build metadata is preserved. |
| **R-BUMP-2** | Otherwise, suggestion is based on Conventional Commits between the previous tag and `HEAD`: `<type>!:` or `BREAKING CHANGE:` → major; `feat:` → minor; else patch. |
| **R-BUMP-3** | If no previous tag exists for the current version, fall back to `patch`. Never produce an invalid SemVer. |
| **R-BUMP-4** | The chosen bump level is printed to the user before the interactive prompt, so the suggestion is never silent. |

### 5.4 Flags & options

| ID | Requirement |
| --- | --- |
| **R-OPT-1** | Every short flag has a matching GNU long form. Both `--name value` and `--name=value` parse. |
| **R-OPT-2** | Boolean long options reject `--name=value` with exit `2`. |
| **R-OPT-3** | Unknown long options exit `2` with a message naming the option. |
| **R-OPT-4** | `--` stops option processing; remaining argv is forwarded verbatim. |
| **R-OPT-5** | `--completions <bash\|zsh\|fish>` emits a shell completion script to stdout and exits `0`. It does not require a `package.json`, a git repo, or any mutation. Unknown shell exits `1`. |
| **R-OPT-6** | `-t <prefix>` / `--tag-prefix` overrides the tag prefix (default `v`). `-B <prefix>` / `--branch-prefix` overrides the branch prefix (default `release-`). The chosen prefix is used consistently by every step that reads or writes tags / branches. |
| **R-OPT-7** | The repo's own `package-lock.json` is bumped built-in when present; `-f`/`--file` is for *additional* JSON files only (resolves Q-3). |
| **R-OPT-8** | `--about` prints a branded info block and exits `0` without requiring a `package.json` or git repo. Bare `-v`/`--version` (no value) prints the tool's own version — a plain, parseable `VerBump <ver>` token when colour is off — and exits `0`. |

### 5.5 Dry-run

| ID | Requirement |
| --- | --- |
| **R-DRY-1** | With `-d` / `--dry-run`, no files are written, no `git add`/`commit`/`tag`/`push`/`branch`/`checkout` is executed. |
| **R-DRY-2** | Every side-effect that would have occurred is printed to stderr with a `[dry-run]` prefix, in the order it would have been executed. |
| **R-DRY-3** | Running `--dry-run` against this repo's own checkout must not modify the working tree (regression guard). |
| **R-DRY-4** | Dry-run intercepts the push: with `-p <remote>` and `--dry-run`, no network call is made and the user is never prompted to push (resolves Q-2). |

### 5.6 Exit codes

`VerBump` commits to the following contract:

| Code | Meaning |
| ---- | ------- |
| `0`  | Success |
| `1`  | Generic / unexpected error |
| `2`  | Usage or argument-parse error (bad/unknown flag, bad value) |
| `3`  | Precondition failure (missing `git`/`jq`, no `package.json`, dirty tree, missing tag, SemVer parse failure) |
| `4`  | Hook failure — a user-supplied release hook (`PRE_BUMP_CMD` / `POST_TAG_CMD`) exited non-zero (R-HOOK-1/2, [`docs/features/hooks`](features/hooks/requirements.md)) |
| `5`  | User abort (declined an interactive prompt) |

| ID | Requirement |
| --- | --- |
| **R-EXIT-1** | Every user-visible error path must exit with a code from the table above, not a bare `exit 1`. |
| **R-EXIT-2** | The contract is versioned with the major release. It must not shift between `2.x` patch releases. |

### 5.7 Shell completions

| ID | Requirement |
| --- | --- |
| **R-COMP-1** | Emitted bash script must pass `bash -n`. Zsh script must pass `zsh -n`. Fish script must pass `fish -n` when fish is available. |
| **R-COMP-2** | Completions must offer every short and long flag. |
| **R-COMP-3** | After `-f`/`--file`, completion must restrict to `*.json`. |
| **R-COMP-4** | After `--completions`, completion must offer `bash zsh fish`. |
| **R-COMP-5** | Completions must be registered for both `VerBump` and `verbump.sh` command names. |
| **R-COMP-6** | `--install-completions [shell]` auto-detects the user's shell from `$SHELL` when no argument is given (exit `2` if detection fails), and installs the matching script to a user-scope location (zsh: `~/.local/share/zsh/site-functions`, with an oh-my-zsh-aware setup hint). |
| **R-COMP-7** | `--install-completions` honours `--dry-run` regardless of flag order on the command line. |

### 5.8 GitHub release publishing

| ID | Requirement |
| --- | --- |
| **R-REL-1** | `--release` publishes a GitHub release for the newly-created tag after the tag is pushed, invoking `gh release create <tag> --generate-notes` by default, or `--notes "<notes>"` when `VERBUMP_RELEASE_NOTES_CMD` is set (R-REL-2). |
| **R-REL-2** | By default, release notes are generated by `gh release create --generate-notes` (no dependency beyond the already-required `gh`). Setting `VERBUMP_RELEASE_NOTES_CMD` instead runs that command and passes its stdout via `--notes`. |
| **R-REL-3** | `--release` requires `-p <remote>` / `--push <remote>`. Invoking `--release` without a push remote exits `2` with a message naming the missing flag. |
| **R-REL-4** | `gh` is a **conditional** dependency: required only when `--release` is used (missing → exit `3`). A custom `VERBUMP_RELEASE_NOTES_CMD` may add further deps (e.g. `node`/`npx`), required only when it is set. R-DEP-1/2 still hold for the default path: calls without `--release` must not invoke `gh`, `node`, or `npx`. |
| **R-REL-5** | Under `--dry-run`, no `gh` call is made and no release is published. The resolved `gh release create` invocation is printed to stderr with the `[dry-run]` prefix, including the tag and the notes source (`--generate-notes` by default, or `--notes '<output>'` for a custom command). A custom notes command MAY still run (it is expected to be read-only) so the preview reflects real output; the default path runs nothing. |
| **R-REL-6** | If the notes command exits non-zero, `--release` aborts before calling `gh` and exits `1` with the captured stderr surfaced to the user. The tag push is not rolled back. |

### 5.9 Developer harness

| ID | Requirement |
| --- | --- |
| **R-DEV-1** | `pnpm dev` / `./dev/sandbox.sh` creates an isolated throwaway git repo, runs `VerBump` inside it, and cleans up on exit (including Ctrl-C). |
| **R-DEV-2** | The sandbox's cleanup must never fire against the host repo. |
| **R-DEV-3** | Environment variables `SANDBOX_VERSION` and `SANDBOX_COMMITS` customise the starting version and seed commits respectively. `--keep` / `-k` preserves the temp dir for inspection. |

### 5.10 Config file

| ID | Requirement |
| --- | --- |
| **R-CFG-1** | `.verbumprc` is discovered by walking up from `$PWD` to `/`. First match wins; absence is not an error. |
| **R-CFG-2** | Supported keys: `TAG_PREFIX`, `REL_PREFIX`, `PUSH_DEST`, `COMMIT_MSG_PREFIX`, `COMMIT_MSG_TEMPLATE`, `FLAG_BRANCH`, `PR_BASE`, `CHANGELOG_STYLE`, `FLAG_NOCHANGELOG`, `FLAG_CHANGELOG_PAUSE`, `ALLOW_DIRTY`, `NO_FETCH`, `RELEASE_BRANCHES`, `TAG_SIGN`, `SOURCE_FILE`, `BUMP_FILES`, `PRE_BUMP_CMD`, `POST_TAG_CMD`, plus deprecated `FLAG_NOBRANCH` (back-compat; superseded by `FLAG_BRANCH`). Only these participate in the precedence contract (R-CFG-3); other assignments in the file execute as plain shell (R-CFG-5) but are unsupported, warn (R-CFG-7), and carry no precedence or compatibility guarantee. |
| **R-CFG-3** | Precedence end-to-end: CLI > environment > `.verbumprc` > built-in default. |
| **R-CFG-4** | `.verbumprc` is refused (exit `3`) if world-writable, group-writable, or not owned by the invoking user. |
| **R-CFG-5** | `.verbumprc` is shell-sourced, not parsed. Failures in sourcing exit `3` with the shell error as context. |
| **R-CFG-6** | CLI-only switches with no env / rc contract (`DO_RELEASE`, `BUMP_LEVEL`) are reset before parsing so an inherited env var or rc assignment can never force a bump level or publish a release without the flag on the command line. |

### 5.11 Non-interactive mode

| ID | Requirement |
| --- | --- |
| **R-YES-1** | `-y` / `--yes` auto-accepts the suggested (or `-v`-supplied) version at the version prompt and the push confirmation — no `read` blocks the run (resolves Q-1: shipped in 2.0, not deferred). |
| **R-YES-2** | `--yes` is honoured by `--undo`'s confirmation as well, regardless of flag order. `FLAG_YES` is **not** a supported `.verbumprc` key (auto-confirmation must be an explicit per-invocation choice). |

### 5.12 Explicit bump switches

| ID | Requirement |
| --- | --- |
| **R-FORCE-1** | `--major` / `--minor` / `--patch` force the bump level, bypassing the conventional-commit suggestion. Long-only, boolean. |
| **R-FORCE-2** | The three switches are mutually exclusive with each other (exit `2` naming both flags) and conflict with `-v <version>` (exit `2`). |
| **R-FORCE-3** | A forced or explicit (`-v`) version skips the bump-suggestion machinery entirely — no suggestion is computed or printed. |

### 5.13 Local undo

| ID | Requirement |
| --- | --- |
| **R-UNDO-1** | `--undo [version]` locally deletes the release branch and tag for `<version>` (defaulting to the current `package.json` version) and reverts the bump commit when it is `HEAD`. It never touches any remote. |
| **R-UNDO-2** | `--undo` honours `--dry-run`, `--yes`, `--tag-prefix`, and `--branch-prefix` regardless of their position in argv. |
| **R-UNDO-3** | `--undo` prompts for confirmation before deleting (bypassed by `-y`). |
| **R-UNDO-4** | Aborting or refusing preconditions in `--undo` exits with contract codes (§5.6), not bare `exit 1`. |
| **R-UNDO-5** | Tag-in-place releases (§5.14) are handled: the tag is deleted and the bump commit kept. |

### 5.14 Release workflows

| ID | Requirement |
| --- | --- |
| **R-FLOW-1** | Default is **tag-in-place**: commit + annotated tag on the current branch; no branch is created. `--branch` (or `FLAG_BRANCH=true` in `.verbumprc`) cuts a `release-<version>` branch instead. `-b`/`--no-branch` is retained as a deprecated no-op. |
| **R-FLOW-2** | `--pr` implies `--branch` and a push to `origin` (override with `-p`), then opens a pull request via `gh` (conditional dependency, preflighted like `--release`). The base branch resolves `--base <branch>` › `PR_BASE` (env/`.verbumprc`) › the invocation branch › the remote's default branch. |

---

## 6. User stories

1. **US-1** — *As a solo maintainer*, I run `VerBump`, see a bump suggestion derived from my recent commits, press Enter, and the release happens. Outcome: correct bump without me having to think.
2. **US-2** — *As a maintainer working on a pre-release*, I'm on `4.0.0-dev.6`. I run `VerBump`, see `4.0.0-dev.7` suggested, press Enter.
3. **US-3** — *As a cautious maintainer*, I run `verbump --dry-run` first, read the side-effects, satisfy myself nothing surprising is about to happen, then re-run without `--dry-run`.
4. **US-4** — *As a CI author*, I run `verbump -v 1.2.3 -p origin -n` in a GH Actions job and branch on exit code: `0` succeeds, `2` fails the workflow with an "invalid input" message, `3` fails with a "precondition" message.
5. **US-5** — *As a new user*, I pipe `verbump --completions zsh` into `_verbump` on my `fpath`, restart my shell, and get tab-completion for every flag.
6. **US-6** — *As a contributor*, I clone the repo, run `pnpm dev`, and can exercise the real release flow end-to-end without touching my clone's working tree.
7. **US-7** — *As someone with a typo-prone setup*, I run `verbump -v banana` and get exit `2` with a clear message before anything is mutated.
8. **US-8** — *As a user with a custom tagging convention*, I run `verbump --tag-prefix=release/` and get `release/1.2.3` tags instead of `v1.2.3`.

---

## 7. Acceptance / success criteria

- **AC-1** All `R-*` requirements above have at least one bats test exercising them.
- **AC-2** Shellcheck (with `-x`) passes on `verbump.sh`, `lib/*.sh`, and `dev/sandbox.sh` with zero warnings.
- **AC-3** The test suite (`pnpm tests:run`) reports `0 failures`.
- **AC-4** Running `./verbump.sh --dry-run -v 1.1.9` against this repo leaves `git status --porcelain` byte-identical to its pre-run state.
- **AC-5** A fresh container with only `bash`, `git`, `jq` installed can run `./verbump.sh --dry-run -v 0.0.1` against a minimal repo without missing-dependency errors.
- **AC-6** `verbump --completions bash | bash -n` exits `0`; same for `zsh -n`.
- **AC-7** `README.md` and `./verbump.sh --help` enumerate the same set of flags.

---

## 8. Backward compatibility & migration

### 8.1 Breaking changes

- **B-1 — `-v` rejects non-SemVer.** Existing calls like `-v banana` will fail with exit `2`. This was never guaranteed; old behaviour tagged a corrupt version. **Migration**: fix the input.
- **B-2 — Exit codes change.** `1.1.x` used `exit 1` for nearly every error. `2.0.0` uses `2`/`3`/`5` for usage, precondition, and user-abort failures. **Migration**: CI wrappers that branched on exit code `0` vs. non-zero are unaffected; wrappers that branched on specific non-zero codes must update.
- **B-3 — `npm` no longer invoked.** `npm version`'s lifecycle scripts (`preversion`, `version`, `postversion`) will no longer fire as a side-effect of running `VerBump`. **Migration**: if you relied on them, invoke them explicitly or move the logic into a separate step. *Post-2.0, the release hooks (issue #62) close the common case: `PRE_BUMP_CMD="npm test"` in `.verbumprc` restores a `preversion`-style test gate — see [`docs/features/hooks`](features/hooks/requirements.md).*
- **B-4 — bare `-v` / `--version` prints the tool version.** In `1.1.x`, `-v` without a value was an argument-parse error. In `2.0.0` it prints `VerBump <ver>` and exits `0` (matching every modern CLI). With a value, `-v <semver>` keeps its `1.1.x` meaning. **Migration**: none expected — no working `1.1.x` invocation relied on the error.
- **B-5 — tag-in-place is the new default workflow.** `1.1.x` always cut a `release-<version>` branch; `2.0.0` commits and tags the current branch in place (§5.14, ADR-12). `-b`/`--no-branch` becomes a no-op. **Migration**: pass `--branch` per run, or set `FLAG_BRANCH=true` in `.verbumprc` to keep the old behaviour as a team default.

### 8.2 Non-breaking

- Every short flag keeps its argument contract from `1.1.x` (including `-p`, which always required an argument in the implementation — the docs were wrong).
- Tag prefix still defaults to `v`; branch prefix still defaults to `release-`.
- `CHANGELOG.md` format unchanged.

### 8.3 Deprecations carried forward

- The `VERSION` file is written-through for backward compatibility when present, but is never consulted as a version source (deprecated since `0.2.0`). Will be removed in `3.0.0`.

---

## 9. Dependencies

| | |
| --- | --- |
| Required at runtime | `bash ≥ 3.2`, `git`, `jq ≥ 1.5` |
| Required for tests | `bats-core`, `bats-support`, `bats-assert` |
| Required for linting | `shellcheck ≥ 0.8` |
| Conditional at runtime | `gh` — only when `--release` / `--pr` is used (default notes via `gh --generate-notes`); `node`/`npx` only if `VERBUMP_RELEASE_NOTES_CMD` is overridden with a Node-based notes command |
| Conditional at runtime | `tomlq` (TOML) / `yq` (YAML) — only when `--bump` / `BUMP_FILES` targets those formats (JSON targets need only `jq`) |
| Conditional at runtime | `tar`, `curl` (or `wget`), `sha256sum` (or `shasum`) — only when `--update` runs the shipped installer (R-UPD-3) |
| Optional | `pnpm` or `npm` (install + `dev` scripts); `zsh`, `fish` (to verify their completion scripts locally); `terminalizer` (regenerate demo GIF) |

---

## 10. Testing strategy

- **Unit level** — one `.bats` file per feature under `test/` (`args.bats`, `version.bats`, `release.bats`, `pr.bats`, `undo.bats`, `sandbox.bats`, …) covers every requirement in §5. Currently **518 tests** across 38 files — every `R-*` bucket now has coverage (AC-1 holds), including the `R-SAFE` safety preflights (`worktree-clean.bats`, `release-branch-guard.bats`, `remote-sync.bats`, `no-release.bats`).
- **Contract level** — exit-code table is asserted per branch in `fail()` unit tests (`test/errors.bats`).
- **Regression** — running the test suite must not mutate the host repo: anything touching git state runs inside a `scratch_repo` throwaway (`test/test_helper.bash`).
- **Emitted artefacts** — every completion script is syntax-checked (`bash -n` / `zsh -n` / `fish --no-execute`) in `test/completions-syntax.bats`.
- **Sandbox** — `pnpm dev` is the primary tool for exploratory E2E testing; `test/e2e-live.bats` covers a live end-to-end bump.
- **CI matrix** — bats on Ubuntu + macOS (fail-fast off); shellcheck + lint run once on Linux (Windows dropped from the matrix — CRLF made shellcheck results meaningless there).

---

## 11. Release plan

1. Land remaining uncommitted work on `develop` as `fix:` / `feat:` commits following Conventional Commits.
2. Draft `CHANGELOG.md` entry for `2.0.0` summarising each `R-*` bucket.
3. Cut a `release-2.0.0` branch via `VerBump` itself (dog-fooding against the sandbox first).
4. Open PR to `main`.
5. Tag `v2.0.0`, publish GitHub release with the PRD changelog.
6. `npm publish` (optional — install path remains supported).

---

## 12. Open questions

All resolved for 2.0:

1. **Q-1** `-y` / `--yes` — **Resolved: shipped in 2.0** (not deferred). See §5.11 R-YES.
2. **Q-2** Dry-run vs push — **Resolved: keep current behaviour.** Dry-run intercepts the push call; codified as R-DRY-4.
3. **Q-3** `-f` vs built-in `package-lock.json` bump — **Resolved: keep current behaviour**; codified as R-OPT-7.

---

## 13. Future work (post-2.0)

- **Grouped CHANGELOG** from Conventional Commits (the other major friction point vs. modern tools). *Shipped post-2.0 as opt-in `CHANGELOG_STYLE=grouped` (issue #61; R-CHLOG-1..5 in [docs/features/changelog/requirements.md](features/changelog/requirements.md)); the flat default is unchanged — flipping it is a 3.0 decision.*
- **Hook system** — a `post-push` hook remains future work. *`pre-bump` and `post-tag` shipped post-2.0 as `PRE_BUMP_CMD` / `POST_TAG_CMD` (issue #62; R-HOOK-1..6 in [docs/features/hooks/requirements.md](features/hooks/requirements.md)) and now use exit code `4` for hook failures — it is no longer reserved.*
- **Non-npm install paths** — Homebrew formula (deferred from 2.0; issue [#24](https://github.com/jv-k/VerBump/issues/24)), `basher` ([#39](https://github.com/jv-k/VerBump/issues/39)).
- **GitHub Packages publishing docs** ([#40](https://github.com/jv-k/VerBump/issues/40)).

*(Moved out of this list because they shipped in 2.0: `--major`/`--minor`/`--patch` → §5.12; config file → §5.10.)*

---

## 14. Appendix — flag inventory (for review completeness)

Exactly the flags shipping in `2.0.0`:

| Short | Long | Takes arg | Purpose |
| :---: | --- | :---: | --- |
| `-v` | `--version` | ✓ | Manual SemVer (validated); **bare** `-v`/`--version` prints the tool version (B-4) |
| `-m` | `--message` | ✓ | Annotated-tag message |
| `-f` | `--file` | ✓ | Extra JSON file to bump (repeatable) |
| — | `--source` | ✓ | Version-source manifest to read/write (default `package.json`); git-tag fallback when absent |
| — | `--bump` | ✓ | Additional file to bump by spec (repeatable); JSON-path / `{{version}}` / TOML / YAML |
| — | `--preid` | ✓ | Enter or advance a prerelease line with identifier `<id>` |
| `-p` | `--push` | ✓ | Push remote |
| `-t` | `--tag-prefix` | ✓ | Tag prefix override |
| `-B` | `--branch-prefix` | ✓ | Branch prefix override |
| `-d` | `--dry-run` | | Preview-only mode |
| `-n` | `--no-commit` | | Disable commit (and tag + push) |
| `-b` | `--no-branch` | | *(deprecated)* No-op — tag-in-place is the default (B-5) |
| `-c` | `--no-changelog` | | Disable CHANGELOG.md update |
| `-l` | `--pause-changelog` | | Pause before commit |
| `-y` | `--yes` | | Auto-accept version suggestion + push confirmation (§5.11) |
| `-q` | `--quiet` | | Suppress narrative output; print the bare new version on success |
| — | `--sign` | | Create a signed annotated tag (`git tag -s`) |
| `-h` | `--help` | | Help output |
| — | `--about` | | Branded info block; exit 0 (§5.4 R-OPT-8) |
| — | `--major` / `--minor` / `--patch` | | Force bump level; mutually exclusive (§5.12) |
| — | `--allow-dirty` | | Skip the clean-working-tree preflight (R-SAFE-2, [`docs/features/safety-preflights`](./features/safety-preflights/requirements.md)) |
| — | `--allow-empty` | | Release even with no new commits since the previous tag (R-SAFE-16) |
| — | `--no-fetch` | | Skip the remote-sync preflight (R-SAFE-8, [`docs/features/safety-preflights`](./features/safety-preflights/requirements.md)) |
| — | `--no-hooks` | | Skip the `PRE_BUMP_CMD` / `POST_TAG_CMD` release hooks (R-HOOK-5, [`docs/features/hooks`](./features/hooks/requirements.md)) |
| — | `--branch` | | Cut a `release-<version>` branch (pre-2.0 default) instead of tagging in place (§5.14) |
| — | `--pr` | | Branch + push + open a release PR via `gh`; implies push to `origin` (§5.14) |
| — | `--base` | ✓ | Base branch for `--pr` (default: resolution chain in R-FLOW-2) |
| — | `--undo` | optional | Locally revert release `<version>` — branch, tag, bump commit (§5.13) |
| — | `--completions` | ✓ | Emit completion script to stdout |
| — | `--install-completions` | optional | Install completion script; auto-detects shell (§5.7 R-COMP-6) |
| — | `--update` | optional | Update VerBump itself to the latest or a pinned release (R-UPD, [`docs/features/update`](./features/update/requirements.md)) |
| — | `--release` | | Publish GitHub release for the new tag (requires `-p`) |
| — | `--` | | Stop option processing |
