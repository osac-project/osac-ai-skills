#!/usr/bin/env python3
"""Structural check backing tools/check-mandatory-reviewers.sh.

Parses skills/.config/create-pr-reviewers.yaml as real YAML (not text
patterns) and verifies the security-review entry is intact: present under
its exact name, mandatory is boolean true, enabled is not false, and skill
still points at its own skill file (a repointed skill: value would silently
swap out what "the mandatory reviewer" actually runs while every other
field stays untouched).

Usage: check-mandatory-reviewers.py <path-to-yaml>
"""
import sys

import yaml

MANDATORY_REVIEWER_NAME = "security-review"
EXPECTED_SKILL_PATH = "skills/security-review/SKILL.md"


def fail(message):
    """Print a FAIL line and exit non-zero."""
    print(f"FAIL: {message}")
    sys.exit(1)


def main():
    """Validate the mandatory security-review entry in the given YAML config."""
    if len(sys.argv) != 2:
        fail(f"usage: {sys.argv[0]} <path-to-yaml>")

    path = sys.argv[1]

    try:
        with open(path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        fail(f"{path} not found")
    except yaml.YAMLError:
        # Not `fail(f"...: {e}")` -- PyYAML's exception text often quotes a
        # snippet of the offending content for context, so a malformed
        # config containing a secret-shaped value would echo it straight
        # into CI logs. Point at the file instead of the parse error detail.
        fail(f"{path} is not valid YAML — check its syntax with a local YAML linter")

    if not isinstance(config, dict):
        fail(f"{path} does not parse to a mapping")

    reviewers = config.get("reviewers")
    if not isinstance(reviewers, list):
        fail(f"{path} has no top-level 'reviewers' list")

    # Exact, literal name match against the parsed structure -- not a
    # substring, line-anchor, or whitespace-tolerant search -- so a decoy
    # entry like "security-review-legacy"/"security-review-experimental",
    # or a padded name like "security-review " with a trailing space, is
    # never confused with the real one. A padded-name entry is treated
    # exactly like a missing entry (see the smoke test), not silently
    # accepted as "close enough."
    matches = [
        r for r in reviewers
        if isinstance(r, dict) and r.get("name") == MANDATORY_REVIEWER_NAME
    ]

    if not matches:
        fail(
            f"no '{MANDATORY_REVIEWER_NAME}' entry found in {path} — the "
            "mandatory security reviewer appears to have been removed. See "
            "skills/create-pr/references/reviewer-config.md's Mandatory "
            "Reviewers section."
        )

    if len(matches) > 1:
        fail(
            f"{len(matches)} entries named '{MANDATORY_REVIEWER_NAME}' in "
            f"{path} — check 7's name-uniqueness requirement is violated"
        )

    entry = matches[0]

    # `is True` / `is False`, not truthiness -- PyYAML already normalizes
    # every YAML 1.1 boolean spelling (True/TRUE/no/off/...) to a real bool,
    # so this is not vulnerable to the spelling-variant bypass a text-based
    # substring match would be.
    if entry.get("mandatory") is not True:
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} does not have "
            "'mandatory: true'"
        )

    if entry.get("enabled") is False:
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} has 'enabled: "
            "false' alongside 'mandatory: true' — create-pr's own "
            "validation checklist (check 9) should already reject this, "
            "but failing loudly here too"
        )

    actual_skill = entry.get("skill")
    if actual_skill != EXPECTED_SKILL_PATH:
        # Don't interpolate the raw `skill:` value into the FAIL line -- it's
        # PR-controlled YAML content, not a validated path, so it could carry
        # a secret-shaped value into CI logs. Point at the file instead of
        # echoing what it's set to.
        fail(
            f"'{MANDATORY_REVIEWER_NAME}' entry in {path} does not have "
            f"skill: {EXPECTED_SKILL_PATH!r} — the mandatory entry now "
            "points somewhere else, which defeats the guarantee even "
            "though name/mandatory/enabled all look intact; inspect "
            f"{path} directly to see what it's set to"
        )

    print(f"PASS: '{MANDATORY_REVIEWER_NAME}' entry present in {path}, mandatory: true, not disabled")


if __name__ == "__main__":
    main()
