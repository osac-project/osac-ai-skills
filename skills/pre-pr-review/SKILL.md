---
name: pre-pr-review
description: >
  Use when the user invokes /pre-pr-review, wants a pre-flight review without
  creating a PR, or wants create-pr Step 4's config-driven reviewers run in
  isolation (no repo build/lint/test, coverage, push, or gh pr create). Orchestrates
  skills/.config/create-pr-reviewers.yaml as parallel subagents. Distinct from
  /review-gate (sequential, different output, includes dirty tree).
metadata:
  version: "0.1.0"
---

# Pre-PR Review

Config-driven pre-flight review gate: the same YAML, validation checklist,
parallel reviewer fan-out, Output Contract, and PASS / BLOCKED / INVALID
verdict as create-pr Step 4 — without repo build/lint/test, coverage, push, or
`gh pr create`.

**Announce at start:** "Using the pre-pr-review skill to run the pre-PR review gate."

**CRITICAL — fan-out in this agent, never a wrapper subagent:** Spawn one
background reviewer subagent per enabled YAML entry, **all in the same
message**. Do **not** wrap this skill in an extra Agent/subagent (including
from create-pr). Nested `create-pr` → `pre-pr-review` subagent → N reviewers
breaks "all reviewers in one parent message." If this harness cannot fan out
concurrent background agents from one call, verdict is `INVALID` — name that
limitation; never fall back to sequential reviewers.

**CRITICAL — never push.** Report the verdict and stop. Do not `git push` or
`gh pr create`. Do not resolve `INVALID` by editing the reviewed source,
history, or git state so a reviewer's scope computation succeeds — fix
tooling/config, or escalate; the reviewed change is not what to change.

## vs `/review-gate`

Do not implement this skill as "just call `review-gate`." Same reviewer
**skills** may run in both; the **orchestrator** is different:

| | `/pre-pr-review` (this skill) | `/review-gate` |
|---|---|---|
| Reviewers | YAML `create-pr-reviewers.yaml` (currently 3) | Hardcoded performance then security |
| Parallelism | Parallel subagents | Sequential |
| Output | create-pr table contract | `[SEVERITY] file:line — …` lines |
| Typical scope | merge-base `{base}`…HEAD (committed) | Also untracked / dirty |

create-pr still embeds this same gate at its Step 4; wiring it to **read
and follow this file inline** is a follow-up. Until then, both copies must
keep the same semantics.

## Callers

