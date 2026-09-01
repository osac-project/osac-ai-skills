#!/usr/bin/env bash
# Smoke test for `make docs` — skillsaw docs catalog into docs/.
# Run from a checkout of this repo:
#   bash tools/test/skillsaw-docs-smoke.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

cd "$ROOT"

skill_names=()
for skill_md in skills/*/SKILL.md; do
  [[ -f "$skill_md" ]] || continue
  skill_names+=("$(basename "$(dirname "$skill_md")")")
done
((${#skill_names[@]} > 0)) || fail "no skills/*/SKILL.md found"

# Remove any leftover docs/ so `make docs` cannot succeed as
# "Nothing to be done" for a directory named docs without a recipe.
rm -rf docs/

make docs || fail "make docs failed"

[[ -f docs/index.html ]] || fail "docs/index.html missing after make docs"
rg -q -i '<html' docs/index.html || fail "docs/index.html is not HTML"

for name in "${skill_names[@]}"; do
  rg -q -F "$name" docs/index.html || fail "docs/index.html missing skill ${name}"
done
pass "catalog lists ${#skill_names[@]} skills"

if [[ -n $(git ls-files -- docs/) ]]; then
  dirty=$(git status --porcelain -- docs/)
  [[ -z "$dirty" ]] || fail "docs/ dirty after make docs:"$'\n'"$dirty"
  pass "docs/ matches git after regen"
else
  pass "docs/ not tracked yet; skipping idempotency check"
fi
