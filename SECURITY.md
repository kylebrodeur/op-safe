# Security policy

## Supported versions

One release line is supported at a time: the latest tag on the default
branch. Older tags receive no security patches; upgrade before reporting
a version-specific issue.

## Reporting a vulnerability

Open a GitHub security advisory on this repository ("Report a
vulnerability" under the Security tab). Do not open a public issue for a
security problem: the advisory keeps it out of search until it is fixed.

Include:

- the affected command(s) and, where known, the code path in
  `op-access.sh`
- the exact command line that triggers it
- the impact you believe it has, ideally with a reproduction against the
  test shim in `tests/mock/`

## What is in scope

- any path that could print, log, or otherwise expose a secret value on
  stdout, stderr, or a debug stream
- `cleanup` removal bypasses: any input that makes the tool remove a file
  outside its own temp prefix
- temp-file handling defects in `save`: a file left world-readable, an
  unsafe extension reaching the filesystem, a predictable or reused temp
  path
- argument-injection through item, field, vault, or extension inputs into
  the `op` invocations

## What is out of scope

- the 1Password CLI and desktop app themselves: report their defects to
  1Password
- a consumer script that echoes the saved temp file to itself: the tool
  cannot stop a caller from printing the file it was handed
- resource exhaustion in `jq` filters beyond the obvious: this is a local
  tool that already runs on the caller's machine

## Handling

Reports are acknowledged within a week. Fixes land with a test in
`tests/op-access.bats` that reproduces the report, and the advisory is
published when the fix is tagged.