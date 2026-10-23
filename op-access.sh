#!/usr/bin/env bash
# op-safe: metadata-first 1Password CLI helper for local agents.
#
# Uses the unlocked 1Password desktop app. Secret values are never printed;
# every list command renders metadata only, `reference` prints a non-secret
# op:// reference, `save` writes one selected reference to a mode-0600 file
# under the tool's own prefix and prints only the path, and `cleanup`
# securely removes a path this tool created and refuses any other.
set -euo pipefail

if [[ -n "${OP_ACCOUNT:-}" ]]; then
  ACCOUNT="$OP_ACCOUNT"
else
  ACCOUNT=""
fi
TMP_ROOT="${OP_TMP_ROOT:-/tmp/op-safe-op}"

export OP_BIOMETRIC_UNLOCK_ENABLED="${OP_BIOMETRIC_UNLOCK_ENABLED:-true}"
umask 077

# The ownership registry. `save` records each file it creates here, with
# an unguessable token, and `cleanup` will only remove a file whose
# record is present AND whose token matches. The registry lives OUTSIDE
# the save directory, so a forged directory (one the tool did not create)
# cannot present a matching token: the registry is the only proof of
# provenance, and a file inside it is the only thing it can prove.
REGISTRY_DIR="${OP_SAFE_REGISTRY:-${TMP_ROOT}.registry}"
REGISTRY_FILE="${REGISTRY_DIR}/owned"

registry_lock() {
  # A portable lock: a lock DIRECTORY, created with mkdir, which is
  # atomic on every POSIX filesystem. The registry is rewritten by
  # `forget` and appended to by `add`, so without a lock a concurrent
  # save between forget's read and its rename would lose its record and
  # strand a secret the caller could never clean up.
  local tries=0
  mkdir -p "$REGISTRY_DIR" 2>/dev/null || return 1
  while ! mkdir "${REGISTRY_DIR}.lock" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 100 ]; then
      echo "ERROR: the ownership registry is locked by another process." >&2
      return 1
    fi
    sleep 0.05
  done
  return 0
}

registry_unlock() {
  rmdir "${REGISTRY_DIR}.lock" 2>/dev/null || true
}

registry_add() {
  # registry_add <path> <token>. Returns non-zero when the record could
  # not be written, so the caller can refuse to proceed.
  registry_lock || return 1
  mkdir -p "$REGISTRY_DIR" 2>/dev/null || { registry_unlock; return 1; }
  chmod 700 "$REGISTRY_DIR" 2>/dev/null || { registry_unlock; return 1; }
  printf '%s\t%s\n' "$1" "$2" >>"$REGISTRY_FILE" 2>/dev/null || {
    registry_unlock
    return 1
  }
  chmod 600 "$REGISTRY_FILE" 2>/dev/null || { registry_unlock; return 1; }
  registry_unlock
  return 0
}

registry_owns() {
  # registry_owns <path> <token-from-the-file> -> 0 when the registry proves it
  local path="$1" token="$2" line
  [[ -f "$REGISTRY_FILE" ]] || return 1
  while IFS=$'\t' read -r line _; do
    [[ "$line" == "$path" ]] || continue
    return 0
  done <"$REGISTRY_FILE"
  return 1
}

registry_token() {
  # The token for a path, or empty when the registry has no record.
  local path="$1" line
  [[ -f "$REGISTRY_FILE" ]] || return 0
  while IFS=$'\t' read -r line token; do
    if [[ "$line" == "$path" ]]; then
      printf '%s' "$token"
      return 0
    fi
  done <"$REGISTRY_FILE"
}

