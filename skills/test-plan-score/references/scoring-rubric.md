# Test Plan Scoring Rubric

Test plans are scored on 5 dimensions, 0-2 each, for a total of 0-10.
This matches the Org Pulse dashboard scoring format used across
PRD Review, Design Review, and Test Plan Review.

## Testplan Format

Testplans group behavioral test cases (TC-FR1-01, TC-NFR2-01) under PRD
requirement headings, with structured metadata tables, preconditions,
numbered steps, and concrete expected results.

## Verdicts

- **Ready** (8-10): Test plan is implementation-ready
- **Revise** (5-7): Address gaps, re-score
- **Rework** (0-4 or any zero): Fundamental issues

When integration coverage is required, Grounding 1 caps the verdict at
**Revise**; only complete boundary evidence can support **Ready**. If no
integration case is required, do not penalize the plan for omitting an
integration row. However, absent or unusable test-codebase grounding without a
demonstrated mismatch still caps the verdict at **Revise**.
If a required integration boundary has no case, report the gap and cap the
verdict at **Revise**; a lower-tier case does not fill that gap. A follow-up
ticket records ownership but does not satisfy the boundary or permit **Ready**.

### Integration-boundary Rework veto

After scoring, return **Rework** regardless of the total if a required
integration case claims a tier below or different from the affected component's
touched-area map, or describes a real-versus-faked setup that demonstrably does
not exercise the required boundary, or leaves real-versus-faked dependencies
undisclosed. Name the test-case IDs and cite the map or planning-evidence row.
Absent disclosure invokes the Rework veto; ambiguous but present disclosure is
a Grounding 1 evidence gap capped at Revise. A missing case
for a required boundary is a coverage gap and cannot receive Ready. Do not apply
the veto to unrelated provider gaps or to changes whose touched-area map
requires only a lower tier.

## Dimensions

### 1. Specificity (0-2)

**Does each TC name concrete scenarios with specific inputs and outputs?**

- 0 = Vague: "test CRUD operations", "verify resource lifecycle"
- 1 = Names scenarios but inputs/outputs lack specific values
- 2 = Exact API calls, concrete field values, precise error types

**Calibration:**
- S=0: Steps say "Create a DiskImage" with Expected Results "it is created successfully"
- S=1: Steps name the gRPC method but Expected Results say "returns the correct response"
- S=2: Steps: "Call `DiskImages/Create` with source_type=REGISTRY, source_ref='quay.io/containerdisks/fedora:41', guest_os_family=LINUX, architecture=[AMD64]" / Expected Results: "Response status 200 OK, Response contains DiskImage with non-empty `id`, `metadata.creation_timestamp` set, `spec.lifecycle` = AVAILABLE"

Each Expected Result should state a specific observable outcome (status code,
field value, error type), not a restatement of the acceptance criteria.

### 2. Grounding (0-2)

**Is the plan grounded in the actual test codebase and required component
integration boundaries?**

For every required coverage-matrix row, check the component's touched-area map,
the relevant `docs/INTEGRATION-TESTING.md` section for tier/command/boundary,
and the shared planning-evidence guidance. The row must name its tier,
owning component and `[DEV]`/`[QE]` work owner, touched behavior,
requirement/interface references, boundary, test-case IDs, existing suite/file
or clearly proposed location, verified or explicitly proposed command or
concrete manual procedure, applicable working directory or justified N/A,
environment prerequisites,
execution status, and which relevant dependencies are real versus mocked,
stubbed, or omitted. For unavailable suites or unresolved prerequisites, it
must link the owning follow-up Jira issue or state that no owner/ticket exists.
Also check for test frameworks, fixtures, helpers, and existing test patterns.

Each coverage row must select one canonical tier. Slash-separated alternatives
or multiple candidate tiers are ambiguous. A manual case may identify its
procedure instead of a shell command and explain why a working directory does
not apply. Supplemental static/build checks may be listed separately as
non-test validation, but are not a test tier and cannot satisfy a Unit, Envtest,
component-integration, Contract, or E2E requirement.

- 0 = A required case has a demonstrated tier or boundary mismatch: it claims
  a tier that conflicts with the touched-area map, or claims a real/deployed
  boundary while its described setup demonstrably fakes or omits a required
  component, or a required integration case is stub-only and leaves real-versus-
  faked dependencies undisclosed
- 1 = Test-codebase grounding is absent or incomplete without a demonstrated
  boundary mismatch, or at least one applicable row is missing or ambiguous
  about its tier, owner, boundary, case IDs, suite/location, command or manual
  procedure, applicable working directory or justified N/A for a manual case,
  prerequisites, execution status, real-versus-faked dependencies, or
  documented gap/follow-up. No usable test-codebase grounding by itself is an
  evidence gap: score 1, not 0.
- 2 = Every applicable row contains the required planning evidence; existing
  commands are verified, proposed paths/commands are labelled, manual paths are
  actionable, gaps have a follow-up or are explicitly unresolved, and the plan
  points to the relevant test codebase or existing test pattern

