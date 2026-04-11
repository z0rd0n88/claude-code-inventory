# Inventory Plugin v1.2 - v2.1 Design Spec

> Theme-based release plan for the claude-code-inventory plugin.
> Covers 12 features across 3 releases, plus cross-cutting JSON schema versioning.
> Implements GitHub issue #3 (global standalone + cross-project comparison) in v2.0.

---

## Release Overview

| Release | Theme | Features | Focus |
|---------|-------|----------|-------|
| **v1.2** "Deep Scan" | Richer per-project data | 5 features | Enrich existing inventory without architectural change |
| **v2.0** "Global View" | Global standalone + cross-project | 4 features | Break free of project directory; implement issue #3 |
| **v2.1** "Capabilities" | New Claude Code primitives | 3 features | Track Tool Search, Monitor, sandbox |

---

## v1.2 "Deep Scan" -- Richer Per-Project Inventory

No architectural changes. More Discovery sources, more output sections, smarter validation. The 7-phase structure stays identical.

### Feature 1: Memory Files

**What:** Index files in `~/.claude/projects/<project-slug>/memory/`, showing name, type, description from YAML frontmatter. Detect orphaned files and broken links.

**Discovery sources:**
- `~/.claude/projects/<slug>/memory/MEMORY.md` -- index file with markdown links
- `~/.claude/projects/<slug>/memory/*.md` -- individual memory files with YAML frontmatter

The project slug is derived from the current project path using Claude Code's mangling convention: `C:\Users\sneak\Documents\Foo` becomes `C--Users-sneak-Documents-Foo`. Worktree directories get their own slugs.

**Classification:** All memory files are `custom` (user-created).

**Validation rules:**
- Orphan detection: file exists in `memory/` but not referenced in `MEMORY.md` index
- Broken link detection: `MEMORY.md` references a file that doesn't exist on disk

**Output section** (placed after Local Scope):

```markdown
## Memory Files

| File | Type | Description |
|------|------|-------------|
| user_environment.md | user | Shell and tool PATH quirks |
| project_sms_feature.md | project | Twilio SMS gateway on sms branch |

Summary: 2 memory files (1 user, 1 project, 0 feedback, 0 reference)
```

**JSON sidecar addition:**

```json
{
  "memory": {
    "files": [
      { "filename": "user_environment.md", "type": "user", "name": "...", "description": "..." }
    ],
    "summary": { "total": 2, "user": 1, "project": 1, "feedback": 0, "reference": 0 },
    "orphaned": [],
    "brokenLinks": []
  }
}
```

**Complexity:** Low. Same YAML frontmatter parsing pattern already used for skills.

**Effort:** 8-10 hours.

---

### Feature 2: Scheduled Tasks

**What:** List persistent scheduled tasks from `~/.claude/scheduled-tasks/{taskId}/`. Show task ID, description, cron/fireAt schedule, enabled state.

**Discovery sources:**
- `~/.claude/scheduled-tasks/*/` -- each subdirectory is a task
- Task definition file within each subdirectory (format TBD -- needs one real task created to confirm the actual file structure)

If `~/.claude/scheduled-tasks/` does not exist, skip the section entirely.

**Important distinction:** `CronCreate` (built-in tool) creates session-only ephemeral jobs that die with the session. Only persistent MCP-based tasks (from `mcp__scheduled-tasks__create_scheduled_task`) are inventoried.

**Output section:**

```markdown
## Scheduled Tasks

| Task ID | Description | Schedule | Enabled |
|---------|-------------|----------|---------|
| check-inbox | Check email for urgent items | 0 9 * * 1-5 (weekdays 9am) | yes |
| weekly-report | Generate project report | 0 17 * * 5 (Fridays 5pm) | no |
```

**JSON sidecar addition:**

