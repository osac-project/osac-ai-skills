---
title: {slug}
authors: [{email}]
creation-date: {yyyy-mm-dd}
last-updated: {yyyy-mm-dd}
tracking-link: [{Jira URL}]
prd: "prd.md"
---

# {Feature name}

{One paragraph, 3-5 sentences: what the system does after this design, the main new parts, what each role gets.}

Design for {feature} ({JIRA}). See the [PRD](prd.md).

## Today and with this design

| | Today | With this design |
|---|---|---|
| {aspect a person notices} | {current} | {new} |

## How it works

{One Mermaid diagram, at most 8 boxes, new parts marked.}

- **{Step 1}.** {one sentence}

Each step has its own section below.

## Definitions

- **{Term}**: {what it is}

## {Step 1}

1. **{Rule, one sentence.}** {at most two sentences of reason or detail.}

## Guard Rails

{Required. The invariants that keep results correct: atomic writes, duplicate prevention, ordering, tenant isolation, what happens on crash, restart, restore and failure. Numbered, one rule each, never cut. "N/A: {reason}" only when the design has no such invariant.}

## Security

## Where the code goes

- **New:** {components}
- **Changed:** {components}
- **Unchanged:** {APIs, CRDs or protos}

## API

{New or changed APIs, topics, routes and config values as one short table or list. Give one numbered entry per affected interface (proto service/method, CRD, topic or route) first, so the test plan can map cases to them. If the design changes no interface, write "N/A: {reason}".}

## UX Alignment

{Only when the feature changes the UI or a matching `@temp-api` file exists:
the screens or components it touches, and the osac-ux guidance it follows.
Otherwise omit this section.}

## Alternatives

- **{Alternative}.** {why not, one sentence}

## Not in this design

{One line: deferrals, with Jira keys where known. Unresolved questions as "Open: ...", at most 3.}
