---
name: test-plan-score
metadata:
  version: "0.7.3"
description: |
  Score an OSAC test plan against the 5-dimension rubric (Specificity,
  Grounding, Scope Fidelity, Actionability, Consistency). Produces
  structured verdict with per-dimension scores and actionable findings.
  Grounding checks per-component integration tier, boundary, suite, and
  real-versus-faked dependencies against OSAC touched-area guidance.

  Required on relevant enhancement-proposals PRs that change a test plan,
  design, or its PRD. Also trigger when the user requests test-plan scoring.
---

# OSAC Test Plan Scorer

Score a `testplan.md`. The testplan groups behavioral test cases by PRD requirement,
each with structured metadata, preconditions, steps, and expected results.

## Testplan Structure

The input testplan follows this structure:

```
# Testplan — {OSAC-key}

## Overview
- Feature: {key} — {title}
- Total test cases: {N}
- Requirements covered: {N} of {M}

## Test Cases

### FR-1: {requirement description}

#### TC-FR1-01: {scenario title}

| Story | AC | Priority | Automation |
|-------|-----|----------|------------|
| {Jira key} | AC-1, AC-2 | critical | automated |

##### Preconditions
- {system state}

##### Steps
1. {action}

##### Expected Results
- {observable outcome}

### NFR-1: {requirement description}
...

## Gaps
- {uncovered requirements with justification}

## Summary
| Metric | Count |
| Total test cases | {N} |
| Critical / High / Medium / Low | ... |
| Automated / Manual | ... |
```

For OSAC changes, use the shared planning guide, affected component maps, and
approved PRD/design boundaries together. The guide defines canonical tiers and
shared evidence/ownership rules; maps define behavior-specific boundaries. A
matrix or tier taxonomy alone does not require integration coverage. If the
matrix is absent, report missing evidence against the maps. Each row names the
component and behavior, requirement, tier/boundary, owner and cases, suite or
proposed location, verified command or concrete manual procedure, prerequisites,
real-versus-mocked dependencies, execution status, and follow-up for unavailable
work. Explain N/A, label proposals, and do not invent owners or tickets. Do not
claim a boundary the setup does not exercise. Verify commands and observed
results; planned coverage, an execution path, and a passing run are distinct.

## Input Detection

1. **Local file path** — `enhancements/<slug>/testplan.md`
2. **PR number** — fetch from PR diff
3. **No input** — search:
   ```bash
   find enhancement-proposals/enhancements -name "testplan.md" -type f
   ```

## Load Context

Before scoring, read:

1. **testplan.md** — the plan being scored
2. **design.md** — `enhancements/<slug>/design.md` (for Scope Fidelity)
3. **prd.md** — `enhancements/<slug>/prd.md` (for requirement coverage)
4. **Scoring rubric** — [scoring rubric](references/scoring-rubric.md)
5. **Test strategy** — [test strategy](references/osac-test-strategy.md)
6. **Test infra reference** — [test infra reference](references/osac-test-infra-reference.md)
7. **Operator test patterns** — [operator test patterns](references/osac-operator-test-patterns.md)
8. The OSAC workspace's `docs/INTEGRATION-TESTING.md` planning-evidence section
   and the relevant component sections for tier names, commands, boundaries,
   and documented coverage gaps
9. Each affected component's `AGENTS.md` touched-area map and integration-test
   guidance

If the workspace guidance or a component map is unavailable, say so in the
findings. Do not invent a required tier or count an unverified boundary as
covered.

## Scoring Process

Use the shared guide and affected maps together, preserving explicit approved
PRD/design boundaries. A matrix or tier taxonomy alone does not require
integration coverage. Strategy/reference documents provide examples, not
execution gates; use current guidance over stale examples and disclose conflicts.

For Grounding 1, identify a missing or ambiguous execution-row field, omitted
required case, or unsupported existing-source claim. A fully disclosed proposed
location/helper is not an unsupported existing-source claim. For Consistency 1,
identify an actual count, ID, grouping or internal contradiction; optional extra
columns/audit tables, consistent local aliases and a valid uniform priority do
not alone justify a deduction. Risk-priority advice is not an invented PRD AC.

