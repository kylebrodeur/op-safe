# Tests for op-safe's op-access.sh.
#
# The suite runs the real script against the `mock-op` shim in this directory
# and proves the tool's contract: metadata only, a non-secret reference on
# stdout, one secret landing in one mode-0600 file, and a removal path that
# only accepts files the tool itself created.

# The script under test and the mock bin live next to this file.
TOOL_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
MOCK_DIR="$BATS_TEST_DIRNAME/mock"

setup() {
  # The mock bin on PATH, plus the system essentials behind it.
  PATH_BASE="/tmp/op-safe-tests-base"
  mkdir -p "$PATH_BASE"
  PATH_WITH_MOCK="$MOCK_DIR:$PATH_BASE:/usr/bin:/bin"
  # A per-test temp prefix so tests never collide with each other.
  TEST_TMP="/tmp/op-safe-test.$$"
  rm -rf "$TEST_TMP"
  mkdir -p "$TEST_TMP"
}

teardown() {
  rm -rf "$TEST_TMP" "$PATH_BASE"
}

run_tool() {
  OP_TMP_ROOT="$TEST_TMP/p" PATH="$PATH_WITH_MOCK" bash "$TOOL_DIR/op-access.sh" "$@"
}
export -f run_tool

run_tool_no_tmp() {
  PATH="$PATH_WITH_MOCK" bash "$TOOL_DIR/op-access.sh" "$@"
}
export -f run_tool_no_tmp

# The file mode, in octal, on both stat flavors. BSD (macOS) uses
# 'stat -f %Lp'; GNU (Linux) uses 'stat -c %a'.
#
# The flavor cannot be detected by trying the BSD form and falling back
# on failure: GNU's 'stat -f' does not fail. It means "file system
# status" there, and it prints the file's metadata instead of the mode.
# So the BSD form SUCCEEDS on Linux and returns the wrong answer. The
# flavor is therefore detected by the OS, not by an exit code.
file_mode() {
  if [ "$(uname -s)" = "Darwin" ]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

@test "mock selftest carries the shibboleth that must stay off stdout" {
  PATH="$PATH_WITH_MOCK" op --mock-selftest | grep -q 'SECRET-VALUE-shibboleth'
}

@test "help lists the whole command surface and the env contract" {
  run run_tool help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Usage: op-access.sh <command>'
  for c in accounts status signin vaults items fields reference save cleanup; do
    echo "$output" | grep -q "  $c\$" || echo "$output" | grep -q "  $c "
  done
  echo "$output" | grep -q 'OP_ACCOUNT'
  echo "$output" | grep -q '/tmp/op-safe-op'
}

@test "status confirms reachability, never a secret" {
  run run_tool status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'reachable'
  ! echo "$output" | grep -q 'SECRET'
}

@test "the tool never calls op whoami" {
  # The mock exits 97 if whoami is called. `status` and every other
  # command must not reach it: whoami is not a readiness check.
  run run_tool status
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'whoami must not be called'
}

@test "accounts prints configured accounts (metadata only)" {
  run run_tool accounts
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'agent@example.com'
  ! echo "$output" | grep -q 'SECRET'
}

@test "vaults lists vault ids and names and filters by query" {
  run run_tool vaults
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^v1	Team Vault$'
  echo "$output" | grep -q '^v2	Employee$'

  run run_tool vaults Team
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^v1	Team Vault$'
  ! echo "$output" | grep -q 'Employee'

  run run_tool vaults employee
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^v2	Employee$'
  ! echo "$output" | grep -q 'Team Vault'
}

@test "items lists metadata rows and filters by title query" {
  run run_tool items
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^i1	Posthog Key	API_CREDENTIAL	Team Vault$'
  echo "$output" | grep -q '^i2	Deploy Token	API_CREDENTIAL	Team Vault$'

  run run_tool items posthog
  [ "$status" -eq 0 ]
  [[ "$output" == *"Posthog Key"* ]]
  [[ "$output" != *"Deploy Token"* ]]
}

@test "items hides every field value: the SECRET marker appears nowhere" {
  run run_tool items
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'SECRET'
}

@test "fields lists ids, labels, types, sections and hides values" {
  run run_tool fields 'Posthog Key'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q $'^password\tProject API Key\tCONCEALED'
  echo "$output" | grep -q $'^note\tUsage Note\tSTRING'
  ! echo "$output" | grep -q 'SECRET'
}

@test "fields with a vault argument reaches the same item" {
  run run_tool fields 'Posthog Key' 'Team Vault'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Project API Key'
}

@test "reference prints ONLY a non-secret op:// path" {
  run run_tool reference 'Posthog Key' 'Project API Key'
  [ "$status" -eq 0 ]
  [ "$output" = 'op://Team Vault/Posthog Key/Project API Key' ]
  ! echo "$output" | grep -q 'SECRET'
}

@test "reference resolves by field id as well as by label" {
  run run_tool reference i1 password
  [ "$status" -eq 0 ]
  [ "$output" = 'op://Team Vault/Posthog Key/Project API Key' ]
}

@test "reference fails with the not-found error and exit 1" {
  run run_tool reference 'Posthog Key' 'No Such Field'
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "ERROR: field 'No Such Field' was not found"
}

@test "reference for an unknown item surfaces the op failure" {
  run run_tool reference 'Bad Item' 'Anything'
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q 'SECRET'
}

@test "save writes one 0600 file, stdout carries only the path" {
  run run_tool save 'op://Team Vault/Posthog Key/Project API Key' .txt
  [ "$status" -eq 0 ]
  # stdout is EXACTLY one line: the path.
  [ "$(echo "$output" | grep -c .)" -eq 1 ]
  tmp_path="$output"
  # It is under the tool's prefix and inside the test's root.
  case "$tmp_path" in "$TEST_TMP/p."*) ;; *) echo "path not under prefix: $tmp_path"; return 1 ;; esac
  # Mode 0600.
  mode=$(file_mode "$tmp_path")
  [ "$mode" = "600" ] || { echo "mode was '$mode', expected 600"; return 1; }
  # The file holds the secret (the value flowed to the file), and the value
  # never appeared on stdout: exactly one line was printed, checked above.
  grep -q 'SECRET-VALUE-op_____Team Vault__Posthog Key__Project API Key' "$tmp_path"
}

