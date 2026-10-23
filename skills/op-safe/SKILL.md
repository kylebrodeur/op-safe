---
name: op-safe
description: Use when a local agent needs a 1Password secret without seeing its value, wants to mint a non-secret op:// reference, must save a secret to a temp file, or is wiring secret cleanup into an agent workflow.
---

# op-safe skill: secrets for agents without ever printing one

Use when an agent task needs a credential: mint a reference, save one
selected secret to a 0600 file, clean it up. This skill teaches the
boundary:

1. **Metadata only on any list command.** `accounts`, `status`, `signin`,
   `vaults`, `items`, `fields` print ids, titles, labels, and types. If a
   command's output can contain a field value, it is not one of these.
2. **The pointer, not the value.** `reference` prints the non-secret
   `op://vault/item/field` string. Hold references in notes, configs, and
   conversation; resolve one only at the moment of use.
3. **`save` is the only value path and it ends in a 0600 file.**
   `save <op://vault/item/field> [ext]` prints ONLY the temp path. Read
   the file programmatically, never echo it.
4. **`cleanup` is the only removal path and it refuses foreign paths.**
   Files under `/tmp/op-safe-op.` (or `OP_TMP_ROOT`) that `save` created
   are what `cleanup` accepts; anything else exits 2. Call `cleanup` as
   soon as the consumer process has read its value.
5. **Fail closed.** A half-formed reference, an unsafe extension, or an
   unreachable account exits nonzero; the tool never degrades.

Run the CLI as:

```bash
op-access.sh vaults [query]
op-access.sh items [query] [vault]
op-access.sh reference <item> <field> [vault]
op-access.sh save <op://vault/item/field> [ext]   # prints the path only
op-access.sh cleanup <temporary-path>
```