#!/usr/bin/env bash
# Static checks on the jira-task-management family's SKILL.md files — run
# from a checkout of this repo:
#   bash tools/test/jira-skills-static-check.sh
#
# Lighter analog of osac-workspace's tools/test/jira-skills-smoke.sh, checking
# the native skills/ tree directly instead of a materialized-from-vendor copy.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

test_skills_reference_shared_script() {
  # Consumers either name the script directly (jira-task-management, the
  # canonical skill) or link to the shared resolve-jira-safe-create.md
  # reference (everyone else, since OSAC-4005's dedup) — either counts.
  local skill file
  for skill in jira-task-management report-bug capture-tasks-from-meeting-notes osac-feature; do
    file="${ROOT}/skills/${skill}/SKILL.md"
    # osac-feature's sourcing logic lives in a nested reference, not SKILL.md
    [[ "$skill" == "osac-feature" ]] && file="${ROOT}/skills/osac-feature/references/bash-patterns.md"
    rg -q 'jira-safe-create\.sh|resolve-jira-safe-create\.md' "$file" \
      || fail "${skill}: missing jira-safe-create.sh / resolve-jira-safe-create.md reference in ${file}"
    pass "${skill}: references shared script"
  done
}

test_jira_safe_create_lookup_not_duplicated() {
  # OSAC-4005 extracted the vendor-lookup snippet to a single shared
  # reference (jira-task-management/references/resolve-jira-safe-create.md)
  # specifically to stop this ~9-line block from drifting across 5 verbatim
  # copies. Fail if any consumer re-inlines it instead of linking.
  local skill file
  for skill in report-bug capture-tasks-from-meeting-notes osac-feature; do
    file="${ROOT}/skills/${skill}/SKILL.md"
    [[ "$skill" == "osac-feature" ]] && file="${ROOT}/skills/osac-feature/references/bash-patterns.md"
    if rg -q 'for _cand in .*\.osac-ai-skills.*\.osac-ai-skills' "$file"; then
      fail "${skill}: re-inlined the jira-safe-create.sh vendor-lookup snippet instead of linking to resolve-jira-safe-create.md"
    fi
  done
  pass "no re-duplicated jira-safe-create.sh vendor-lookup snippets"
}

test_no_fixed_tmp_paths() {
  if rg -q '/tmp/(issue-body|jira-create)' "${ROOT}/skills/jira-task-management" \
      "${ROOT}/skills/report-bug" \
      "${ROOT}/skills/capture-tasks-from-meeting-notes" \
      "${ROOT}/skills/osac-feature" 2>/dev/null; then
    fail "fixed /tmp paths still present in skill docs"
  fi
  pass "no fixed /tmp create paths in affected skills"
}

test_no_inline_create_in_examples() {
  # Matches the antipattern string wherever it appears, then checks a few
  # lines of *preceding* context (not just the match line itself) for a
  # "Never do this" / "Do not" qualifier — jira-task-management documents the
  # antipattern under a "**Never do this:**" heading one line above the
  # example, so a same-line-only check would false-positive on it.
  local skill file line_nums line_no context
  for skill in jira-task-management report-bug capture-tasks-from-meeting-notes osac-feature; do
    file="${ROOT}/skills/${skill}/SKILL.md"
    [[ "$skill" == "osac-feature" ]] && file="${ROOT}/skills/osac-feature/references/bash-patterns.md"
    line_nums=$(rg -n 'KEY=\$\(jira issue create' "$file" 2>/dev/null | cut -d: -f1 || true)
    for line_no in $line_nums; do
      context=$(sed -n "$((line_no > 3 ? line_no - 3 : 1)),${line_no}p" "$file")
      grep -qiE 'never |do not ' <<<"$context" && continue
      fail "${skill}: inline KEY=\$(jira issue create...) pattern in example at ${file}:${line_no}"
    done
    pass "${skill}: no inline create antipattern in examples"
  done
}

test_osac_feature_no_duplicate_helpers() {
  if rg -q '^TEMP_FILES=\(\)' "${ROOT}/skills/osac-feature/SKILL.md" "${ROOT}/skills/osac-feature/references/bash-patterns.md"; then
    fail "osac-feature: inline TEMP_FILES block should be removed (use shared script)"
  fi
  pass "osac-feature: no duplicate temp helpers"
}

