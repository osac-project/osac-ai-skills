# Development Conventions

## Git Workflow

- **Always create a feature branch** for any work — never commit directly to `main`.
- **Branch naming**: `<type>/<ticket-or-description>` (e.g., `feat/OSAC-23607`, `fix/duplicate-aap-jobs`)
- **Fork-based**: push to `$PUSH_REMOTE`, never to `$UPSTREAM_REMOTE`. Default remote names (set by each consumer's own bootstrap script): `origin` = upstream `osac-project` repo, `fork` = developer fork. Manual setups may reverse these (e.g. `origin` = fork, `upstream` = osac-project) — always resolve dynamically rather than assuming, via the vendored `resolve-remotes.sh`:
  ```bash
  for d in "$HOME/.osac-ai-skills" "./.osac-ai-skills"; do [[ -x "$d/tools/resolve-remotes.sh" ]] && { RR="$d/tools/resolve-remotes.sh"; break; }; done
  eval "$("$RR" <component-path>)"
  ```
- **PR titles**: always include the Jira ticket key (e.g., "OSAC-12345: fix subnet race condition")
- **DCO sign-off**: `git commit -s` on all commits
- **AI attribution**: use an `Assisted-by: <tool> <contact>` trailer on commits, naming whichever AI tool actually did the work — never `Co-Authored-By` for AI tools (Red Hat attribution standard). Example for Claude Code:
  ```text
  Assisted-by: Claude Code <noreply@anthropic.com>
  ```

## Jira Conventions

- OSAC uses Jira **Tasks** (not Stories) for implementation work — in the **implement** workflow, "story" references mean Tasks in this project
- Use `jira` CLI for Jira access (e.g., `jira issue view OSAC-1234 --plain`), not Jira MCP
