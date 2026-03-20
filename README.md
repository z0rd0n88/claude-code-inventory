# claude-code-inventory

A Claude Code plugin that auto-generates a comprehensive inventory of your entire Claude Code environment — hooks, skills, plugins, agents, MCP servers — organized by scope and tagged as **installed** or **custom**.

> **One file to see everything.** No more digging through `settings.json`, plugin caches, and skill directories to remember what you have.

## What It Does

Generates three files in your project root:

| File | Purpose |
|------|---------|
| `.CLAUDE.automatons.md` | Human-readable inventory (markdown tables) |
| `.CLAUDE.automatons.json` | Machine-readable sidecar (for tooling) |
| `.CLAUDE.automatons.hash` | Config hash for smart staleness detection |

All three are gitignored automatically.

### Example Output

```
## Global Scope (~/.claude/)

### Skills
| Name | Origin | Description |
|------|--------|-------------|
| add-claude-to-gitignore | custom | Auto-add .claude/ and CLAUDE.md to .gitignore |
| execute-approved-plan | custom | Launch autonomous plan execution after approval |
| update-automatons | custom | Generate this automation inventory file |

### Plugins
| Plugin | Source | Origin | Version |
|--------|--------|--------|---------|
| superpowers | claude-plugins-official | installed | 5.0.5 |
| commit-and-push | local | custom | 1.0.0 |

## Project Scope (.claude/)

### MCP Servers
| Name | Type | Package/URL | Origin |
|------|------|-------------|--------|
| context7 | npx | @upwind-media/context7-mcp@latest | custom |

### Skills
| Name | Origin | Description |
|------|--------|-------------|
| deploy-runpod | custom | Build, push, and deploy to RunPod |
| health-check | custom | Unified health check for all services |
```

See [`examples/sample-output.md`](examples/sample-output.md) for a complete example.

## Features

### Scope-Ordered Organization

Every item is categorized under one of three scopes:

| Scope | Location | What's There |
|-------|----------|-------------|
| **Global** | `~/.claude/` | Settings, plugins, global skills, global hooks |
| **Project** | `.claude/` | MCP servers, project skills, agents, project hooks |
| **Local** | `.claude/settings.local.json` | User-specific permissions (count only) |

### Installed vs Custom Classification

Each item is tagged based on its origin:

| Tag | Meaning | Detection |
|-----|---------|-----------|
| `installed` | From a plugin marketplace | `@claude-plugins-official` suffix in `enabledPlugins` |
| `custom` | User-created | Skills in `~/.claude/skills/`, local plugins (`@local`), user-defined hooks |
| `blocked` | In the plugin blocklist | Listed in `~/.claude/plugins/blocklist.json` |

### Three-Tier Staleness Detection

The SessionStart hook uses a cascade to decide when to prompt regeneration:

```
1. File missing?         → Trigger immediately
2. File older than 24h?  → Trigger (time-based)
3. Config hash changed?  → Trigger (content-based)
```

The hash check is the most powerful — it concatenates `settings.json`, `installed_plugins.json`, and skill directory listings, then MD5s the result. **Installing a plugin triggers regeneration even if the inventory was generated seconds ago.**

### Self-Documenting

The generated inventory includes the `update-automatons` plugin itself — its skill, command, and SessionStart hook. The file documents the system that generates it.

### Validation Warnings

The skill checks that every referenced automation actually exists on disk:

- Hook scripts present at referenced paths
- Skill `SKILL.md` files readable
- Plugins not orphaned (no `.orphaned_at` marker)
- MCP server commands available

Broken references get flagged with `[!]` warnings in a Validation section.

### Change Detection

When regenerating, the skill compares the new inventory against the previous `.CLAUDE.automatons.json`. Items added or removed since the last run appear in a "Recent Changes" section at the top.

### Recommendations

A lightweight gap analysis that reads your project's tech stack (`pyproject.toml`, `package.json`) and suggests 3-5 automations you're missing. For a full analysis, run `/claude-code-setup:claude-automation-recommender`.

## Installation

### Quick Install (Local Plugin)

1. Copy the plugin files to your local plugin cache:

```bash
mkdir -p ~/.claude/plugins/cache/local/update-automatons/1.0.0
cp -r .claude-plugin commands skills hooks \
  ~/.claude/plugins/cache/local/update-automatons/1.0.0/
```

2. Register in your global settings:

```bash
# Add to ~/.claude/settings.json under "enabledPlugins":
# "update-automatons@local": true
```

3. Start a new Claude Code session. The SessionStart hook will detect the missing inventory and prompt you to run `/update-automatons`.

### Manual

Just copy the `skills/update-automatons/SKILL.md` to `~/.claude/skills/update-automatons/SKILL.md` if you only want the skill without the hook or slash command. You'll need to invoke it manually.

## Usage

### Slash Command

```
/update-automatons
```

Scans all configuration sources and generates the inventory.

