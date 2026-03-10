# agents

**AI agent skills for integrating with Access Development's loyalty and rewards platform.**

Ready-to-use **Claude Skills** that teach AI coding agents how to work with Access Development APIs. Built by [Access Development](https://www.accessdevelopment.com/) — America's largest loyalty and rewards network.

## Skills

| Skill | Description |
|---|---|
| [access-travel-integration](skills/access-travel-integration/) | Integrate the Access Development Travel Platform — server-side authentication, SDK embedding, deep linking (hotels, cars, theme parks, activities, flights), and event handling. |

## Usage with Claude Code

Add the skill to your project's `.claude/settings.json`:

```json
{
  "skills": [
    "/path/to/agents/skills/access-travel-integration/SKILL.md"
  ]
}
```

Then ask Claude to help with travel platform integration — it will automatically use the skill.

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
