---
name: test-plan-score
metadata:
  version: "0.3.0"
description: |
  Score an OSAC test plan against the 5-dimension rubric (Specificity,
  Grounding, Scope Fidelity, Actionability, Consistency). Produces
  structured verdict with per-dimension scores and actionable findings.
  Grounding checks per-component integration tier, boundary, suite, and
  real-versus-faked dependencies against OSAC touched-area guidance.

  Trigger when a testplan.md is ready for review, or when the user asks to
  score or review a test plan.
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

For OSAC changes, use the per-component coverage matrix required by the shared
planning guidance to connect each behavior to its tier, boundary, owner, suite,
and execution evidence. If the matrix is absent, compare the test cases with the
touched-area maps and report the missing evidence. Do not treat a test case as
proof of a boundary unless its documented tier and dependencies actually
exercise that boundary. Each row must identify the owning component, touched
behavior and requirement/interface references; required tier and boundary;
owner and test-case IDs; existing suite/file or proposed location; verified
test command and working directory, or a concrete manual procedure; if a shell
command or working directory does not apply, state N/A and why; environment
prerequisites;
real-versus-mocked/omitted
dependencies; execution status; and any unavailable suite or unresolved
prerequisite with its follow-up Jira URL or an explicit no-owner/ticket
statement.
If no owner or ticket exists, state that the gap is unresolved without inventing
a ticket.

Verify existing suites and commands against repository guidance. Label a new
location or unverified command as proposed. Record `not run` or `blocked`
honestly; neither is a passing result. A reported pass needs evidence of the
command or manual procedure and observed result. Keep planned coverage, an identified execution path, and a passed execution
distinct in the score and feedback.

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

Score each dimension independently. For each:
1. Quote specific evidence from the testplan
2. Assign the score (0, 1, or 2)
3. Note what would raise the score

Before assigning Grounding, compare the plan's component and behavior rows with
the affected components' touched-area maps and the relevant component sections
of `docs/INTEGRATION-TESTING.md`. For every required matrix row,
record the owning component and behavior, requirement/interface references,
test-case IDs, claimed tier, owner, required boundary, named suite or proposed
location, verified command or concrete manual procedure, applicable working
directory or justified N/A, environment prerequisites, execution status, and
which dependencies run for real versus being mocked, stubbed, or
omitted. Record a follow-up Jira URL for each known unavailable suite or
unresolved infrastructure prerequisite, or state that no owner/ticket exists.
Check that any component-specific tier label maps to the canonical tier in the
shared guidance, and that the row's owner matches the documented tier ownership.
Each coverage row must select one canonical tier; slash-separated alternatives
or multiple candidate tiers are ambiguous and do not identify an execution path.
A manual case may identify its procedure instead of a shell command and explain
why a working directory does not apply. Supplemental static/build checks may be
listed separately as non-test validation, but are not a test tier and cannot
satisfy a Unit, Envtest, component-integration, Contract, or E2E requirement.
Only compare boundaries that apply to the changed behavior; a documented
provider gap for unrelated behavior is not a failure. A proposed suite location
must be labelled proposed and must not be described as an existing runnable
suite. Verify an existing command against the repository file that defines it;
label an unverified or invented command as proposed, and do not count it as an
identified runnable path.

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
component.
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

`Not run` or `blocked` is a valid execution status when stated accurately; it
does not count as a passing test. A claimed pass without command or manual procedure and observed-result
evidence is unsubstantiated and must be reported as not passed. Absent or
incomplete test-codebase grounding without a demonstrated mismatch, missing
execution detail, or a missing required boundary caps the verdict at Revise.
These are evidence gaps, not Rework triggers. Only a wrong-tier claim or
demonstrated mismatch between the claimed boundary and described real-versus-
faked setup triggers the Rework veto. Missing or ambiguous dependency disclosure
is an evidence gap, not a veto.

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
- The owner matches the test tier's documented work ownership
- The test approach identifies the suite and verified command or a concrete
  manual procedure, plus applicable working directory or justified N/A for a
  manual case, and environment prerequisites without presenting proposed details
  as verified
- Execution status distinguishes planned, blocked, not run, and passed evidence
- Priority and Automation fields are set

Missing matrix evidence fields are Grounding gaps; do not score Actionability 0
solely for those omissions.

**0** = Missing steps or assertions, or no usable behavioral test scenario
**1** = Structure present but some TCs lack specifics
**2** = Every TC fully specified with preconditions, steps, results

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

- **Ready** (8-10): Test plan is implementation-ready
- **Revise** (5-7): Address gaps, re-score
- **Rework** (0-4 or any zero): Fundamental issues — zero on any
  dimension is automatic Rework

### Integration-boundary Rework veto

After scoring, apply this veto before returning the verdict. Return **Rework**
regardless of total when a required integration case:

- claims a tier below or different from the boundary required by the affected
  component's touched-area map; or
- claims a required real or deployed boundary while the described test
  setup substitutes a mock/stub or omits a component that boundary requires.

Name the affected test-case IDs and cite the map or planning-evidence row that
establishes the required boundary. Missing or ambiguous dependency
disclosure is an evidence gap, not the Rework veto. An absent case for a
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
    "grounding": "...",
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

## Notes

- Score what's in the testplan, not what you think should be there
- Grounding is about test infrastructure, not production code
- A plan with strong specificity but zero grounding is still Rework
- The Gaps section is a positive signal — honest gap reporting is
  better than silent omission

$ARGUMENTS
