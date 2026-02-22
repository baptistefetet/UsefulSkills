#!/usr/bin/env bash
# confluence.sh — Lightweight Confluence Cloud CRUD via REST API (curl + jq)
# Requires: CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN
# Usage: confluence.sh <command> [args...]
#
# Commands:
#   list-spaces [--limit N]                         List spaces
#   list-pages  <space_id> [--limit N]              List pages in a space
#   get         <page_id>                           Get page metadata + body (JSON)
#   read        <page_id>                           Print page body as storage HTML
#   create      <space_id> <title> [--parent ID]    Create page (reads body from stdin)
#   update      <page_id> <title>                   Update page (reads body from stdin)
#   delete      <page_id>                           Delete (trash) a page
#   search      <cql_query> [--limit N]             Search content via CQL
#   children    <page_id> [--limit N]               List child pages

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

# ---------- configuration ----------

# Source .env from skill root if variables are not already set
if [[ -z "${CONFLUENCE_URL:-}" || -z "${CONFLUENCE_EMAIL:-}" || -z "${CONFLUENCE_API_TOKEN:-}" ]]; then
  SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$SKILL_DIR/.env" ]]; then
    export $(grep -v '^#' "$SKILL_DIR/.env" | xargs)
  fi
fi

[[ -z "${CONFLUENCE_URL:-}" ]]       && die "CONFLUENCE_URL not set. Export it or add it to .env."
[[ -z "${CONFLUENCE_EMAIL:-}" ]]     && die "CONFLUENCE_EMAIL not set. Export it or add it to .env."
[[ -z "${CONFLUENCE_API_TOKEN:-}" ]] && die "CONFLUENCE_API_TOKEN not set. Export it or add it to .env."

# Strip trailing slash from URL
CONFLUENCE_URL="${CONFLUENCE_URL%/}"

# Basic auth: base64(email:token)
AUTH_HEADER="Authorization: Basic $(printf '%s:%s' "$CONFLUENCE_EMAIL" "$CONFLUENCE_API_TOKEN" | base64)"

# ---------- HTTP helper ----------

confluence_api() {
  local method="$1" endpoint="$2"
  shift 2
  local url="${CONFLUENCE_URL}${endpoint}"
  local response http_code body

  response=$(curl -s -w "\n%{http_code}" -X "$method" \
    -H "$AUTH_HEADER" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$@" "$url")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "HTTP ${http_code} — ${method} ${endpoint}" >&2
    echo "$body" | jq -r '.message // .errors[0].message // .errorMessage // "Unknown error"' 2>/dev/null >&2 || echo "$body" >&2
    exit 1
  fi
  echo "$body"
}

# ---------- commands ----------

cmd_list_spaces() {
  local limit=25
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) die "list-spaces: unknown flag $1" ;;
    esac
  done
  confluence_api GET "/wiki/api/v2/spaces?limit=${limit}" \
    | jq -r '.results[] | "\(.id)  \(.key)  \(.name)  \(.status)"'
}

cmd_list_pages() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh list-pages <space_id> [--limit N]"
  local space_id="$1"; shift
  local limit=25
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) die "list-pages: unknown flag $1" ;;
    esac
  done
  confluence_api GET "/wiki/api/v2/spaces/${space_id}/pages?limit=${limit}" \
    | jq -r '.results[] | "\(.id)  \(.status)  \(.title)"'
}

cmd_get() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh get <page_id>"
  confluence_api GET "/wiki/api/v2/pages/$1?body-format=storage" | jq '.'
}

cmd_read() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh read <page_id>"
  confluence_api GET "/wiki/api/v2/pages/$1?body-format=storage" \
    | jq -r '.body.storage.value // "(empty page)"'
}

