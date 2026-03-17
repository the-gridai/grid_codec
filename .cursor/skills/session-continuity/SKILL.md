---
name: session-continuity
description: Maintain session context, update skills based on work done, and create useful scripts. Use at the end of significant work sessions or when asked to continue, document, or reflect on work done.
---

# Session Continuity

## After Significant Work

When a session includes meaningful changes (features, optimizations, fixes), do the following:

### 1. Update Skills
If the work revealed new patterns, workflows, or lessons:
- Update existing skills in `.cursor/skills/` with new knowledge
- Create new skills if a new workflow pattern emerged
- Keep skills concise — only add what the agent wouldn't already know
- When adding a new feature, check if it needs to be reflected across: codec-development (integration checklist), testing-strategy (test patterns), quality-check (audit phase), architecture-review (review dimensions), and release-version (pre-release steps)

### 2. Create Useful Scripts
If manual operations were repeated (benchmarking, profiling, data generation):
- Save reusable scripts to `.cursor/scripts/`
- Scripts should be self-contained and documented with usage comments
- Prefer Elixir `.exs` scripts for this codebase

### 3. Version Control Awareness
- `.cursor/` is in `.gitignore` — skills and scripts are local, not pushed
- `.cursorignore` has `!.cursor/` so Cursor still indexes them
- NEVER push `.cursor/` contents to git
- Specs and internal docs: write to local files, not version control

## When Asked to "Continue"

1. Check if there are pending tasks (TodoWrite state)
2. If all tasks are done, say so clearly — don't invent work
3. Suggest next steps that require the user's input or a different codebase

## Tracking What Was Done

Keep a mental model of session progression:
- What was the starting state (version, baseline numbers)
- Each change and its measured impact
- What's shipped vs what's local/experimental
- What depends on other repos 
