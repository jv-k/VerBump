# `--dry-run --json` — structured release preview

Status: **shipped** (R-OUT-5..7, issue #107). Requirements contract in
[`requirements.md`](./requirements.md); accumulator in
[`lib/effects.sh`](../../../lib/effects.sh); tests in
`test/dry-run-json.bats`.

## Goal

Give a script, a CI job, or an agent a machine-readable answer to *"what
would a release do?"* without side effects. Same information the human
`[dry-run] would ...` lines already carry, emitted once as a single JSON
object instead of prose scattered across stderr.

Deliberately **preview-only**: `--json` without `--dry-run` exits 2. Lowering
the barrier to *reading* a release plan is safe; lowering it to *triggering*
one is not (this is also why an MCP server was rejected in #107 — the
mutating path stays human-gated). A post-run *result* object remains a
possible later extension precisely because the combination is rejected today.

## How it works

| Piece | Mechanism |
| --- | --- |
| Serializer | `jq` — already a hard runtime dep, adds none. Not pure bash: hand-built JSON corrupts on the first `"` in a commit subject. |
| Stream discipline | reuses R-OUT-1's FD-3 redirect (`exec 3>&1 1>&2` in `process-arguments`): decoration → stderr, the one JSON object → the saved real stdout. |
| Effect collection | one `record-effect` call beside each `[dry-run]` preview line — the structured sibling of the prose. Guards (`FLAG_*`/`DO_*`) already decide whether a site runs, so `effects[]` contains only what *would* run. |
| Bash 3.2 | no associative arrays → the accumulator is one JSON-array *string* (`VB_EFFECTS`), grown via `jq --arg` calls. |

`record-effect key value ...` builds one object through jq's `$ARGS.named`
(every value escaped by jq; all values strings). `record-effect-raw '<json>'`
is the escape hatch for typed fields — booleans and counts — with jq
validating the fragment on merge. Both are **no-ops unless `FLAG_JSON=true`**,
so normal runs pay nothing. `emit-effects-json` writes the final object to
FD 3 at the end of `main()`.

`FLAG_JSON` is CLI-only (reset in `process-arguments`, like `FLAG_QUIET`),
and `--json` requires a non-interactive version choice (`--yes`, `-v`, a
bump level, or `--preid`) — a JSON pipeline must not stop at a prompt.

## Schema — `verbump.dry-run/v1`

Top level:

| field | type | notes |
| --- | --- | --- |
| `schema` | string | `verbump.dry-run/v1`; bump on breaking change |
| `dryRun` | bool | always `true` in this mode |
| `version` | object | `{from, to}` + `level` only when a bump level drove the version (absent under `-v`) + `preid` only when set |
| `source` | string | resolved version source (`--source` / default `package.json`) |
| `tag` | string | `TAG_PREFIX + V_NEW` |
| `effects` | array | ordered as `main()` would execute them — the array doubles as the execution plan |

Each `effects[]` object carries an `action` discriminator plus
action-specific fields. All values are strings unless noted:

| `action` | fields | recorded by |
| --- | --- | --- |
| `run-hook` | `hook` (`pre-bump` \| `post-tag`), `command` | `_run-hook` (lib/hooks.sh) |
| `bump-json` | `target`, `from`, `to`, `role` (`source` \| `lock` \| `extra`) | `do-packagefile-bump`, `bump-json-files` |
| `bump-text` | `target`, `pattern` (with `{{version}}`), `from`, `to` | `bump-target-files` (text patterns) |
| `bump-struct` | `target`, `format` (`json` \| `toml` \| `yaml`), `path` (dotted), `from`, `to` | `bump-target-files` (structured paths) |
| `write` | `target` (`VERSION`), `to` | `do-versionfile` |
| `changelog` | `target`, `op` (`created` \| `updated`), `heading`, `entries` (**number**: commit bullets + the bump entry) | `do-changelog` |
| `branch` | `ref` | `do-branch` |
| `commit` | `message` (full rendered message; no `paths` field — the file effects before it already enumerate every staged path) | `do-commit` |
| `tag` | `ref`, `annotated` (**bool**, always `true`), `signed` (**bool**), `message` | `do-tag` |
| `push` | `remote`, `branch`, `tag` | `do-push` |
| `open-pr` | `head`, `base`, `title` | `do-pr` |
| `github-release` | `tag`, `notes` (`generated` \| `changelog` \| `command` \| `agent`), `prerelease` (**bool**), `agent` (the notes agent a live run would call, or `null`), `fallback` (`generated` \| `changelog`: the notes published without a custom command or a notes agent, set even when a command wins) | `do-github-release` |

A no-op run (nothing to release) emits **nothing** on stdout and exits 0 —
`[ -s plan.json ]` is the "a release would happen" test, mirroring R-OUT-4.
`--quiet --json` emits only the JSON object; the bare-version line is
skipped because the same fact lives at `.version.to`.

## Sample payload

Verbatim output of the dev sandbox — reproducible by anyone with:

```sh
SANDBOX_COMMITS='feat: add login; fix: null crash' \
  ./dev/sandbox.sh --minor --yes --remote -p origin --dry-run --json 2>/dev/null | jq .
```

```json
{
  "schema": "verbump.dry-run/v1",
  "dryRun": true,
  "version": {
    "from": "0.1.0",
    "to": "0.2.0",
    "level": "minor"
  },
  "source": "package.json",
  "tag": "v0.2.0",
  "effects": [
    {
      "action": "bump-json",
      "target": "package.json",
      "from": "0.1.0",
      "to": "0.2.0",
      "role": "source"
    },
    {
      "action": "changelog",
      "target": "CHANGELOG.md",
      "op": "created",
      "heading": "## 0.2.0 (2026-07-19)",
      "entries": 3
    },
    {
      "action": "commit",
      "message": "chore: updated package.json, created CHANGELOG.md, bumped 0.1.0 -> 0.2.0"
    },
    {
      "action": "tag",
      "ref": "v0.2.0",
      "annotated": true,
      "signed": false,
      "message": "Tag version 0.2.0."
    },
    {
      "action": "push",
      "remote": "origin",
      "branch": "main",
      "tag": "v0.2.0"
    }
  ]
}
```

### Fuller plan

The same schema with more of the surface switched on —
`verbump --minor --yes --pr --release -f composer.json --dry-run --json`:

```json
{
  "schema": "verbump.dry-run/v1",
  "dryRun": true,
  "version": { "from": "1.2.3", "to": "1.3.0", "level": "minor" },
  "source": "package.json",
  "tag": "v1.3.0",
  "effects": [
    { "action": "bump-json", "target": "package.json", "from": "1.2.3", "to": "1.3.0", "role": "source" },
    { "action": "bump-json", "target": "composer.json", "from": "1.2.3", "to": "1.3.0", "role": "extra" },
    { "action": "changelog", "target": "CHANGELOG.md", "op": "created", "heading": "## 1.3.0 (2026-07-19)", "entries": 2 },
    { "action": "branch", "ref": "release-1.3.0" },
    { "action": "commit", "message": "chore: updated package.json, updated composer.json, created CHANGELOG.md, bumped 1.2.3 -> 1.3.0" },
    { "action": "tag", "ref": "v1.3.0", "annotated": true, "signed": false, "message": "Tag version 1.3.0." },
    { "action": "push", "remote": "origin", "branch": "release-1.3.0", "tag": "v1.3.0" },
    { "action": "open-pr", "head": "release-1.3.0", "base": "main", "title": "Release v1.3.0" },
    { "action": "github-release", "tag": "v1.3.0", "notes": "generated", "prerelease": false }
  ]
}
```

## Decisions (resolved 2026-07-19)

1. **Typed fields** — booleans and counts are real JSON types via
   `record-effect-raw`; everything else stays a string.
2. **`--json` without `--dry-run` rejects** (exit 2). Preview-only for v1; a
   result object can be added later without a breaking change.
3. **`effects` is flat + ordered** — it doubles as the execution plan.
   Consumers group trivially: `jq '.effects | group_by(.action)'`.
4. **Requirement ids** — R-OUT-5..7 in [`requirements.md`](./requirements.md),
   extending the `--quiet` R-OUT bucket.
5. **Field deviations from the issue's abridged sample** (all deliberate):
   `commit` has no `paths` field (the file effects before it already
   enumerate every staged path); structured `--bump` targets get their own
   `bump-struct` action (they can be TOML/YAML, not just text patterns);
   `push` uses separate `branch` + `tag` fields instead of a joined `refs`
   string; `github-release` records `notes` + `prerelease` and drops `title`
   (gh derives the title from the tag); `version.level` is absent under an
   explicit `-v`.
