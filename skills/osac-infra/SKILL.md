---
name: osac-infra
description: >
  Umbrella command for OSAC infra/CI team automation, routing to subcommands.
  Currently supports: weekly-report (generate a data-verified infra status
  report from Jira, GitHub PRs, and real CI run stats -- not a dashboard
  pull) and release (invoke the OSAC Helm chart release wizard). USE WHEN
  user says "osac-infra", "infra report", "weekly report", "infra status
  report", "biweekly report", or wants recurring CI/infra reporting or
  release automation for OSAC.
triggers:
  - osac-infra
  - infra report
  - infra weekly report
  - infra status report
  - infra biweekly report
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
metadata:
  version: "0.1.0"
---

# /osac-infra -- OSAC Infra Automation Umbrella

Single entry point for recurring OSAC infra-team automation. Each subcommand's
full workflow lives in its own file under `steps/` -- this file only routes.

## Step 1: Intent Routing

Case-insensitive substring matching against the user's message. Rules
evaluated in order; first match wins.

1. Message contains "release", "publish osac", "bump osac version", "helm
   chart" -> **Release subcommand** (see below)
2. Message contains "weekly", "biweekly", "status report", "infra report",
   or "report" -> **Weekly Report subcommand** (see below)
3. No additional text (user just typed `/osac-infra`) -> ask which
   subcommand via AskUserQuestion, listing the table below

## Subcommands

| Subcommand | Trigger phrases | Workflow |
|---|---|---|
| `weekly-report` | "weekly report", "infra status report", "biweekly report" | [`steps/weekly-report.md`](steps/weekly-report.md) |
| `release` | "release", "publish osac", "bump osac version" | [`steps/release.md`](steps/release.md) |

`weekly-report` is a **draft-then-finalize** flow, not a single pass --
it always produces a draft with an open "Uncertain / Needs Your Input"
section first, invites corrections, then finalizes into a separate clean
document. Never present the first pass as done. See [`steps/weekly-report.md`](steps/weekly-report.md).

Read the workflow file for the matched subcommand and follow it. Do not
inline subcommand logic in this file.

## Adding a New Subcommand

1. Add a row to the routing table above and a matching rule in Step 1.
2. Create `steps/<subcommand>.md` with the full workflow.
3. If the subcommand wraps an existing skill (like `release` wraps
   `osac-release`), invoke that skill via the `Skill` tool rather than
   duplicating its logic -- see [`steps/release.md`](steps/release.md) for the pattern.
4. No Jira ticket IDs in skill file content -- only in commit messages / PR
   titles if anything is committed.
5. Bump `metadata.version` in this file's frontmatter (semver patch/minor)
   any time you modify it -- `check-skill-version-bump.sh` CI enforces this.