registry_forget() {
  # Drop a path's record once the file is gone. This REWRITES the
  # registry, so it takes the same lock `add` takes: without it, a
  # concurrent save between the read and the rename would lose its
  # record.
  local path="$1" tmp
  [[ -f "$REGISTRY_FILE" ]] || return 0
  registry_lock || return 1
  tmp="$(mktemp "${REGISTRY_FILE}.XXXXXX")"
  while IFS=$'\t' read -r line token; do
    [[ "$line" == "$path" ]] && continue
    printf '%s\t%s\n' "$line" "$token" >>"$tmp"
  done <"$REGISTRY_FILE"
  # TEST HOOK: pause after the registry has been read but before the
  # rewrite, so a test can prove that a concurrent save is not lost.
  # Unset in normal use; the suite sets it and nothing else does.
  if [[ -n "${OP_SAFE_TEST_PAUSE_AFTER_READ:-}" ]]; then
    : >"${OP_SAFE_TEST_PAUSE_AFTER_READ}.read"
    while [[ ! -f "${OP_SAFE_TEST_PAUSE_AFTER_READ}.release" ]]; do
      sleep 0.05
    done
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$REGISTRY_FILE"
  registry_unlock
  return 0
}

account_args() {
  if [[ -n "$ACCOUNT" ]]; then
    printf '%s\n' "--account" "$ACCOUNT"
  fi
}

usage() {
  cat <<'EOF'
Usage: op-access.sh <command> [arguments]

Commands:
  accounts
      List configured 1Password accounts (metadata only).

  status
      Verify that the selected account is signed in.

  signin
      Start interactive desktop/biometric sign-in for the selected account.

  vaults [query]
      List accessible vault IDs and names. Optionally filter by query.

  items [query] [vault]
      List item IDs, titles, categories, and vault names. Optionally filter by
      title query and/or vault name or ID. Values are never shown.

  fields <item-id-or-title> [vault]
      List field IDs, labels, types, and sections for an item. Values are never
      shown. Supplying a vault disambiguates duplicate titles.

  reference <item-id-or-title> <field-id-or-label> [vault]
      Print a non-secret op:// reference for a selected field. This prints the
      reference only, never the field value.

  save <op://vault/item/field> [extension]
      Read a selected secret reference and save it to a mode-0600 temporary
      file under the tool's own prefix. Prints only the temporary path. The
      optional extension must contain letters, numbers, dot, underscore, or
      hyphen.

  cleanup <temporary-path>
      Securely remove a file previously created by `save` under this tool's
      own prefix. Refuses any other path.

Environment:
  OP_ACCOUNT          1Password account shorthand (default: none).
  OP_TMP_ROOT         Temporary file prefix (default: /tmp/op-safe-op).
  OP_BIOMETRIC_UNLOCK_ENABLED  Set to true by default so the desktop app
                      integration is used when it is available.

Examples:
  op-access.sh signin
  op-access.sh vaults support
  op-access.sh items posthog
  op-access.sh fields cvz6iqdmin4gjexqdbzj2ydvuq
  REF=$(op-access.sh reference ITEM_ID 'project API key' 'Employee')
  PATH_ONLY=$(op-access.sh save "$REF" .txt)
  op-access.sh cleanup "$PATH_ONLY"

The contract: metadata only. `op-access.sh` never prints a secret value;
the one path a value can flow through ends in a mode-0600 file that only
`cleanup` may remove.
EOF
}

need_op() {
  command -v op >/dev/null 2>&1 || {
    echo "ERROR: 1Password CLI ('op') is not installed." >&2
    exit 127
  }
}

need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq is required." >&2
    exit 127
  }
}

need_session() {
  # `op whoami` can report "not signed in" under desktop-integration sessions
  # that still successfully serve items. Probe with a lightweight metadata
  # call instead; if that also fails, surface the sign-in instructions.
  local args=("account" "get")
  if [[ -n "$ACCOUNT" ]]; then
    args+=(--account "$ACCOUNT")
  fi
  if ! op "${args[@]}" >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: 1Password account '${ACCOUNT:-<default>}' is not reachable.
Open and unlock the 1Password desktop app, enable Settings > Developer >
Integrate with 1Password CLI, then run:
  op-access.sh signin
EOF
    exit 1
  fi
}

# Unwrap an op JSON payload: most `op` calls print an object, but `item list`
# prints an array, and a jq filter written for the other shape would index the
# wrong side. One place decides it.
json_unwrap() {
  jq 'if type == "array" then .[] else . end'
}