Score each dimension independently. For each:
1. Quote specific evidence from the testplan
2. Assign the score (0, 1, or 2)
3. Note what would raise the score

Before assigning Grounding, compare each required row with approved PRD/design
boundaries, affected maps, the shared guide, and cited repository sources.
Verify its canonical tier, owner, boundary, case IDs, suite/location,
command or manual procedure, prerequisites, status, dependencies, and gaps or
follow-up. A row must select one tier, not alternatives. Label unverified paths
as proposed; manual cases need an actionable procedure and justified N/A.
Static/build checks are not test tiers. Assess only boundaries for changed
behavior; unrelated provider gaps are not failures.

### Dimension 1: Specificity (0-2)

Does each test case name concrete scenarios with specific inputs and outputs?

Look for:
- TC-IDs with specific API calls, parameters, field values
- Concrete expected results (status codes, field values, state transitions)
- Specific error types (InvalidArgument, FailedPrecondition, NotFound)
- Each Expected Result states a specific observable outcome, not a restatement
  of the acceptance criteria

**0** = Vague steps/results. "test CRUD", "verify lifecycle"
**1** = Names scenarios but inputs/outputs lack specifics
**2** = Exact API calls, concrete field values, precise error types

### Dimension 2: Grounding (0-2)

Is the plan grounded in the actual test codebase and, when required, the
component integration boundary?

For each applicable row, check the component's touched-area map and the shared
planning-evidence guidance. Each row must name its owning component and
behavior, requirement/interface references,
tier, boundary, test-case IDs, existing suite/file or a clearly proposed
location, verified or explicitly proposed command or concrete manual procedure,
applicable working directory or justified N/A, environment prerequisites,
execution status, and which dependencies are real
versus mocked/stubbed/omitted. For an unavailable suite or unresolved
prerequisite, it must link the owning Jira follow-up or say no owner/ticket
exists. Also look for the existing framework, fixtures, helpers, and test
patterns that ground the test in the repository.

When the map requires a Contract or deployed E2E boundary, apply the same
boundary-evidence check to that row. Confirm component-specific tier labels map
to exactly one canonical tier in the shared guidance; a list of alternative
tiers is ambiguous. Manual cases may use a concrete procedure instead of a
shell command and state why a working directory does not apply. Static/build
checks may be listed separately as supplemental non-test validation; they do
not satisfy any test-tier requirement.

**0** = A required case has a demonstrated tier or boundary mismatch: it
claims a tier that conflicts with the touched-area map, or claims a real/deployed
boundary while its described setup demonstrably fakes or omits a required
component, or a required integration case is stub-only and leaves real-versus-
faked dependencies undisclosed.
**1** = Test-codebase grounding is absent or incomplete without a demonstrated
boundary mismatch, or at least one applicable row is missing or ambiguous about
its tier, boundary, owner, case IDs, suite/location, command or manual procedure,
applicable working directory or justified N/A for a manual case, prerequisites,
execution status, real-versus-faked dependencies, or documented gap/follow-up.
No usable test-codebase grounding by itself is an evidence gap: score 1, not 0.
**2** = Every applicable row contains the required planning evidence; existing
commands are verified, proposed paths/commands are labelled, manual paths are
actionable, gaps have a follow-up or are explicitly unresolved, and the plan
points to the relevant
test codebase or existing test pattern.

This is a planning gate. New tests need not already exist or have passed. A
clearly proposed case with a complete execution row can receive Grounding 2.
An explicitly unresolved owner/ticket satisfies gap disclosure; do not invent
a requirement for an assigned person or filed issue. A missing required case
is different from a planned case whose harness still needs implementation.
Do not infer priority requirements absent from the PRD/design.

`Not run` or `blocked` is a valid execution status when stated accurately; it
does not count as a passing test. A claimed pass without command or manual procedure and observed-result
evidence is unsubstantiated and must be reported as not passed. Absent or
incomplete test-codebase grounding without a demonstrated mismatch, missing
execution detail, or a missing required boundary caps the verdict at Revise.
These are evidence gaps, not Rework triggers. A wrong-tier claim, a demonstrated
mismatch between claimed and actual dependency boundaries, or a required
integration case leaving real-versus-faked dependencies undisclosed triggers
the Rework veto. Stub-only required integration with undisclosed dependencies
scores Grounding 0. Ambiguous but present dependency disclosure scores 1;
it is distinct from absent disclosure, which invokes the veto.

