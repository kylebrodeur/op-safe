<!-- STATUS: VERIFIED 2026-10-22 against op-access.sh + tests/op-access.bats (29 tests passing). -->
# How-to: day-to-day operation

Task-shaped answers for the things you do repeatedly once op-safe is
working. The one-time setup is [quickstart.md](quickstart.md); every
command, flag, and error is indexed in [RUNBOOK.md](RUNBOOK.md).

## Give a script one secret without seeing it

```bash
REF=$(./op-access.sh reference <item> '<field label>')
PATH_ONLY=$(./op-access.sh save "$REF")
myscript --with-file "$PATH_ONLY"
./op-access.sh cleanup "$PATH_ONLY"
```

The script reads the file; your terminal, logs, and scrollback only ever
saw the reference and the path. Call `cleanup` as soon as the consumer
has read its value, including on the error path of the consuming script.

## Point the tool at a specific account

```bash
export OP_ACCOUNT=work-shorthand
./op-access.sh status
```

Expected: that account's metadata, or the not-reachable error with the
sign-in fix. Export it in the shell that runs the tool; nothing else
reads it.

## Keep agent temp files in a dedicated place

```bash
export OP_TMP_ROOT=/tmp/agent-secrets
```

Every `save` lands under `$OP_TMP_ROOT.` and every `cleanup` accepts
exactly that prefix. Setting it per session keeps one agent's files from
another agent's prefix and gives you one directory to audit.

## Wire the cleanup into a consuming script's error path

```bash
#!/usr/bin/env bash
set -euo pipefail
REF=$(op-access.sh reference deploy 'deploy key')
SECRETS=$(op-access.sh save "$REF")
trap 'op-access.sh cleanup "$SECRETS"' EXIT
# ... the script's own work, reading "$SECRETS" ...
```

The trap removes the file on success and on failure alike; a foreign path
refused by `cleanup` is a loud exit, never a silent skip.

## Find which fields an item has (without reading their values)

```bash
./op-access.sh fields '<item>' [vault]
```

```text
password	Project API Key	CONCEALED
note	Usage Note	STRING
```

IDs and labels on the left, values nowhere. Duplicate item titles across
vaults are disambiguated with the vault argument, by name or id.

## Audit what op-safe could remove right now

```bash
ls -la /tmp/op-safe-op.* 2>/dev/null
```

Each of those files is a `save` that was not cleaned up. Removing one by
hand is possible but discouraged: prefer
`./op-access.sh cleanup <path>` so the refusal boundary stays the only
removal code that runs.