**Standalone (`/pre-pr-review` — this skill's job today):** locate
`$REPO_DIR` / `$OSAC_AI_SKILLS_DIR` below. No `gh` auth, no push remote, no
"must not be on main", no "commits ahead of main." Empty scope → reviewers'
`NONE` → PASS. After the report, **stop**.

**create-pr Step 4 (not wired yet; when it is, same agent, inline):** reuse
`$REPO_DIR` / `$OSAC_AI_SKILLS_DIR` if already set. After PASS, that caller
continues to its Step 5. INVALID/BLOCKED: do not push; BLOCKED → fix in a
**new** commit (never amend), restart create-pr at its Step 2.

## Locate the repo and skills checkout

```bash
REPO_DIR=$(git rev-parse --show-toplevel)
```

If this fails, overall verdict `INVALID` — name the git error; stop.

**If `$OSAC_AI_SKILLS_DIR` is already set, reuse it.** Otherwise find a
directory that contains `skills/.config/create-pr-reviewers.yaml`. **Do
not** run `resolve-remotes.sh` (no push remote required). Search
**local-first**, then one parent of `$REPO_DIR` (a nested component repo
such as `osac/` lives under a workspace that holds `skills/` or
`.osac-ai-skills/`), and only then `~/.osac-ai-skills`. At each level
prefer `.osac-ai-skills/` over the directory itself. A global install
must not shadow a checkout in or above `$REPO_DIR`.

```bash
if [[ -z "${OSAC_AI_SKILLS_DIR:-}" ]]; then
  OSAC_AI_SKILLS_DIR=""
  for _cand in \
      "${REPO_DIR}/.osac-ai-skills" \
      "${REPO_DIR}" \
      "${REPO_DIR}/../.osac-ai-skills" \
      "${REPO_DIR}/.." \
      "${HOME}/.osac-ai-skills"; do
    if [[ -f "${_cand}/skills/.config/create-pr-reviewers.yaml" ]]; then
      OSAC_AI_SKILLS_DIR=$(cd "$_cand" && pwd) || continue
      break
    fi
  done
fi
```

If still unset → `INVALID`. Tell the user to bootstrap so the YAML exists
at `$REPO_DIR`, `$REPO_DIR/..`, a vendored `.osac-ai-skills` in either, or
`~/.osac-ai-skills`.

If `git status --porcelain` in `$REPO_DIR` is non-empty, **warn** that
uncommitted/untracked files are **out of scope** (reviewers use
merge-base…HEAD like create-pr Step 4), then **continue**. Do not fail
solely for a dirty tree — dirty-inclusive review is `/review-gate`.

Each reviewer diffs from `$(git merge-base {base} HEAD)`, run against
`$REPO_DIR`, using its own config `base` (default `main`).

Reviewers are defined in `skills/.config/create-pr-reviewers.yaml`, not
hardcoded here — **read before running Step 1:**
`skills/create-pr/references/reviewer-config.md` for the schema, path
resolution, validation checklist, and Output Contract. Do not rewrite that
contract in this file.

## Step 1: Validate Config and Launch Reviewers in Parallel

Read `${OSAC_AI_SKILLS_DIR}/skills/.config/create-pr-reviewers.yaml` with
`Read`. Every `skill:` value is also read from
`${OSAC_AI_SKILLS_DIR}/<path>`.

Run every check in `skills/create-pr/references/reviewer-config.md`'s
Validation Checklist, in order. **Any failure stops here with overall
verdict `INVALID`** — no agent spawned, no push, naming exactly which check
and entry failed.

Once validation passes, for each enabled reviewer substitute `{skill}`
(the `$OSAC_AI_SKILLS_DIR`-resolved path), `{base}` (default `main`),
`{category}`, and `{repo_dir}` (`$REPO_DIR`) into `prompt_template`.
`{repo_dir}` anchors the reviewer's own git commands to the repo under
review — file-path resolution (`$OSAC_AI_SKILLS_DIR`) and git-scope
anchoring (`$REPO_DIR`) are separate concerns; both must be substituted.

Spawn **one separate background Agent subagent per enabled reviewer, all
in the same message** — one agent per reviewer, substituted prompt as its
`prompt`, never shared.

```text
Agent tool calls (all enabled reviewers, same message):
  For each enabled reviewer:
    subagent_type: not specified (use <reviewer.skill>, resolved via $OSAC_AI_SKILLS_DIR)
    prompt: <prompt_template with {skill}, {base}, {category}, {repo_dir}
             substituted for this reviewer>
```

The number of calls this produces always matches the config's enabled
entries — adding, removing, or disabling a reviewer changes it without any
edit to this file. `security-review` cannot be disabled via `enabled: false`
while its entry keeps `mandatory: true` (check 9) — but deleting the entry
outright is not itself blocked; that's an accepted limitation, not a bug.
An independent CI check (`.github/workflows/mandatory-reviewer-check.yml`)
catches entry removal too — see
`skills/create-pr/references/reviewer-config.md`'s Mandatory Reviewers
section.

Wait for all agents to complete. **A reviewer that hasn't returned within
10 minutes — or if this harness provides no way to detect/bound a hung
subagent's runtime at all — is `INVALID`** (see Step 2); there is no
option to note the limitation and keep waiting. Prefer a real wall-clock
timeout parameter on the agent-spawning tool itself, if the harness offers
one, over a post-hoc `duration_ms`-style field — the latter only arrives
after a call finishes, so it can't detect a reviewer that never returns at
all.

## Step 2: Validate Outputs and Aggregate Results

For each spawned reviewer, normalize and validate its output per
`skills/create-pr/references/reviewer-config.md`'s Output Contract —
read that section for the exact rules (the unconditional stray-`verdict:`
check, the leading-prose tolerance and its concrete-finding judgment call,
the single-table-shape grammar including the `NONE`/`INVALID` solo-row
rule). **Reviewers never self-report PASS or BLOCKED — only a solo
`INVALID` row.** A timeout, empty/missing output, or anything else not
matching the contract is that reviewer's result: `INVALID`.

**If any spawned reviewer's result is `INVALID`, the overall gate verdict
is `INVALID`** — name the reviewer(s) and stop. **Show every spawned
reviewer's output in the report** (raw if it didn't parse, its findings if
it did) — not only the one that failed; do not aggregate the clean
reviewers into a PASS alongside a failed one.

