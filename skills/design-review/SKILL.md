---
name: design-review
description: |
  Review an OSAC design document against template requirements, architectural patterns,
  and historical reviewer expectations. Use when reviewing a design PR, preparing a design for
  submission, or self-reviewing a draft before requesting feedback. Produces rubric scores
  and structured findings with severity levels and actionable suggestions.

  Also trigger when user says "review this design", "check this design document",
  "is this design ready", "review PR on enhancement-proposals", or references a PR
  on osac-project/enhancement-proposals.
metadata:
  version: "0.4.0"
---

# OSAC Design Document Reviewer

## Overview

This skill reviews a design document against the OSAC design template at
`enhancement-proposals/guidelines/design_template.md` and author guide at
`enhancement-proposals/guidelines/design_guide.md`, architectural conventions, and patterns learned from past reviewer feedback.
Design documents describe HOW — architecture, APIs, implementation. User stories
and persona coverage belong in the PRD (`prd.md`), not the design.
It uses calibrated 0-2 scoring across 4 dimensions with hard pass/fail
thresholds — matching the Org Pulse dashboard assessment format.

## When to Use

- Reviewing a PR on `osac-project/enhancement-proposals`
- Self-reviewing a draft design before submitting
- Preparing a revision in response to reviewer feedback
- Checking if a design is ready for merge
- After `/design:revise` to verify improvements

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the design content from the PR diff
2. **Local file path** → Read the design from disk (e.g., `enhancement-proposals/enhancements/<slug>/design.md`)
3. **No input** → Ask: "Which design should I review? Provide a PR number, URL, or file path."

### Fetching from PR

