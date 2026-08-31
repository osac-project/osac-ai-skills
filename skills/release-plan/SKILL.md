---
name: release-plan
description: "Generate a forward-looking release plan for an OSAC version — shows what the platform will deliver, cumulative capabilities across all prior versions, customer requirements coverage, and use-case cards. Use when asked for a release plan, developer preview plan, or version roadmap."
metadata:
  version: "0.4.0"
---

# Release Plan

Generate a structured JSON report showing what an OSAC version will deliver — the default and only output unless the user asks for more. Also generate companion HTML and/or markdown reports, but only if explicitly requested. Shows cumulative capabilities across ALL prior versions (0.1, 0.2, +0.3 style), customer requirements coverage, and cumulative use-case breakdowns with the target version's additions highlighted and customer driver tags.

The JSON output is the machine-readable form consumed by the Org Pulse dashboard's Release Plan view (`org-pulse` releases module) — it must contain the full report content, not a summary of it. See Step 6 for the schema.

**CRITICAL**: Use `jira` as the jira binary (must be on PATH). All `list` commands use `--plain --no-headers`. Do NOT use `--no-input` on `list` or `view`.

**CRITICAL — FILENAMES**: Always include date AND time in output filenames. Get the current time using `date +%Y-%m-%d-%H%M` and use it in every output filename generated. Never use date-only filenames — this causes overwrites on multiple runs per day. Example: `OSAC-0.3-release-plan-2026-08-19-1435.json` (always generated), plus `OSAC-0.3-release-plan-2026-08-19-1435.md` and/or `OSAC-0.3-release-plan-2026-08-19-1435.html` only if the user asked for them.

**IMPORTANT**: Only features with resolution "Done" appear as completed in prior versions. Fix versions are tracked at the **Feature level only** (not epics). Do not query epics for fix versions.

## Input

Accept two arguments:
1. **Target version** (required) — the version to plan (e.g., `0.3`)
2. **Prior version** (optional) — the immediately preceding version (defaults to one step back, e.g., `0.2` for `0.3`)

The skill automatically queries ALL versions before the target to build the full cumulative history.

**Output format**: By default, generate only the JSON report — it is the primary, machine-readable output. Only generate the markdown and/or HTML reports in addition if the user explicitly asks for them (e.g., "also give me the HTML", "make the markdown too").

## Workflow

### Step 1: Query Features for Target and All Prior Versions

Fetch features for the **target version** (open + closed):
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status != Closed" --plain --no-headers
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<TARGET>' AND status = Closed AND resolution = Done" --plain --no-headers
```

Fetch features for **each prior version** using different rules depending on how far back:

**N-1 (the immediately preceding version)** — include ALL features regardless of status (Closed, In Progress, Review, New). These are expected to land before the target version ships:
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<N-1>'" --plain --no-headers
```

**N-2 and older** — include only completed features (Closed + resolution = Done). These versions have already shipped; incomplete items never landed:
```bash
jira issue list --project OSAC -q "type = Feature AND fixVersion = '<N-2_OR_OLDER>' AND status = Closed AND resolution = Done" --plain --no-headers
```

For example, for a 0.3 report: query 0.2 (N-1) with ALL statuses, query 0.1 (N-2) with Closed+Done only.
For a 0.4 report: query 0.3 (N-1) with ALL statuses, query 0.1 and 0.2 (N-2 and older) with Closed+Done only.

For each feature in ALL versions, fetch full details:
```bash
jira issue view <FEATURE-KEY> --plain
```

Extract per feature: key, summary, status, component(s), labels, description.

**Step 1.5 — Enrich from child epics**: For ALL features across ALL versions (target and prior), also fetch child epics to surface capabilities that the feature description may not enumerate:
```bash
jira issue list --project OSAC -q "type = Epic AND parent = <FEATURE-KEY>" --plain --no-headers
```

From the child epics, extract **only epics that represent user-facing capabilities** — new APIs, new UI surfaces, new integrations, new service behaviors. **Skip epics that are purely internal work**: E2E tests, demo recordings, CI/CD pipelines, performance benchmarks, documentation, bootstrap/planning epics (those titled "Bootstrap", "PRD", "Design", "UX Design", "UI Design"). These provide no external value and should not appear in the report.

