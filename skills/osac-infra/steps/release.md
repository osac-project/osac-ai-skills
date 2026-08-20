# Release Subcommand

`/osac-infra release` is a thin passthrough to the team's actual release
skill. Do not reimplement any release logic here.

## Invoke the Real Skill

Call the `Skill` tool with `skill: "osac-release"`, forwarding the user's
original request text as `args` if the Skill tool supports it, otherwise
just invoke it and let it run its own Step 0 intent parsing.

```
Skill({ skill: "osac-release" })
```

`osac-release` (`skills/osac-release/`, this repo) owns: component
discovery, version bumping, tagging, CI monitoring, OCI registry
verification, and umbrella chart publishing. See that skill's `SKILL.md`,
`guidelines.md`, and `steps/` for its full workflow -- none of it is
duplicated here.

If `osac-release` is ever renamed, moved, or superseded, update the
`Skill` call above. Do not silently fork or copy its logic into this file.
