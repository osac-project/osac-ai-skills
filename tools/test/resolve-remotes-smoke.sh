#!/usr/bin/env bash
# Smoke test for tools/resolve-remotes.sh — run from a checkout of this repo:
#   bash tools/test/resolve-remotes-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="${SCRIPT_DIR}/../resolve-remotes.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"
[[ -x "$SCRIPT" ]] || fail "$SCRIPT is not executable"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

make_repo() {
  local dir="$TMPDIR_ROOT/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" -q
  echo "$dir"
}

test_standard_bootstrap_naming() {
  local repo
  repo=$(make_repo "standard")
  git -C "$repo" remote add origin "https://github.com/osac-project/standard.git"
  git -C "$repo" remote add fork "git@github.com:dev/standard.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "expected PUSH_REMOTE=fork, got: $out"
  pass "standard bootstrap naming (origin=upstream, fork=push)"
}

test_reversed_naming() {
  local repo
  repo=$(make_repo "reversed")
  git -C "$repo" remote add origin "git@github.com:dev/reversed.git"
  git -C "$repo" remote add upstream "https://github.com/osac-project/reversed.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=upstream" || fail "expected UPSTREAM_REMOTE=upstream, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=origin" || fail "expected PUSH_REMOTE=origin, got: $out"
  pass "reversed naming (origin=fork, upstream=upstream)"
}

test_no_upstream() {
  local repo
  repo=$(make_repo "noupstream")
  git -C "$repo" remote add myremote "git@github.com:dev/noupstream.git"
  local rc=0
  "$SCRIPT" "$repo" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]] || fail "expected exit code 1 when no upstream remote, got $rc"
  pass "exit code 1 when no upstream remote"
}

test_read_only_clone() {
  local repo
  repo=$(make_repo "readonly")
  git -C "$repo" remote add origin "https://github.com/osac-project/readonly.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=" || fail "expected PUSH_REMOTE= in output, got: $out"
  eval "$out"
  [[ -z "$PUSH_REMOTE" ]] || fail "expected empty PUSH_REMOTE after eval, got: $PUSH_REMOTE"
  pass "read-only clone (no push remote)"
}

