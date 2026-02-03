# MCPB Release Workflow

Prerelease QA flow for testing MCP servers in Claude Desktop before merging PRs.

## Key Concept

Claude Desktop ships with `npx` and `uvx` built-in. The `.mcpb` bundle is just a **wrapper** that tells Claude Desktop to run `npx your-package` or `uvx your-package`.

This means:
1. Publish to npm/PyPI → package available globally via npx/uvx
2. mcpb pack → creates a thin wrapper pointing to your package
3. Users install the .mcpb → Claude Desktop uses its built-in npx/uvx

```
npm publish → package on npm
    ↓
mcpb pack → bundle says "run: npx my-package"
    ↓
Claude Desktop (has npx built-in) → runs your code
```

**Why this is powerful:** No bundling dependencies. No native module issues. Just publish and wrap.

## The Flow

```
Code ready → PR open (not merged)
    ↓
Publish prerelease to npm/PyPI (so npx/uvx can fetch it)
    ↓
Pack mcpb bundle + GitHub release
    ↓
Install .mcpb in Claude Desktop → QA Test
    ↓
If works → Merge PR
```

## Node.js Prerelease

```bash
# 1. Bump version
npm version prerelease --preid=beta  # → v0.2.0-beta.1
# Or: npm version prerelease --preid=rc

# 2. Build
npm run build

# 3. Publish npm beta
npm publish --tag beta

# 4. Push version commit & tag
git push && git push origin v0.2.0-beta.1

# 5. Pack MCPB bundle
mcpb pack  # → my-mcp.mcpb

# 6. Create GitHub prerelease
gh release create v0.2.0-beta.1 ./my-mcp.mcpb --prerelease
```

## Python (Poetry) Prerelease

```bash
# 1. Bump version
poetry version prerelease  # or manually edit pyproject.toml

# 2. Build
poetry build

# 3. Publish to PyPI
poetry publish

# 4. Push & tag
git add pyproject.toml && git commit -m "Bump version"
git tag v0.3.0-beta.1
git push && git push origin v0.3.0-beta.1

# 5. Pack MCPB bundle
mcpb pack

# 6. Create GitHub release
gh release create v0.3.0-beta.1 ./my-mcp.mcpb --prerelease
```

## Claude Desktop Installation (QA Testing)

1. Go to GitHub release page
2. Download the `.mcpb` file
3. Claude Desktop → Settings → Extensions → Install Extension
4. Select the `.mcpb` file
5. Test the MCP server functionality
6. If good → merge the PR

## Manifest.json Examples

Node.js (wraps npx):
```json
{
  "manifest_version": "0.3",
  "name": "my-mcp",
  "version": "0.2.0-beta.1",
  "description": "What it does",
  "author": { "name": "Your Name" },
  "server": {
    "type": "node",
    "entry_point": "dist/index.js",
    "mcp_config": {
      "command": "npx",
      "args": ["my-package-name@0.2.0-beta.1"]
    }
  }
}
```

Python (wraps uvx):
```json
{
  "manifest_version": "0.3",
  "name": "my-mcp",
  "version": "0.3.0-beta.1",
  "description": "What it does",
  "author": { "name": "Your Name" },
  "server": {
    "type": "python",
    "entry_point": "server/main.py",
    "mcp_config": {
      "command": "${HOME}/.local/bin/uvx",
      "args": ["my-package-name"]
    }
  }
}
```

Note: The `mcp_config` tells Claude Desktop how to actually run the server.

## MCPB CLI Commands

```bash
npm install -g @anthropic-ai/mcpb  # Install CLI
mcpb init                           # Generate manifest.json
mcpb pack                           # Create .mcpb bundle
```
