---
name: test-plan-review
metadata:
  version: "0.3.0"
description: |
  Completeness reviewer for OSAC testplans. Checks requirement
  coverage, test case depth, structural consistency, and gap analysis.
  Run after scoring flags issues, or before publishing a testplan.

  Trigger when user says "review test plan", "check test completeness",
  "are all tests covered", or after a Revise/Rework verdict.
---

# OSAC Test Plan Completeness Reviewer

A focused reviewer for `testplan.md`.
Examines test plan quality from a single angle: **is every requirement
covered by a detailed, implementable test case?** It also checks required
component-integration cases against the documented tier and boundary, and
rejects coverage claims that rely on an undisclosed fake.

## Testplan Structure

The input follows the testplan format:

- `## Overview` — feature, total TCs, requirements covered
- `## Test Cases` — grouped by `### FR-N` / `### NFR-N` headings
- Each `#### TC-{req}-{NN}` has: metadata table (Story/AC/Priority/Automation),
  Preconditions, Steps, Expected Results
- `## Gaps` — uncovered requirements with justification
- `## Summary` — counts by priority and automation

## Input

1. **File path** — `enhancements/<slug>/testplan.md`
2. **PR number** — fetch from PR diff
3. **No input** — search:
   ```bash
   find enhancement-proposals/enhancements -name "testplan.md" -type f
   ```

## Load Context

1. **testplan.md** — the plan being reviewed
2. **design.md** — `enhancements/<slug>/design.md`
3. **prd.md** — `enhancements/<slug>/prd.md`
4. **OSAC test strategy** — [test strategy](../test-plan-score/references/osac-test-strategy.md)
5. The OSAC workspace's `docs/INTEGRATION-TESTING.md` planning-evidence section
   and relevant component sections for tier names, commands, boundaries, and
   documented coverage gaps
6. Each affected component's `AGENTS.md` touched-area map and integration-test
   guidance

If the workspace guidance or a component map is unavailable, report that
limitation and leave the required boundary unverified. Do not infer it from a
test's filename or from the word "integration".

## Review Checks

### Check 1: Integration Tier and Boundary

For each affected component and touched behavior:
- Use the component's touched-area map to identify the required tier and
  boundary, and use the corresponding `docs/INTEGRATION-TESTING.md` section to
  verify the suite and command. Check only boundaries that apply to this
  change.
- Map component-specific tier labels to the canonical tier in the shared
  guidance. Check ownership too: Unit, Envtest, component-integration, and
  Contract coverage for changed code belongs to [DEV]; deployed cross-component
  journeys belong to [QE].
- Require one selected canonical tier per coverage row. Slash-separated
  alternatives or multiple candidate tiers are ambiguous. A manual case may
  identify its procedure instead of a shell command and explain why a working
  directory does not apply. Supplemental static/build checks may be listed
  separately as non-test validation, but are not a test tier and cannot satisfy
  a required test tier.
- Verify every required Unit, Envtest, component-integration, Contract, or
  deployed E2E row identifies
  the owning component and behavior, requirement/interface references,
  canonical tier, boundary, test-case IDs, existing suite/file or clearly
  proposed location, verified command or concrete manual procedure, applicable
  working directory or justified N/A, environment prerequisites, execution
  status, and which dependencies run for real versus being mocked,
  stubbed, or omitted.
- Verify existing suites and commands against repository guidance. Label new
  locations and unverified commands as proposed; identify manual paths as
  manual procedures, not runnable shell commands. If a suite is unavailable or
  a prerequisite is unresolved, require the owning follow-up's Jira URL or an
  explicit statement that no owner/ticket exists.
- Distinguish a planned test, an identified execution path, and a passed run.
  `Not run` or `blocked` is an honest status, not a pass. A claimed pass needs
  command or manual procedure and observed-result evidence; otherwise report it as not passed.
- Compare the claimed tier and actual dependency boundary with the documented
  requirement. A case at a different tier does not satisfy it merely because
  it covers the same behavior. Unit and Envtest do not satisfy a required
  component-integration, Contract, or E2E boundary; a component-integration
  case does not satisfy a required deployed E2E boundary.
- Treat a missing case for a required boundary as a coverage gap. Do not count
  a lower-tier case as coverage for it. A follow-up ticket records ownership of
  the gap; it does not satisfy the boundary or permit PASS.

**Hard failure:** If a required case claims the wrong tier for its
documented boundary, or claims a required real/deployed boundary while its
described setup substitutes a mock/stub or omits a required component, mark the
review `NEEDS WORK` and label the finding `Rework veto`. Cite the test
case and the map or planning-evidence row. Do not apply this failure to a
documented gap for unrelated behavior or when the map requires only a lower
tier.

Missing command or manual procedure, applicable working directory (or a
justified N/A for a manual case), prerequisite, execution status, follow-up
information, ambiguous tier, or missing/ambiguous dependency disclosure is an
evidence gap, not a Rework veto. Mark the affected row incomplete and the plan `NEEDS WORK`; do not count
it as an identified runnable path or passed coverage.

Report a missing or mismatched owner as an ownership gap and mark `NEEDS WORK`;
it is not a Rework veto unless the case also has a wrong tier or a
demonstrated claimed-versus-actual boundary mismatch.

**Output:** Table of required boundaries with status: Planned at required tier
(not run) / Execution path identified / Passed with result evidence / Wrong
tier (Rework veto) / Ambiguous tier / Claimed-versus-actual boundary
mismatch (Rework veto) / Dependency-disclosure gap / Evidence gap / Coverage
gap / Owner gap / Unverified (source unavailable).

