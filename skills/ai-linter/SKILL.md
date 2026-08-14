---
name: ai-linter
description: |
  Review AI-produced prose and emit a clean current artifact. Primary target is
  process leakage: parenthetical asides, "(previously X, now Y)", notes about
  removed material, rewrite commentary, and other edit-history residue that
  turns a document into a changelog. Also flags leftover chatbot framing and
  stock AI diction. Use when asked to lint, scrub, or review AI-written text;
  remove AI smells; clean a README, spec, email, or skill after a revision;
  or when someone mentions /ai-linter, process leakage, ghost text, deletion
  residue, or "this reads like a draft conversation."
trigger: |
  Use when the user wants AI-produced text reviewed or rewritten into a finished
  document: "lint this", "scrub AI smells", "remove process residue",
  "/ai-linter", or after an iterative rewrite of docs, skills, emails, or specs.
---

# AI linter

Review AI-produced text and return the version a competent human would ship if they had written it once, from scratch, for the intended reader.

The model that wrote the draft can see the whole conversation: prior versions, rejected wording, and the user's edit requests. It does not keep a hard line between "notes about the change" and "the document." Those notes leak. The linter's job is to put that line back.

## Output contract

The artifact contains only what the audience needs now.

- Do not mention prior drafts, removed commands, renamed sections, or why a sentence changed.
- Do not add a preface, changelog, or "I've updated this to..." inside the document.
- A short finding list belongs in the chat reply, never in the artifact.

**Clean-draft test.** For each flagged sentence, ask: would this exist if the author had written the final version with no prior draft and no review thread? If no, cut it or rewrite it as a standalone statement of the current fact.

## Modes

| User ask | Mode | Deliver |
|---|---|---|
| "lint", "review", "what smells" | Review | Findings only. Do not rewrite unless asked. |
| "clean this", "scrub", "fix the smells", "/ai-linter" on a file | Rewrite | Apply edits. Summarize cuts in chat. |
| Unclear | Review first | Then ask whether to apply. |

Default to the smallest change that removes the residue. Do not restyle a document that is already clean.

## Procedure

1. Identify the artifact (file, selection, or last draft) and its audience. A README reader is not the author. A CHANGELOG reader is expecting history.
2. Run `scripts/scan.sh <path>` when the text is on disk. Treat hits as candidates, not proof. Load `references/smells.md` for the pass-1 and pass-2 definitions. Load `references/examples.md` before rewriting if the case is close.
3. **Pass 1: process leakage** (do this first; it is the point of the skill). Cut or rewrite:
   - Parentheticals that exist to record a decision ("the command is `add` (there is no `npx skills install`)")
   - "Previously X, now Y", "formerly", "no longer", "we used to", "replaced X with Y"
   - Explanations of what was removed, dropped, or not done
   - Rewrite narration ("I've revised...", "updated to reflect feedback", "as requested")
   - Correction asides whose only job is to argue with an earlier draft
4. **Pass 2: leftover AI voice**, using the catalog in `references/smells.md`. Only flag diction or structure that a careful editor would cut. Do not flatten a real human voice into generic "plain style."
5. **Pass 3: documentation debt.** Drop stale, obvious, or filler material that accumulated across revisions and no longer earns its place.
6. Apply the clean-draft test to every remaining edit. If a distinction is one the *reader* independently needs (API constraint, breaking change, safety warning), keep it as a current fact, not as a contrast with a deleted draft.

## Preserve

Leave these alone unless the user asked to rewrite them:

- Facts, commands, identifiers, URLs, ticket keys, and constraints
- Documents whose job *is* history: CHANGELOG, release notes, ADR decision records, "What changed in v3"
- Quoted third-party text
- Legal or contract language
- Code, except comments that themselves leak process ("// removed the old parser")

A reader-facing constraint is not residue. "Access will not fall back to TLS 1.2" stays. "We no longer mention TLS 1.2 because..." does not.

## Rewrite rules

- Delete. Do not wrap the old sentence in a comment, footnote, or "note that."
- Prefer omission over a sentence about the omission.
- If two sentences exist because the second corrects the first, keep the corrected fact only.
- After edits, re-read the surrounding paragraph. Cutting residue often leaves a broken transition; fix the transition, do not restore the residue.
- Do not replace residue with a different AI tell (new hedging, new throat-clearing, a "In short," recap).

## Review output (chat)

Use a compact table:

| Location | Smell | Quote | Fix |
|---|---|---|---|
| README.md:16 | Process aside | `(there is no npx skills install)` | Drop the clause. Keep the `add` command. |

Sort process leakage first. Skip nits when the document is otherwise shippable. If nothing fails the clean-draft test, say so and stop.
