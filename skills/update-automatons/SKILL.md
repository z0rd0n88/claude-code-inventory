---
name: update-automatons
description: >
  Generate or update .CLAUDE.automatons.md — a comprehensive inventory of all
  Claude Code automations (hooks, skills, plugins, agents, MCP servers) ordered
  by scope, with each item tagged as installed or custom. Use when the user says
  "update automatons", "list my automations", "what skills/hooks do I have",
  "refresh automation inventory", or when the SessionStart hook reports the
  inventory is missing or stale. Also run after /claude-code-setup:claude-automation-recommender
  to capture new recommendations.
---

# Update Automatons — Automation Inventory Generator

Generates `.CLAUDE.automatons.md` in the current project root: a comprehensive,
human-readable inventory of every Claude Code automation active for this project,
organized by scope and tagged as **installed** (from a plugin/marketplace) or
**custom** (user-created). Also produces a `.CLAUDE.automatons.json` sidecar.

## When to Run

- SessionStart hook reports inventory is missing, stale (>24h), or configs changed
- User invokes `/update-automatons`
- After running `/claude-code-setup:claude-automation-recommender`
- After installing, removing, or updating plugins, skills, or MCP servers

---

## Phase 1 — Discovery

Read these files **in parallel** using the Read tool. If a file doesn't exist, skip it gracefully.

### Global scope (`~/.claude/`)

| Source file | Extract |
|-------------|---------|
| `~/.claude/settings.json` | `hooks` (all events), `enabledPlugins` (all keys), `effortLevel` |
| `~/.claude/plugins/installed_plugins.json` | Plugin names, versions, install dates, scope |
| `~/.claude/plugins/blocklist.json` | Blocked plugin names and reasons |
| `~/.claude/skills/*/SKILL.md` | Each skill's `name` and `description` from YAML frontmatter |

### Project scope (`.claude/` in project root)

| Source file | Extract |
|-------------|---------|
| `.claude/settings.json` | `hooks` (all events + matchers), `mcpServers` (all entries) |
| `.claude/skills/*/SKILL.md` | Each skill's `name` and `description` from YAML frontmatter |
| `.claude/agents/*.md` | Each agent's `name` and `description` from YAML frontmatter |

### Local scope

| Source file | Extract |
|-------------|---------|
| `.claude/settings.local.json` | Count of `permissions.allow` entries only (do NOT list individual entries) |

### Plugin-bundled content

For each plugin listed in `enabledPlugins`, look up its install path from `installed_plugins.json`.
For local plugins, the path is `~/.claude/plugins/cache/local/<name>/<version>/`.

Scan each plugin's install directory for:
- `skills/*/SKILL.md` — bundled skills (read name + description from frontmatter)
- `agents/*.md` — bundled agents (read name + description from frontmatter)
- `commands/*.md` — bundled slash commands (read description from frontmatter)
- `hooks/hooks.json` — bundled hooks (read event types and commands)

If a plugin's install path doesn't exist on disk, record a validation warning.

---

## Phase 2 — Classification

Tag every discovered item as `installed`, `custom`, or `blocked`:

| Rule | Tag |
|------|-----|
| Plugin key ends with `@claude-plugins-official` (or any non-local marketplace) | `installed` |
| Plugin key ends with `@local` | `custom` |
| Skill/agent/command/hook bundled inside a plugin's install directory | inherit plugin's tag |
| Skill in `~/.claude/skills/` (global, outside plugins/) | `custom` |
| Skill in `.claude/skills/` (project) | `custom` |
| Agent in `.claude/agents/` (project) | `custom` |
| Hook defined in user's `settings.json` (global or project, not from a plugin) | `custom` |
| MCP server in project `.claude/settings.json` | `custom` by default |
| MCP server known to come from a plugin (e.g., `github` from `github@claude-plugins-official`) | `installed` |
| Plugin listed in `~/.claude/plugins/blocklist.json` | `blocked` |

---

## Phase 3 — Validation

Check that every referenced automation actually exists on disk. Collect warnings:

| Check | Method | Warning format |
|-------|--------|---------------|
| Hook scripts exist | Use Bash: `[ -f "<path>" ]` for each hook command path | `[!] Hook script not found: <path>` |
| Skill SKILL.md exists | Confirm each discovered SKILL.md was readable | `[!] Skill file missing: <path>` |
| Plugin not orphaned | Check for `.orphaned_at` file in plugin install dir | `[!] Plugin orphaned since <date>` |
| Plugin dir exists | Verify install path from installed_plugins.json exists | `[!] Plugin directory not found: <path>` |
| MCP command available | Use Bash: `command -v <cmd>` for npx/node/etc. | `[!] MCP command not available: <cmd>` |

