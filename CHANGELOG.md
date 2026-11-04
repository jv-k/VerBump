## 4.1.1 (2026-11-04)
- chore: updated package.json, updated CHANGELOG.md, bumped 4.1.0 -> 4.1.1
- chore(deps): bump next from 16.2.10 to 16.2.12 (#140)
- chore(deps): bump next from 16.2.10 to 16.2.12
- ci: bump actions/checkout from 7.0.0 to 7.0.1 (#132)
- chore(deps): bump postcss from 8.5.19 to 8.5.21 (#135)
- chore(deps): bump react-dom from 19.2.7 to 19.2.8 (#137)
- chore(deps): bump react-dom from 19.2.7 to 19.2.8
- chore(deps): bump postcss from 8.5.19 to 8.5.21
- ci: bump actions/checkout from 7.0.0 to 7.0.1
- docs(img): regenerate release visuals

## 4.1.0 (2026-07-21)
- chore: updated package.json, updated CHANGELOG.md, bumped 4.0.3 -> 4.1.0
- chore: Updated bump-version task
- fix(tests): pin stdin in the monorepo suites (#131)
- fix(tests): pin stdin in the monorepo suites
- feat(config): per-package monorepo support via COMMIT_PATHS scope (#130)
- docs(docs): ring the VerBump column in the comparison table
- docs(docs): keep the feature column on one line
- docs(docs): move features under Why VerBump; lucide table glyphs
- test(tests): close review coverage gaps
- fix(config): keep COMMIT_PATHS globs out of shell expansion
- fix(changelog): scoped notes render grouped regardless of style
- docs(docs): add hint style rules and an errors catalogue
- fix(errors): normalise hint wording across fail sites
- docs(docs): monorepos user guide + feature comparison on the docs site
- docs(docs): ADR-23 per-package monorepo support + R-MONO requirements
- test(tests): monorepo fixture + scope and preflight suites
- feat(json): additive scope member in the release preview
- feat(changelog): scope changelog, PR body, and release notes
- feat(checks): scope the no-release gate; split the dirty check
- feat(version): scope the bump-suggestion scan to COMMIT_PATHS
- feat(config): COMMIT_PATHS package scope anchored to the rc dir
- docs(docs): document the package-lock companion bump (#129)
- docs(docs): tighten companion-bump wording per review
- docs(docs): document the package-lock companion bump
- docs(docs): add versioning and release-mechanics terms to the glossary
- chore: Install Vercel Web Analytics (#113)
- docs(docs): add social preview card below the readme title [skip ci]
- Install Vercel Web Analytics
- Merge branch 'main' of https://github.com/jv-k/VerBump
- docs(img): regenerate release visuals
- fix(tests): pin bats harness clones to release tags
- fix(ui): grow help tape height past the --json help growth
- ci: install zsh for vhs renders
- docs(img): regenerate release visuals
- docs(img): regenerate release visuals
- docs(img): regenerate release visuals
- fix(tests): pin vhs release binary, drop broken vhs-action (#112)
- docs(img): regenerate release visuals
- fix(tests): pin vhs release binary, drop broken vhs-action

## 4.0.3 (2026-07-19)
- chore: updated package.json, updated CHANGELOG.md, bumped 4.0.2 -> 4.0.3
- ci: render release visuals on tag push, add social card (#111)
- docs(docs): list demo final-frame still in screenshots.sh header
- ci: render release visuals on tag push, add social card
- docs(docs): note git hosting support, gitlab/bitbucket coming soon
- docs(docs): slim quickstart install to curl + installation link
- docs(docs): note deploy-skip behaviour in docs-site README
- chore(ci): retire README TOC generator
- chore(docs): update TOC
- docs(docs): add fumadocs user docs site and slim README (ADR-22) (#109)
- fix(tests): point help-flag parity at user-docs CLI reference
- feat(docs): link feature cards, bash-highlighted install block
- refactor(docs): text nav wordmark, labeled install command
- feat(docs): brand tokens, card icons, logo cut-outs, copy button
- feat(docs): add social preview to landing hero and OG metadata
- chore(docs): deploy only on docs-site or workspace lockfile changes
- docs(docs): slim README to hero page pointing at user docs site
- chore(tests): replace bats submodules with plain ignored clones
- feat(docs): brand site and decompose README into user docs pages
- chore(docs): convert to pnpm workspace with fumadocs docs-site package
- docs(docs): record ADR-22 and user/engineering docs vocabulary
- feat(json): add --dry-run --json structured release preview (#108)
- feat(json): add --dry-run --json structured release preview
- ci: scope push trigger to main to stop duplicate PR runs
- refactor(publish): rename VerBump.sh and command to lowercase verbump
- feat(errors): render ERROR and HINT as inverted header pills
- test(hooks): make the push-prompt EOF explicit in the no-hooks test

## 4.0.2 (2026-07-19)
- chore: updated package.json, updated CHANGELOG.md, bumped 4.0.1 -> 4.0.2
- test(hooks): sanitize inherited VERBUMP_* before the leak assertion
- test(completions): sync on compinit before TAB in live zpty test
- docs: standardize git worktrees under .worktrees/
- chore(publish): gate releases on lint + tests via pre-bump hook
- chore(publish): add bump-release script for one-shot patch releases
- fix(completions): unbracket the zsh --bump spec, add live comp test
- fix(completions): make zsh cache hint ZDOTDIR-aware and glob-safe
- fix(completions): register lowercase verbump in all three shells
- ci(screenshots): center the social card and drop requirements line
- ci(screenshots): add social-preview card tape and 1280x640 render
- ci(screenshots): freeze legacy demo.gif; rename current verbump-demo
- ci(screenshots): restore the 2.0.0 demo tape and renders
- ci(screenshots): land 1.0.0 demo and 4.0.1 help renders
- ci(screenshots): retarget the demo at an evergreen 1.0.0 bump
- fix(publish): match npm-pack glob to the scoped package name
- docs(changelog): correct npm package name in the 4.0.0 note
- docs(readme): restore live npm version badge

## 4.0.1 (2026-07-18)
- chore: updated package.json, updated CHANGELOG.md, bumped 4.0.0 -> 4.0.1
- docs(readme): use static npm badge until verbump is published
- docs(readme): keep npm badge on the verbump package
- docs(readme): point npm badge at ver-bump, swap CI badge to shields
- chore(publish): chain brew:bump into the release script
- chore(publish): add brew:bump script to dispatch tap formula bump
- Merge pull request #103 from jv-k/docs/homebrew-install-path
- Merge branch 'main' into docs/homebrew-install-path
- docs(readme): point homebrew section at the jv-k/tap verbump formula
- Merge remote-tracking branch 'origin/main' into docs/homebrew-install-path
- docs(readme): add homebrew install path

## 4.0.0 (2026-07-18)

> **⚠ Breaking — full rename, `ver-bump` → VerBump.** Nothing is called `ver-bump` anymore. The command/repo/brand are **`VerBump`**; the npm package is **`@jv-k/verbump`** (npm reserves the bare name `verbump` as too similar to the retired `ver-bump`) and the config file is **`.verbumprc`**. Update: `npm i -g ver-bump` → **`npm i -g @jv-k/verbump`** (new package; old one ends at 1.1.8, deprecated), `.ver-bumprc` → **`.verbumprc`**, `VER_BUMP_*` env vars → **`VERBUMP_*`**, and repo URLs `jv-k/ver-bump` → **`jv-k/VerBump`** (old URLs redirect). `PRE_BUMP_CMD`/`POST_TAG_CMD` and the tag prefix are unchanged; an existing `ver-bump` install keeps working until removed. See [README § Migrating from ver-bump](README.md#migrating-from-ver-bump).

- chore: updated package.json, updated CHANGELOG.md, bumped 3.0.0 -> 4.0.0
- refactor!: rename everything ver-bump -> VerBump / verbump

## 3.0.0 (2026-07-17)

> **⚠ Breaking — the command is renamed `ver-bump` → `VerBump`.** The npm package name stays `ver-bump` (npm forbids uppercase); installing it now provides the `VerBump` command. Update any aliases, scripts, CI steps, and shell completions. An already-installed `ver-bump` symlink keeps working until removed. See [README § Command renamed to VerBump](README.md#command-renamed-to-verbump).

- chore: updated package.json, updated CHANGELOG.md, bumped 2.0.2 -> 3.0.0
- docs(readme): explain the ver-bump package / VerBump command split
- fix(publish): keep npm-pack tarball glob lowercase after rename
- refactor!: rename the command and brand to VerBump
- docs(publish): record package-registry publishing as out of scope
- docs(readme): repin images to main raw URLs
- ci(screenshots): land re-rendered demo and help stills
- docs(readme): swap bash and npm badges to shields.io
- docs(readme): add a feature list at the top
- docs(readme): fix stale claims, fold exit codes, document installer
- docs: add contributing guide, PR template, and CLI issue templates

## 2.0.2 (2026-07-17)
- chore: updated package.json, updated CHANGELOG.md, bumped 2.0.1 -> 2.0.2
- docs(adr): ADR-21 — main is the canonical branch post-2.0
- ci: drop the GitHub Packages publish job
- Merge pull request #100 from jv-k/dependabot/github_actions/actions/checkout-7.0.0
- Merge pull request #102 from jv-k/dependabot/github_actions/actions/download-artifact-8.0.1
- ci: bump actions/download-artifact from 4.3.0 to 8.0.1
- ci: bump actions/checkout from 4.3.1 to 7.0.0

## 2.0.1 (2026-07-17)
- chore: updated package.json, updated CHANGELOG.md, bumped 2.0.0 -> 2.0.1
- Merge pull request #99 from jv-k/dependabot/github_actions/stefanzweifel/git-auto-commit-action-7.2.0
- Merge pull request #101 from jv-k/fix/input-prompt-newline
- Merge pull request #98 from jv-k/dependabot/github_actions/actions/setup-node-7.0.0
- Merge pull request #97 from jv-k/dependabot/github_actions/actions/upload-artifact-7.0.1
- fix(ui): terminate prompt line when enter accepts the suggestion
- ci: bump stefanzweifel/git-auto-commit-action from 5.2.0 to 7.2.0
- ci: bump actions/setup-node from 4.4.0 to 7.0.0
- ci: bump actions/upload-artifact from 4.6.2 to 7.0.1

## 2.0.0 (2026-07-17)
- chore: updated package.json, updated CHANGELOG.md, bumped 2.0.0-rc.1 -> 2.0.0
- ci(screenshots): drop the release trigger to avoid the GA main-reset race
- ci(screenshots): pre-install ffmpeg for the flaky vhs-action install
- fix: stop dev/verify-rc.sh check 4 hanging on the push-offer prompt

## 2.0.0-rc.1 (2026-07-17)
- chore: updated package.json, updated CHANGELOG.md, bumped 1.1.8 -> 2.0.0-rc.1
- chore: add dev/verify-rc.sh for release-candidate verification
- ci(publish): require Node 22 in publish-npm for OIDC trusted publishing
- ci(screenshots): re-render help still for the compact banner
- feat(ui): gray sub-heading pills, compact banner, flush help pills
- chore(docs): update TOC
- ci(screenshots): re-record demo with flush-left header pills
- ci(screenshots): trim help.tape height to cut trailing blank space
- ci(screenshots): render 'ver-bump --help' and trim window padding
- docs: move CONTEXT.md into docs/ and update references
- docs(readme): rework front page with tables and collapsible reference
- fix(ui): drop the one-space lead-in before header pills
- feat(ui): replace prompt glyph with magenta INPUT/CONFIRM pills
- docs: reconcile 2.0 docs surface with shipped code
- chore: drop the dead terminalizer demo/ ignore
- Merge pull request #94 from jv-k/chore/release-2.0-hardening
- docs: fix R-REL-1 default-notes invocation + release.bats count
- docs: reconcile PRD/README/CHANGELOG with shipped 2.0 surface
- docs: capture 2.0 design-grill decisions (ADR-15..20)
- chore(publish): dogfood ver-bump --release in the release script
- feat(config): warn on unknown .ver-bumprc keys
- feat(git-actions): default --release notes to gh --generate-notes
- docs: scaffold engineering-skills config files
- ci(screenshots): regenerate --help still for the grouped/paged layout
- docs(readme): add a grouped Flags table matching the --help layout
- refactor(config): make tag-in-place the explicit default
- feat(ui): page long --help, group OPTIONS, dim examples, hide --about
- ci(screenshots): rework demo + help stills, drop dry-run/completions
- ci(screenshots): render CLI visuals via vhs; trigger on release + manual tasks
- feat(dev): sandbox --remote to exercise the real push path
- feat(args): nudge -f/--file users toward --bump
- fix(ui): keep the short alias first in OPTIONS rows
- fix(ui): refine OPTIONS/USAGE layout and repo-sourced description
- fix(ui): no blank line after run-output section pills
- fix(ui): concise USAGE, correct-width wrapping, repo-sourced description
- fix(errors): separate the hint from the error with a blank line
- fix(ui): stack over-long example commands above their descriptions
- feat(ui): wrap the USAGE synopsis to the terminal width
- feat(ui): fluid --help layout that wraps to the terminal width
- fix(checks): explain why the remote-sync fetch failed
- refactor(ui): drive status-line gutter from a width constant
- Merge pull request #93 from jv-k/feat/bump-targets
- feat(version): bump non-JSON files via --bump per-file locators
- Merge pull request #91 from jv-k/chore/remove-sandcastle
- chore(repo): remove the Sandcastle agent harness
- Merge pull request #87 from jv-k/refactor/ui-restyle
- test(ui): robust style guards (word-boundary grep, style-only error assert)
- fix(ui): declare _chlog_line local, dedupe prompt glyph
- refactor(ui): theme-adaptive tokens, soft prompts, changelog pill
- Merge pull request #86 from jv-k/test/fail-shadowing
- test(tests): assert fail shadow via definition diff, not internals
- test(tests): stop ver-bump fail() from shadowing bats-support fail()
- Merge pull request #85 from jv-k/feat/preid
- docs(usage): note --preid as a quiet-mode non-interactive path
- fix(version): compare full preid id chain in bump-preid
- Merge pull request #84 from jv-k/docs/adopt-in-repo-standards
- feat(version): --preid <id> to start or advance a prerelease line
- docs(style): fix ralph-merge scope name (no trailing colon)
- feat(version): git-tag version fallback + --source for non-Node repos (#83)
- docs(style): adopt in-repo standards; scope ralph to Sandcastle
- Merge pull request #82 from jv-k/feat/release-hooks
- Merge remote-tracking branch 'origin/develop' into feat/release-hooks
- Merge pull request #80 from jv-k/feat/commit-template
- docs(prd): exit code 4 is hook failure, not reserved
- Merge remote-tracking branch 'origin/develop' into feat/release-hooks
- Merge pull request #81 from jv-k/feat/quiet-mode
- fix(template): escape patsub replacements + safe dry-run preview
- Merge remote-tracking branch 'origin/develop' into feat/quiet-mode
- Merge pull request #79 from jv-k/feat/signed-tags
- style(git-actions): printf for dry-run tag preview
- docs(output): R-OUT bucket in ui-output requirements + index row
- test(output): quiet-mode contract — R-OUT-1..4 in quiet.bats
- feat(output): --quiet surface parity — help row, completions, README
- feat(output): -q/--quiet prints the bare new version on stdout
- test(hooks): cover R-HOOK-1..6 in hooks.bats + --no-hooks arg cases
- feat(hooks): PRE_BUMP_CMD / POST_TAG_CMD release hooks (exit code 4)
- docs(docs): document COMMIT_MSG_TEMPLATE and the R-TPL contract
- test(tests): pin COMMIT_MSG_TEMPLATE rendering, parity, and no-eval
- feat(config): COMMIT_MSG_TEMPLATE with ${version} placeholders
- feat(git): opt-in signed release tags (--sign / TAG_SIGN)
- Merge pull request #77 from jv-k/feat/safety-preflights
- feat(checks): nothing-to-release no-op with --allow-empty
- feat(checks): remote-sync preflight with --no-fetch
- feat(checks): release-branch guard via RELEASE_BRANCHES
- feat(checks): dirty-working-tree preflight with --allow-dirty
- Merge pull request #76 from jv-k/feat/curl-installer
- Merge pull request #75 from jv-k/feat/grouped-changelog
- fix(installer): rename-swap with rollback for existing installs
- fix(changelog): URL-encode compare-link refs
- docs(distribution): curl-first install section + R-DIST requirements
- docs(changelog): document CHANGELOG_STYLE and the R-CHLOG bucket
- test(changelog): grouped snapshots, link fixtures, precedence, flat pin
- feat(changelog): grouped conventional-commit style behind CHANGELOG_STYLE
- ci(publish): upload release tarball + sha256 as release assets
- feat(distribution): add checksummed curl installer
- Merge pull request #74 from jv-k/fix/json-format-preserve
- fix(json): string-only surgical path + checked mv
- Merge pull request #73 from jv-k/docs/github-only-scope
- docs(readme): tighten GitHub-only wording per PR review
- Merge pull request #72 from jv-k/docs/windows-support-status
- docs(json): backfill R-FMT requirements for json-bump-formatting
- test(json): byte-identical fixtures + fallback paths for json_set_version
- fix(json): preserve source formatting on version bump
- docs(readme): state GitHub-only scope of --pr/--release
- chore(pkg): drop untested windows test scripts
- docs(readme): document Windows support tiers
- docs(prd): test counts 227 -> 237; AC-1 now holds after #51-#53 fixes
- Merge pull request #56 from jv-k/test/sandbox-coverage
- Merge pull request #55 from jv-k/fix/esc-abort-exit-code
- Merge pull request #54 from jv-k/fix/undo-dryrun-stderr
- test(sandbox): quote eval'd cleanup paths + positional script path
- test(undo): assert --undo --dry-run exit status in the stderr test
- test(sandbox): cover R-DEV-1..3 for dev/sandbox.sh
- fix(version): ESC abort exits 5 via fail, not raw 130
- fix(git-actions): --undo dry-run preview goes to stderr per R-DRY-2
- docs: catch docs up with merged PR #49 (tag-in-place + --pr)
- Merge pull request #50 from jv-k/docs/reconcile-outstanding
- docs: align R-CFG-2/R-YES claims with shipped lib/config.sh
- chore(docs): update TOC
- Merge pull request #49 from jv-k/feat/release-pr-workflow
- docs(adr): backfill architecture decision records
- docs(features): add per-feature requirements with test mapping
- docs(style): make docs/CODE_STYLE.md the canonical standards doc
- docs(prd): reconcile 2.0 PRD with shipped code
- feat(lib): tag-in-place default + --pr release-PR workflow
- ci(publish): switch npmjs to OIDC Trusted Publishing (tokenless)
- ci(publish): fix rc publish — exec bits, decouple provenance, gate GHPR
- ci(publish): prereleases go to the npm 'next' dist-tag, not 'latest'
- ci(tests): scope matrix to Linux + macOS, fail-fast off
- ci: fix Windows shellcheck (CRLF) + lint once on Linux
- chore(docs): update TOC
- docs(readme): honest install paths, quickstart, demo alt text
- feat(screenshots): freeze-based deterministic panels + CLICOLOR_FORCE
- ci: SHA-pin actions, add provenance/OIDC publish, least-privilege
- test: cover R-COMP-1, live e2e bump, do-versionfile, --about
- fix(git-actions): abort on git tag failure instead of false success
- chore(npm): add files allowlist + provenance, kill 17.5MB tarball
- fix(lib): accept space-form --install-completions <shell>
- fix(lib): honour CLI prefix overrides + worktree marker in --undo
- fix(lib): skip bump suggestion for forced/explicit versions
- fix(lib): stop env/.ver-bumprc leaking into DO_RELEASE/BUMP_LEVEL
- fix(lib): publish prereleases as GitHub prereleases
- fix(lib): harden GitHub-release pipeline (push gate, -n, gh auth)
- feat(cli): --major / --minor / --patch explicit bump switches
- feat(cli): --release publishes GitHub release after push
- refactor(lib): split helpers.sh into focused modules
- Merge pull request #48 from jv-k/chore/swap-integration-to-develop
- chore(sandcastle): swap integration branch from feat/v2.0 to develop
- merge: feat/v2.0 → develop (cut for 2.0.0-alpha)
- Merge pull request #46 from jv-k/fix/sandcastle-pnpm-hook
- fix(sandcastle): use pnpm in onSandboxReady hook so reviewer can run
- feat(cli): --undo to locally revert a release (+ -y/--yes)
- feat(ui): ESC to abort, editable default on version prompt
- docs(cli): expand ver-bump.sh header with author, homepage, full description
- docs(readme): add --help screenshot under CLI synopsis
- chore: remove stale TODO.md
- merge: pull request #45 from jv-k/sandcastle/issue-33-readme-verbumprc-flags
- docs: add DONATE and v2.0 planning docs
- docs(claude): add Claude Code project instructions
- chore: gitignore vhs tmp, sandcastle runtime, and claude local config
- chore(sandcastle): move @ai-hero/sandcastle to devDependencies
- chore(dev): add screenshots tooling
- chore(dev): add shellcheck lint script
- docs(docs): add missing flags, exit codes, and sandbox env-vars to README
- chore(sandcastle): add planner+merger pipeline for autonomous issue work
- feat(cli): bare --version / -v prints tool version pill
- fix(completions): zsh → ~/.local/share/zsh/site-functions, omz-aware setup hint
- refactor(ui): S_VAL (green) for run-time values, %b body in log_* helpers
- refactor(ui): polish --help layout and update project description
- feat(completions): --install-completions with shell auto-detection (#42)
- feat(ui): branded --about, restructured --help, section pills in main()
- refactor(ui): migrate call sites to log_* helpers + semantic S_* tokens
- refactor(ui): add log / section / version_block helpers
- refactor(ui): add USE_COLOR gate, DIM, and inverse-video header pills
- refactor(ui): replace emoji icons with structured symbol vocabulary
- chore(docs): drop stale bashdoc HTML artefacts and generator script
- chore(docs): update TOC
- fix(ui): use %b for style tokens in do-changelog printfs
- test: scratch-repo isolation, coverage for review fixes, integration
- fix(helpers): apply code review to helpers.sh
- fix(config): reject group-writable or attacker-owned .ver-bumprc
- fix(config): enforce CLI > env > file > default precedence end-to-end
- refactor(ui): strip narrative colour, reserve accents for values
- feat(config): .ver-bumprc loader with CLI > env > file precedence
- refactor(tests): split ver-bump.bats into per-feature files
- fix(errors): harden fail helper with printf and default-safe style vars
- feat(errors): fail helper + standardized exit codes
- test: coverage for suggest-bump-level, dry-run, and prefix overrides
- feat: SemVer 2.0 input, long-opts, dry-run, prefix overrides, conventional-commits bump
- feat(dev): add sandbox harness + pnpm dev script
- chore(ci): upgrade workflow actions + remove orphan dev-tests.bats
- fix: correctness and hygiene in helpers.sh and ver-bump.sh
- docs(todo): added new task
- Merge pull request #29 from jv-k/release-1.1.8
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.7 -> 1.1.8
- bug: fixed change that caused CI #94
- chore(tests): update bats
- chore(build): created release task
- style: removed extra ws
- Merge pull request #27 from jv-k/release-1.1.7
- chore(docs): update TOC
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.6 -> 1.1.7
- chore(docs): update TOC
- docs: added testing section
- docs: fix linting issues
- docs: add switcher feat to todos
- docs: add basher deploy to todos
- merge branch: 'release-1.1.6' into main
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.5 -> 1.1.6
- fix: disabled SC2086 double quote warning - The version tag isn't a concern if it were split
- fix: fixed bug when there's not previous tag - issue arises when there are commits, but no previous tag is present - bump failed at grabbing previous commit history for building the changlelog
- chore: added commitizen
- docs: added better comments task in TODO.md
- merge: branch 'release-1.1.5' into main
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.4 -> 1.1.5
- Merge pull request #23 from jv-k/fix-npmissue
- bugfix: allow bumping when uncommitted changes exist
- merge: branch 'release-1.1.4' into main
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.3 -> 1.1.4
- docs: fixed style issue
- merge: branch 'release-1.1.3' into main
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.2 -> 1.1.3
- tests: fixed issue with package publishing workflow
- docs: added CI badge - removed old workflow badges
- tests: removed old actions + fully activate CI
- chore: created new combined ci action
- chore: closes #21, closes #20, closes #19
- fixed: codefactor issues with trailing spaces
- tests: fixed codefactor code quality niggles
- chore(docs): update TOC
- docs: created ToC gh action
- tests: added multi-platform bats test suite
- docs: fixed image issue - was not showing on gh docs
- merge: branch 'release-1.1.2' into main
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.1 -> 1.1.2
- tests: renamed test for compatibility with previous badge
- tests: ignored SC2288 - made SC fail on windows test
- tests: disabled SC1017 checking - on windows-latest invokes error
- tests: added more platforms for shellcheck testing
- tests: removed shellcheck follow file directive - it's covered by using the -x switch
- merge: pull request #18 from jv-k/stable
- merge: pull request #17 from jv-k/release-1.1.1
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.0 -> 1.1.1
- bugfix: un-capitalised first letter of changelog entry for ver-bump's own commit msg - because the rest of commit messages are lowercase (personal preference... see next bullet) - probably best left to the user to capitalise or not, perhaps don't enforce it (added future option to TODO.md) - updated BATS test case for changelog output assert test
- docs: moved todos into TODO.md
- docs: add demo GIF
- merge: branch 'stable' into main
- merge: branch 'release-1.1.0' into stable
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.0.5 -> 1.1.0
- tests: fixed "would clobber existing tag" error when running action
- docs: document remaining CLI switches
- docs: updated badges for new gh actions
- tests: added test for new -l CLI argument
- tests: update tests after refactors / chores that changed prompts
- feat: added previously implemented options to the CLI help prompt
- chore: changed help + prompt messages for clarity
- chore:  small refactor + capitalise first letter of changlog entry for files that ver-bump changes - following from d4770e5
- feat: fixes #15 added -l argument to the CLI for optional pausing right after changelog is created, - the default previously was to pause and wait for the user to check the changelog and press enter to continue - the default now is to bypass the prompt and make it optional by supplying the -l argument
- feat: added option to add a commit message prefix - By default "chore:  " is used
- refactor: change changelog & commit msg for changes the script makes -> lowercase
- tests: add fetch remote tags - fixes bats test failing when git history needs to be retrieved
- tests: changed versionfile bump tool from sed -> jq
- tests: Fixed changelog.md test
- chore: cleaned up unnecessary comments
- tests: fixed check-tag-exists assert
- tests: added test: check tag doesn't exist
- tests: changed functions to pass shellcheck - the `` Command Substitution that was changed to $() notation is difficult to make work, because of needed multiple double quotes, hence made them pass using exceptions
- chore: moved functions around for correct order
- merge: branch 'chore-unit-tests' into main - merge to add all the new testing functions to github actions
- tests: created test runner action
- chore: renamed test runner npm task for clarity
- chore: rename bats installer script
- merge: branch 'main' into chore-unit-tests - grab latest changes from main development branch
- merge: branch 'tests-shellcheck' into main
- chore: added shellcheck + changed bash scripts as per recommended
- chore: Rename release action for clarity
- tests: add tests for branch functions
- tests: dev commit for push/branch/commit functions
- Merge branch 'main' into chore-unit-tests
- refactor: in bump json files fn, changed to V_PREV -> V_NEW like rest of code + added detection for when version number will remain the same
- refactor: corrected do-changelog message about existing file
- refactor: corrected function name
- docs: moved TODO.md inside README.md + deleted file
- tests: clean up test set-up + added tests - added test for do-packagefile-bump - added test for bump-json-files success + failure + if no version is found (3 tests) - added test for check-tag-exists - added test for do-changelog
- tests: add bats-mock submodule
- tests: Update npm test run cmds + update Bats module
- Merge branch 'main' into chore-unit-tests
- Merge branch 'refactor-tests' into main
- tests: Added install script for BATS test runner
- tests: First commit of batch of unit tests
- refactor: abstractified version suggestion algorithm + changed the new desired version number var name + cleanup
- refactor(for tests): changed exit codes for proper error handling in tests
- refactor(for tests): disable msg styles when sourced + move main functions into main loop - separated styles and icons in prep for test regime, as the styles within the echo statements made them untestable - grabbing output with formatting failed when compared to plain text, or text with the same escape characters. - now the styles don't load when ver-bumped is sourced for testing with BATS
- bugfix: fixed -c disable changelog switch not taking arguments
- Merge branch 'bug-default-version' into main
- fix: failing on when version number unchanged and previously not bumped (#14)
- refactor: change tagging fn for cleaner code in stable module
- merge: branch 'release-1.0.5' into stable
- merge: branch 'release-1.0.5' into main
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.4 –> 1.0.5
- fix: Removed cross-env dependency. Unreliable detection of package.json parameters. No dependencies now!
- Merge branch 'release-1.0.4' into stable
- Merge branch 'release-1.0.4' into main
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.3 –> 1.0.4
- Merge branch 'release-1.0.3' into main
- Updated docs - lil typo
- Merge pull request #13 from jv-k/main
- Merge branch 'release-1.0.3' into stable
- Merge branch 'stable' of github.com:jv-k/ver-bump into stable
- Update docs - fixed broken contrib & license urls
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.2 –> 1.0.3
- docs: Updated README to remove duplicate table that shows detailed run steps
- Merge branch 'release-1.0.2' into stable Fixed #12
- Merge branch 'release-1.0.2' into main
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.2-beta.1 –> 1.0.2
- Fixes #12
- Update README.md
- Merge pull request #10 from jv-k/release-1.0.2-beta.1
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.1 –> 1.0.2-beta.1
- Merge branch 'stable' into main
- Update TODO.md
- Changed webhook for action
- Added build tast
- Publish to GitHub Package Registry and NPM
- Merge branch 'main' into stable
- Merge branch 'release-1.0.1' into main
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.0 –> 1.0.1
- Updated docs
- Update README.md
- Merge branch 'release-1.0.0' into stable - First confident release! 🚀✨
- Merge branch 'release-1.0.0' into main First confident release! 🚀✨
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.4 –> 1.0.0
- Bugfix: commit history since last tag wasn't working correctly - missing `v` in tag name
- Updated code comment
- Merge branch 'release-0.2.4' into stable
- Merge branch 'release-0.2.4' into main
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.3 –> 0.2.4
- Cleaned up code comment
- Bugfix: works now with no previous tags
- Added option to disable committing - For debug purposes. Not yet decided to put it in docs, it's not really useful for general usage.
- Update ver-bump CLI credits logo - Stole it from oh-my-zsh..!
- Updated docs From todos:   - [x] Docs: Inform user how the script works in the current branch   - [x] Docs: Local `npm` install   - [x] Docs: Semver + Gh branching model
- Removed placeholder CoC - not required for now!
- Merge branch 'release-0.2.3' into stable
- Merge branch 'release-0.2.3' into main
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.2 –> 0.2.3
- 📕 Add temporary instructions
- 📕 Add npm version badge
- Add issue and Feature request templates
- Merge pull request #6 from jv-k/add-code-of-conduct-1
- Create CODE_OF_CONDUCT.md
- Merge pull request #5 from jv-k/release-0.2.2
- Merge branch 'release-0.2.2' into main
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.1 –> 0.2.2
- Merge branch 'npm-publish-action' into main
- Merge pull request #4 from jv-k/npm-publish-action
- Update npm-publish.yml
- Update npm-publish.yml
- Merge pull request #3 from jv-k/release-0.2.1
- Update README.md
- Merge pull request #2 from jv-k/jv-k-patch-1
- Add NPM publish badge
- Create npm-publish.yml

## Unreleased — 2.0 (breaking)
- **BREAKING:** tag-in-place is now the default workflow. ver-bump 1.x always cut a `release-<version>` branch; 2.0 commits + tags the current branch in place. Pass `--branch` to keep the old behaviour.
- **BREAKING:** `-v <value>` now rejects non-SemVer input with exit `2` before any mutation; 1.x tagged whatever string you passed (`vbanana` included). Migration: pass valid SemVer.
- **BREAKING:** bare `-v` / `--version` (no value) now prints the tool version and exits `0`; in 1.x it was a parse error. `-v <semver>` is unchanged.
- **BREAKING:** exit codes are now a fixed contract — `0` success, `2` usage/parse, `3` precondition, `4` hook failure, `5` user abort; 1.x used `1` for everything. Wrappers branching on `0` vs non-zero are unaffected; those branching on specific codes must update.
- **BREAKING:** `npm` is no longer invoked at runtime, so `npm version` lifecycle scripts (`preversion` / `version` / `postversion`) no longer fire as a side-effect. Migration: run them explicitly, or set `PRE_BUMP_CMD` / `POST_TAG_CMD` in `.ver-bumprc`.
- feat: `--source <file>` sets the version source + primary bump target (default `package.json`), with a git-tag fallback so non-Node repos work.
- feat: `--bump <spec>` also bumps JSON / TOML / YAML / text files (repeatable; `file:@dotted.path` or a `{{version}}` text pattern). TOML/YAML paths need `tomlq` / `yq` (conditional deps).
- feat: `--major` / `--minor` / `--patch` force an explicit bump level from the current version.
- feat: `--preid <id>` starts or advances a prerelease line (e.g. `1.2.0-rc.1`); conflicts with `-v`.
- feat: `--pr` opens a release pull request via the `gh` CLI (branch + push + PR). Base resolves to `--base <branch>`, else `PR_BASE`, else the invocation branch, else the remote default branch.
- feat: `--branch` opts into the `release-<version>` branch workflow; `--base <branch>` sets the `--pr` PR base.
- feat: `--release` publishes a GitHub release for the new tag via `gh` (GitHub-only; requires `-p`). Notes default to `gh release create --generate-notes`, overridable with `$VER_BUMP_RELEASE_NOTES_CMD`.
- feat: `--sign` creates a signed tag (`git tag -s`; config `TAG_SIGN`).
- feat: `--undo [<version>]` rolls back a local release — deletes the tag (and any `release-*` branch) and reverts the bump commit, refusing when the tag was already pushed or the tree is dirty.
- feat: `-q` / `--quiet` prints only the new version on stdout for scripting (needs `-y`, `-v`, a bump level, or `--preid`).
- feat: `--completions <shell>` emits and `--install-completions` installs bash / zsh / fish completions.
- feat(config): `.ver-bumprc` config file — a permission-guarded loader with `CLI > env > file > default` precedence; unknown keys draw a non-fatal warning. Keys include `TAG_PREFIX`, `SOURCE_FILE`, `BUMP_FILES`, `CHANGELOG_STYLE`, `FLAG_BRANCH`, and `PR_BASE`.
- feat(config): `PRE_BUMP_CMD` / `POST_TAG_CMD` release hooks run before the bump / after the tag; a non-zero hook exits `4`. `--no-hooks` skips both for one run. Hooks see `VER_BUMP_VERSION`, `VER_BUMP_PREV_VERSION`, and `VER_BUMP_TAG`.
- feat(config): `COMMIT_MSG_TEMPLATE` customises the bump commit subject via `${version}` placeholders.
- feat(changelog): `CHANGELOG_STYLE=grouped` renders Conventional-Commit-grouped release notes; the default `flat` stays byte-identical to 1.x.
- feat(checks): safety preflights — `--allow-dirty`, `--allow-empty`, `--no-fetch`, plus a `RELEASE_BRANCHES` branch guard.
- feat(distribution): checksummed `curl … | bash` installer.
- deprecate: `-b` / `--no-branch` is now a no-op (kept for back-compat) and prints a deprecation notice.

## 1.1.8 (August 23, 2023)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.7 -> 1.1.8
- bug: fixed change that caused CI #94
- chore(tests): update bats
- chore(build): created release task
- style: removed extra ws
- Merge pull request #27 from jv-k/release-1.1.7
- chore(docs): update TOC
- chore(docs): update TOC

## 1.1.7 (August 23, 2023)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.6 -> 1.1.7
- docs: added testing section
- docs: fix linting issues
- docs: add switcher feat to todos
- docs: add basher deploy to todos
- merge branch: 'release-1.1.6' into main

## 1.1.6 (November 06, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.5 -> 1.1.6
- fix: disabled SC2086 double quote warning - The version tag isn't a concern if it were split
- fix: fixed bug when there's not previous tag - issue arises when there are commits, but no previous tag is present - bump failed at grabbing previous commit history for building the changlelog
- chore: added commitizen
- docs: added better comments task in TODO.md
- merge: branch 'release-1.1.5' into main

## 1.1.5 (July 22, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.4 -> 1.1.5
- Merge pull request #23 from jv-k/fix-npmissue
- bugfix: allow bumping when uncommitted changes exist
- merge: branch 'release-1.1.4' into main

## 1.1.4 (July 01, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.3 -> 1.1.4
- docs: fixed style issue
- merge: branch 'release-1.1.3' into main

## 1.1.3 (June 30, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.2 -> 1.1.3
- tests: fixed issue with package publishing workflow
- docs: added CI badge - removed old workflow badges
- tests: removed old actions + fully activate CI
- chore: created new combined ci action
- chore: closes #21, closes #20, closes #19
- fixed: codefactor issues with trailing spaces
- tests: fixed codefactor code quality niggles
- chore(docs): update TOC
- docs: created ToC gh action
- tests: added multi-platform bats test suite
- docs: fixed image issue - was not showing on gh docs
- merge: branch 'release-1.1.2' into main

## 1.1.2 (June 29, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.1 -> 1.1.2
- tests: renamed test for compatibility with previous badge
- tests: ignored SC2288 - made SC fail on windows test
- tests: disabled SC1017 checking - on windows-latest invokes error
- tests: added more platforms for shellcheck testing
- tests: removed shellcheck follow file directive - it's covered by using the -x switch
- merge: pull request #18 from jv-k/stable
- merge: pull request #17 from jv-k/release-1.1.1

## 1.1.1 (June 28, 2022)
- chore: updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.1.0 -> 1.1.1
- bugfix: un-capitalised first letter of changelog entry for ver-bump's own commit msg - because the rest of commit messages are lowercase (personal preference... see next bullet) - probably best left to the user to capitalise or not, perhaps don't enforce it (added future option to TODO.md) - updated BATS test case for changelog output assert test
- docs: moved todos into TODO.md
- docs: add demo GIF
- merge: branch 'stable' into main
- merge: branch 'release-1.1.0' into stable

## 1.1.0 (June 26, 2022)
- chore: Updated package.json, updated package-lock.json, updated CHANGELOG.md, bumped 1.0.5 -> 1.1.0
- tests: fixed "would clobber existing tag" error when running action
- docs: document remaining CLI switches
- docs: updated badges for new gh actions
- tests: added test for new -l CLI argument
- tests: update tests after refactors / chores that changed prompts
- feat: added previously implemented options to the CLI help prompt
- chore: changed help + prompt messages for clarity
- chore:  small refactor + capitalise first letter of changlog entry for files that ver-bump changes - following from d4770e5
- feat: fixes #15 added -l argument to the CLI for optional pausing right after changelog is created, - the default previously was to pause and wait for the user to check the changelog and press enter to continue - the default now is to bypass the prompt and make it optional by supplying the -l argument
- feat: added option to add a commit message prefix - By default "chore:  " is used
- refactor: change changelog & commit msg for changes the script makes -> lowercase
- tests: add fetch remote tags - fixes bats test failing when git history needs to be retrieved
- tests: changed versionfile bump tool from sed -> jq
- tests: Fixed changelog.md test
- chore: cleaned up unnecessary comments
- tests: fixed check-tag-exists assert
- tests: added test: check tag doesn't exist
- tests: changed functions to pass shellcheck - the `` Command Substitution that was changed to $() notation is difficult to make work, because of needed multiple double quotes, hence made them pass using exceptions
- chore: moved functions around for correct order
- merge: branch 'chore-unit-tests' into main - merge to add all the new testing functions to github actions
- tests: created test runner action
- chore: renamed test runner npm task for clarity
- chore: rename bats installer script
- merge: branch 'main' into chore-unit-tests - grab latest changes from main development branch
- merge: branch 'tests-shellcheck' into main
- chore: added shellcheck + changed bash scripts as per recommended
- chore: Rename release action for clarity
- tests: add tests for branch functions
- tests: dev commit for push/branch/commit functions
- Merge branch 'main' into chore-unit-tests
- refactor: in bump json files fn, changed to V_PREV -> V_NEW like rest of code + added detection for when version number will remain the same
- refactor: corrected do-changelog message about existing file
- refactor: corrected function name
- docs: moved TODO.md inside README.md + deleted file
- tests: clean up test set-up + added tests - added test for do-packagefile-bump - added test for bump-json-files success + failure + if no version is found (3 tests) - added test for check-tag-exists - added test for do-changelog
- tests: add bats-mock submodule
- tests: Update npm test run cmds + update Bats module
- Merge branch 'main' into chore-unit-tests
- Merge branch 'refactor-tests' into main
- tests: Added install script for BATS test runner
- tests: First commit of batch of unit tests
- refactor: abstractified version suggestion algorithm + changed the new desired version number var name + cleanup
- refactor(for tests): changed exit codes for proper error handling in tests
- refactor(for tests): disable msg styles when sourced + move main functions into main loop - separated styles and icons in prep for test regime, as the styles within the echo statements made them untestable - grabbing output with formatting failed when compared to plain text, or text with the same escape characters. - now the styles don't load when ver-bumped is sourced for testing with BATS
- bugfix: fixed -c disable changelog switch not taking arguments
- Merge branch 'bug-default-version' into main
- fix: failing on when version number unchanged and previously not bumped (#14)
- refactor: change tagging fn for cleaner code in stable module
- merge: branch 'release-1.0.5' into stable
- merge: branch 'release-1.0.5' into main
- Merge branch 'release-1.0.4' into stable
- Merge pull request #13 from jv-k/main
- Merge branch 'release-1.0.3' into stable
- Merge branch 'stable' of github.com:jv-k/ver-bump into stable
- Update docs - fixed broken contrib & license urls

## 1.0.5 (February 04, 2022)
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.4 –> 1.0.5
- fix: Removed cross-env dependency. Unreliable detection of package.json parameters. No dependencies now!
- Merge branch 'release-1.0.4' into develop

## 1.0.4 (February 03, 2022)
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.3 –> 1.0.4
- Merge branch 'release-1.0.3' into develop
- Updated docs - lil typo
- Merge branch 'release-1.0.2' into develop

## 1.0.3 (January 27, 2022)
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.2 –> 1.0.3
- docs: Updated README to remove duplicate table that shows detailed run steps
- Merge branch 'release-1.0.2' into main Fixed #12

## 1.0.2 (October 07, 2021)
- Updated package.json, Updated package-lock.json, Updated CHANGELOG.md, Bumped 1.0.2-beta.1 –> 1.0.2
- Fixes #12
- Update README.md
- Merge pull request #10 from jv-k/release-1.0.2-beta.1
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.1 –> 1.0.2-beta.1
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.1 –> 1.0.2-beta.1

## 1.0.2-beta.1 (September 28, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.1 –> 1.0.2-beta.1
- Merge branch 'main' into develop
- Update TODO.md
- Changed webhook for action
- Added build tast
- Publish to GitHub Package Registry and NPM
- Merge branch 'develop' into main
- Merge branch 'release-1.0.1' into develop
- Merge branch 'release-1.0.0' into main - First confident release! 🚀✨
- Merge branch 'release-0.2.4' into main
- Merge branch 'release-0.2.3' into main

## 1.0.1 (September 28, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 1.0.0 –> 1.0.1
- Updated docs
- Update README.md
- Merge branch 'release-1.0.0' into develop First confident release! 🚀✨

## 1.0.0 (September 27, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.4 –> 1.0.0
- Bugfix: commit history since last tag wasn't working correctly - missing `v` in tag name
- Updated code comment
- Merge branch 'release-0.2.4' into develop

## 0.2.4 (September 27, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.3 –> 0.2.4
- Cleaned up code comment
- Bugfix: works now with no previous tags
- Added option to disable committing - For debug purposes. Not yet decided to put it in docs, it's not really useful for general usage.
- Update ver-bump CLI credits logo - Stole it from oh-my-zsh..!
- Updated docs From todos:   - [x] Docs: Inform user how the script works in the current branch   - [x] Docs: Local `npm` install   - [x] Docs: Semver + Gh branching model
- Removed placeholder CoC - not required for now!
- Merge branch 'release-0.2.3' into develop

## 0.2.3 (September 22, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.2 –> 0.2.3
- 📕 Add temporary instructions
- 📕 Add npm version badge
- Add issue and Feature request templates
- Merge pull request #6 from jv-k/add-code-of-conduct-1
- Create CODE_OF_CONDUCT.md
- Merge pull request #5 from jv-k/release-0.2.2
- Merge pull request #4 from jv-k/npm-publish-action

## 0.2.2 (September 15, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.1 –> 0.2.2
- Merge branch 'npm-publish-action' into develop
- Added badges to docs
- Update npm-publish.yml
- Update npm-publish.yml
- Merge pull request #3 from jv-k/release-0.2.1
- Merge branch 'release-0.2.1' into develop
- Update README.md
- Merge pull request #2 from jv-k/jv-k-patch-1
- Add NPM publish badge
- Create npm-publish.yml
- Merge pull request #1 from jv-k/release-0.2.0
- Merge branch 'release-0.1.4' into main
- Merge branch 'release-0.1.3' into master
- Merge branch 'release-0.1.3'
- Merge branch 'release-0.1.2'
- Merge branch 'release-0.1.0'

## 0.2.1 (September 14, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.2.0 –> 0.2.1
- 🧹 comments
- Merge branch 'release-0.2.0' into develop

## 0.2.0 (August 25, 2021)
- Updated package.json, Updated CHANGELOG.md, Bumped 0.1.4 –> 0.2.0
- Move helper functions to separate file
- Read version from package.json Remove default fetch of version from VERSION file Updated comments
- Saving commit
- Merge branch 'release-0.1.4' into develop
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.3 –> 0.1.4
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.3 –> 0.1.4

## 0.1.4 (August 17, 2021)
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.3 –> 0.1.4
- Renamed script + update docs
- Move bash colours/styles to separate file
- Allow help to show without a commit present
- Merge branch 'release-0.1.3' into develop
- Fix: Git message was repeating
- Merge branch 'release-0.1.3' into develop

## 0.1.3 (November 27, 2020)
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.2 –> 0.1.3
- Fixed: Docs: Added -b to usage
- Merge branch 'release-0.1.2' into develop

## 0.1.2 (November 27, 2020)
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.1 –> 0.1.2
- Fix: line break issue in help msg
- Removed hard-coded version no. in script
- Fixed CHANGELOG commit message bug
- Merge branch 'release-0.1.1' into develop

## 0.1.1 (November 27, 2020)
- Updated VERSION, Updated CHANGELOG.md, Bumped 0.1.0 –> 0.1.1
- Docs: Added entry for -b argument (disables branch creation)
- Merge branch 'release-0.1.0' into develop
- Added gitignore

## 0.1.0 (November 27, 2020)
- Created VERSION, Created CHANGELOG.md, Bumped to 0.1.0
- 🚀 Initial commit

