# Dev sandbox

Contributors exercise the real release flow (not just dry-run) in an
isolated throwaway repo (PRD G5, US-6).

| ID | Requirement | Status |
| --- | --- | --- |
| R-DEV-1 | `pnpm dev` / `./dev/sandbox.sh` creates an isolated throwaway git repo, runs `VerBump` inside it, cleans up on exit incl. Ctrl-C. | ✅ `test/sandbox.bats` |
| R-DEV-2 | Sandbox cleanup must never fire against the host repo. | ✅ `test/sandbox.bats` |
| R-DEV-3 | `SANDBOX_VERSION` / `SANDBOX_COMMITS` customise start state; `--keep`/`-k` preserves the temp dir. | ✅ `test/sandbox.bats` |

Coverage notes: cleanup is exercised on normal exit, on VerBump failure
(exit code propagation), and on SIGTERM delivered mid-run to the sandbox and
its foreground `VerBump` child — the closest deterministic analogue to
Ctrl-C from a non-interactive test (a real Ctrl-C signals the whole
foreground process group; bash defers traps until the foreground child
exits, so both processes are signalled explicitly).

Also in `dev/` (unspecced tooling, no requirements): `screenshots.sh` drives
the VHS tapes (`help`, `demo`, `social`) that render the README's `--help`
still, the demo GIF (plus its final-frame still `img/verbump-demo-final.png`)
and the social card — VHS runs a real terminal emulator, so the inverted-video
section pills and dim markers render faithfully — and `wordmark.js`, which
draws the README's wordmark pictures. Its `release` target runs from
`.verbumprc`'s `PRE_BUMP_CMD`, so each release commit carries pictures of its
own version; and `prepublish-version-guard.sh`.
`sandbox.sh --remote` adds a throwaway bare `origin` so a real `-p origin`
push path can be exercised; `sandbox.sh --setup-only` scaffolds the repo (and
remote), prints their paths, and hands off without running VerBump — the demo
tape `cd`s in and drives a clean `VerBump …` command itself.

Modules: `dev/sandbox.sh`.
