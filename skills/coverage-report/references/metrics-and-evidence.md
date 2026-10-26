# Metrics and Evidence Reference

## Areas and config

- Config lives in `org-pulse-data` at `config/coverage/<wg>.yaml` (one file per WG, edited by MR); the osac `features.yaml` is the Core example and default.
- `--features` takes files or a directory of `*.yaml` and merges them; duplicate
  area keys are rejected. A file may set a top-level `group:` default.
- An entry has `key`, `name`, `group`, `testplans:` (plans prefix ids
  `<plan-key>/TC-...`, where `<plan-key>` is the plan's OSAC-N key or, when its
  directory has none, the directory name; map that exact id), optional inline
  `behaviors:` (`id`, `title`, `tier`, `priority`), `unit_packages`, and
  `mappings:`.
- Inline behaviors are automated. A configured `priority` is preserved in their
  gaps, so `critical` or `high` can drive `not ready`; an unset priority sorts
  `unknown`. Only a reviewed mapping covers one.

## Metric states

| State | Meaning |
|---|---|
| `value` | A percentage with covered/denominator. |
| `zero` | A measured zero; the verdict reason says drafted links pending review or none reviewed. |
| `unavailable` | No coverprofile supplied. Not zero. |
| `blocked` | A mapped unit package is missing from the profile, or an automated behavior has no tier (shows `N tier-unassigned`). |
| `na` | No test plan for that tier, or no statements in the mapped packages. |
| `none` | A plan exists but has no automated behaviors at that tier; neutral. |

## Evidence

| Class | Source | Counted? |
|---|---|---|
| `measured` | Statements in a `--coverprofile`. | Unit only. |
| `declared` | A non-proposed existing test path from a plan, or an existing `mappings:` path whose `tier` matches and whose reviewer handle is valid. | Yes. |
| `inferred` | A `mappings:` entry without a valid `mappings_reviewed_by`. | Never; listed only. |
| `gap` | No existing test, a proposed or missing path, no path, or no tier. | Drives the next action. |

Gap kinds: `planned-not-implemented` (proposed or missing path), `no-mapping`
(no test path), `tier-unassigned` (no tier; assign one).

## Verdicts

| Verdict | Condition |
|---|---|
| `not ready` | Any critical/high gap. |
| `insufficient evidence` | Otherwise, any metric is `unavailable`, `blocked`, `na`, or `zero`. A `none` tier is neutral. |
| `ready` | Otherwise. |

Each area and overview row carries `verdict_reason`, the strongest cause.

## Troubleshooting

| Symptom | Meaning and action |
|---|---|
| Unit `unavailable` / `na` / `blocked` | No profile, no statements for mapped packages, or a package absent; measure, widen the profile, or fix `unit_packages`. |
| Tier `blocked` / `na` | Add a missing tier in the plan's `Tier / owner` bullet or inline `tier`; for `na`, add or fix `testplans` in the WG config. |
| Flow listed as inferred | No valid `@user` / `org/team` handle; only a QE reviewer may set it. |
