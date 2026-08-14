#!/usr/bin/env bash
# Smoke test: PROJECT_ROOT override for consumer fan-out.
# Run from osac-ai-skills: bash tools/test/link-agent-skills-project-root.sh
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

# Build an isolated standalone checkout under TMPDIR_ROOT so default-mode
# linking never touches the developer's real .claude/.
# Also mirrors real osac-ai-skills content the script materializes/verifies
# unconditionally (or under --claude) even in standalone mode: .claude/rules/,
# .claude/agents/, .claude/hooks/, and .design/context/ (OSAC-4006). In
# standalone mode PROJECT_ROOT==REPO_ROOT, so materialize_shared_dir's
# self-symlink guard no-ops — these must already exist as real files, not
# symlinks, same as a real standalone clone would have.
make_standalone_fixture() {
  local isolated skill_dir name rel_dir
  isolated=$(mktemp -d "${TMPDIR_ROOT}/standalone.XXXXXX")
  mkdir -p "${isolated}/tools" "${isolated}/skills"
  cp "$SCRIPT" "${isolated}/tools/link-agent-skills.sh"
  chmod +x "${isolated}/tools/link-agent-skills.sh"
  for skill_dir in "${REPO_ROOT}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    name=$(basename "$skill_dir")
    ln -sfn "${skill_dir%/}" "${isolated}/skills/${name}"
  done
  for rel_dir in .claude/rules .claude/agents .claude/hooks .design/context; do
    mkdir -p "${isolated}/${rel_dir}"
    cp "${REPO_ROOT}/${rel_dir}"/*.md "${isolated}/${rel_dir}/"
  done
  printf '%s' "$isolated"
}

# --- Contracts ---

test_default_project_root_links_in_repo() {
  # Unset PROJECT_ROOT → agent links land under the skills repo root of an
  # isolated copy (not the developer checkout).
  local isolated
  isolated=$(make_standalone_fixture)

  unset PROJECT_ROOT || true
  (
    cd "$isolated"
    ./tools/link-agent-skills.sh --claude
  ) >/dev/null

  [[ -L "${isolated}/.claude/skills" ]] || fail ".claude/skills is not a symlink in isolated fixture"
  local expected resolved
  expected=$(cd "${isolated}/skills" && pwd -P)
  resolved=$(cd -L "${isolated}/.claude/skills" && pwd -P)
  [[ "$resolved" == "$expected" ]] || fail "default mode resolved to $resolved, expected $expected"
  [[ -r "${isolated}/.claude/skills/create-pr/SKILL.md" ]] || fail "cannot read create-pr via isolated .claude/skills"
  pass "unset PROJECT_ROOT links under skills repo root (isolated fixture)"
}

test_project_root_override_links_consumer() {
  local consumer vendor_skill
  consumer=$(mktemp -d "${TMPDIR_ROOT}/consumer.XXXXXX")
  mkdir -p "${consumer}/skills"

  # Materialize native skills as symlinks (consumer overlay).
  for vendor_skill in "${REPO_ROOT}/skills"/*/; do
    [[ -d "$vendor_skill" ]] || continue
    local name
    name=$(basename "$vendor_skill")
    ln -sfn "${vendor_skill%/}" "${consumer}/skills/${name}"
  done
  [[ -r "${consumer}/skills/create-pr/SKILL.md" ]] || fail "fixture missing create-pr"

  # Stub ai-workflows under the consumer for --with-ai-workflows.
  mkdir -p "${consumer}/.ai-workflows/bugfix" \
    "${consumer}/.ai-workflows/design" \
    "${consumer}/.ai-workflows/e2e" \
    "${consumer}/.ai-workflows/implement" \
    "${consumer}/.ai-workflows/prd" \
    "${consumer}/.ai-workflows/_shared"
  echo '# stub' >"${consumer}/.ai-workflows/bugfix/SKILL.md"
  echo '# stub' >"${consumer}/.ai-workflows/design/SKILL.md"
  echo '# stub' >"${consumer}/.ai-workflows/e2e/SKILL.md"
  echo '# stub' >"${consumer}/.ai-workflows/implement/SKILL.md"
  echo '# stub' >"${consumer}/.ai-workflows/prd/SKILL.md"

  # Capture pre-state: consumer mode must not create agent links in the
  # skills-repo checkout when none existed before this invocation.
  local had_repo_claude=0
  [[ -e "${REPO_ROOT}/.claude/skills" ]] && had_repo_claude=1

  PROJECT_ROOT="$consumer" "$SCRIPT" --claude --with-ai-workflows >/dev/null

  [[ -L "${consumer}/.claude/skills" ]] || fail "consumer .claude/skills is not a symlink"
  local expected resolved
  expected=$(cd "${consumer}/skills" && pwd -P)
  resolved=$(cd -L "${consumer}/.claude/skills" && pwd -P)
  [[ "$resolved" == "$expected" ]] || fail "override resolved to $resolved, expected $expected"
  [[ -r "${consumer}/.claude/skills/create-pr/SKILL.md" ]] || fail "cannot read create-pr via consumer .claude/skills"

  [[ -L "${consumer}/skills/bugfix" ]] || fail "expected skills/bugfix symlink under consumer"
  [[ -r "${consumer}/skills/bugfix/SKILL.md" ]] || fail "cannot read bugfix via consumer skills/"

  if [[ "${had_repo_claude}" -eq 0 ]]; then
    [[ ! -e "${REPO_ROOT}/.claude/skills" ]] \
      || fail "consumer mode created ${REPO_ROOT}/.claude/skills (expected isolation)"
  fi
  pass "PROJECT_ROOT override links under consumer tree only"
}

test_default_project_root_links_in_repo
test_project_root_override_links_consumer

echo "All link-agent-skills PROJECT_ROOT smoke tests passed."
