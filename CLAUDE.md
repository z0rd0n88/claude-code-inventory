# CLAUDE.md

## Project Overview

**claude-code-inventory** is a Claude Code plugin that auto-generates a unified inventory of all Claude Code automations (hooks, skills, plugins, agents, MCP servers) across global, project, and local scopes. It produces `.CLAUDE.inventory.md` (human-readable), `.CLAUDE.inventory.json` (machine-readable), and `.CLAUDE.inventory.hash` (staleness detection).

**Version:** 2.1.0
**License:** MIT
**Author:** z0rd0n88

## Repository Structure

```
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata (name, version, category)
├── commands/
│   ├── inventory.md             # /inventory slash command
│   ├── inventory-global.md      # /inventory-global slash command (v2.0)
│   └── inventory-compare.md     # /inventory-compare slash command (v2.0)
├── docs/
│   └── superpowers/
│       ├── plans/
│       │   ├── 2026-04-11-inventory-v12-deep-scan.md
│       │   ├── 2026-04-11-inventory-v20-global-view.md
│       │   └── 2026-04-11-inventory-v21-capabilities.md
│       └── specs/
│           └── 2026-04-11-inventory-v12-v21-design.md
├── evals/
│   └── evals.json               # Evaluation test cases (8 scenarios)
├── examples/
│   └── sample-output.md         # Real-world example of generated output
├── hooks/
│   ├── hooks.json               # SessionStart hook registration
│   ├── inventory.cmd    # Polyglot Windows+Unix wrapper
│   └── inventory.sh     # Bash staleness detection script
├── skills/
│   └── inventory/
│       └── SKILL.md             # Core 7-phase generation logic (~800 lines)
├── README.md                    # Full documentation
└── CLAUDE.md                    # This file
```

## Tech Stack

- **Bash** — Hook scripts with cross-platform support (macOS/Linux/Windows via Git Bash)
- **Markdown** — Skills, commands, and documentation (with YAML frontmatter)
- **JSON** — Configuration files (plugin.json, hooks.json, evals.json)
- **No external dependencies** — Runs entirely via Claude Code's built-in capabilities

## Architecture

### Core Flow

1. **SessionStart hook** (`hooks/inventory.sh`) runs on every session start
2. Hook performs lightweight staleness detection (file age > 24h or config hash changed)
3. If stale, hook outputs a JSON message prompting Claude to regenerate
4. **Skill** (`skills/inventory/SKILL.md`) executes 7-phase generation:
   - Discovery → Classification → Validation → Change Detection → Recommendations → Generation → Gitignore

### Key Design Patterns

- **Polyglot wrapper**: `inventory.cmd` works as both batch (Windows) and bash (Unix)
- **Three-tier staleness**: Missing file → age-based (24h) → config hash comparison (MD5)
- **Multi-format output**: `.md` for humans, `.json` for tools, `.hash` for fast staleness checks
- **Self-documenting**: The inventory lists the plugin itself among discovered automations
- **Non-destructive hooks**: Hook only signals staleness; Claude decides whether to regenerate

### Configuration Sources Scanned

| Scope   | Sources |
|---------|---------|
| Global  | `~/.claude/settings.json`, `~/.claude/plugins/installed_plugins.json`, `~/.claude/plugins/blocklist.json`, `~/.claude/skills/*/SKILL.md`, `~/.claude/mcp-needs-auth-cache.json`, `~/.claude/keybindings.json`, `~/.claude/CLAUDE.md`, `~/.claude/scheduled-tasks/*/`, `~/.claude/plugins/cache/` (orphan markers) |
| Project | `.claude/settings.json`, `.claude/skills/*/SKILL.md`, `.claude/agents/*.md`, `CLAUDE.md`, `**/CLAUDE.md` (subdirectories) |
| Local   | `.claude/settings.local.json` (permission count only) |
| Memory  | `~/.claude/projects/<slug>/memory/MEMORY.md`, `~/.claude/projects/<slug>/memory/*.md` |

## Development Guide

### Naming Conventions

- **Files**: dash-separated lowercase (`inventory`, not `updateAutomatons`)
- **Output files**: `.CLAUDE.inventory.*` prefix (dot-prefixed, distinct namespace)
- **Frontmatter**: YAML blocks delimited by `---` at top of `.md` files

### JSON Style

- 2-space indentation
- Flat top-level structure

### Markdown Tables

- Pipe-delimited columns with descriptive headers
- Status indicators: `active`, `ORPHANED`, `MISSING`

### Error Handling

- Missing config files silently skipped (`2>/dev/null`)
- Warnings collected and surfaced in validation output
- Fallback chains (e.g., `md5sum` → `md5` → Python hashlib → timestamp)
- Graceful degradation for every edge case (no git repo, no `.claude/`, empty blocklist, first run)

### Testing

Evaluations are defined in `evals/evals.json` with 8 test scenarios:
1. Full inventory listing (both scopes)
2. Skills/plugins only (handles missing `.claude/`)
3. Regeneration after plugin install (detects Recent Changes)
4. Memory files, scheduled tasks, and plugin health status
5. Hook execution order and CLAUDE.md hierarchy
6. Global-only inventory via `/inventory-global`
7. Cross-project comparison via `/inventory-compare`
8. Deferred tools, monitor tracking, and sandbox security

No formal test runner — evaluation framework is for future expansion.

### Key Files to Understand

| File | Why It Matters |
|------|---------------|
| `skills/inventory/SKILL.md` | Core logic — all 7 generation phases, output templates, edge cases |
| `hooks/inventory.sh` | Staleness detection — platform-aware stat, MD5 hashing, fallbacks |
| `commands/inventory.md` | Slash command entry point — frontmatter + invocation instructions |
| `.claude-plugin/plugin.json` | Plugin identity — name, version, category for marketplace |

## Common Tasks

### Modifying generation logic
Edit `skills/inventory/SKILL.md`. The 7 phases are clearly delineated with headers.

### Changing staleness thresholds
Edit `hooks/inventory.sh`. The 24-hour threshold is in the age comparison logic.

### Adding new config sources
Update the Discovery phase in `SKILL.md` to read additional files, then update Classification and Generation phases to include the new data.

### Adding evaluation scenarios
Append to `evals/evals.json` following the existing pattern of `prompt` + `expected_output` objects.
