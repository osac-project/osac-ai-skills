# osac-ai-skills

Agent Skills and supporting tooling for
[OSAC](https://github.com/osac-project/docs) (Open Sovereign AI Cloud) — an
open source fulfillment system for provisioning Kubernetes clusters and
compute instances with networking capabilities. This repository hosts:

- Native Agent Skills under `skills/`
- [Skillsaw](https://skillsaw.org/) lint config and CI (`.skillsaw.yaml`, `.github/workflows/`)
- Generic agent skill fan-out (`tools/link-agent-skills.sh`)
- Shared helper scripts consumed by specific skills (`tools/resolve-remotes.sh`,
  `tools/jira-safe-create.sh`)
- Skill-quality eval harness (`evals/`)

Browse the live catalog: [https://osac-project.github.io/osac-ai-skills/](https://osac-project.github.io/osac-ai-skills/).

This is the skills content store. Bootstrap/orchestration (what to clone and
when) lives in consumer repos — primarily `osac/tools/bootstrap.sh`, and
until cutover also `osac-workspace/bootstrap.sh`. `flightctl/ai-workflows`
remains a separate vendored dependency of those consumers; it is not hosted
here.

For skill-authoring conventions, versioning rules, and how to contribute a
skill, see [`AGENTS.md`](AGENTS.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Recommended Skill Sequence

Canonical Feature → PRD → Design → Jira sync → Implement → E2E ordering for
OSAC agent skills. Consumer repos (`osac/`, and until cutover
`osac-workspace/`) link here rather than maintaining their own copy.

Run the consumer's bootstrap before a new session so skills are vendored and
linked:

- **osac (mono-repo):** `tools/bootstrap.sh` from the `osac/` checkout
- **osac-workspace (until cutover):** `./bootstrap.sh` from the workspace root

Do not run `osac/tools/bootstrap.sh` from an `osac/` nested inside
`osac-workspace`. Skills are available in Claude Code, Cursor, and Gemini CLI
after bootstrap (command syntax varies by tool).

### 1. Create a Jira Feature

`/osac-feature` — Describe what you want to build. Creates a Feature issue in
Jira (OSAC project) that anchors everything downstream.

### 2. Write a PRD

`/prd` — Ingests requirements from the Jira Feature, walks through clarifying
ambiguities, drafts a Product Requirements Document, and publishes as a PR to
`enhancement-proposals`.

Phases: `/prd:ingest` → `/prd:clarify` → `/prd:draft` → `/prd:revise` →
`/prd:publish` → `/prd:respond`

Get the PR reviewed and merged before moving on.

### 3. Write a Design (Enhancement Proposal)

`/design` — Takes the merged PRD, researches the problem space, drafts a
technical design document (EP), decomposes work into epics and stories, and
publishes as a PR to `enhancement-proposals`.

Phases: `/design:ingest` → `/design:research` → `/design:draft` →
`/design:decompose` → `/design:revise` → `/design:publish` → `/design:respond`

Get the PR reviewed and merged.

### 4. Create Jira Epics & Tasks

`/design:sync` — Syncs the approved task breakdown from the design into Jira
as epics and tasks under the Feature.

### 5. Implement

`/implement` — Pick up a Jira task, plan the implementation, write tests and
code via TDD, validate, and publish a PR.

Phases: `/implement:ingest` → `/implement:plan` → `/implement:code` →
`/implement:validate` → `/implement:publish` → `/implement:respond`

### 6. Write E2E Tests

`/e2e` — Pick up a [QE] Jira task produced by the design workflow, discover
the project's e2e testing infrastructure, plan test scenarios, write e2e tests
matching project conventions, validate, and publish a PR.

Phases: `/e2e:ingest` → `/e2e:plan` → `/e2e:code` → `/e2e:validate` →
`/e2e:publish` → `/e2e:respond`

### Other useful skills

- `/bugfix` — Systematic bug investigation and fix (phase-based)
- `/debug-e2e` — Debug a failing CI job using build logs and gathered OSAC artifacts
- `/create-pr` — Runs repo-specific validation and creates a PR via the fork workflow
- `/pre-pr-review` — Config-driven pre-flight review gate (create-pr Step 4) without opening a PR
- `/code-review` — Review your current diff before submitting

Each skill is phase-based — you can jump directly to any phase (e.g.
`/prd:draft`, `/implement:code`).

## Consumer fan-out

From a standalone clone of this repo:

```bash
tools/link-agent-skills.sh --all
# optional: also wire flightctl/ai-workflows under skills/
tools/link-agent-skills.sh --all --with-ai-workflows
```

From a consumer workspace that vendors this repo (e.g. as `.osac-ai-skills/`),
set `PROJECT_ROOT` to the consumer root so agent symlinks land there. Native
skills must already be present under `$PROJECT_ROOT/skills/` (typically as
symlinks into the vendored `skills/` tree):

```bash
PROJECT_ROOT=/path/to/consumer \
  /path/to/.osac-ai-skills/tools/link-agent-skills.sh --all --with-ai-workflows
```

`--verify` checks the existing tree and exits non-zero on failure. Alone, it
does not create links. Combined with linking flags (`--all`, `--claude`,
`--cursor`, `--gemini`, `--with-ai-workflows`), the script performs the
requested linking first, then verifies:

```bash
tools/link-agent-skills.sh --all --with-ai-workflows --verify
```

### Shared rules, agents, hook docs, and design context

Beyond skill symlinks, the fan-out also materializes canonical content that
lives directly at its real consumer-side path in this repo — `.claude/rules/`,
`.claude/agents/`, `.claude/hooks/`, and `.design/context/` — as per-file
symlinks into `$PROJECT_ROOT`'s matching path, alongside any consumer-local
files already there (e.g. a workspace-only rule with no reason to be shared):

- `.claude/rules/*.md`, `.claude/agents/*.md`, and `.claude/hooks/*.md` —
  materialized only when `--claude` (or `--all`) is passed; no Cursor/Gemini
  equivalent format exists to fan the same raw content out to. `.claude/hooks/`
  holds only shared *documentation* (e.g. `README.md`) — hook scripts
  themselves are consumer-specific executables, not portable content.
- `.design/context/*.md` — materialized unconditionally. Agent-agnostic: read
  directly by skill instructions (`design-review`, `prd-review`,
  `flightctl/ai-workflows`'s `prd`/`design`), not by any one coding agent's
  auto-attach mechanism.
- `.design/templates/*.md` and `.prd/templates/*.md` — materialized
  unconditionally. These are OSAC's section-guidance overrides for
  `flightctl/ai-workflows`'s `prd`/`design` `draft.md` skills (see
  `template-override-resolution.md` in that repo); agent-agnostic for the
  same reason as `.design/context/*.md`.

`reference/*.md` (codebase-analysis excerpts like `ARCHITECTURE.md`,
`CONVENTIONS.md`) is intentionally **not** centralized here — those document
a specific downstream codebase's current internals, not portable skill
guidance, and live in `osac/docs/` instead, co-located with the code they
analyze.

Content in these directories must stay agnostic to where a consumer clones
sibling repos — use component-relative paths or full GitHub URLs, never a
path that assumes a specific repo nesting depth.

## Shared helper scripts

Some skills need small bash helpers beyond what's inlined in their `SKILL.md`.
Rather than each skill (or each consumer repo) carrying its own copy, these
live once in `tools/` here and are resolved by skill instructions from
whichever vendored checkout of this repo the consumer has — `~/.osac-ai-skills`
or the consumer repo's own `.osac-ai-skills/` — the same 2-candidate order
`link-agent-skills.sh`'s `resolve_osac_ai_skills_dir()` uses. There is no
per-consumer copy to keep in sync.

- **`tools/resolve-remotes.sh`** — detects which git remote points at the
  `osac-project` org (upstream) vs. the developer's fork (push target).
  Consumed by `create-pr` and `osac-release`.
- **`tools/jira-safe-create.sh`** — temp-file/cleanup and Jira-credential
  helpers (`new_temp`/`add_temp`, `jira_login`/`jira_token`) for the safe
  `jira issue create` pattern. Consumed by `jira-task-management`,
  `report-bug`, `capture-tasks-from-meeting-notes`, and `osac-feature`.

Smoke tests for both live in `tools/test/` and are run manually (no CI wiring
yet — see `tools/test/*.sh` headers for invocation).

## Background

See ADR 0001 in `osac-project/osac-workspace`:
`decisions/0001-dedicated-ai-skills-repo.md`.
