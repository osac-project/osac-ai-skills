# CI assessment mode

When the trusted CI caller explicitly selects this mode, return an internal
assessment object with exactly `scores`, `criterionNotes`, `summary`, `feedback`,
`findings`, and `policy`. Keep the existing five score/note keys and the three
finding arrays. Do not emit `verdict` or `total`; the trusted gate computes them
and writes the existing public `verdict.json` contract. Standalone scoring uses the
[public output format](../SKILL.md#output).

`policy` has exactly:

- `integrationRequired`: boolean, derived from the trusted workspace's
  `docs/INTEGRATION-TESTING.md`, each affected component's `AGENTS.md`
  touched-area map, and the approved PRD/design boundary requirements. Use
  these sources together: the shared guide establishes canonical tiers,
  common planning-evidence and ownership requirements, and the rule that a
  lower tier does not satisfy a higher-tier boundary; the touched-area map
  identifies which tiers and behavior-specific boundaries apply to changed
  behavior; an approved PRD/design can add explicit boundary requirements.
  Read the relevant component section of the shared guide to verify its suite
  boundaries and documented gaps, and map any component-specific tier label
  to exactly one canonical tier. Set this to `true` if any affected behavior
  or approved PRD/design requires a Component integration, Contract, or E2E
  boundary, including a component-specific tier mapped to one of those tiers.
  Set it to `false` only after reviewing the applicable sources and confirming
  that they require no such boundary (for example, Unit or Envtest only).
  Requiring a coverage matrix or citing the shared guide's tier taxonomy alone
  does not make integration coverage required. The shared guide and component
  maps are complementary: do not let either erase the other's requirements.
  If a required source is unavailable, disclose it and let the trusted caller
  block scoring for missing context. If sources disagree, name them in the
  notes and set this to `true` whenever any applicable map or approved
  PRD/design explicitly requires an integration tier; set it to `false` only
  after reviewing all required sources and confirming none requires one. Do
  not infer a tier from generic taxonomy or silently discard an explicit
  boundary requirement.
- `groundingUsable`: boolean; whether the plan identifies usable test-codebase
  source grounding, such as an existing suite/file or a clearly proposed test
  location. Set it true when that source is identifiable even if execution
  metadata (command, working directory, prerequisites, or execution status) is
  missing or ambiguous; those remain Grounding 1 evidence
  gaps. Set it false only when test-codebase source grounding is absent or
  unusable.
- `caps`: array, empty when no stated rubric cap applies. Each object contains
  `code`, `caseIds` (nonempty array of case or source-obligation references),
  `source` (the source section/map establishing the condition), and `detail`
  (specific observed missing evidence or mismatch).

Allowed cap codes are `boundary_mismatch` for a demonstrated required-tier or
real-versus-faked mismatch, `missing_required_case` for an absent required
boundary case, `unusable_grounding` for absent/unusable test-source grounding,
and `undisclosed_dependencies` when a required integration case leaves
real-versus-faked dependencies undisclosed. The latter is a Rework veto even
at a high total, regardless of `groundingUsable`; score Grounding 0 when that
case is also stub-only. Cite the case and the source obligation, and identify
the absent dependency disclosure. Ambiguous but present disclosure is a
Grounding 1 gap, not this veto.
If groundingUsable is false, supply the unusable_grounding cap with evidence.
Missing or ambiguous required-integration execution fields get Grounding 1;
integrationRequired then makes the trusted gate cap readiness at Revise.
Identify those fields in the Grounding note. A known wrong-tier/faked boundary
is the stronger boundary_mismatch veto.

Check case ownership separately from boundary conformance. Under the shared
ownership rule, Unit, Envtest, Component integration, and Contract cases belong
to the owning `[DEV]` story; deployed cross-component E2E cases belong to
`[QE]`. For an otherwise usable behavioral case, a missing work owner or one
that does not match its canonical tier scores Actionability 1; score 2 only
when every case has a present, tier-consistent owner. An owner gap alone never
scores Actionability 0. If the coverage row requires an owner, the same gap is
also a Grounding 1 evidence gap. It is not a boundary mismatch, does not invoke
the integration-boundary Rework veto, and must not be added as a separate
`policy.caps` item. A missing owner on a required integration row still counts
as missing Grounding evidence under the existing `integrationRequired` Revise
rule. State the affected case IDs and source in the notes; an explicit
unassigned-owner statement is honest gap disclosure but does not supply an
assigned owner or justify inventing a ticket.

Assess every condition; do not omit a cap to raise readiness. Optional formatting,
consistent local aliases, and valid uniform priority are not cap codes. Keep
planning evidence separate from execution results and name the actual cases and
source passages. Scores, notes and policy facts must agree. Internal assessments
are retained separately from the public verdict for diagnostics.
