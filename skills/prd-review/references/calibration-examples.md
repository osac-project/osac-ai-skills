# PRD Review — Calibration Examples

Worked scoring examples for each criterion in [SKILL.md](../SKILL.md).
Read the section for the criterion currently being scored.

## 1. WHAT — Clear user-facing need?

- W=0: "Ship example YAML files and a README in the repo so admins can load them with `osac create -f`." — the API and CLI already exist; the deliverable is content (example files + docs), not a product capability. This is a Jira task, not an enhancement.
- W=0: "Implement CSI driver installation via AAP playbook on ClusterOrder Ready event" — describes a system action, not a user need. No persona mentioned.
- W=0: A PRD states "Cloud Infrastructure Admin and Cloud Provider Admin personas are affected" in the problem statement and references personas in functional requirements, but has no User Stories section and no `As a <persona>...` stories. Personas are named but the PRD never describes what each persona can do — the reviewer cannot evaluate completeness.
- W=1: "Storage should be available on CaaS clusters" — right direction but vague. Which clusters? What does "available" mean to the user? How would a tenant know? No personas identified.
- W=1: "Tenant users can create and manage secrets" — right direction but generic. What secrets? SSH keypairs? OIDC client secrets? Cluster kubeconfigs? Cloud-init credentials? Without explicit use cases, reviewers can't evaluate whether the scope is right.
- W=1: "As a Tenant User, I want to pause a running VM so that its execution freezes while RAM and application state are retained" and "As a Tenant User, I want to resume a paused VM so that its applications continue from retained state" — the capabilities are observable, but the motivation is tautological: the `so that` clauses restate what pause and resume mechanically do. The stories still do not explain the user's goal, pain avoided, or business outcome (for example, saving cost while preserving debugging state, pausing maintenance-sensitive workloads, or avoiding a long application restart).
- W=2: "When a CaaS cluster is provisioned and ready, tenants can create persistent volumes using StorageClasses without manual configuration. Tenants can see whether storage is ready on their cluster. Cloud Provider Admins can see storage readiness across all tenant clusters." — clear, observable, specific, personas identified.
- W=2: "Tenant users can retrieve cluster kubeconfig and admin password via the secrets API. Tenant admins can store OIDC client secrets for IDP integration. Tenant users can store cloud-init credentials containing passwords for VM provisioning." — names the concrete artifacts and scenarios, not just the generic capability.
- W=2: A single `### Tenant Admin / Tenant User` heading with "As a Tenant Admin or Tenant User, I want persistent storage to be available on my CaaS cluster when it is ready, so that I can run stateful workloads without waiting for manual configuration." — one story, two personas, because the capability is identical for both. Full coverage; do not dock for "missing" separate Tenant Admin and Tenant User headings.
- W=1: A `### Tenant Admin / Tenant User` heading with "As a Tenant Admin or Tenant User, I want to view resource quota usage" — but Tenant Admins actually need org-wide quota visibility across all Tenant Users, while Tenant Users only need their own usage. The heading labels this a consolidation, but the two personas' real needs differ. Treat the Tenant Admin persona as uncovered — the shared heading doesn't describe what a Tenant Admin can actually do.
- Important finding, not a WHAT score change (missed consolidation): separate `### Cloud Provider Admin` and `### Cloud Infrastructure Admin` headings, one reading "...so that I don't need to query the inventory backend directly" and the other "...so that correlation happens without my manual intervention" — different wording, but neither outcome traces to a persona-specific need in the source material; this is an invented distinction papering over what the swap test would call duplication. Both personas remain covered (no WHAT deduction), but recommend consolidating into `### Cloud Provider Admin / Cloud Infrastructure Admin`.
- Suggestion, not a WHAT score change (invented persona): a `### CaaS (Internal Service Consumer)` heading with "As the CaaS system, I want..." — CaaS is a service from the vocabulary table, not one of the four canonical personas; the same finding applies to a dedicated heading for BMaaS, VMaaS, MaaS, or Enclave. Recommend moving this content to Dependencies; only escalate if it displaced a real persona's story.

## 2. WHY — Business justification?

