#!/usr/bin/env bash
# Temp-file and Jira-credential helpers for jira-cli safe create (mktemp +
# EXIT trap cleanup, plus jira_login()/jira_token() for skills that need
# direct REST calls).
#
# Shared tooling for osac-ai-skills-hosted skills (jira-task-management,
# report-bug, capture-tasks-from-meeting-notes). Consumers resolve this
# script from their vendored osac-ai-skills checkout (see each skill's
# resolution snippet) rather than carrying their own copy.
#
# Source (do not execute — defines shell functions):
#   source "${OSAC_AI_SKILLS_DIR}/tools/jira-safe-create.sh"
#
# Call new_temp for each temp path, then add_temp in the parent shell after
# assignment. add_temp inside $(new_temp ...) runs in a subshell and the EXIT
# trap will not see those paths.

if [[ -n "${JIRA_SAFE_CREATE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
JIRA_SAFE_CREATE_LOADED=1

_JSC_TEMP_FILES=()
_JSC_PREV_EXIT_TRAP=""

# Unescape the command body from `trap -p EXIT` (trap -- 'body' EXIT / "body").
_jsc_capture_prev_exit() {
  _JSC_PREV_EXIT_TRAP=""
  local tp
  tp=$(trap -p EXIT 2>/dev/null || true)
  [[ -z "$tp" ]] && return 0
  tp=${tp#trap -- }
  tp=${tp% EXIT}
  # shellcheck disable=SC2086 # intentional: tp is a shell-quoted string from trap -p
  _JSC_PREV_EXIT_TRAP=$(eval "printf '%s\n' $tp")
}

_jsc_cleanup() {
  if ((${#_JSC_TEMP_FILES[@]} > 0)); then
    rm -f "${_JSC_TEMP_FILES[@]}"
  fi
  if [[ -n "${_JSC_PREV_EXIT_TRAP}" ]]; then
    eval "${_JSC_PREV_EXIT_TRAP}"
  fi
}

# Install our EXIT wrapper. Re-wrap when a later trap replaced us (call from add_temp).
_jsc_install_exit_trap() {
  local tp
  tp=$(trap -p EXIT 2>/dev/null || true)
  if [[ "$tp" == *"_jsc_cleanup"* ]]; then
    return 0
  fi
  _jsc_capture_prev_exit
  trap '_jsc_cleanup' EXIT
}

_jsc_install_exit_trap

add_temp() {
  _JSC_TEMP_FILES+=("$1")
  # Callers who set EXIT after sourcing replace our trap; re-chain on register.
  _jsc_install_exit_trap
}

new_temp() {
  local prefix=${1:-osac-jira}
  mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Configured Jira username, for skills that build `curl -K -` credentials
# (`user = "$(jira_login):${JIRA_API_TOKEN}"`) to call the Jira REST API
# directly for operations jira-cli itself can't perform. Returns 1 (and
# prints nothing) if the config file is missing, unreadable, or has no
# non-empty `login:` value — `grep | awk`'s own exit status is awk's, which
# is 0 even when grep found nothing, so callers can't rely on it alone.
jira_login() {
  local config=~/.config/.jira/.config.yml login
  if [ ! -r "$config" ]; then
    echo "jira_login: ${config} not found or unreadable — run 'jira init' first" >&2
    return 1
  fi
  login=$(grep '^login:' "$config" | awk '{print $2}')
  if [ -z "$login" ]; then
    echo "jira_login: no 'login:' value in ${config}" >&2
    return 1
  fi
  printf '%s\n' "$login"
}

# Jira API token for the same `curl -K -` credentials, preferring
# $JIRA_API_TOKEN and falling back to the password field of the
# `machine redhat.atlassian.net` entry in ~/.netrc — the same file
# jira-cli itself authenticates from (see jira-task-management/SKILL.md's
# "Auth: Bearer token in ~/.netrc" setup). Assumes a single-line netrc
# entry (`machine redhat.atlassian.net login <user> password <token>`),
# matching this repo's documented format; does not handle netrc's
# multi-line or `macdef` syntax. Returns 1 if neither source has a token.
jira_token() {
  if [ -n "${JIRA_API_TOKEN:-}" ]; then
    printf '%s\n' "$JIRA_API_TOKEN"
    return 0
  fi
  local netrc=~/.netrc token
  if [ ! -r "$netrc" ]; then
    echo "jira_token: \$JIRA_API_TOKEN not set and ${netrc} not found or unreadable" >&2
    return 1
  fi
  token=$(awk '
    /^machine[[:space:]]+redhat\.atlassian\.net([[:space:]]|$)/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "password" && i < NF) { print $(i + 1); exit }
      }
    }
  ' "$netrc")
  if [ -z "$token" ]; then
    echo "jira_token: \$JIRA_API_TOKEN not set and no 'machine redhat.atlassian.net' password entry in ${netrc}" >&2
    return 1
  fi
  printf '%s\n' "$token"
}
