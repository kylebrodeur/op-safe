# AGENTS.md: the boundary of this repo, stated as rules

An agent working inside `op-safe/` obeys these rules. They are the
contract; everything else in the docs is detail.

## What this repo is

A metadata-first 1Password CLI helper for local agents: one bash script
(`op-access.sh`) that lists metadata, mints non-secret `op://` references,
saves one selected secret to a mode-0600 temp file, and cleans that file
up. Secret values are never printed.

## Rules an agent keeps here

1. **Secret values are never printed.** Every command that touches `op`
   either renders metadata, or writes a value to the mode-0600 temp file
   and prints only the path. Never add a code path that echoes, logs, or
   inspects a value.
2. **`cleanup` removes only what `save` created.** The prefix check
   (`/tmp/op-safe-op.` by default, `OP_TMP_ROOT` when set) is the safety
   boundary. Never loosen it, never bypass it, never remove a file the
   pattern did not match.
3. **One script, no flags that change the contract.** The command surface
   is exactly `accounts | status | signin | vaults | items | fields |
   reference | save | cleanup` plus `help`. A new command needs a
   documented value-flow argument before it lands.
4. **No project names, no account defaults inside the source.** The
   default account is empty (`OP_ACCOUNT` decides); the default temp
   prefix is the neutral `/tmp/op-safe-op`. This is the family's
   extraction discipline: the kit carries no consumer identity.
5. **Tests cover the value-flow gates.** Any change to `items`, `fields`,
   `reference`, `save`, or `cleanup` updates `tests/op-access.bats` in the
   same change, and the suite must pass: `tests/run-tests.sh`.
6. **Validation fails closed.** A malformed `op://` reference, an unsafe
   file extension, or an unreachable account exits nonzero with the
   documented error string; it never degrades to a best effort.
7. **Keep the docs honest per the family standard**: real commands with
   expected output, errors carrying their fix, no em or en dashes, no
   AI-slop words, no personal identifiers, and a check date on factual
   claims. Run the suite:
   `tests/run-tests.sh`
8. **Status comments on unshipped claims.** Any doc line that describes
   behavior not in `op-access.sh` today carries DESIGN or PLANNED.

## Where to start reading

`docs/quickstart.md` is the one starting point; `docs/RUNBOOK.md` is the
operator's surface and error table. The skill in
`skills/op-safe/SKILL.md` is the short form of rules 1 through 4.