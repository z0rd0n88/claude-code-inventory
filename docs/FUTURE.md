# Future Work — claude-code-inventory

> Working planning document. Not committed to the README.
> Last updated: 2026-04-11

---

## Table of Contents

1. [Memory Files](#1-memory-files)
2. [Scheduled Tasks](#2-scheduled-tasks)
3. [MCP Auth State](#3-mcp-auth-state)
4. [Keybindings](#4-keybindings)
5. [Cross-Project Comparison](#5-cross-project-comparison)
6. [Plugin Health](#6-plugin-health)
7. [Permission Audit](#7-permission-audit)
8. [CLAUDE.md Quality Integration](#8-claudemd-quality-integration)
9. [Session History / Usage Patterns](#9-session-history--usage-patterns)
10. [Install Script / One-Liner](#10-install-script--one-liner)
11. [Plugin Marketplace Distribution](#11-plugin-marketplace-distribution)

---

## 1. Memory Files

### What it would inventory

Claude Code's memory system stores per-project knowledge in markdown files with YAML frontmatter. Each memory file has structured metadata:

```yaml
---
name: SMS/RCS Feature
description: SMS gateway implementation via Twilio on the sms branch
type: project
---
```

The `type` field classifies memories: `user`, `project`, `feedback`, `reference`. The `MEMORY.md` index file links to individual memory files with one-line descriptions.

The inventory would list:
- Total memory file count per project
- Breakdown by type (user/project/feedback/reference)
- Each file's name, type, and description from frontmatter
- Whether the MEMORY.md index references all files (orphan detection)
- Whether any index entries point to missing files (broken links)
- Age of each memory file (from filesystem mtime)

### Where the data lives

| File | Contents |
|------|----------|
| `~/.claude/projects/<project-slug>/memory/MEMORY.md` | Index with markdown links |
| `~/.claude/projects/<project-slug>/memory/*.md` | Individual memory files with YAML frontmatter |

The project slug is a mangled path: `C:\Users\sneak\Documents\BratBot` becomes `C--Users-sneak-Documents-BratBot`. Worktree directories get their own project slugs (e.g., `C--Users-sneak-Documents-BratBot--claude-worktrees-bold-chandrasekhar`).

### Output section

```markdown
## Memory Files

| File | Type | Description |
|------|------|-------------|
| user_environment.md | user | Shell and tool PATH quirks in the user's Windows/Git Bash environment |
| project_sms_feature.md | project | SMS gateway implementation via Twilio on the sms branch |
| project_runpod_gpu_risk.md | project | RTX 4090 pod must never be stopped unless absolutely necessary |
| project_supervisord_env_vars.md | project | How to override container env vars on RunPod via supervisord |
| project_update_automatons.md | project | Local plugin that auto-generates .CLAUDE.inventory.md |

Summary: 5 memory files (1 user, 4 project, 0 feedback, 0 reference)
```

Validation warnings:
- `[!] Memory file not in MEMORY.md index: <filename>` (orphaned file)
- `[!] MEMORY.md references missing file: <filename>` (broken link)

### JSON sidecar addition

```json
{
  "memory": {
    "files": [
      { "filename": "user_environment.md", "type": "user", "name": "...", "description": "..." }
    ],
    "summary": { "total": 5, "user": 1, "project": 4, "feedback": 0, "reference": 0 },
    "orphaned": [],
    "brokenLinks": []
  }
}
```

### Complexity: Low

Straightforward file reads with YAML frontmatter parsing. The discovery phase already reads SKILL.md frontmatter, so the pattern is established. The only new logic is parsing the MEMORY.md index to cross-reference against actual files.

### Effort: 8-10 hours

### Verification

- Create test memory files with various types
- Verify summary counts are accurate
- Create orphaned file (not in MEMORY.md index), verify detection
- Create broken link (index references missing file), verify detection
- Verify JSON sidecar structure matches spec

### Dependencies / blockers

- None. All data is local filesystem. YAML frontmatter parsing is already done for skills.
- Project slug path mangling logic must handle both regular paths and worktree paths.

---

## 2. Scheduled Tasks

### What it would inventory

Scheduled tasks created via `mcp__scheduled-tasks__create_scheduled_task`. Each task has:
- `taskId` (kebab-case identifier, used as directory name)
- `prompt` (the instructions Claude executes)
- `description` (one-line summary)
- `cronExpression` or `fireAt` (schedule)
- `enabled` state
- `notifyOnCompletion` flag

### Where the data lives

Based on the tool's documentation, each task is stored as a skill file at:

```
~/.claude/scheduled-tasks/{taskId}/SKILL.md
```

However, on the current machine `~/.claude/scheduled-tasks/` does not exist (no tasks have been created yet). This means the directory is created on first task creation.

The tool documentation says tasks are "session-only" for CronCreate but the `mcp__scheduled-tasks__create_scheduled_task` tool explicitly says the task is "stored as a skill file." These are two different systems:

| System | Storage | Persistence |
|--------|---------|-------------|
| `CronCreate` (built-in) | In-memory only | Dies with session |
| `mcp__scheduled-tasks__*` (MCP tool) | `~/.claude/scheduled-tasks/{taskId}/SKILL.md` | Persistent on disk |

The inventory should focus on the persistent MCP-based tasks since the in-memory cron jobs are ephemeral.

### Output section

```markdown
## Scheduled Tasks

| Task ID | Description | Schedule | Enabled | Next Run |
|---------|-------------|----------|---------|----------|
| check-inbox | Check email for urgent items | 0 9 * * 1-5 (weekdays 9am) | yes | 2026-03-21T09:00 |
| daily-standup | Prepare standup summary | 0 8 * * 1-5 (weekdays 8am) | yes | 2026-03-21T08:00 |
| weekly-report | Generate weekly project report | 0 17 * * 5 (Fridays 5pm) | no | -- |
```

If no `~/.claude/scheduled-tasks/` directory exists: omit the section entirely.

### JSON sidecar addition

```json
{
  "scheduledTasks": [
    {
      "taskId": "check-inbox",
      "description": "Check email for urgent items",
      "cronExpression": "0 9 * * 1-5",
      "fireAt": null,
      "enabled": true
    }
  ]
}
```

### Complexity: Low-Medium

Low complexity for the file discovery (just read SKILL.md files in subdirectories). Medium because the SKILL.md format for scheduled tasks may differ from regular skills -- the task's prompt, schedule, and enabled state need to be extracted, and the storage format isn't documented. Need to create a task first to inspect the actual file structure.

### Effort: 6-8 hours

### Verification

- Create test scheduled task with cron expression
- Verify parsing of cronExpression and next-run calculation
- Verify one-time fireAt tasks display correctly
- Verify disabled tasks show "no" in Enabled column
- Test edge cases: invalid cron, missing frontmatter keys

### Dependencies / blockers

- **Need to create a test task first** to confirm the file format. The tool says it creates `{taskId}/SKILL.md` but the actual YAML frontmatter schema is unknown until one exists on disk.
- The scheduled-tasks MCP server must be running to list tasks programmatically via `list_scheduled_tasks`. But for inventory purposes, reading the filesystem directly is more reliable (works offline, doesn't depend on MCP server state).
- Cron parsing library choice (inline or external?) is undecided.

---

## 3. MCP Auth State

> **Status: Implemented in v1.1** (2026-03-21) — surfaces servers from `~/.claude/mcp-needs-auth-cache.json`. Caveat: currently only shows Claude.ai web app servers, not Claude Code CLI servers; under investigation.

### What it would inventory

> **Status: Implemented in v1.1** (2026-03-21)

Which MCP servers need re-authentication. This is useful because MCP auth tokens expire silently and the first sign of trouble is a failed tool call mid-session.

### Where the data lives

```
~/.claude/mcp-needs-auth-cache.json
```

Current contents on this machine:

```json
{
  "claude.ai Google Calendar": { "timestamp": 1773833415584 },
  "claude.ai Gmail": { "timestamp": 1773833415557 }
}
```

The keys are MCP server display names (not the `mcpServers` keys from settings.json -- these appear to be from the Claude.ai web interface, not Claude Code). The timestamps are Unix epoch milliseconds indicating when the auth was flagged as needed.

### Output section

```markdown
## MCP Auth State

| Server | Auth Needed Since |
|--------|------------------|
| Google Calendar | 2026-03-16 04:30 |
| Gmail | 2026-03-16 04:30 |
```

If the cache file is empty or all entries are recent (< 1 hour old): show "All MCP servers authenticated" or omit.

### JSON sidecar addition

```json
{
  "mcpAuthState": [
    { "server": "Google Calendar", "needsAuthSince": "2026-03-16T04:30:15.584Z" }
  ]
}
```

### Complexity: Low

Single JSON file read + timestamp formatting. No parsing ambiguity.

### Effort: 2-3 hours

### Verification

- Create test MCP auth cache file
- Run skill, verify section appears in output
- Verify JSON sidecar contains `mcpAuthState` key
- Delete cache file, verify section disappears gracefully

### Dependencies / blockers

- **Unclear whether this file tracks Claude Code MCP servers or only Claude.ai ones.** The current entries ("claude.ai Google Calendar", "claude.ai Gmail") suggest this is the web app's auth cache, not the CLI's. Claude Code's MCP servers (context7, github from `.claude/settings.json`) don't appear here. Need to investigate whether Claude Code has its own MCP auth cache or if it just fails at runtime.
- If this file only tracks Claude.ai auth, the utility for the CLI inventory is limited. Consider flagging this clearly in the output.

---

## 4. Keybindings

> **Status: Implemented in v1.1** (2026-03-21) — skeleton only. Section appears if `~/.claude/keybindings.json` exists; omitted otherwise. Full parsing pending when file format is known.

### What it would inventory

Custom keyboard shortcuts configured in Claude Code. These let users bind key combinations to commands, skills, or actions.

### Where the data lives

```
~/.claude/keybindings.json
```

This file does **not currently exist** on this machine. The keybindings feature may be:
- Not yet released
- Only available in IDE integrations (VS Code extension)
- Created on first custom binding

### Output section

```markdown
## Keybindings

| Key | Action | Description |
|-----|--------|-------------|
| Ctrl+Shift+R | /inventory | Refresh automation inventory |
| Ctrl+Shift+T | run-tests | Execute test suite |
```

If the file doesn't exist: omit the section entirely.

### JSON sidecar addition

```json
{
  "keybindings": [
    { "key": "ctrl+shift+r", "action": "/inventory", "description": "..." }
  ]
}
```

### Complexity: Low

Single JSON file read. The challenge is that the file format is unknown since it doesn't exist yet.

### Effort: 1-2 hours

### Verification

- Create dummy keybindings.json, verify it appears
- Delete file, verify section disappears

### Dependencies / blockers

- **File format is completely unknown.** No keybindings.json exists to inspect. Must either:
  - Create a keybinding through the Claude Code UI and inspect the resulting file, or
  - Wait for Anthropic to document the feature, or
  - Check the Claude Code source/changelog for the schema
- This is a low-risk addition: if the file doesn't exist, the section is simply omitted. Implement the skeleton now and fill in the parsing logic when the format is known.

---

## 5. Cross-Project Comparison

### What it would inventory

A comparison view across all projects in `~/.claude/projects/*/`. Shows what each project has configured so you can spot gaps ("project A has a linting hook but project B doesn't").

### Where the data lives

```
~/.claude/projects/*/
```

Each project directory is named with a mangled absolute path (e.g., `C--Users-sneak-Documents-BratBot`). Relevant subdirectories and files:

| Path | Contents |
|------|----------|
| `memory/` | Memory files (if they exist) |
| `*.jsonl` | Session transcripts |
| `*/` (UUID dirs) | Agent session data |

But the more interesting data is in the project's actual `.claude/` directory on disk, which requires reverse-mapping the slug back to a filesystem path:
- `C--Users-sneak-Documents-BratBot` -> `C:\Users\sneak\Documents\BratBot`
- Then read `C:\Users\sneak\Documents\BratBot\.claude\settings.json`

### Output section

```markdown
## Cross-Project Comparison

| Feature | BratBot | asciiSkill | vista |
|---------|---------|------------|-------|
| Project hooks | 2 (PreToolUse, PostToolUse) | 0 | 0 |
| MCP servers | 2 (context7, github) | 0 | 1 |
| Project skills | 4 | 1 | 0 |
| Project agents | 1 | 0 | 0 |
| Memory files | 5 | 2 | 0 |
| CLAUDE.md | yes | no | yes |
```

Optionally flag recommendations like: "asciiSkill has no hooks -- consider adding a linting hook."

### JSON sidecar addition

```json
{
  "crossProject": {
    "projects": [
      {
        "slug": "C--Users-sneak-Documents-BratBot",
        "path": "C:\\Users\\sneak\\Documents\\BratBot",
        "hooks": 2,
        "mcpServers": 2,
        "skills": 4,
        "agents": 1,
        "memoryFiles": 5,
        "hasClaudeMd": true
      }
    ]
  }
}
```

### Complexity: High

Several hard problems:

1. **Slug-to-path mapping.** The project slug uses `--` as a path separator and `-` to replace `\` or `/`. This is reversible for simple paths but ambiguous if a directory name contains hyphens. The safest approach is to attempt the reverse mapping, then verify the path exists on disk.

2. **Worktree noise.** The projects directory is full of worktree slugs (e.g., `C--Users-sneak-Documents-BratBot--claude-worktrees-bold-chandrasekhar`). These should be filtered out -- they aren't real "projects," they're temporary branches. Filtering heuristic: any slug containing `--claude-worktrees-` is a worktree.

3. **Permission concerns.** Reading other projects' `.claude/settings.json` means the skill reaches outside the current project root. This is fine for a global inventory but may surprise users.

4. **Performance.** Scanning N projects means N directory reads + N settings.json reads + N skill directory listings. For a user with many projects this could be slow (though likely still under 10 seconds).

### Effort: 8-10 hours

### Verification

- Create multiple test projects with varying configurations
- Verify comparison table is accurate
- Verify inconsistency detection catches real differences
- Test on actual multi-project setup

### Dependencies / blockers

- Reliable slug-to-path reverse mapping. Needs testing with edge cases (paths with hyphens, spaces, unicode).
- Decision: should this run by default, or only when explicitly requested? Running it every SessionStart hook invocation would be expensive. Recommendation: only run on explicit `/inventory --cross-project` flag.
- Requires Memory Files (v1.2) and Plugin Health (v1.2) to be useful.
- Requires `.CLAUDE.inventory.json` to exist in each project (created by this skill).

---

## 6. Plugin Health

### What it would inventory

Deeper analysis of the plugin ecosystem beyond simple listing:

**Orphaned versions:** Plugin versions with a `.orphaned_at` marker file. These are old versions that the plugin system has superseded but hasn't cleaned up. Currently observed on this machine:

| Plugin | Orphaned Versions | Active Version |
|--------|-------------------|----------------|
| code-review | 78497c524da3, d5c15b861cd2 | 6b70f99f769f |
| explanatory-output-style | 78497c524da3, d5c15b861cd2 | 6b70f99f769f |
| feature-dev | 78497c524da3, d5c15b861cd2 | 6b70f99f769f |
| frontend-design | 78497c524da3, d5c15b861cd2 | 6b70f99f769f |
| github | 78497c524da3, aa296ec81e8c, d5c15b861cd2 | 6b70f99f769f |
| rust-analyzer-lsp | 1.0.0 | (not installed) |
| skill-creator | 78497c524da3, d5c15b861cd2 | 6b70f99f769f |
| superpowers | 5.0.2, 5.0.4 | 5.0.5 |

**Version mismatches:** When `installed_plugins.json` points to a version that doesn't exist in the cache directory (install path missing).

**Enabled but not installed:** When `enabledPlugins` in settings.json lists a plugin that has no entry in `installed_plugins.json`. Currently, `railway@claude-plugins-official` is enabled in settings but not in `installed_plugins.json`.

**Cache disk usage:** How much disk space orphaned versions consume.

**Update recency:** How long since each plugin was last updated (from `lastUpdated` in `installed_plugins.json`). Flag plugins not updated in 30+ days.

### Where the data lives

| File | What to check |
|------|---------------|
| `~/.claude/plugins/installed_plugins.json` | Active versions, install paths, lastUpdated |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/` | All cached versions on disk |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.orphaned_at` | Orphan markers |
| `~/.claude/settings.json` -> `enabledPlugins` | What's actually enabled |

### Output section

```markdown
## Plugin Health

### Orphaned Versions (cleanup candidates)

| Plugin | Orphaned Versions | Disk Usage |
|--------|-------------------|------------|
| github | 3 old versions | 4.2 MB |
| superpowers | 2 old versions | 12.1 MB |
| ... | ... | ... |

Total reclaimable: ~32 MB

### Potential Issues

| Issue | Plugin | Details |
|-------|--------|---------|
| Enabled but not installed | railway | In enabledPlugins but not in installed_plugins.json |
| Not updated in 30+ days | claude-code-setup | Last updated 2026-03-15 |
| Install path missing | — | (none detected) |
```

### JSON sidecar addition

```json
{
  "pluginHealth": {
    "orphanedVersions": [
      { "plugin": "github", "marketplace": "claude-plugins-official", "versions": ["78497c524da3", "aa296ec81e8c"], "diskUsageMB": 4.2 }
    ],
    "enabledButNotInstalled": ["railway@claude-plugins-official"],
    "stalePlugins": [
      { "plugin": "claude-code-setup", "lastUpdated": "2026-03-15T14:27:30.313Z", "daysSinceUpdate": 5 }
    ],
    "totalReclaimableMB": 32.0
  }
}
```

### Complexity: Medium

The orphan detection is straightforward (find `.orphaned_at` files). Disk usage calculation requires `du -sh` on each orphaned version directory. The cross-referencing between `enabledPlugins`, `installed_plugins.json`, and the cache directory is logic-heavy but all data is readily available.

### Effort: 10-12 hours

### Verification

- Test with real plugins (some orphaned, some current, some disabled)
- Verify disk usage calculation is accurate
- Verify enabled-but-not-installed edge case is detected
- Compare against manual filesystem inspection

### Dependencies / blockers

- Disk usage calculation may be slow on Windows if the cache is large (many plugin versions with many files). Consider caching the result.
- No way to determine if orphaned versions are "safe to delete" without understanding the plugin system's cleanup schedule. The inventory should report but not recommend deletion -- leave that to the user.
- Stale detection threshold (6 months? 12 months?) is undecided — make configurable.

---

## 7. Permission Audit

### What it would inventory

Analysis of `settings.local.json` permission patterns. Currently the inventory only reports a count ("~250 allowlisted entries"). A deeper audit would:

- Group permissions by tool type (Bash, Read, Write, WebSearch, etc.)
- Detect overly broad patterns (e.g., `Bash(*)` or `Read(**)`)
- Flag duplicate or near-duplicate entries
- Identify permissions that reference non-existent paths
- Show the most common permission patterns

### Where the data lives

```
.claude/settings.local.json -> permissions.allow[]
```

Each entry is a string like:
- `Bash(uv run:*)` -- Bash with a glob pattern
- `WebSearch` -- bare tool name (allows all)
- `Bash(docker compose:*)` -- Bash with specific command prefix
- `Read(//c/ProgramData/chocolatey/bin/**)` -- Read with path glob

### Output section

```markdown
## Permission Audit

### By Tool Type

| Tool | Count | Example Pattern |
|------|-------|-----------------|
| Bash | 187 | `Bash(uv run:*)`, `Bash(docker compose:*)` |
| Read | 23 | `Read(//c/ProgramData/chocolatey/bin/**)` |
| WebSearch | 1 | `WebSearch` (unrestricted) |
| Write | 5 | `Write(src/**/*.py)` |

### Observations

| Observation | Count | Details |
|-------------|-------|---------|
| Broad patterns (wildcard-heavy) | 3 | `Bash(python -c:*)` allows arbitrary Python execution |
| Duplicate permissions | 12 | Same command allowlisted multiple times |
| Dead paths | 2 | References paths that no longer exist on disk |
```

### JSON sidecar addition

```json
{
  "permissionAudit": {
    "total": 250,
    "byTool": {
      "Bash": 187,
      "Read": 23,
      "WebSearch": 1,
      "Write": 5
    },
    "broadPatterns": [
      { "pattern": "Bash(python -c:*)", "risk": "Allows arbitrary Python code execution" }
    ],
    "duplicates": 12,
    "deadPaths": ["Read(//c/path/that/no/longer/exists)"]
  }
}
```

### Complexity: Medium

Parsing the permission strings requires understanding the format: `ToolName(pattern)` or bare `ToolName`. The "broad pattern" detection needs heuristics:
- Any pattern ending in `:*)` after a short prefix
- Any pattern that is just a tool name with no restrictions
- `Bash` permissions with shell metacharacters that could be exploited

Dead path detection requires filesystem checks for each Read/Write permission, which could be slow with hundreds of entries.

### Effort: 12-15 hours

### Verification

- Create test settings.local.json with various permission patterns
- Verify each pattern is classified correctly
- Verify risk scoring aligns with intuition
- Gather user feedback on false positives/negatives

### Dependencies / blockers

- **Privacy sensitivity.** The current inventory deliberately only reports a count. Listing individual permission patterns could expose information about the user's workflow, installed tools, and directory structure. The full audit should be opt-in, possibly via a `--audit-permissions` flag. The default output should remain count-only.
- The v1.0 SKILL.md explicitly says "Count of `permissions.allow` entries only (do NOT list individual entries)." This design decision should be respected unless the user explicitly requests the audit.
- Need to reverse-engineer permission rule format (settings.local.json structure).
- Risk scoring heuristics (what counts as "overly broad"?) should be conservative.

---

## 8. CLAUDE.md Quality Integration

> **Status: Implemented in v1.1** (2026-03-21) — scores the project's CLAUDE.md against 8 criteria (dev commands, architecture, gotchas, environment, conventions, deployment, key paths, length). Shows cross-reference note if `claude-md-management` plugin is installed.

### What it would inventory

Read the project's CLAUDE.md file and produce a quality score based on criteria from the `claude-md-management` plugin's improver skill. The score would indicate how well the CLAUDE.md documents the project for Claude Code.

Scoring criteria (approximate):
- Has dev commands documented (build, test, lint, format)
- Has architecture overview
- Has gotchas / known issues
- Has environment setup instructions
- Has conventions documented (formatting, naming)
- Has deployment instructions (if applicable)
- References key file paths
- Not excessively long (diminishing returns past ~200 lines)

### Where the data lives

```
<project-root>/CLAUDE.md
```

The `claude-md-management@claude-plugins-official` plugin has a skill called `claude-md-improver` that does a similar analysis. However, invoking another plugin's skill from within this plugin adds coupling.

### Output section

```markdown
## CLAUDE.md Quality

| Criterion | Status |
|-----------|--------|
| Dev commands | present (5 commands) |
| Architecture | present |
| Gotchas | present (6 items) |
| Environment setup | present |
| Conventions | present |
| Deployment | present |
| Key file paths | partial (model/ not documented) |
| Length | 85 lines (good) |

Score: 8/8 criteria met
```

### JSON sidecar addition

```json
{
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
      "deployment": true,
      "keyPaths": "partial",
      "length": "good"
    }
  }
}
```

### Complexity: Medium-High

The scoring heuristics are inherently fuzzy. Detecting whether "architecture" is documented requires keyword matching (sections titled "Architecture", "Structure", "Overview") or more sophisticated analysis. The criteria need to be calibrated to avoid false positives/negatives.

This is essentially building a lightweight version of `claude-md-improver` inside this plugin. It might be better to:
1. Check if `claude-md-management` is installed
2. If yes, reference its analysis rather than duplicating logic
3. If no, do a simpler check (file exists, line count, section headings present)

### Effort: 6-8 hours

### Verification

- Test on projects with different CLAUDE.md completeness levels
- Verify scoring is consistent
- Verify graceful handling of missing/empty CLAUDE.md

### Dependencies / blockers

- **Heuristic quality.** A bad quality score is worse than no quality score. The criteria detection needs to be good enough to be useful but not so aggressive that it flags well-written CLAUDE.md files as lacking.
- **Overlap with claude-md-management plugin.** If the user has that plugin installed, this feature is redundant. Consider: only show CLAUDE.md quality if `claude-md-management` is NOT installed, and otherwise show "See /claude-md-management:claude-md-improver for CLAUDE.md analysis."
- **Not a core inventory feature.** This is more "advisory" than "inventory." Consider making it opt-in.

---

## 9. Session History / Usage Patterns

### What it would inventory

Claude Code stores detailed session metadata in two locations:

**Session metadata** (`~/.claude/usage-data/session-meta/*.json`):
```json
{
  "session_id": "...",
  "project_path": "C:\\Users\\sneak\\Documents\\BratBot",
  "start_time": "2026-03-18T01:30:53.353Z",
  "duration_minutes": 0,
  "user_message_count": 1,
  "tool_counts": { "Grep": 1 },
  "input_tokens": 30,
  "output_tokens": 24,
  "first_prompt": "how do i populate the RUNPOD_SSH_KEY?",
  "uses_task_agent": false,
  "uses_mcp": false
}
```

**Session facets** (`~/.claude/usage-data/facets/*.json`):
```json
{
  "underlying_goal": "Add Telegram bot integration...",
  "goal_categories": { "feature_implementation": 1 },
  "outcome": "fully_achieved",
  "claude_helpfulness": "essential",
  "primary_success": "multi_file_changes",
  "brief_summary": "User requested Telegram bot integration..."
}
```

Useful aggregations:
- Most-used tools across sessions (Bash, Read, Edit, Grep, etc.)
- Most-used MCP tools (which MCP servers are actually being used)
- Sessions per project (which projects are most active)
- Average session duration and token usage
- Success rate (from facets: fully_achieved vs partially_achieved)
- Whether skills/agents are actually invoked (`uses_task_agent`)

### Where the data lives

| Path | Contents |
|------|----------|
| `~/.claude/usage-data/session-meta/*.json` | Per-session metadata (tool counts, tokens, duration) |
| `~/.claude/usage-data/facets/*.json` | Per-session qualitative analysis (goals, outcomes) |
| `~/.claude/usage-data/report.html` | Pre-generated usage report (may be stale) |

### Output section

```markdown
## Usage Patterns (last 30 days)

### Tool Usage

| Tool | Invocations | Sessions |
|------|-------------|----------|
| Bash | 1,247 | 42 |
| Read | 983 | 38 |
| Edit | 567 | 31 |
| Grep | 412 | 29 |
| WebSearch | 23 | 8 |

### Session Summary

| Metric | Value |
|--------|-------|
| Total sessions | 47 |
| Average duration | 18 min |
| Total tokens | 2.3M input / 890K output |
| Success rate | 78% fully achieved |
| Most active project | BratBot (31 sessions) |

### Skill/Agent Adoption

| Item | Times Used | Last Used |
|------|-----------|-----------|
| inventory | 12 | 2026-03-20 |
| brainstorming (superpowers) | 5 | 2026-03-19 |
| code-reviewer agent | 3 | 2026-03-18 |
```

### JSON sidecar addition

```json
{
  "usagePatterns": {
    "period": "30d",
    "totalSessions": 47,
    "toolUsage": { "Bash": 1247, "Read": 983 },
    "avgDurationMinutes": 18,
    "totalInputTokens": 2300000,
    "totalOutputTokens": 890000,
    "successRate": 0.78,
    "projectSessions": { "BratBot": 31, "asciiSkill": 8 }
  }
}
```

### Complexity: High

Several challenges:

1. **Volume.** A power user may have hundreds or thousands of session files. Reading and aggregating all of them takes time and memory.

2. **Skill/agent attribution.** Session metadata has `uses_task_agent: true/false` but doesn't say WHICH skill or agent was used. Tool counts like `{ "Grep": 1 }` show tool names but not which skill invoked them. Determining "this session used the brainstorming skill" would require parsing session transcripts (`.jsonl` files), which are large and structured as message streams.

3. **Privacy.** Session data includes `first_prompt` (what the user asked), `brief_summary` (what happened), and `underlying_goal`. Including these in the inventory output exposes potentially sensitive session content. The aggregated statistics (tool counts, duration, token usage) are safe; individual session details are not.

4. **Staleness.** Usage patterns change over time. A "most used tools" report from 30 days ago is different from last week. The output needs a clear time window.

### Effort: 15-20 hours

### Verification

- Create synthetic usage logs, verify aggregation is correct
- Test on real Claude Code session(s)
- Verify privacy notice is clear
- Test opt-in/opt-out toggles work correctly

### Dependencies / blockers

- **Privacy decision.** Must decide what level of detail is appropriate. Recommendation: aggregate statistics only (tool counts, session counts, token totals). Never include `first_prompt`, `brief_summary`, or `underlying_goal` in the inventory output.
- **Performance.** Reading hundreds of JSON files is slow, especially on Windows. Consider caching the aggregated stats and only re-computing when new session files appear.
- **Not core inventory.** This is analytics, not inventory. Consider making it a separate command (`/inventory --usage`) rather than including it in every generation.

---

## 10. Install Script / One-Liner

### What it would do

Provide a single command that installs the plugin from the GitHub repo to `~/.claude/plugins/cache/local/inventory/1.0.0/` and registers it in `~/.claude/settings.json`.

### Current install process

```bash
# 1. Clone the repo
git clone https://github.com/<user>/claude-code-inventory.git
cd claude-code-inventory

# 2. Copy files to plugin cache
mkdir -p ~/.claude/plugins/cache/local/inventory/1.0.0
cp -r .claude-plugin commands skills hooks \
  ~/.claude/plugins/cache/local/inventory/1.0.0/

# 3. Register in settings.json (manual JSON edit)
# Add "inventory@local": true to enabledPlugins
```

### Proposed one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/<user>/claude-code-inventory/main/install.sh | bash
```

The `install.sh` would:
1. Create the plugin cache directory
2. Download the 6 required files from GitHub (or clone and copy)
3. Check if `~/.claude/settings.json` exists
4. Add `"inventory@local": true` to `enabledPlugins` using `jq` or sed
5. Verify the hook script is executable
6. Print a success message

### Complexity: Low-Medium

The script itself is simple. The complications are:

| Challenge | Details |
|-----------|---------|
| JSON editing without jq | Not all systems have `jq`. Need a fallback (Python one-liner, or sed hack). |
| Windows support | `curl \| bash` doesn't work on Windows natively. Need a PowerShell equivalent or rely on Git Bash. |
| Idempotency | Must not corrupt settings.json if run twice. Check before modifying. |
| Version updates | The one-liner installs a fixed version. How does the user update? Need an `install.sh --update` path. |

### Implementation plan

1. Write `install.sh` (bash, works on macOS/Linux/Git Bash on Windows)
2. Write `install.ps1` (PowerShell, for native Windows)
3. Add install instructions to README
4. Consider: `npx` installer if the plugin is published to npm (see #11)

### Effort: 4-6 hours

### Verification

- Test install script on clean machine (no plugin pre-existing)
- Verify all files copied correctly
- Verify skill runs successfully after installation
- Test on Windows (Git Bash) and macOS/Linux

### Dependencies / blockers

- The repo must be public on GitHub for the raw URL to work.
- Editing `settings.json` programmatically is fragile. If Anthropic adds a `claude plugin install --local <path>` CLI command, that would be the better approach. Monitor Claude Code releases for this.

---

## 11. Plugin Marketplace Distribution

### What it would take

Publishing to the official `claude-plugins-official` marketplace (hosted at `anthropics/claude-plugins-official` on GitHub).

### Current marketplace structure

The marketplace repo is cloned locally at:
```
~/.claude/plugins/marketplaces/claude-plugins-official/
```

It contains:
- `plugins/` — one directory per plugin, each with a `plugin.json`
- `external_plugins/` — plugins hosted externally (just metadata)
- `README.md`

### Requirements (observed, not officially documented)

Based on existing marketplace plugins:

| Requirement | Details |
|-------------|---------|
| `plugin.json` | Metadata: name, description, version, category |
| Plugin structure | Must follow the `commands/`, `skills/`, `hooks/`, `agents/` convention |
| GitHub repo | Plugin source must be publicly accessible |
| Review process | PRs to `anthropics/claude-plugins-official` are reviewed by Anthropic |
| Naming | kebab-case, unique within the marketplace |
| Category | Must be one of the recognized categories (documentation, lsp, etc.) |

### What would change

| Aspect | Current (local) | Marketplace (published) |
|--------|-----------------|-------------------------|
| Installation | Manual file copy | `claude plugin install inventory` (hypothetical) |
| Updates | Manual re-copy | Automatic via marketplace sync |
| Discovery | Only if you know about it | Searchable in plugin marketplace |
| Plugin key | `inventory@local` | `inventory@claude-plugins-official` |
| Install counts | N/A | Tracked in `install-counts-cache.json` |

### Steps to publish

1. **Fork `anthropics/claude-plugins-official`**
2. **Add plugin directory** at `plugins/inventory/`
3. **Add `plugin.json`** with marketplace metadata
4. **Add source reference** pointing to this repo (or include files inline)
5. **Open PR** to `anthropics/claude-plugins-official`
6. **Wait for review** — timeline unknown, review criteria unknown
7. **Post-publish**: update README, remove local install instructions, add marketplace install instructions

### Complexity: Medium

The technical work is trivial (the plugin already works). The real complexity is:

- **Review process uncertainty.** Anthropic's review criteria and timeline are not documented. Some marketplace plugins have 1 install (suggesting low review bar or auto-acceptance), but this may have changed.
- **Ongoing maintenance.** Marketplace plugins need to be updated when Claude Code's plugin API changes. The hook format, SKILL.md frontmatter, and settings.json schema are not versioned or guaranteed stable.
- **Self-referential problem.** The plugin inventories the plugin ecosystem, including itself. If it becomes a marketplace plugin, it needs to correctly classify itself as "installed" rather than "custom." This is already handled by the classification rules but should be tested.

### Effort: 4-6 hours

### Verification

- Verify plugin appears in Claude Code marketplace search
- Test installation from marketplace works
- Verify plugin auto-updates when new version is released

### Dependencies / blockers

- **Anthropic's submission process.** Need to find or ask for documentation on how to submit a plugin.
- **Plugin naming.** "inventory" may conflict with something else. "claude-code-inventory" is the repo name but the plugin is currently named "inventory." Consider renaming the plugin to match the repo before publishing.
- **Not urgent.** The local install works fine. Publishing is a distribution convenience, not a capability blocker.
- Plugin should be stable (v2.0+ release candidate) before publishing.

---

## Priority Matrix

| Feature | Complexity | Value | Effort | Release | Status |
|---------|-----------|-------|--------|---------|--------|
| MCP auth state | Low | Medium | 2-3h | **v1.1** | ✅ Done |
| Keybindings | Low | Low | 1-2h | **v1.1** | ✅ Done |
| CLAUDE.md quality | Low-Medium | Medium | 6-8h | **v1.1** | ✅ Done |
| Memory files | Low | High | 8-10h | **v1.2** | ✅ Done |
| Scheduled tasks | Low-Medium | Medium | 6-8h | **v1.2** | ✅ Done |
| Plugin health | Medium | High | 10-12h | **v1.2** | ✅ Done |
| CLAUDE.md hierarchy | Low | Medium | 3-4h | **v1.2** | ✅ Done |
| Hook execution order | Low | Medium | 3-4h | **v1.2** | ✅ Done |
| Global standalone mode | Medium | High | 8-10h | **v2.0** | ✅ Done |
| Cross-project comparison | High | High | 8-10h | **v2.0** | ✅ Done |
| Settings conflict detection | Low-Medium | Medium | 4-6h | **v2.0** | ✅ Done |
| Remote triggers | Low-Medium | Medium | 4-6h | **v2.0** | ✅ Done |
| Deferred tools inventory | Medium | Medium | 6-8h | **v2.1** | ✅ Done |
| Monitor tool tracking | Low | Low-Medium | 3-4h | **v2.1** | ✅ Done |
| Sandbox configuration | Low | Medium | 2-3h | **v2.1** | ✅ Done |
| Permission audit | Medium-High | Medium | 12-15h | **v3.0** | — |
| Session history | High | Medium | 15-20h | **v3.0** | — |
| Install script | Low-Medium | High | 4-6h | **v3.0** | — |
| Marketplace distribution | Medium | Medium | 4-6h | **v3.0** | — |

### Sequencing Strategy: Complexity-First

Ship quick wins first (2-3 weeks per iteration) to build momentum, gather user feedback, and validate architecture before heavy lifting. Each release is independent and shippable.

**Rationale:**
- Low-complexity features (MCP Auth State, Keybindings) are 1-3 hour wins — prove execution
- Early Memory Files adoption (week 4-5) addresses high user pain without blocking earlier releases
- Architecture remains flexible — no major upfront investment in plumbing
- User feedback on v1.1 informs design of later features (Permission Audit, Session Patterns)

### Release Timeline

| Release | Features | Status |
|---------|----------|--------|
| **v1.1** | MCP Auth State, Keybindings (skeleton), CLAUDE.md Quality | ✅ Shipped |
| **v1.2** | Memory Files, Scheduled Tasks, Plugin Health, CLAUDE.md Hierarchy, Hook Execution Order | ✅ Shipped |
| **v2.0** | Global Standalone Mode, Cross-Project Comparison, Settings Conflicts, Remote Triggers | ✅ Shipped |
| **v2.1** | Deferred Tools, Monitor Tracking, Sandbox Configuration | ✅ Shipped |
| **v3.0** | Permission Audit, Session History, Install Script, Marketplace Distribution | Planned |

**Shipping cadence:** One release every 2-3 weeks (maintains momentum, allows feedback loops)

---

## Open Questions

1. **Should cross-project comparison be a separate command?** Running `/inventory --cross-project` vs `/inventory-compare` vs a standalone skill. The current plugin name "inventory" doesn't suggest cross-project analysis.

2. ~~**Should the plugin be renamed?**~~ **Resolved.** Renamed from `update-automatons` to `inventory` in v1.1. Plugin key is now `inventory@local` (or `inventory@claude-plugins-official` after marketplace submission). Output files renamed to `.CLAUDE.inventory.*`.

3. **JSON schema versioning.** The `.CLAUDE.inventory.json` sidecar has no schema version field. Adding new sections (memory, auth, health) will change the structure. Should add a `"schemaVersion": 2` field before expanding.

4. **Performance budget.** The current generation reads ~20 files. Adding memory files, session data, cross-project scans, and disk usage calculations could push this to hundreds of file reads. What's the acceptable generation time? The SessionStart hook should stay under 2 seconds; the full generation can take longer since it's user-initiated.

5. **Privacy tiers.** Some new features (permission audit, session history) expose more sensitive data than the current inventory. Consider a tiered output model:
   - Default: safe, non-sensitive (current behavior + memory files, auth state, plugin health)
   - `--detailed`: includes permission patterns, session statistics
   - `--full`: everything including session summaries (never recommended)

---

## Architecture Notes

### Unified SKILL.md Structure

All features follow the same 7-phase pattern in `skills/inventory/SKILL.md`:

1. **Discovery** — Read all config files in parallel
2. **Classification** — Tag items (installed/custom/blocked)
3. **Validation** — Check existence on disk
4. **Change Detection** — Diff against previous `.CLAUDE.inventory.json`
5. **Recommendations** — Gap analysis based on detected tech stack
6. **Generation** — Write `.md`, `.json`, `.hash` files
7. **Gitignore** — Auto-update `.gitignore` if needed

Each feature adds 1-2 discovery steps, validation rules, and recommendation patterns. The structure remains consistent.

### JSON Sidecar Schema

`.CLAUDE.inventory.json` is extensible. Each new feature adds a top-level key:

```json
{
  "automations": { "..." : "..." },
  "mcpAuthState": ["..."],
  "keybindings": { "..." : "..." },
  "claudeMdQuality": { "..." : "..." },
  "memory": { "..." : "..." },
  "scheduledTasks": ["..."],
  "pluginHealth": ["..."],
  "permissionAudit": { "..." : "..." },
  "crossProjectComparison": { "..." : "..." },
  "sessionUsage": { "..." : "..." }
}
```

---

## Success Criteria

### Per-Release

**v1.1:**
- All 3 features implemented and tested
- JSON sidecar validates (can be parsed and used by tools)
- No regressions in v1.0 core functionality
- Documentation updated (README, examples/)
- Evals pass (with-skill vs. without-skill)

**v1.2:**
- Memory Files parsing handles orphans/broken links correctly
- Scheduled Tasks format confirmed via actual task creation
- Plugin Health detects edge cases (enabled-but-missing)

**v2.0:**
- Permission Audit detects overly broad rules without false positives
- Session Patterns telemetry is opt-in and privacy-respecting
- Cross-project comparison accurate across 2+ real projects
- All features composable: can filter/sort JSON output programmatically

**v2.1:**
- Install script works on Windows (Git Bash) and Unix
- Plugin successfully submitted to marketplace
- Auto-update mechanism works for future releases

### End-to-End

- Running `/inventory` on a real multi-plugin project surfaces all feature categories
- JSON sidecar enables downstream tools (comparison scripts, dashboards)
- Documentation (README, examples) is complete and accurate
- No known regressions from v1.0