```bash
gh pr diff <N> --repo osac-project/enhancement-proposals
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

## Load Context

Use `docs/` as the context root in an OSAC checkout, or `reference/` in a
standalone CI review workspace. Read these paths relative to that root:

1. `agent-context/osac-dimensions.md` — services, personas, relevant dimensions
2. `agent-context/review-patterns.md` — review expectations and historical examples
3. `ARCHITECTURE.md` and `personas.md` — technical and persona grounding

If unavailable locally, follow the canonical GitHub links in
`.design/context/osac-dimensions.md` and `.design/context/review-patterns.md`.
Read the full linked documents, not just those forwarding files. For standalone
workspaces, use [architecture](https://github.com/osac-project/osac/blob/main/docs/ARCHITECTURE.md)
and [personas](https://github.com/osac-project/osac/blob/main/docs/personas.md).
Report inaccessible context. Follow networking/Wizard references when applicable.

## Scoring Rubric

### Context

A design document describes HOW a feature will be implemented — architecture,
API design, controller logic, provisioning workflows. It builds on a PRD (WHAT/WHY)
and provides enough detail for engineering to estimate, plan, and implement.

### Template Completeness

Before scoring, note any structural issues. These feed into dimension scores
rather than blocking the review — the agent must always produce scores for
all 4 dimensions.

- YAML frontmatter: title, authors, creation-date, last-updated, tracking-link (full URL), prd (relative path to PRD)
- These required sections apply to designs drafted in the simplified format. For a design that predates it, score the structure it was written with and do not flag missing simplified-format sections
- Required sections, in order: Today and with this design, How it works, Definitions, one section per step, Guard Rails, Security, Where the code goes, API (one numbered entry per affected interface first), Alternatives, Not in this design
- Test Plan is not a design section: the detailed test plan is published as `testplan.md` and reviewed separately
- Conditionally required: UX Alignment, when the design changes the UI, or a matching `@temp-api` file exists in `osac-ux/libs/ui-components/src/api/v1/`
- PRD reference: the `prd:` frontmatter field or an explicit link to `prd.md` must be present — user stories and persona coverage belong in the PRD, not the design
- Placeholder-only sections (`TBD` with no other content, or a lone `TODO:` line with no other content) count against the relevant dimension score
- Sections that are genuinely N/A must explain why — silence is a gap

### Criteria (0-2 each, /8 total)

Score each criterion independently. For each, first state your reasoning,
then assign the score. Missing or placeholder-only sections that are relevant
to a criterion pull that criterion's score toward 0.

#### 1. Architecture (0-2)

Are the technical decisions sound and consistent with OSAC patterns?

Check:
- [ ] Owner reference (`osac.openshift.io/owner-reference`) and tenant isolation (`osac.openshift.io/tenant`) annotations present on all new resources
- [ ] API conventions per `osac/fulfillment-service/docs/API.md`: standard object shape (`id`, `Metadata`, `<Type>Spec`, `<Type>Status`), spec/status ownership, declarative intent-based design (no imperative methods), naming conventions
- [ ] Spec contains only desired state (user-controlled); status contains only observed state (system-controlled)
- [ ] Controller patterns: finalizer → status update → provisioning lifecycle
- [ ] Conditions used for lifecycle state (preferred over phase enums for new resources)
- [ ] Maps avoided in CRDs (prefer lists of named subobjects); pluggable architectures preferred over hardcoded implementations
- [ ] Dependencies between components identified with ordering; genuine cross-repo impacts (e.g., `osac-test-infra`) enumerated separately from in-repo cross-component sequencing within `osac`
- [ ] Integration with existing services described
- [ ] Breaking changes called out with migration strategies
- [ ] Terminology defined upfront and used consistently throughout

- 0 = Fundamental architectural misalignment — missing tenant isolation, wrong patterns, no dependency analysis
- 1 = Core patterns followed but gaps — some conventions missed, integration partially described, inconsistent terminology
- 2 = All OSAC patterns followed, dependencies clear, integration well-described, terminology consistent

##### Calibration Examples

- A=0: Design introduces new CRDs without tenant annotation, uses direct DB access instead of gRPC, proto schemas don't follow standard object shape, doesn't mention which components or repos need changes.
- A=1: Design follows controller patterns and has tenant isolation, proto schemas use standard object shape but mix spec/status ownership (e.g., user-modifiable fields in status), doesn't describe interaction with osac-aap for provisioning.
- A=2: Design follows all conventions, describes the full resource hierarchy with owner references, enumerates cross-component changes within `osac` (fulfillment-service proto + osac-operator controller + osac-aap role) plus any genuine cross-repo impact (e.g., `osac-test-infra`), and defines terminology upfront.

#### 2. Feasibility (0-2)

Is the implementation realistic, specific, and proportional to the scope?

Check:
- [ ] Implementation details are specific — names data structures, specifies error codes, defines validation rules
- [ ] Proto schemas included for new resources (at least key fields, types, constraints)
- [ ] API section gives one numbered entry per affected interface, so test plans can map cases to them. Padding the list to reach a count is a gap
- [ ] No hand-waving on hard parts (e.g. vague phrases like `handle edge cases appropriately` or `implement as needed`)
- [ ] Effort is proportional to scope
- [ ] Workflow covers all lifecycle operations (create, get, list, update, delete)
- [ ] Error handling and failure modes described
- [ ] For a stateful or billing-like design, Guard Rails states the invariants: atomic writes, duplicate prevention, ordering, isolation, and crash/restart/restore/failure behavior. Missing Guard Rails on such a design is a gap
- [ ] Risks are specific technical risks with concrete mitigations
- [ ] Trade-offs against the chosen approach appear in Risks or Alternatives (the simplified template has no Drawbacks section)

Length and plain language, for a design in the simplified format (scored with this criterion):
- [ ] At most 200 content lines, tables included (YAML frontmatter, Mermaid diagrams and code blocks excluded)
- [ ] At most 2,000 words, tables included
- [ ] No sentence over 25 words
- [ ] No semicolon chains or "unless" clauses
- [ ] No inline source markers (`[PRD: ...]`, `[Locked: D{N}]`, `[Research: §...]`)
- [ ] N/A sections are one line
- [ ] No repetition across sections

A simplified-format design over 200 content lines cannot score 2 on this criterion.

- 0 = Vague implementation — no proto schemas, hand-waving on hard parts, generic risks ("things might break")
- 1 = Reasonable detail but gaps — some lifecycle operations missing, risks somewhat generic, thin error handling
- 2 = Key decisions specific and complete (schemas, APIs, lifecycle ops, guarantees), risks with concrete mitigations, no code-level walkthroughs

**Calibration examples:**

- F=0: Example of vague implementation: `The controller will handle provisioning appropriately` with no detail on what provisioning means, no proto schema, and risks like "implementation might be complex."
- F=1: Design includes proto schemas for the main resource and describes create/get/list, but update and delete flows are "TBD." Risks mention "race conditions" without specifying which ones or how to mitigate.
- F=2: Design includes full proto schemas with field types and validation annotations, describes all CRUD lifecycle operations with error codes, identifies specific risks ("concurrent subnet allocation may cause CIDR overlap") with concrete mitigations ("use optimistic locking with resource version").

#### 3. Scope (0-2)

Is the design right-sized with clear boundaries, covering relevant personas and dimensions?

Check:
- [ ] Summary is 3-5 sentences: what's added, why it's valuable, key capabilities
- [ ] Goals are user-visible outcomes, not implementation tasks
- [ ] Non-goals are specific about what's explicitly out of scope and why
- [ ] No scope creep signals ("and related functionality", "all necessary changes")
- [ ] Alternatives section includes at least one real alternative with rationale for rejection
- [ ] Design references its PRD (`prd:` frontmatter or link to `prd.md`) and addresses relevant personas through architectural decisions

Using the loaded feature-dimensions context, also check cross-cutting dimension
coverage — for each dimension relevant to this design, the design must address it or
explicitly defer. Silence on a relevant dimension is a gap.

- 0 = Scope unbounded, no PRD reference, vague non-goals, no alternatives, relevant dimensions ignored
- 1 = Boundaries mostly clear, PRD referenced but some relevant dimensions not addressed, non-goals could be more specific
- 2 = Clear boundaries, PRD referenced, specific non-goals, real alternatives, relevant dimensions addressed or deferred

**Calibration examples:**

- S=0: Design has no PRD reference, no non-goals, and says "Alternatives: none considered." Storage dimension is relevant but not mentioned.
- S=1: Design references a PRD but non-goals say "advanced features are out of scope" without specifying which. Networking dimension acknowledged but not addressed. Cloud Provider Admin perspective not covered in workflow description.
- S=2: Design references its PRD, non-goals explicitly exclude auto-scaling and multi-region ("deferred to v0.2, see OSAC-XXXX"), alternatives section compares two real approaches with trade-offs, and all relevant dimensions from osac-dimensions.md are addressed or explicitly deferred.

#### 4. Testability (0-2)

Does the design give a separate test plan enough to map cases to behavior?

The detailed test plan is published as `testplan.md` and reviewed separately.
Do not require a Test Plan section in the design.

Check:
- [ ] Interfaces are numbered, or the API section states `N/A: {reason}` and the design changes no interface. For a design that predates the simplified format, an equivalent mapping by interface name is enough
- [ ] Lifecycle operations and state transitions are described
- [ ] Error paths and failure behavior are described
- [ ] Validation rules and limits are stated
- [ ] Observable outcomes are specific enough to test

- 0 = Behavior is too vague to test. No interface list or lifecycle detail.
- 1 = Main paths are described. Error paths, limits, or interface mapping are missing.
- 2 = Numbered interfaces (or a justified `N/A`), lifecycle, error paths, and limits are specific enough to map test cases.

**Calibration examples:**

- T=0: "The controller handles provisioning" with no interfaces, states, or error paths.
- T=1: Interfaces are listed but error paths and limits are "TBD".
- T=2: Interfaces 1-4 map to create, attach, detach, and delete. Each has error paths and limits, so test cases can reference them directly.

### Pass/Fail

- **PASS**: Total >= 5/8 AND no zeros on any criterion
- **FAIL**: Total < 5 OR any zero (automatic fail regardless of total)

A single zero is an automatic fail because it signals a fundamental problem
(e.g., no interface list when the design changes interfaces, or architectural misalignment). The author must fix
zero-scored criteria before resubmission.

## Output Format

Present findings as a structured review:

```markdown
## Design Review: {title}

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| Architecture | X/2 | {pattern compliance, dependency clarity, terminology} |
| Feasibility | X/2 | {implementation depth, proto schemas, risk quality} |
| Scope | X/2 | {boundary clarity, persona coverage, dimension coverage} |
| Testability | X/2 | {interface mapping, lifecycle and error-path coverage} |
| **Total** | **X/8** | **PASS / FAIL** |

