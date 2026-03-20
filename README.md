# claude-code-inventory

A Claude Code plugin that auto-generates a comprehensive inventory of your entire Claude Code environment — hooks, skills, plugins, agents, MCP servers — organized by scope and tagged as **installed** or **custom**.

> **One file to see everything.** No more digging through `settings.json`, plugin caches, and skill directories to remember what you have.

## The Problem

Claude Code's automation ecosystem grows fast. You install plugins, create custom skills, add hooks, configure MCP servers, define agents — and within weeks you can't remember what you have or where it lives. Configuration is scattered across:

- `~/.claude/settings.json` (global hooks, plugins, permissions)
- `~/.claude/plugins/installed_plugins.json` (plugin registry)
- `~/.claude/plugins/blocklist.json` (blocked plugins)
- `~/.claude/skills/*/SKILL.md` (global skills)
- `.claude/settings.json` (project hooks, MCP servers)
- `.claude/skills/*/SKILL.md` (project skills)
- `.claude/agents/*.md` (project agents)
- Each plugin's install directory (bundled skills, agents, commands, hooks)

There's no single place to see it all. This plugin creates that single place.

## Current State (v1.0)

**What works today:**

- Generates `.CLAUDE.automatons.md` — a human-readable inventory with markdown tables
- Generates `.CLAUDE.automatons.json` — a machine-readable sidecar for tooling
- Generates `.CLAUDE.automatons.hash` — config hash for smart staleness detection
- All files are gitignored automatically
- Tags every item as `installed` (from marketplace), `custom` (user-created), or `blocked`
- Organizes by scope: Global → Project → Local
- SessionStart hook with three-tier staleness detection
- Validates that referenced automations exist on disk
- Detects changes between regenerations (additions/removals)
- Lightweight recommendations based on detected tech stack
- Self-documenting — the inventory includes this plugin in its own output
- Cross-platform — polyglot hook scripts work on Windows (Git Bash) and Unix

**Known limitations:**

- The SKILL.md is a prompt, not executable code — Claude interprets and executes it, so output quality depends on the model
- Plugin-bundled hooks from `hooks/hooks.json` are discovered but the plugin system's auto-loading behavior isn't documented by Anthropic, so this is based on observed behavior
- The hash check uses MD5 (fine for staleness detection, not for security)
- First run requires manual `/update-automatons` invocation — the hook only *detects* staleness, it doesn't auto-regenerate

## Future Direction

The name "claude-code-inventory" leaves room to grow beyond automations. The JSON sidecar already supports extensibility — new sections slot in without breaking the existing structure.

### Memory Files (v1.1)

Claude Code stores per-project knowledge in `~/.claude/projects/<project-slug>/memory/` as markdown files with YAML frontmatter:

```yaml
---
name: SMS/RCS Feature
description: Twilio SMS gateway on the sms branch
type: project
---
```

Memory types: `user`, `project`, `feedback`, `reference`. The inventory would list each file's name, type, and description — plus detect orphaned files (not in `MEMORY.md` index) and broken links (index references missing file).

```
## Memory Files

| File | Type | Description |
|------|------|-------------|
| user_environment.md | user | Windows/Git Bash PATH quirks |
| project_sms_feature.md | project | Twilio SMS gateway on sms branch |
| project_update_automatons.md | project | Auto-generates .CLAUDE.automatons.md |

Summary: 3 memory files (1 user, 2 project, 0 feedback, 0 reference)
```

**Complexity: Low.** Same YAML frontmatter parsing pattern already used for skills.

### Scheduled Tasks (v1.2)

Persistent scheduled tasks (created via `mcp__scheduled-tasks__create_scheduled_task`) are stored at `~/.claude/scheduled-tasks/{taskId}/SKILL.md`. Each has a taskId, description, cron expression or one-time fireAt, and enabled state.

```
## Scheduled Tasks

| Task ID | Description | Schedule | Enabled |
|---------|-------------|----------|---------|
| check-inbox | Check email for urgent items | weekdays 9am | yes |
| weekly-report | Generate project report | Fridays 5pm | no |
```

