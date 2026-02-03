# Development Workflow

## Project Law

**No implementation without validated assumptions.**

Every feature must go through assumption validation before code is written. This prevents wasted effort on misunderstood requirements.

## Issue Types

### Spike (Research)
- Purpose: Validate assumptions, explore unknowns
- Output: Findings document, not code
- Branch: `spike/{issue-number}-{description}`
- Duration: Time-boxed

### Feature
- Purpose: Implement validated requirements
- Prerequisites: Spike completed OR assumptions are trivial
- Branch: `{issue-number}-{description}`
- Requires: Clear acceptance criteria

## Development Flow

1. **Issue First**
   - Create GitHub issue before any work
   - Define what success looks like
   - List assumptions that need validation

2. **Assumption Check**
   - Are there unknowns? → Create spike first
   - All clear? → Proceed to implementation

3. **Branch from Issue**
   - Branch name includes issue number
   - One branch per issue

4. **Small, Focused Changes**
   - Each commit does one thing
   - PR should be reviewable in <15 minutes

5. **Push Before Switch**
   - Always push current work before changing branches
   - Prevents lost work and enables collaboration

## Anti-Patterns

- Starting to code before understanding the problem
- "I'll figure it out as I go" without a spike
- Mixing multiple concerns in one PR
- Working on main/master directly
- Unpushed commits when switching context
