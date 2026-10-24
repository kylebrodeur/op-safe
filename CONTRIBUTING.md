# Contributing to op-safe

The bar: one change at a time, tests in the same change, docs that pass
the family harness.

## Setup

```bash
git clone <this repo>
cd op-safe
command -v op jq python3 bash   # the runtime prerequisites
brew install bats-core          # the test runner (or your system's equivalent)
```

No other dependencies. The tests never touch a real 1Password account:
they run `op-access.sh` against the shim in `tests/mock/`.

## Run the tests

```bash
tests/run-tests.sh
```

Expected output:

```text
1..34
ok 1 mock selftest carries the shibboleth that must stay off stdout
...
ok 29 save with no argument fails with the usage error
```

A change to `op-access.sh` with no matching test in
`tests/op-access.bats` is an incomplete change.

## Run the docs harness

The family harness is in the private system repo and runs against this
checkout. It is MAINTAINER-ONLY: it is not part of this repo's public
test command, and a public contributor does not have it.

```bash
# In the private family system repo, against this checkout:
python3 tools/verify-system.py --repo <path-to-this-checkout>
```

Every line should read `PASS`. The checks include the prose gates: no em
or en dashes, none of the four banned wording habits (the slop gate lists
them), and no personal identifiers in any tracked markdown.

**What a public contributor runs instead** is the repo's own commands,
which are the ones CI runs:

```bash
tests/run-tests.sh
```

That is the Bats suite, and its output is TAP: a `1..34` plan and one
`ok` line per test. It does not print `PASS` lines, because it is not
the family harness.

## Open a change

1. One behavior change per branch or patch series; a value-flow change
   (anything touching `items`, `fields`, `reference`, `save`, or
   `cleanup`) carries its test and its RUNBOOK row together.
2. Keep `AGENTS.md` the boundary of record: if a rule changes, the rule
   text changes in the same commit.
3. The prose in docs follows `docs/DOC-STANDARD.md` in the system repo:
   real commands with expected output, errors carrying their fix, and a
   check date on factual claims.

## What will not be accepted

- A code path that prints, logs, or inspects a secret value.
- A loosening of the `cleanup` prefix check.
- A new default that names a specific account, project, or consumer.
- An error string that appears in code without appearing (with its fix)
  in `docs/RUNBOOK.md`.