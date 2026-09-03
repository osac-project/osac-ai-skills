# Weekly Report Subcommand

Generate a data-verified OSAC infra/CI status report. Every claim must be
independently confirmed against a live source (Jira, `gh`, or the actual
repo content) -- never repeat a PR description, a Slack summary, or a memory
file's claim as fact without checking it directly.

This is a **two-phase flow: draft, then finalize** (see Step 5 and Step 6).
Do not treat the first pass as complete or publishable -- it isn't, by
design.

## Step 1: Scope

Ask only if not already clear from the user's message:
- **Time period** -- default to 14 days (biweekly) if unspecified. Confirm
  the exact start/end dates before querying.
- **Audience** -- default to team-level (detailed, with confirmed root
  causes) unless the user asks for an executive summary.

## Step 2: Pull Data From Multiple Independent Sources

Do not rely on a cached dashboard number for anything that can be computed
directly.

### Jira -- component search AND known-epic search, not component alone

A single `component = Infrastructure` query misses real work that lives
under other epics/components (e.g. mono-repo consolidation, disconnected-env
research have both been missed this way before). Run **both**:

```bash
export JIRA_API_TOKEN="$(systemctl --user show-environment | sed -n 's/^JIRA_API_TOKEN=//p')"

# NOTE: do not embed "ORDER BY" inside the -q/--jql string -- jira-cli appends
# its own ORDER BY based on --order-by, and a query-supplied one collides with
# it (400: "Expecting ',' but got 'ORDER'"). Use --order-by instead. Confirmed
# by actually running this command, not assumed from docs.

# 1. Generic component sweep
jira issue list --plain -q \
  'project = OSAC AND component = Infrastructure AND updated >= -<N>d' \
  --order-by updated

# 2. Known active epics, checked explicitly regardless of component/label
for EPIC in OSAC-1732 OSAC-1963; do
  jira issue list --plain -q "parent = ${EPIC} AND updated >= -<N>d" --order-by updated
done
```

`OSAC-1732` (mono-repo consolidation) and `OSAC-1963` (disconnected-env
support) are a **seed list, not a ceiling** -- ask the user at Step 1 whether
a canonical list of standing epics exists; if not, also run a discovery
pass for epics with real recent child-ticket activity that a plain
component filter would miss:

```bash
jira issue list --plain -q \
  'project = OSAC AND issuetype = Epic AND status != Done AND updated >= -<N>d' \
  --order-by updated
```

Cross-check candidates from this discovery pass against the component
sweep -- anything already covered there doesn't need separate epic
treatment. Add any new standing epic the user confirms is worth tracking
every time to the seed list above (persisted as a skill update, not
re-asked every run).

Jira's "Infrastructure" component also catches non-CI items (hardware
procurement, onboarding, release paperwork). Only include items you
individually confirm are real CI/infra/tooling work -- note in Open
Questions that the component label is broader than this report's scope.

### GitHub PRs

Discover the relevant repos the same way `osac-release` does (dynamic
sibling discovery via the `bootstrap.sh` layout, not a hardcoded list) --
in practice this usually includes `osac`, `osac-test-infra`,
`github-config`, and any component repo where CI/infra work landed (e.g.
`osac-aap` for AAP-related e2e or networking fixes). Adjust based on what
the Jira pull surfaces.

```bash
gh pr list --repo osac-project/<repo> --state merged --search "merged:>=<start-date>" --json number,title,mergedAt,url
```

### CI Run Stats

Compute pass rates directly from raw workflow run data -- do not assume a
dashboard figure is current.

```bash
gh api "repos/osac-project/osac/actions/workflows/<workflow-file>/runs?created=>=<start-date>" \
  --jq '[.workflow_runs[] | {conclusion, event}]'
```

Split by `event` (`pull_request` vs `schedule`/`workflow_dispatch`) and
compute pass rate separately for each -- the gap between the two is often
the most useful signal (e.g. concurrent-load issues that only show up
under real PR traffic).

## Step 3: Verify Before Asserting

This is the step most likely to be skipped under time pressure -- don't.

- **Never call something "resolved" or "fixed" from a PR title or
  description alone.** Check `gh pr view <N> --json state,mergedAt` and,
  for anything safety-critical, grep the current default branch to confirm
  the fix is actually present in the code today.
- **Treat memory-file or Slack-summary claims as leads, not facts.** If a
  memory file names a specific PR/ticket as the root cause, verify that PR
  or ticket directly via `gh`/`jira` before including it. If the memory
  file can't be found or doesn't match, say so explicitly rather than
  silently dropping or silently trusting the claim.
