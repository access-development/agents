---
name: ai-linter
description: |
  Review AI-produced prose and emit a clean current artifact. Primary target is
  process leakage: parenthetical asides, "(previously X, now Y)", notes about
  removed material, rewrite commentary, and other edit-history residue that
  turns a document into a changelog. Also flags leftover chatbot framing and
  stock AI diction. This skill should be used when the user asks to lint, scrub,
  or review AI-written prose; remove AI smells or process residue; clean a
  README, spec, email, or skill after a revision; or mentions /ai-linter,
  ghost text, deletion residue, or that a doc "reads like a draft conversation."
trigger: |
  Use when the user wants AI-produced text reviewed or rewritten into a finished
  document: "lint this README", "scrub AI smells", "remove process residue",
  "/ai-linter", or after an iterative rewrite of docs, skills, emails, or specs.
---

# AI linter

Review AI-produced text and return the version a competent human would ship if they had written it once, from scratch, for the intended reader.

The model that wrote the draft can see the whole conversation: prior versions, rejected wording, and the user's edit requests. It does not keep a hard line between "notes about the change" and "the document." Those notes leak. The linter's job is to put that line back.

## Output contract

The artifact contains only what the audience needs now.

- Do not mention prior drafts, removed commands, renamed sections, or why a sentence changed.
- Do not add a preface, changelog, or rewrite narration inside the document.
- A short finding list belongs in the chat reply, never in the artifact.

**Clean-draft test.** For each flagged sentence, ask: would this exist if the author had written the final version with no prior draft and no review thread? If no, cut it or rewrite it as a standalone statement of the current fact.

## Modes

| User ask | Mode | Deliver |
|---|---|---|
| "lint this README", "what smells", "review this draft" | Review | Findings in chat. Do not edit the file. |
| "clean this", "scrub AI smells", "/ai-linter" on a file | Rewrite | Edit the file. Summarize cuts in chat. |
| Unclear | Review first | Then ask whether to apply. |

Default to the smallest change that removes the residue. Do not restyle a document that is already clean.

## Procedure

1. Identify the artifact (file, selection, paste, or last draft) and its audience. A README reader is not the author. A CHANGELOG reader is expecting history.
2. If the text is on disk, run the first-pass scan from this skill directory:

   ```bash
   bash <skill-dir>/scripts/scan.sh <path>
   ```

   `<skill-dir>` is the directory that contains this `SKILL.md`. Hits are candidates, not proof. Skip the script for a paste or last-draft with no file. If the path is a directory, scan it, then lint the files that matter (the ones the user named, or the ones with hits).
3. Load `references/smells.md`. Run **pass 1 (process leakage)** first, then pass 2 and pass 3. The pass-1 classes are: process aside, changelog sentence, deletion residue, rewrite narration, correction aside, ghost text, context carry-over.
4. Load `references/examples.md` when keep-versus-cut is not obvious (live constraint vs residue, troubleshooting vs happy path, history file vs how-to).
5. Apply the clean-draft test to every remaining edit. If a distinction is one the *reader* independently needs (API constraint, breaking change, safety warning), keep it as a current fact, not as a contrast with a deleted draft.

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
- Do not replace residue with a different AI tell (new hedging, new throat-clearing, a recap box).

## Review output (chat)

Use a compact table:

| Location | Smell | Quote | Fix |
|---|---|---|---|
| README.md:16 | Process aside | `(there is no npx skills install)` | Drop the clause. Keep the current command. |

Sort process leakage first. Skip nits when the document is otherwise shippable. If nothing fails the clean-draft test, say so and stop.