Include all warnings in the Validation section of the output. If no warnings, omit the section.

---

## Phase 4 — Change Detection

If `.CLAUDE.automatons.json` already exists from a previous generation:

1. Read the existing JSON file
2. Build a set of `{name}:{scope}:{type}` keys from the old data
3. Build the same set from the newly discovered data
4. Items in new but not old → "Added"
5. Items in old but not new → "Removed"
6. Include a "Recent Changes" section at the top of the markdown

If no previous `.CLAUDE.automatons.json` exists (first run), skip this phase entirely.

---

## Phase 5 — Recommendations

Lightweight gap analysis (do NOT invoke the full claude-automation-recommender):

1. Read `pyproject.toml` or `package.json` in the project root to detect the tech stack
2. Look at what is already configured (MCP servers, hooks, skills, agents)
3. Identify 3-5 useful automations that are NOT yet set up. Consider:
   - Docker MCP server if `docker-compose.yml` or `Dockerfile` exists
   - Test watcher hook if test files exist but no auto-test hook
   - Security review agent if auth/token handling code exists
   - Release notes skill if git-based deployment is configured
   - Notification hook for long-running operations
4. Format as a table: Type, Suggestion, Reason, Priority (Low/Medium/High)

Always include: "Run `/claude-code-setup:claude-automation-recommender` for a comprehensive analysis."

---

## Phase 6 — Generate Output

### 6a. Write `.CLAUDE.automatons.md`

Write the inventory to the project root. Use this template structure, replacing
all `{placeholders}` with actual discovered data. Use the current date for the timestamp.

**CRITICAL:** Include the `update-automatons@local` plugin itself — its skill, command,
and SessionStart hook — in the appropriate sections. This file must document the
system that generates it.

```markdown
# Claude Code Automation Inventory

> Auto-generated by `update-automatons` plugin — {YYYY-MM-DD}
> Regenerate: `/update-automatons`

---

## Recent Changes

(Include only if Phase 4 detected changes. Otherwise omit this entire section.)

| Change | Item | Type | Scope | Date |
|--------|------|------|-------|------|
| + Added | {name} | {type} | {scope} | {date} |
| - Removed | {name} | {type} | {scope} | {date} |

---

## Global Scope (`~/.claude/`)

### Hooks

| Event | Command | Origin | Description |
|-------|---------|--------|-------------|
| {event} | {script basename} | {custom/installed} | {what it does} |

### Skills

| Name | Origin | Description |
|------|--------|-------------|
| {name} | {custom/installed} | {description from frontmatter} |

### Plugins

| Plugin | Source | Origin | Version | Installed |
|--------|--------|--------|---------|-----------|
| {name} | {marketplace or "local"} | {installed/custom} | {version} | {date} |

### Plugin-Bundled Skills

| Skill | Plugin | Description |
|-------|--------|-------------|
| {skill name} | {plugin name} | {description from frontmatter} |

### Plugin-Bundled Agents

| Agent | Plugin | Description |
|-------|--------|-------------|
| {agent name} | {plugin name} | {description from frontmatter} |

### Plugin-Bundled Commands

| Command | Plugin | Description |
|---------|--------|-------------|
| {command name} | {plugin name} | {description from frontmatter} |

### Blocked Plugins

(Include only if blocklist.json has entries. Otherwise omit.)

| Plugin | Reason |
|--------|--------|
| {name} | {reason} |

### Settings

- effortLevel: {value}

---

## Project Scope (`.claude/`)

### Hooks

| Event | Matcher | Action | Origin |
|-------|---------|--------|--------|
| {event} | {matcher or "—"} | {what it does} | {custom/installed} |

### MCP Servers

| Name | Type | Package/URL | Origin |
|------|------|-------------|--------|
| {name} | {npx/http/stdio} | {package or url} | {custom/installed} |

### Skills

| Name | Origin | Description |
|------|--------|-------------|
| {name} | {custom/installed} | {description from frontmatter} |

### Agents

| Name | Origin | Description |
|------|--------|-------------|
| {name} | {custom/installed} | {description from frontmatter} |

---

## Local Scope (`.claude/settings.local.json`)

- Permissions: {count} allowlisted entries (user-specific, not listed)

---

## Validation

(Include only if Phase 3 found warnings. Otherwise omit.)

| Warning | Item | Details |
|---------|------|---------|
| [!] | {name} | {message} |

---

## Recommendations

> Run `/claude-code-setup:claude-automation-recommender` for a comprehensive analysis

| Type | Suggestion | Reason | Priority |
|------|-----------|--------|----------|
| {type} | {name} | {one-line reason} | {Low/Medium/High} |

---

## About This File

| Property | Value |
|----------|-------|
| Generated by | `update-automatons@local` plugin (custom) |
| Kept fresh by | SessionStart hook (regenerates on config change or >24h stale) |
| Gitignored | Yes — `.CLAUDE.automatons.md`, `.CLAUDE.automatons.json`, `.CLAUDE.automatons.hash` |
| JSON sidecar | `.CLAUDE.automatons.json` (machine-readable) |
| Self-documenting | This plugin, its skill, command, and hook appear in the inventory above |
```

