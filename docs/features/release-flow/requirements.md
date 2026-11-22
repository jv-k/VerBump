# Release flow (git actions)

The core mechanical sequence: bump files → changelog → commit → tag →
push, with three selectable workflows since PR #49 (ADR-12):
**tag-in-place** (default), **release branch** (`--branch`), and
**release PR** (`--pr`).

| ID | Requirement | Status |
| --- | --- | --- |
| R-FLOW-1 | Default is **tag-in-place**: commit + annotated tag on the current branch; no branch is created. `--branch` (or `FLAG_BRANCH=true` in `.verbumprc`) cuts a `release-<version>` branch instead (prefix overridable via `-B`). `-b`/`--no-branch` is a deprecated no-op. | ✅ shipped (PR #49) — `test/git-ops.bats` |
| R-FLOW-2 | `--pr` implies `--branch` and a push to `origin` (override with `-p`), then opens a pull request via `gh` (`check-pr-deps` preflight — conditional dependency like `--release`). Base resolves `--base` › `PR_BASE` › invocation branch › remote HEAD. | ✅ shipped (PR #49) — `test/pr.bats` |
| R-FLOW-3 | The bump commit includes every bumped file; `-n` disables commit *and* tag *and* push. | ✅ shipped |
| R-FLOW-4 | An annotated tag `<prefix><version>` is created (`-t` overrides prefix; `-m` sets the message). | ✅ shipped |
| R-FLOW-5 | `git tag` failure aborts the run with an error — never reports false success. | ✅ shipped (`5a9035a`) |
| R-FLOW-6 | With `-p <remote>` (or `--pr`) the push happens without a prompt. Without them, VerBump asks to push to `PUSH_DEST`; `-y` answers yes (R-YES-1), a decline exits `5`. | ✅ shipped |
| R-FLOW-7 | Dirty-tree and zero-commit repos are rejected as preconditions (exit `3`) before any mutation. | ✅ shipped — `lib/git-checks.sh` |
| R-FLOW-8 | A failed push ends the run with exit `1`. The local commit and tag are kept, `--pr` / `--release` do not run, and the hint gives the command that finishes the push (and the PR or release), or `--undo`. Before this, a failed push was a warning with exit `0`, so CI reported a release that never reached the remote. | ✅ shipped — `test/non-interactive.bats`, `test/pr.bats`, `test/release.bats` |

Migration note (PRD B-5): 1.x always cut a release branch; 2.0 tags in
place by default — pass `--branch` for the old behaviour.

Scope decision (#67): forge integration is GitHub-only by design —
`--pr` and `--release` shell out to `gh`; the core flow (bump →
changelog → commit → tag → push) works on any Git remote. Supporting
another forge (GitLab, Gitea) is a separate feature decision.

Modules: `lib/git-actions.sh`, `lib/git-checks.sh`, `lib/args.sh`.
Tests: `test/git-ops.bats`, `test/pr.bats`, `test/prefixes.bats`,
`test/e2e-live.bats`.

Related: [github-release](../github-release/requirements.md) (post-push),
[undo](../undo/requirements.md) (local revert, incl. tag-in-place).
