# Feature requirements

One folder per feature; each `requirements.md` is the living contract for
that feature — requirement IDs, current status, test mapping, and known
gaps. IDs originate in [`docs/PRD.md`](../PRD.md) (the 2.0.0 release
contract); IDs added after the PRD are backfilled here first.

| Feature | IDs | Tests |
| --- | --- | --- |
| [runtime-dependencies](./runtime-dependencies/requirements.md) | R-DEP | `errors.bats` |
| [version-input](./version-input/requirements.md) | R-VER | `version.bats` |
| [version-source](./version-source/requirements.md) | R-SRC | `version-source.bats` |
| [bump-suggestion](./bump-suggestion/requirements.md) | R-BUMP | `bump-suggest.bats` |
| [explicit-bump-switches](./explicit-bump-switches/requirements.md) | R-FORCE | `args.bats`, `bump-suggest.bats` |
| [prerelease](./prerelease/requirements.md) | R-PRE | `args.bats`, `preid.bats` |
| [cli-options](./cli-options/requirements.md) | R-OPT | `args.bats` |
| [non-interactive](./non-interactive/requirements.md) | R-YES | `args.bats`, `config.bats` |
| [dry-run](./dry-run/requirements.md) | R-DRY | `dryrun.bats` |
| [exit-codes](./exit-codes/requirements.md) | R-EXIT | `errors.bats` |
| [config-file](./config-file/requirements.md) | R-CFG | `config.bats`, `config-env.bats` |
| [completions](./completions/requirements.md) | R-COMP | `args.bats`, `completions-syntax.bats`, `install-completions.bats` |
| [changelog](./changelog/requirements.md) | R-LOG, R-CHLOG | `changelog.bats`, `changelog-grouped.bats` |
| [commit-template](./commit-template/requirements.md) | R-TPL | `commit-template.bats` |
| [release-flow](./release-flow/requirements.md) | R-FLOW | `git-ops.bats`, `pr.bats`, `prefixes.bats`, `e2e-live.bats` |
| [signed-tags](./signed-tags/requirements.md) | R-SIGN | `signed-tags.bats`, `args.bats` |
| [github-release](./github-release/requirements.md) | R-REL | `release.bats` |
| [undo](./undo/requirements.md) | R-UNDO | `undo.bats` |
| [safety-preflights](./safety-preflights/requirements.md) | R-SAFE | `worktree-clean.bats`, `release-branch-guard.bats`, `remote-sync.bats`, `no-release.bats` |
| [hooks](./hooks/requirements.md) | R-HOOK | `hooks.bats`, `args.bats` |
| [ui-output](./ui-output/requirements.md) | R-UI, R-OUT-1..4 | `ui.bats`, `color.bats`, `about.bats`, `quiet.bats` |
| [dry-run-json](./dry-run-json/requirements.md) | R-OUT-5..7 | `dry-run-json.bats` |
| [dev-sandbox](./dev-sandbox/requirements.md) | R-DEV | `sandbox.bats` |
| [json-bump-formatting](./json-bump-formatting/requirements.md) | R-FMT | `json.bats`, `bumpfile.bats` |
| [bump-targets](./bump-targets/requirements.md) | R-TGT | `bump-targets.bats` |
| [installer](./installer/requirements.md) | R-DIST | `install.bats` |
| [update](./update/requirements.md) | R-UPD | `update.bats` |
