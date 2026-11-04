# Self-update (`--update`)

`verbump --update [version]` updates VerBump in place. The user asked for an
"autoupdate"; this ships the explicit, on-demand form. ADR-15 rules out a
default-path network call, so there is no background check and no silent
update.

| ID | Requirement | Status |
| --- | --- | --- |
| R-UPD-1 | `--update [<version>]` (space or `=` form, leading `v` accepted) is a pre-scanned mode: it runs and exits before any repo preflight, so it works outside a git repo. An empty or non-SemVer version exits 2. | ✅ shipped — `test/update.bats` |
| R-UPD-2 | The install channel is read from the running script's resolved path: a `.git` entry → git checkout; `*/Cellar/verbump/*` → Homebrew; `*/node_modules/@jv-k/verbump` → npm/pnpm; `*/share/verbump` → install script; anything else → unknown. A git checkout wins over every path pattern (the manual install clones to `~/.local/share/verbump`). | ✅ shipped — `test/update.bats` |
| R-UPD-3 | Install-script channel: runs a temp copy of the `install.sh` that ships inside the install, with `--prefix <prefix>` and `--version <v>` when pinned, and with `VERBUMP_INSTALL_VERSION` / `VERBUMP_PREFIX` cleared so the user's shell cannot redirect it. Reports `Updated VerBump A → B`, or that the version is unchanged. An installer failure exits with the installer's code and a retry hint. | ✅ shipped — `test/update.bats` |
| R-UPD-4 | Channels VerBump does not own (git, Homebrew, npm, unknown) and an install-script tree with no `install.sh` exit 3 without running anything, with a hint naming the command that does update them. | ✅ shipped — `test/update.bats` |
| R-UPD-5 | `--update` honours `--dry-run` in either argv position: it prints the installer command to stderr with the `[dry-run]` prefix and runs nothing. | ✅ shipped — `test/update.bats` |
| R-UPD-6 | The release tarball carries `install.sh`, so every install-script install from this release on can update itself through the checksummed path (`publish-release-assets` in `ci.yml`). | ✅ shipped — `test/install.bats` fixture mirrors the CI file set |

Design notes:

- **Why not pipe `install.sh` from `main`?** That would run unreleased,
  unverified code. The shipped copy is part of a tarball whose sha256 was
  checked when it was installed, and it verifies the new tarball the same way.
- **Why a temp copy?** The installer swaps out the directory it lives in.
- **Why exit 3 for npm/Homebrew rather than run them?** Running another
  package manager on the user's behalf is a surprise mutation, and a
  non-zero exit keeps `verbump --update && …` honest in scripts.
- Installs made before this release have no `install.sh` in the tree, and
  also no `--update` flag. They re-run the curl one-liner once.
- `_update-run-installer` is the process seam; the tests swap the shipped
  `install.sh` for a stub, so the suite never touches the network.

Modules: `lib/update.sh`, the `--update` pre-scan in `lib/args.sh`.
Tests: `test/update.bats`.
