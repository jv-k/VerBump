# VerBump

The domain language of `VerBump`, an opinionated release tool for Git
repositories. This glossary fixes the vocabulary the tool, its docs, and its
tests use. It is a glossary only — not a spec (see `docs/PRD.md`) and free of
implementation detail (see `docs/ADR.md`).

## Language

### The tool

**Plain-bash release tool** (the canonical self-description):
What `VerBump` is: a plain-bash release tool for Git repositories with no Node
runtime, `git` and `jq` its only default-path dependencies. `verbump.sh` is the
entry point to read; the `lib/*.sh` split is an implementation detail, so the
tool is not described by a file count.
_Avoid_: one file, single-file, one-file script

**Default path**:
The execution of a `VerBump` invocation that uses no opt-in feature flags. It
is contractually restricted to `bash`, `git`, and `jq` — the dependency freeze
recorded in ADR-15.
_Avoid_: happy path, core path

**Opt-in feature**:
A capability gated behind an explicit flag or config key whose extra
dependencies are preflighted only when it is invoked (e.g. `--release` needs
`gh`; TOML/YAML bump targets need `tomlq`/`yq`). The counterpart to the default
path.
_Avoid_: plugin, extension, add-on

### Versioning

**Version source**:
The one file the current version is read from — `package.json` by default, any
JSON file via `--source` — and always the primary bump target. When the file
doesn't exist, the current version is derived from the latest matching release
tag instead.
_Avoid_: version file, source file (unqualified)

**Bump target**:
A file whose recorded version a release rewrites: the version source plus any
extras declared with `--bump` / `--file` (structured JSON/TOML/YAML fields, or
a `{{version}}` text pattern for anything else).
_Avoid_: bump file, target file

**Bump suggestion**:
The proposed next version, derived from Conventional Commits since the last
tag — or, on a prerelease, its trailing counter — and always printed before
the prompt so pressing Enter does the right thing.
_Avoid_: auto-bump, guessed version

**Explicit bump switch**:
`--major` / `--minor` / `--patch` — a CLI-only switch that forces the bump
level and bypasses the suggestion machinery entirely; mutually exclusive with
each other and with `-v`.
_Avoid_: force flag, level flag

### Release mechanics

**Release workflow**:
One of the three selectable shapes a release can take: **tag-in-place** (the
default), **release branch** (`--branch`), or **release PR** (`--pr`).
_Avoid_: release mode, release strategy

**Tag-in-place**:
The default release workflow — bump commit plus annotated tag on the current
branch, no release branch created.
_Avoid_: no-branch mode (its flag `--no-branch` is a deprecated no-op)

**Bump commit**:
The single commit a release makes, containing every bump target and the
changelog update; its message comes from `COMMIT_MSG_TEMPLATE` or the
generated default.
_Avoid_: release commit, version commit

**Safety preflight**:
A guard that stops a release before any mutation when repo state looks wrong
(dirty tree, remote out of sync, wrong branch, nothing to release). Every
preflight refusal exits `3`, the precondition code.
_Avoid_: sanity check, safety check

**Release hook**:
A user-supplied command run at one of the two hook points around the mutation
phase (`PRE_BUMP_CMD`, `POST_TAG_CMD`). Hook failure is the sole meaning of
exit code `4`; a fuller plugin system is a non-goal.
_Avoid_: plugin, lifecycle script

**Release notes**:
The body of the GitHub release that `--release` publishes for a tag. Distinct
from the changelog entry, which lives in `CHANGELOG.md` and ships inside the
bump commit; release notes live only on GitHub.
_Avoid_: changelog (for the release body), release description

**Notes agent**:
The external LLM command-line tool (`claude`, `codex`, or a user-named
command) that an opt-in release asks to write its release notes. It is an
improvement, never a requirement: when no notes agent can run, the release
publishes the notes it would have published without one.
_Avoid_: AI, LLM, provider, model

**Local undo**:
Reverting a just-cut release — tag, release branch, bump commit — before
anything is pushed. It never touches a remote.
_Avoid_: rollback, revert (unqualified)

**Package scope**:
The set of paths a release's commit analysis is restricted to, resolved from
`COMMIT_PATHS` against the `.verbumprc`'s directory (ADR-23, R-MONO). Active
only when narrower than the repo root; a whole-repo run has no scope. The
blessed monorepo flow is "run from the package directory with a per-package
rc".
_Avoid_: package mode, monorepo mode, path filter

**Release preview**:
The machine-readable `--dry-run --json` answer to "what would this release
do?" — the _plan_ before a release, where `--quiet` output is the _result_
after one.
_Avoid_: dry-run JSON dump, plan output

**Dev sandbox**:
An isolated throwaway git repo in which contributors exercise the real release
flow, not just a dry-run; its cleanup must never fire against the host repo.
_Avoid_: test repo, playground

### Docs

**User docs**:
The published documentation site for people who run `VerBump` — how to
install, configure, and release with it. Canonical for usage; the README is a
hero page that pitches and points here, never a second copy.
_Avoid_: the docs (unqualified), website, public docs

**Engineering docs**:
The `docs/` tree — PRD, ADRs, code style, feature requirements, agent
workflows. Canonical for how `VerBump` is built and decided; its audience is
contributors and agents, and it is not published on the user docs site.
_Avoid_: the docs (unqualified), internal docs, repo docs
