#!/usr/bin/env bash
# Run the op-safe test suite.
#
# The suite is `bats` (`tests/op-access.bats`). When bats is not installed
# the runner reports a loud skip naming the install command; it never
# reports a fake pass.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v bats >/dev/null 2>&1; then
  exec bats tests/op-access.bats
fi

echo "SKIP: bats is not installed; install it with 'brew install bats-core' (or the package manager of your system) and re-run." >&2
exit 3