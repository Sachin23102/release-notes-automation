#!/bin/bash

# Shared script to extract Jira information from git commits
# Usage: ./extract-jira-info.sh <FROM_BRANCH> <TO_BRANCH>

FROM_BRANCH="${1:-origin/release/alpha}"
TO_BRANCH="${2:-origin/release/staging}"
REPO_URL="https://github.com/Adaptavant/fullpayments"

declare -A JIRA_MAP
PAYM_0_LIST=()

generate_bullet_point() {
    local ID="$1"
    local DESCRIPTION="$2"

    echo "- [$ID] $DESCRIPTION"
    echo "  - [x] Needs testing "
    echo "  - [ ] Tested "
    echo "  - [ ] Safe to rollback "
    echo "---"
}

process_commit_msg() {
    local COMMIT_MSG="$1"

    # Extract JIRA ID or PAYM-0 (get last match if ID is at end of message)
    local ID
    ID=$(echo "$COMMIT_MSG" | grep -oE '([A-Z]+-[0-9]+)' | tail -1)

    if [ -z "$ID" ]; then
        ID="UNKNOWN"
    fi

    # Remove the ID and any colon or space before/after
    local DESCRIPTION
    DESCRIPTION=$(echo "$COMMIT_MSG" | sed -E "s/[[:space:]]*$ID[[:space:]]*/ /")

    # Clean up leading/trailing spaces
    DESCRIPTION=$(echo "$DESCRIPTION" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Extract PR number if present in format (#123)
    local PR_NUMBER
    PR_NUMBER=$(echo "$COMMIT_MSG" | grep -oE '\(#([0-9]+)\)' | grep -oE '[0-9]+' | head -1)

    # If PR number exists, remove (#123) and append a clickable PR link
    if [[ -n "$PR_NUMBER" ]]; then
        DESCRIPTION=$(echo "$DESCRIPTION" | sed -E 's/\(#([0-9]+)\)//')
        DESCRIPTION="$DESCRIPTION ([#${PR_NUMBER}]($REPO_URL/pull/${PR_NUMBER}))"
    fi

    if [[ "$ID" == "PAYM-0" ]]; then
        PAYM_0_LIST+=("$DESCRIPTION")
    else
        # Combine commit messages for repeated JIRA tickets
        if [[ -n "${JIRA_MAP[$ID]}" ]]; then
            JIRA_MAP["$ID"]="${JIRA_MAP[$ID]}; $DESCRIPTION"
        else
            JIRA_MAP["$ID"]="$DESCRIPTION"
        fi
    fi
}

# Main execution
COMMITS=$(git log --pretty=format:"%s" "$FROM_BRANCH..$TO_BRANCH" || true)

if [ -z "$COMMITS" ]; then
  exit 0
fi

while IFS= read -r COMMIT_MSG; do
    if [[ -n "$COMMIT_MSG" ]]; then
        process_commit_msg "$COMMIT_MSG"
    fi
done < <(
  echo "$COMMITS" |
  grep -v '^Merge pull request' |
  grep -v '^Merge branch'
)

# Print PAYM-0 entries
for DESC in "${PAYM_0_LIST[@]}"; do
    generate_bullet_point "PAYM-0" "$DESC"
done

# Print bullet points for combined JIRA ticket messages
for ID in "${!JIRA_MAP[@]}"; do
    generate_bullet_point "$ID" "${JIRA_MAP[$ID]}"
done

