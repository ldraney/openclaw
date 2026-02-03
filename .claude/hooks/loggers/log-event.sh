#!/bin/bash
#
# log-event.sh - Structured logging for Claude Code hooks
#
# Logs events in JSONL format to both stderr (visible) and file (persistent).
#
# Log location: ~/.claude/logs/sop-hooks.jsonl
# Format: One JSON object per line with timestamp, event, tool, outcome, etc.

set -e

# Read hook input from stdin
input=$(cat)

# Extract fields from hook input
event=$(echo "$input" | jq -r '.hook_event_name // .event // "unknown"')
tool=$(echo "$input" | jq -r '.tool_name // .tool // "none"')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# Get timestamp in ISO format
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get project name from cwd (last directory component)
project=$(basename "$cwd")

# Get current branch if in a git repo
branch=""
if [[ -d "$cwd/.git" ]] || git -C "$cwd" rev-parse --git-dir &>/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
fi

# Get session ID from environment or generate one
# Claude Code may set this, otherwise we use a fallback
session_id="${CLAUDE_SESSION_ID:-$(echo "$PPID")}"

# Ensure log directory exists
log_dir="$HOME/.claude/logs"
mkdir -p "$log_dir"

log_file="$log_dir/sop-hooks.jsonl"

# Build log entry
log_entry=$(jq -n \
    --arg ts "$timestamp" \
    --arg event "$event" \
    --arg tool "$tool" \
    --arg project "$project" \
    --arg branch "$branch" \
    --arg session "$session_id" \
    '{
        timestamp: $ts,
        event: $event,
        tool: $tool,
        project: $project,
        branch: $branch,
        session: $session
    }'
)

# Write to file (persistent)
echo "$log_entry" >> "$log_file"

# Write to stderr (visible in terminal) - condensed format
echo "[SOP] $timestamp | $event | $tool | $project" >&2

# Always allow (this is just logging)
exit 0
