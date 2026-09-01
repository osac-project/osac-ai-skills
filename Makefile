# Local skillsaw lint — keep SKILLSAW_VERSION in sync with
# .github/workflows/skillsaw.yml `version:` input.
.PHONY: skillsaw docs help

SKILLSAW_VERSION ?= 0.17.0
SKILL ?= .

help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

skillsaw: ## Lint repo or one skill (SKILL=skills/<name>/; version pinned here)
	uvx --from skillsaw==$(SKILLSAW_VERSION) skillsaw lint $(SKILL) --strict --no-baseline

docs: ## Generate GitHub Pages catalog into docs/
	uvx --from skillsaw==$(SKILLSAW_VERSION) skillsaw docs -o docs/ --title "OSAC AI Skills" --theme indigo
	touch docs/.nojekyll