test_osac_feature_takeover_and_derive() {
  local skill="${ROOT}/skills/osac-feature"
  local skill_md="${skill}/SKILL.md"
  local body="${skill}/references/feature-body-template.md"
  local bash="${skill}/references/bash-patterns.md"
  local epic="${skill}/references/bootstrap-epic.md"

  rg -q 'version: "0.3.0"' "$skill_md" \
    || fail "osac-feature: SKILL.md metadata.version must be 0.3.0"
  pass "osac-feature: version 0.3.0"

  rg -qi 'empty placeholder' "$skill_md" \
    || fail "osac-feature: SKILL.md must document takeover of empty placeholders"
  rg -qi 'never overwrite' "$skill_md" \
    || fail "osac-feature: SKILL.md must document never overwrite of non-empty Features"
  if rg -qi 'proceed anyway' "$skill_md" "$body"; then
    fail "osac-feature: must not tell agents to create a second Feature (proceed anyway)"
  fi
  pass "osac-feature: takeover / never overwrite"

  rg -qi 'always ask the UI-work question' "$skill_md" \
    || fail "osac-feature: SKILL.md must state UI work is always asked (including takeover)"
  pass "osac-feature: UI work always asked"

  rg -qi 'existing Feature key' "$skill_md" \
    || fail "osac-feature: SKILL.md Gather Inputs must accept an optional existing Feature key"
  pass "osac-feature: optional existing Feature key"

  rg -q 'assert_empty_placeholder' "$body" \
    || fail "feature-body-template.md must call assert_empty_placeholder on duplicate/user-supplied key"
  pass "osac-feature: duplicate check calls assert_empty_placeholder"

  local fn
  for fn in is_placeholder_description assert_empty_placeholder read_feature_fields feature_description_has_non_text_nodes clear_feature_managed_labels; do
    rg -q "${fn}()" "$bash" \
      || fail "bash-patterns.md missing ${fn}()"
  done
  pass "osac-feature: placeholder and Feature-field helpers"

  rg -qF -- '--component "${BOOTSTRAP_COMPONENT}"' "$epic" \
    || fail 'bootstrap-epic.md epic create must use --component "${BOOTSTRAP_COMPONENT}"'
  pass "osac-feature: epic create uses BOOTSTRAP_COMPONENT"

  rg -qF 'read_feature_fields "$feature_key"' "$bash" \
    || fail "apply_bootstrap_epic_metadata must call read_feature_fields \"\$feature_key\" (Feature team, not only \$team_name)"
  pass "osac-feature: apply_bootstrap_epic_metadata reads Feature team"

  if rg -n 'jira issue edit' "$body" | rg -q -- '--template'; then
    fail "feature-body-template.md must not use --template on jira issue edit (create-only flag)"
  fi
  rg -qF -- '-b "$(cat "$BODY")"' "$body" \
    || fail "feature-body-template.md takeover must write the body with jira issue edit -b"
  if rg -q 'if \[ "\$TAKEOVER" -eq 1 \]' "$body"; then
    fail "feature-body-template.md write path must branch on KEY, not a TAKEOVER flag from an earlier fence"
  fi
  rg -qF '[ -n "${KEY:-}" ]' "$body" \
    || fail "feature-body-template.md write path must take over when KEY is set"
  local assert_count
  assert_count=$(rg -c 'assert_empty_placeholder' "$body" || true)
  if [ "${assert_count:-0}" -lt 3 ]; then
    fail "feature-body-template.md must re-run assert_empty_placeholder immediately before takeover edit (got ${assert_count:-0})"
  fi
  pass "osac-feature: takeover body uses issue edit -b"

  rg -q 'issue edit.*no.*--template' "$bash" \
    || fail "bash-patterns.md safe-create rules must say issue edit has no --template"
  pass "osac-feature: safe-create rules distinguish create --template from edit -b"

  rg -qF "tr '\\n\\r' ' '" "$bash" \
    || fail "feature_description_text must convert newlines to spaces before sed"
  pass "osac-feature: description flatten joins newlines"

  rg -qF 'OSAC-[0-9]+' "$bash" \
    || fail "assert_empty_placeholder must require an OSAC-[0-9]+ key"
  rg -qF '.fields.project.key' "$bash" \
    || fail "assert_empty_placeholder must check fields.project.key"
  pass "osac-feature: placeholder check enforces OSAC project"

  rg -q 'FEATURE_COMPONENT=$' "$bash" \
    && rg -q 'FEATURE_TEAM=$' "$bash" \
    && rg -q 'FEATURE_FIX_VERSION=$' "$bash" \
    || fail "read_feature_fields must clear FEATURE_* before each read"
  pass "osac-feature: read_feature_fields clears FEATURE_*"

  rg -qF '"to be determined"|"coming soon"' "$bash" \
    || fail 'is_placeholder_description must quote multi-word case patterns'
  pass "osac-feature: placeholder case patterns are quoted"

  rg -qF 'feature_description_has_non_text_nodes' "$bash" \
    || fail "bash-patterns.md must define feature_description_has_non_text_nodes"
  rg -qF 'hardBreak' "$bash" \
    || fail "feature_description_has_non_text_nodes must allow hardBreak as a text wrapper"
  rg -qF 'non-text ADF nodes' "$bash" \
    || fail "assert_empty_placeholder must reject non-text ADF nodes"
  rg -qF 'recurse(.content[]? | objects)' "$bash" \
    || fail "feature_description_has_non_text_nodes must walk content, not marks"
  local adf_pred='
    .fields.description |
    if . == null then false
    elif type == "string" then false
    else
      any(
        recurse(.content[]? | objects);
        (.type // "") != "doc" and (.type // "") != "paragraph"
          and (.type // "") != "text" and (.type // "") != "hardBreak"
          and (.type // "") != ""
      )
    end'
  printf '%s' '{"fields":{"description":{"type":"doc","content":[{"type":"media"}]}}}' \
    | jq -e "$adf_pred" >/dev/null \
    || fail "ADF predicate must treat media-only description as non-text"
  if printf '%s' '{"fields":{"description":{"type":"doc","content":[]}}}' \
    | jq -e "$adf_pred" >/dev/null; then
    fail "ADF predicate must accept an empty doc as text-only"
  fi
  if printf '%s' '{"fields":{"description":"TBD"}}' \
    | jq -e "$adf_pred" >/dev/null; then
    fail "ADF predicate must accept a plain-string description"
  fi
  if printf '%s' '{"fields":{"description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"TBD","marks":[{"type":"strong"},{"type":"link","attrs":{"href":"https://example.invalid"}}]}]}]}}}' \
    | jq -e "$adf_pred" >/dev/null; then
    fail "ADF predicate must accept marked-text TBD as text-only"
  fi
  pass "osac-feature: non-text ADF is not a placeholder"

  if rg -nF 'fix-version "-${existing}"' "$bash" | rg -q '\|\| true'; then
    fail "apply_feature_fix_version must not ignore Backlog-remove failure with || true"
  fi
  rg -qF 'not appending' "$bash" \
    || fail "apply_feature_fix_version must stop before append when Backlog remove fails"
  pass "osac-feature: Backlog remove failure does not append"

  rg -qF 'clear_feature_managed_labels' "$bash" \
    || fail "bash-patterns.md must define clear_feature_managed_labels"
  rg -qF 'clear_feature_managed_labels "$KEY"' "$body" \
    || fail "feature-body-template.md takeover must call clear_feature_managed_labels"
  rg -qF 'customer:*' "$bash" \
    || fail "clear_feature_managed_labels must match customer:* labels"
  rg -qF 'type == "array"' "$bash" \
    || fail "clear_feature_managed_labels must require .fields.labels to be an array"
  if rg -qF 'clear_feature_managed_labels "$KEY" || true' "$body"; then
    fail "takeover must not apply FEATURE_LABELS after a failed managed-label clear"
  fi
  rg -qF 'if clear_feature_managed_labels "$KEY"; then' "$body" \
    || fail "takeover must apply FEATURE_LABELS only after a successful managed-label clear"
  pass "osac-feature: takeover reconciles managed labels"

  if rg -qF 'BOOTSTRAP_FIX_VERSION="${FIX_VERSION:-backlog}"' "$body"; then
    fail "takeover re-read failure must not copy unapplied FIX_VERSION onto the epic"
  fi
  pass "osac-feature: re-read failure does not copy unapplied FIX_VERSION"

  rg -qi 'the confirm gate \(not after\)' "$skill_md" \
    || fail "SKILL.md must run same-summary duplicate check before the confirm gate"
  pass "osac-feature: same-summary duplicate check before confirm"
}

test_skills_reference_shared_script
test_jira_safe_create_lookup_not_duplicated
test_no_fixed_tmp_paths
test_no_inline_create_in_examples
test_osac_feature_no_duplicate_helpers
test_osac_feature_takeover_and_derive

echo ""
echo "All jira skill static checks passed."
