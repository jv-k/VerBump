<div align="center">
  <img src="https://raw.githubusercontent.com/jv-k/VerBump/main/img/social-preview.png" alt="VerBump social card: the VerBump wordmark in a yellow, green, cyan and purple gradient in a dark terminal window, the current version pill, the tagline 'Release tool for any Git repo.', and the pipeline Conventional Commits, SemVer, changelog, tag, push.">
</div>

**A plain-bash release tool for any Git repo.**

- **Suggests the right bump** — reads your [Conventional Commits](https://www.conventionalcommits.org/) to propose the next [SemVer](https://semver.org/), prereleases included
- **Writes the changelog** — flat or grouped by commit type, with commit / PR / compare links
- **Bumps any file** — `package.json`, `pyproject.toml`, `Chart.yaml`, a Go const, any `{{version}}` text pattern
- **Three workflows** — tag in place, cut a release branch, or open a GitHub PR
- **Safe by default** — preflight checks, `--dry-run` previews every side-effect, `--undo` rolls back
- **Nothing to install but bash** — `git` and `jq` are the only runtime dependencies

<div align="center">

[![bash 3.2+](https://img.shields.io/badge/bash-3.2%2B-1f425f?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/) [![CI](https://img.shields.io/github/actions/workflow/status/jv-k/VerBump/ci.yml?branch=main&label=CI&logo=githubactions&logoColor=white)](https://github.com/jv-k/VerBump/actions/workflows/ci.yml?query=branch%3Amain) [![CodeFactor](https://www.codefactor.io/repository/github/jv-k/VerBump/badge)](https://www.codefactor.io/repository/github/jv-k/VerBump) [![npm version](https://img.shields.io/npm/v/%40jv-k%2Fverbump?logo=npm&color=cb3837)](https://www.npmjs.com/package/@jv-k/verbump) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<img src="https://raw.githubusercontent.com/jv-k/VerBump/main/img/screenshot.png" alt="verbump --help output: the header logo and the full flag reference, covering version input, bump levels, prerelease, changelog, tag, push, and GitHub release options.">

</div>

## Quickstart

### Install with curl (no Node required):

```sh
curl -fsSL https://raw.githubusercontent.com/jv-k/VerBump/main/install.sh | bash
```

### Install from a registry (npm / pnpm):

```sh
pnpm add -g @jv-k/verbump
```

or

```sh
npm install -g @jv-k/verbump
```

> The npm package is **`@jv-k/verbump`** (npm reserves the bare name `verbump`); it installs the **`verbump`** command.

### Install with Homebrew:

```sh
brew install jv-k/tap/verbump
```

### Updating:

```sh
verbump --update
```

Install-script installs update in place. For npm, Homebrew, and git clones, it prints the command to run instead. See [Updating](https://verbump.jvk.to/docs/installation#updating).

### Use it in your repo folder:

```sh
cd your-repo
verbump --dry-run   # preview a release end-to-end, changes nothing
verbump             # cut it: reads commits, suggests a bump, prompts before pushing
```

## Demo

<div align="center">
  <img src="https://raw.githubusercontent.com/jv-k/VerBump/main/img/verbump-demo.gif" alt="Animated demo: VerBump reads commits, sets the version, updates package.json and CHANGELOG, commits, tags in place, prompts before pushing, then pushes the tag to origin.">
</div>

## Documentation

**Full docs live at [verbump.jvk.to](https://verbump.jvk.to)** — the canonical
guide to installing, configuring, and releasing with VerBump:

- [Quickstart](https://verbump.jvk.to/docs/quickstart) — install and cut your first release
- [Workflows](https://verbump.jvk.to/docs/guides/workflows) — tag in place, release branch, or release PR
- [Version suggestion](https://verbump.jvk.to/docs/guides/version-suggestion) — how commits pick the next SemVer
- [Bump targets](https://verbump.jvk.to/docs/guides/bump-targets) — non-Node projects and extra files
- [CLI options](https://verbump.jvk.to/docs/reference/cli) — every flag, grouped like `verbump --help`
- [Configuration](https://verbump.jvk.to/docs/reference/configuration) — `.verbumprc`, every key
- [Migrating](https://verbump.jvk.to/docs/guides/migrating) — from 1.x or the old `ver-bump`

## Requirements

**Bash 3.2+**, a **Git repository**, and **`git`** + **`jq`** on your `PATH`.
The [`gh`](https://cli.github.com) CLI is optional, used only by `--pr` and
`--release`. GitHub is supported today; GitLab and Bitbucket support is
coming soon. Linux and macOS are tested in CI; see
[platform support](https://verbump.jvk.to/docs/requirements).

## Development

Contributions are welcome — start with [`CONTRIBUTING.md`](CONTRIBUTING.md),
then open [an issue or pull request](https://github.com/jv-k/VerBump/issues/new/choose).
Coding standards, commit conventions, and the test/lint workflow live in
[`docs/CODE_STYLE.md`](docs/CODE_STYLE.md); the sandbox harness and test suite
are described there too:

```sh
pnpm dev             # exercise VerBump against a throwaway sandbox repo
pnpm lint            # shellcheck
pnpm tests:install   # one-time: vendors bats-core + helpers
pnpm tests:run       # run the full bats suite
```

## License

The scripts and documentation in this project are released under the [MIT license](LICENSE).