```json
{
  "scheduledTasks": [
    {
      "taskId": "check-inbox",
      "description": "Check email for urgent items",
      "cronExpression": "0 9 * * 1-5",
      "fireAt": null,
      "enabled": true,
      "source": "local"
    }
  ]
}
```

**Complexity:** Low-Medium. Blocked on confirming the file format by creating a real task.

**Effort:** 6-8 hours.

---

### Feature 3: Plugin Health

**What:** Deeper analysis beyond simple listing: orphaned versions, enabled-but-not-installed detection, disk usage of orphaned versions, update recency.

**Discovery sources:**
- `~/.claude/plugins/installed_plugins.json` -- active versions, install paths, lastUpdated
- `~/.claude/plugins/cache/<marketplace>/<plugin>/` -- all cached versions on disk
- `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.orphaned_at` -- orphan markers
- `~/.claude/settings.json` -> `enabledPlugins` -- what's actually enabled

**Cross-reference logic:**
1. For each entry in `enabledPlugins`, check if it exists in `installed_plugins.json`. If not: "enabled but not installed."
2. For each plugin in the cache directory, scan for `.orphaned_at` files. If found: record as orphaned with timestamp.
3. Calculate disk usage of orphaned version directories via `du -sh`.
4. Check `lastUpdated` field -- flag plugins not updated in 30+ days.

**Output section:**

```markdown
## Plugin Health

### Orphaned Versions (cleanup candidates)

| Plugin | Orphaned Versions | Disk Usage |
|--------|-------------------|------------|
| github | 3 old versions | 4.2 MB |
| superpowers | 2 old versions | 12.1 MB |

Total reclaimable: ~32 MB

### Potential Issues

| Issue | Plugin | Details |
|-------|--------|---------|
| Enabled but not installed | railway | In enabledPlugins but not in installed_plugins.json |
| Not updated in 30+ days | claude-code-setup | Last updated 2026-03-15 |
```

**JSON sidecar addition:**

```json
{
  "pluginHealth": {
    "orphanedVersions": [
      { "plugin": "github", "marketplace": "claude-plugins-official", "versions": ["78497c524da3"], "diskUsageMB": 4.2 }
    ],
    "enabledButNotInstalled": ["railway@claude-plugins-official"],
    "stalePlugins": [
      { "plugin": "claude-code-setup", "lastUpdated": "2026-03-15T14:27:30.313Z", "daysSinceUpdate": 27 }
    ],
    "totalReclaimableMB": 32.0
  }
}
```

**Complexity:** Medium.

**Effort:** 10-12 hours.

---

### Feature 4: CLAUDE.md Hierarchy Chain (NEW)

**What:** Map the full chain of CLAUDE.md files that Claude Code loads for the current project: the user's global `~/.claude/CLAUDE.md`, the project root `CLAUDE.md`, and any subdirectory CLAUDE.md files.

**Discovery sources:**
- `~/.claude/CLAUDE.md` -- global user instructions
- `./CLAUDE.md` -- project root instructions (already read for quality scoring)
- Glob `**/CLAUDE.md` in project root, max 3 levels deep (avoids pathological repos with hundreds of nested CLAUDE.md files in node_modules, etc.)

**Output:** Extends the existing "CLAUDE.md Quality" section with a hierarchy table:

```markdown
## CLAUDE.md Quality

### Hierarchy

| Path | Lines | Scope |
|------|-------|-------|
| ~/.claude/CLAUDE.md | 12 | global |
| ./CLAUDE.md | 85 | project root |
| ./packages/api/CLAUDE.md | 24 | subdirectory |

### Quality Score (project root)

| Criterion | Status |
|-----------|--------|
| Dev commands | present (5 commands) |
| ... | ... |

Score: 7/8 criteria met
```

Quality scoring stays on the project-root file only. Subdirectory and global files are listed with line counts but not scored.

**JSON sidecar addition:**