If the touched-area map says the change needs only Unit or Envtest coverage,
do not lower Grounding just because the plan has no component-integration case.
If the map requires an integration case and the plan omits it, report a coverage
gap; do not count a lower-tier case as satisfying it. A missing required
boundary caps the verdict at Revise, unless another rule yields Rework.
When integration coverage is required, Grounding 1 caps the verdict at Revise;
only complete boundary evidence can support Ready. If no integration case is
required, do not penalize the plan for omitting an integration row; absent or
unusable test-codebase grounding without a demonstrated mismatch still caps the
verdict at Revise.

Note: referencing production code (proto fields, API methods) is NOT
grounding. Grounding means the test codebase, not the production codebase.

### Dimension 3: Scope Fidelity (0-2)

Does the test scope match the design/PRD scope?

Cross-reference:
- Every FR/NFR heading in the testplan traces to a PRD requirement
- Every PRD requirement has at least one TC
- The Overview's "Requirements covered: N of M" claim is accurate
- Gaps section honestly documents uncovered requirements
- No extra scope (TCs for features not in this design)

**0** = Major requirements missing, or tests for wrong feature
**1** = Most covered but some gaps or extra scope
**2** = Every requirement mapped, gaps documented, scope exact

### Dimension 4: Actionability (0-2)

Can an engineer implement the tests from the plan?

For each TC check:
- Preconditions specify concrete system state
- Steps are numbered with specific API calls and parameters
- Expected Results state observable outcomes (not restatements of ACs)
- Story/AC metadata links to the implementing story
- The work owner is present and matches the test tier's documented ownership
- The test approach identifies the suite and verified command or a concrete
  manual procedure, plus applicable working directory or justified N/A for a
  manual case, and environment prerequisites without presenting proposed details
  as verified
- Execution status distinguishes planned, blocked, not run, and passed evidence
- Priority and Automation fields are set

Missing matrix fields are Grounding gaps, not Actionability 0. For an otherwise
usable case, a missing or tier-mismatched owner scores Actionability 1; score 2
requires a present, tier-consistent owner on every case. Owner gaps do not cause
Actionability 0 or the integration-boundary Rework veto. Apply Grounding and
`integrationRequired` rules separately; see `references/ci-assessment.md`.

**0** = A case has no steps, has neither expected results nor assertions, or
has no usable behavioral test scenario
**1** = Steps and expected results are present, but some cases have vague or
unobservable outcomes, missing parameters, or an otherwise usable case has a
missing or tier-mismatched work owner
**2** = Every TC fully specified with preconditions, steps, results, and a
present work owner consistent with its canonical tier

### Dimension 5: Consistency (0-2)

Are all sections internally consistent?

Check:
- TC-IDs follow `TC-{req}-{NN}` with sequential numbering per requirement
- All TCs are grouped under their correct FR/NFR heading
- Story references use consistent format (all Jira keys or all local IDs)
- Priority values are valid: critical, high, medium, low
- Automation values are valid: automated, manual
- Summary table counts match actual TC count
- Overview "Requirements covered" matches sections present

**0** = Contradictions, misplaced TCs, broken numbering
**1** = Minor issues (one misplaced TC, small count mismatch)
**2** = All sections align, IDs sequential, counts accurate

## Verdict

### CI assessment mode

Trusted CI callers select the internal contract in
[CI assessment mode](references/ci-assessment.md). Return scores, evidence and
explicit policy facts; trusted code emits the public verdict. Standalone
scoring uses the output format below. Preserve every rubric cap and veto in
both modes.

### Public verdict rules

- **Ready** (8-10): Test plan is implementation-ready
- **Revise** (5-7): Address gaps, re-score
- **Rework** (0-4 or any zero): Fundamental issues — zero on any
  dimension is automatic Rework

