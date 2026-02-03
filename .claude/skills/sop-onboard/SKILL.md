# Onboarding a Project to dev-sop-engine

Step-by-step playbook for setting up dev-sop-engine in any project.

## Prerequisites

- Project is a git repository
- `npx dev-sop-engine .` is available (npm installed), OR the `sop_generate` MCP tool is configured
- You have push access to the repository
- GitHub CLI (`gh`) is available for issue/PR creation

## Step 1: Analyze the Project

Before writing any configuration, understand the project:

```bash
# What language/framework?
ls package.json Cargo.toml pyproject.toml go.mod Makefile requirements.txt 2>/dev/null

# What's the structure?
ls -la
ls src/ lib/ app/ 2>/dev/null

# Existing Claude config?
ls -la .claude/ .mcp.json CLAUDE.md 2>/dev/null

# Git workflow?
git log --oneline -10
git branch -a
```

Key questions:
- What language and build system does it use?
- Are there existing MCP servers to preserve?
- What development rules make sense for this project?
- Would any custom skills or agents help this team?

## Step 2: Create a GitHub Issue

Create an issue to track the onboarding work:

```bash
gh issue create \
  --title "Set up dev-sop-engine for project configuration" \
  --body "Scaffold sop/ directory with sop.json and run generator to produce .claude/ config."
```

## Step 3: Create a Branch

```bash
git checkout -b {issue-number}-setup-dev-sop-engine
```

## Step 4: Scaffold the sop/ Directory

Create the directory structure:

```bash
mkdir -p sop/validators sop/loggers sop/skills sop/agents sop/hooks
```

## Step 5: Author sop.json

Start with this minimal template and tailor it to the project:

```json
{
  "version": "1.0",
  "enforcement": "hard",

  "rules": {
    "no-main-commit": {
      "description": "Block direct work on main/master and require issue branch",
      "events": ["PreToolUse"],
      "matcher": "Bash",
      "condition": "git.*(ci|push|merge)",
      "validator": "validators/no-main-commit.sh",
      "enabled": true
    }
  },

  "logging": {
    "enabled": true,
    "stderr": true,
    "file": "~/.claude/logs/sop-hooks.jsonl",
    "events": ["PreToolUse", "Stop"],
    "include_blocked_only": false,
    "handler": "loggers/log-event.sh"
  },

  "subagents": {
    "inherit_rules": true
  },

  "mcp": {},

  "skills": {},

  "agents": {}
}
```

### Tailoring Guidelines

**Rules** - Add rules based on project needs:
- `no-main-commit` - Almost always include. Prevents direct work on main.
- `require-issue` - Add if the team uses issue-driven development.
- `push-before-switch` - Add if context switching is common.
- Custom validators - Write project-specific rules (e.g., "don't modify generated files").

**MCP Servers** - Add servers the project already uses or needs:
- Preserve any existing `.mcp.json` entries (they'll be merged automatically).
- Add project-relevant servers (e.g., database, API tools).

**Skills** - Add skills for recurring workflows:
- Deployment playbooks, release checklists, onboarding guides.
- Content goes in `sop/skills/<name>.md`.

**Agents** - Add agents for specialized tasks:
- Code review, testing, documentation generation.
- Prompts go in `sop/agents/<name>.md`.

## Step 6: Copy Validator and Logger Scripts

The project needs the hook infrastructure. Copy from dev-sop-engine's reference implementation or write project-specific versions.

Required for the starter template:
- `sop/validators/no-main-commit.sh` - Blocks work on main/master
- `sop/loggers/log-event.sh` - Logs hook events to JSONL
- `sop/hooks/engine.sh` - Hook router entry point

These scripts receive JSON on stdin and use exit codes:
- `0` = allow action
- `2` = block action (stderr shown to Claude)

Make all scripts executable: `chmod +x sop/**/*.sh`

## Step 7: Run the Generator

```bash
npx dev-sop-engine .
```

Or if using the MCP tool, invoke `sop_generate` with the project directory.

## Step 8: Verify Output

```bash
# Check generated structure
ls -la .claude/
ls -la .claude/hooks/
ls -la .claude/skills/
ls -la .claude/agents/
cat .claude/settings.json

# Check MCP config if applicable
cat .mcp.json
```

Verify:
- `.claude/settings.json` contains your rules as hook entries
- `.claude/hooks/` contains your validator and logger scripts
- Any skills appear in `.claude/skills/<name>/SKILL.md`
- Any agents appear in `.claude/agents/<name>.md` with YAML frontmatter
- `.mcp.json` has your servers (and preserves any pre-existing manual ones)

## Step 9: Save and Open PR

```bash
git add sop/ .claude/ .mcp.json
git push -u origin HEAD
gh pr create \
  --title "Set up dev-sop-engine for project configuration" \
  --body "Scaffolds sop/ directory and generates .claude/ config using dev-sop-engine."
```

## Troubleshooting

### Generator fails with "sop.json not found"
- Ensure `sop/sop.json` exists in the target directory (not at the root).

### Scripts not executing
- Check permissions: `chmod +x sop/**/*.sh`
- Check shebang lines: scripts should start with `#!/bin/bash` or `#!/usr/bin/env bash`

### MCP servers missing from .mcp.json
- Servers go in `sop.json` under the `"mcp"` key.
- Existing manual `.mcp.json` entries are preserved automatically.

### Hook validators not triggering
- Verify the `events` array matches the hook event name exactly.
- Check `matcher` regex matches the tool name.
- Ensure `enabled` is `true`.

### Generated files look wrong
- Always regenerate from scratch: `npx dev-sop-engine .`
- Never hand-edit files in `.claude/` - edit `sop/` sources instead.
