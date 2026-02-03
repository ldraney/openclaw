#!/bin/bash
#
# view-logs.sh - View and query SOP hook logs
#
# Usage:
#   view-logs.sh              # Last 20 entries
#   view-logs.sh -n 50        # Last 50 entries
#   view-logs.sh -f           # Follow (tail -f)
#   view-logs.sh -q '.event'  # Query with jq
#   view-logs.sh --blocked    # Show only blocked events
#   view-logs.sh --today      # Today's entries only

log_file="$HOME/.claude/logs/sop-hooks.jsonl"

if [[ ! -f "$log_file" ]]; then
    echo "No logs found at $log_file"
    exit 0
fi

case "${1:-}" in
    -f|--follow)
        tail -f "$log_file" | jq -c '.'
        ;;
    -n)
        tail -n "${2:-20}" "$log_file" | jq -c '.'
        ;;
    -q|--query)
        cat "$log_file" | jq -c "${2:-.}"
        ;;
    --blocked)
        cat "$log_file" | jq -c 'select(.outcome == "blocked")'
        ;;
    --today)
        today=$(date -u +"%Y-%m-%d")
        cat "$log_file" | jq -c "select(.timestamp | startswith(\"$today\"))"
        ;;
    --stats)
        echo "=== SOP Hook Log Stats ==="
        echo ""
        echo "Total entries: $(wc -l < "$log_file" | tr -d ' ')"
        echo ""
        echo "By event type:"
        cat "$log_file" | jq -r '.event' | sort | uniq -c | sort -rn
        echo ""
        echo "By tool:"
        cat "$log_file" | jq -r '.tool' | sort | uniq -c | sort -rn
        echo ""
        echo "By project:"
        cat "$log_file" | jq -r '.project' | sort | uniq -c | sort -rn
        ;;
    -h|--help)
        echo "Usage: view-logs.sh [option]"
        echo ""
        echo "Options:"
        echo "  (none)      Show last 20 entries"
        echo "  -n N        Show last N entries"
        echo "  -f          Follow log (tail -f)"
        echo "  -q QUERY    Query with jq expression"
        echo "  --blocked   Show only blocked events"
        echo "  --today     Show today's entries"
        echo "  --stats     Show statistics"
        echo "  -h          Show this help"
        ;;
    *)
        tail -n 20 "$log_file" | jq -c '.'
        ;;
esac
