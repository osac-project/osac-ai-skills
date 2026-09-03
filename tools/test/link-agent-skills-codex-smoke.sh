#!/usr/bin/env bash
# Smoke test: --codex fan-out for Codex .agents/skills discovery.
# Run from osac-ai-skills: bash tools/test/link-agent-skills-codex-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
SCRIPT="${REPO_ROOT}/tools/link-agent-skills.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$SCRIPT" ]] || fail "missing $SCRIPT"
[[ -x "$SCRIPT" ]] || fail "$SCRIPT is not executable"

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Consumer fixture with native skills symlinked in (mirrors real fan-out input).
make_consumer() {
  local consumer vendor_skill name
  consumer=$(mktemp -d "${TMPDIR_ROOT}/consumer.XXXXXX")
  mkdir -p "${consumer}/skills"
  for vendor_skill in "${REPO_ROOT}/skills"/*/; do
    [[ -d "$vendor_skill" ]] || continue
    name=$(basename "$vendor_skill")
    ln -sfn "${vendor_skill%/}" "${consumer}/skills/${name}"
  done
  printf '%s' "$consumer"
}

assert_codex_link() {
  local consumer="$1" expected resolved
  [[ -L "${consumer}/.agents/skills" ]] || fail ".agents/skills is not a symlink"
  expected=$(cd "${consumer}/skills" && pwd -P)
  resolved=$(cd -L "${consumer}/.agents/skills" && pwd -P)
  [[ "$resolved" == "$expected" ]] || fail ".agents/skills resolved to $resolved, expected $expected"
  [[ -r "${consumer}/.agents/skills/create-pr/SKILL.md" ]] \
    || fail "cannot read create-pr via .agents/skills"
}

# --- Contracts ---

test_codex_flag_creates_agents_skills() {
  local consumer
  consumer=$(make_consumer)
  PROJECT_ROOT="$consumer" "$SCRIPT" --codex >/dev/null
  assert_codex_link "$consumer"
  # --codex alone must not wire the Claude umbrella.
  [[ ! -e "${consumer}/.claude/skills" ]] \
    || fail "--codex created .claude/skills without --claude/--all"
  pass "--codex creates .agents/skills -> ../skills"
}

test_all_includes_codex() {
  local consumer
  consumer=$(make_consumer)
  PROJECT_ROOT="$consumer" "$SCRIPT" --all >/dev/null
  assert_codex_link "$consumer"
  [[ -L "${consumer}/.claude/skills" ]] || fail "--all did not create .claude/skills"
  pass "--all includes codex"
}

test_codex_verify_passes() {
  local consumer out rc=0
  consumer=$(make_consumer)
  out=$(PROJECT_ROOT="$consumer" "$SCRIPT" --codex --verify 2>&1) || rc=$?
  [[ "$rc" -eq 0 ]] || fail "expected --codex --verify to succeed (rc=$rc): $out"
  echo "$out" | grep -q "Verification passed" \
    || fail "expected verification to pass, got: $out"
  assert_codex_link "$consumer"
  pass "--codex --verify links then verifies"
}

test_codex_idempotent() {
  local consumer
  consumer=$(make_consumer)
  PROJECT_ROOT="$consumer" "$SCRIPT" --codex >/dev/null
  PROJECT_ROOT="$consumer" "$SCRIPT" --codex >/dev/null
  assert_codex_link "$consumer"
  pass "--codex is idempotent on re-run"
}

test_no_codex_no_agents_dir() {
  local consumer
  consumer=$(make_consumer)
  PROJECT_ROOT="$consumer" "$SCRIPT" --claude >/dev/null
  [[ ! -e "${consumer}/.agents/skills" && ! -L "${consumer}/.agents/skills" ]] \
    || fail "--claude created .agents/skills without --codex/--all"
  pass "--claude alone does not create .agents/skills"
}

test_codex_flag_creates_agents_skills
test_all_includes_codex
test_codex_verify_passes
test_codex_idempotent
test_no_codex_no_agents_dir

echo "All link-agent-skills --codex smoke tests passed."
