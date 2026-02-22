#!/usr/bin/env bash
# gist.sh — Lightweight GitHub Gist CRUD via REST API (curl only)
# Requires: GITHUB_TOKEN environment variable with 'gist' scope
# Usage: gist.sh <command> [args...]
#
# Commands:
#   list   [--per-page N] [--page N]          List authenticated user's gists
#   get    <gist_id>                           Get a single gist (files + metadata)
#   read   <gist_id> [filename]               Print raw content of a file in a gist
#   create <description> <filename> [--public] Create gist (reads content from stdin)
#   update <gist_id> <filename>               Update a file in a gist (reads from stdin)
#   rename <gist_id> <old_name> <new_name>    Rename a file in a gist
#   delete <gist_id>                           Delete a gist (irreversible)
#   add    <gist_id> <filename>               Add a file to an existing gist (stdin)
#   rm     <gist_id> <filename>               Remove a single file from a gist
#   desc   <gist_id> <new_description>        Update gist description
#   search <pattern>                           Search gists by description (local grep)

set -euo pipefail

API="https://api.github.com"
API_VERSION="2022-11-28"

die() { echo "error: $*" >&2; exit 1; }

# If GITHUB_TOKEN is not set, try to source .env from the skill root directory
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$SKILL_DIR/.env" ]]; then
    export $(grep -v '^#' "$SKILL_DIR/.env" | xargs)
  fi
fi

[[ -z "${GITHUB_TOKEN:-}" ]] && die "GITHUB_TOKEN not set. Export a token with 'gist' scope or add it to .env."

auth_headers=(
  -H "Authorization: Bearer ${GITHUB_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: ${API_VERSION}"
)

gh_api() {
  local method="$1" endpoint="$2"
  shift 2
  local url="${API}${endpoint}"
  local response http_code body

  response=$(curl -s -w "\n%{http_code}" -X "$method" "${auth_headers[@]}" "$@" "$url")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "HTTP ${http_code} — ${endpoint}" >&2
    echo "$body" | jq -r '.message // .errors[0].message // "Unknown error"' 2>/dev/null >&2 || echo "$body" >&2
    exit 1
  fi
  echo "$body"
}

cmd_list() {
  local per_page=30 page=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --per-page) per_page="$2"; shift 2 ;;
      --page)     page="$2"; shift 2 ;;
      *) die "list: unknown flag $1" ;;
    esac
  done
  gh_api GET "/gists?per_page=${per_page}&page=${page}" \
    | jq -r '.[] | "\(.id)  \(.public | if . then "public " else "secret" end)  \(.updated_at | split("T")[0])  \(.description // "(no description)")  [\(.files | keys | join(", "))]"'
}

