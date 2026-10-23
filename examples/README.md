# Examples

One runnable example: `demo-with-mock.sh`.

It runs the whole try-it path against the test mock (`tests/mock/op`) and
prints each command before running it, so a reader can copy the commands
into a terminal and compare. Run it:

```bash
examples/demo-with-mock.sh
```

Expected output (captured from a real run on 2026-10-22):

```text
$ op-access.sh vaults Team
v1	Team Vault
$ op-access.sh items posthog
i1	Posthog Key	API_CREDENTIAL	Team Vault
$ op-access.sh fields "Posthog Key"
password	Project API Key	CONCEALED
note	Usage Note	STRING
$ REF=$(op-access.sh reference "Posthog Key" "Project API Key")
op://Team Vault/Posthog Key/Project API Key
$ PATH_ONLY=$(op-access.sh save "$REF" .txt)
/tmp/op-safe-op.XXXXXX.txt
mode: 600
$ op-access.sh cleanup "$PATH_ONLY"
removed: /tmp/op-safe-op.XXXXXX.txt
```

With the real 1Password desktop app unlocked and integrated with its CLI,
skip the mock line and run the same commands with an account you own.