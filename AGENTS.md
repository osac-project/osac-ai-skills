# AGENTS.md

This file provides guidance to AI coding assistants working in this repository.

## Project Overview

`osac-ai-skills` hosts OSAC-native Agent Skills (`skills/`) plus the
tooling that lints, validates, and vendors them — shared shell helpers
(`tools/`), a skill-quality eval harness (`evals/`), and skillsaw
lint/review CI (see Skill-Quality Linting below for the `skillsaw` link).

Consumers (currently `osac-workspace`, later the `osac` mono-repo) vendor
this repo as a dependency and fan its content out into their own
`.claude/`, `.cursor/`, and `.gemini/` directories via their own bootstrap
scripts, which call [`tools/link-agent-skills.sh`](tools/link-agent-skills.sh).
Consumer-side fan-out
mechanics (what gets symlinked where, how `--verify` works, which shared
directories get materialized) are documented in [`README.md`](README.md) —
this file does not repeat that; it covers skill-authoring conventions for
someone working **inside** this repository.

## Skill Structure

Every skill is a directory under `skills/` containing at minimum a
`SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: What the skill does and when to use it.
metadata:
  version: "0.1.0"
---
```

- `name` must be lowercase letters, numbers, and hyphens, and match the
  directory name.
- `metadata.version` is required (enforced by skillsaw's `agentskill-valid`
  rule) and must be a quoted semver string.
- A skill may also have `references/`, `scripts/`, `evals/`, `assets/`, or
  `steps/` subdirectories — no others are recognized
  (`agentskill-structure` in `.skillsaw.yaml`).
- Every file bundled with a skill must be referenced from its `SKILL.md`,
  directly or transitively (`agentskill-unreferenced-files`) — an orphaned
  file in a skill directory is a lint warning.

As of this writing, `skills/` holds 21 skills (e.g. `jira-task-management`,
`osac-feature`, `design-review`, `create-pr`) — treat that as an example of
current shape, not an exhaustive or maintained list; read `skills/` itself
for the current set.

### Path References in Skill Content

Paths inside a skill's own directory should be wrapped in markdown link
syntax (e.g. `[references/foo.md](references/foo.md)`). Workspace-root and
cross-component paths — ones that only resolve once this repo is vendored
into a consumer (e.g. `presentations/`, `osac/fulfillment-service/`) — stay
as backtick text instead, since a markdown link would point nowhere from
inside this repo. This is the convention `.skillsaw.yaml`'s `content-unlinked-internal-reference`
rule already accepts as an exception for `AGENTS.md`/`.claude/rules/*.md`'s
bare-path style, and both that rule and `content-broken-internal-reference`
accept for cross-component paths in skill content.

## Versioning

`metadata.version` is a semantic version. **Any content change to a
`skills/*/SKILL.md` file requires bumping that version** — PATCH for
wording/typo fixes, MINOR for added or changed behavior, MAJOR for
removed/renamed phases or breaking changes to the skill's contract.

This is enforced mechanically, not just by convention:
[`.github/workflows/skill-version-check.yml`](.github/workflows/skill-version-check.yml)
runs on every PR that touches `skills/**` and calls
[`tools/check-skill-version-bump.sh`](tools/check-skill-version-bump.sh),
which fails the PR if a `SKILL.md`'s content changed but its
`metadata.version` string did not. The check only verifies the version
string *changed* — it does not validate that the new value is a
semantically correct bump.

## Shared Tooling

[`tools/resolve-remotes.sh`](tools/resolve-remotes.sh) (fork vs. upstream
remote resolution) and [`tools/jira-safe-create.sh`](tools/jira-safe-create.sh)
(safe `jira issue create` helpers) are shared shell helpers consumed by
multiple skills, so they live once here instead of being copied into each
skill. See [`README.md`](README.md)'s "Shared helper scripts" section for
the full list and which skills consume each one.

## Skill-Quality Linting (skillsaw)

[`skillsaw`](https://skillsaw.org/) lints the **entire repository**
(`skillsaw lint .`, per `.skillsaw.yaml`'s exclude list, which only removes
agent-discovery symlink dirs and `.artifacts/` — root-level files including
this one are in scope). Rule configuration lives in `.skillsaw.yaml`;
[`.github/workflows/skillsaw.yml`](.github/workflows/skillsaw.yml) runs it
on every PR with `strict: true` (every warning fails the check), pinned to
the version in `Makefile`'s `SKILLSAW_VERSION`.
[`.github/workflows/skillsaw-review.yml`](.github/workflows/skillsaw-review.yml)
posts the lint findings as inline PR comments.

Run it locally before opening a PR:

```bash
make skillsaw              # lints the whole repo
make skillsaw SKILL=skills/<name>/   # lints one skill
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full pre-PR checklist.

## Eval Harness

`evals/` measures skill quality (currently `prd-review` and
`design-review`) against human-validated reference cases using a pinned
`agent-eval-harness` checkout. See [`evals/README.md`](evals/README.md)
for setup, prerequisites, and how to run a case — not duplicated here.

## File Organization

```text
osac-ai-skills/
├── skills/                          # Agent Skills — one directory per skill
│   └── <name>/
│       ├── SKILL.md                # Required: frontmatter + entry point
│       ├── references/             # Optional, e.g. — see Skill Structure for the full allowed set
│       ├── scripts/                # Optional, e.g.
│       └── evals/                  # Optional, e.g.
├── tools/                           # Shared shell helpers + fan-out script
│   ├── link-agent-skills.sh        # Consumer fan-out (see README.md)
│   ├── resolve-remotes.sh
│   ├── jira-safe-create.sh
│   ├── check-skill-version-bump.sh
│   └── test/                       # Smoke/static tests for tools/ and skill families
├── evals/                           # Skill-quality eval harness (see evals/README.md)
├── .design/                         # Design-workflow context/templates (fan-out — see README.md)
├── .prd/                            # PRD-workflow templates (fan-out — see README.md)
├── .claude/
│   ├── rules/                       # Shared canonical content (fan-out — see README.md)
│   ├── agents/                      # Shared canonical content (fan-out — see README.md)
│   └── hooks/                       # Shared canonical content (fan-out — see README.md)
├── .github/workflows/               # skillsaw, skillsaw-review, skill-version-check
├── .skillsaw.yaml                   # skillsaw rule configuration
├── OWNERS                           # Approvers / reviewers
├── Makefile                         # `make skillsaw`
├── README.md                        # Consumer fan-out mechanics
├── AGENTS.md                        # This file
├── CLAUDE.md                        # Claude Code entry point (points here)
└── CONTRIBUTING.md                  # Human contributor walkthrough
```

## Development

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to add or modify a skill,
PR expectations, and who reviews a PR (version-bump mechanics are covered
above in Versioning).
