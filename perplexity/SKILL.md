---
name: perplexity
description: >
  Query Perplexity AI (perplexity.ai) without an API key or token. Use this
  skill only when the user explicitly mentions "perplexity" — e.g. to run a
  web search via perplexity, ask perplexity a question, get a synthesized
  answer from perplexity, or fetch links via perplexity search. Do not use
  for generic web searches where "perplexity" is not named.
allowed-tools:
  - Bash(node:*)
---

# Perplexity Skill (tokenless)

Query Perplexity AI from the command line without an API key. Reimplements the
no-auth path of the Rust MCP server
[mishamyrt/perplexity-web-api-mcp](https://github.com/mishamyrt/perplexity-web-api-mcp)
in a single Node.js script.

> **Reference**: if the Perplexity web API changes, the upstream Rust crate
> (`crates/perplexity-web-api/src/{client,config,types,parse}.rs`) is the
> source of truth to consult first.

## Prerequisites

- `node` ≥ 14.17 on PATH. No npm dependencies — only built-in `https` and `crypto`.
- No credentials, no `.env` file. The script does an anonymous warm-up of
  `https://www.perplexity.ai/api/auth/session` to obtain Cloudflare cookies,
  then issues a single `POST /rest/sse/perplexity_ask` with the free `turbo`
  model.

## Helper Script

The script lives at `scripts/perplexity.js`. Make sure it is executable:

```bash
chmod +x /path/to/this/skill/scripts/perplexity.js
```

Alias for convenience in the examples below:

```bash
PPLX="node /path/to/this/skill/scripts/perplexity.js"
```

Replace `/path/to/this/skill/` with the directory where this `SKILL.md` lives.

## Operations Reference

### `ask` — synthesized answer + sources

```bash
$PPLX ask "<question>"
```

Output (JSON):

```json
{
  "answer": "Perplexity's synthesized answer (may contain citation markers like [1], [10])",
  "web_results": [ { "name": "...", "url": "...", "snippet": "..." }, ... ]
}
```

### `search` — web results only

```bash
$PPLX search "<query>"
```

Output (JSON):

```json
{
  "web_results": [ { "name": "...", "url": "...", "snippet": "..." }, ... ]
}
```

## Patterns & Best Practices

**Strip citation markers from the answer:**

```bash
$PPLX ask "question" | jq -r '.answer' | sed -E 's/\[[0-9]+\]//g'
```

**Get only the first URL of a search:**

```bash
$PPLX search "query" | jq -r '.web_results[0].url'
```

**Validated example** (the canonical test case for this skill):

```bash
$PPLX ask "quel est le dernier épisode de For All Mankind qui a été diffusé. Réponds avec le format SXXEXX"
# → "answer": "S05E08[10]"
```

The `[10]` marker corresponds to `web_results[9]` in the response.

## Error Handling

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Session warm-up failed: HTTP 403` | Cloudflare blocked the request (TLS fingerprint mismatch) | Update the `CHROME_HEADERS` in the script to a newer Chrome version, or switch to `curl-impersonate`. The upstream Rust client uses `rquest` with `Emulation::Chrome136`. |
| `Search request failed: HTTP 429` | Rate limited | Wait and retry. Anonymous quota is per-IP. |
| `"answer": null, "web_results": []` | Perplexity changed its SSE event schema | Inspect a raw SSE response and update `extractFromEvent()` in the script. Cross-check against `crates/perplexity-web-api/src/parse.rs` upstream. |
| Hang / timeout | Network egress to `www.perplexity.ai` blocked | Verify connectivity. The script has no built-in timeout — kill and retry. |

## Limits

- Only the `turbo` model (the sole model accessible without auth cookies).
- No file attachments, no Pro/Research/Reason modes, no follow-up context.
  Those features require `PERPLEXITY_SESSION_TOKEN` + `PERPLEXITY_CSRF_TOKEN`
  in the upstream Rust MCP — intentionally not ported here.
- Output may include citation markers `[N]` in the `answer` field; strip them
  with `sed` if you need plain text (see *Patterns* above).

## Security Notes

- The script makes anonymous requests; no credentials are sent and none are
  stored locally.
- The query string is sent verbatim to Perplexity over HTTPS. Treat queries
  the same way you'd treat any third-party AI prompt: don't include secrets
  or personally identifying information you wouldn't paste into perplexity.ai.