cmd_get() {
  [[ $# -lt 1 ]] && die "usage: gist.sh get <gist_id>"
  gh_api GET "/gists/$1" | jq '.'
}

cmd_read() {
  [[ $# -lt 1 ]] && die "usage: gist.sh read <gist_id> [filename]"
  local gist_id="$1"
  local filename="${2:-}"
  local data
  data=$(gh_api GET "/gists/${gist_id}")

  if [[ -z "$filename" ]]; then
    # If no filename, pick the first (or only) file
    filename=$(echo "$data" | jq -r '.files | keys[0]')
  fi

  local content truncated raw_url
  content=$(echo "$data" | jq -r ".files[\"${filename}\"].content // empty")
  truncated=$(echo "$data" | jq -r ".files[\"${filename}\"].truncated // false")

  if [[ "$truncated" == "true" ]]; then
    # File >1MB: fetch via raw_url
    raw_url=$(echo "$data" | jq -r ".files[\"${filename}\"].raw_url")
    curl -sL "${auth_headers[@]}" "$raw_url"
  elif [[ -n "$content" ]]; then
    echo "$content"
  else
    die "File '${filename}' not found in gist ${gist_id}. Available: $(echo "$data" | jq -r '.files | keys | join(", ")')"
  fi
}

cmd_create() {
  [[ $# -lt 2 ]] && die "usage: echo 'content' | gist.sh create <description> <filename> [--public]"
  local description="$1" filename="$2" public="false"
  shift 2
  [[ "${1:-}" == "--public" ]] && public="true"

  local content
  content=$(cat)
  [[ -z "$content" ]] && die "No content on stdin."

  local payload
  payload=$(jq -n \
    --arg desc "$description" \
    --arg fname "$filename" \
    --arg cont "$content" \
    --argjson pub "$public" \
    '{description: $desc, public: $pub, files: {($fname): {content: $cont}}}')

  local result
  result=$(gh_api POST "/gists" -d "$payload")
  local gist_id html_url
  gist_id=$(echo "$result" | jq -r '.id')
  html_url=$(echo "$result" | jq -r '.html_url')
  echo "Created: ${gist_id}"
  echo "URL:     ${html_url}"
}

cmd_update() {
  [[ $# -lt 2 ]] && die "usage: echo 'new content' | gist.sh update <gist_id> <filename>"
  local gist_id="$1" filename="$2"
  local content
  content=$(cat)
  [[ -z "$content" ]] && die "No content on stdin."

  local payload
  payload=$(jq -n \
    --arg fname "$filename" \
    --arg cont "$content" \
    '{files: {($fname): {content: $cont}}}')

  gh_api PATCH "/gists/${gist_id}" -d "$payload" | jq -r '"Updated: \(.id)\nURL:     \(.html_url)"'
}

cmd_rename() {
  [[ $# -lt 3 ]] && die "usage: gist.sh rename <gist_id> <old_name> <new_name>"
  local gist_id="$1" old_name="$2" new_name="$3"

  local payload
  payload=$(jq -n \
    --arg old "$old_name" \
    --arg new "$new_name" \
    '{files: {($old): {filename: $new}}}')

  gh_api PATCH "/gists/${gist_id}" -d "$payload" | jq -r '"Renamed: \(.id)\nURL:     \(.html_url)"'
}

cmd_delete() {
  [[ $# -lt 1 ]] && die "usage: gist.sh delete <gist_id>"
  gh_api DELETE "/gists/$1" > /dev/null 2>&1
  echo "Deleted: $1"
}

cmd_add() {
  [[ $# -lt 2 ]] && die "usage: echo 'content' | gist.sh add <gist_id> <filename>"
  cmd_update "$@"  # Same PATCH endpoint, adding a new key creates the file
}

cmd_rm() {
  [[ $# -lt 2 ]] && die "usage: gist.sh rm <gist_id> <filename>"
  local gist_id="$1" filename="$2"

  local payload
  payload=$(jq -n --arg fname "$filename" '{files: {($fname): null}}')
  gh_api PATCH "/gists/${gist_id}" -d "$payload" | jq -r '"Removed \"'"$filename"'\" from \(.id)"'
}

cmd_desc() {
  [[ $# -lt 2 ]] && die "usage: gist.sh desc <gist_id> <new_description>"
  local gist_id="$1" description="$2"
  local payload
  payload=$(jq -n --arg d "$description" '{description: $d}')
  gh_api PATCH "/gists/${gist_id}" -d "$payload" | jq -r '"Description updated: \(.id)"'
}

cmd_search() {
  [[ $# -lt 1 ]] && die "usage: gist.sh search <pattern>"
  local pattern="$1"
  # Fetch up to 100 gists and grep descriptions + filenames
  gh_api GET "/gists?per_page=100" \
    | jq -r '.[] | "\(.id)  \(.description // "")  [\(.files | keys | join(", "))]"' \
    | grep -i "$pattern" || echo "No matches for '${pattern}'"
}

# --- dispatch ---
cmd="${1:-help}"
shift || true

case "$cmd" in
  list)   cmd_list "$@" ;;
  get)    cmd_get "$@" ;;
  read)   cmd_read "$@" ;;
  create) cmd_create "$@" ;;
  update) cmd_update "$@" ;;
  rename) cmd_rename "$@" ;;
  delete) cmd_delete "$@" ;;
  add)    cmd_add "$@" ;;
  rm)     cmd_rm "$@" ;;
  desc)   cmd_desc "$@" ;;
  search) cmd_search "$@" ;;
  help|--help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    ;;
  *) die "Unknown command: $cmd. Run '$0 help' for usage." ;;
esac
