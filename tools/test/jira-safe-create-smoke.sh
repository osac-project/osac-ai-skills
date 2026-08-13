#!/usr/bin/env bash
# Smoke test for tools/jira-safe-create.sh — run from a checkout of this repo:
#   bash tools/test/jira-safe-create-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE="${SCRIPT_DIR}/../jira-safe-create.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SOURCE" ]] || fail "missing $SOURCE"

# Regression: add_temp must run in the parent shell after $(new_temp ...).
# If temps are not registered, EXIT trap does not remove them.
test_registered_temp_cleaned_on_exit() {
  local path
  path=$(
    # shellcheck source=/dev/null
    source "$SOURCE"
    local f
    f=$(new_temp smoke-test)
    add_temp "$f"
    echo "$f"
  )
  [[ -n "$path" ]] || fail "new_temp returned empty path"
  [[ ! -f "$path" ]] || fail "registered temp not removed on EXIT: $path"
  pass "registered temp cleaned on EXIT"
}

# Unregistered temp (no add_temp) is intentionally not cleaned — documents the subshell footgun.
test_unregistered_temp_leaks() {
  local path
  path=$(
    # shellcheck source=/dev/null
    source "$SOURCE"
    new_temp smoke-leak
  )
  [[ -f "$path" ]] || fail "expected unregistered temp to exist for leak demo"
  rm -f "$path"
  pass "unregistered temp not tracked (add_temp required in parent shell)"
}

test_double_source_idempotent() {
  local dir marker path
  dir=$(mktemp -d)
  marker="${dir}/prior-trap"
  path=$(
    trap "touch '${marker}'" EXIT
    # shellcheck source=/dev/null
    source "$SOURCE"
    local f
    f=$(new_temp smoke-double)
    add_temp "$f"
    # JIRA_SAFE_CREATE_LOADED must no-op the second source — state preserved.
    # shellcheck source=/dev/null
    source "$SOURCE"
    echo "$f"
  )
  [[ -n "$path" ]] || fail "new_temp returned empty path"
  [[ ! -f "$path" ]] || fail "registered temp leaked after double source: $path"
  [[ -f "$marker" ]] || fail "prior EXIT trap lost after double source"
  rm -rf "$dir"
  pass "double source preserves registered temps and prior EXIT trap"
}

# Prior EXIT trap must observe the status that triggered exit, not rm's status.
test_prior_trap_sees_original_exit_status() {
  local dir status_file got
  dir=$(mktemp -d)
  status_file="${dir}/status"
  (
    # Expand status_file at trap-set time; keep $? deferred until EXIT fires.
    trap "printf '%s\n' \"\$?\" >\"${status_file}\"" EXIT
    # shellcheck source=/dev/null
    source "$SOURCE"
    local f
    f=$(new_temp smoke-status)
    add_temp "$f"
    exit 23
  ) || true
  [[ -f "$status_file" ]] || fail "prior EXIT trap did not write status file"
  got=$(cat "$status_file")
  [[ "$got" == "23" ]] || fail "prior EXIT trap saw \$?=$got, expected 23"
  rm -rf "$dir"
  pass "prior EXIT trap observes original exit status (23)"
}

# Caller EXIT trap registered before source must still run after temp cleanup.
test_preserves_preexisting_exit_trap() {
  local dir marker path
  dir=$(mktemp -d)
  marker="${dir}/prior-trap"
  path=$(
    trap "touch '${marker}'" EXIT
    # shellcheck source=/dev/null
    source "$SOURCE"
    local f
    f=$(new_temp smoke-prior)
    add_temp "$f"
    echo "$f"
  )
  [[ -n "$path" ]] || fail "new_temp returned empty path"
  [[ ! -f "$path" ]] || fail "registered temp not removed on EXIT: $path"
  [[ -f "$marker" ]] || fail "pre-existing EXIT trap did not run"
  rm -rf "$dir"
  pass "pre-existing EXIT trap preserved and runs after cleanup"
}

# Caller EXIT trap registered after source is re-wrapped on add_temp.
test_later_registered_exit_trap_composed() {
  local dir marker path
  dir=$(mktemp -d)
  marker="${dir}/later-trap"
  path=$(
    # shellcheck source=/dev/null
    source "$SOURCE"
    trap "touch '${marker}'" EXIT
    local f
    f=$(new_temp smoke-later)
    add_temp "$f"
    echo "$f"
  )
  [[ -n "$path" ]] || fail "new_temp returned empty path"
  [[ ! -f "$path" ]] || fail "registered temp not removed after later trap: $path"
  [[ -f "$marker" ]] || fail "later-registered EXIT trap did not run"
  rm -rf "$dir"
  pass "later-registered EXIT trap composed via add_temp rewrap"
}

# Sourcing must not clobber a caller's TEMP_FILES array.
test_preserves_caller_temp_files_array() {
  (
    TEMP_FILES=(caller.tmp)
    # shellcheck source=/dev/null
    source "$SOURCE"
    [[ ${#TEMP_FILES[@]} -eq 1 ]] || fail "caller TEMP_FILES length changed: ${#TEMP_FILES[@]}"
    [[ "${TEMP_FILES[0]}" == "caller.tmp" ]] || fail "caller TEMP_FILES clobbered: ${TEMP_FILES[*]-}"
  ) || fail "caller TEMP_FILES not preserved"
  pass "caller TEMP_FILES array preserved across source"
}

test_registered_temp_cleaned_on_exit
test_unregistered_temp_leaks
test_preserves_preexisting_exit_trap
test_later_registered_exit_trap_composed
test_preserves_caller_temp_files_array
test_double_source_idempotent
test_prior_trap_sees_original_exit_status

echo "All jira-safe-create smoke tests passed."
