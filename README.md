# osac-ai-skills

Dedicated repository for OSAC AI skills and the tooling that only exists to
support or validate them:

- Native Agent Skills under `skills/`
- Skillsaw lint config and CI (`.skillsaw.yaml`, `.github/workflows/`)
- Generic agent skill fan-out (`tools/link-agent-skills.sh`)
- Shared helper scripts consumed by specific skills (`tools/resolve-remotes.sh`,
  `tools/jira-safe-create.sh`)
- Skill-quality eval harness (`evals/`)

This is the skills content store. Bootstrap/orchestration (what to clone and
when) lives in consumer repos — primarily `osac/tools/bootstrap.sh`, and
until cutover also `osac-workspace/bootstrap.sh`. `flightctl/ai-workflows`
remains a separate vendored dependency of those consumers; it is not hosted
here.

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

### Shared rules, agents, design context, and reference docs

Beyond skill symlinks, the fan-out also materializes canonical content that
lives directly at its real consumer-side path in this repo — `.claude/rules/`,
`.claude/agents/`, `.design/context/`, and `reference/` — as per-file symlinks
into `$PROJECT_ROOT`'s matching path, alongside any consumer-local files
already there (e.g. a workspace-only rule with no reason to be shared):

- `.claude/rules/*.md` and `.claude/agents/*.md` — materialized only when
  `--claude` (or `--all`) is passed; no Cursor/Gemini equivalent format exists
  to fan the same raw content out to.
- `.design/context/*.md` and `reference/*.md` — materialized unconditionally.
  Agent-agnostic: read directly by skill instructions (`design-review`,
  `prd-review`, `flightctl/ai-workflows`'s `prd`/`design`), not by any one
  coding agent's auto-attach mechanism.

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