### Automatic (SessionStart Hook)

Every time you start a Claude Code session in a git repo, the hook checks if the inventory is missing, stale (>24h), or if configs have changed. If so, it prompts:

> "Automation inventory (.CLAUDE.automatons.md) is missing, stale, or configs have changed. Run /update-automatons to regenerate."

### After Installing/Removing Plugins

Run `/update-automatons` after any plugin, skill, or MCP server changes to capture them immediately.

### After Running Automation Recommender

Run `/update-automatons` after `/claude-code-setup:claude-automation-recommender` to capture new recommendations in the inventory.

## Architecture

### Plugin Structure

```
update-automatons/1.0.0/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── commands/
│   └── update-automatons.md     # /update-automatons slash command
├── skills/
│   └── update-automatons/
│       └── SKILL.md             # 7-phase skill instructions
└── hooks/
    ├── hooks.json               # SessionStart hook registration
    ├── update-automatons.sh     # Bash staleness detection
    └── update-automatons.cmd    # Polyglot Windows+Unix wrapper
```

### How It Works

The skill instructs Claude through 7 phases:

```
Phase 1: Discovery      — Read configs in parallel (global + project + local)
Phase 2: Classification  — Tag each item as installed/custom/blocked
Phase 3: Validation      — Check all references exist on disk
Phase 4: Change Detection — Diff against previous inventory
Phase 5: Recommendations  — Gap analysis based on tech stack
Phase 6: Generation       — Write .md, .json, and .hash files
Phase 7: Gitignore        — Ensure all generated files are ignored
```

### Configuration Sources Scanned

| File | What's Extracted |
|------|-----------------|
| `~/.claude/settings.json` | Hooks, enabledPlugins, effortLevel |
| `~/.claude/plugins/installed_plugins.json` | Plugin names, versions, install dates |
| `~/.claude/plugins/blocklist.json` | Blocked plugins and reasons |
| `~/.claude/skills/*/SKILL.md` | Global skill names and descriptions |
| `.claude/settings.json` | Project hooks, MCP servers |
| `.claude/skills/*/SKILL.md` | Project skill names and descriptions |
| `.claude/agents/*.md` | Project agent names and descriptions |
| `.claude/settings.local.json` | Permission count (entries not listed) |
| Plugin install directories | Bundled skills, agents, commands, hooks |

### Cross-Platform Hooks

The `.cmd` file is a polyglot — it runs as Windows batch *and* Unix bash from a single file:

```cmd
: << 'CMDBLOCK'
@echo off
"%ProgramFiles%\Git\bin\bash.exe" "%~dp0update-automatons.sh" %*
exit /b %ERRORLEVEL%
CMDBLOCK
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/update-automatons.sh" "$@"
```

Windows sees `@echo off` and runs Git Bash. Unix ignores the batch block via heredoc and runs bash directly.

## Design Decisions

### Why a Plugin Instead of a Bare Skill?

A bare skill (single `SKILL.md` in `~/.claude/skills/`) would work, but the plugin structure adds:

| Feature | Bare Skill | Plugin |
|---------|-----------|--------|
| Slash command (`/update-automatons`) | No | Yes |
| Bundled SessionStart hook | No (manual settings.json edit) | Yes (auto-loaded) |
| Clean enable/disable | Delete the file | Toggle in `enabledPlugins` |
| Files | 1 | 6 |

The plugin system auto-loads hooks from `hooks/hooks.json` when the plugin is enabled — no manual `settings.json` editing needed.

### Why Three Output Files?

| File | Audience | Purpose |
|------|----------|---------|
| `.CLAUDE.automatons.md` | Humans | Read, scan, understand at a glance |
| `.CLAUDE.automatons.json` | Tools | Programmatic access, diffing, cross-project comparison |
| `.CLAUDE.automatons.hash` | Hook script | Fast staleness detection without re-scanning |

### Why Config Hash Instead of Just Time-Based?

Time-based staleness (24h) misses the most important case: **you just installed a plugin**. The hash approach computes MD5 of `settings.json` + `installed_plugins.json` + skill directory listings. Any config change triggers regeneration immediately, even if the inventory was generated seconds ago.

## Roadmap

The name "claude-code-inventory" reflects a broader vision beyond just automations:

| v1.0 (Current) | v2.0 (Planned) |
|----------------|----------------|
| Hooks, skills, plugins, agents, MCP servers | Memory files — what's in `~/.claude/projects/*/memory/` |
| Installed/custom/blocked tags | Scheduled tasks — cron jobs |
| Validation warnings | MCP auth state — which servers need re-auth |
| Change detection | Keybindings — custom shortcuts |
| Recommendations | Cross-project comparison — "project A has X but B doesn't" |
| — | Plugin health — orphaned, outdated, version mismatches |
| — | Permission patterns — frequently allowed/denied actions |

The JSON sidecar already enables this — new sections can be added without breaking the existing structure.

## License

MIT
