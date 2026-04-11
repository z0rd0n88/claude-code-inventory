---
description: "Generate or refresh ~/.claude/.CLAUDE.inventory.md — the global-scope automation inventory (plugins, skills, hooks, keybindings, auth state)"
---

Invoke the inventory skill in **global mode**. Follow the skill instructions exactly,
but operate in global mode:

- Read only global-scope discovery sources (~/.claude/)
- Skip all project-scope and local-scope reads
- Skip Recommendations (no project tech stack to analyze)
- Write output files to ~/.claude/ instead of the project root:
  - ~/.claude/.CLAUDE.inventory.md
  - ~/.claude/.CLAUDE.inventory.json
  - ~/.claude/.CLAUDE.inventory.hash
- Skip the gitignore step
- Use "Regenerate: `/inventory-global`" in the header
