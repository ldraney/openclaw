#!/bin/bash
#
# no-main-commit.sh - Block commits on main/master and require issue branch
#
# Called by engine.sh for git commit commands.
# Validates commits only happen on issue branches.
#

set -e

# Read hook input from stdin
input=$(cat)

# Extract command and cwd
cwd=$(echo "$input" | jq -r '.cwd')

# Get current branch
branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")

# Block if on main/master
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "BLOCKED: Cannot commit directly to $branch." >&2
    echo "" >&2
    echo "The development SOP requires:" >&2
    echo "  1. Create a GitHub issue first (spike or feature)" >&2
    echo "  2. Work on an issue branch, not main" >&2
    echo "  3. Create a PR to merge changes" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  - Create an issue: gh issue create" >&2
    echo "  - Create a branch: git checkout -b <issue-num>-description" >&2
    exit 2
fi

# Block if no branch (detached HEAD)
if [[ -z "$branch" ]]; then
    echo "BLOCKED: Cannot commit in detached HEAD state." >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  - Create a branch: git checkout -b <issue-num>-description" >&2
    exit 2
fi

# Function to validate issue exists on GitHub
validate_issue() {
    local issue_ref="$1"
    local issue_num=""

    if [[ "$issue_ref" =~ ^#?([0-9]+)$ ]]; then
        issue_num="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    if command -v gh &> /dev/null; then
        gh issue view "$issue_num" --json state &> /dev/null 2>&1 && return 0
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

# Extract issue number from branch
issue_num=$(extract_issue_from_branch "$branch")

if [[ -z "$issue_num" ]]; then
    echo "BLOCKED: Branch '$branch' does not reference a GitHub issue." >&2
    echo "" >&2
    echo "Branch names must include an issue number:" >&2
    echo "  - 42-feature-description" >&2
    echo "  - issue-42-description" >&2
    echo "  - feature-#42" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  - Create an issue: gh issue create" >&2
    echo "  - Rename branch: git branch -m <issue-num>-$branch" >&2
    exit 2
fi

# Validate issue exists on GitHub
if ! validate_issue "$issue_num"; then
    echo "BLOCKED: Branch '$branch' references issue #$issue_num but issue not found on GitHub." >&2
    echo "" >&2
    echo "Either:" >&2
    echo "  - Issue #$issue_num doesn't exist" >&2
    echo "  - gh CLI not authenticated for this repo" >&2
    echo "" >&2
    echo "To proceed:" >&2
    echo "  - Create the issue: gh issue create" >&2
    echo "  - Or rename branch with valid issue number" >&2
    exit 2
fi

# All checks passed
exit 0
