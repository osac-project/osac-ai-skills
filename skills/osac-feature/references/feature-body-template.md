# Feature body template and create

**Read this file when creating the Feature issue, or taking over an empty
placeholder** (after user confirms the gate).

The User Stories section must include a subsection for each OSAC persona
defined in `osac-docs/personas.md` (canonical source:
[osac-project/docs/personas.md](https://github.com/osac-project/docs/blob/main/personas.md)).
For each persona, either write an outcome-focused story ("As a X, I want Y
so that Z") or explicitly mark the persona as not affected by this feature.

Write the Feature body to `$BODY` using this structure (`BODY=$(new_temp osac-feature-body)` first). Use a blank line before
each `###` persona heading so jira-cli preserves separate subsections in Jira.
Replace `<SKILL_VERSION>` in the trailer with this skill's `metadata.version` value from `skills/osac-feature/SKILL.md`.

```markdown
## Feature Goal
<What this feature aims to accomplish>

## Problem Statement
<The problem this feature solves>

## User Stories

### Cloud Provider Admin

- As a Cloud Provider Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Cloud Infrastructure Admin

- As a Cloud Infrastructure Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant Admin

- As a Tenant Admin, I want <outcome> so that <reason>
- (or: not affected by this feature)

### Tenant User

- As a Tenant User, I want <outcome> so that <reason>
- (or: not affected by this feature)

## Definition of Done
- [ ] <criterion>

## Out of Scope
<What is excluded>

---

_This feature specification was drafted with AI assistance ([osac-feature](https://github.com/osac-project/osac-workspace/tree/main/skills/osac-feature) v<SKILL_VERSION>). Review for accuracy_
```

## Duplicate check

Exact summary match, project-scoped (Features have no parent). If `KEY` is
already set (user-supplied existing Feature key), skip the JQL search and go
to the placeholder check.

```bash
TAKEOVER=0
if [ -n "${KEY:-}" ]; then
  assert_empty_placeholder "$KEY" \
    || { echo "Existing Feature ${KEY} is not an empty placeholder — not overwriting" >&2; exit 1; }
  TAKEOVER=1
else
  collect_keys_from_jql "project = OSAC AND type = Feature AND summary = \"${FEATURE_SUMMARY}\"" \
    || { echo "Feature duplicate-check failed — stopping before create" >&2; exit 1; }
  if [ "$KEY_COUNT" -gt 1 ]; then
    echo "Multiple Features with this summary (${FIRST_KEY} …) — ask user which key to use" >&2
    exit 1
  fi
  if [ "$KEY_COUNT" -eq 1 ]; then
    KEY=$FIRST_KEY
    assert_empty_placeholder "$KEY" \
      || { echo "Existing Feature ${KEY} is not an empty placeholder — not overwriting" >&2; exit 1; }
    TAKEOVER=1
  fi
fi
```

A failed lookup must stop here — do not fall through with `KEY_COUNT=0` and
create a duplicate Feature on a transient Jira error. A non-empty Feature
must stop here — never overwrite.

Write `$BODY`, then create or take over. Use patterns from
[bash-patterns.md](bash-patterns.md) (`new_temp`, `require_osac_key`,
`assert_empty_placeholder`, `read_feature_fields`):

```bash
BODY=$(new_temp osac-feature-body)
add_temp "$BODY"
# write markdown body to $BODY, then:
OUT=$(new_temp osac-jira-feature-out)
add_temp "$OUT"
ERR=$(new_temp osac-jira-feature-err)
add_temp "$ERR"

FEATURE_LABELS=()
[ "$REQUIRES_UI" = "yes" ] && FEATURE_LABELS+=(--label osac-ux --label osac-ui)
[ -n "${CUSTOMER:-}" ] && FEATURE_LABELS+=(--label customer --label "customer:${CUSTOMER}")

if [ "$TAKEOVER" -eq 1 ]; then
  if ! jira issue edit "$KEY" --template "$BODY" --no-input 2>"$ERR" </dev/null; then
    echo "Feature body edit failed for ${KEY} — stopping" >&2
    cat "$ERR" >&2
    exit 1
  fi
  if [ ${#FEATURE_LABELS[@]} -gt 0 ]; then
    if ! jira issue edit "$KEY" "${FEATURE_LABELS[@]}" --no-input 2>>"$ERR" </dev/null; then
      echo "Feature label edit failed for ${KEY} — continuing bootstrap" >&2
      cat "$ERR" >&2
    fi
  fi
  read_feature_fields "$KEY" || true
  if [ -z "${FEATURE_COMPONENT:-}" ]; then
    if ! jira issue edit "$KEY" --component "${COMPONENT}" --no-input 2>>"$ERR" </dev/null; then
      echo "Feature component edit failed for ${KEY} — continuing bootstrap" >&2
      cat "$ERR" >&2
    fi
  fi
  if [ -n "${FEATURE_FIX_VERSION:-}" ]; then
    BOOTSTRAP_FIX_VERSION="$FEATURE_FIX_VERSION"
  elif apply_feature_fix_version "$KEY" "$FIX_VERSION"; then
    BOOTSTRAP_FIX_VERSION="$FIX_VERSION"
  else
    echo "Feature fix version not applied — bootstrap epic will not receive a copy; set both manually" >&2
    BOOTSTRAP_FIX_VERSION="backlog"
  fi
  if [ -z "${FEATURE_TEAM:-}" ]; then
    apply_team "$KEY" "$TEAM"
  fi
else
  jira issue create -t Feature --project OSAC \
    -s "${FEATURE_SUMMARY}" \
    --template "$BODY" \
    --component "${COMPONENT}" \
    "${FEATURE_LABELS[@]}" \
    --no-input --raw >"$OUT" 2>"$ERR" </dev/null

  KEY=$(jq -r '.key // empty' "$OUT")
  require_osac_key "$KEY" "Feature" "$OUT" "$ERR"
  if apply_feature_fix_version "$KEY" "$FIX_VERSION"; then
    BOOTSTRAP_FIX_VERSION="$FIX_VERSION"
  else
    echo "Feature fix version not applied — bootstrap epic will not receive a copy; set both manually" >&2
    BOOTSTRAP_FIX_VERSION="backlog"
  fi
  apply_team "$KEY" "$TEAM"
fi
```

Allow up to 3 minutes for create or takeover edit to complete.

Order after Feature create or takeover: **fix version → team → assign (if any) →
bootstrap epic**. Gate tasks never receive `--fix-version`. Use
`$BOOTSTRAP_FIX_VERSION` (not `$FIX_VERSION`) when applying bootstrap epic
metadata below — it reflects whether the Feature already had a version or the
edit actually succeeded.
On takeover, skip `apply_team` / `--component` / `apply_feature_fix_version`
when that field is already set on the Feature. `$TEAM` is still the
resolved value (Feature or prompted) passed through to the bootstrap epic
and gate tasks.

## Assign if specified

If user specified an assignee:

```bash
ASSIGN_ERR=$(new_temp osac-jira-assign-err)
add_temp "$ASSIGN_ERR"
if ! jira issue assign "$KEY" "$ASSIGNEE" 2>"$ASSIGN_ERR"; then
  echo "Assign failed for ${KEY} — continuing bootstrap" >&2
  cat "$ASSIGN_ERR" >&2
fi
```