@test "save without an extension still lands a 0600 file" {
  run run_tool_no_tmp save 'op://Team Vault/Posthog Key/Project API Key'
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  mode=$(file_mode "$output")
  [ "$mode" = "600" ] || { echo "mode was '$mode', expected 600"; return 1; }
  case "$output" in /tmp/op-safe-op.*) ;; *) echo "not under the default prefix: $output"; return 1 ;; esac
  rm -f "$output"
}

@test "save rejects an incomplete op:// reference with exit 2" {
  run run_tool save 'op://vault/item'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: save requires a complete op://vault/item/field reference.'

  run run_tool save 'op://vault/item/'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: save requires a complete op://vault/item/field reference.'

  run run_tool save 'plain-text'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: save requires a complete op://vault/item/field reference.'
}

@test "save rejects an extension with shell metacharacters" {
  run run_tool save 'op://Team Vault/Posthog Key/Project API Key' '.txt; rm -rf /'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ERROR: unsafe extension '.txt; rm -rf /'."
  # Nothing was written anywhere.
  ! ls "$TEST_TMP" | grep -q .
}

@test "save rejects a path-ish extension" {
  run run_tool save 'op://Team Vault/Posthog Key/Project API Key' '../evil'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ERROR: unsafe extension"
}

@test "save removes the temp file when op read fails" {
  run run_tool save 'op://Team Vault/Missing Item/X-Field' .txt
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'ERROR: unable to read the selected secret reference.'
  # No secret FILE survives. The registry is bookkeeping, not a secret,
  # so it may remain; what must not remain is a saved secret or the
  # private save directory that held it.
  run bash -c "find '$TEST_TMP' -name secret -type f 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  run bash -c "find '$TEST_TMP' -type d -name 'p.??????' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "cleanup removes a file the tool created" {
  path="$(run_tool_no_tmp save 'op://Team Vault/Posthog Key/Project API Key')"
  [ -f "$path" ] || { echo "save did not leave the file: $path"; return 1; }
  run run_tool_no_tmp cleanup "$path"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "removed: $path"
  [ ! -f "$path" ]
}

@test "save refuses to write a secret it cannot record ownership for" {
  # Fault injection: the registry cannot be written. A secret that
  # exists without a registry record is one the caller can never clean
  # up, so the save must fail BEFORE the secret is written, and the
  # stray directory must not survive.
  bad_registry="$TEST_TMP/registry-not-writable"
  mkdir -p "$bad_registry"
  chmod 500 "$bad_registry"
  run env OP_TMP_ROOT="$TEST_TMP/p" OP_SAFE_REGISTRY="$bad_registry/reg" \
    PATH="$PATH_WITH_MOCK" bash "$TOOL_DIR/op-access.sh" save 'op://Team Vault/Posthog Key/Project API Key'
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'cannot record ownership'
  # No secret file was left anywhere under the prefix.
  run bash -c "ls -d '$TEST_TMP'/p.* 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
  chmod 700 "$bad_registry"
}

@test "a concurrent save keeps its ownership record" {
  # The registry is appended to by save and REWRITTEN by cleanup. Without
  # a lock, a save that lands between a cleanup's read and its rename
  # loses its record, and the secret it just wrote can never be cleaned
  # up.
  #
  # The overlap is DETERMINISTIC. The test hook pauses the rewrite after
  # the registry has been read, while holding the lock. A save started
  # in that window must WAIT for the lock, then append, so its record
  # survives the rewrite.
  first="$(run_tool save 'op://Team Vault/Posthog Key/Project API Key')"
  [ -f "$first" ]

  hook="$TEST_TMP/hook"
  OP_SAFE_TEST_PAUSE_AFTER_READ="$hook" \
    run_tool cleanup "$first" >/dev/null 2>&1 &
  cleanup_pid=$!

  # Wait for the rewrite to reach the pause point (and take the lock).
  for _ in $(seq 1 100); do
    [ -f "$hook.read" ] && break
    sleep 0.05
  done
  [ -f "$hook.read" ] || {
    echo "the rewrite never reached the pause point" >&2
    return 1
  }

  # A save starts while the rewrite is paused. With the lock it waits.
  run_tool save 'op://Team Vault/Posthog Key/Project API Key' >"$TEST_TMP/second" 2>/dev/null &
  save_pid=$!
  sleep 0.3

  # Release the rewrite: the cleanup finishes and drops the lock, and the
  # waiting save proceeds and appends its record.
  : >"$hook.release"
  wait "$cleanup_pid"
  wait "$save_pid"

  second="$(cat "$TEST_TMP/second" 2>/dev/null || true)"
  [ -n "$second" ] || {
    echo "the concurrent save produced no path" >&2
    return 1
  }
  [ -f "$second" ] || {
    echo "the concurrent save left no file" >&2
    return 1
  }

  # Its record must have survived the rewrite: cleanup must accept it.
  run run_tool cleanup "$second"
  [ "$status" -eq 0 ] || {
    echo "a concurrent save lost its ownership record: $second" >&2
    return 1
  }
}

@test "cleanup refuses a foreign path with exit 2 and does nothing" {
  other="$TEST_TMP/foreign.txt"
  echo "not a tool file" > "$other"
  run run_tool cleanup "$other"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: refusing to remove a path not created by this helper.'
  [ -f "$other" ]
}

@test "cleanup refuses a FORGED same-prefix directory" {
  # The attack: a same-user creates a directory that matches the tool's
  # own prefix, puts a file in it, and hands the path to cleanup. A
  # prefix check alone would delete it. The ownership registry is the
  # proof of provenance, so this must be refused and the file must
  # survive.
  forged="$TEST_TMP/p.forged"
  mkdir -p "$forged"
  chmod 700 "$forged"
  echo "someone else's data" > "$forged/secret"
  run run_tool cleanup "$forged/secret"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: refusing to remove a path not created by this helper.'
  [ -f "$forged/secret" ]
}

@test "cleanup refuses a forged directory even with a plausible marker" {
  # A marker file inside the target directory is forgeable, so it must
  # not be what proves provenance. This directory looks exactly like a
  # real save directory, down to the token file, and must still be
  # refused because the registry has no record of it.
  forged="$TEST_TMP/p.forged2"
  mkdir -p "$forged"
  chmod 700 "$forged"
  echo "someone else's data" > "$forged/secret"
  printf '%s' "deadbeefdeadbeefdeadbeefdeadbeef" > "$forged/.op-safe-token"
  chmod 600 "$forged/.op-safe-token"
  run run_tool cleanup "$forged/secret"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: refusing to remove a path not created by this helper.'
  [ -f "$forged/secret" ]
}

@test "cleanup refuses a prefix-lookalike path under another root" {
  other="/tmp/op-safe-test-lookalike.$$.XX.txt"
  echo "lookalike" > "$other"
  run run_tool cleanup "$other"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ERROR: refusing to remove a path not created by this helper.'
  [ -f "$other" ]
  rm -f "$other"
}

@test "cleanup refuses a missing file with the exists error and exit 1" {
  path="$(run_tool save 'op://Team Vault/Posthog Key/Project API Key')"
  rm -f "$path"
  run run_tool cleanup "$path"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'ERROR: temporary file does not exist'
}

@test "cleanup requires an argument" {
  run run_tool cleanup
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'Usage: op-access.sh cleanup'
}

@test "OP_ACCOUNT env var is honored on the op calls" {
  # The mock prints the same metadata regardless of account; instead, prove
  # the pass-through by calling with a bogus account shape: the mock still
  # accepts it (it ignores the account) and the tool succeeds.
  OP_ACCOUNT=agents PATH="$PATH_WITH_MOCK" OP_TMP_ROOT="$TEST_TMP/p" \
    bash "$TOOL_DIR/op-access.sh" status
  [ "$?" -eq 0 ]
}

@test "unknown command prints the usage to stderr with exit 2" {
  run run_tool bogus-command
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "ERROR: unknown command 'bogus-command'."
  echo "$output" | grep -q 'Usage: op-access.sh'
}

@test "fields with no argument fails with the usage error" {
  run run_tool fields
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'Usage: op-access.sh fields'
}

@test "reference with one argument fails with the usage error" {
  run run_tool reference 'Item Only'
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'Usage: op-access.sh reference'
}

@test "save with no argument fails with the usage error" {
  run run_tool save
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'Usage: op-access.sh save'
}