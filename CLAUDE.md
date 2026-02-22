# Project Guidelines

This repository is a collection of self-contained skills for AI code agents.

## Creating a New Skill

Every skill follows the same structure:

```
skill-name/
├── SKILL.md           # Main documentation (required)
├── .env.sample        # Template for environment variables (required)
└── scripts/
    └── main-script.sh # Executable helper script (required)
```

### SKILL.md

Must include YAML front matter with `name` and `description` fields. The description should list trigger keywords and use cases so the agent knows when to activate the skill.

Sections to include in order:
1. **Title & one-liner** — what the skill does
2. **Prerequisites** — required environment variables, how to obtain credentials, token loading logic (env var first, `.env` fallback)
3. **Helper Script** — path, chmod instructions, alias convention
4. **Operations Reference** — one subsection per command with usage examples
5. **Patterns & Best Practices** — common workflows and recipes
6. **Error Handling** — HTTP error codes table with causes and fixes
7. **Security Notes** — credential hygiene reminders

### .env.sample

List every required environment variable with placeholder values. One variable per line, no quotes around values.

### scripts/

- One main bash script named after the skill (e.g., `gist.sh`, `confluence.sh`).
- Must start with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Dependencies: `curl` and `jq` only. No other external tools.
- Must load credentials from environment variables first, falling back to a `.env` file in the skill root directory:
  ```bash
  if [[ -z "${MY_TOKEN:-}" ]]; then
    SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [[ -f "$SKILL_DIR/.env" ]]; then
      export $(grep -v '^#' "$SKILL_DIR/.env" | xargs)
    fi
  fi
  ```
- Must include a `die()` function for error logging.
- Must include a single HTTP wrapper function that captures both the response body and HTTP status code, and exits non-zero on 4xx/5xx.
- Must include a `help` command that prints usage from the script header comments.
- Command dispatch via a `case` statement at the bottom.
- Mark the script executable (`chmod +x`).

### Conventions

- Skill directory names use lowercase with hyphens (e.g., `github-gist`, `atlassian-confluence`).
- The `.env` file is git-ignored globally — never commit credentials.
- Keep scripts portable: no bashisms beyond what `bash 4+` supports, no OS-specific tools.
- Output should be machine-readable (tab-separated or JSON) with human-readable errors to stderr.
- Always confirm destructive operations (delete) with the user before executing.
