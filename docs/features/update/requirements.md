# Self-update (`--update`)

`verbump --update [version]` updates VerBump in place, with whatever tool
installed it. This is the explicit, on-demand form of an "autoupdate". ADR-15 rules out a
default-path network call, so there is no background check and no silent
update.

| ID | Requirement | Status |
| --- | --- | --- |
| R-UPD-1 | `--update [<version>]` (space or `=` form, leading `v` accepted) is a pre-scanned mode: it runs and exits before any repo preflight, so it works outside a git repo. An empty or non-SemVer version exits 2. | ✅ shipped — `test/update.bats` |
| R-UPD-2 | The install channel is read from the running script's resolved path: a `.git` entry → git checkout; `*/Cellar/verbump/*` → Homebrew; `*/node_modules/@jv-k/verbump` → a Node package manager (R-UPD-7); `*/share/verbump` → install script; anything else → unknown. A git checkout wins over every path pattern (the manual install clones to `~/.local/share/verbump`). | ✅ shipped — `test/update.bats` |
| R-UPD-3 | Install-script channel: runs a temp copy of the `install.sh` that ships inside the install, with `--prefix <prefix>` and `--version <v>` when pinned, and with `VERBUMP_INSTALL_VERSION` / `VERBUMP_PREFIX` cleared so the user's shell cannot redirect it. Reports `Updated VerBump A → B`, or that the version is unchanged. An installer failure exits with the installer's code and a retry hint. | ✅ shipped — `test/update.bats` |
| R-UPD-4 | A git checkout, an unknown layout, and an install-script tree with no `install.sh` exit 3 without running anything, with a hint naming the command that does update them. A git checkout is left alone because it may be the user's own working clone. | ✅ shipped — `test/update.bats` |
| R-UPD-5 | `--update` honours `--dry-run` in either argv position: it prints the installer command to stderr with the `[dry-run]` prefix and runs nothing. | ✅ shipped — `test/update.bats` |
| R-UPD-7 | Homebrew installs run `brew update`, then `brew upgrade jv-k/tap/verbump` with `HOMEBREW_NO_AUTO_UPDATE=1` (the taps were just refreshed). A pinned version exits 2, because a tap formula has no per-version install. Node installs re-install `@jv-k/verbump@<version or latest>` globally with the manager read from the path: `.pnpm/` or `pnpm/global/` → pnpm, `.bun/install/global/` → bun, `yarn/global/` → yarn, else npm. A missing tool exits 3; a failing command exits with its own code. Each command goes through `_update-run`, so `--dry-run` previews it. The new version is read back from the `verbump` on `PATH`, because a package manager may install it at a new path. | ✅ shipped — `test/update.bats` |
| R-UPD-6 | The release tarball carries `install.sh`, so every install-script install from this release on can update itself through the checksummed path (`publish-release-assets` in `ci.yml`). | ✅ shipped — `test/install.bats` fixture mirrors the CI file set |

Design notes:

- **Why not pipe `install.sh` from `main`?** That would run unreleased,
  unverified code. The shipped copy is part of a tarball whose sha256 was
  checked when it was installed, and it verifies the new tarball the same way.
- **Why a temp copy?** The installer swaps out the directory it lives in.
- **Why run the package manager?** Updating with a different tool than the
  one that installed VerBump leaves two copies, with the old one still first
  on `PATH`. So `--update` always drives the owning tool.
- **Why `brew update` first?** `brew upgrade` only sees formula versions the
  local tap already knows. The explicit `brew update` works even when the
  user sets `HOMEBREW_NO_AUTO_UPDATE`.
- Installs made before this release have no `install.sh` in the tree, and
  also no `--update` flag. They re-run the curl one-liner once.
- `_update-exec` is the process seam. The tests swap the shipped
  `install.sh` for a stub and put stub package managers on `PATH`, so the
  suite never touches the network.

Modules: `lib/update.sh`, the `--update` pre-scan in `lib/args.sh`.
Tests: `test/update.bats`.