```json
{
  "claudeMdHierarchy": [
    { "path": "~/.claude/CLAUDE.md", "lines": 12, "scope": "global" },
    { "path": "./CLAUDE.md", "lines": 85, "scope": "project_root" },
    { "path": "./packages/api/CLAUDE.md", "lines": 24, "scope": "subdirectory" }
  ]
}
```

**Complexity:** Low.

**Effort:** 3-4 hours.

---

### Feature 5: Hook Execution Order (NEW)

**What:** When multiple hooks fire on the same event, execution order matters. The inventory shows hooks grouped by event with explicit sequence numbers reflecting actual load order.

**Execution order logic:**
1. Global hooks from `~/.claude/settings.json` (array order)
2. Plugin-bundled hooks from each enabled plugin's `hooks/hooks.json` (plugin registration order from `enabledPlugins`)
3. Project hooks from `.claude/settings.json` (array order)

**Output:** Enhances existing Hooks tables with a sequence number column:

```markdown
### Hooks (by execution order)

| # | Event | Command | Origin | Source |
|---|-------|---------|--------|--------|
| 1 | SessionStart | add-claude-gitignore.cmd | custom | global settings |
| 2 | SessionStart | inventory.cmd | installed | inventory plugin |
| 3 | SessionStart | superpowers-hook.sh | installed | superpowers plugin |
| 1 | PreToolUse | lint-check.sh | custom | project settings |
```

Sequence numbers reset per event.

**JSON sidecar change:** Add `"order"` field to each hook entry in the existing `hooks` arrays:

```json
{ "event": "SessionStart", "command": "inventory.cmd", "origin": "installed", "source": "inventory plugin", "order": 2 }
```

**Complexity:** Low. Data is already collected; this is a presentation change plus ordering logic.

**Effort:** 3-4 hours.

---

### v1.2 Hash Update

The staleness hash computation must be updated to include:
- `~/.claude/projects/<slug>/memory/` directory listing
- `~/.claude/scheduled-tasks/` directory listing
- Plugin cache `.orphaned_at` file presence

This ensures the SessionStart hook detects changes to memory files, scheduled tasks, and plugin health without waiting for the 24-hour age threshold.

---

## v2.0 "Global View" -- Global Standalone + Cross-Project

The architectural leap. The inventory operates at the user's entire Claude Code installation level, not just within a project. Directly implements issue #3.

### Feature 6: Global Standalone Skill

**What:** A mode that generates `~/.claude/.CLAUDE.inventory.md` covering only global-scope config. Works from any directory without project context.

**Entry point:** New slash command `/inventory-global` (separate from `/inventory`).

Rationale for a separate command rather than a flag:
- Different output path (`~/.claude/` vs project root)
- Different staleness hook (global settings, not project-level)
- Can run without any project open
- Cleaner UX -- no ambiguity about what gets generated

**Discovery sources (global only):**
- `~/.claude/settings.json` -- hooks, enabledPlugins, effortLevel
- `~/.claude/plugins/installed_plugins.json` -- plugin registry
- `~/.claude/plugins/blocklist.json` -- blocked plugins
- `~/.claude/skills/*/SKILL.md` -- global skills
- `~/.claude/keybindings.json` -- custom keybindings
- `~/.claude/mcp-needs-auth-cache.json` -- MCP auth state
- `~/.claude/scheduled-tasks/` -- scheduled tasks (from v1.2)
- `~/.claude/CLAUDE.md` -- global instructions file
- `~/.claude/plugins/marketplaces/` -- configured marketplaces
- Plugin-bundled content (skills, agents, commands, hooks) -- same as current

**Explicitly skipped:** All project-scope reads (`.claude/settings.json`, `.claude/skills/`, `.claude/agents/`, `CLAUDE.md` in project root).

**Output files:**
- `~/.claude/.CLAUDE.inventory.md` -- global-only markdown inventory
- `~/.claude/.CLAUDE.inventory.json` -- global-only JSON sidecar
- `~/.claude/.CLAUDE.inventory.hash` -- staleness hash for global config files

