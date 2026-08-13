#!/usr/bin/env bash
# Link agent skill discovery directories to the canonical skills/ tree.
#
# Usage: tools/link-agent-skills.sh [--claude] [--cursor] [--gemini] [--all] [--verify]
#
# Creates umbrella symlinks:
#   .claude/skills -> ../skills
#   .cursor/skills -> ../skills
#   .gemini/skills -> ../skills
#
# Optionally wires flightctl/ai-workflows skill symlinks under skills/ when
# ~/.ai-workflows or ./.ai-workflows is present. Consumers that need those
# workflows still bootstrap ai-workflows themselves (e.g. osac/tools/bootstrap.sh).
#
# Also materializes shared content from this repo's own .claude/rules/,
# .claude/agents/, and .design/context/ into the consumer's tree (per-file
# symlinks, alongside any consumer-local files in the same dirs):
#   .claude/rules/<name>.md   -> <this repo>/.claude/rules/<name>.md
#   .claude/agents/<name>.md  -> <this repo>/.claude/agents/<name>.md
#   .design/context/<name>.md -> <this repo>/.design/context/<name>.md
# Rules/agents are Claude-only today (no Cursor/Gemini equivalent format to
# fan the same raw content out to). design/context is agent-agnostic — it's
# read by skill instructions (prd-review, design-review, ai-workflows
# prd/design), not by any one coding agent's auto-attach mechanism.
# reference/*.md (ARCHITECTURE.md and siblings) is NOT centralized here —
# it's a codebase-analysis snapshot of osac/'s own internals (same origin as
# reference/CONVENTIONS.md and friends, which stay consumer-local), not
# portable guidance. Placement is deferred to OSAC-4008.
# OSAC-4006: centralized here (not duplicated per-consumer) so both osac and
# osac-workspace pick this up automatically once they vendor+exec this script.
set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"
# Consumers (osac-workspace, osac) may set PROJECT_ROOT to their own tree so
# agent links and --with-ai-workflows materialize there instead of inside this
# skills repo. Unset → standalone clone behavior (repo root == REPO_ROOT).
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(realpath "${PROJECT_ROOT}")"
else
  PROJECT_ROOT="${REPO_ROOT}"
fi

OSAC_SKILLS=(
  browser-demo-recording
  capture-tasks-from-meeting-notes
  create-pr
  design-review
  generate-status-report
  github-actions-workflows
  jira-task-management
  milestone-scope
  osac-cluster
  osac-demo-recording
  osac-feature
  osac-release
  performance-review
  prd-review
  presentation
  quick-fix
  report-bug
  review-gate
  security-review
)

AI_WORKFLOW_SKILLS=(bugfix design e2e implement prd)

SHARED_RULES=(architecture-patterns networking-design-alignment request-path-tracing)
SHARED_AGENTS=(quick-fix)
SHARED_DESIGN_CONTEXT=(enclave-wizard-pipeline networking-decisions osac-dimensions review-patterns)

LINK_CLAUDE=false
LINK_CURSOR=false
LINK_GEMINI=false
LINK_AI_WORKFLOWS=false
VERIFY_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--claude] [--cursor] [--gemini] [--all] [--with-ai-workflows] [--verify]

  --claude              Link .claude/skills -> ../skills
  --cursor              Link .cursor/skills -> ../skills
  --gemini              Link .gemini/skills -> ../skills
  --all                 Link all agent directories (default when no link flag is given)
  --with-ai-workflows   Also symlink flightctl/ai-workflows under skills/ (opt-in;
                        consumers that bootstrap ai-workflows pass this)
  --verify              Verify symlinks and OSAC skill files; exit non-zero on failure

