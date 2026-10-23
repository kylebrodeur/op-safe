<!-- STATUS: VERIFIED 2026-10-22 against op-access.sh + tests/op-access.bats (29 tests passing). The mock-run outputs below were captured from a live run of examples/demo-with-mock.sh. -->
# Quickstart: from nothing to a saved-and-cleaned secret

The numbered path: check the prerequisites, sign in, mint a reference,
save one secret to a private temp file, clean it up, then run the suite.
Every command is copy-pasteable; the two that need your own vault say so.

**What you will have at the end:** a signed-in `op` CLI exercised through
op-safe, one `op://` reference, one 0600 temp file that held a secret and
is gone, and a green test run.

## 0. What this is not

Not a secret store and not a replacement for `op` itself. op-safe is the
narrow, agent-shaped slice on top of the 1Password CLI: metadata, one
reference, one temp file, one cleanup. It never lists values, never
creates or edits items, and never prints a secret.

## 1. Prerequisites

```bash
command -v op && command -v jq && command -v python3 && command -v bash
```

Expected: four paths, no `command not found`. The 1Password desktop app
must be unlocked, with `Settings > Developer > Integrate with 1Password
CLI` enabled.

## 2. Confirm the CLI

```bash
./op-access.sh help
```

```text
Usage: op-access.sh <command> [arguments]

Commands:
  accounts
      List configured 1Password accounts (metadata only).
  ...
```

(The full usage text lists all nine commands, the environment variables,
and worked examples.)

## 3. Sign in and check status

```bash
./op-access.sh signin      # interactive; opens the desktop unlock
./op-access.sh status
```

```text
{"email":"you@example.com","user_uuid":"U1","shorthand":"agents"}
```

If your shorthand is not the `op` CLI default, point the tool at it:

```bash
export OP_ACCOUNT=your-shorthand
```

## 4. Try it without a 1Password account (the mock)

`examples/demo-with-mock.sh` runs the whole flow against the test shim,
so nothing needs a real vault. Output captured from a real run
(2026-10-22):

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

## 5. The real flow with your own vault

The same commands against an account you own. `<vault>`, `<item>`, and
`<field label>` are yours:

```bash
./op-access.sh vaults
./op-access.sh items <query> <vault>
./op-access.sh fields <item> [vault]
REF=$(./op-access.sh reference <item> '<field label>' [vault])
echo "$REF"        # SAFE: a reference is not the value
PATH_ONLY=$(./op-access.sh save "$REF")
```

`PATH_ONLY` is a mode-0600 file that holds the secret value. Never
`echo`, `cat`, or log it; read it in the process that needs it, then:

```bash
./op-access.sh cleanup "$PATH_ONLY"
```

```text
removed: /tmp/op-safe-op.<random>
```

## 6. Run the tests

```bash
tests/run-tests.sh
```

```text
1..29
ok 1 mock selftest carries the shibboleth that must stay off stdout
...
ok 29 save with no argument fails with the usage error
```

The suite needs `bats` (`brew install bats-core`). Without it the runner
exits 3 with the install command; it never fakes a pass.

## Where next

- Day-to-day operation: [how-to.md](how-to.md)
- Every command, flag, and error string: [RUNBOOK.md](RUNBOOK.md)
- The runnable mock walkthrough: [../examples/README.md](../examples/README.md)