**Staleness hook:** A SessionStart hook registered in the user's global `~/.claude/settings.json` that checks `~/.claude/.CLAUDE.inventory.hash` against global config files only. Same three-tier logic: missing -> age (24h) -> hash mismatch.

**Skill architecture:** The existing `SKILL.md` gains a mode parameter:
- **Project mode** (default, current behavior): scans global + project + local, writes to project root
- **Global mode** (new): scans global only, writes to `~/.claude/`

The 7-phase structure stays identical. Mode affects Phase 1 (which files to discover) and Phase 6 (where to write output). A new command file `commands/inventory-global.md` invokes the skill with the global mode flag.

**Plugin files added:**
- `commands/inventory-global.md` -- slash command entry point

---

### Feature 7: Cross-Project Comparison

**What:** Aggregates config across all projects on the machine. Produces a comparison matrix.

**Entry point:** `/inventory-compare` (separate command). User-initiated only -- too expensive for SessionStart.

**Discovery algorithm:**
1. List all directories in `~/.claude/projects/`
2. Filter out worktree slugs: any slug containing `--claude-worktrees-` is excluded
3. Reverse-map each slug to a filesystem path:
   - Replace leading drive letter pattern: `C--` becomes `C:\` (Windows) or `/` (Unix)
   - Replace remaining `--` with path separator
   - This is ambiguous for paths with hyphens; verify the resolved path exists on disk before including
4. For each resolved path that exists:
   - Read `<path>/.claude/settings.json` -> count hooks and MCP servers
   - Glob `<path>/.claude/skills/*/SKILL.md` -> count skills
   - Glob `<path>/.claude/agents/*.md` -> count agents
   - Check `<path>/CLAUDE.md` exists; if so, note line count
   - Count memory files from `~/.claude/projects/<slug>/memory/`

**Performance guard:** If `~/.claude/projects/` contains more than 50 non-worktree project slugs, warn the user and cap at the 50 most recently modified (by directory mtime).

**Output location:** `~/.claude/.CLAUDE.cross-project.md` (separate file, not merged into per-project or global inventory).

**Output section:**

```markdown
# Cross-Project Comparison

> Auto-generated by `inventory` plugin -- {YYYY-MM-DD}
> Regenerate: `/inventory-compare`

## Summary

| Feature | BratBot | asciiSkill | inventory |
|---------|---------|------------|-----------|
| Hooks | 2 | 0 | 1 |
| MCP servers | 2 | 0 | 0 |
| Skills | 4 | 1 | 1 |
| Agents | 1 | 0 | 0 |
| Memory files | 5 | 2 | 3 |
| CLAUDE.md | yes (8/8) | no | yes (7/8) |

## Inconsistencies

| Issue | Projects Affected | Details |
|-------|-------------------|---------|
| No CLAUDE.md | asciiSkill | Missing project instructions |
| No hooks | asciiSkill, inventory | No automation hooks configured |
| MCP server drift | -- | (none detected) |
```

**JSON sidecar:**

```json
{
  "crossProject": {
    "generatedAt": "ISO-8601",
    "projects": [
      {
        "slug": "C--Users-sneak-Documents-BratBot",
        "path": "C:\\Users\\sneak\\Documents\\BratBot",
        "hooks": 2,
        "mcpServers": 2,
        "skills": 4,
        "agents": 1,
        "memoryFiles": 5,
        "hasClaudeMd": true,
        "claudeMdScore": 8
      }
    ],
    "inconsistencies": [
      { "issue": "No CLAUDE.md", "projects": ["asciiSkill"], "details": "Missing project instructions" }
    ]
  }
}
```

Written to `~/.claude/.CLAUDE.cross-project.json`.

**Plugin files added:**
- `commands/inventory-compare.md` -- slash command entry point

---

### Feature 8: Settings Conflict Detection (NEW)

**What:** Claude Code settings cascade across three scopes. When the same key appears at multiple scopes, the most-specific wins. The inventory surfaces these overrides.

**Scope precedence:**
1. `.claude/settings.local.json` (most specific, wins)
2. `.claude/settings.json` (project)
3. `~/.claude/settings.json` (global, least specific)

**Discovery:** Read all three files. For overlapping keys, record which scope provides the effective value.

**Scope limitation:** Only applies to project-mode inventory (needs 2+ scopes to compare). Not relevant to global-only mode.

**Output section:**

```markdown
## Settings Conflicts

| Setting | Global | Project | Local | Effective |
|---------|--------|---------|-------|-----------|
| effortLevel | high | low | -- | low (project) |
```

Omitted entirely if no conflicts exist.

**JSON sidecar addition:**

```json
{
  "settingsConflicts": [
    {
      "key": "effortLevel",
      "global": "high",
      "project": "low",
      "local": null,
      "effective": "low",
      "effectiveScope": "project"
    }
  ]
}
```

**Complexity:** Low-Medium.

**Effort:** 4-6 hours.

---

### Feature 9: Remote Triggers Inventory (NEW)

**What:** Claude Code supports remote triggers / scheduled agents that run on Anthropic's infrastructure (distinct from local scheduled tasks). The inventory lists all configured triggers.

**Discovery:**
- Primary: invoke `mcp__scheduled-tasks__list_scheduled_tasks` at generation time to query active remote triggers
- Fallback: read `~/.claude/scheduled-tasks/` filesystem if MCP server is unavailable

**Output:** Extends the "Scheduled Tasks" section (from v1.2 Feature 2) with a "Source" column:

```markdown
## Scheduled Tasks

| Task ID | Description | Schedule | Enabled | Source |
|---------|-------------|----------|---------|--------|
| check-inbox | Check email | weekdays 9am | yes | remote |
| local-lint | Lint on save | every 30min | yes | local |
```

**JSON sidecar change:** Add `"source": "local" | "remote"` to each entry in `scheduledTasks[]`.

**Complexity:** Low-Medium. Depends on MCP server availability.

**Effort:** 4-6 hours (incremental on Feature 2).

---

## v2.1 "Capabilities" -- New Claude Code Primitives

Tracks newer Claude Code features. Forward-looking -- positions the inventory as the place to understand the full Claude Code surface area.

### Feature 10: Tool Search / Deferred Tools Inventory (NEW)

**What:** Claude Code's Tool Search enables lazy-loading for MCP servers -- tools are deferred and only loaded when needed, reducing context usage by up to 95%. The inventory surfaces which tools are deferred vs always-loaded.

**Discovery:**
- Read `.claude/settings.json` -> `mcpServers` entries for tool configuration
- For each MCP server, check for `toolSearch` or deferred configuration
- At generation time, invoke `ToolSearch` with a broad query to enumerate currently deferred tools (captures live state)

**Output:** Extends "MCP Servers" table with a loading column, plus a new sub-section:

```markdown
### MCP Servers

| Name | Type | Package | Origin | Loading |
|------|------|---------|--------|---------|
| context7 | npx | @upwind-media/context7-mcp | custom | eager |
| github | npx | @modelcontextprotocol/server-github | installed | deferred (12 tools) |

### Deferred Tools

| Tool | MCP Server | Description |
|------|-----------|-------------|
| mcp__github__create_issue | github | Create a new issue |
| mcp__github__list_prs | github | List pull requests |
```

**JSON sidecar addition:**

```json
{
  "deferredTools": [
    { "tool": "mcp__github__create_issue", "server": "github", "description": "Create a new issue" }
  ]
}
```

**Complexity:** Medium. The live ToolSearch invocation adds runtime dependency.

**Effort:** 6-8 hours.

---

### Feature 11: Monitor Tool Tracking (NEW)

**What:** Claude Code's Monitor tool streams events from background scripts. The inventory detects where monitoring is configured in the project's automations.

**Discovery:**
- Grep project skills (`skills/*/SKILL.md`) for references to `Monitor` tool
- Grep hook scripts for `run_in_background` patterns
- Check `.claude/settings.json` for monitor-related configuration

This is detection-only. The inventory reports where monitoring is configured, not whether monitors are currently running.

**Output section** (only if monitoring usage is detected):

```markdown
### Background Monitoring

