#!/bin/bash

# This script generates the HTML content for a Confluence page
# based on Jira information extracted from git commits.

PR_LINK="${PR_LINK}"
PR_TITLE="${PR_TITLE}"
HEAD_REF="${HEAD_REF}"
RELEASE_DATE=$(date +"%d %B")
YEAR=$(date +"%Y")
MONTH=$(date +"%b")

if [ ! -f extracted_info.md ]; then
  echo "❌ Error: extracted_info.md not found."
  exit 1
fi

# 1. Detect if hotfix
IS_HOTFIX="false"
if [[ "$PR_TITLE" =~ ^hotfix: ]] || [[ "$HEAD_REF" == *"hotfix/"* ]] || grep -iq "hotfix" extracted_info.md; then
  IS_HOTFIX="true"
fi

# 2. Extract standard Jira tickets (excluding PAYM-0) from the generated info
JIRA_TICKETS=$(grep -oE '[A-Z]+-[0-9]+' extracted_info.md | grep -v "PAYM-0" | sort -u)

# Helper to fetch Jira ticket summary
fetch_jira_summary() {
  echo "Using username: ${ATLASSIAN_USERNAME:-NOT_SET}"
  echo "Token present: ${ATLASSIAN_API_TOKEN:+YES}"

  local ticket_id="$1"
  if [[ -z "${ATLASSIAN_USERNAME:-}" ]] || [[ -z "${ATLASSIAN_API_TOKEN:-}" ]]; then
    echo "⚠️ Warning: ATLASSIAN_USERNAME or ATLASSIAN_API_TOKEN not set. Skipping API call for $ticket_id."
    echo "$ticket_id"
    return
  fi

  echo "Fetching summary for $ticket_id from Jira API..."
  local response
  response=$(curl -s -u "${ATLASSIAN_USERNAME}:${ATLASSIAN_API_TOKEN}" \
    "https://anywhereworks.atlassian.net/rest/api/2/issue/${ticket_id}?fields=summary")

  echo "API response for $ticket_id: $response"
  local summary
  summary=$(echo "$response" | jq -r '.fields.summary // empty')

  echo "Extracted summary for $ticket_id: $summary"
  if [[ -n "$summary" && "$summary" != "null" ]]; then
    echo "$ticket_id - $summary"
  else
    echo "$ticket_id"
  fi
}

TICKET_ROWS=""
while read -r ticket; do
  if [[ -n "$ticket" ]]; then
    SUMMARY=$(fetch_jira_summary "$ticket")
    TICKET_ROWS+="<tr><td><a href='https://anywhereworks.atlassian.net/browse/$ticket'>$SUMMARY</a></td></tr>"
  fi
done <<< "$JIRA_TICKETS"

# 3. Extract all PAYM-0 descriptions
PAYM_0_LIST=$(grep "\[PAYM-0\]" extracted_info.md | sed 's/- \[PAYM-0\] //' | sed 's/ (\[#.*\])//' || true)

if [[ -n "$PAYM_0_LIST" ]]; then
  PAYM_0_CONTENT="<strong>PAYM-0 Summary:</strong><ul>"
  while read -r line; do
    if [ -n "$line" ]; then
      CLEAN_LINE=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
      PAYM_0_CONTENT+="<li>$CLEAN_LINE</li>"
    fi
  done <<< "$PAYM_0_LIST"
  PAYM_0_CONTENT+="</ul>"
else
  PAYM_0_CONTENT=""
fi

# 4. Construct the Final HTML for Confluence
{
  echo "<ul>"
  echo "  <li>Associated PR: <a href='$PR_LINK'>LINK</a></li>"
  echo "  <li>Safe to rollback: <strong>YES</strong><small>(Note: <span style='color: rgb(255,0,0);'><strong>Change to NO</strong></span> if any database migrations or breaking API changes are included)</small></li>"
  echo "</ul>"
  echo "<table><thead><tr><th style=\"text-align: center\"><strong>Title</strong></th></tr></thead><tbody>"
  echo "$TICKET_ROWS"
  if [[ -n "$PAYM_0_CONTENT" ]]; then
    echo "<tr><td>$PAYM_0_CONTENT</td></tr>"
  fi
  echo "</tbody></table>"
} > confluence_body.html

PAGE_TITLE="$RELEASE_DATE"
if [ "$IS_HOTFIX" = "true" ]; then
  PAGE_TITLE="$RELEASE_DATE - Hotfix"
fi

# Output parameters for GITHUB_OUTPUT
echo "year=$YEAR" >> "$GITHUB_OUTPUT"
echo "month=$MONTH" >> "$GITHUB_OUTPUT"
echo "page_title=$PAGE_TITLE" >> "$GITHUB_OUTPUT"
