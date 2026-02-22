---
name: atlassian-confluence
description: >
  CRUD operations on Confluence Cloud pages via the REST API — create, read,
  update, delete, list, and search pages and spaces. Use this skill whenever the
  user mentions Confluence, wiki pages, knowledge base, documentation spaces,
  wants to publish or update a wiki page, search Confluence content, list spaces
  or pages, read a Confluence page, create documentation, or manage wiki content.
  Also trigger when the user says "post this to Confluence", "update the wiki",
  "search Confluence", "create a page", "list spaces", or references a Confluence
  page ID/URL. Works with any HTML/storage-format content: documentation,
  runbooks, meeting notes, technical specs, decision records.
---

# Atlassian Confluence Skill

Create, read, update, delete, list, and search Confluence Cloud pages and spaces.
Zero dependencies beyond `curl` and `jq`.

## Prerequisites

The user must have three variables available. They can be provided in two ways:

1. **Environment variables** (preferred): `CONFLUENCE_URL`, `CONFLUENCE_EMAIL`,
   and `CONFLUENCE_API_TOKEN` set in the shell environment.
2. **Local `.env` file** (fallback): A `.env` file located next to this `SKILL.md`
   (i.e., in the skill's root directory) containing the three variables.

```bash
# If variables are not set in the environment, source the .env file as fallback
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
if [ -z "${CONFLUENCE_URL:-}" ] || [ -z "${CONFLUENCE_EMAIL:-}" ] || [ -z "${CONFLUENCE_API_TOKEN:-}" ]; then
  if [ -f "$SKILL_DIR/.env" ]; then
    export $(grep -v '^#' "$SKILL_DIR/.env" | xargs)
  fi
fi
```

If no source provides the variables, instruct the user to:
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Create an API token
3. Either export the variables or add them to the `.env` file in the skill directory:
   - `CONFLUENCE_URL` — the Atlassian site URL (e.g., `https://mycompany.atlassian.net`)
   - `CONFLUENCE_EMAIL` — the email associated with the Atlassian account
   - `CONFLUENCE_API_TOKEN` — the API token generated above

## Helper Script

All operations go through `scripts/confluence.sh` bundled with this skill.
Make it executable before first use:

```bash
chmod +x /path/to/this/skill/scripts/confluence.sh
```

Alias for convenience in the examples below:

```bash
CONFL="bash /path/to/this/skill/scripts/confluence.sh"
```

> **Important:** Replace `/path/to/this/skill/` with the actual path where this
> skill is installed (e.g., `~/.claude/skills/atlassian-confluence/`).

## Operations Reference

### List spaces

```bash
$CONFL list-spaces                 # default: 25 spaces
$CONFL list-spaces --limit 50
```

Output: one line per space — `id  key  name  status`

### List pages in a space

```bash
$CONFL list-pages <space_id>
$CONFL list-pages <space_id> --limit 50
```

Output: one line per page — `id  status  title`

> **Note:** `space_id` is the numeric space ID, not the space key.
> Use `list-spaces` to find the ID.

### Read a page

```bash
$CONFL get  <page_id>     # Full JSON (metadata + body in storage format)
$CONFL read <page_id>     # Print only the body HTML (storage format)
```

- `get` returns the complete JSON response including version, space, links, etc.
- `read` returns just the body content in Confluence storage format (XHTML).

### Create a page

```bash
echo '<p>Hello world</p>'   | $CONFL create <space_id> "My Page Title"
echo '<h1>Runbook</h1>...'  | $CONFL create <space_id> "Ops Runbook" --parent <parent_page_id>
cat document.html           | $CONFL create <space_id> "Imported Doc"
```

- Reads content from **stdin** in Confluence storage format (XHTML).
- Use `--parent <page_id>` to create a child page under an existing page.
- Returns the page ID and the web URL.

### Update a page

```bash
echo '<p>Updated content</p>' | $CONFL update <page_id> "New Title"
cat updated.html              | $CONFL update <page_id> "Same Title"
```

- Reads content from **stdin** in Confluence storage format.
- Automatically fetches the current version number and increments it.
- The title argument is required (can be the same as current title).

### Delete a page

```bash
$CONFL delete <page_id>
```

Moves the page to the trash. **Confirm with the user before executing.**

### Search content (CQL)

```bash
$CONFL search 'type=page AND space=DEV AND title~"runbook"'
$CONFL search 'text~"deployment process"' --limit 10
$CONFL search 'label=important AND type=page'
```

Uses [Confluence Query Language (CQL)](https://developer.atlassian.com/cloud/confluence/advanced-searching-using-cql/).
Output: one line per result — `id  type  title  [space_key]`

Common CQL fields:
- `type` — `page`, `blogpost`, `comment`, `attachment`
- `space` — space key (e.g., `DEV`, `OPS`)
- `title` — page title (use `~` for contains, `=` for exact)
- `text` — full-text search across page content
- `label` — page labels
- `creator` — account ID of the author
- `lastmodified` — date comparison (`>`, `<`, `>=`)

### List child pages

```bash
$CONFL children <page_id>
$CONFL children <page_id> --limit 50
```

Output: one line per child — `id  status  title`

## Patterns & Best Practices

### Publishing documentation from code

```bash
# Generate and push a markdown-to-HTML doc
pandoc README.md -t html | $CONFL create <space_id> "Project README"

# Update an existing page from a template
cat docs/runbook.html | $CONFL update <page_id> "Production Runbook"
```

### Building a page tree

```bash
# Create a parent page
echo '<p>Project docs root</p>' | $CONFL create <space_id> "My Project"
# → page_id = 12345

# Create child pages under it
echo '<p>API reference</p>'  | $CONFL create <space_id> "API Reference" --parent 12345
echo '<p>Architecture</p>'   | $CONFL create <space_id> "Architecture" --parent 12345
```

### Searching and reading

```bash
# Find all pages in the DEV space mentioning "migration"
$CONFL search 'type=page AND space=DEV AND text~"migration"'

# Read the content of a found page
$CONFL read <page_id>
```

### Piping command output

```bash
# Save current env as a Confluence page
env | sed 's/^/<p>/;s/$/<\/p>/' | $CONFL create <space_id> "Env Snapshot $(date +%F)"
```

## Confluence Storage Format

Confluence uses an XHTML-based storage format. Common elements:

```html
<p>Paragraph text</p>
<h1>Heading 1</h1>
<h2>Heading 2</h2>
<ul><li>List item</li></ul>
<ol><li>Numbered item</li></ol>
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">python</ac:parameter>
  <ac:plain-text-body><![CDATA[print("hello")]]></ac:plain-text-body>
</ac:structured-macro>
<a href="https://example.com">Link</a>
<strong>Bold</strong> and <em>Italic</em>
```

For simple text, plain `<p>...</p>` tags work fine. For rich content,
refer to the [storage format docs](https://developer.atlassian.com/cloud/confluence/confluence-storage-format/).

## Error Handling

The script exits non-zero on HTTP 4xx/5xx and prints the Confluence error
message to stderr. Common issues:

| HTTP code | Cause | Fix |
|-----------|-------|-----|
| 401 | Bad credentials | Check CONFLUENCE_EMAIL and CONFLUENCE_API_TOKEN |
| 403 | Insufficient permissions | Ensure the user has access to the space/page |
| 404 | Page or space not found | Check the ID |
| 409 | Version conflict | Re-fetch the page and retry (update auto-handles this) |
| 422 | Malformed payload | Validate input content |

## Security Notes

- **Never hardcode credentials in scripts or pages.** Always use env vars or `.env`.
- The API token grants the same permissions as the user account — use a
  service account with minimal permissions when possible.
- The script sends credentials only to your Confluence instance via HTTPS.
- Consider rotating API tokens regularly.
- The `.env` file is git-ignored by default — never commit it.