json_items() {
  local query="${1:-}"
  local vault="${2:-}"
  local args=(item list --format=json)
  if [[ -n "$vault" ]]; then
    args+=(--vault "$vault")
  fi
  if [[ -n "$ACCOUNT" ]]; then
    args+=(--account "$ACCOUNT")
  fi
  op "${args[@]}" | jq --arg q "$query" '
    map(
      select(
        ($q == "")
        or ((.title // "") | ascii_downcase | contains($q | ascii_downcase))
      )
    )
  '
}

resolve_item() {
  local item="$1"
  local vault="${2:-}"
  local args=(item get "$item" --format=json)
  if [[ -n "$vault" ]]; then
    args+=(--vault "$vault")
  fi
  if [[ -n "$ACCOUNT" ]]; then
    args+=(--account "$ACCOUNT")
  fi
  op "${args[@]}"
}

command="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

need_op

case "$command" in
  help|-h|--help)
    usage
    ;;

  accounts)
    op account list
    ;;

  status)
    # NEVER `op whoami`: it is not a readiness check, and under the
    # desktop integration it can report "not signed in" for a session
    # that still serves items. Probe with a lightweight metadata call.
    need_session
    echo "OK: the 1Password account '${ACCOUNT:-<default>}' is reachable."
    ;;

  signin)
    if [[ -n "$ACCOUNT" ]]; then
      op signin --account "$ACCOUNT"
    else
      op signin
    fi
    ;;

  vaults)
    need_jq
    need_session
    query="${1:-}"
    vargs=(vault list --format=json)
    if [[ -n "$ACCOUNT" ]]; then
      vargs+=(--account "$ACCOUNT")
    fi
    op "${vargs[@]}" | json_unwrap |
      jq -r --arg q "$query" '
        select(
          ($q == "")
          or ((.name // "") | ascii_downcase | contains($q | ascii_downcase))
        )
        | [.id, .name]
        | @tsv
      '
    ;;

  items)
    need_jq
    need_session
    query="${1:-}"
    vault="${2:-}"
    json_items "$query" "$vault" |
      json_unwrap |
      jq -r '[.id, .title, .category, (.vault.name // "")] | @tsv'
    ;;

  fields)
    need_jq
    need_session
    item="${1:?Usage: op-access.sh fields <item-id-or-title> [vault]}"
    vault="${2:-}"
    resolve_item "$item" "$vault" |
      json_unwrap |
      jq -r '
        [(.fields // [])[]]
        | .[]
        | [
            .id,
            .label,
            .type,
            (.section.label // "")
          ]
        | @tsv
      '
    ;;

  reference)
    need_jq
    need_session
    item="${1:?Usage: op-access.sh reference <item-id-or-title> <field-id-or-label> [vault]}"
    field="${2:?Usage: op-access.sh reference <item-id-or-title> <field-id-or-label> [vault]}"
    vault="${3:-}"

    item_json="$(resolve_item "$item" "$vault")"
    item_title="$(echo "$item_json" | json_unwrap | jq -r '.title // ""')"
    vault_title="$(echo "$item_json" | json_unwrap | jq -r '.vault.name // ""')"
    field_label="$(echo "$item_json" | jq -r --arg f "$field" '
      [(.fields // [])[] | select(.id == $f or .label == $f) | .label]
      | first
      // empty
    ')"

    if [[ -z "$field_label" ]]; then
      echo "ERROR: field '$field' was not found. Run the fields command first." >&2
      exit 1
    fi

    # Build the op:// path with spaces preserved: the 1Password CLI rejects
    # percent-encoding in secret references but accepts literal spaces.
    python3 - "$vault_title" "$item_title" "$field_label" <<'PY'
import sys
ref = "op://" + "/".join(sys.argv[1:])
assert sys.argv[1] and sys.argv[2] and sys.argv[3], "empty op:// component"
print(ref)
PY
    ;;

  save)
    need_session
    reference="${1:?Usage: op-access.sh save <op://vault/item/field> [extension]}"
    extension="${2:-}"

    [[ "$reference" == op://*/*/* ]] || {
      echo "ERROR: save requires a complete op://vault/item/field reference." >&2
      exit 2
    }
    [[ "$extension" =~ ^[A-Za-z0-9._-]*$ ]] || {
      echo "ERROR: unsafe extension '$extension'." >&2
      exit 2
    }

    # `save` also refuses a half-formed reference whose components are empty:
    # `op://vault/item/field` must carry three non-empty parts.
    trimmed="${reference#op://}"
    IFS='/' read -r ref_vault ref_item ref_field <<< "$trimmed"
    [[ -n "$ref_vault" && -n "$ref_item" && -n "$ref_field" ]] || {
      echo "ERROR: save requires a complete op://vault/item/field reference." >&2
      exit 2
    }

    # Every save lands in its OWN private directory under the root, and
    # the path is recorded in the ownership registry with an unguessable
    # token. The registry is the proof of provenance: a forged directory
    # (one the tool did not create) has no record, so cleanup refuses it.
    save_dir="$(mktemp -d "${TMP_ROOT}.XXXXXX")"
    chmod 700 "$save_dir"
    tmp_path="${save_dir}/secret${extension}"

    # Register ownership BEFORE the secret is written. If the registry
    # cannot be written, the save fails and the (empty) directory is
    # removed: a secret that exists without a registry record would be
    # one the caller can never clean up.
    token="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    if ! registry_add "$tmp_path" "$token"; then
      rm -rf "$save_dir"
      echo "ERROR: cannot record ownership; refusing to write a secret that cannot be cleaned up." >&2
      exit 1
    fi
    printf '%s' "$token" >"${save_dir}/.op-safe-token"
    chmod 600 "${save_dir}/.op-safe-token"

    ( umask 077 && : >"$tmp_path" )
    chmod 600 "$tmp_path"
    read_args=("read" "$reference")
    if [[ -n "$ACCOUNT" ]]; then
      read_args+=(--account "$ACCOUNT")
    fi
    if ! op "${read_args[@]}" >"$tmp_path"; then
      rm -rf "$save_dir"
      registry_forget "$tmp_path"
      echo "ERROR: unable to read the selected secret reference." >&2
      exit 1
    fi

    # Print only the path. Never print or inspect the saved secret value.
    # The file survives this process: the caller reads it, then hands the
    # path to `cleanup`, the only command that may remove it.
    printf '%s\n' "$tmp_path"
    ;;

  cleanup)
    path="${1:?Usage: op-access.sh cleanup <temporary-path>}"
    [[ -f "$path" ]] || {
      echo "ERROR: temporary file does not exist: $path" >&2
      exit 1
    }
    # Provenance is proved by the ownership registry, not by the name.
    # A file the tool did not create has no registry record, and a
    # forged directory cannot present the unguessable token that a real
    # save directory carries beside its secret.
    save_dir="$(dirname -- "$path")"
    case "$save_dir" in
      "${TMP_ROOT}".*) ;;
      *)
        echo "ERROR: refusing to remove a path not created by this helper." >&2
        exit 2
        ;;
    esac
    expected_token="$(registry_token "$path")"
    [[ -n "$expected_token" ]] || {
      echo "ERROR: refusing to remove a path not created by this helper." >&2
      exit 2
    }
    token_file="${save_dir}/.op-safe-token"
    [[ -f "$token_file" ]] || {
      echo "ERROR: refusing to remove a path not created by this helper." >&2
      exit 2
    }
    file_token="$(cat "$token_file")"
    [[ -n "$file_token" && "$file_token" == "$expected_token" ]] || {
      echo "ERROR: refusing to remove a path not created by this helper." >&2
      exit 2
    }
    if command -v shred >/dev/null 2>&1; then
      shred -u "$path"
    else
      rm -f "$path"
    fi
    rm -f "$token_file"
    registry_forget "$path"
    # The private directory goes with the file, and only after the file
    # is gone: a leftover empty directory is not a secret.
    rmdir -- "$save_dir" 2>/dev/null || true
    echo "removed: $path"
    ;;

  *)
    echo "ERROR: unknown command '$command'." >&2
    usage >&2
    exit 2
    ;;
esac