<!-- STATUS: VERIFIED 2026-10-22. Every error string below is quoted from op-access.sh source every flag was checked against the case branches. -->
# RUNBOOK.md: the operator's reference

The full command surface, the environment, every error string with its
fix, and the recovery procedures. Task-shaped guidance lives in
[how-to.md](how-to.md); the setup path lives in
[quickstart.md](quickstart.md).

## The command surface

Exactly nine subcommands (`op-access.sh`), no more:

```
accounts  status  signin  vaults  items  fields  reference  save  cleanup
```

Plus `help` (`-h`, `--help`, or no arguments) which prints the usage text.

## Environment

| Name | Meaning |
|---|---|
| `OP_ACCOUNT` | The 1Password account shorthand passed as `--account` to every `op` call. Default: empty, so `op` uses its own configured default. |
| `OP_TMP_ROOT` | The temp-file prefix for `save` and the allowed prefix for `cleanup`. Default: `/tmp/op-safe-op`. |
| `OP_BIOMETRIC_UNLOCK_ENABLED` | Exported to `op` as `true` by default so the desktop app integration is used when available. |

The temp file mode is enforced twice: `umask 077` at start, then an
explicit `chmod 600` on the created file.

## Command details

### Non-secret commands (safe to run anywhere)

| Command | What it prints |
|---|---|
| `accounts` | `op account list`, unchanged. |
| `status` | A metadata probe of the selected account. Never `op whoami`. |
| `signin` | Interactive desktop or biometric sign-in. |
| `vaults [query]` | Vault `id` and `name` rows, `@tsv`, filtered by name. |
| `items [query] [vault]` | Item `id`, `title`, `category`, vault name rows; filtered by title. |
| `fields <item> [vault]` | A field table: `id`, `label`, `type`, section label. Values are not read. |

`vaults`, `items`, and `fields` require `jq` and a reachable session (the
tool probes with `op account get` before running them).

### `reference <item> <field> [vault]`

Resolves the item JSON, matches the field by exact id or exact label
(case sensitive, matching `op`'s own reference semantics), and prints:

```text
op://<vault name>/<item title>/<field label>
```

Literal spaces are kept: the 1Password CLI rejects percent-encoding in
secret references. A field with no label match exits 1 with the
not-found error below; disambiguate with the `[vault]` argument.

### `save <op://vault/item/field> [extension]`

Validations, in order, all fail-closed:

1. The reference must match `op://*/*/*` with all three parts non-empty,
   else exit 2.
2. The extension must be `[A-Za-z0-9._-]*`, else exit 2.
3. The ownership record must be written, else nothing is saved and exit
   1. The record is made BEFORE the secret is read, so a secret can
   never exist without a way to clean it up.
4. `op read` must succeed, else the save directory is removed and exit 1.

On success it prints exactly one line: the created path. The file is
mode 0600, sits in its own private directory under the configured prefix,
and holds the raw secret value from `op read`.

### `cleanup <temporary-path>`

Removes a file that the tool CREATED, overwriting its bytes first when
`shred` is available, and prints `removed: <path>`.

Provenance is proved by the ownership registry, not by the file's name.
`save` records the path and an unguessable token in a registry that
lives outside the save directory, and writes the same token beside the
secret. `cleanup` removes a file only when the registry has a record for
it AND the token beside the file matches that record.

The registry is serialized with a lock directory, so a save that runs
while a cleanup is rewriting the registry waits for the rewrite and then
appends. Without the lock, a save landing in that window would lose its
record, and the secret it just wrote could never be cleaned up.

So a same-user file that merely shares the name prefix is NOT removed:
a forged directory has no registry record, and it cannot present the
token a real save directory carries. Anything else is refused:

- a path with no registry record exits 2 (the refusal is the safety
  boundary)
- a path with a record but a mismatched token exits 2
- a matching but missing path exits 1

## Error strings and their fixes

Every error is printed to stderr. Find your string, apply its fix.

| Error string | Cause and fix |
|---|---|
| `ERROR: 1Password CLI ('op') is not installed.` | `op` is not on PATH. Install the 1Password CLI and retry (exit 127). |
| `ERROR: jq is required.` | `jq` is not on PATH. Install it (`brew install jq`) and retry (exit 127). |
| `ERROR: 1Password account '<name>' is not reachable.` | The desktop app is locked, closed, or not integrated. Unlock it, enable `Settings > Developer > Integrate with 1Password CLI`, then run `op-access.sh signin` (exit 1). |
| `ERROR: field '<field>' was not found. Run the fields command first.` | The label or id does not exist on that item. Run `op-access.sh fields <item>` and copy an exact label or id (exit 1). |
| `ERROR: save requires a complete op://vault/item/field reference.` | The argument is not an `op://` string with three non-empty parts. Mint one with `reference`, then `save` it (exit 2). |
| `ERROR: unsafe extension '<ext>'.` | The extension has characters outside `[A-Za-z0-9._-]`. Drop the argument or use one like `.txt` (exit 2). |
| `ERROR: unable to read the selected secret reference.` | `op read` failed. Check the vault, item, and field names with the metadata commands, verify sign-in with `status`, then retry (exit 1). |
| `ERROR: cannot record ownership; refusing to write a secret that cannot be cleaned up.` | The ownership registry could not be written (a read-only or unwritable registry directory). Fix the registry location or its permissions, then retry. Nothing was saved (exit 1). |
| `ERROR: refusing to remove a path not created by this helper.` | The path has no ownership record, or its token does not match the record. `cleanup` accepts only files `save` created; if the file is yours, delete it yourself (exit 2). |
| `ERROR: temporary file does not exist: <path>` | The file is gone. Nothing to do (exit 1). |
| `ERROR: unknown command '<cmd>'.` plus usage | A typo. Use one of the nine commands (exit 2). |

`<field>` and `<item>` argument omissions exit with the matching
`Usage: op-access.sh <command>` line instead of a table row.

## Recovery procedures

### The desktop app integration refuses

Symptom: the not-reachable error right after unlocking the app.

1. Confirm the desktop app itself is unlocked (open it once).
2. Confirm integration: `Settings > Developer > Integrate with 1Password
   CLI` is on.
3. Run `op-access.sh signin`, then `op-access.sh status`.

### A duplicate item title picks the wrong item

Symptom: `reference` or `fields` answers for the wrong copy.

1. Run `op-access.sh items <title>`; read the vault names on each row.
2. Re-run with the vault: `op-access.sh fields <title> <vault>`.

### A saved temp file was orphaned

Symptom: `ls /tmp/op-safe-op.*` shows directories the consumer never
cleaned.

1. For each path: `op-access.sh cleanup <path>` (overwrite + remove).
2. Adopt the `trap ... EXIT` pattern from `docs/how-to.md` in the
   consuming script so the next run cleans itself up.

### `cleanup` refuses a path you believe op-safe made

The refusal is registry-based: the path must have an ownership record
made by `save`, and the token beside the file must match that record.
The registry lives at `$OP_SAFE_REGISTRY` (default:
`${OP_TMP_ROOT}.registry`).

If you ran `save` with a different `OP_TMP_ROOT` or a different
`OP_SAFE_REGISTRY`, set the same values for this `cleanup` call. If the
registry is gone entirely (a wiped `/tmp`, say), the file can no longer
be proven to be yours, so remove it manually.

## What this runbook does NOT cover

- 1Password account, vault, or permission administration: the desktop
  app and `op` own those surfaces.
- Creating, editing, or sharing items: op-safe is deliberately read-only
  plus one temp write.
- Any command that prints a field value: no such command exists, and
  adding one is outside the boundary AGENTS.md states.