Note: `CronCreate` (the built-in tool) creates session-only ephemeral jobs — those aren't inventoried since they die with the session. Only persistent MCP-based tasks are included.

**Complexity: Low-Medium.** Blocked on confirming the file format — the directory doesn't exist until the first task is created.

### MCP Auth State (v1.1)

`~/.claude/mcp-needs-auth-cache.json` tracks which MCP servers need re-authentication. Auth tokens expire silently — the first sign of trouble is a failed tool call mid-session. The inventory would surface this proactively:

```
## MCP Auth State

| Server | Auth Needed Since |
|--------|------------------|
| Google Calendar | 2026-03-16 04:30 |
| Gmail | 2026-03-16 04:30 |
```

**Complexity: Low.** Single JSON file read with timestamp formatting.

**Caveat:** Current data suggests this file only tracks Claude.ai web app servers, not Claude Code CLI MCP servers. Needs investigation.

### Keybindings (v1.1)

Custom keyboard shortcuts in `~/.claude/keybindings.json`. The file format is currently unknown (the file doesn't exist until the first custom binding is created), so this would be a skeleton implementation — show the data if the file exists, omit the section otherwise.

```
## Keybindings

| Key | Action | Description |
|-----|--------|-------------|
| Ctrl+Shift+R | /update-automatons | Refresh automation inventory |
| Ctrl+Shift+T | run-tests | Execute test suite |
```

**Complexity: Low.** Skeleton now, flesh out when the format is known.

### Further Out

See [`docs/FUTURE.md`](docs/FUTURE.md) for detailed specs on additional planned features:
- **Cross-project comparison** — compare configs across all projects in `~/.claude/projects/`
- **Plugin health** — orphaned versions, enabled-but-not-installed, disk usage, update recency
- **Permission audit** — group patterns by tool type, detect duplicates and overly broad rules (opt-in)
- **CLAUDE.md quality** — lightweight quality score based on documented commands, architecture, gotchas
- **Session usage patterns** — aggregate tool usage, session duration, success rates (opt-in)
- **Install script** — `curl | bash` one-liner for easier adoption
- **Marketplace distribution** — publish to `claude-plugins-official`

## Example Output

Running `/update-automatons` produces inventory like this:

```markdown
# Claude Code Automation Inventory

> Auto-generated by `update-automatons` plugin — 2026-03-20
> Regenerate: `/update-automatons`

## Global Scope (~/.claude/)

### Hooks
| Event | Command | Origin | Description |
|-------|---------|--------|-------------|
| SessionStart | add-claude-gitignore.cmd | custom | Add .claude/ and CLAUDE.md to .gitignore |
| SessionStart | update-automatons.cmd | custom | Check if inventory needs regeneration |

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
| github | claude-plugins-official | installed | 6b70f99f |
| commit-and-push | local | custom | 1.0.0 |
| update-automatons | local | custom | 1.0.0 |

### Plugin-Bundled Skills
| Skill | Plugin | Description |
|-------|--------|-------------|
| brainstorming | superpowers | Explore intent and design before implementation |
| systematic-debugging | superpowers | Find root cause before attempting fixes |
| test-driven-development | superpowers | Write test first, watch it fail, write code |

## Project Scope (.claude/)

### MCP Servers
| Name | Type | Package/URL | Origin |
|------|------|-------------|--------|
| context7 | npx | @upwind-media/context7-mcp@latest | custom |
| github | npx | @modelcontextprotocol/server-github | installed |

### Skills
| Name | Origin | Description |
|------|--------|-------------|
| deploy-runpod | custom | Build, push, and deploy to RunPod |
| health-check | custom | Unified health check for all services |

### Agents
| Name | Origin | Description |
|------|--------|-------------|
| code-reviewer | custom | Reviews code for async correctness and security |

## Recommendations
| Type | Suggestion | Reason | Priority |
|------|-----------|--------|----------|
| MCP | Docker MCP server | docker-compose.yml detected | Medium |
| Agent | security-reviewer | Auth tokens in codebase | Medium |

## About This File
| Property | Value |
|----------|-------|
| Generated by | `update-automatons@local` plugin (custom) |
| Kept fresh by | SessionStart hook (config change or >24h stale) |
| Self-documenting | This plugin appears in the inventory above |
```

See [`examples/sample-output.md`](examples/sample-output.md) for a full real-world example with all sections populated.

## How It Works

The plugin has two main components: a **SessionStart hook** (bash script) that detects when the inventory is stale, and a **skill** (SKILL.md prompt) that Claude executes to generate the inventory.

### The Hook — Staleness Detection

The hook runs automatically at the start of every Claude Code session. It checks three conditions in cascade — if any triggers, it asks Claude to regenerate:

```bash
#!/usr/bin/env bash
# SessionStart hook: check if .CLAUDE.automatons.md needs regeneration
set -euo pipefail

# Only act in git repos
[ -d ".git" ] || exit 0

stale=false

# Check 1: File missing
if [ ! -f ".CLAUDE.automatons.md" ]; then
    stale=true
fi

# Check 2: File older than 24 hours
if [ "$stale" = false ] && [ -f ".CLAUDE.automatons.md" ]; then
    now=$(date +%s)
    if [ "$(uname -s)" = "Darwin" ]; then
        file_mod=$(stat -f %m ".CLAUDE.automatons.md" 2>/dev/null || echo 0)
    else
        # Linux and Git Bash on Windows
        file_mod=$(stat -c %Y ".CLAUDE.automatons.md" 2>/dev/null || echo 0)
    fi
    file_age=$(( now - file_mod ))
    [ "$file_age" -gt 86400 ] && stale=true
fi

# Check 3: Config hash changed (catches plugin installs/removals immediately)
if [ "$stale" = false ] && [ -f ".CLAUDE.automatons.hash" ]; then
    current_hash=""

    # Build hash input from key config files + directory listings
    hash_input=""
    [ -f "$HOME/.claude/settings.json" ] && hash_input+=$(cat "$HOME/.claude/settings.json" 2>/dev/null)
    [ -f "$HOME/.claude/plugins/installed_plugins.json" ] && \
        hash_input+=$(cat "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
    hash_input+=$(ls "$HOME/.claude/skills/" 2>/dev/null | sort)
    [ -f ".claude/settings.json" ] && hash_input+=$(cat ".claude/settings.json" 2>/dev/null)
    hash_input+=$(ls ".claude/skills/" 2>/dev/null | sort)

    if command -v md5sum &>/dev/null; then
        current_hash=$(printf '%s' "$hash_input" | md5sum | cut -d' ' -f1)
    elif command -v md5 &>/dev/null; then
        current_hash=$(printf '%s' "$hash_input" | md5 -q)
    fi

    if [ -n "$current_hash" ]; then
        stored_hash=$(cat ".CLAUDE.automatons.hash" 2>/dev/null || echo "")
        [ "$current_hash" != "$stored_hash" ] && stale=true
    fi
fi

if $stale; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n'
    printf '    "additionalContext": "Automation inventory (.CLAUDE.automatons.md) is missing,'
    printf ' stale, or configs have changed. Run /update-automatons to regenerate."\n'
    printf '  }\n}\n'
fi

exit 0
```

**Key design choice:** The hook doesn't regenerate the inventory itself — it only outputs a JSON message that Claude sees at session start. Claude then decides whether to run the skill. This keeps the hook lightweight (pure bash, no Claude invocation) and lets the user control when regeneration happens.

### The Polyglot Wrapper

A single `.cmd` file that runs on both Windows and Unix:

```cmd
: << 'CMDBLOCK'
@echo off
"%ProgramFiles%\Git\bin\bash.exe" "%~dp0update-automatons.sh" %*
exit /b %ERRORLEVEL%
CMDBLOCK
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${SCRIPT_DIR}/update-automatons.sh" "$@"
```

Windows batch sees `@echo off` and launches Git Bash. Unix bash treats the batch block as a heredoc (ignored) and runs the script directly.

### The Skill — 7-Phase Generation

The core logic lives in [`skills/update-automatons/SKILL.md`](skills/update-automatons/SKILL.md) — a structured prompt that Claude executes phase by phase:

| Phase | What It Does | Tools Used |
|-------|-------------|------------|
| **1. Discovery** | Read all config files in parallel | Read, Glob |
| **2. Classification** | Tag each item as installed/custom/blocked | — (logic) |
| **3. Validation** | Check referenced files exist on disk | Bash, Read |
| **4. Change Detection** | Diff against previous `.CLAUDE.automatons.json` | Read |
| **5. Recommendations** | Gap analysis from `pyproject.toml`/`package.json` | Read |
| **6. Generation** | Write `.md`, `.json`, `.hash` files | Write |
| **7. Gitignore** | Append entries if missing | Grep, Edit |

The skill is ~350 lines of structured instructions with explicit file paths, classification rules, output templates, and edge case handling. See the [full source](skills/update-automatons/SKILL.md).

### Plugin Metadata

```json
{
  "name": "update-automatons",
  "description": "Auto-generates .CLAUDE.automatons.md — a comprehensive inventory of all Claude Code automations (hooks, skills, plugins, agents, MCP servers) ordered by scope and tagged as installed or custom.",
  "version": "1.0.0",
  "category": "documentation",
  "source": {
    "source": "local"
  }
}
```

### Hook Registration

The plugin bundles its own hook via `hooks/hooks.json` — the plugin system loads this automatically when the plugin is enabled:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/plugins/cache/local/update-automatons/1.0.0/hooks/update-automatons.cmd"
          }
        ]
      }
    ]
  }
}
```

## Plugin Structure

```
update-automatons/1.0.0/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata (name, version, category)
├── commands/
│   └── update-automatons.md     # /update-automatons slash command entry point
├── skills/
│   └── update-automatons/
│       └── SKILL.md             # 7-phase generation instructions (~350 lines)
└── hooks/
    ├── hooks.json               # SessionStart hook registration
    ├── update-automatons.sh     # Bash staleness detection (56 lines)
    └── update-automatons.cmd    # Polyglot Windows+Unix wrapper (7 lines)
