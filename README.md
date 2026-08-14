# agents

**AI agent skills for integrating with Access Development's loyalty and rewards platform.**

Ready-to-use AI agent skills that teach coding assistants how to work with Access Development APIs. Compatible with **Claude Code, Cursor, Windsurf, GitHub Copilot**, and [40+ other agents](https://github.com/vercel-labs/sdk/tree/main/packages/skills). Built by [Access Development](https://www.accessdevelopment.com/) — America's largest loyalty and rewards network.

## Skills

| Skill | Description |
|---|---|
| [access-travel-integration](skills/access-travel-integration/) | Integrate the Access Development Travel Platform — server-side authentication, SDK embedding, deep linking (hotels, cars, theme parks, activities, flights), and event handling. |
| [loyalty-points-integration](skills/loyalty-points-integration/) | Implement the Access Loyalty Points API — five REST endpoints for balance, holds, redemption, refund, and cancellation. Covers the OpenAPI 3.0 contract, mTLS intake (app vs cloud LB vs reverse proxy), platform recipes, idempotency, hold lifecycle, and testing. |

## Installation

Install with the `skills` CLI:

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

### Manual setup

If you prefer not to use the CLI, copy each skill folder (the directory that contains `SKILL.md` plus any `references/` or `scripts/`) into the agent's skills directory.

Claude Code, project-level:

```bash
git clone https://github.com/access-development/agents.git
mkdir -p .claude/skills
cp -R agents/skills/access-travel-integration .claude/skills/
cp -R agents/skills/loyalty-points-integration .claude/skills/
```

Claude Code, user-level (all projects):

```bash
mkdir -p ~/.claude/skills
cp -R agents/skills/access-travel-integration ~/.claude/skills/
cp -R agents/skills/loyalty-points-integration ~/.claude/skills/
```

Common paths for other agents:

| Agent | Project | Global |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Cursor | `.agents/skills/` | `~/.cursor/skills/` |
| GitHub Copilot | `.agents/skills/` | `~/.copilot/skills/` |
| Grok Build | `.grok/skills/` | `~/.grok/skills/` |
| Windsurf | `.windsurf/skills/` | `~/.codeium/windsurf/skills/` |

Then ask your agent to help with travel platform or loyalty points integration. It will pick up the matching skill.

## Repository Structure

```
skills/
  access-travel-integration/
    SKILL.md                  # Skill definition (loaded by the agent)
    references/               # Parameter docs, attraction IDs, OpenAPI spec
    scripts/                  # Utilities (e.g. fetch-attractions.sh)
  loyalty-points-integration/
    SKILL.md                  # Skill definition (loaded by the agent)
    references/               # OpenAPI spec, mTLS config guide, endpoint reference, lifecycle rules, testing
```

## License

Copyright Access Development. All rights reserved.
