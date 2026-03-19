#!/bin/bash
set -euo pipefail

# Scripts to generate Confluence HTML for release notes
# Usage: ./generate-release-html.sh <PR_LINK> <PR_TITLE> <HEAD_REF> <EXTRACTED_INFO_FILE>

PR_LINK="$1"
PR_TITLE="$2"
HEAD_REF="$3"
EXTRACTED_INFO_FILE="$4"

RELEASE_DATE=$(date +"%d %B")
YEAR=$(date +"%Y")
MONTH=$(date +"%B")

echo "--- Generating Release HTML ---"
echo "Date: $RELEASE_DATE"
echo "PR Title: $PR_TITLE"

# 1. Detect if hotfix
IS_HOTFIX="false"
if [[ "$PR_TITLE" =~ ^hotfix: ]] || [[ "$HEAD_REF" == *"hotfix/"* ]] || grep -iq "hotfix" "$EXTRACTED_INFO_FILE"; then
  IS_HOTFIX="true"
fi

PAGE_TITLE="$RELEASE_DATE"
if [[ "$IS_HOTFIX" == "true" ]]; then
  PAGE_TITLE="$RELEASE_DATE - Hotfix"
fi

echo "extracted info file: - "
cat "$EXTRACTED_INFO_FILE"

# 2. Extract standard Jira tickets (excluding PAYM-0)
JIRA_TICKETS=$(grep -oE '[A-Z]+-[0-9]+' "$EXTRACTED_INFO_FILE" | grep -v "PAYM-0" | sort -u || true)

TICKET_ROWS=""
while read -r ticket; do
  if [[ -n "$ticket" ]]; then
    TICKET_ROWS+="<tr><td><a href='https://anywhereworks.atlassian.net/browse/$ticket'>https://anywhereworks.atlassian.net/browse/$ticket</a></td></tr>"
  fi
done <<< "$JIRA_TICKETS"

# 3. Extract all PAYM-0 descriptions
PAYM_0_LIST=$(grep "\[PAYM-0\]" "$EXTRACTED_INFO_FILE" | sed 's/- \[PAYM-0\] //' | sed 's/ (\[#.*\])//' || true)

PAYM_0_CONTENT="<strong>PAYM-0 Summary:</strong><ul>"
while read -r line; do
  if [[ -n "$line" ]]; then
    CLEAN_LINE=$(echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    PAYM_0_CONTENT+="<li>$CLEAN_LINE</li>"
  fi
done <<< "$PAYM_0_LIST"
PAYM_0_CONTENT+="</ul>"

# 4. Construct Final HTML
{
  echo "<ul>"
  echo "  <li>Associated PR: <a href='$PR_LINK'>LINK</a></li>"
  echo "  <li>Safe to rollback: <strong>YES</strong><br/><small>(Note: <span style='color: rgb(255,0,0);'><strong>Change to NO</strong></span> if any database migrations or breaking API changes are included)</small></li>"
  echo "</ul>"
  echo "<table><thead><tr><th>Title</th></tr></thead><tbody>"
  echo "$TICKET_ROWS"
  echo "<tr><td>$PAYM_0_CONTENT</td></tr>"
  echo "</tbody></table>"
} > confluence_body.html

# Output metadata for GitHub Actions
echo "date=$RELEASE_DATE" >> "$GITHUB_OUTPUT"
echo "year=$YEAR" >> "$GITHUB_OUTPUT"
echo "month=$MONTH" >> "$GITHUB_OUTPUT"
echo "page_title=$PAGE_TITLE" >> "$GITHUB_OUTPUT"

echo "✅ Generated confluence_body.html and workflow outputs."

