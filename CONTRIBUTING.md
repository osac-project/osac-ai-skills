# Contributing

Thanks for your interest in contributing to `osac-ai-skills`. This guide
covers adding or modifying a skill, what CI checks before merge, and how
PRs get reviewed. For repository architecture and skill-authoring
conventions in more depth, see [`AGENTS.md`](AGENTS.md).

## Adding a New Skill

1. Create `skills/<name>/` (lowercase, hyphens) with a `SKILL.md`:

   ```yaml
   ---
   name: skill-name
   description: What the skill does and when to use it.
   metadata:
     version: "0.1.0"
   ---
   ```

2. Add any supporting files under the subdirectories `AGENTS.md`'s Skill
   Structure section allows, and reference every bundled file from
   `SKILL.md` (directly or transitively) — see [`AGENTS.md`](AGENTS.md)
   for the exact rules skillsaw enforces here.
3. Run `make skillsaw SKILL=skills/<name>/` and fix anything it flags.
4. Open a PR (see below).

## Modifying an Existing Skill

Any content change to a `skills/*/SKILL.md` file requires bumping its
`metadata.version` — see [`AGENTS.md`](AGENTS.md)'s Versioning section for
the PATCH/MINOR/MAJOR rules and how CI enforces the bump.

## Before Opening a PR

Run the full-repo lint locally:

```bash
make skillsaw
```

This is the same check that runs on every PR (see [`AGENTS.md`](AGENTS.md)'s
Skill-Quality Linting section for scope and enforcement details) — fix
everything it reports before pushing. There's no install script to
smoke-test against (unlike `flightctl/ai-workflows`'s `install.sh cursor`).

If your change touches shared tooling in `tools/`, also run that script's
smoke test under `tools/test/` (see each script's header for invocation).
If it touches an eval-covered skill (`prd-review`, `design-review`), also
run the relevant case — see [`evals/README.md`](evals/README.md).

## PR Conventions

Follow this repository's standard commit/PR conventions — title and commit
format, DCO sign-off, AI attribution, and fork-based push — documented
once in [`.claude/rules/dev-conventions.md`](.claude/rules/dev-conventions.md).

No repository-specific PR template exists today. A useful shape to follow
(seen in prior merged PRs): a `## <Title>` heading, a link to the Jira
ticket, then `### Summary`, `### Changes`, `### Testing`, and an
`### Acceptance Criteria` checklist — not a hard requirement, just a
convention worth matching.

## Review and Approval

PRs are reviewed and approved by the approvers and reviewers listed in
[`OWNERS`](OWNERS).

## Skills Vendored From Elsewhere

`flightctl/ai-workflows` is a separate upstream dependency that consumers
vendor alongside this repo, outside this repo's own fork-based
contribution workflow — its workflows (`bugfix`, `implement`, `design`,
`prd`, `e2e`, etc.) are not part of `osac-ai-skills`. Contributions to
those workflows go upstream to `flightctl/ai-workflows`, not here.