- **Distinguish confirmed causation from plausible inference in the
  prose itself.** e.g. "most likely tied to X, but this is a plausible
  inference, not confirmed" rather than stating a causal link as fact.
- If a PR is closed but unmerged (including `[WIP]`-tagged), report it as
  an open/stalled item, not a shipped resolution -- even if CI validated
  the underlying fix.
- **Standing instruction: for any epic included in the report, verify
  every child/sub-task's live current status individually** (`jira issue
  list --jql "parent = <EPIC>"` or `jira issue view <CHILD>`) -- do not
  summarize an epic from its own description or a stale rollup. An epic
  description saying "in progress" can hide 9 follow-up tasks that are all
  still untouched, or a gap-analysis doc that's actually done and sitting
  in Review. Always check each child directly, every run, not only when it
  happens to seem necessary.

## Step 4: Draft the Report -- Aggregate Framing by Default

```markdown
# OSAC Infra Team — Status Report (<start>–<end>, <year>)

## TL;DR
- 3-5 plain-language bullets, no jargon

## CI Health

| Suite | On real PRs | On scheduled/nightly runs |
|---|---|---|
| <suite> | <pct>% | <pct>% |

**Real incidents this period:**
- Default to PATTERNS, not single-PR play-by-plays: "queue stalls happen
  when a conflicted PR blocks the batch" beats a detailed writeup of one
  specific PR number. Team-facing reports want the systemic shape, not a
  narrative the affected person likely already has directly.
- Only include single-incident detail when the incident itself IS the
  systemic pattern worth surfacing (a one-off that's actually a first
  instance of a new failure mode) -- not just because it was interesting
  to investigate.
- Each item still needs a confirmed root cause OR an explicit
  "unconfirmed" caveat -- never a mix presented as equally certain.

## Infra / Hardware Changes
- Runner fleet, host config, monitoring/observability additions

## Shipped This Period
- Cross-reference incidents/changes above; don't repeat facts without the
  confirmed/unconfirmed framing established there

## In Progress
- Real current status per item (open / in review / blocked), not just a
  title. For epic-level items, this must reflect the live child-ticket
  check from Step 3, not the epic's own summary text.

## Uncertain / Needs Your Input
- Anything not independently confirmed
- Anything you searched for and could not find (missing tickets, numbers
  you could not source, memory-file references that didn't resolve) --
  name the specific gap so the user can point you at it, the same way a
  missing failure-rate number or an unlisted epic would surface here
- Known scope gaps (e.g. Jira component breadth, dashboard vs computed
  numbers)
```

This is the **draft**. It is expected to be incomplete -- that is the point
of having this section at all.

## Step 5: Present the Draft and Invite Corrections

Present the draft in full and explicitly say something like: "This is a
draft. Point me at anything missing, wrong, or worth cutting -- specific
tickets, numbers I couldn't find, or content that's accurate but shouldn't
be in the final version (e.g. detail already delivered to the affected
person directly) -- and I'll fold it in before finalizing."

Treat follow-up corrections as the **normal expected second step**, not a
failure of the first pass:
- A pointer to a missing ticket/epic -> pull it live (Jira/`gh`), verify
  child status per Step 3, fold in.
- A number you couldn't find -> ask where to source it rather than
  estimating or omitting silently.
- A request to cut accurate-but-unwanted content -> remove it; don't argue
  for keeping something correct if the user says it doesn't belong (e.g.
  single-incident detail the affected person already has, or content not
  meant for this audience).

Loop this step until the user confirms the draft is ready to finalize.

## Step 6: Finalize -- a Distinct, Clean Output

Finalizing is not "save the same file again." Produce a **separate final
document** that:
- Removes the `## Uncertain / Needs Your Input` section entirely, or folds
  any items the user explicitly chose to keep (rare) into the relevant
  section as confirmed fact -- with no residual "I'm not sure" / "flagging
  as unconfirmed" language anywhere in the final text.
- Applies every correction/cut from Step 5.
- Re-checks that aggregate framing (Step 4) still holds after edits --
  cuts sometimes leave an orphaned single-incident reference.

Save the draft as `/tmp/osac-infra-weekly-report-<end-date>-draft.md` and
the finalized version as `/tmp/osac-infra-weekly-report-<end-date>.md` --
two distinct files, not one edited in place. Print the final version to the
user on completion.
