# Release Plan — JSON Schema

Full schema and rules for the `.json` output of the `release-plan` skill (see [../SKILL.md](../SKILL.md) Step 6). The JSON is a **structured, complete** representation of the same content as the HTML/markdown — not a summary. Every capability description, status, and customer tag that appears in the HTML must appear in the JSON. Reuse the exact human-readable capability text extracted for the HTML (never raw Jira titles) so the three outputs stay in sync.

```json
{
  "metadata": {
    "version": "<TARGET>",
    "priorVersion": "<N-1>",
    "generatedAt": "<YYYY-MM-DD HH:MM>",
    "badge": "Developer Preview"
  },
  "vision": {
    "summary": "<Section 1 one-paragraph summary>",
    "metrics": [
      { "num": 41, "label": "Features in <TARGET>" },
      { "num": 9, "label": "Use Cases" },
      { "num": 8, "label": "Customer Drivers" },
      { "num": 110, "label": "Total Features (0.1–<TARGET>)" }
    ]
  },
  "serviceMatrix": {
    "services": ["CaaS", "VMaaS", "BMaaS", "MaaS"],
    "rows": [
      {
        "dimension": "API",
        "cells": {
          "CaaS": [
            { "version": "0.1", "isTarget": false, "text": "<capability description>" },
            { "version": "+<TARGET>", "isTarget": true, "text": "<capability description>" }
          ],
          "VMaaS": [ "..." ],
          "BMaaS": [ "..." ],
          "MaaS": [ "..." ]
        }
      }
    ]
  },
  "useCaseCards": [
    {
      "key": "caas",
      "title": "CaaS — Cluster Provisioning",
      "items": [
        { "jira": "OSAC-1191", "title": "Cluster provisioning via HyperShift + Metal3 + BCM inventory", "version": "0.1", "isTarget": false, "customers": [] },
        { "jira": "OSAC-1415", "title": "Support cluster upgrade", "version": "+<TARGET>", "isTarget": true, "customers": ["Moc", "Telenor"] }
      ]
    }
  ],
  "customerCoverage": {
    "ncp": [
      { "req": "CNP02", "requirement": "Declarative Resource Interfaces", "coverage": "<description>", "version": "0.2", "status": "Partial" }
    ],
    "byCustomer": [
      {
        "customer": "MOC",
        "rows": [
          { "key": "OSAC-1415", "feature": "Support cluster upgrade", "version": "0.3", "status": "In Review" }
        ]
      }
    ]
  },
  "cumulativeProgression": [
    {
      "useCase": "CaaS — Cluster Provisioning",
      "versions": [
        { "version": "0.1", "isTarget": false, "items": [ { "jira": "OSAC-1191", "text": "Cluster provisioning via HyperShift + Metal3 + BCM inventory" } ] },
        { "version": "+<TARGET>", "isTarget": true, "items": [ "..." ] }
      ]
    }
  ],
  "featureInventory": [
    {
      "group": "CaaS — Cluster Provisioning",
      "features": [
        { "key": "OSAC-1415", "summary": "Support cluster upgrade", "customers": ["Moc", "Telenor"], "status": "In Review" }
      ]
    },
    {
      "group": "Spikes (Investigations)",
      "features": [
        { "key": "OSAC-2850", "summary": "[spike] Investigate Slurm cluster setup using BMaaS API", "customers": ["Moc", "Telefonica"], "status": "Planned" }
      ]
    }
  ],
  "notes": {
    "needsDecomposition": [ { "jira": "OSAC-3784", "title": "Billing Integration MVP", "note": "large scope, needs epic breakdown" } ],
    "spikes": [ { "jira": "OSAC-2850", "title": "...", "note": "investigation, not a delivered capability" } ],
    "backlog": [ { "jira": "OSAC-63", "title": "Activity and Audit Log API", "customers": ["MOC", "Telenor", "Jio", "Telus"], "note": "Backlog" } ]
  }
}
```

## Rules

Mirror the HTML rules from `SKILL.md` Sections 1–7:

- `useCaseCards[].items` are cumulative across all versions, not just the target: each item carries `version` (`"0.1"`, `"0.2"`, …, or `"+<TARGET>"`) and `isTarget` (`true` only for the target version's additions). Omit versions that added nothing to a use case — same rule as `cumulativeProgression`. Same use-case grouping and no-standalone-UI-card rule as the HTML (Section 3).
- `serviceMatrix.rows[].cells` uses a `—` sentinel string (not an empty array) for a service/dimension with no history in any version, so consumers can distinguish "no data" from "not yet fetched".
- `cumulativeProgression[].versions` omits entries for versions that added nothing to that use case — the same rule as the markdown/HTML tables (Section 5).
- `featureInventory` never includes a standalone "UI" group; spikes get their own `"Spikes (Investigations)"` group and are excluded from `serviceMatrix` and `cumulativeProgression`.
- `status` values are the actual Jira status, mapped the same way as the HTML/markdown tables: `"Done ✅"` / `"Closed ✅"` for Closed+Done, `"In Progress"`, `"In Review"`, `"Planned"` for New/not-started. Map every row from its real Jira status individually — do not reuse one status value across rows.
- `notes.backlog` includes every customer-labeled feature in Backlog or beyond the target version — never truncated.
- All Jira keys use the bare key (`"OSAC-1415"`); consumers construct the browse URL themselves (`https://redhat.atlassian.net/browse/<key>`) rather than the JSON embedding full URLs, since the HTML/markdown embed links but downstream renderers need the raw key too.
