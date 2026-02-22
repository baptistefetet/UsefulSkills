# UsefulSkills

A curated collection of useful skills for AI code agents (Claude Code, etc.).

Each skill is a self-contained module that extends an agent's capabilities with ready-to-use tools and workflows.

## Available Skills

| Skill | Description |
|-------|-------------|
| [github-gist](./github-gist/) | CRUD operations on GitHub Gists — create, read, update, delete, list, search, and manage files. Use gists as lightweight snippet storage or key-value store. |
| [atlassian-confluence](./atlassian-confluence/) | CRUD operations on Confluence Cloud pages — create, read, update, delete, list, search pages and spaces via CQL. Publish documentation, build page trees, search wiki content. |

## What is a Skill?

A skill is a portable package that teaches a code agent how to perform a specific task. Each skill contains at least a **`SKILL.md`** file that describes the capability, its prerequisites, and how to use it.

## Installation

### Claude Code

Copy a skill folder into your Claude Code skills directory:

```bash
cp -r github-gist ~/.claude/skills/
```

Or reference this repository directly in your Claude Code configuration.

## License

MIT