Calculate the verdict from the final scores, then apply only the explicit
rubric caps and boundary veto below. A total of 8-10 with no zero is Ready
unless a stated cap applies. A nonzero Consistency 1 or an improvement
suggestion alone does not cap that result at Revise. If returning Revise for
8-10, name the applicable cap, affected case and missing required evidence.
Return one final score per dimension; numeric scores, notes, total and verdict
must agree.

### Integration-boundary Rework veto

After scoring, apply this veto before returning the verdict. Return **Rework**
regardless of total when a required integration case:

- claims a tier below or different from the boundary required by the affected
  component's touched-area map; or
- claims a required real or deployed boundary while the described test
  setup substitutes a mock/stub or omits a component that boundary requires; or
- leaves real-versus-faked dependencies undisclosed.

Name the affected test-case IDs and cite the map or planning-evidence row that
establishes the required boundary. Absent dependency disclosure invokes this
veto; ambiguous but present disclosure is a Grounding 1 evidence gap. An absent case for a
required boundary caps the verdict at Revise; it is not the veto.
Do not apply the veto to unrelated provider gaps or to changes whose
touched-area map requires only a lower tier. Keep the existing `verdict.json`
schema; record a veto in `criterionNotes.grounding` and `findings.critical`.

## Output

Write `verdict.json`:

```json
{
  "verdict": "Revise",
  "scores": {
    "specificity": 2,
    "grounding": 1,
    "scope_fidelity": 2,
    "actionability": 2,
    "consistency": 1
  },
  "total": 8,
  "criterionNotes": {
    "specificity": "...",
    "grounding": "Grounding 1 with integrationRequired=true caps the 8-point plan at Revise: TC-FR4-01 is the required component-integration case, but its execution row omits the command (verified or explicitly proposed) and working directory.",
    "scope_fidelity": "...",
    "actionability": "...",
    "consistency": "..."
  },
  "summary": "One sentence overall assessment",
  "feedback": "2-3 sentences of actionable feedback",
  "findings": {
    "critical": ["..."],
    "important": ["..."],
    "suggestions": ["..."]
  }
}
```

This matches the org-pulse test plan data schema and the
PRD/design review verdict format.

## Required CI gate

Enhancement-proposals CI invokes this scorer for every affected plan, including
an unchanged plan whose PRD or design changed. A new or edited design requires
a plan: an affected enhancement that has a design but no test plan is recorded
as an unscored affected plan missing required context and fails the aggregate
check, as does removing or renaming the only test plan. PRD-only work without
a design and unrelated changes are not applicable; untouched legacy designs
are not retroactively required to add a plan. A PR that changes no enhancement
PRD, design, or test plan resolves to an explicitly recorded Not-applicable
result, never a silent vacuous pass; an empty affected-plan set cannot skip a
required plan.

Only a valid **Ready** verdict permits merge. A high numeric total cannot
override evidence caps or integration-boundary vetoes in the scoring rubric.
Keep the five-dimension `verdict.json` contract. Missing required context,
invalid model output, service errors, and an unscored affected plan block the
gate; a previous comment or label is not a passing result for the current PR.

The caller publishes one aggregate `Test Plan Score` check on the exact PR
head SHA and retains each plan's verdict and feedback. All affected plans must
be Ready. Re-score on PR updates or an authorized `/test-plan-score` retry.
A `/test-plan-respond` revision requires a fresh score; it cannot pass the gate
by itself. Completeness review remains diagnostic after Revise or Rework.

Read the authoritative PRD, design, rubric and references plus the trusted
OSAC checkout's integration guidance, affected component maps and cited test
sources. The caller records the source commit SHAs. If required evidence is
unavailable, disclose the gap instead of claiming it was verified. Plan
readiness does not mean the planned tests have executed successfully.

## Notes

- Score what's in the testplan, not what you think should be there
- Grounding is about test infrastructure, not production code
- A demonstrated Grounding mismatch scores 0 and triggers Rework. No usable
  test-codebase grounding by itself scores 1 and caps the verdict at Revise.
- The Gaps section is a positive signal — honest gap reporting is
  better than silent omission

$ARGUMENTS
