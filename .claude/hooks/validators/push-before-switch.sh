#!/bin/bash
#
# push-before-switch.sh - Ensure branch is pushed before switching
#
# Called by engine.sh for git checkout/switch commands.
# Prevents work from being stranded locally.
#

set -e

# Read hook input from stdin
input=$(cat)

# Extract command
command=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd')

# Ignore if creating a new branch
if [[ "$command" =~ git\ checkout\ -b ]] || [[ "$command" =~ git\ switch\ -c ]]; then
    exit 0
fi

# Ignore if restoring files (git checkout -- file or git checkout HEAD file)
if [[ "$command" =~ git\ checkout\ -- ]] || [[ "$command" =~ git\ checkout\ HEAD ]]; then
    exit 0
fi

# Check if we're in a git repo
if ! git -C "$cwd" rev-parse --git-dir &>/dev/null 2>&1; then
    exit 0
fi

# Get current branch
current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")

# If no branch (detached HEAD) or on main, allow switch
if [[ -z "$current_branch" ]] || [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
    exit 0
fi

# Check if branch has a remote tracking branch
tracking=$(git -C "$cwd" config --get "branch.$current_branch.remote" 2>/dev/null || echo "")

if [[ -z "$tracking" ]]; then
    echo "BLOCKED: Branch '$current_branch' has never been pushed to remote." >&2
    echo "" >&2
    echo "Before switching branches, push your work:" >&2
    echo "  git push -u origin $current_branch" >&2
    echo "" >&2
    echo "This ensures your work is safely stored on the remote." >&2
    exit 2
fi

# Check for unpushed commits
unpushed=$(git -C "$cwd" log @{u}..HEAD --oneline 2>/dev/null || echo "")

if [[ -n "$unpushed" ]]; then
    commit_count=$(echo "$unpushed" | wc -l | tr -d ' ')
    echo "BLOCKED: Branch '$current_branch' has $commit_count unpushed commit(s)." >&2
    echo "" >&2
    echo "Unpushed commits:" >&2
    echo "$unpushed" | head -5 >&2
    if [[ $commit_count -gt 5 ]]; then
        echo "  ... and $((commit_count - 5)) more" >&2
    fi
    echo "" >&2
    echo "Before switching branches, push your work:" >&2
    echo "  git push" >&2
    exit 2
fi

# Check for uncommitted changes
if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
    echo "BLOCKED: Branch '$current_branch' has uncommitted changes." >&2
    echo "" >&2
    echo "Before switching branches:" >&2
    echo "  1. Commit your changes: git add . && git commit -m 'WIP'" >&2
    echo "  2. Push to remote: git push" >&2
    exit 2
fi

# All checks passed
exit 0
