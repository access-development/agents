# Before / after

Each "before" would fail the clean-draft test. The "after" is what to emit in the artifact. Chat-only commentary stays out of the after.

## 1. Process aside in install docs

**Before**

```markdown
The easiest way to install is with the `skills` CLI. The command is `add` (there is no `npx skills install`):

npx skills add access-development/agents
```

**After**

```markdown
Install with the `skills` CLI:

npx skills add access-development/agents
```

The parenthetical exists because a writing session discussed a wrong command. A first-draft README would just show the command. If `install` is a real, recurring trap for this audience, put it in a troubleshooting section as a current fact, not as an inline aside next to the happy path.

## 2. Changelog sentence in a how-to

**Before**

> Previously we told clients to register the skill in `.claude/settings.json`. Now copy the skill folder into `.claude/skills/` instead.

**After**

> Copy the skill folder into `.claude/skills/`.

Keep the old path only if readers will still find it in shipped docs and need a migration note. That belongs in a dated "Migrating from settings.json" section, not in the install steps.

## 3. Deletion residue

**Before**

> Domain allowlisting is required. (The localhost exception section was removed; localhost is not supported.)

**After**

> Domain allowlisting is required. The SDK does not load on `localhost`. Use a custom local hostname and have it allowlisted.

The current constraint stays. The note that a section was removed does not.

## 4. Rewrite narration inside the artifact

**Before**

> I've revised the loyalty overview to be clearer. Access calls five REST endpoints on your server.

**After**

> Access calls five REST endpoints on your server.

## 5. Correction aside vs live misconception

**Residue (cut)**

> This is not a settings.json path list; it is a folder you copy.

Nobody reading the finished install section is holding `settings.json` unless the doc just mentioned it.

**Live misconception (keep, rewritten as a current fact)**

> The API key must not go in the browser. Proxy token creation through your backend.

## 6. Ghost text after a cut

**Before**

> There are three ways to authenticate. Additionally, use a bearer token.

(The other two ways were deleted.)

**After**

> Authenticate with a bearer token.

## 7. Leave it alone

**Not residue**

> Access will not fall back to TLS 1.2.

That is a current protocol constraint. It would appear in a first draft.

**Not residue**

```markdown
## 2026-08-14

- Replaced the settings.json install path with folder copy.
```

inside `CHANGELOG.md` or a release note. History is the job of that file.

**Not residue**

> Use `npx skills add`. The CLI has no `install` command.

only when this is a dedicated troubleshooting row whose audience is people who typed `install` and failed. Even then, write it as a current CLI fact, not as "(there is no...)".