test_custom_org() {
  local repo
  repo=$(make_repo "customorg")
  git -C "$repo" remote add origin "https://github.com/my-org/customorg.git"
  local out
  out=$("$SCRIPT" --org my-org "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  pass "custom org via --org flag"
}

test_print_mode() {
  local repo
  repo=$(make_repo "printmode")
  git -C "$repo" remote add origin "https://github.com/osac-project/printmode.git"
  git -C "$repo" remote add fork "git@github.com:dev/printmode.git"
  local out
  out=$("$SCRIPT" --print "$repo")
  echo "$out" | grep -q "Repository:" || fail "expected Repository: in print output"
  echo "$out" | grep -q "Upstream remote:" || fail "expected Upstream remote: in print output"
  echo "$out" | grep -q "Push remote:" || fail "expected Push remote: in print output"
  pass "print mode output"
}

test_idempotent() {
  local repo
  repo=$(make_repo "idempotent")
  git -C "$repo" remote add origin "https://github.com/osac-project/idempotent.git"
  git -C "$repo" remote add fork "git@github.com:dev/idempotent.git"
  local out1 out2
  out1=$("$SCRIPT" "$repo")
  out2=$("$SCRIPT" "$repo")
  [[ "$out1" == "$out2" ]] || fail "non-idempotent output: '$out1' vs '$out2'"
  pass "idempotent (two runs produce same output)"
}

test_not_a_repo() {
  local dir="$TMPDIR_ROOT/not-a-repo"
  mkdir -p "$dir"
  local rc=0
  "$SCRIPT" "$dir" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || fail "expected exit code 2 for non-repo directory, got $rc"
  pass "exit code 2 for non-git directory"
}

test_eval_integration() {
  local repo
  repo=$(make_repo "evaltest")
  git -C "$repo" remote add upstream "https://github.com/osac-project/evaltest.git"
  git -C "$repo" remote add origin "git@github.com:dev/evaltest.git"
  eval "$("$SCRIPT" "$repo")"
  [[ "$UPSTREAM_REMOTE" == "upstream" ]] || fail "eval: UPSTREAM_REMOTE=$UPSTREAM_REMOTE, expected upstream"
  [[ "$PUSH_REMOTE" == "origin" ]] || fail "eval: PUSH_REMOTE=$PUSH_REMOTE, expected origin"
  pass "eval integration (variables set in calling shell)"
}

test_worktree() {
  local repo
  repo=$(make_repo "worktree-main")
  git -C "$repo" remote add origin "https://github.com/osac-project/worktree-main.git"
  git -C "$repo" remote add fork "git@github.com:dev/worktree-main.git"
  local wt="$TMPDIR_ROOT/worktree-fix"
  git -C "$repo" worktree add "$wt" -b fix-branch -q
  local out
  out=$("$SCRIPT" "$wt")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "worktree: expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "worktree: expected PUSH_REMOTE=fork, got: $out"
  git -C "$repo" worktree remove "$wt" 2>/dev/null
  pass "worktree (repo name resolved from main repo, not worktree dir)"
}

test_directory_name_mismatch() {
  local repo
  repo=$(make_repo "osac-docs")
  git -C "$repo" remote add origin "https://github.com/osac-project/docs.git"
  git -C "$repo" remote add fork "git@github.com:dev/docs.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "expected PUSH_REMOTE=fork, got: $out"
  local print_out
  print_out=$("$SCRIPT" --print "$repo")
  echo "$print_out" | grep -q "Repository:.*docs" || fail "expected repo name 'docs' from URL, got: $print_out"
  pass "directory name mismatch (osac-docs dir, docs repo)"
}

test_prefer_fork_remote() {
  local repo
  repo=$(make_repo "preferfork")
  git -C "$repo" remote add origin "https://github.com/osac-project/preferfork.git"
  git -C "$repo" remote add colleague "git@github.com:colleague/preferfork.git"
  git -C "$repo" remote add fork "git@github.com:dev/preferfork.git"
  local out
  out=$("$SCRIPT" "$repo" 2>/dev/null)
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "expected PUSH_REMOTE=fork when 'fork' remote exists, got: $out"
  pass "prefer 'fork' remote over other push candidates"
}

test_explicit_push_remote() {
  local repo
  repo=$(make_repo "explicit-push")
  git -C "$repo" remote add origin "https://github.com/osac-project/explicit-push.git"
  git -C "$repo" remote add colleague "git@github.com:colleague/explicit-push.git"
  git -C "$repo" remote add myfork "git@github.com:dev/explicit-push.git"
  local out
  out=$("$SCRIPT" --push-remote myfork "$repo" 2>/dev/null)
  echo "$out" | grep -q "PUSH_REMOTE=myfork" || fail "expected PUSH_REMOTE=myfork with --push-remote, got: $out"
  pass "--push-remote selects explicit push remote"
}

test_explicit_push_remote_print() {
  local repo
  repo=$(make_repo "explicit-push-print")
  git -C "$repo" remote add origin "https://github.com/osac-project/explicit-push-print.git"
  git -C "$repo" remote add colleague "git@github.com:colleague/explicit-push-print.git"
  git -C "$repo" remote add myfork "git@github.com:dev/explicit-push-print.git"
  local out
  out=$("$SCRIPT" --push-remote myfork --print "$repo" 2>/dev/null)
  echo "$out" | grep -q "Push remote:.*myfork" || fail "expected 'Push remote: myfork' in print output, got: $out"
  pass "--push-remote works with --print mode"
}

test_explicit_push_remote_invalid() {
  local repo
  repo=$(make_repo "explicit-push-invalid")
  git -C "$repo" remote add origin "https://github.com/osac-project/explicit-push-invalid.git"
  local rc=0
  "$SCRIPT" --push-remote nonexistent "$repo" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || fail "expected exit code 2 for invalid --push-remote, got $rc"
  pass "--push-remote exits 2 for nonexistent remote"
}

# Triangular clone: single remote fetches upstream, pushes to a fork via pushurl.
test_triangular_clone_pushurl() {
  local repo
  repo=$(make_repo "triangular")
  git -C "$repo" remote add origin "https://github.com/osac-project/triangular.git"
  git -C "$repo" remote set-url --push origin "git@github.com:dev/triangular.git"
  local out
  out=$("$SCRIPT" "$repo")
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "triangular: expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=origin" || fail "triangular: expected PUSH_REMOTE=origin (same remote via pushurl), got: $out"
  pass "triangular clone (fetch upstream, pushurl fork → PUSH_REMOTE=origin)"
}

# Remote whose effective push URL is upstream must not be a push candidate.
test_pushurl_to_upstream_excluded() {
  local repo
  repo=$(make_repo "pushurl-upstream")
  git -C "$repo" remote add origin "https://github.com/osac-project/pushurl-upstream.git"
  git -C "$repo" remote add colleague "git@github.com:colleague/pushurl-upstream.git"
  git -C "$repo" remote set-url --push colleague "https://github.com/osac-project/pushurl-upstream.git"
  git -C "$repo" remote add fork "git@github.com:dev/pushurl-upstream.git"
  local out
  out=$("$SCRIPT" "$repo" 2>/dev/null)
  echo "$out" | grep -q "UPSTREAM_REMOTE=origin" || fail "expected UPSTREAM_REMOTE=origin, got: $out"
  echo "$out" | grep -q "PUSH_REMOTE=fork" || fail "expected PUSH_REMOTE=fork (colleague pushurl is upstream), got: $out"
  pass "pushurl-to-upstream remote excluded from push candidates"
}

test_triangular_clone_print_shows_push_url() {
  local repo
  repo=$(make_repo "triangular-print")
  git -C "$repo" remote add origin "https://github.com/osac-project/triangular-print.git"
  git -C "$repo" remote set-url --push origin "git@github.com:dev/triangular-print.git"
  local out
  out=$("$SCRIPT" --print "$repo")
  echo "$out" | grep -q "Push remote:.*origin" || fail "print: expected Push remote: origin, got: $out"
  echo "$out" | grep -q "git@github.com:dev/triangular-print.git" \
    || fail "print: expected fork push URL in Push remote line, got: $out"
  echo "$out" | grep -q "Upstream remote:.*osac-project/triangular-print" \
    || fail "print: expected upstream fetch URL on Upstream remote line, got: $out"
  pass "triangular --print shows push URL for Push remote"
}

test_standard_bootstrap_naming
test_reversed_naming
test_no_upstream
test_read_only_clone
test_custom_org
test_print_mode
test_idempotent
test_not_a_repo
test_eval_integration
test_worktree
test_directory_name_mismatch
test_prefer_fork_remote
test_explicit_push_remote
test_explicit_push_remote_print
test_explicit_push_remote_invalid
test_triangular_clone_pushurl
test_pushurl_to_upstream_excluded
test_triangular_clone_print_shows_push_url

echo ""
echo "All resolve-remotes.sh smoke tests passed."