- Y=0: "Add storage support for CaaS clusters" with no explanation of why this matters or what happens without it.
- Y=0: A feature listing 11 Definition of Done bullets and 10 user stories but zero explanation of why this capability matters, who is asking for it, or what happens without it.
- Y=0: A PRD whose Problem Statement says only that OSAC lacks VM pause/resume, while User Stories say tenants want to pause so execution freezes and resume so applications continue. The stories describe the requested behavior, but neither the Problem Statement nor the stories explains why tenants need this capability or what user/business pain remains without it.
- Y=1: "Tenants cannot run stateful workloads on CaaS clusters without manual storage configuration." — describes the gap but no impact.
- Y=2: "CaaS clusters are provisioned without persistent storage. Tenants cannot run stateful workloads until someone manually configures storage, and there is no visibility into whether storage is available. This blocks CaaS adoption for any tenant with stateful workloads." — names the pain, describes the consequence, ties to adoption.
- Y=2: "Tenants running VM workloads need a way to suspend execution during maintenance or cost-control windows without losing in-memory application state. Today they must keep the VM running and pay for active compute, or stop it and accept restart time and lost volatile state." — names the user pain, tradeoff, and consequence.
- Y=2: "Multi-tenant GPU clusters require InfiniBand tenant isolation to prevent cross-tenant traffic interference. Without isolation, tenants sharing a fabric can observe each other's RDMA traffic, which is a security and compliance blocker for sovereign AI deployments." — specific pain, concrete consequence, ties to strategic goal.

## 3. User-Facing Focus — Free from design leakage?

- UF=0: "When a ClusterOrder reaches phase=Ready and the owning Tenant has StorageBackendReady=True, the storage controller invokes osac-create-tenant-cluster-storage with provisioning_target=hcp_data_plane." — names controllers, internal conditions, playbook parameters.
- UF=0: "The storage controller places a finalizer on each ClusterOrder where storage was set up. On deletion, it triggers osac-delete-tenant-cluster-storage to remove StorageClasses, VolumeSnapshotClasses, and CSI Secret from the CaaS cluster." — describes finalizer behavior and cleanup implementation.
- UF=1: "Storage is automatically provisioned on CaaS clusters when they become ready. The controller uses AAP to install the CSI driver." — good user outcome, but "the controller uses AAP" is an implementation detail.
- UF=2: "When a CaaS cluster is provisioned and ready, persistent storage is automatically available on the cluster without manual configuration." — pure user outcome.
- UF=2: "Tenants can see storage readiness on their ClusterOrder status." — ClusterOrder is user-facing platform vocabulary, readiness is observable.
- UF=2: "Tenants specify port mappings in the format `8080:80` (host:container) when creating a ComputeInstance." — a single, minimal illustrative example of a value the user types; it conveys the user-facing format without describing how the system implements it. Do not dock a PRD for including one example like this.
- UF=0: "The reconciler records the parsed mapping in the ComputeInstance status as `conditions: [{type: PortMappingApplied, hostPort: 8080, containerPort: 80}]`." — reads like a design doc even though it's framed as "an example": the condition type and internal field names are only visible in code, not to the user. An example is not automatically exempt from design leakage — apply the same smell tests to it as to any other statement.

## 4. Right-Sized — Focused and economical scope?

**Increment-sizing banding:** 0 = collapses several increments, burying the one deliverable step among capabilities that depend on it working first; 1 = one step plus a few capabilities that could be deferred without weakening it; 2 = one step plus only what it cannot work without.

**Establishing the baseline.** The baseline is what a persona can already do
end to end in this capability domain — not what components exist, and not
what the PRD promises. Read it from the PRD's own Problem Statement, which
usually declares it in the first sentence ("OSAC CaaS manages creation,
scaling, and deletion, but provides no managed path for upgrading" states a
baseline of nothing for upgrades). State the baseline in the review so the
author can contest it; a wrong baseline invalidates the score, and only the
author may know of shipped work the PRD failed to mention.

Judge the baseline by capability, not component: a component with many
merged EPs can still be entering a new domain, and an API letting a user
*declare* a property is not prior art for *changing* it. Prior EPs in the
same component — including ones this PRD lists as dependencies — do not by
themselves establish a baseline. Ask what the PRD makes newly possible, then
check whether anything shipped already does a version of that.

When the baseline is nothing, the one step is a **walking skeleton** — the
thinnest end-to-end path plus the ability to see whether it worked. When
there is a baseline, the same question is narrower but not weaker: the step
must be usable on its own, not a slice that only pays off once the next two
PRDs land. Do not push the other way either: a step a persona cannot
complete — initiating an upgrade with no way to see whether it worked — is
not a smaller increment, it is an unusable one. One step, not half of one.

Raise this mode in the first review pass — scope feedback delivered after
rounds of line-level review discards work that was competently done.