cmd_create() {
  [[ $# -lt 2 ]] && die "usage: echo '<p>content</p>' | confluence.sh create <space_id> <title> [--parent ID]"
  local space_id="$1" title="$2"
  shift 2
  local parent_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent) parent_id="$2"; shift 2 ;;
      *) die "create: unknown flag $1" ;;
    esac
  done

  local content
  content=$(cat)
  [[ -z "$content" ]] && die "No content on stdin. Pipe HTML storage format into the command."

  local payload
  if [[ -n "$parent_id" ]]; then
    payload=$(jq -n \
      --arg sid "$space_id" \
      --arg t "$title" \
      --arg c "$content" \
      --arg pid "$parent_id" \
      '{spaceId: $sid, status: "current", title: $t, parentId: $pid, body: {representation: "storage", value: $c}}')
  else
    payload=$(jq -n \
      --arg sid "$space_id" \
      --arg t "$title" \
      --arg c "$content" \
      '{spaceId: $sid, status: "current", title: $t, body: {representation: "storage", value: $c}}')
  fi

  local result
  result=$(confluence_api POST "/wiki/api/v2/pages" -d "$payload")
  local page_id page_url
  page_id=$(echo "$result" | jq -r '.id')
  page_url=$(echo "$result" | jq -r '._links.base + ._links.webui')
  echo "Created: ${page_id}"
  echo "URL:     ${page_url}"
}

cmd_update() {
  [[ $# -lt 2 ]] && die "usage: echo '<p>new content</p>' | confluence.sh update <page_id> <title>"
  local page_id="$1" title="$2"

  local content
  content=$(cat)
  [[ -z "$content" ]] && die "No content on stdin. Pipe HTML storage format into the command."

  # Fetch current page to get version number and spaceId
  local current
  current=$(confluence_api GET "/wiki/api/v2/pages/${page_id}?body-format=storage")
  local current_version space_id
  current_version=$(echo "$current" | jq -r '.version.number')
  space_id=$(echo "$current" | jq -r '.spaceId')

  local new_version=$((current_version + 1))

  local payload
  payload=$(jq -n \
    --arg pid "$page_id" \
    --arg sid "$space_id" \
    --arg t "$title" \
    --arg c "$content" \
    --argjson v "$new_version" \
    '{id: $pid, status: "current", title: $t, spaceId: $sid, body: {representation: "storage", value: $c}, version: {number: $v}}')

  local result
  result=$(confluence_api PUT "/wiki/api/v2/pages/${page_id}" -d "$payload")
  local page_url
  page_url=$(echo "$result" | jq -r '._links.base + ._links.webui')
  echo "Updated: ${page_id} (v${new_version})"
  echo "URL:     ${page_url}"
}

cmd_delete() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh delete <page_id>"
  confluence_api DELETE "/wiki/api/v2/pages/$1" > /dev/null 2>&1
  echo "Deleted (trashed): $1"
}

cmd_search() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh search <cql_query> [--limit N]"
  local cql="$1"; shift
  local limit=25
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) die "search: unknown flag $1" ;;
    esac
  done

  local encoded_cql
  encoded_cql=$(printf '%s' "$cql" | jq -sRr @uri)

  confluence_api GET "/wiki/rest/api/search?cql=${encoded_cql}&limit=${limit}" \
    | jq -r '.results[] | "\(.content.id // .id)  \(.content.type // .type)  \(.content.title // .title)  [\(.content.space.key // "")]"'
}

cmd_children() {
  [[ $# -lt 1 ]] && die "usage: confluence.sh children <page_id> [--limit N]"
  local page_id="$1"; shift
  local limit=25
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) die "children: unknown flag $1" ;;
    esac
  done
  confluence_api GET "/wiki/api/v2/pages/${page_id}/children?limit=${limit}" \
    | jq -r '.results[] | "\(.id)  \(.status)  \(.title)"'
}

# ---------- dispatch ----------
cmd="${1:-help}"
shift || true

case "$cmd" in
  list-spaces) cmd_list_spaces "$@" ;;
  list-pages)  cmd_list_pages "$@" ;;
  get)         cmd_get "$@" ;;
  read)        cmd_read "$@" ;;
  create)      cmd_create "$@" ;;
  update)      cmd_update "$@" ;;
  delete)      cmd_delete "$@" ;;
  search)      cmd_search "$@" ;;
  children)    cmd_children "$@" ;;
  help|--help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    ;;
  *) die "Unknown command: $cmd. Run '$0 help' for usage." ;;
esac