Pay special attention to:
- **Epics with a different component than the parent feature** — e.g. UI epics (component=UI, labels=OSAC-UI) under a Core feature reveal a UI dimension the feature description may not mention. Surface these as a separate capability bullet in the matrix under the appropriate dimension (UI row for UI epics, API row for API epics, etc.). This applies to ALL versions — if OSAC-2992 (a 0.2 Core feature) has 6 UI child epics covering tenant management UI, those must appear in the **0.2 row of the UI dimension** of the matrix.
- **Epics with no fixVersion inherit the parent feature's version for matrix placement**. In OSAC, fixVersions are set on Features, not Epics. When an epic has no fixVersion, use its parent feature's fixVersion to determine where it belongs in the cumulative matrix. Example: OSAC-3344–3349 are UI epics with no fixVersion, but their parent OSAC-2992 has `fixVersion=0.2` — so these UI epics belong in the **0.2 row** of the UI dimension.
- **Epics that reveal specific sub-capabilities** — e.g. "Vault Configuration & Tenant NS Lifecycle", "M360 Adapter", "MaaS Inference Metering" are specific capabilities worth naming rather than just "Secret Management" or "Metering".

**Customer label detection** — auto-discover all customer labels dynamically:
- Any label matching `customer:*` → extract the customer name after the colon (e.g. `customer:moc` → MOC, `customer:telenor` → Telenor, `customer:jio` → Jio). Capitalize the name for display.
- `rfp-telefonica-gigafactory` → Telefónica (legacy label, maps to same customer as `customer:telefonica`)
- `NCP` → NCP (NVIDIA Cloud Partners)
- `AIGRID` or `ai-grid-60d-plan` → AI Grid

Do not hard-code specific customer names — discover them from the labels on each feature. This ensures new customers (e.g. `customer:nebius`, `customer:vz`) are automatically included without skill changes.

### Step 2: Query Customer Requirements

**NCP requirements** (OSAC-991):
```bash
jira issue view OSAC-991 --plain
```
Extract the linked issues and map each NCP requirement to its OSAC feature and which version covers it.

Then also search by label as a fallback to catch any NCP-related features not linked back to OSAC-991, but **only for the target version**:
```bash
jira issue list --project OSAC -q "labels = 'NCP' AND type = Feature AND fixVersion = '<TARGET>'" --plain --no-headers
```
Merge the two result sets — label-based results may surface features (like breakfix/BFX02 tickets) that were created after OSAC-991 and not explicitly linked back. Do NOT include NCP-labeled features from other versions or with fixVersion=Backlog.

**All customers with `customer:*` labels** — query each customer dynamically. First discover which customer labels exist on features in scope:
```bash
jira issue list --project OSAC -q "type = Feature AND labels is not EMPTY AND (fixVersion = '<TARGET>' OR fixVersion = '<N-1>')" --plain --no-headers
```
Then for each unique `customer:*` label found, query that customer's full feature list:
```bash
jira issue list --project OSAC -q "labels = 'customer:<NAME>' AND type = Feature" --plain --no-headers
```

**Telefónica RFP** (legacy label — always include):
```bash
jira issue list --project OSAC -q "labels = 'rfp-telefonica-gigafactory' AND type = Feature" --plain --no-headers
```

### Step 3: Group Features by Use Case

Use the **component** field as the primary grouping key:

| Component / Keyword | Use Case Category |
|---------------------|-------------------|
| CaaS | CaaS — Cluster Provisioning |
| VMaaS, VCD | VMaaS — VM Management |
| Storage | Storage |
| Connectivity&Fabric, Networking | Networking |
| Core | Core — Multi-Tenancy & Platform |
| Enclave | Enclave & Deployment |
| Infrastructure | Infrastructure |
| BMaaS | BMaaS — Bare Metal Lifecycle |
| Metering, Billing and Quota | Metering & Quota |
| UI | *(do not create a standalone UI group — assign to the other service component instead)* |
| MaaS | MaaS — Model as a Service |

Keyword fallback applies if no component is set (scan summary).

**Spikes**: Any feature whose title starts with "Spike:" or "[spike]" is an investigation, not a delivered capability. **Do not include spikes in the Service Offering Matrix.** They may appear in the Use Case Cards and Feature Inventory with a clear "Spike" label, but never as a capability in a matrix cell.

