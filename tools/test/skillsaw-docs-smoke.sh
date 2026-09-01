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

# Remove docs/ so the run proves the generator recreates every file
# rather than leaving stale output in place.
restore_docs() {
  git checkout -- docs/ 2>/dev/null || true
}
trap restore_docs EXIT
rm -rf docs/

make docs || fail "make docs failed"
trap - EXIT

[[ -f docs/index.html ]] || fail "docs/index.html missing after make docs"
rg -q -i '<html' docs/index.html || fail "docs/index.html is not HTML"

for name in "${skill_names[@]}"; do
  rg -q -F "\"name\": \"${name}\"" docs/index.html \
    || fail "docs/index.html missing skill ${name}"
done
pass "catalog lists ${#skill_names[@]} skills"

if [[ -n $(git ls-files -- docs/) ]]; then
  git diff --exit-code -- docs/ \
    || fail "make docs changed staged/committed docs/ (catalog should be generator output only)"
  untracked=$(git ls-files --others --exclude-standard -- docs/)
  [[ -z "$untracked" ]] || fail "untracked files under docs/: $untracked"
  pass "docs/ matches git after regen"
else
  pass "docs/ not tracked yet; skipping idempotency check"
fi
