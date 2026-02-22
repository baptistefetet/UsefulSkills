---
name: github-gist
description: >
  CRUD operations on GitHub Gists via the REST API — create, read, update, delete,
  list, search, and manage files in gists. Use this skill whenever the user mentions
  gists, wants to store/retrieve snippets or data online, save code to a gist,
  share a snippet via gist URL, persist small data in a gist, read or modify an
  existing gist, or use gists as lightweight key-value storage. Also trigger when
  the user says "save this to gist", "post this snippet", "gist it", "store this
  online", or references a gist ID/URL. Works with any text content: code, config,
  notes, JSON data, logs, markdown.
---

# GitHub Gist Skill

Store, retrieve, and manage small pieces of data online via GitHub Gists.
Zero dependencies beyond `curl` and `jq`.

## Prerequisites

The user must have a `GITHUB_TOKEN` available. It can be provided in two ways:

1. **Environment variable** (preferred): `GITHUB_TOKEN` set in the shell environment.
2. **Local `.env` file** (fallback): A `.env` file located next to this `SKILL.md`
   (i.e., in the skill's root directory) containing `GITHUB_TOKEN=ghp_...`.

The token needs the **`gist`** scope (classic PAT) or **Gists read/write** permission (fine-grained PAT).

```bash
# If GITHUB_TOKEN is not set in the environment, source the .env file as fallback
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
if [ -z "$GITHUB_TOKEN" ] && [ -f "$SKILL_DIR/.env" ]; then
  export $(grep -v '^#' "$SKILL_DIR/.env" | xargs)
fi

# Verify the token is set
echo "${GITHUB_TOKEN:?GITHUB_TOKEN not set — export a token with gist scope or add it to .env}"
```

If neither source provides the token, instruct the user to:
1. Go to https://github.com/settings/tokens
2. Create a token with the `gist` scope
3. Either `export GITHUB_TOKEN="ghp_..."` or add it to the `.env` file in the skill directory

## Helper Script

All operations go through `scripts/gist.sh` bundled with this skill.
Make it executable before first use:

```bash
chmod +x /path/to/this/skill/scripts/gist.sh
```

Alias for convenience in the examples below:

```bash
GIST="bash /path/to/this/skill/scripts/gist.sh"
```

> **Important:** Replace `/path/to/this/skill/` with the actual path where this
> skill is installed (e.g., `~/.claude/skills/github-gist/`).

## Operations Reference

### List gists

```bash
$GIST list                       # default: 30 most recent
$GIST list --per-page 10        # paginate
$GIST list --per-page 50 --page 2
```

Output: one line per gist — `id  public/secret  date  description  [files]`

### Search gists by description/filename

```bash
$GIST search "config"
$GIST search "TODO"
```

Fetches up to 100 gists and greps locally. For heavier search, use the
GitHub search API directly:
```bash
curl -sH "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/search/code?q=keyword+in:file+user:USERNAME&type=Code" | jq
```

### Read a gist

```bash
$GIST get  <gist_id>                  # Full JSON (metadata + all files)
$GIST read <gist_id>                  # Print content of the first file
$GIST read <gist_id> "config.json"    # Print content of a specific file
```

- If the file is truncated (>1 MB), the script automatically fetches via `raw_url`.
- For gists referenced by URL like `https://gist.github.com/user/abc123`,
  extract the ID (`abc123`) and use it.

### Create a gist

```bash
echo '{"key": "value"}' | $GIST create "My config" "config.json"
echo '{"key": "value"}' | $GIST create "Public snippet" "data.json" --public
cat myfile.py          | $GIST create "Utility script" "utils.py"
```

- Reads content from **stdin**.
- Default visibility: **secret** (unlisted, not private — anyone with the URL can see it).
- Pass `--public` to make it discoverable.
- Returns the gist ID and the HTML URL.

### Update a file in a gist

```bash
echo 'new content' | $GIST update <gist_id> "config.json"
cat modified.py    | $GIST update <gist_id> "utils.py"
```

Overwrites the content of the named file. If the file doesn't exist yet,
it is created (equivalent to `add`).

### Add a file to an existing gist

```bash
echo 'extra data' | $GIST add <gist_id> "extra.txt"
```

Same as `update` under the hood — adding a new filename creates it.

### Remove a file from a gist

```bash
$GIST rm <gist_id> "obsolete.txt"
```

Deletes a single file from the gist. The gist itself remains.

### Rename a file in a gist

```bash
$GIST rename <gist_id> "old_name.txt" "new_name.md"
```

### Update a gist's description

```bash
$GIST desc <gist_id> "New description text"
```

### Delete a gist

```bash
$GIST delete <gist_id>
```

**Irreversible.** Always confirm with the user before executing.

## Patterns & Best Practices

### Using gists as lightweight key-value storage

A common pattern: one gist = one "namespace", each file = one key.

```bash
# Create a namespace
echo '{}' | $GIST create "myapp-settings" "db.json"
# → gist_id = abc123

# Write a key
echo '{"host":"localhost","port":5432}' | $GIST update abc123 "db.json"

# Read a key
$GIST read abc123 "db.json"

# Add another key
echo '{"level":"debug"}' | $GIST add abc123 "logging.json"
```

### Storing multi-file data

Gists natively support multiple files — use this instead of encoding
everything in one blob:

```bash
echo 'SELECT * FROM users' | $GIST create "SQL queries" "users.sql"
# then add more files:
echo 'SELECT * FROM orders' | $GIST add <id> "orders.sql"
```

### Piping command output

```bash
# Save current env to a private gist
env | $GIST create "Env snapshot $(date +%F)" "env.txt"

# Save a diff
git diff | $GIST create "WIP diff" "changes.patch"
```

### Handling large content

The API accepts up to **1 MB per file** in the content field. For larger content:
- The file will be stored but the API response will set `truncated: true`.
- Use `$GIST read` which auto-fetches the full content via `raw_url`.
- For files >10 MB, gists must be cloned via git — this is a GitHub limitation.

## Error Handling

The script exits non-zero on HTTP 4xx/5xx and prints the GitHub error message
to stderr. Common issues:

| HTTP code | Cause | Fix |
|-----------|-------|-----|
| 401 | Bad or expired token | Re-generate GITHUB_TOKEN |
| 403 | Token lacks `gist` scope | Add `gist` scope to the PAT |
| 404 | Gist doesn't exist or isn't yours | Check the gist ID |
| 422 | Malformed payload (empty content, bad JSON) | Validate input |

## Security Notes

- **Never hardcode `GITHUB_TOKEN` in scripts or gists.** Always use env vars.
- Secret gists are **not encrypted** — they're unlisted but accessible to anyone
  with the URL. Don't store real secrets (passwords, API keys) in gists.
- The script sends the token only to `api.github.com` via HTTPS.
- Consider using a fine-grained PAT scoped to gists only (no repo access).
