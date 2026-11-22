# Config file (.verbumprc)

Repo- or home-level defaults without repeating flags. Shipped in 2.0
(originally a PRD non-goal; the PRD was reconciled — see §5.10).

| ID | Requirement | Status |
| --- | --- | --- |
| R-CFG-1 | Discovered by walking up from `$PWD` to `/`; first match wins; absence is not an error. | ✅ shipped — `_find-rc-upward` |
| R-CFG-2 | Supported keys (`_CONFIG_KEYS`): `TAG_PREFIX`, `REL_PREFIX`, `PUSH_DEST`, `COMMIT_MSG_PREFIX`, `COMMIT_MSG_TEMPLATE` (#69, R-TPL), `FLAG_BRANCH`, `PR_BASE`, `CHANGELOG_STYLE` (#61), `FLAG_NOCHANGELOG`, `FLAG_CHANGELOG_PAUSE`, `ALLOW_DIRTY` (R-SAFE-2), `NO_FETCH` (R-SAFE-8), `RELEASE_BRANCHES` (R-SAFE-10), `TAG_SIGN` (R-SIGN-1), `SOURCE_FILE` (R-SRC), `BUMP_FILES` (R-TGT), `PRE_BUMP_CMD` / `POST_TAG_CMD` (R-HOOK-1/2), `RELEASE_NOTES_AGENT` / `RELEASE_NOTES_PROMPT` (R-REL-10/11), plus deprecated `FLAG_NOBRANCH` (back-compat; superseded by `FLAG_BRANCH`, ADR-12). Only these get precedence tracking; other assignments execute as raw shell (R-CFG-5) with no guarantee and now warn (R-CFG-7). | ✅ shipped |
| R-CFG-3 | Precedence: CLI > env > `.verbumprc` > built-in default, end-to-end. | ✅ shipped (`f6d66b4`) — `test/config-env.bats` |
| R-CFG-4 | Refused (exit `3`) if world-writable, group-writable, or not owned by the invoking user. | ✅ shipped (`6a37077`) |
| R-CFG-5 | Shell-sourced, not parsed; sourcing failures exit `3` with the shell error as context. | ✅ shipped |
| R-CFG-6 | CLI-only switches (`DO_RELEASE`, `BUMP_LEVEL`) reset before parsing — env/rc can never force a bump or release. | ✅ shipped (`783f457`) |
| R-CFG-7 | Top-level assignments to keys outside `_CONFIG_KEYS` draw a non-fatal stderr warning (heuristic; catches typos like `TAG_PREFX=`); exit stays `0`. | ✅ shipped — `_warn-unknown-rc-keys` |

Unknown keys (R-CFG-7): a lint heuristic warns (non-fatal, stderr) on
top-level `NAME=` assignments outside `_CONFIG_KEYS` (ADR-05) — it catches
typos, not computed or indented assignments, and is not a security control
(that boundary is the permission gate, R-CFG-4). `FLAG_YES` is deliberately not
an rc key; see [non-interactive](../non-interactive/requirements.md).

Precedence is enforced by call ordering in `main()`
(`load-config` → `apply-config-defaults` → `process-arguments`) — don't
reorder, don't add a fifth tier (see `docs/CODE_STYLE.md`).

Modules: `lib/config.sh`. Tests: `test/config.bats` (17),
`test/config-env.bats` (4).
