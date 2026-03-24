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
| `~/.claude/mcp-needs-auth-cache.json` | MCP servers needing re-auth: keys = server display names, values = `{ "timestamp": <unix_ms> }`. If file missing, skip gracefully. |
| `~/.claude/keybindings.json` | Custom keyboard shortcuts. File format TBD — if file exists, read as JSON and display key-action pairs. If file missing, skip gracefully. |

### Project scope (`.claude/` in project root)

| Source file | Extract |
|-------------|---------|
| `.claude/settings.json` | `hooks` (all events + matchers), `mcpServers` (all entries) |
| `.claude/skills/*/SKILL.md` | Each skill's `name` and `description` from YAML frontmatter |
| `.claude/agents/*.md` | Each agent's `name` and `description` from YAML frontmatter |
| `CLAUDE.md` (project root) | Project instructions file. Read contents for quality scoring: check for dev commands, architecture, gotchas, environment setup, conventions, deployment, key file paths, and line count. |

### Local scope

| Source file | Extract |
|-------------|---------|
| `.claude/settings.local.json` | Count of `permissions.allow` entries only (do NOT list individual entries) |

### Plugin-bundled content

**This step is critical and must always run, even if the project has no `.claude/` directory.**
Plugin-bundled content is global — it comes from `~/.claude/plugins/`, not from the project.

For each plugin listed in `enabledPlugins`, look up its install path from `installed_plugins.json`.
For local plugins, the path is `~/.claude/plugins/cache/local/<name>/<version>/`.

Scan each plugin's install directory for:
- `skills/*/SKILL.md` — bundled skills (read name + description from frontmatter)
- `agents/*.md` — bundled agents (read name + description from frontmatter)
- `commands/*.md` — bundled slash commands (read description from frontmatter)
- `hooks/hooks.json` — bundled hooks (read event types and commands). These hooks
  are loaded automatically by the plugin system and should appear in the Global Hooks
  table alongside user-defined hooks from `settings.json`.
- `.orphaned_at` — if this file exists, note the plugin as orphaned (record the
  timestamp from the file content for the Status column)

If a plugin's install path doesn't exist on disk, record a validation warning and
mark the plugin as MISSING in the Plugins table.

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

| Plugin | Source | Origin | Version | Status |
|--------|--------|--------|---------|--------|
| {name} | {marketplace or "local"} | {installed/custom} | {version} | {active / ORPHANED / MISSING} |

For the Status column:
- **active** — plugin directory exists and is not orphaned
- **ORPHANED** — plugin has a `.orphaned_at` marker file in its install directory
- **MISSING** — plugin is in `enabledPlugins` but has no entry in `installed_plugins.json` or no directory on disk

This makes orphaned/missing plugins visible at a glance in the table itself, not buried in a separate Validation section.

### Plugin-Bundled Skills

Group skills by plugin for readability. Within each plugin group, list skills alphabetically.

| Skill | Plugin | Description |
|-------|--------|-------------|
| — | **{plugin name}** | — |
| {skill name} | | {description from frontmatter} |

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

## MCP Auth State

(Include only if `~/.claude/mcp-needs-auth-cache.json` exists and has entries. Otherwise omit this entire section.)

| Server | Auth Needed Since |
|--------|------------------|
| {server display name, strip "claude.ai " prefix if present} | {convert unix ms timestamp to YYYY-MM-DD HH:MM local time} |

---

## Keybindings

(Include only if `~/.claude/keybindings.json` exists and is valid JSON with entries. Otherwise omit this entire section.)

Display the keybindings as a table. The exact columns depend on the file format — at minimum show:

| Key | Action |
|-----|--------|
| {key combination} | {bound action or command} |

If the file format contains additional fields (description, context, etc.), include those as extra columns.

---

## CLAUDE.md Quality

(Include only if `CLAUDE.md` exists in the project root. Otherwise omit this entire section.)

Score the project's CLAUDE.md against these criteria by scanning for section headings containing relevant keywords (case-insensitive):

- **Dev commands**: headings with "commands", "scripts", "dev commands", "build", "run"
- **Architecture**: headings with "architecture", "structure", "overview", "design"
- **Gotchas**: headings with "gotchas", "known issues", "caveats", "warnings", "pitfalls"
- **Environment setup**: headings with "environment", "setup", "prerequisites", "requirements", "installation"
- **Conventions**: headings with "conventions", "style", "coding standards", "formatting", "naming"
- **Deployment**: headings with "deploy", "deployment", "release", "production" — mark "not applicable" if project has no deployment
- **Key file paths**: look for backtick-wrapped file paths (e.g., `src/`, `lib/`, `skills/`)
- **Length**: count lines — ≤200 = good, 201-400 = long, >400 = excessive

| Criterion | Status |
|-----------|--------|
| Dev commands | {present (N commands) / missing} |
| Architecture | {present / missing} |
| Gotchas | {present (N items) / missing} |
| Environment setup | {present / missing} |
| Conventions | {present / missing} |
| Deployment | {present / not applicable / missing} |
| Key file paths | {present / partial / missing} |
| Length | {N lines (good/long/excessive)} |

Score: {N}/8 criteria met

If `claude-md-management` plugin is installed (check `enabledPlugins`), append: "Run `/claude-md-management:claude-md-improver` for detailed CLAUDE.md analysis and improvements."

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
  "mcpAuthState": [
    {
      "server": "Google Calendar",
      "needsAuthSince": "2026-03-16T04:30:15.584Z"
    }
  ],
  "keybindings": [],
  "claudeMdQuality": {
    "exists": true,
    "lineCount": 85,
    "score": 8,
    "maxScore": 8,
    "criteria": {
      "devCommands": true,
      "architecture": true,
      "gotchas": true,
      "environment": true,
      "conventions": true,
      "deployment": "not_applicable",
      "keyPaths": "partial",
      "length": "good"
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

Compute a hash of the key config files for staleness detection. Try the Bash approach
first — if Bash is unavailable or fails, fall back to a Python one-liner, and if that
also fails, write a timestamp-based fallback. The hash does NOT need to be
cryptographically secure — it just needs to change when configs change.

**Approach 1 — Bash (preferred):**
```bash
hash_input=$(cat ~/.claude/settings.json ~/.claude/plugins/installed_plugins.json .claude/settings.json 2>/dev/null; ls ~/.claude/skills/ .claude/skills/ 2>/dev/null | sort)
printf '%s' "$hash_input" | md5sum | cut -d' ' -f1
```

**Approach 2 — Python fallback (if Bash fails or is restricted):**
```python
import hashlib, os, json
files = [os.path.expanduser("~/.claude/settings.json"), os.path.expanduser("~/.claude/plugins/installed_plugins.json"), ".claude/settings.json"]
data = ""
for f in files:
    try: data += open(f).read()
    except: pass
for d in [os.path.expanduser("~/.claude/skills"), ".claude/skills"]:
    try: data += "\n".join(sorted(os.listdir(d)))
    except: pass
print(hashlib.md5(data.encode()).hexdigest())
```

**Approach 3 — Timestamp fallback (last resort):**
If neither Bash nor Python can compute a hash, write the current ISO-8601 timestamp
instead. This means the hook will always see a "changed" hash and prompt regeneration,
which is the safe default.

Write the resulting hash string (or timestamp) to `.CLAUDE.automatons.hash`.

**IMPORTANT:** Verify the hash is not the MD5 of an empty string (`d41d8cd98f00b204e9800998ecf8427e`
or `e3b0c44298fc1c149afbf4c8996fb924` for SHA-256). If it is, the computation failed —
fall back to the next approach.

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
