#!/bin/bash
#
# engine.sh - Config-driven hook router
#
# Single entrypoint for all Claude Code hooks.
# Reads sop.json and routes to appropriate validators.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
SOP_CONFIG="$CLAUDE_DIR/sop.json"

# Read hook input from stdin
input=$(cat)

# Extract event info
hook_event=$(echo "$input" | jq -r '.hook_event_name // ""')
tool_name=$(echo "$input" | jq -r '.tool_name // ""')
tool_input=$(echo "$input" | jq -r '.tool_input // {}')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# Check if config exists
if [[ ! -f "$SOP_CONFIG" ]]; then
    echo "Warning: sop.json not found at $SOP_CONFIG" >&2
    exit 0
fi

# Read config
config=$(cat "$SOP_CONFIG")
enforcement=$(echo "$config" | jq -r '.enforcement // "hard"')

# Function to log events
log_event() {
    local outcome="$1"
    local rule_name="$2"

    local logging_enabled=$(echo "$config" | jq -r '.logging.enabled // false')
    if [[ "$logging_enabled" != "true" ]]; then
        return
    fi

    # Check if this event should be logged
    local log_events=$(echo "$config" | jq -r '.logging.events // []')
    if ! echo "$log_events" | jq -e "index(\"$hook_event\")" > /dev/null 2>&1; then
        return
    fi

    # Check if only logging blocked events
    local blocked_only=$(echo "$config" | jq -r '.logging.include_blocked_only // false')
    if [[ "$blocked_only" == "true" && "$outcome" != "blocked" ]]; then
        return
    fi

    local handler=$(echo "$config" | jq -r '.logging.handler // ""')
    if [[ -n "$handler" && -x "$SCRIPT_DIR/$handler" ]]; then
        # Pass log info to handler
        echo "{\"event\": \"$hook_event\", \"tool\": \"$tool_name\", \"outcome\": \"$outcome\", \"rule\": \"$rule_name\"}" | \
            "$SCRIPT_DIR/$handler"
    fi
}

# Function to check if a rule matches
rule_matches() {
    local rule_name="$1"
    local rule=$(echo "$config" | jq -r ".rules[\"$rule_name\"]")

    # Check if rule is enabled (default true if not specified)
    # Note: jq's // operator treats false as falsy, so we use has() instead
    local enabled=$(echo "$rule" | jq -r 'if has("enabled") then .enabled else true end')
    if [[ "$enabled" == "false" ]]; then
        return 1
    fi

    # Check if event matches
    local events=$(echo "$rule" | jq -r '.events // []')
    if ! echo "$events" | jq -e "index(\"$hook_event\")" > /dev/null 2>&1; then
        return 1
    fi

    # Check if tool matches (regex)
    local matcher=$(echo "$rule" | jq -r '.matcher // ""')
    if [[ -n "$matcher" && -n "$tool_name" ]]; then
        if ! echo "$tool_name" | grep -qE "^($matcher)$"; then
            return 1
        fi
    fi

    # Check condition if present (for Bash commands)
    local condition=$(echo "$rule" | jq -r '.condition // ""')
    if [[ -n "$condition" ]]; then
        local command=$(echo "$tool_input" | jq -r '.command // ""')
        if [[ -z "$command" ]]; then
            return 1
        fi
        if ! echo "$command" | grep -qE "$condition"; then
            return 1
        fi
    fi

    return 0
}

# Function to run a validator
run_validator() {
    local rule_name="$1"
    local rule=$(echo "$config" | jq -r ".rules[\"$rule_name\"]")
    local validator=$(echo "$rule" | jq -r '.validator // ""')

    if [[ -z "$validator" ]]; then
        return 0
    fi

    local validator_path="$SCRIPT_DIR/$validator"
    if [[ ! -x "$validator_path" ]]; then
        echo "Warning: Validator not found or not executable: $validator_path" >&2
        return 0
    fi

    # Run validator with original input
    echo "$input" | "$validator_path"
    return $?
}

# Get all rule names
rule_names=$(echo "$config" | jq -r '.rules | keys[]')

# Track if any rule blocked
blocked=false
blocking_rule=""

# Check each rule
for rule_name in $rule_names; do
    if rule_matches "$rule_name"; then
        if ! run_validator "$rule_name"; then
            blocked=true
            blocking_rule="$rule_name"
            break
        fi
    fi
done

# Log and exit
if [[ "$blocked" == "true" ]]; then
    log_event "blocked" "$blocking_rule"
    if [[ "$enforcement" == "hard" ]]; then
        exit 2
    else
        exit 0  # Soft enforcement - warn but allow
    fi
else
    log_event "allowed" ""
    exit 0
fi
