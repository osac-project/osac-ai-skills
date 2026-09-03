#!/usr/bin/env bash
# Detect which git remotes point to the upstream org and the developer's fork.
#
# Shared tooling for osac-ai-skills-hosted skills (create-pr).
# Consumers resolve this script from their vendored osac-ai-skills checkout
# (see resolve_osac_ai_skills_dir()-style lookup in each skill's SKILL.md)
# rather than carrying their own copy.
#
# Usage:
#   eval $(tools/resolve-remotes.sh [OPTIONS] [REPO_PATH])
#   tools/resolve-remotes.sh --print [REPO_PATH]
#
# Options:
#   --org ORG           GitHub org to detect as upstream (default: osac-project)
#   --push-remote NAME  Explicitly select the push remote (skip auto-detection)
#   --print             Human-readable output instead of eval-able assignments
#   -h, --help          Show usage
#
# Output (eval mode):
#   UPSTREAM_REMOTE=origin
#   PUSH_REMOTE=fork
#
# Exit codes:
#   0  Upstream remote resolved (PUSH_REMOTE may be empty for read-only clones)
#   1  No remote matches the upstream org
#   2  Usage error
set -euo pipefail

ORG="osac-project"
PRINT=false
REPO_PATH=""
EXPLICIT_PUSH_REMOTE=""

usage() {
  sed -n '2,/^[^#]/{ /^#/s/^# \?//p }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      [[ -n "${2:-}" ]] || { echo "error: --org requires a value" >&2; exit 2; }
      ORG="$2"; shift 2 ;;
    --push-remote)
      [[ -n "${2:-}" ]] || { echo "error: --push-remote requires a value" >&2; exit 2; }
      EXPLICIT_PUSH_REMOTE="$2"; shift 2 ;;
    --print)  PRINT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "error: unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -z "$REPO_PATH" ]] || { echo "error: unexpected argument: $1" >&2; exit 2; }
      REPO_PATH="$1"; shift ;;
  esac
done

REPO_PATH="${REPO_PATH:-.}"

if ! git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $REPO_PATH is not a git repository" >&2
  exit 2
fi

ORG_ESC=$(printf '%s' "$ORG" | sed 's/[.+?{}()|\\[^$*]/\\&/g')

UPSTREAM_REMOTE=""
PUSH_REMOTE=""
push_candidates=()

while IFS= read -r remote; do
  fetch_url=$(git -C "$REPO_PATH" remote get-url "$remote" 2>/dev/null || true)
  push_url=$(git -C "$REPO_PATH" remote get-url --push "$remote" 2>/dev/null || true)
  if echo "$fetch_url" | grep -qE "[:/]${ORG_ESC}/[^/]+(\.git)?$"; then
    if [[ -z "$UPSTREAM_REMOTE" ]]; then
      UPSTREAM_REMOTE="$remote"
    fi
  fi
  # Effective push URL (may differ via pushurl) decides push candidacy independently.
  if [[ -n "$push_url" ]] && ! echo "$push_url" | grep -qE "[:/]${ORG_ESC}/[^/]+(\.git)?$"; then
    push_candidates+=("$remote")
  fi
done < <(git -C "$REPO_PATH" remote)

if [[ -n "$EXPLICIT_PUSH_REMOTE" ]]; then
  if git -C "$REPO_PATH" remote get-url "$EXPLICIT_PUSH_REMOTE" >/dev/null 2>&1; then
    PUSH_REMOTE="$EXPLICIT_PUSH_REMOTE"
  else
    echo "error: --push-remote '$EXPLICIT_PUSH_REMOTE' does not exist in this repository" >&2
    exit 2
  fi
elif [[ ${#push_candidates[@]} -eq 1 ]]; then
  PUSH_REMOTE="${push_candidates[0]}"
elif [[ ${#push_candidates[@]} -gt 1 ]]; then
  for c in "${push_candidates[@]}"; do
    if [[ "$c" == "fork" ]]; then
      PUSH_REMOTE="$c"
      break
    fi
  done
  if [[ -z "$PUSH_REMOTE" ]]; then
    PUSH_REMOTE="${push_candidates[0]}"
  fi
  echo "warning: multiple push remote candidates: ${push_candidates[*]}; using '${PUSH_REMOTE}'" >&2
  echo "  hint: use --push-remote NAME to select explicitly" >&2
fi

REPO_NAME=""
if [[ -n "$UPSTREAM_REMOTE" ]]; then
  REPO_NAME=$(git -C "$REPO_PATH" remote get-url "$UPSTREAM_REMOTE" 2>/dev/null \
    | sed -E 's|\.git$||; s|.*/||')
fi

if [[ -z "$UPSTREAM_REMOTE" ]]; then
  local_name=$(basename "$(git -C "$REPO_PATH" rev-parse --show-toplevel)")
  echo "error: no remote points to ${ORG}/ in $local_name" >&2
  echo "  Add one (any name works): git -C \"$REPO_PATH\" remote add <name> https://github.com/${ORG}/<repo>.git" >&2
  exit 1
fi

redact_url() {
  sed -E 's|://[^@]+@|://***@|'
}

if [[ "$PRINT" == true ]]; then
  echo "Repository:      ${REPO_NAME}"
  echo "Upstream remote:  ${UPSTREAM_REMOTE} ($(git -C "$REPO_PATH" remote get-url "$UPSTREAM_REMOTE" | redact_url))"
  if [[ -n "$PUSH_REMOTE" ]]; then
    echo "Push remote:      ${PUSH_REMOTE} ($(git -C "$REPO_PATH" remote get-url --push "$PUSH_REMOTE" | redact_url))"
  else
    echo "Push remote:      (none — read-only clone)"
  fi
else
  printf 'UPSTREAM_REMOTE=%q\n' "$UPSTREAM_REMOTE"
  printf 'PUSH_REMOTE=%q\n' "$PUSH_REMOTE"
fi
