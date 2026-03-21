#!/bin/bash
set -euo pipefail

# This script posts the generated release HTML to Confluence.
# Renamed CONFLUENCE_TOKEN to ATLASSIAN_API_TOKEN as per guidelines.

CONFLUENCE_BASE_URL="https://anywhereworks.atlassian.net/wiki"
: "${ATLASSIAN_USERNAME:?Missing ATLASSIAN_USERNAME}"
: "${ATLASSIAN_API_TOKEN:?Missing ATLASSIAN_API_TOKEN}"
: "${YEAR:?Missing YEAR}"
: "${MONTH:?Missing MONTH}"
: "${PAGE_TITLE:?Missing PAGE_TITLE}"
: "${REPO_ID:?Missing REPO_ID}"

CONFLUENCE_SPACE_KEY="Payments"

if [ ! -f confluence_body.html ]; then
  echo "❌ Error: confluence_body.html not found."
  exit 1
fi

HTML_CONTENT=$(cat confluence_body.html)

# get_page_id(title, parent_id, type)
get_page_id() {
  local title="$1"
  local parent_id="$2"
  local type="${3:-page}" # Default to page if not provided

  local query="space=${CONFLUENCE_SPACE_KEY} AND type=${type} AND title=\"${title}\" AND parent=${parent_id}"
  local encoded_query=$(printf '%s' "$query" | jq -sRr @uri)

  local search_response
  search_response=$(curl -sSf -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "${CONFLUENCE_BASE_URL}/rest/api/content/search?cql=${encoded_query}" \
    -H "Content-Type: application/json")

  local count
  count=$(echo "$search_response" | jq '.results | length')

  if [[ "$count" -eq 0 ]]; then
    return
  elif [[ "$count" -gt 1 ]]; then
    echo "❌ Error: Found more than one page with title \"$title\" and type \"$type\" under parent $parent_id. Count: $count"
    exit 1
  fi

  echo "$search_response" | jq -r '.results[0].id // empty'
}

create_page() {
  local title="$1"
  local parent_id="$2"
  local type="${3:-page}"

  local response
  response=$(curl -s -X POST -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "${CONFLUENCE_BASE_URL}/rest/api/content" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$title" --arg space "$CONFLUENCE_SPACE_KEY" --arg parent "$parent_id" --arg type "$type" \
      '{type: $type, title: $title, space: {key: $space}, ancestors: [{id: $parent}], body: {storage: {value: "", representation: "storage"}}}')")

  local new_id
  new_id=$(echo "$response" | jq -r '.id // empty')

  if [ -z "$new_id" ] || [ "$new_id" == "null" ]; then
    echo "❌ Failed to create $type: \"$title\" under parent $parent_id"
    echo "Response: $response"
    exit 1
  fi
  echo "$new_id"
}

# 1. Ensure Year folder exists under "fullpayments"
YEAR_ID=$(get_page_id "$YEAR" "$REPO_ID" "page")
if [ -z "$YEAR_ID" ]; then
  echo "📁 Creating year folder: $YEAR"
  YEAR_ID=$(create_page "$YEAR" "$REPO_ID" "page")
fi

# 2. Ensure Month folder exists under Year folder
MONTH_ID=$(get_page_id "$MONTH" "$YEAR_ID" "page")
if [ -z "$MONTH_ID" ]; then
  echo "📁 Creating month folder: $MONTH"
  MONTH_ID=$(create_page "$MONTH" "$YEAR_ID" "page")
fi

# 3. Create or Update Release Page under Month folder
FINAL_PARENT_ID="$MONTH_ID"
PAGE_ID=$(get_page_id "$PAGE_TITLE" "$FINAL_PARENT_ID" "page")

if [ -z "$PAGE_ID" ]; then
  echo "📄 Creating new release page: ${PAGE_TITLE}"
  curl -s -f -X POST -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "${CONFLUENCE_BASE_URL}/rest/api/content" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$PAGE_TITLE" --arg space "$CONFLUENCE_SPACE_KEY" --arg parent "$FINAL_PARENT_ID" --arg html "$HTML_CONTENT" \
      '{type: "page", title: $title, space: {key: $space}, ancestors: [{id: $parent}], body: {storage: {value: $html, representation: "storage"}}}')"
else
  echo "📝 Updating existing release page ID: ${PAGE_ID} (Smart Appending)"
  GET_RESPONSE=$(curl -s -f -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "${CONFLUENCE_BASE_URL}/rest/api/content/${PAGE_ID}?expand=version,body.storage")

  CUR_VER=$(echo "$GET_RESPONSE" | jq -r '.version.number')
  PREV_CONTENT=$(echo "$GET_RESPONSE" | jq -r '.body.storage.value')
  NEXT_VER=$((CUR_VER + 1))

  # Smart Appending: Add a horizontal rule and the new content to the top
  UPDATED_CONTENT="$HTML_CONTENT<hr/><br/>$PREV_CONTENT"

  curl -s -f -X PUT -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "${CONFLUENCE_BASE_URL}/rest/api/content/${PAGE_ID}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$PAGE_TITLE" --arg html "$UPDATED_CONTENT" --argjson ver "$NEXT_VER" \
      '{type: "page", title: $title, version: {number: $ver}, body: {storage: {value: $html, representation: "storage"}}}')"
fi

echo "✅ Success! Release notes posted to Confluence."
