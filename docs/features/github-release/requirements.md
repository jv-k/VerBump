# GitHub release (--release)

Opt-in publishing of a GitHub release for the new tag, after the push.
Resolves the "automate a release" ask (issue #25, #43).

| ID | Requirement | Status |
| --- | --- | --- |
| R-REL-1 | `--release` runs `gh release create <tag> --generate-notes` (default) or `--notes "<notes>"` (custom `VERBUMP_RELEASE_NOTES_CMD`, R-REL-2) after the tag is pushed. | ✅ shipped — `test/release.bats` (22) |
| R-REL-2 | Notes default to `gh release create --generate-notes`; a custom `VERBUMP_RELEASE_NOTES_CMD` is captured via `--notes`. | ✅ shipped |
| R-REL-3 | `--release` requires `-p <remote>`; missing → exit `2` naming the flag. | ✅ shipped |
| R-REL-4 | `gh` is conditional: required only with `--release` (missing → `3`). `node`/`npx` only if `VERBUMP_RELEASE_NOTES_CMD` is overridden. Default VerBump path never invokes `gh`/`node`/`npx`. | ✅ shipped |
| R-REL-5 | Under `--dry-run`: no `gh` call; resolved invocation printed with `[dry-run]` prefix (`--generate-notes` or `--notes '<output>'`); a custom notes command may still run (read-only). | ✅ shipped |
| R-REL-6 | Notes command failing → abort before `gh`, exit `1`, stderr surfaced; tag push not rolled back. | ✅ shipped |
| R-REL-7 | Prerelease versions publish as GitHub **prereleases** (`--prerelease`). | ✅ shipped (`0c565f8`) |
| R-REL-8 | Pipeline hardened: push gate enforced, `gh auth status` preflighted, `-n` blocks release. | ✅ shipped (`93b76e4`) |
| R-REL-9 | `DO_RELEASE` is CLI-only — env/`.verbumprc` can never trigger a release (R-CFG-6). | ✅ shipped (`783f457`) |
| R-REL-10 | `RELEASE_NOTES_AGENT` (`.verbumprc` or env, env wins; default `off`) names a notes agent: a command that reads a prompt on stdin. On a live `--release` run, after the push, its stdout is published with `gh release create … --notes`. `off` (or unset) gives output identical to a run without the key. `VERBUMP_RELEASE_NOTES_CMD` takes precedence and keeps its abort-on-failure behaviour (R-REL-6). | ✅ shipped (#162) — `test/release-notes.bats` |
| R-REL-11 | The agent's stdin holds the built-in prompt (Markdown notes for the project's users, facts from the context only, `#N` references kept, no title or version heading, the notes body only), then the `RELEASE_NOTES_PROMPT` guidance, then the context in delimited blocks: the changelog entry (the grouped rendering of R-MONO-9), the commit list (subject and body) and the diffstat for the previous tag → new tag range, or the full history when there is no previous tag. Under a package scope every block covers only the scope. The commit list and diffstat have a line limit and end with a marker line when cut. | ✅ shipped (#162) |
| R-REL-12 | The agent runs in a fresh empty temporary directory, not the repo. On success the run prints an info line naming the notes agent, then the notes, on the normal progress channel (stderr under `--quiet`, so stdout keeps only the version). | ✅ shipped (#162) |
| R-REL-13 | A notes agent is never fatal: a non-zero exit, a timeout (R-REL-15), or empty or whitespace-only output, prints one warning naming the cause and publishes the fallback notes — `gh --generate-notes` anchored to the previous tag at whole-repo scope, the package's changelog entry under a package scope. The exit code stays `0`. | ✅ shipped (#162) |
| R-REL-14 | The notes agent never runs without `--release`, after a failed push, or under `--dry-run`. A prerelease still publishes with `--prerelease` (R-REL-7). | ✅ shipped (#162) |
| R-REL-15 | `RELEASE_NOTES_AGENT_TIMEOUT` (`.verbumprc` or env, env wins; default `120`) caps the notes agent's run in seconds. On timeout VerBump stops the agent and every process it started, prints one warning that names the timeout, publishes the fallback notes (R-REL-13) and exits `0`. The watchdog needs no coreutils `timeout` (bash 3.2 on macOS); it leaves no agent, timer or temporary file behind, also when the run is interrupted. A value that is not a positive integer prints a warning when the agent runs, and VerBump uses `120`. | ✅ shipped (#163) — `test/release-notes.bats` |

Modules: `lib/args.sh` (parse), `lib/git-actions.sh` (`resolve-release-notes`,
`do-github-release`), `lib/notes-agent.sh` (`build-notes-prompt`,
`run-notes-agent`, ADR-24).
Tests: `test/release.bats`, `test/release-notes.bats`.