- R=0: "Add storage support, networking policy enforcement, and cluster monitoring for CaaS." — three independent capabilities for different concerns.
- R=0: "East-west connectivity: Ethernet fabric provisioning, InfiniBand tenant isolation, NVLink partition management, VPC peering, and cross-fabric validation." — five independent capabilities that each serve different fabric types and could ship independently. This should be split into individual features per fabric type.
- R=1: "Add CaaS cluster storage and add tenant storage quota management." — storage provisioning and quota management serve different workflows (day-1 vs day-2) and could ship independently.
- R=0: A PRD for one narrow capability (e.g., exposing one existing inventory field through the API) padded with a `Terminology` section defining platform terms already in `osac-dimensions.md`, a standalone `Acceptance Criteria` section duplicating User Stories content, a `Risks` section, and a `Milestone Scoping` section — none of which exist in `prd_template.md` — such that the actual one-capability scope is buried under four non-template sections a reader must cut through to find it.
- R=1: A PRD covering one coherent capability (e.g., exposing one existing inventory field through the API) but restating the same story two or three times across near-identical Acceptance Criteria bullets, defining terms already covered by `osac-dimensions.md`, and stating numeric SLAs with no traceable source (a pattern that appeared in `enhancement-proposals#169`) — the underlying scope is fine, but the document is padded well past what that scope needs.
- R=2: "CaaS cluster storage: automatic provisioning, readiness visibility, and cleanup on deletion." — provisioning without visibility is incomplete; cleanup without provisioning is meaningless. Tightly coupled.
- R=2: `OSAC-1332-caas-cluster-storage` (47 lines) — one coherent capability, each section states its content once, no restatement across sections.
- R=0 (increment sizing, baseline is nothing): `OSAC-1415-cluster-upgrade-caas` as merged — the first PRD to deliver anything in the upgrades domain, scoped as a mature upgrade product across 15 Tenant User stories: version discovery, risk review and explicit risk acknowledgment, a cancellation window, upgrade history, version-divergence notifications, and EOL limited-support state, alongside the initiate-and-monitor core. Nothing in it is independent of "cluster upgrade," so it does not fail on bundling — it fails because the domain had no shipped baseline and the PRD scoped the finished version of it. Note the prior EP it depends on, `OSAC-1269-cluster-version-api`, gave CaaS a way to *declare* a cluster's version; that is not prior art for *changing* one, and does not make this a mature domain. This merged before the first-increment test existed and is the case it was written from — cite it as a scope calibration, not as a criticism of its author or reviewers.
- R=2 (increment sizing, baseline is nothing): The skeleton the same PRD could have started from — two stories: a Tenant User initiates an upgrade to a platform-allowed target version, and observes whether it is running, succeeded, or failed. A tenant can upgrade a cluster and see the outcome. Note the merged version's fourth state, `pending`, is absent here — it exists only to create the cancellation window, so it defers with cancellation. Everything else in the merged version becomes a follow-up Feature, sequenced once something works end to end.
- R=0 (increment sizing, baseline exists): With the upgrade skeleton shipped — a tenant can upgrade a cluster and see the outcome — a follow-up PRD scoping upgrade history, version-divergence notifications, skew warnings, and EOL limited-support state. The baseline is no longer nothing, so this is not a walking-skeleton finding, but four separately valuable and separately deferrable steps are still collapsed into one PRD. Recommend an Outcome with one Feature per step, sequenced.
- R=2 (increment sizing, baseline exists): The same baseline, a PRD scoping upgrade history alone — a Tenant User can see which version transitions occurred and their outcomes. Valuable the day it ships, and it does not depend on the divergence or EOL work landing first.
- Important finding, not a Right-Sized score change (compensating mechanism): `OSAC-1415`'s "brief cancellation window during which the upgrade remains pending" exists because the PRD's own Assumptions record that OpenShift cannot cancel a running upgrade. The PRD invents a pending state to make cancellation possible rather than deferring cancellation along with the constraint — new user-facing surface in a domain with no working baseline yet.

## 5. Testability — Verifiable requirements?

- T=0: "The controller reconciles within 30 seconds" and "The finalizer is removed after cleanup completes" — not observable by users.
- T=1: "Tenants can create PVCs on CaaS clusters" (testable) mixed with "The AAP job succeeds and StorageClasses are confirmed" (internal).
- T=2: "A tenant can create a PVC using a StorageClass on their CaaS cluster within 5 minutes of the cluster becoming ready." — observable, measurable, testable.