| Source | Type | What's Monitored |
|--------|------|-----------------|
| hooks/test-watcher.sh | hook | Test suite output (PostToolUse) |
| skills/deploy/SKILL.md | skill | Deployment log streaming |
```

**JSON sidecar addition:**

```json
{
  "monitoring": [
    { "source": "hooks/test-watcher.sh", "type": "hook", "description": "Test suite output" }
  ]
}
```

**Complexity:** Low. Pattern matching in existing files.

**Effort:** 3-4 hours.

---

### Feature 12: Sandbox Configuration (NEW)

**What:** Claude Code supports subprocess sandboxing with PID namespace isolation (Linux). The inventory reports the current sandboxing and security posture.

**Discovery:**
- `~/.claude/settings.json` -- sandbox-related keys, `dangerouslySkipPermissions` if set
- `.claude/settings.json` -- project-level overrides
- OS detection: check if PID namespace isolation is available (`uname -s` for Linux)

**Output:** Extends the existing "Settings" section:

```markdown
### Security

| Setting | Value | Scope |
|---------|-------|-------|
| Sandbox mode | enabled (PID namespace) | global |
| dangerouslySkipPermissions | false | global |
| Permission entries | 127 | local |
```

**JSON sidecar addition:**

```json
{
  "security": {
    "sandboxMode": "pid_namespace",
    "dangerouslySkipPermissions": false,
    "permissionCount": 127,
    "os": "linux"
  }
}
```

**Complexity:** Low.

**Effort:** 2-3 hours.

---

## Cross-Cutting: JSON Schema Versioning

Starting with v1.2, add `"schemaVersion"` to `.CLAUDE.inventory.json`. This lets downstream tools detect which fields are available.

| Schema Version | Release | New Top-Level Keys |
|----------------|---------|-------------------|
| 1 (implicit) | v1.0-v1.1 | scopes, mcpAuthState, keybindings, claudeMdQuality, validation, recommendations |
| 2 | v1.2 | memory, scheduledTasks, pluginHealth, claudeMdHierarchy (hookOrder added to existing hooks) |
| 3 | v2.0 | crossProject, settingsConflicts (remoteTriggers merged into scheduledTasks) |
| 4 | v2.1 | deferredTools, monitoring, security |

Backward compatibility: tools reading schema version 1 files should treat missing keys as empty/null rather than erroring.

---

## Plugin File Changes by Release

### v1.2

| Change | File |
|--------|------|
| Modify | `skills/inventory/SKILL.md` -- add memory, scheduled tasks, plugin health, CLAUDE.md hierarchy, hook ordering to Phases 1-6 |
| Modify | `hooks/inventory.sh` -- update hash computation to include memory dir listing and scheduled-tasks dir listing |
| Modify | `.claude-plugin/plugin.json` -- bump version to 1.2.0 |

### v2.0

| Change | File |
|--------|------|
| Add | `commands/inventory-global.md` -- slash command for global-only mode |
| Add | `commands/inventory-compare.md` -- slash command for cross-project comparison |
| Modify | `skills/inventory/SKILL.md` -- add mode parameter (project/global), settings conflicts, remote triggers, cross-project logic |
| Modify | `.claude-plugin/plugin.json` -- bump version to 2.0.0 |

### v2.1

| Change | File |
|--------|------|
| Modify | `skills/inventory/SKILL.md` -- add deferred tools, monitor tracking, sandbox config to Phases 1-6 |
| Modify | `.claude-plugin/plugin.json` -- bump version to 2.1.0 |

---

## Acceptance Criteria

### v1.2

- [ ] Memory files section lists files with name, type, description from YAML frontmatter
- [ ] Orphaned memory files and broken MEMORY.md links detected and reported
- [ ] Scheduled tasks section shows task ID, description, schedule, enabled state
- [ ] Scheduled tasks section omitted when `~/.claude/scheduled-tasks/` doesn't exist
- [ ] Plugin health reports orphaned versions with disk usage
- [ ] Plugin health detects enabled-but-not-installed plugins
- [ ] CLAUDE.md hierarchy lists all CLAUDE.md files from global through subdirectories
- [ ] Hook tables include sequence numbers reflecting execution order
- [ ] JSON sidecar includes `schemaVersion: 2` and all new keys
- [ ] Hash computation updated to detect memory/scheduled-task/plugin-health changes
- [ ] No regressions in v1.1 functionality

### v2.0

- [ ] `/inventory-global` generates `~/.claude/.CLAUDE.inventory.md` from any working directory
- [ ] Global inventory covers: plugins, global skills, global hooks, keybindings, MCP auth state, scheduled tasks, global CLAUDE.md
- [ ] `/inventory-compare` generates cross-project comparison table
- [ ] Cross-project mode filters out worktree slugs
- [ ] Cross-project mode caps at 50 projects with warning
- [ ] Inconsistency detection flags missing CLAUDE.md, missing hooks across projects
- [ ] Settings conflict detection surfaces scope overrides with effective values
- [ ] Remote triggers appear in scheduled tasks with source=remote
- [ ] All output files written to `~/.claude/` for global/compare modes
- [ ] JSON sidecar includes `schemaVersion: 3`

### v2.1

- [ ] Deferred tools table shows which MCP tools use lazy loading
- [ ] MCP Servers table includes Loading column (eager/deferred)
- [ ] Background monitoring section detects Monitor tool usage in skills/hooks
- [ ] Security section shows sandbox mode and dangerouslySkipPermissions state
- [ ] JSON sidecar includes `schemaVersion: 4`

---

## Effort Summary

| Release | Features | Estimated Effort |
|---------|----------|-----------------|
| v1.2 | 5 (memory, scheduled tasks, plugin health, CLAUDE.md hierarchy, hook order) | 30-38 hours |
| v2.0 | 4 (global standalone, cross-project, settings conflicts, remote triggers) | 24-32 hours |
| v2.1 | 3 (deferred tools, monitor tracking, sandbox config) | 11-15 hours |
| **Total** | **12 features** | **65-85 hours** |

---

## Open Questions

1. **Scheduled task file format:** The actual YAML/frontmatter structure of `~/.claude/scheduled-tasks/{taskId}/SKILL.md` is unconfirmed. Need to create a test task to inspect. If the format differs significantly from skills, parsing logic will need adjustment.

2. **Cross-project slug reversal ambiguity:** Paths with hyphens in directory names produce ambiguous slugs. The spec uses "verify path exists on disk" as the disambiguation strategy. If this proves unreliable, an alternative is to read the `.claude/projects/<slug>/` contents for a stored project path reference.

3. **Plugin health stale threshold:** The spec says "30+ days." This may need to be configurable or adjusted based on user feedback. Some marketplace plugins update monthly; others are stable for months.

4. **ToolSearch live invocation (v2.1):** Querying ToolSearch at generation time adds a runtime dependency on MCP servers being available. If servers are down, the deferred tools section should gracefully degrade to "unable to query -- MCP server unavailable."

5. **Global staleness hook registration:** The v2.0 global mode needs a SessionStart hook in `~/.claude/settings.json`. Should the plugin auto-register this, or should the user add it manually? Auto-registration requires modifying `settings.json` programmatically, which is fragile. Recommendation: provide the hook config in the README and let the user add it.
