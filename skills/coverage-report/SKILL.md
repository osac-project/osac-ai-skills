---
name: coverage-report
description: >
  Explain an OSAC capability-area coverage report from the deterministic
  reporter at tools/coverage-report/ in the osac mono-repo. Use when the user
  asks for coverage of a working group ("coverage for VMaaS"), an area
  ("coverage for IAM"), or a full quality plan. Runs make coverage-report from
  the osac repo root against the working-group configs in org-pulse-data, reads
  report.md and report.json, and explains the overview, verdicts and reasons,
  Feature x tier rows, evidence, and gaps. Never computes or adjusts a number.
metadata:
  version: "0.1.0"
---

# OSAC Coverage Report

Thin wrapper around the deterministic reporter at `tools/coverage-report/`.
Rows are capability areas grouped by working group (WG); configs for the 11 WGs
(core, vmaas, bmaas, caas, connectivity, storage, metering, ui, infra, enclave,
ai-sdlc) live in `org-pulse-data` under `config/coverage/<wg>.yaml`. The
reporter owns every number; this skill explains it.

## Hard Rules

- **Never calculate, estimate, round, or adjust a number.** Quote only what
  `report.md` or `report.json` contains; if absent, name the input that produces it.
- **Never promote `inferred` evidence to `declared`** or present an unreviewed
  mapping as covered. Only a QE reviewer may set `mappings_reviewed_by`.
- **Never edit a generated report, post to Jira, open a PR, or change code or tests.**
- **Config edits only with explicit user approval**: propose the exact YAML
  lines, never apply them unasked.

## Step 1: Run the Reporter

Run from the `osac` repo root. Pass the WG configs with `FEATURES`:

| User asks | Command |
|---|---|
| One WG ("coverage for VMaaS") | `make coverage-report FEATURES=<org-pulse-data>/config/coverage ARGS="--group vmaas"` |
| One area ("coverage for IAM") | `make coverage-report FEATURE=iam FEATURES=<org-pulse-data>/config/coverage` |
| Bundled Core example only | `make coverage-report` |

Without `FEATURES`, the bundled `tools/coverage-report/features.yaml` Core
example is used; it has no VMaaS or other WG areas. `--features` may be
repeated and accepts a file or a directory of `*.yaml`; merged duplicate area
keys are rejected. There is no Make `GROUP` variable — pass `--group` in `ARGS`.

Optional `ARGS`: `--coverprofile PATH` (repeatable) and `--out DIR` (default
`.artifacts/coverage-report`):

```bash
make coverage-report FEATURES=../org-pulse-data/config/coverage \
  ARGS="--group vmaas --coverprofile /abs/path/cover.out"
```

Without a coverprofile the unit metric is `unavailable` — missing, not zero.
To measure, warn that the unit suite is slow, then pass the resulting path:

```bash
cd fulfillment-service
ginkgo run -r --cover --output-dir=/abs/path --coverprofile=cover.out internal
```

`--coverprofile` takes a filename, not a path; `--output-dir` sets its directory.

## Step 2: Branch on Exit Code 2

Exit 0 writes the report; only then read it. Exit 2 means the run was rejected,
either because an input was invalid or because the report could not be written.

- **Invalid input** — unknown area or group (an area prints `Did you mean:` /
  `Known features:`), unreadable or invalid config (duplicate area keys,
  absolute or `..` test-plan paths), or a bad coverprofile. Show the message
  verbatim, then ask the user to pick, regenerate or replace the coverprofile,
  or fix the config; offer a config MR only for a config defect. Never guess.
- **Unwritable output** — `--out` could not be created or written. Ask the user
  to choose a writable directory; do not open a config MR.

The reporter writes each report file atomically: it writes `report.json`, then
`report.md`, each through a temporary file and rename. A failure between the two
can still leave a complete `report.json` without `report.md`, so treat neither
as this run's result until a run exits 0.

## Step 3: Read and Explain the Report

The reporter writes `<out>/<area key, group, or ALL>/report.json` and
`report.md`, and prints both paths. Read both.

- **Group or all-areas report** — lead with the `Overview` table
  (`Area | Unit | Integration | E2E | Verdict`), then its per-area reason lines.
- **Any report** — explain:
  1. **Header** — area, group, test plans, commit.
  2. **Verdict and reason** — `not ready` only for critical/high gaps; otherwise
     `insufficient evidence` for `unavailable`, `blocked`, `na`, or `zero`;
     else `ready`. Quote `verdict_reason`; do not invent a cause.
  3. **Feature x tier** — rows as rendered; never turn `unavailable`, `blocked`,
     or `na` into "0%", and treat `none` as neutral.
  4. **Unit packages**, **inferred mappings** (listed, never counted), and
     **gaps** (priority order with a next action).
  5. **Zero tiers** — say whether the reason reports drafted links pending
     review or no reviewed test links yet.

[references/metrics-and-evidence.md](references/metrics-and-evidence.md) defines every state, evidence class, verdict, and gap kind.

## Step 4: Propose Config Changes (Approval Required)

WG configs are MRs to `org-pulse-data` at `config/coverage/<wg>.yaml`; the osac
`tools/coverage-report/features.yaml` is only the Core example. Propose the
exact YAML and stop for:

- **New or misnamed area** — `key`, `name`, `group`, `testplans:` (a list), or
  cases outside a plan as inline `behaviors:` (`id`, `title`, `tier`).
- **Missing mapping** — `mappings:` (`behavior`, `test`, `tier`); `behavior`
  must match the report id (prefixed for multi-plan areas).
- **Unit scope** — `unit_packages`, each with a one-line rationale.
- **Unassigned tier** — add it to the plan's `Tier / owner` bullet or the inline
  behavior's `tier`.

Mappings stay `inferred` until a QE reviewer sets `mappings_reviewed_by` to a
`@user` or `org/team` handle. Entries in `org-pulse-data` are drafts until the
WG lead reviews the MR; a merge alone is not WG sign-off. Apply edits only after
approval, then re-run Step 1.