**Component takes precedence over summary keywords**: If a feature has a component set, always use the component for grouping — never override with summary-based inference. Examples:
- A feature titled "Key Management Service" with `component=Core` belongs in "Core — Multi-Tenancy & Platform", not Storage
- OSAC-3046 "Per-Service Enablement" with `component=Core` belongs in Core, not Infrastructure
- OSAC-1644 "Cross-cluster authentication" with `component=Core,Infrastructure` belongs in Core (use the first non-Infrastructure component; Infrastructure is a delivery concern, not a use-case grouping)
- If a feature has multiple components, use the most specific service component (CaaS, VMaaS, BMaaS, Storage, Networking, MaaS, Core) and ignore Infrastructure/Enclave as primary grouping keys

### Step 4: Build the Cumulative Capability View

For each use case category, organize features across ALL versions showing the full history:

**Version labels to use:**
- `0.1` — shipped in 0.1
- `0.2` — shipped in 0.2
- `0.3` — shipped/planned in 0.3
- `+<TARGET>` — what this version adds (the focus of the report)

Example for a 0.3 report:
```
CaaS API:
  0.1: Cluster provisioning via HyperShift + Metal3
  0.2: Managed cluster versions, cluster upgrade, CaaS networking (Netris/VLAN)
  +0.3: Scale CLI, cluster status report, VM worker nodes, upgrade progress
```

Example for a 0.4 report:
```
Core Security:
  0.1: Keycloak auth, OPA RBAC
  0.2: Secret Management foundation, Vault integration
  0.3: Per-Project KMS, cross-cluster auth and TLS trust
  +0.4: Audit Log API, Breakfix Event API (NCP BFX02)
```

### Step 5: Build the Service Offering Matrix

For each of the four core services (CaaS, VMaaS, BMaaS, MaaS), evaluate four dimensions across all versions:

1. **API** — Core provisioning and lifecycle capabilities
2. **Networking** — Network fabric, connectivity, tenant network isolation
3. **Storage** — Storage backends, CSI, encryption, volume management
4. **UI** — User-facing surfaces, wizards, consoles

**Do NOT include a Multi-Tenancy row.** Multi-tenancy (Keycloak auth, OPA RBAC, tenant/project scoping) is a platform-level concern that applies equally across all services. It is not meaningfully different per service and repeating it across columns adds noise. Multi-tenancy progression is covered in the Cumulative Capability Progression section under Core.

Each cell shows cumulative layers with version labels. Use human-readable capability descriptions only — **never put Jira keys (e.g., OSAC-1436) in the matrix cells, and never use raw Jira feature titles**. Extract a concise, user-facing capability description from the feature description or summary. Transform verbose Jira titles into plain capability phrases: "CaaS - Provision Clusters via OSAC API Using Auto-Provisioned Agents from File/BCM Inventory - Part 1" → "Cluster provisioning via HyperShift + Metal3 + BCM inventory". "Catalog Items v2 - Field Governance Redesign" → "Catalog item field governance". Keep descriptions short (5–8 words max per bullet).

The matrix has **4 service columns**: CaaS, VMaaS, BMaaS, MaaS. Include MaaS even if it only has content in one or two versions.

```
0.1: <base capability description>
0.2: + <added capability description>
+0.3: + <new capability description>
```

### Step 6: Generate Reports (JSON by default; Markdown/HTML on request)

Per-section content rules for all seven sections (Release Vision, Service Offering Matrix, Use Case Cards, Customer Requirements Coverage, Cumulative Capability Progression, Feature Inventory, Notes & Action Items), shared across all three output formats: [references/html-sections.md](references/html-sections.md).

#### JSON

Save to: `OSAC-<VERSION>-release-plan-<YYYY-MM-DD-HHMM>.json`

The JSON is a **structured, complete** representation of the full report — not a summary. Every capability description, status, and customer tag must appear in the JSON. Reuse the exact human-readable capability text (never raw Jira titles) consistently across whichever outputs are generated.

Full schema and rules: [references/json-schema.md](references/json-schema.md). Key points: reuse the exact human-readable capability text (never raw Jira titles); map each row's real Jira status individually (`"Done ✅"`, `"In Progress"`, `"In Review"`, `"Planned"` — never one value for all rows); omit cumulative-progression entries for versions that added nothing; never truncate the backlog notes list.

#### Markdown

Only generate this if the user explicitly asked for the markdown report in addition to the default JSON.

Save to: `OSAC-<VERSION>-release-plan-<YYYY-MM-DD-HHMM>.md`

Include generation timestamp in the report header: `Generated: <YYYY-MM-DD HH:MM>` (use current date and time).

