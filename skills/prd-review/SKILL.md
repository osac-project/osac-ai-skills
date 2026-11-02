---
name: prd-review
description: |
  Review an OSAC PRD against template requirements, OSAC feature dimensions,
  persona coverage, and testability standards. Use when reviewing a PRD PR,
  preparing a PRD for submission, or self-reviewing before /prd:publish.
  Produces structured findings with rubric scores and actionable suggestions.

  Also trigger when user says "review this PRD", "check this PRD",
  "is this PRD ready", "review the requirements doc", or references a PRD
  file or PR.
metadata:
  version: "0.5.0"
---

# OSAC PRD Reviewer

## Overview

This skill reviews a PRD against a calibrated 0-2 rubric with hard pass/fail
thresholds.

## When to Use

- Self-reviewing a PRD before running `/prd:publish`
- Reviewing a PRD PR on `enhancement-proposals`
- Checking if a PRD is ready for the design phase
- After `/prd:revise` to verify improvements

## Input Detection

Detect what's being reviewed:

1. **PR URL or number** → Fetch the PRD content from the PR diff
2. **Local file path** → Read the PRD from disk (e.g., `enhancement-proposals/enhancements/<slug>/prd.md` or `.artifacts/prd/*/03-prd.md` for pre-publish drafts)
3. **No input** → Ask: "Which PRD should I review? Provide a PR number, file path, or Jira issue key."

### Fetching from PR

```bash
gh pr diff <N> --repo osac-project/enhancement-proposals
gh pr view <N> --repo osac-project/enhancement-proposals --json title,body,author
```

### Reading from artifact

```bash
ls .artifacts/prd/*/03-prd.md
```

## Load Context

Use `docs/` in OSAC checkouts or `reference/` in standalone CI workspaces.
Read relative to that root:

1. `agent-context/osac-dimensions.md` and `agent-context/review-patterns.md`
2. `ARCHITECTURE.md` and `personas.md` when available

If missing locally, follow both `.design/context/` forwarding files to the
full GitHub documents. Report inaccessible context.

## Scoring Rubric

### Context

A PRD describes WHAT the product must do and WHY — from the user's perspective.
A design document (enhancement proposal) describes HOW — architecture,
controllers, API fields, playbooks. PRDs should be written from the perspective
of a Product Manager, not an engineer.

### Persona Review Gate

Two persona checks apply below: missed or false consolidation between
closely-related personas is an Important finding, not a WHAT deduction, as
long as every canonical persona is covered; a non-canonical persona heading
is a Suggestion unless it displaces a required persona's story.

### Criteria (0-2 each, /10 total)

Score each criterion independently. For each, first state your reasoning,
then assign the score.

#### 1. WHAT — Clear user-facing need? (0-2)

Does the PRD describe a new or changed product capability — something that
requires building, not just writing content? A PRD whose sole deliverable is
documentation, example files, configuration samples, or other content with no
new platform capability is not an enhancement — it belongs in a Jira task, not
the PRD pipeline. Score 0 if there is no new product capability.

Does the PRD clearly describe what users can do or observe?

##### OSAC Dimensions Checklist

Using the loaded feature-dimensions context, also check whether the PRD
addresses the OSAC dimensions relevant to this feature:
- **Services**: Which services (BMaaS, CaaS, VMaaS, MaaS, Enclave) are in scope?
- **Personas**: Cloud Provider Admin, Cloud Infrastructure Admin, Tenant Admin, Tenant User — which are affected and how?
- **Cross-cutting dimensions** (tenant onboarding, inventory, provisioning, networking, storage, installation): addressed or explicitly out of scope where relevant?
- **Verification scope**: What must demonstrably work vs deferred; detailed test plan belongs in the EP
- **Documentation**: User-observable doc needs and workflow impact; detailed doc plan belongs in the EP
- **UI**: User-observable console needs and persona workflows; detailed UI design belongs in the EP
- **API resources**: For each in-scope service, affected API resources listed

##### Scoring

Not every dimension applies to every feature. Don't penalize for dimensions
that aren't relevant — but a PRD that names no personas or services has an
unclear WHAT.

Each affected persona must have at least one user story grouped under a
persona heading (e.g., `### Tenant User`). Mentioning a persona in prose
("Cloud Infrastructure Admins are affected") without a corresponding
`As a <persona>...` user story does not count — the reviewer cannot
evaluate what that persona can actually do.