```

**Total: 6 files, ~430 lines.**

## Installation

### Quick Install (Local Plugin)

1. Copy the plugin files to your local plugin cache:

```bash
mkdir -p ~/.claude/plugins/cache/local/update-automatons/1.0.0
cp -r .claude-plugin commands skills hooks \
  ~/.claude/plugins/cache/local/update-automatons/1.0.0/
```

2. Register in your global settings — add to `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "update-automatons@local": true
  }
}
```

3. Start a new Claude Code session. The SessionStart hook will detect the missing inventory and prompt you to run `/update-automatons`.

### Minimal Install (Skill Only)

Copy just the skill if you don't need the hook or slash command:

```bash
mkdir -p ~/.claude/skills/update-automatons
cp skills/update-automatons/SKILL.md ~/.claude/skills/update-automatons/
```

You'll need to tell Claude to "run the update-automatons skill" manually.

## Design Decisions

### Why a Plugin Instead of a Bare Skill?

| Feature | Bare Skill | Plugin |
|---------|-----------|--------|
| Slash command (`/update-automatons`) | No | Yes |
| Bundled SessionStart hook | No (manual settings.json edit) | Yes (auto-loaded) |
| Clean enable/disable | Delete the file | Toggle in `enabledPlugins` |
| Files | 1 | 6 |

### Why Three Output Files?

| File | Audience | Purpose |
|------|----------|---------|
| `.CLAUDE.automatons.md` | Humans | Read, scan, understand at a glance |
| `.CLAUDE.automatons.json` | Tools | Programmatic access, diffing, cross-project comparison |
| `.CLAUDE.automatons.hash` | Hook script | Fast staleness detection without re-scanning |

### Why Config Hash Instead of Just Time-Based?

Time-based staleness (24h) misses the most important case: **you just installed a plugin**. The hash concatenates `settings.json` + `installed_plugins.json` + skill directory listings and MD5s the result. Any config change triggers regeneration immediately, even if the inventory was generated seconds ago.

### Why Self-Documenting?

A tool that inventories automations but doesn't list itself is a blind spot. The generated output includes this plugin's skill, command, and hook in the appropriate tables. If someone reads the file and wonders "how was this made?", the answer is in the file itself.

## Configuration Sources

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

## License

MIT