### 6b. Write `.CLAUDE.automatons.json`

Write a machine-readable JSON sidecar to the project root with this structure:

```json
{
  "generated": "ISO-8601 timestamp",
  "generator": "update-automatons@local",
  "scopes": {
    "global": {
      "hooks": [
        { "event": "...", "command": "...", "origin": "custom|installed", "description": "..." }
      ],
      "skills": [
        { "name": "...", "origin": "custom|installed", "description": "..." }
      ],
      "plugins": [
        { "name": "...", "source": "...", "origin": "installed|custom", "version": "...", "installedAt": "..." }
      ],
      "pluginSkills": [
        { "name": "...", "plugin": "...", "description": "..." }
      ],
      "pluginAgents": [
        { "name": "...", "plugin": "...", "description": "..." }
      ],
      "pluginCommands": [
        { "name": "...", "plugin": "...", "description": "..." }
      ],
      "blockedPlugins": [
        { "name": "...", "reason": "..." }
      ],
      "settings": { "effortLevel": "..." }
    },
    "project": {
      "hooks": [
        { "event": "...", "matcher": "...", "action": "...", "origin": "custom|installed" }
      ],
      "mcpServers": [
        { "name": "...", "type": "...", "package": "...", "origin": "custom|installed" }
      ],
      "skills": [
        { "name": "...", "origin": "custom|installed", "description": "..." }
      ],
      "agents": [
        { "name": "...", "origin": "custom|installed", "description": "..." }
      ]
    },
    "local": {
      "permissionCount": 0
    }
  },
  "validation": [
    { "level": "warning", "item": "...", "message": "..." }
  ],
  "recommendations": [
    { "type": "...", "name": "...", "reason": "...", "priority": "Low|Medium|High" }
  ]
}
```

### 6c. Write `.CLAUDE.automatons.hash`

Compute an MD5 hash of the concatenation of all scanned config file contents plus
directory listings (skills dirs). Write just the hash string to `.CLAUDE.automatons.hash`.

Use Bash:
```bash
hash_input=$(cat ~/.claude/settings.json ~/.claude/plugins/installed_plugins.json .claude/settings.json 2>/dev/null; ls ~/.claude/skills/ .claude/skills/ 2>/dev/null | sort)
echo -n "$hash_input" | md5sum | cut -d' ' -f1 > .CLAUDE.automatons.hash
```

---

## Phase 7 — Gitignore

Idempotent check — only append if not already present:

```bash
grep -qF '.CLAUDE.automatons' .gitignore 2>/dev/null
```

If not found, append:

```gitignore

# Automation inventory (auto-generated by update-automatons plugin)
.CLAUDE.automatons.md
.CLAUDE.automatons.json
.CLAUDE.automatons.hash
```

---

## Edge Cases

- **Not a git repo:** Still generate the inventory files. Skip the gitignore step.
- **No project `.claude/` directory:** Show "No project-level automations configured" under Project Scope.
- **No `settings.local.json`:** Show "No local overrides" under Local Scope.
- **Plugin install path missing:** Record `[!] Plugin directory not found` in Validation.
- **Plugin has `.orphaned_at`:** Record `[!] Plugin orphaned since <date>` in Validation.
- **Empty blocklist:** Omit the Blocked Plugins section entirely.
- **No previous `.CLAUDE.automatons.json` (first run):** Skip change detection, omit Recent Changes.
- **No `pyproject.toml` or `package.json`:** Omit Recommendations or provide generic suggestions.
- **Skill frontmatter missing `description`:** Use the skill directory name as fallback.
