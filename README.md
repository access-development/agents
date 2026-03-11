# agents

**AI agent skills for integrating with Access Development's loyalty and rewards platform.**

Ready-to-use AI agent skills that teach coding assistants how to work with Access Development APIs. Compatible with **Claude Code, Cursor, Windsurf, GitHub Copilot**, and [40+ other agents](https://github.com/vercel-labs/sdk/tree/main/packages/skills). Built by [Access Development](https://www.accessdevelopment.com/) — America's largest loyalty and rewards network.

## Skills

| Skill | Description |
|---|---|
| [access-travel-integration](skills/access-travel-integration/) | Integrate the Access Development Travel Platform — server-side authentication, SDK embedding, deep linking (hotels, cars, theme parks, activities, flights), and event handling. |

## Installation

The easiest way to install is with the `skills` CLI:

```bash
npx skills add access-development/agents
```

This works with Claude Code, Cursor, Windsurf, GitHub Copilot, and many more — no Vercel account required.

### Install options

```bash
# List available skills without installing
npx skills add access-development/agents --list

# Install all skills to all detected agents
npx skills add access-development/agents --all

# Install to a specific agent
npx skills add access-development/agents --skill '*' --agent claude-code
npx skills add access-development/agents --skill '*' --agent cursor

# Install globally (user-level, applies to all projects)
npx skills add access-development/agents --all --global
```

### Manual setup (Claude Code)

If you prefer not to use the CLI, add the skill directly to your project's `.claude/settings.json`:

```json
{
  "skills": [
    "/path/to/agents/skills/access-travel-integration/SKILL.md"
  ]
}
```

Then ask your agent to help with travel platform integration — it will automatically use the skill.

## Repository Structure

```
skills/
  access-travel-integration/
    SKILL.md                  # Skill definition (loaded by the agent)
    references/               # Parameter docs, attraction IDs, OpenAPI spec
    scripts/                  # Utilities (e.g. fetch-attractions.sh)
```

## License

Copyright Access Development. All rights reserved.