### Check 2: Requirement Tracing

Read the PRD's functional and non-functional requirements. For each:
- Does a `### FR-N` / `### NFR-N` section exist in the testplan?
- Does it have at least one TC underneath?
- If not covered, is it documented in the Gaps section with justification?

**Output:** Table of requirements with status: Covered / Gap (justified) / MISSING

### Check 3: Test Case Depth

For every TC in the testplan:
- **Metadata table** — Story, AC, Priority, Automation all present?
- **Preconditions** — concrete system state (not just "system running")?
- **Steps** — numbered with specific API calls and parameters?
- **Expected Results** — observable outcomes with specific values?
  Banned: restatements of acceptance criteria, non-specific outcomes,
  or phrases that describe intent rather than observable behavior

**Score each TC:**
- **Complete** — all sections present and specific
- **Shallow** — has structure but some sections are vague
- **Incomplete** — missing required sections

### Check 4: AC Coverage

For each TC's metadata table, check the AC field:
- Does the referenced AC exist in the story?
- Is every story AC covered by at least one TC?
- Report story ACs that have no TC mapping

### Check 5: Priority and Automation Distribution

Verify the distribution makes sense:
- Core CRUD and data integrity scenarios should be `critical`
- Edge cases and secondary workflows should be `medium` or `low`
- All scenarios should have an automation classification
- Summary table counts should match actual TC counts

### Check 6: Structural Consistency

- TC-IDs follow `TC-{req}-{NN}` sequentially per requirement
- All TCs are grouped under their correct requirement heading
- No orphaned TCs (placed under wrong FR/NFR section)
- Story references use consistent format throughout
- Overview "Requirements covered" matches actual sections

### Check 7: Gap Analysis Quality

Review the Gaps section:
- Is every uncovered requirement listed?
- Does each gap have a justification (deferred, out of scope, dependency)?
- Are there silent omissions — requirements with no TCs and no gap entry?

## Output Format

```markdown
## Test Plan Completeness Review: {title}

### Summary

- Requirements covered: X/Y ({Z missing})
- Required boundaries with a planned case at the required tier: X/Y
- Required boundaries with an identified execution path: X/Y
- Required boundaries with a passing execution and result evidence: X/Y
- Wrong-tier cases: X; demonstrated boundary mismatches: Y
- Dependency-disclosure gaps: X
- Missing planning-evidence fields: X
- Owner gaps: X
- Test cases: X total (Y complete, Z shallow, W incomplete)
- AC coverage: X/Y story ACs mapped
- Structural issues: X found

The verdict evaluates planning completeness; it does not mean any cases passed.
Report execution results separately.

### Requirement Tracing

| Requirement | TCs | Status |
|-------------|-----|--------|
| FR-1: {desc} | TC-FR1-01, TC-FR1-02 | Covered |
| FR-2: {desc} | — | MISSING |
| NFR-1: {desc} | — | Gap (justified: pending OSAC-2921) |

### Integration Boundary Assessment

| Component / behavior / refs | Required tier and boundary | Owner | TCs / suite | Command or manual procedure / working directory / prerequisites | Real vs. faked | Execution status / evidence | Gap / follow-up | Status |
|-----------------------------|----------------------------|-------|------------|---------------------------------------------------------------|----------------|----------------------------|---------------|--------|
| {behavior and requirement refs} | {tier and boundary} | {DEV/QE} | {TCs and path} | {verified/proposed command or manual procedure; applicable cwd; prerequisites} | {dependencies} | {not run/blocked/passed and evidence} | {Jira URL or unresolved} | {status} |

### Test Case Assessment

| TC ID | Status | Issues |
|-------|--------|--------|
| TC-FR1-01 | Complete | — |
| TC-FR1-02 | Shallow | Expected Results restate AC without specifics |
| TC-FR7-06 | Complete | Placed under FR-13 section (structural issue) |

### Structural Issues

1. {TC-FR7-06 grouped under FR-13 instead of FR-7}
2. {"FR-7 (continued)" section breaks sequential ordering}

### Gap Analysis

| Gap | Justified | Notes |
|-----|-----------|-------|
| NFR-1 | Yes | Pending OSAC-2921, documented in Gaps section |
| FR-11 | No | Missing from testplan with no gap entry |

### Verdict

{PASS: all in-scope requirements have traceable cases or a justified gap with a
follow-up; every required boundary has a traceable case at the required tier;
required planning-evidence fields, owners, and real-versus-faked dependency
disclosures are present; there are no unaddressed evidence or owner gaps,
shallow or incomplete TCs, Rework vetoes, or structural issues. A justified gap
or follow-up ticket does not qualify a missing required boundary for PASS.}
{NEEDS WORK: list missing requirements or boundaries, including justified
required-boundary gaps, wrong-tier or demonstrated claimed-versus-actual
boundary mismatches, missing planning-evidence fields, dependency-disclosure or
owner gaps, unjustified or unassigned coverage gaps, shallow TCs, and structural
issues. A Rework veto always prevents PASS.}
```

## Notes

- This is a FOCUSED reviewer. Don't expand scope to design quality.
- Missing requirements are worse than shallow TCs. Flag missing first.
- The Gaps section is a positive signal — honest gap documentation
  with justification is acceptable. A gap for a required boundary still means
  NEEDS WORK until a case at the required tier exists; a follow-up ticket does
  not count as coverage. Silent omissions are not.
- A testplan with a Summary table but no detailed TCs is automatic NEEDS WORK.

$ARGUMENTS