Structure:
```markdown
# OSAC <VERSION> — Release Plan
Generated: <date>

## Release Vision
<one-paragraph summary>

## Service Offering Matrix
...

## Use Case Cards
...

## Customer Requirements Coverage
...

## Cumulative Capability Progression
### <Use Case>
| Version | Capabilities |
|---------|-------------|
| 0.1 | ... |
| 0.2 | ... |
| +<TARGET> | ... |

## Feature Inventory
...

## Notes & Action Items
...
```

#### HTML

Only generate this if the user explicitly asked for the HTML report in addition to the default JSON.

Save to: `OSAC-<VERSION>-release-plan-<YYYY-MM-DD-HHMM>.html`

Include generation timestamp in the HTML subtitle bar: `Generated: <YYYY-MM-DD HH:MM>`.

**Use the CSS from [references/html-styles.md](references/html-styles.md) verbatim in the `<style>` tag** — do not invent your own styling.

Use a clean, professional style with:
- Red Hat-inspired color palette (`#EE0000` red accent, `#151515` dark text)
- Color-coded version badges with fixed colors: 0.1=`#6c757d` (gray), 0.2=`#0066cc` (blue), 0.3=`#00838f` (teal), target version=`#3d7a00` (green) with `+` prefix
- **Feature names must be clickable links** to `https://redhat.atlassian.net/browse/<KEY>`
- Cumulative capability table for each use case showing version history
- Color-coded use case cards (Core=red, CaaS=blue, VMaaS=green, BMaaS=orange, Storage=purple, Networking=teal)
- Customer driver badges (NCP=blue, Telefónica=orange, MOC=purple, Telenor=dark blue, AI Grid=red)
- Service offering matrix with layered version labels
- Print-friendly layout
- All CSS self-contained in `<head>`

### Step 7: Open and Present

After saving whichever files were generated:
1. Print the output path(s) to the user
2. If HTML was generated, suggest opening it with: `open OSAC-<VERSION>-release-plan-<DATE>.html`
3. The `.json` file (always generated) is the machine-readable artifact consumed by downstream pipelines (e.g. the Org Pulse dashboard's release-plan data pipeline) — validate it is well-formed JSON before finishing (`python3 -m json.tool <file> > /dev/null`).

## Tips

- **Cumulative history**: The key differentiator of this skill. Always show what was built in 0.1, 0.2, etc. before showing what's new. A reader should understand the full journey, not just the delta. **If a prior version has no features in a given use case category, omit that version row entirely** — never write "Foundation maintained" or "No new features" as a row. Only include rows where something was actually delivered.
- **Feature links**: Every feature name in the HTML must be a clickable link to `https://redhat.atlassian.net/browse/<KEY>`. Never display a feature name as plain text.
- **Customer tags**: Check ALL labels on each feature. A feature can have multiple customer tags.
- **Rate limiting**: Batch epic queries using `parent in (...)`. Don't fire more than 5 jira commands in parallel.
- **Shell variable names**: Never use `status` as a bash/zsh variable name — it is a read-only reserved variable in zsh and causes `(eval): read-only variable: status` errors. Use `jira_status`, `issue_status`, or similar instead.
- **macOS bash compatibility**: macOS ships bash 3.2 which does NOT support associative arrays (`declare -A`). Never use associative arrays in shell scripts. Use Python for any data aggregation, grouping, or key-value mapping instead — e.g. `jira issue list ... | python3 -c "..."`. All complex data processing should be done in Python, not bash.
- **No M1/M2 granularity**: Treat 0.2-M1 and 0.2-M2 as part of 0.2. Query `fixVersion = '0.2'` and treat all 0.2 features together.
- **Component-based grouping**: Use component field, not Team field, for grouping (Team may not be set on all features).
- **N-1 vs N-2+ distinction**: For the immediately preceding version (N-1), include ALL features regardless of status — they are expected to ship before the target version. For N-2 and older, include only Closed+Done features. This ensures in-flight work like a storage framework being built in 0.2 appears in the 0.3 report instead of being silently dropped for not yet being Done.
- **Target version scope (Feature Inventory only)**: Only features where `fixVersion = '<TARGET>'` belong in Section 6 (Feature Inventory) — that section is a clean list of what this version delivers, not a cumulative one. Use Case Cards, the Service Offering Matrix, and Cumulative Capability Progression are cumulative across all versions with the target's additions highlighted; do not restrict those three sections to `fixVersion = '<TARGET>'`.
