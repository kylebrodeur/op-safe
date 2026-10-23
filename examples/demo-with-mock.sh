#!/usr/bin/env bash
# A runnable op-safe walkthrough, executed against the tests/mock shim so it
# runs on a machine without the 1Password app. Every line shown in
# docs/quickstart.md under "Try it without a 1Password account" is captured
# from a real run of this script.
#
#   examples/demo-with-mock.sh
set -uo pipefail
# shellcheck disable=SC2016  # the echo lines SHOW the unexpanded command on purpose
cd "$(dirname "$0")/.." || exit 1
TOOL="$PWD/op-access.sh"

# 1. Put the test mock on PATH. With the real 1Password desktop app unlocked
#    and integrated, skip this line: every command below is the same.
MOCK_BIN="$(cd tests/mock && pwd)"
export PATH="$MOCK_BIN:$PATH"

echo '$ op-access.sh vaults Team'
"$TOOL" vaults Team

echo '$ op-access.sh items posthog'
"$TOOL" items posthog

echo '$ op-access.sh fields "Posthog Key"'
"$TOOL" fields 'Posthog Key'

# shellcheck disable=SC2016  # the echo lines SHOW the unexpanded command on purpose
echo '$ REF=$(op-access.sh reference "Posthog Key" "Project API Key")'
REF="$("$TOOL" reference 'Posthog Key' 'Project API Key')"
echo "$REF"

# shellcheck disable=SC2016  # the echo lines SHOW the unexpanded command on purpose
echo '$ PATH_ONLY=$(op-access.sh save "$REF" .txt)'
PATH_ONLY="$("$TOOL" save "$REF" .txt)"
echo "$PATH_ONLY"

echo "# stat $PATH_ONLY: mode is 0600, the value is inside, stdout never saw it"
if [ "$(uname -s)" = "Darwin" ]; then
  stat -f 'mode: %Lp' "$PATH_ONLY"
else
  stat -c 'mode: %a' "$PATH_ONLY"
fi

# shellcheck disable=SC2016  # the echo line SHOWS the unexpanded command on purpose
echo '$ op-access.sh cleanup "$PATH_ONLY"'
"$TOOL" cleanup "$PATH_ONLY"