Always materializes .design/context/*.md (agent-agnostic; read by skill
instructions, not by any one coding agent's auto-attach mechanism).
When --claude (or --all) is passed, also materializes shared rules
(.claude/rules/*.md) and agents (.claude/agents/*.md).
EOF
}

# Replace link_path with a symlink to target. Refuses to delete a real
# file/directory (only removes an existing symlink or creates anew).
safe_symlink() {
  local link_path="$1"
  local target="$2"

  if [[ -L "${link_path}" ]]; then
    rm -f "${link_path}"
  elif [[ -e "${link_path}" ]]; then
    echo "ERROR: ${link_path} exists and is not a symlink; refusing to replace" >&2
    return 1
  fi
  ln -sfn "${target}" "${link_path}"
}

link_agent_skills() {
  local agent_dir="$1"
  local label="$2"

  mkdir -p "${agent_dir}"
  safe_symlink "${agent_dir}/skills" ../skills
  echo "  Linked ${agent_dir}/skills -> ../skills  (${label})"
}

resolve_ai_workflows_dir() {
  local dir
  for dir in "${HOME}/.ai-workflows" "${PROJECT_ROOT}/.ai-workflows"; do
    if [[ -d "${dir}" ]]; then
      (cd "${dir}" && pwd -P)
      return
    fi
  done
}

link_canonical_ai_workflows() {
  local ai_dir
  ai_dir="$(resolve_ai_workflows_dir || true)"
  if [[ -z "${ai_dir}" ]]; then
    echo "WARN: ai-workflows not found; skipping skills/ workflow symlinks" >&2
    return 0
  fi

  mkdir -p "${PROJECT_ROOT}/skills"
  if [[ -d "${ai_dir}/_shared" ]]; then
    safe_symlink "${PROJECT_ROOT}/skills/_shared" "${ai_dir}/_shared"
    echo "  Linked skills/_shared -> ${ai_dir}/_shared"
  fi
  for wf in "${AI_WORKFLOW_SKILLS[@]}"; do
    if [[ -d "${ai_dir}/${wf}" ]]; then
      safe_symlink "${PROJECT_ROOT}/skills/${wf}" "${ai_dir}/${wf}"
      echo "  Linked skills/${wf} -> ${ai_dir}/${wf}"
    fi
  done
}

# Symlinks $PROJECT_ROOT/$rel_dir/<name>.md -> this repo's own $rel_dir/<name>.md
# for each name in the given list. No-op in standalone mode (PROJECT_ROOT is
# this same repo) — the canonical files already live at that exact path, so
# symlinking a file onto itself would trip safe_symlink's real-file guard.
materialize_shared_dir() {
  local rel_dir="$1" label="$2"
  shift 2
  local names=("$@")
  local name source

  if [[ "${PROJECT_ROOT}" == "${REPO_ROOT}" ]]; then
    return 0
  fi
  mkdir -p "${PROJECT_ROOT}/${rel_dir}"
  for name in "${names[@]}"; do
    source="${REPO_ROOT}/${rel_dir}/${name}.md"
    if [[ ! -f "${source}" ]] || [[ ! -r "${source}" ]]; then
      echo "ERROR: canonical source ${source} missing or unreadable (${label}); refusing to link" >&2
      return 1
    fi
    safe_symlink "${PROJECT_ROOT}/${rel_dir}/${name}.md" "${source}"
    echo "  Linked ${rel_dir}/${name}.md -> osac-ai-skills/${rel_dir}/${name}.md (${label})"
  done
}

materialize_shared_rules() {
  materialize_shared_dir ".claude/rules" "shared rule" "${SHARED_RULES[@]}"
}

materialize_shared_agents() {
  materialize_shared_dir ".claude/agents" "shared agent" "${SHARED_AGENTS[@]}"
}

materialize_design_context() {
  materialize_shared_dir ".design/context" "design context" "${SHARED_DESIGN_CONTEXT[@]}"
}

verify_symlink() {
  local agent_dir="$1"
  local label="$2"
  local expected resolved

  if [[ ! -L "${agent_dir}/skills" ]]; then
    echo "ERROR: ${label}: ${agent_dir}/skills is not a symlink" >&2
    return 1
  fi

  expected="$(cd "${PROJECT_ROOT}/skills" && pwd -P)"
  resolved="$(cd -L "${agent_dir}/skills" && pwd -P)"
  if [[ "${resolved}" != "${expected}" ]]; then
    echo "ERROR: ${label}: ${agent_dir}/skills resolves to ${resolved}, expected ${expected}" >&2
    return 1
  fi

  if [[ ! -r "${agent_dir}/skills/create-pr/SKILL.md" ]]; then
    echo "ERROR: ${label}: cannot read create-pr via ${agent_dir}/skills" >&2
    return 1
  fi

  echo "  OK ${label}: ${agent_dir}/skills -> ../skills"
}

verify_osac_skills() {
  local missing=0
  for skill in "${OSAC_SKILLS[@]}"; do
    if [[ ! -r "${PROJECT_ROOT}/skills/${skill}/SKILL.md" ]]; then
      echo "ERROR: missing ${PROJECT_ROOT}/skills/${skill}/SKILL.md" >&2
      missing=1
    fi
  done
  return "${missing}"
}

verify_ai_workflow_skills() {
  local missing=0 skill any=0
  # Only verify when workflow symlinks were actually wired under skills/.
  for skill in "${AI_WORKFLOW_SKILLS[@]}" _shared; do
    if [[ -e "${PROJECT_ROOT}/skills/${skill}" ]]; then
      any=1
      break
    fi
  done
  if [[ "${any}" -eq 0 ]]; then
    return 0
  fi
  for skill in "${AI_WORKFLOW_SKILLS[@]}"; do
    if [[ ! -r "${PROJECT_ROOT}/skills/${skill}/SKILL.md" ]]; then
      echo "ERROR: missing skills/${skill}/SKILL.md (pass --with-ai-workflows after bootstrapping ai-workflows)" >&2
      missing=1
    fi
  done
  return "${missing}"
}

verify_shared_dir() {
  local rel_dir="$1" label="$2"
  shift 2
  local names=("$@")
  local missing=0 name path expected resolved expected_resolved

  for name in "${names[@]}"; do
    path="${PROJECT_ROOT}/${rel_dir}/${name}.md"
    if [[ "${PROJECT_ROOT}" == "${REPO_ROOT}" ]]; then
      # Standalone mode: this file *is* the canonical source, not a link to it.
      if [[ ! -r "${path}" ]]; then
        echo "ERROR: missing ${rel_dir}/${name}.md (${label})" >&2
        missing=1
      fi
      continue
    fi
    # Consumer mode: must be a symlink resolving to this repo's canonical file
    # — a stale real file left over from before materialization would pass a
    # bare readability check without actually tracking the canonical source.
    expected="${REPO_ROOT}/${rel_dir}/${name}.md"
    if [[ ! -f "${expected}" ]] || [[ ! -r "${expected}" ]]; then
      echo "ERROR: canonical source ${expected} missing or unreadable (${label})" >&2
      missing=1
      continue
    fi
    if [[ ! -L "${path}" ]]; then
      echo "ERROR: ${rel_dir}/${name}.md (${label}) is not a symlink" >&2
      missing=1
      continue
    fi
    resolved="$(realpath "${path}" 2>/dev/null || true)"
    expected_resolved="$(realpath "${expected}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]] || [[ -z "${expected_resolved}" ]] || [[ "${resolved}" != "${expected_resolved}" ]]; then
      echo "ERROR: ${rel_dir}/${name}.md (${label}) resolves to ${resolved:-<broken symlink>}, expected ${expected}" >&2
      missing=1
    fi
  done
  return "${missing}"
}

verify_shared_rules_agents() {
  local errors=0
  verify_shared_dir ".claude/rules" "shared rule" "${SHARED_RULES[@]}" || errors=1
  verify_shared_dir ".claude/agents" "shared agent" "${SHARED_AGENTS[@]}" || errors=1
  return "${errors}"
}

verify_design_context() {
  verify_shared_dir ".design/context" "design context" "${SHARED_DESIGN_CONTEXT[@]}"
}

run_verify() {
  local errors=0

  echo "Verifying agent skill symlinks..."
  if [[ "${LINK_CLAUDE}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.claude" "Claude" || errors=1
    verify_shared_rules_agents || errors=1
  fi
  if [[ "${LINK_CURSOR}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.cursor" "Cursor" || errors=1
  fi
  if [[ "${LINK_GEMINI}" == true ]]; then
    verify_symlink "${PROJECT_ROOT}/.gemini" "Gemini" || errors=1
  fi

  echo "Verifying canonical skills/ content..."
  verify_osac_skills || errors=1
  verify_ai_workflow_skills || errors=1
  verify_design_context || errors=1

  if [[ "${LINK_CURSOR}" == true ]] && [[ ! -f "${PROJECT_ROOT}/.cursor/commands/implement-ingest.md" ]]; then
    echo "WARN: missing .cursor/commands/implement-ingest.md (run ai-workflows cursor install?)" >&2
  fi

  if [[ "${errors}" -ne 0 ]]; then
    echo "Verification failed." >&2
    return 1
  fi

  echo "Verification passed."
}

if [[ $# -eq 0 ]]; then
  LINK_CLAUDE=true
  LINK_CURSOR=true
  LINK_GEMINI=true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude) LINK_CLAUDE=true ;;
    --cursor) LINK_CURSOR=true ;;
    --gemini) LINK_GEMINI=true ;;
    --all)
      LINK_CLAUDE=true
      LINK_CURSOR=true
      LINK_GEMINI=true
      ;;
    --with-ai-workflows) LINK_AI_WORKFLOWS=true ;;
    --verify) VERIFY_ONLY=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "${VERIFY_ONLY}" == true ]]; then
  if [[ "${LINK_CLAUDE}" == false && "${LINK_CURSOR}" == false && "${LINK_GEMINI}" == false ]]; then
    LINK_CLAUDE=true
    LINK_CURSOR=true
    LINK_GEMINI=true
  fi
  run_verify
  exit $?
fi

echo "Linking agent skill directories to skills/..."
materialize_design_context
if [[ "${LINK_AI_WORKFLOWS}" == true ]]; then
  link_canonical_ai_workflows
fi
if [[ "${LINK_CLAUDE}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.claude" "Claude"
  materialize_shared_rules
  materialize_shared_agents
fi
if [[ "${LINK_CURSOR}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.cursor" "Cursor"
fi
if [[ "${LINK_GEMINI}" == true ]]; then
  link_agent_skills "${PROJECT_ROOT}/.gemini" "Gemini"
fi

run_verify
