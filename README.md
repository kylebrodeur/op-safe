# op-safe

A metadata-first 1Password CLI helper for local agents: list accounts,
vaults, items, and fields without ever printing a secret value, mint a
non-secret `op://` reference for one field, save exactly one selected
secret into a mode-0600 temp file, and clean it up afterwards.

One shell script, `op-access.sh`. Its contract is the point:

- `accounts`, `status`, `signin`, `vaults`, `items`, `fields` print
  metadata only. No field value ever reaches stdout.
- `reference` prints the non-secret `op://vault/item/field` string, so an
  agent can hold a pointer instead of a value.
- `save` reads one `op://` reference and writes it to a mode-0600 file
  under the tool's own `/tmp/op-safe-op` prefix. It prints the path and
  nothing else.
- `cleanup` securely removes a file that `save` created and refuses to
  remove anything else.

Read [docs/quickstart.md](docs/quickstart.md) first: it is the numbered
path from nothing to a saved-and-cleaned secret.

## Family

This kit is a member of the AI Engineering Control Plane (AI ECP)
family: independent, single-purpose repos. Siblings:

- [ecp-toolkit](https://github.com/kylebrodeur/ecp-toolkit) (the `ecp`
  control-plane CLI).
- [repo-guards](https://github.com/kylebrodeur/repo-guards) (the `guv`
  repo-discipline gates).
- [actions-runner](https://github.com/kylebrodeur/actions-runner) (the
  `arun` local agent-pipeline runner).
- [agent-workspace-kit](https://github.com/kylebrodeur/agent-workspace-kit)
  (the manifest-driven role launcher for multi-agent teams).
- [docs-policy-kit](https://github.com/kylebrodeur/docs-policy-kit) (the
  `docpol` documentation policy engine).
- [op-safe](https://github.com/kylebrodeur/op-safe) (the `op://` secrets
  reference resolution).
- [anti-slop-kit](https://github.com/kylebrodeur/anti-slop-kit) (the
  vendored neutral lint policy).

## Install

```bash
# needs: bash, the 1Password CLI (op), jq, and python3 for the reference build
# from a checkout:
./op-access.sh help
```

The 1Password desktop app must be unlocked, with `Settings > Developer >
Integrate with 1Password CLI` enabled; `op-access.sh signin` starts that
sign-in when needed.

## In the family

op-safe is the secrets kit of the AI Engineering Control Plane (AI ECP)
family, catalogued in the family catalog (in the private
control-plane repo) alongside its siblings:
[repo-guards](https://github.com/kylebrodeur/repo-guards) (governance),
[actions-runner](https://github.com/kylebrodeur/actions-runner) (agent
pipelines),
[agent-workspace-kit](https://github.com/kylebrodeur/agent-workspace-kit)
(agent teams),
[docs-policy-kit](https://github.com/kylebrodeur/docs-policy-kit) (docs and
publication), and
[ecp-toolkit](https://github.com/kylebrodeur/ecp-toolkit) (the control
plane). [llms.txt](llms.txt) is the map of this repo's docs for agents.

Run the tests with `tests/run-tests.sh` (check date: 2026-10-22, 29
passing).