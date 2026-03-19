#!/bin/bash
set -euo pipefail

# Scripts to post release notes to Confluence via API
# Usage: ./post-to-confluence.sh <SPACE_KEY> <YEAR> <MONTH> <PAGE_TITLE> <HTML_FILE> <REPO_ID>

SPACE_KEY="$1"
YEAR="$2"
MONTH="$3"
# Convert MONTH to first 3 letters (e.g., January -> Jan)
MONTH=$(echo "$MONTH" | cut -c 1-3)
PAGE_TITLE="$4"
HTML_FILE="$5"
REPO_ID="$6" # Root folder ID for this repo

# Ensure required environments are set
: "${CONFLUENCE_BASE_URL:?Missing CONFLUENCE_BASE_URL}"
: "${CONFLUENCE_USERNAME:?Missing CONFLUENCE_USERNAME}"
: "${CONFLUENCE_TOKEN:?Missing CONFLUENCE_TOKEN}"

HTML_CONTENT=$(cat "$HTML_FILE")

# Helper to log API calls for debugging
log_api_call() {
  local method="$1"
  local url="$2"
  local status="$3"
  local body="$4"
  echo "--- Confluence API Call ---"
  echo "Method: $method"
  echo "URL: $url"
  echo "Status: $status"
  echo "Response: $body"
  echo "--------------------------"
}

# Helper to look up page ID by title and parent ID
get_page_id() {
  local title="$1"
  local parent_id="$2"
  local query="space=${SPACE_KEY} AND type=page AND title=\"${title}\" AND ancestor=${parent_id}"
  local encoded_query=$(printf '%s' "$query" | jq -sRr @uri)
  local url="${CONFLUENCE_BASE_URL}/rest/api/content/search?cql=${encoded_query}"

  local response_file=$(mktemp)
  local http_status
  http_status=$(curl -s -u "${CONFLUENCE_USERNAME}:${CONFLUENCE_TOKEN}" \
    -w "%{http_code}" -o "$response_file" \
    "$url" -H "Content-Type: application/json")
  local response
  response=$(cat "$response_file")

  log_api_call "GET (Search)" "$url" "$http_status" "$response"

  if [[ "$http_status" -ne 200 ]]; then
    echo "❌ Search for page '$title' failed with status $http_status"
    exit 1
  fi

  echo "$response" | jq -r '.results[0].id // empty'
}

# Helper to create a new page
create_page() {
  local title="$1"
  local parent_id="$2"
  local body_content="${3:-}"
  local url="${CONFLUENCE_BASE_URL}/rest/api/content"

  echo "📄 Creating new page: $title"
  local response_file=$(mktemp)
  local http_status
  http_status=$(curl -s -X POST -u "${CONFLUENCE_USERNAME}:${CONFLUENCE_TOKEN}" \
    -w "%{http_code}" -o "$response_file" \
    "$url" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$title" --arg space "$SPACE_KEY" --arg parent "$parent_id" --arg html "$body_content" \
      '{type: "page", title: $title, space: {key: $space}, ancestors: [{id: $parent}], body: {storage: {value: $html, representation: "storage"}}}')")
  local response
  response=$(cat "$response_file")

  log_api_call "POST (Create)" "$url" "$http_status" "$response"

  local new_id
  new_id=$(echo "$response" | jq -r '.id // empty')
  if [[ "$http_status" -lt 200 || "$http_status" -gt 299 ]] || [[ -z "$new_id" ]] || [[ "$new_id" == "null" ]]; then
    echo "❌ Failed to create page '$title'. Status: $http_status"
    exit 1
  fi
  echo "$new_id"
}

# 1. Ensure Year folder exists
echo "🔍 Checking Year folder: $YEAR"
YEAR_ID=$(get_page_id "$YEAR" "$REPO_ID")
if [[ -z "$YEAR_ID" ]]; then
  YEAR_ID=$(create_page "$YEAR" "$REPO_ID")
fi

# 2. Ensure Month folder exists
echo "🔍 Checking Month folder: $MONTH"
MONTH_ID=$(get_page_id "$MONTH" "$YEAR_ID")
if [[ -z "$MONTH_ID" ]]; then
  MONTH_ID=$(create_page "$MONTH" "$YEAR_ID")
fi

# 3. Create or Update Release Page
echo "🔍 Checking Release page: $PAGE_TITLE"
PAGE_ID=$(get_page_id "$PAGE_TITLE" "$MONTH_ID")

if [[ -z "$PAGE_ID" ]]; then
  echo "📝 No existing page found. Creating new release page..."
  create_page "$PAGE_TITLE" "$MONTH_ID" "$HTML_CONTENT" > /dev/null
else
  echo "📝 Updating existing release page ID: ${PAGE_ID}"

  # Fetch current version and old content
  url="${CONFLUENCE_BASE_URL}/rest/api/content/${PAGE_ID}?expand=version,body.storage"
  response_file=$(mktemp)
  http_status=$(curl -s -u "${CONFLUENCE_USERNAME}:${CONFLUENCE_TOKEN}" \
    -w "%{http_code}" -o "$response_file" -X GET "$url")
  get_response=$(cat "$response_file")
  log_api_call "GET (Version Fetch)" "$url" "$http_status" "$get_response"

  if [[ "$http_status" -ne 200 ]]; then
    echo "❌ Failed to fetch current page version. Status: $http_status"
    exit 1
  fi

  CUR_VER=$(echo "$get_response" | jq -r '.version.number')
  PREV_CONTENT=$(echo "$get_response" | jq -r '.body.storage.value')
  NEXT_VER=$((CUR_VER + 1))
  UPDATED_CONTENT="$HTML_CONTENT<hr/><br/>$PREV_CONTENT"

  url="${CONFLUENCE_BASE_URL}/rest/api/content/${PAGE_ID}"
  response_file=$(mktemp)
  http_status=$(curl -s -u "${CONFLUENCE_USERNAME}:${CONFLUENCE_TOKEN}" \
    -w "%{http_code}" -o "$response_file" -X PUT "$url" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$PAGE_TITLE" --arg html "$UPDATED_CONTENT" --argjson ver "$NEXT_VER" \
      '{type: "page", title: $title, version: {number: $ver}, body: {storage: {value: $html, representation: "storage"}}}')")
  put_response=$(cat "$response_file")
  log_api_call "PUT (Update Page)" "$url" "$http_status" "$put_response"

  if [[ "$http_status" -lt 200 || "$http_status" -gt 299 ]]; then
    echo "❌ Failed to update release page. Status: $http_status"
    exit 1
  fi
fi

echo "✅ Release notes successfully pushed to Confluence!"