`Not run` or `blocked` is a valid status when stated accurately, but is not a
passing result. A claimed pass without command or manual procedure and observed-result
evidence is unsubstantiated and must be reported as not passed. Absent or
incomplete test-codebase grounding without a demonstrated mismatch, missing
required execution detail, or a missing required boundary caps the verdict at
Revise. These are evidence gaps, not Rework triggers. A wrong-tier claim, a
demonstrated mismatch between claimed and actual dependency boundaries, or a
required integration case leaving real-versus-faked dependencies undisclosed
triggers the Rework veto. Stub-only required integration with undisclosed
dependencies scores Grounding 0. Ambiguous but present disclosure scores 1;
absent disclosure invokes the veto.

If the map requires only Unit or Envtest coverage, do not lower Grounding for
having no component-integration case. If an integration requirement has no
case, report a coverage gap, cap the verdict at Revise, and do not count a
lower tier as satisfying it. If no integration case is required, absent or
unusable test-codebase grounding without a demonstrated mismatch still caps
the verdict at Revise.

**Important:** Referencing production code (proto fields, API methods, error
types) is NOT grounding. Grounding means the test infrastructure — where
and how tests run, not what they test.

**Calibration:**
- G=0: A required integration case is shown to use only a stub and leaves
  real-versus-faked dependencies undisclosed; this is a demonstrated boundary
  mismatch and triggers Rework.
- G=0: A required deployed integration case claims it proves persistence,
  but its setup replaces the receiving service and database with mocks; this
  is a demonstrated boundary mismatch.
- G=1: No usable test-codebase grounding is provided (for example, detailed
  API calls with no test-framework, file, fixture, or helper references), and
  no required-boundary mismatch or undisclosed required-integration dependency
  is demonstrated.
- G=1: "E2E tests using pytest in osac-test-infra" (names codebase and framework)
- G=2: Every applicable row contains the required planning evidence. For
  example:
  ```text
  TC-<ID> | owner: <[DEV]/[QE] owner> | tier/boundary: <one canonical tier
  and required boundary from the touched-area map> | behavior/requirement/
  interface refs: <references> | suite/location: <existing file or clearly
  proposed path> | command/procedure: <verified or explicitly proposed command,
  or concrete manual steps> | working directory: <path or justified N/A> |
  prerequisites: <environment prerequisites> | status: <execution status> |
  dependencies: <named dependencies marked real/mocked/stubbed/omitted, matching
  the required boundary> | gap/follow-up: <owning Jira URL or no owner/ticket> |
  grounding refs: <test framework, fixture/helper, and existing test pattern>
  ```

### 3. Scope Fidelity (0-2)

**Does the test scope match the PRD/design scope — no more, no less?**

- 0 = Major requirements have no TCs, or TCs cover a different feature
- 1 = Most requirements covered but some gaps or extra scope
- 2 = Every FR/NFR mapped to TCs, gaps documented, scope exact

**What to check:**
- Overview's "Requirements covered: N of M" is accurate
- Every FR/NFR heading in the testplan traces to a PRD requirement
- Gaps section documents uncovered requirements with justification
- Honest gap reporting with justification scores higher than silent omission

### 4. Actionability (0-2)

**Can an engineer implement the tests from the plan without guessing?**

- 0 = Missing steps or assertions, or no usable behavioral test scenario
- 1 = Structure present but some TCs lack specific parameters or assertions
- 2 = Every TC specifies preconditions, numbered steps with parameters, and concrete expected results

Also verify that each case has an owner consistent with its required tier. A
missing or mismatched owner is an actionability gap; it does not trigger the
integration-boundary Rework veto by itself.
Missing matrix evidence fields are Grounding gaps; do not score Actionability
0 solely for those omissions.
Also verify that the implementation path names a suite and verified command or
a concrete manual procedure, plus an applicable working directory or
justified N/A for a manual case, environment prerequisites, and honest execution
status. Mark unverified commands and new
locations as proposed; do not present them as existing runnable coverage.

**Calibration:**
- A=0: "Test DiskImage functionality" with no steps or expected results
- A=1: TCs have steps and results but omit concrete request parameters or
  independently observable assertions
- A=2: "Preconditions: Authenticated as Cloud Provider Admin,
  fulfillment-service running. Steps: 1) Call DiskImages/Create with
  source_type=REGISTRY... Expected: Response status 200 OK, DiskImage
  with non-empty id"

Fixture, framework, file, and existing-test references are Grounding
evidence. Their absence does not lower Actionability.

### 5. Consistency (0-2)

**Are all sections internally consistent and aligned?**

- 0 = Contradictions between sections, broken ID scheme, misplaced TCs
- 1 = Minor issues (one misplaced TC, small count mismatch)
- 2 = All sections align, IDs sequential, counts accurate

**What to check:**
- TC-IDs follow `TC-{req}-{NN}` with sequential numbering per requirement
- All TCs grouped under their correct FR/NFR heading
- Story references use consistent format (all Jira keys or all local IDs)
- Priority values: critical, high, medium, low
- Automation values: automated, manual
- Summary table counts match actual TC count in the document
- Overview "Requirements covered" matches sections actually present