### Verdict: {PASS / FAIL}

{1-2 sentence assessment. If fail, name the zero-scored criteria first.}

### Findings

#### Critical (must fix — zero-scored criteria)
1. {finding with specific section reference, quote the problematic text, suggest improvement}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Criterion Details

{For each criterion, explain the score with specific quotes from the design.
Show what's good and what needs improvement.}

### Cross-cutting Dimensions (from osac-dimensions.md)

| Dimension | Relevant? | Status |
|-----------|-----------|-----------|
| {name} | Yes / No | Addressed / Deferred / Gap |

### Comparison with Similar Designs
{Reference 1-2 merged designs from the design reference library in review-patterns.md
that cover similar scope. Note what this design does well or could learn from them.}
```

## Confidentiality Check

Before scoring, scan the entire design document for references to specific
customer names, program names, or engagement names. The
`enhancement-proposals` repository is public — any such reference is a
**Critical** finding regardless of rubric scores. The design must describe
capabilities in terms of technical requirements and deployment scenarios,
not who requested them. Customer-specific language should be abstracted
into generic descriptions (e.g., "a sovereign-cloud deployment" rather
than naming the program or customer).

## Severity Classification

- **Critical**: Any zero-scored criterion. Also: missing tenant isolation on new resources, fundamental architectural misalignment, breaking changes without migration path, security gaps. Also: any reference to a specific customer name, program name, or engagement name — the enhancement-proposals repo is public.
- **Important**: Score of 1 on any criterion. Also: incomplete sections, missing personas, unclear workflow, vague non-goals, generic risks, thin implementation details, relevant dimension neither addressed nor deferred.
- **Suggestion**: Style improvements, deeper alternatives discussion, more specific test plan, documentation polish.

## Notes

- Score based on what's in the design, not what you think should be there
- Use `osac-dimensions.md` to decide relevance per dimension — skip Networking for a storage-only design. When a dimension is relevant, require address-or-defer — silence is a gap
- Reference merged designs in `enhancement-proposals/enhancements/` for calibration on structure only. Length is not a quality signal. Shorter is better when the decisions are covered.
- Push for specificity: "handle errors" is not a mitigation; "retry with exponential backoff, circuit-break after 3 failures" is
- The review process requires consensus from all stakeholders — flag sections that would likely trigger stakeholder questions

$ARGUMENTS
