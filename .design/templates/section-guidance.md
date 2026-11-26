# OSAC Design Document — Section Guidance

Instructions for the AI on how to fill the design template (`design.md`).
Read during the `/draft` phase. Not part of the final output.

## Length

- Hard cap: 200 lines. Target: 150. Count every line, tables included. Only
  Mermaid diagrams, code blocks and the YAML frontmatter do not count.
- Hard cap: 2,000 words in total, tables included.
- Moving text into tables, lists or code to get under the cap does not count as
  cutting. A table row is a line.
- Over the cap means the design carries detail that belongs in the code, or it
  is two designs. Cut detail or propose a split. Never squeeze the same content
  into fewer, longer sentences.
- Cut in this order: content the PRD already states, implementation mechanics
  (function names, step-by-step code flow), repetition, explanations of obvious
  choices, low-risk alternatives.
- Never cut a rule that keeps results correct: atomic writes, duplicate
  prevention, crash and restore behavior.

## Plain language

These rules follow ASD-STE100 Simplified Technical English
(https://www.asd-ste100.org/), restated in our own words.

- At most 25 words per sentence. One claim per sentence. At most six sentences
  per paragraph.
- Active voice. Say who does what: "the fulfillment controller writes X to the
  ComputeInstance", not "X is projected into the hub".
- Use one word for one meaning, and the same word every time. Use the names the
  code uses. Spell out each acronym once.
- Prefer common words. When a concrete word exists, do not use abstract filler:
  contract, boundary, surface, shape, carry, hold, envelope, project/projection
  (as a verb), intent, posture, semantics.
- No semicolons. No "if/when/unless/only when" chains. When behavior depends on
  conditions, write a table of condition -> behavior.
- Define a term by what it is, never by what it is not. Put each definition on
  its own line, not in parentheses inside a rule.
- Write at level 1 or 2 of this ladder:
  - Level 1: "Uploads over the limit fail."
  - Level 2: "The upload service rejects files over the limit."
  - Level 4: "The ingestion layer enforces quota-based admission control on
    inbound payloads."

## Short on purpose

- The design is short by design: 150 lines target, 200 hard cap, 2,000
  words. A simple feature aims for 120 to 150 lines.
- Detail belongs in the implementation PRs and the decomposed stories. The
  design carries what a reviewer must approve and an implementer must know.
- A failure, an upgrade step or a size limit that changes what users see is a
  numbered point in its step section. It never gets its own section.

## General Rules

- **No customer or engagement names.** The `enhancement-proposals` repository
  is public. Describe the context as a technical capability, not as who asked.
- Write in third person, present tense.
- **No inline source markers.** Never write `[PRD: ...]`, `[Locked: D{N}]` or
  `[Research: §...]` in the text. The frontmatter `prd` field covers the PRD.
- **Say each fact once.** Do not restate a fact in another section. Link to
  the section that states it.
- **Incorporate, don't narrate.** Write a changed decision in its final form.
  Do not describe what the PRD first said or why a position was dropped.
- Do not invent requirements. If the PRD does not specify something, mark it
  as an assumption or an open question. Missing information is "To be
  determined — {what's needed}".
- **Formatting restraint.** Bold is for genuine emphasis. When every noun
  phrase is bold, nothing stands out.
- **Diagrams:** Mermaid only. A box per cluster or server, holding only the
  parts this design is about. Label every node and mark new parts. Arrows
  show the main flow only. No styling directives, ASCII art or PlantUML.
- **Keep all required headers.** There is no header linter. Reviewers and the
  automated review expect these topics. A section that does not apply gets one
  line, "N/A: {reason}", and nothing more.

## Per-Section Guidance

### YAML Frontmatter

- **authors** is the human who owns or requests this feature, never the AI
  assistant. Derive it from `git config user.email`, or ask the user.
- The other fields follow the template placeholders: slug title, ISO dates,
  Jira URL, and the PRD path (`prd.md`).

### Title and first paragraph

- Three to five sentences: what the system does after this design, the main
  new parts, and what each role gets. A reader who stops here knows the scope.
- Then one line: "Design for {feature} ({JIRA}). See the [PRD](prd.md)."
- Get the developer's yes on this paragraph before writing the rest.

### Today and with this design

- One table, at most five rows, when the design changes something that
  exists. Each row names an aspect a person notices, then today and after.

### How it works

- One Mermaid architecture diagram, at most 8 boxes. Then one bullet per
  step, three to five steps: a bold verb and one sentence.
- End with "Each step has its own section below."

### Definitions

- Only words a new team member would have to look up. At most six, one line
  each.

### Step sections

- One section per step from "How it works", in the same order and names.
  Numbered points run straight through the design.
- Each point makes one claim in its first sentence, with at most two
  sentences after it.
- The sequence diagram, if any, goes in the step it shows. At most one, with
  at most 4 participants and 8 messages.
- A point must make a reviewer decide something or an implementer build
  something. If it does neither, cut it.

### Guard Rails

- Required. Never cut this section for length.
- It holds the invariants that keep results correct: atomic writes, duplicate
  prevention, ordering, tenant isolation. It also states what happens on
  crash, restart, restore and failure.
- One numbered sentence per rule. Write "N/A: {reason}" only when the design
  truly has no such invariant.
- A design without this section is incomplete for a stateful or billing-like
  system.

### Security

- The security rules: input validation, authorization changes, data
  exposure, and how the feature enforces tenant isolation.
- If the feature inherits the existing security model, say so in one line
  and why that is enough. Do not invent concerns that do not apply.

### Where the code goes

- Three lines: new, changed, unchanged. Name components and repositories.
  "Unchanged" names the APIs, CRDs or protos that stay as they are.

### API

- Give one numbered entry per interface the design adds or changes: each
  proto service or method, CRD, topic or route. Do not pad the list, and do
  not invent an interface to reach a count. Test plans map cases to these
  entries. If the design changes no interface, write "N/A: {reason}".
- Then give the routes and config values as one short table or list. Each
  new config value states its default and who sets it.

### UX Alignment

- Include this section when the feature changes the UI, or when a matching
  `@temp-api` file exists in `osac-ux/libs/ui-components/src/api/v1/`. Name the
  screens or components and the osac-ux guidance it follows. Omit it otherwise.

### Alternatives

- At most three lines, one per alternative: the alternative and why not, in
  one sentence. Include "Do nothing" when a reviewer would ask about it.

### Not in this design

- One line naming the deferrals, with Jira keys where known.
- Unresolved questions go here as "Open: ...", at most three. When review
  resolves one, write the answer into its section and remove the entry.

## Before finishing

- Count the lines. Exclude only Mermaid diagrams, code blocks and the
  frontmatter. Tables count. If the count is over 200, cut and count again.
- Count the words, tables included. If the count is over 2,000, cut.
- Find any sentence over 25 words and split it.
- Search for semicolons, "unless", "only when", and "not the"/"rather than"
  definitions. Rewrite each one.
- Check that every correctness rule from your notes appears in Guard Rails.
  Search for "atomic", "duplicate", "idempotent" and "isolation".
- Read only the headings and the first sentence of each paragraph or bullet.
  They must tell the whole design.

## Applying review feedback

- A reviewer's question marks the point that caused it. Rewrite that point
  so the question cannot come up. Never add an "unless ..." or "only when"
  clause to an existing sentence.
- A question about a detail that does not change the design gets its answer
  in the PR thread, not in the design.
- Each revision round: rerun "Before finishing".
