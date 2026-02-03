#!/bin/bash
#
# require-issue.sh - Validate GitHub issue exists for code changes
#
# Called by engine.sh for Write/Edit operations.
# Validates via .current-issue file or branch name.
#

set -e

# Read hook input from stdin
input=$(cat)

# Extract info
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
cwd=$(echo "$input" | jq -r '.cwd')

# Skip checks for .claude/ and .git/ files
if [[ "$file_path" == *".claude/"* ]] || [[ "$file_path" == *".git/"* ]]; then
    exit 0
fi

# Function to validate issue exists on GitHub
validate_issue() {
    local issue_ref="$1"
    local repo=""
    local issue_num=""

    # Parse issue reference (could be "42", "repo#42", "owner/repo#42")
    if [[ "$issue_ref" =~ ^([^#]+)#([0-9]+)$ ]]; then
        repo="${BASH_REMATCH[1]}"
        issue_num="${BASH_REMATCH[2]}"
    elif [[ "$issue_ref" =~ ^#?([0-9]+)$ ]]; then
        issue_num="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    # Try to validate with gh
    if command -v gh &> /dev/null; then
        if [[ -n "$repo" ]]; then
            gh issue view "$issue_num" --repo "$repo" --json state &> /dev/null && return 0
        else
            gh issue view "$issue_num" --json state &> /dev/null 2>&1 && return 0
        fi
    fi

    return 1
}

# Function to extract issue number from branch name
extract_issue_from_branch() {
    local branch="$1"

    if [[ "$branch" =~ ^([0-9]+)- ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$branch" =~ issue-([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$branch" =~ \#([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Check 1: Is there a .current-issue file?
if [[ -f "$cwd/.current-issue" ]]; then
    issue_ref=$(cat "$cwd/.current-issue" | tr -d '[:space:]')
    if [[ -n "$issue_ref" ]]; then
        if validate_issue "$issue_ref"; then
            exit 0
        else
            echo "BLOCKED: .current-issue contains '$issue_ref' but issue not found on GitHub." >&2
            echo "" >&2
            echo "Either:" >&2
            echo "  - The issue doesn't exist" >&2
            echo "  - gh CLI not authenticated" >&2
            echo "  - Not in a git repo with GitHub remote" >&2
            echo "" >&2
            echo "To fix:" >&2
            echo "  - Create the issue: gh issue create" >&2
            echo "  - Or update .current-issue with valid issue number" >&2
            exit 2
        fi
    fi
fi

# Check 2: Does branch name contain an issue number?
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
    issue_num=$(extract_issue_from_branch "$branch")

    if [[ -n "$issue_num" ]]; then
        if validate_issue "$issue_num"; then
            exit 0
        else
            echo "BLOCKED: Branch '$branch' references issue #$issue_num but issue not found on GitHub." >&2
            echo "" >&2
            echo "Either:" >&2
            echo "  - Issue #$issue_num doesn't exist" >&2
            echo "  - gh CLI not authenticated for this repo" >&2
            echo "" >&2
            echo "To fix:" >&2
            echo "  - Create the issue: gh issue create" >&2
            echo "  - Or switch to a valid issue branch" >&2
            exit 2
        fi
    fi
fi

# No valid issue found - BLOCK
echo "BLOCKED: No valid GitHub issue detected for this work." >&2
echo "" >&2
echo "The development SOP requires:" >&2
echo "  1. Create a GitHub issue first (spike or feature)" >&2
echo "  2. Validate assumptions before implementing" >&2
echo "  3. Update docs with learnings" >&2
echo "" >&2
echo "To proceed:" >&2
echo "  - Create an issue: gh issue create" >&2
echo "  - Then track it: echo '<issue-num>' > .current-issue" >&2
echo "  - Or use branch: git checkout -b <issue-num>-description" >&2
exit 2