Only once every spawned reviewer's result validates — meaning no reviewer
reported an `INVALID` row — combine all real-finding rows
(`CRITICAL`/`IMPORTANT`/`ADVISORY`, excluding any `NONE` rows — they aren't
findings) into a single aggregated table, redacting per
`skills/create-pr/references/reviewer-config.md`'s redaction rule:

```markdown
| Severity | File:Line | Category | Issue | Suggestion |
|----------|-----------|----------|-------|------------|
| ... | ... | Performance | ... | ... |
| ... | ... | Security | ... | ... |
| ... | ... | Ponytail | ... | ... |
```

"Category" uses each reviewer's config `category` — the example above shows
three rows because three reviewers are currently enabled; it grows or
shrinks with the config, not with this example.

## Step 3: Determine Overall Verdict

| Condition | Overall Verdict | Action |
|-----------|----------------|--------|
| Step 1 config validation failed | INVALID | Stop, report which check/entry failed |
| Any spawned reviewer's result is INVALID (Step 2) | INVALID | Stop, name the reviewer(s), show every reviewer's output |
| Any finding is `CRITICAL` or `IMPORTANT` | BLOCKED | Stop, show aggregated report |
| All findings are ADVISORY only, or there are no findings at all | PASS | Report and stop (create-pr caller: continue to its Step 5) |

## Step 4: Gate and Report

**If INVALID:** Stop. Do not push. Every spawned reviewer's output is
shown in the report (Step 2), regardless of which one caused the
`INVALID`. Do not resolve an `INVALID` verdict by editing the reviewed
source, history, or git state to make a reviewer's scope computation
succeed — fix the tooling/config problem, or escalate to the user; the
reviewed change itself is not the thing to change here. Identify which
cause applies:
- **Step 1 config validation failed** — fix `skills/.config/create-pr-reviewers.yaml` per the reported check, then re-run this skill.
- **A reviewer reported an `INVALID` row** — investigate the git state its explanation cell points to, then re-run this skill.
- **A reviewer's output was unparseable, or it timed out/crashed** — check its raw output manually for any real finding (the gate could not auto-classify it), then re-run this skill.

An empty review scope is **not** INVALID — a reviewer with nothing to
review reports a lone `NONE` row, contributing to PASS.

**If BLOCKED:** Stop. Show the full aggregated findings table with all
`CRITICAL`/`IMPORTANT` issues. Do not push. Fix the flagged issues in a new
commit (never amend), then re-invoke `/pre-pr-review` (create-pr caller:
restart at its Step 2 so validation, coverage, and this gate all re-run).

**If PASS (with ADVISORY findings):** Show the aggregated report with the
ADVISORY findings — these do not block. Standalone: stop. create-pr
caller: continue to its Step 5.

**If PASS (clean):** Report "Pre-flight review gate: PASS (no findings)."
Standalone: stop. create-pr caller: continue to its Step 5.

## Red Flags

**Never:**
- Wrap this orchestrator in an extra subagent — this agent fans out the reviewers
- Fall back to sequential reviewers if parallel fan-out is unavailable — `INVALID` instead
- Call `/review-gate` as a substitute for this YAML-driven gate
- Push, force-push, or `gh pr create` from this skill
- Treat a dirty working tree as a hard failure — warn and continue
- Skip an enabled reviewer, or decide PASS/BLOCKED before every spawned reviewer has returned
- Let a reviewer self-report PASS or BLOCKED
- Amend an existing commit to address BLOCKED findings — new commit, then re-run
- "Fix" `INVALID` by editing the reviewed git state so scope computation succeeds

**Always:**
- Read `skills/create-pr/references/reviewer-config.md` before Step 1
- Spawn every enabled reviewer in one parent message
- Show every spawned reviewer's output on overall `INVALID`
- Redact secrets/PII in the report per the Output Contract
