# Smell catalog

Use this file during passes 1 and 2. Each entry is a *class* of problem, not a word ban. Apply the clean-draft test from `SKILL.md` before cutting.

## Pass 1: process leakage

These are the primary targets. They appear when a model revises a document from conversation history and leaves the revision process in the text.

### Process aside

**Detect.** A clause whose only job is to record a decision from the edit thread. Common shapes:

- `(there is no X)`, `(not Y)`, `(use X, not Y)` when the command or heading already states X
- `(previously Y)`, `(formerly Y)`, `(was Y)`
- `(updated)`, `(revised)`, `(new)`

**Why.** The reader did not see the rejected draft. Contrast with the rejected draft is author-facing.

**Fix.** Keep the current instruction. Drop the aside.

**Keep when.** The reader must choose between two live options (two supported APIs, two env vars, a deprecated endpoint that still exists in production). State both as current facts: "Use `/v2/tokens`. `/v1/tokens` still works until 2026-12-01."

### Changelog sentence

**Detect.** "Previously X, now Y." "We used to..." "This used to say..." "Replaced X with Y." "No longer includes X."

**Why.** The document has become a diff.

**Fix.** State Y. Delete the history unless the file is a CHANGELOG, release note, or ADR.

### Deletion residue

**Detect.** Text that exists to explain an absence: "X was removed", "we dropped the old section", "do not use the previous method", "the Foo approach was considered and rejected."

**Why.** Models prefer to retain or wrap material they were asked to delete rather than omit it. The prose analog is a sentence about the deletion.

**Fix.** Delete the sentence. Do not replace it with a note that something was deleted.

**Keep when.** The absent thing is still reachable (old URL, old flag, old package name) and users will hit it. Then write a current warning: "The `install` subcommand is not part of this CLI." Only do that if the trap is real for the reader, not because the writing session discussed it.

### Rewrite narration

**Detect.** "I've updated this to...", "As requested...", "Per your feedback...", "This revision...", "Let me rewrite...", "Sure, here is the cleaned version:" inside the artifact.

**Why.** Chatbot framing leaked into the document.

**Fix.** Delete. If the sentence also contains a fact, keep the fact and drop the frame.

### Correction aside

**Detect.** A second sentence that exists only to overrule the first, or a parenthetical that argues with a phrasing no longer present. "Not a checklist: a procedure." "This is not X; it is Y" when X never appears.

**Why.** The model is still talking to the earlier draft.

**Fix.** Write Y once, in the positive.

**Keep when.** X is a live misconception the audience actually holds (security: "the API key is not a session token").

### Ghost text / residual glue

**Detect.** Orphan transitions after a cut ("Additionally," with nothing added; "As mentioned above" with no prior mention; "the latter" with one item left). Duplicated headings. A list of two items that used to be three and still says "three ways."

**Why.** Surrounding glue survived the deletion.

**Fix.** Repair the grammar and count. Remove the orphan transition.

### Context carry-over

**Detect.** A paragraph that answers a question from the chat, not a question the document's audience has. Specs that suddenly address "your earlier point about mTLS." Emails that recap the prompt.

**Why.** Conversation elements bled into a document with a different audience.

**Fix.** Rewrite for the document's reader. Move chat-only context to the reply.

## Pass 2: leftover AI voice

Flag these only when they are cheap to fix and do not carry meaning. Do not hunt style for its own sake.

### Stock diction

Empty intensifiers and stock phrases that rarely survive a human edit: "delve", "tapestry", "landscape", "embark", "leverage" (as a verb for "use"), "robust" with no failure mode named, "comprehensive", "it's important to note", "in today's rapidly evolving", "unlock", "empower", "streamline", "cutting-edge", "utilize" for "use".

**Fix.** Use the plain verb or drop the sentence.

### Throat-clearing

Openings that delay the point: "In this document, we will...", "Let's dive in", "When it comes to X", "It's worth noting that."

**Fix.** Start with the fact or the instruction.

### Symmetry filler

Three-item lists, three-adjective stacks, and mirrored section headings produced because the model likes balance, not because the subject has three parts.

**Fix.** Cut the item that is only there to complete the set.

### Hedging theater

A confident claim immediately walked back by "it depends", "generally", "it is important to consider" with no actual constraint. Or the reverse: false precision ("100%", "always", "never") on something unverified.

**Fix.** State the known range, or the condition, once. See the project's analysis/verification rules for causal or quantitative claims.

### Bold and recap spam

Every other sentence bolded. A "Key takeaways" box that restates the previous 12 lines. "In conclusion" on a 200-word README.

**Fix.** Bold terms of art on first use, not whole clauses. Delete the recap if the body already said it.

## Pass 3: documentation debt

Not unique to AI, but iterative AI edits accumulate it faster.

- Obvious statements the audience already knows ("Git is a version control system")
- Sections that contradict a later revision and were not deleted
- Duplicate instructions in two headings
- "TODO" or "TBD" that the revision was supposed to resolve, now left as decoration

**Fix.** Delete or merge. Do not add a sentence about the merge.

## Glossary

Names for the same failure, if the user uses them:

| Term | Means here |
|---|---|
| Process leakage / chatbot artifacts | Edit-thread language inside the artifact |
| Deletion avoidance | Keeping or wrapping text that should be omitted |
| Residual glue / ghost text | Orphan transitions and traces after a cut |
| Context pollution / carry-over | Chat history answering in the document |
| AI documentation debt | Stale or obvious material piled up by iterative generation |