Each user story must also explain why the persona wants the capability. The
`so that` clause should name a user goal, pain avoided, business outcome, or
decision enabled. If it only restates mechanics or expected state, it describes
WHAT without establishing WHY.

Personas may share a single heading and story when the capability is
genuinely identical for both (e.g., `### Tenant Admin / Tenant User`
with "As a Tenant Admin or Tenant User, I want..."). This satisfies
coverage for both named personas — do not require a separate heading per
persona when the PRD deliberately consolidates identical stories (see
`enhancement-proposals/guidelines/prd_guide.md`'s "Duplicated persona
stories" entry for the canonical rule this rubric is calibrated
against). Verify the merge is genuine, not just labeled that way: if the
combined story's outcome or constraints only actually hold for one of
the named personas (e.g., a shared "view quota" heading where one
persona sees only their own usage and the other sees the whole
organization's), treat the persona whose real need differs as
uncovered — a shared heading does not exempt the PRD from describing
what each named persona can actually do.

Equally, check the reverse failure: separate headings for closely-related
personas that should have been merged. If two persona-specific stories
differ only in the persona name and cosmetic wording — not in a
constraint, scope, or outcome actually stated in the source material —
this is a missed consolidation (apply the swap test from
`enhancement-proposals/guidelines/prd_guide.md`'s "Duplicated persona
stories" entry). Weigh this with particular scrutiny
for Cloud Provider Admin and Cloud Infrastructure Admin, whose canonical
roles already overlap heavily. Report as an Important finding (see
Right-Sized's "Flag regardless of score") rather than a WHAT deduction —
both personas are still covered, so WHAT itself isn't unclear.

A story heading that names something other than one of the four canonical
personas — most commonly an internal OSAC service (CaaS, BMaaS, VMaaS,
MaaS, Enclave) given its own "persona" story — does not count toward
persona coverage; see `enhancement-proposals/guidelines/prd_guide.md`'s
"Inventing a persona for an internal service" entry. Report as a
Suggestion unless it displaces or
crowds out a required persona's actual story, in which case treat that
persona as uncovered under the scoring below.

- 0 = Vague, unclear, or describes system internals rather than user outcomes. No personas or services identified, or no per-persona user stories.
- 1 = Ambiguous — need is partially clear but mixed with implementation, missing specifics, tautological user-story motivation, or missing affected personas. Or: user stories exist but some affected personas lack stories.
- 2 = Clear, specific, user-observable capabilities. Affected personas and services identified. Each affected persona has at least one user story.

See [calibration-examples.md § 1](references/calibration-examples.md#1-what--clear-user-facing-need) for W=0/1/2 worked examples, including the combined-persona-heading pattern.

#### 2. WHY — Business justification? (0-2)

Is there a clear reason this work matters — user pain, business need, or strategic goal?

- 0 = No justification, or circular reasoning ("we need X because we don't have X")
- 1 = Generic justification — plausible but no specific evidence (e.g., "users need this")
- 2 = Concrete justification — names the pain, quantifies impact, or ties to a strategic goal with a clear causal chain

Take stated evidence at face value. Search the entire PRD for evidence, not
just a dedicated section. User stories count only when their `so that` clauses
explain user/business motivation, not mechanics.

See [calibration-examples.md § 2](references/calibration-examples.md#2-why--business-justification) for Y=0/1/2 worked examples.

#### 3. User-Facing Focus — Free from design leakage? (0-2)

Does the PRD describe user-observable outcomes without prescribing implementation?
A PRD defines WHAT and WHY. The design document (enhancement proposal) defines HOW.

User-facing surfaces (CLI commands, UI pages, API resource names visible to
users) are WHAT. Internal architecture (controllers, reconcilers, playbooks,
env vars, finalizers, internal conditions) is HOW.

##### OSAC Platform Vocabulary

Referencing these by name is acceptable context, not design leakage:
- Platform: OpenShift, Kubernetes, Hosted Control Planes
- Services: BMaaS, CaaS, VMaaS, MaaS, Enclave
- Resources (user-facing): ClusterOrder, ComputeInstance, Tenant, VirtualNetwork, Subnet, SecurityGroup, PublicIPPool, PublicIP, StorageClass
- Networking: OVN, Multus, NetworkClass
- Storage: VAST, CSI
- Auth: Keycloak, OPA
- Tools: kubectl, grpcurl, Helm

##### Scoring

Naming platform technologies is not automatically prescriptive. But mandating
which internal component solves a problem, or describing controller logic,
finalizer behavior, or playbook parameters IS design leakage.

- 0 = PRD reads like a design document — names controllers, describes reconciliation logic, specifies internal API fields or conditions, references playbook parameters
- 1 = Mostly user-focused but some design details leak through — names an internal component or describes a behavior only observable by reading code
- 2 = Describes only user-observable outcomes; implementation details are absent or limited to platform vocabulary

See [calibration-examples.md § 3](references/calibration-examples.md#3-user-facing-focus--free-from-design-leakage) for UF=0/1/2 worked examples, including the illustrative-example-vs-internal-state pair (see `enhancement-proposals/guidelines/prd_guide.md`'s "A narrow exception: illustrative examples" entry for the canonical rule this pair is calibrated against).

**Smell tests:**
- "Could a PM verify this by using the product?" — if no, it's design leakage
- "Would this statement change if we swapped the implementation?" — if no, it belongs in the PRD; if yes, it's design
- "Does this name something only visible in code?" — if yes, it's design leakage

#### 4. Right-Sized — Focused and economical scope? (0-2)

Is the PRD scoped to a coherent set of capabilities, and does it treat
that scope economically? This criterion has three equally-weighted failure
modes — bundling unrelated work, padding a single coherent capability with
more content than it needs, and collapsing several increments of one
capability into a single PRD. Any one caps the score; a PRD is not
"right-sized" just because it avoids the other two.

**Bundling:** When multiple capabilities are present, test independence:
could each ship on its own and provide value? Capabilities that cannot
function without each other are one feature regardless of how many user
stories they span.

**Verbosity:** A focused PRD still fails here if it restates the same
point across sections, includes content the template doesn't call for, or
states specifics with no traceable source. Long PRDs don't get read —
there are no awards for a long PRD.

**Increment sizing:** Every PRD builds on a baseline — what a persona can
already do end to end in this capability domain. Take it from the PRD's
Problem Statement, not from your own expertise; state it in the review so
the author can contest it; then ask whether the scope is one deliverable
step past it or several collapsed. When the baseline is nothing, that
step is a walking skeleton: the thinnest end-to-end path a named persona
can use, plus the ability to see whether it worked.

- 0 = Bundles 3+ independent capabilities that serve different personas or purposes, OR pads a single capability so heavily (restated stories, non-template sections, invented specifics) that a reader cannot extract the actual scope without cutting through the padding, OR collapses several increments past the baseline into one PRD.
- 1 = Bundles 1-2 separable capabilities that could ship independently, OR is scoped to one coherent capability but treats it uneconomically (the same requirement restated more than once, non-template content that duplicates another section), OR is one step past the baseline plus extras that could be deferred without weakening it.
- 2 = Focused and economical — capabilities require each other to function, the scope is one step past the baseline, and the document states that scope once, without restatement or padding.

**Read [calibration-examples.md § 4](references/calibration-examples.md#4-right-sized--focused-and-economical-scope) before scoring this criterion** — it carries R=0/1/2 worked examples for all three modes and the rules for establishing a baseline.

For bundling, recommend restructuring as a Jira Outcome with individual
Features that can be prioritized, estimated, and delivered independently.
For verbosity, name the specific padding to cut rather than a general
"make this shorter" note. For increment sizing, name the one step
explicitly — which stories constitute it — and move the rest to follow-up
Features under the same Outcome; the author needs to see what remains,
not only what is cut.

**Flag regardless of score.** The following are Important findings (see
Severity Classification) whenever present, independent of the numeric
Right-Sized score — they can appear even in a PRD that otherwise scores
well, and each should be called out with its specific location rather
than folded silently into the score:

- Content outside `enhancement-proposals/guidelines/prd_template.md`'s
  sections — most commonly a Risks section, a standalone Acceptance
  Criteria section, or a Terminology/Glossary section restating concepts
  already defined in `osac-dimensions.md`. Recommend trimming or moving
  the content to the design document.
- Numeric thresholds or SLAs (response times, retry counts, timeouts)
  that are not traceable to the source Jira issue or a clarification
  answer. Recommend sourcing the number or marking it `TBD`.
- Near-duplicate or restated user stories *within* the same persona
  (not just across personas — see the WHAT criterion's persona
  consolidation rule for the cross-persona case). Recommend merging into
  one story.
- A **compensating mechanism** — user-facing surface existing only to
  soften a platform limitation the PRD records as an Assumption.
  Recommend deferring both.

Report at most 3 instances per bullet. If more exist, name the clearest
1-2 with their location and summarize the rest in one sentence ("and 4
more near-duplicate stories across User Stories") — this list should stay
proportionate to the PRD's scope, the same standard it holds the PRD to.

#### 5. Testability — Verifiable requirements? (0-2)

Can the requirements be verified by a PM or QA engineer using the product?

- 0 = Requirements describe activities or system internals that can't be tested from the outside
- 1 = Some requirements are testable, others are vague or describe internal behavior
- 2 = Every requirement and acceptance criterion can be verified by using the product

See [calibration-examples.md § 5](references/calibration-examples.md#5-testability--verifiable-requirements) for T=0/1/2 worked examples.

### Pass/Fail

- **PASS**: Total >= 7/10 AND no zeros on any criterion
- **FAIL**: Total < 7 OR any zero (automatic fail regardless of total)

A single zero is an automatic fail because it signals a fundamental problem
(e.g., the PRD is a design doc, or requirements are untestable). The author
must fix zero-scored criteria before resubmission. Exception: if WHAT
scores zero because the work is content-only (docs, examples, config
samples), the recommendation is to track it as a Jira task, not resubmit
as a PRD.

## Output Format

Present findings as a structured review:

```markdown
## PRD Review: {title}

**Baseline:** {what a persona can already do end to end in this domain, or
"nothing"} → {is this PRD one step past that, or several?}. Correct this if
it's wrong — the Right-Sized score depends on it.

### Rubric Scores

| Criterion | Score | Notes |
|-----------|-------|-------|
| WHAT (clear need) | X/2 | {explain what need is described and how clearly; note persona/dimension coverage} |
| WHY (justification) | X/2 | {cite the specific evidence found or note its absence} |
| User-Facing Focus | X/2 | {note any design leakage or lack thereof} |
| Right-Sized | X/2 | {assess scope — independent capabilities? economical treatment of scope? one step past the stated baseline?} |
| Testability | X/2 | {which requirements are verifiable by using the product?} |
| **Total** | **X/10** | **PASS / FAIL** |

### Verdict: {PASS / FAIL}

{1-2 sentence assessment. If fail, name the zero-scored criteria first.}

### Findings

#### Critical (must fix — zero-scored criteria)
1. {finding with specific section reference, quote the problematic text, suggest a user-focused rewrite}

#### Important (should fix)
1. {finding with specific section reference and suggestion}

#### Suggestions (nice to have)
1. {finding}

### Criterion Details

{For each criterion, explain the score with specific quotes from the PRD.
Show what's good and what needs improvement. For design leakage, quote the
offending text and show what a user-focused rewrite would look like.}
```

## Confidentiality Check

Before scoring, scan the entire PRD for references to specific customer
names, program names, or engagement names. The `enhancement-proposals`
repository is public — any such reference is a **Critical** finding
regardless of rubric scores. The PRD must describe capabilities in terms
of what is needed, not who requested it. Customer-specific language should
be abstracted into generic stakeholder or deployment-scenario descriptions
(e.g., "a sovereign-cloud deployment" rather than naming the program or
customer).

## Severity Classification

- **Critical**: Any zero-scored criterion. Also: missing required sections, no personas identified, PRD reads like a design document. Also: any reference to a specific customer name, program name, or engagement name — the enhancement-proposals repo is public.
- **Important**: Score of 1 on any criterion. Also: vague Out of Scope boundaries, weakly testable user stories or requirements, tautological user-story motivation, scope creep signals, requirements stated as generic capabilities without explicit use cases, content outside the PRD template's sections, unsourced numeric thresholds/SLAs, near-duplicate user stories within the same persona, compensating mechanisms for a documented platform limitation (see Right-Sized's "Flag regardless of score").
- **Suggestion**: Style improvements, additional Out of Scope detail, deeper risk analysis, more specific metrics.

## Notes

- Score based on what's in the PRD, not what you think should be there — if information is genuinely unavailable, "TBD" markers are acceptable
- Compare against the PRD template at `enhancement-proposals/guidelines/prd_template.md` for structural compliance
- See `enhancement-proposals/guidelines/prd_guide.md` for the author-facing guidance this rubric is calibrated against
- A PRD that names specific controllers, playbooks, env vars, or internal conditions has design leakage. This is the most common failure mode — score it under User-Facing Focus
- If the PRD was produced by `/prd:draft`, check that clarification locked decisions are reflected

$ARGUMENTS
