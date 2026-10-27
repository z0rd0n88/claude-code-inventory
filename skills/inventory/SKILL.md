---
name: inventory
description: >
  Generate or update automation inventory files. Operates in two modes:
  **Project mode** (default, invoked via `/inventory`): scans global + project + local
  scopes, writes `.CLAUDE.inventory.md` to the project root.
  **Global mode** (invoked via `/inventory-global`): scans global scope only,
  writes `.CLAUDE.inventory.md` to `~/.claude/`.
  Use when the user says "update automatons", "list my automations", "what skills/hooks
  do I have", "refresh automation inventory", or when the SessionStart hook reports
  the inventory is missing or stale.
---

# Update Automatons — Automation Inventory Generator

Generates `.CLAUDE.inventory.md` in the current project root: a comprehensive,
human-readable inventory of every Claude Code automation active for this project,
organized by scope and tagged as **installed** (from a plugin/marketplace) or
**custom** (user-created). Also produces a `.CLAUDE.inventory.json` sidecar.

## When to Run

- SessionStart hook reports inventory is missing, stale (>24h), or configs changed
- User invokes `/inventory`
- After running `/claude-code-setup:claude-automation-recommender`
- After installing, removing, or updating plugins, skills, or MCP servers

## Mode

This skill operates in one of two modes based on how it was invoked:

- **Project mode** (default): Invoked via `/inventory`. Scans global + project + local scopes. Writes output to the current project root. Requires being inside a project directory.
- **Global mode**: Invoked via `/inventory-global`. Scans global scope only — skips all project-scope and local-scope reads. Writes output to `~/.claude/`. Works from any directory.

The mode determines which Phase 1 discovery sources are read, which Phase 6 output sections are generated, and where output files are written.

**In Global mode, skip these entirely:**
- Phase 1: Project scope, Local scope, Memory files (project-specific)
- Phase 5: Recommendations (requires project tech stack detection)
- Phase 6a: Project Scope section, Local Scope section, Memory Files section, Instruction Files Quality Score sub-section (hierarchy table still shows global `~/.claude/CLAUDE.md` if it exists), Settings Conflicts section, Security section "Permission entries" row (local-scope data unavailable)
- Phase 6a header: Use `> Regenerate: `/inventory-global`` instead of `> Regenerate: `/inventory``
- Phase 6a output path: Write to `~/.claude/.CLAUDE.inventory.md` instead of project root
- Phase 6b output path: Write to `~/.claude/.CLAUDE.inventory.json` instead of project root. Still write `instructionFiles` (`mode` and `modeSource` from rule 1, `activeRootFile` `null`, `agentsMdIgnored` `false`) and `claudeMdQuality` as `{"exists": false}`; `claudeMdHierarchy` holds only the global row, if it exists
- Phase 6c output path: Write to `~/.claude/.CLAUDE.inventory.hash` instead of project root
- Phase 7: Skip gitignore step (not in a project)

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
| `~/.claude/CLAUDE.md` | Global user instructions file. If it exists, count lines. List it only as the global row, never as a project-root or ancestor `.claude/CLAUDE.md` row, even when the project root is the home directory. It always loads alongside project instructions (except in `managed-only` mode) and does **not** count toward the AGENTS.md check below. There is no documented global `~/.claude/AGENTS.md`. |
| `~/.claude/settings.json` (instruction files mode) | `pluginConfigs["cc-plugin-agents-md@builtin"].options.instructionFiles`, or the pre-v2.1.285 ID `pluginConfigs["agents-md@builtin"].options.instructionFiles`. Valid values: `claude-md-or-agents-md` (the default when unset), `claude-md-and-agents-md`, `claude-md`, `managed-only`. If both IDs are set and differ, record a warning naming both values: the docs don't say which one wins. Use the `cc-plugin-agents-md@builtin` value for activation and mark the Mode line "uncertain" (`modeSource` `conflict`). If either value is invalid, rule 1's `invalid` case applies instead, with no conflict warning. Claude Code reads this entry only from user settings (or `--settings` / managed settings, which this skill does not read). See [Instruction file activation](#instruction-file-activation). |
| `~/.claude/scheduled-tasks/*/` | Persistent scheduled tasks. For each subdirectory, read the task definition file (likely `SKILL.md` or a JSON file) to extract: task ID (directory name), description, schedule (cron expression or one-time `fireAt`), and enabled state. If the directory does not exist, skip entirely. |
| `~/.claude/settings.json` (security keys) | Check for `sandboxMode`, `dangerouslySkipPermissions`, and any sandbox-related configuration. Also detect the OS via `uname -s` to determine if PID namespace isolation is available (Linux only). |

**Remote triggers:** In addition to reading the filesystem, also invoke `mcp__scheduled-tasks__list_scheduled_tasks` at generation time to query active remote triggers managed by Anthropic's infrastructure. If the MCP server is unavailable, fall back to filesystem-only discovery. For each task returned by the MCP tool that doesn't match a local filesystem task (by taskId), mark it as `source: "remote"`.

### Project scope (`.claude/` in project root)

| Source file | Extract |
|-------------|---------|
| `.claude/settings.json` | `hooks` (all events + matchers), `mcpServers` (all entries — for each server, check if it has `toolSearch` or deferred tool configuration to determine loading strategy) |
| `.claude/skills/*/SKILL.md` | Each skill's `name` and `description` from YAML frontmatter |
| `.claude/agents/*.md` | Each agent's `name` and `description` from YAML frontmatter |
| `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md` (project root) | Claude Code project instructions. Count lines for each that exists. For each, note whether it is a symlink to an `AGENTS.md` (Bash: `readlink <file>`) or imports one (see rule 4 in [Instruction file activation](#instruction-file-activation)). Do the same for these files in ancestor directories. |
| `AGENTS.md`, `.claude/AGENTS.md` (project root) | Cross-tool project instructions, which Claude Code v2.1.277+ reads in place of `CLAUDE.md`. Count lines for each that exists. |
| Root instruction file contents | Read the **active root file** (see [Instruction file activation](#instruction-file-activation)) for quality scoring: check for dev commands, architecture, gotchas, environment setup, conventions, deployment, key file paths, and line count. |
| Ancestor directories | Walk from the project root's parent up to the filesystem root. In each directory, check for `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, and `.claude/AGENTS.md`. Claude Code loads these at session start just like root files. In the home directory, skip `~/.claude/CLAUDE.md` here (it is the global file above). |
| Subdirectory instruction files (max 3 levels deep) | Use Glob with pattern `{*/CLAUDE.md,*/*/CLAUDE.md,*/*/*/CLAUDE.md,*/AGENTS.md,*/*/AGENTS.md,*/*/*/AGENTS.md,*/CLAUDE.local.md,*/*/CLAUDE.local.md,*/*/*/CLAUDE.local.md}` to find them. For each, count lines. Drop any match under the root `.claude/` directory (those are the root rows above, not subdirectories). Exclude `node_modules/`, `.git/`, `.agents/`, and other common vendored directories. For each subdirectory that has an `AGENTS.md`, also check whether `<subdir>/.claude/CLAUDE.md` exists and whether that subdirectory's `CLAUDE.md` or `CLAUDE.local.md` imports or is a symlink to its `AGENTS.md`, because the activation rules need them (rules 3 and 4). |

**Not instruction files:** Claude Code never reads `AGENTS.local.md`, `AGENTS.override.md`, or anything under `.agents/`. Do not list them.

### Instruction file activation

In global mode, only the global row exists: resolve the mode with rule 1 (skip its project and local settings check), then mark `~/.claude/CLAUDE.md` `inactive` ("mode is managed-only") when the mode is `managed-only`, otherwise `active`, and skip the rest of this step. After discovery, mark every instruction file `active`, `on demand`, or `inactive` for Claude Code. The rules follow the Claude Code memory docs (https://code.claude.com/docs/en/memory#agents-md):

1. **Mode:** use the `instructionFiles` value from `~/.claude/settings.json` (see Global scope). If unset, the mode is `claude-md-or-agents-md`. If a value is not one of the four valid values, record a warning naming it, use the other ID's value if that one is valid, else the default, and mark the Mode line "uncertain" (`modeSource` `invalid`). If `.claude/settings.json` or `.claude/settings.local.json` sets it, record a warning: Claude Code ignores that entry in project and local settings.
2. **Counting files:** a `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` in the project root or any ancestor directory. `~/.claude/CLAUDE.md`, managed `CLAUDE.md`, and `.claude/rules/` files do **not** count.
3. **Status per mode:**

| Mode | Root + ancestor `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` | Root + ancestor `AGENTS.md` / `.claude/AGENTS.md` | Subdirectory files |
|------|-------------------------------------------------|--------------------------------------------------|--------------------|
| `claude-md-or-agents-md` (default) | `active` | `active` if no counting file exists; otherwise `inactive` ("CLAUDE.md present") | `CLAUDE.md`: `on demand`. `AGENTS.md`: `on demand` only if no counting file exists **and** that subdirectory has no `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` of its own; otherwise `inactive` ("CLAUDE.md present") |
| `claude-md-and-agents-md` | `active` | `active` | all `on demand` |
| `claude-md` | `active` | `inactive` ("mode is claude-md") | `CLAUDE.md`: `on demand`. `AGENTS.md`: `inactive` ("mode is claude-md") |
| `managed-only` | `inactive` ("mode is managed-only") | `inactive` ("mode is managed-only") | `CLAUDE.md`: `on demand`. `AGENTS.md`: `inactive` ("mode is managed-only") |

A subdirectory `CLAUDE.local.md` follows the subdirectory `CLAUDE.md` rule. When a file gets more than one note, join them with `; `. `~/.claude/CLAUDE.md` is `active` in every mode except `managed-only`.

4. **Imported or symlinked AGENTS.md:** if an active counting file (`CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md`, at the root or in an ancestor) imports an `AGENTS.md` or `.claude/AGENTS.md` or is a symlink to it, mark that `AGENTS.md` `active` with the note "via CLAUDE.md", whatever the mode table says, even where it already marks it `active`. Its content reaches Claude through that file. An import is an `@path` reference outside Markdown code spans and fenced code blocks, and not wrapped in quotes (Claude Code skips all three). An import reached through other imported files also counts, within the docs' limit of four hops. Resolve a relative path from the folder of the file that contains it, so `@AGENTS.md` in `.claude/CLAUDE.md` names `.claude/AGENTS.md`, and the root `AGENTS.md` is `@../AGENTS.md` there. If the import resolves outside the project root, Claude Code treats it as an external import that loads only after the user approves it, so add "uncertain: external import" to the note. If the project-root `AGENTS.md` is itself a symlink to an active root `CLAUDE.md` (Bash: `readlink AGENTS.md`), treat it the same way, with the note "via CLAUDE.md (symlink, uncertain)": the docs describe only a `CLAUDE.md` that links to `AGENTS.md`. A subdirectory `CLAUDE.md` or `CLAUDE.local.md` that imports or is a symlink to the `AGENTS.md` in its own subdirectory makes that `AGENTS.md` `on demand` with the note "via CLAUDE.md", in every mode; in `managed-only` mode, where the docs leave out every `AGENTS.md`, an imported one gets the note "via CLAUDE.md; uncertain: managed-only import" instead.
5. **AGENTS.md support unavailable:** read `enabledPlugins` from `.claude/settings.local.json`, `.claude/settings.json`, and `~/.claude/settings.json`. For each of `cc-plugin-agents-md@builtin` and `agents-md@builtin`, the first of those files that sets the key wins (local > project > user). If either key ends up `false`, the built-in plugin that reads `AGENTS.md` is disabled. Mark every `AGENTS.md` `inactive` with the note "AGENTS.md plugin disabled (uncertain)", which replaces any reason note from the mode table (rule 4 still applies). The docs don't say which settings scopes count, and the exact `enabledPlugins` key is inferred from the plugin ID in the docs, so treat both as unconfirmed. Claude Code versions before v2.1.277 also never read `AGENTS.md`, nor do some sessions before v2.1.281 (such as Amazon Bedrock or telemetry disabled) and, in some cases, the first session after upgrading from v2.1.276 or earlier; this skill can't detect any of these, so don't guess.
6. **Active root file:** the file used for quality scoring. Use the project-root `CLAUDE.md` (else `.claude/CLAUDE.md`, else `CLAUDE.local.md`) if it is active. Otherwise use the project-root `AGENTS.md` (else `.claude/AGENTS.md`) if it is active. If neither is active, there is no active root file. When the chosen `CLAUDE.md` or `CLAUDE.local.md` imports or symlinks to `AGENTS.md`, score the combined content: the chosen file plus only the `AGENTS.md` files that rule 4 marks `active` through it, each counted once (a symlink and its target are one file). Other imports are not part of the scored content.
7. **Warnings** (add to Phase 3 Validation):
   - Default mode only (unlike `agentsMdIgnored` in 6b, which covers any mode), a counting file exists, and rule 4 does not apply to at least one root or ancestor `AGENTS.md`. Emit exactly one of these:
     - If the only counting files are `CLAUDE.local.md`: `[!] CLAUDE.local.md stops Claude Code from reading AGENTS.md — set instructionFiles to claude-md-and-agents-md to load both`.
     - Otherwise: `[!] AGENTS.md ignored by Claude Code: CLAUDE.md present (instructionFiles = claude-md-or-agents-md)`.
   - At least one root or ancestor instruction file exists, but none of them is active: `[!] No project instructions load for Claude Code (instructionFiles = <mode>)`. If rule 5 applies and the mode is `claude-md-or-agents-md` or `claude-md-and-agents-md` (so the disabled plugin is the cause), use `[!] No project instructions load for Claude Code: AGENTS.md plugin disabled` instead.

**Deferred tools enumeration:** At generation time, invoke `ToolSearch` with a broad query (e.g., `"*"` or `"list all"`) to enumerate currently deferred/lazy-loaded tools. For each tool returned, record its name, the MCP server it belongs to, and its description. If MCP servers are unavailable or ToolSearch returns an error, skip this step gracefully and note "Deferred tools: unable to query — MCP server unavailable" in the output.

**Background monitoring detection:** Search for Monitor tool usage in project automations:
- Grep project skills (`.claude/skills/*/SKILL.md`) for references to `Monitor` tool (case-insensitive: "Monitor", "monitor tool", "background monitor")
- Grep hook scripts referenced in `.claude/settings.json` for `run_in_background` patterns
- Check `.claude/settings.json` for any monitor-related configuration keys

This is detection-only — report where monitoring is configured, not whether monitors are currently running. Skip in global mode (project-scoped feature).

### Local scope

| Source file | Extract |
|-------------|---------|
| `.claude/settings.local.json` | Count of `permissions.allow` entries only (do NOT list individual entries) |

### Memory files

Claude Code stores per-project knowledge in memory files with YAML frontmatter.

| Source file | Extract |
|-------------|---------|
| `~/.claude/projects/<slug>/memory/MEMORY.md` | Index file — parse markdown links to map which files are referenced |
| `~/.claude/projects/<slug>/memory/*.md` (excluding MEMORY.md) | Each file's `name`, `description`, and `type` from YAML frontmatter |

**Deriving the project slug:** Convert the current project's absolute path to a slug by replacing path separators with `--` and drive letters with `{letter}-`. Example: `C:\Users\sneak\Documents\MyProject` becomes `C--Users-sneak-Documents-MyProject`.

If `~/.claude/projects/<slug>/memory/` does not exist, skip this section entirely.

### Settings conflict detection (project mode only)

In project mode, after reading all three settings files (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`), compare their top-level keys. For any key that appears in more than one scope, record:
- The key name
- The value at each scope (or null if absent)
- Which scope provides the effective value (most specific wins: local > project > global)

Skip this step entirely in global mode.

### Plugin-bundled content

**This step is critical and must always run, even if the project has no `.claude/` directory.**
Plugin-bundled content is global — it comes from `~/.claude/plugins/`, not from the project.

For each plugin listed in `enabledPlugins` other than `@builtin` keys (Claude Code's built-in plugins; rule 5 reads the AGENTS.md ones), look up its install path from `installed_plugins.json`.
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

### Plugin health analysis

After scanning plugin-bundled content, perform these additional checks:

1. **Orphaned versions:** For each plugin in `~/.claude/plugins/cache/` (both `claude-plugins-official/` and `local/` marketplaces), list all version subdirectories. Any version directory containing a `.orphaned_at` file is orphaned. Record:
   - Plugin name and marketplace
   - List of orphaned version strings
   - Disk usage of each orphaned version directory (use Bash: `du -sh <path>` — if this fails on Windows, skip disk usage and show "N/A")

2. **Enabled but not installed:** For each key in `enabledPlugins` from `~/.claude/settings.json`, other than `@builtin` keys (see Plugin-bundled content), check if a matching entry exists in `installed_plugins.json`. If not, record the plugin as "enabled but not installed."

3. **Update recency:** For each plugin in `installed_plugins.json`, check the `lastUpdated` field. If more than 30 days old (compared to the current date), flag as potentially stale.

### Hook execution order

When collecting hooks, track the order they will execute. Hooks fire in this sequence:

1. Global hooks from `~/.claude/settings.json` (array order within each event)
2. Plugin-bundled hooks from each enabled plugin's `hooks/hooks.json` (in the order plugins appear in `enabledPlugins`)
3. Project hooks from `.claude/settings.json` (array order within each event)

Assign a sequence number to each hook, resetting to 1 for each event type. This order determines the `#` column in the output tables.

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
| Memory file in `~/.claude/projects/<slug>/memory/` | `custom` |
| Plugin listed in `~/.claude/plugins/blocklist.json` | `blocked` |

---

## Phase 3 — Validation

Check that every referenced automation actually exists on disk. Collect warnings:

| Check | Method | Warning format |
|-------|--------|---------------|
| Hook scripts exist | Use Bash: `[ -f "<path>" ]` for each hook command path. Plugin path variables are not set in the Bash tool, so first strip shell quotes from the path, replace a `CLAUDE_PLUGIN_ROOT` reference with that plugin's install path from installed_plugins.json, replace a `CLAUDE_PLUGIN_DATA` reference with `$HOME/.claude/plugins/data/<id>/` (`<id>` is the plugin's `name@marketplace` key with every character other than a letter, digit, `_` or `-` replaced by `-`, so `my-plugin@my-marketplace` becomes `my-plugin-my-marketplace`), and in project mode replace a `CLAUDE_PROJECT_DIR` reference with the project root. Replace a leading `~/` with `$HOME/`, and leave ordinary shell variables such as `$HOME` for Bash to expand in the test. If the path still references a plugin variable that can't be resolved (such as `CLAUDE_PLUGIN_OPTION_<KEY>`, `CLAUDE_PLUGIN_ROOT` in a hook that isn't from a plugin, or `CLAUDE_PROJECT_DIR` in global mode), don't run the test; record that it was not checked | `[!] Hook script not found: <path>`; `[!] Hook script not checked (unresolved <variable>): <path>` |
| Skill SKILL.md exists | Confirm each discovered SKILL.md was readable | `[!] Skill file missing: <path>` |
| Plugin not orphaned | Check for `.orphaned_at` file in plugin install dir | `[!] Plugin orphaned since <date>` |
| Plugin dir exists | Verify install path from installed_plugins.json exists | `[!] Plugin directory not found: <path>` |
| MCP command available | Use Bash: `command -v <cmd>` for npx/node/etc. | `[!] MCP command not available: <cmd>` |
| Memory file not in index | Parse `MEMORY.md` links; check each `.md` file in `memory/` is referenced | `[!] Memory file not in MEMORY.md index: <filename>` |
| Index references missing file | For each link in `MEMORY.md`, check the target file exists in `memory/` | `[!] MEMORY.md references missing file: <filename>` |
| Instruction file activation | Apply the warning rules in [Instruction file activation](#instruction-file-activation) | `[!] AGENTS.md ignored by Claude Code: ...` and the other messages listed there |

Include all warnings in the Validation section of the output. If no warnings, omit the section.

---

## Phase 4 — Change Detection

If `.CLAUDE.inventory.json` already exists from a previous generation:

1. Read the existing JSON file
2. Build a set of `{name}:{scope}:{type}` keys from the old data
3. Build the same set from the newly discovered data

For memory files, use the key format `{filename}:memory:memory_file`. This ensures additions and removals of memory files appear in the Recent Changes section.

4. Items in new but not old → "Added"
5. Items in old but not new → "Removed"
6. Include a "Recent Changes" section at the top of the markdown

If no previous `.CLAUDE.inventory.json` exists (first run), skip this phase entirely.

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

### 6a. Write `.CLAUDE.inventory.md`

Write the inventory to the project root. Use this template structure, replacing
all `{placeholders}` with actual discovered data. Use the current date for the timestamp.

**CRITICAL:** Include the `inventory@local` plugin itself — its skill, command,
and SessionStart hook — in the appropriate sections. This file must document the
system that generates it.

```markdown
# Claude Code Automation Inventory

> Auto-generated by `inventory` plugin — {YYYY-MM-DD}
> Regenerate: `/inventory`

---

## Recent Changes

(Include only if Phase 4 detected changes. Otherwise omit this entire section.)

| Change | Item | Type | Scope | Date |
|--------|------|------|-------|------|
| + Added | {name} | {type} | {scope} | {date} |
| - Removed | {name} | {type} | {scope} | {date} |

---

## Global Scope (`~/.claude/`)

### Hooks (by execution order)

| # | Event | Command | Origin | Source | Description |
|---|-------|---------|--------|--------|-------------|
| {seq} | {event} | {script basename} | {custom/installed} | {global settings / plugin name} | {what it does} |

Sequence numbers reset to 1 for each event type. Order: global settings hooks first, then plugin-bundled hooks (in enabledPlugins order).

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

### Security

| Setting | Value | Scope |
|---------|-------|-------|
| Sandbox mode | {enabled (PID namespace) / enabled (basic) / disabled / N/A (not Linux)} | {global/project} |
| dangerouslySkipPermissions | {true/false} | {global} |
| Permission entries | {count from settings.local.json} | {local} |

(In global mode, omit the "Permission entries" row — `settings.local.json` is project-scoped and not read in global mode.)

If `dangerouslySkipPermissions` is `true`, add a warning note: "**Warning:** Permissions bypass is enabled. All tool calls execute without confirmation."

### Plugin Health

(Include only if orphaned versions, enabled-but-not-installed plugins, or stale plugins are detected. Otherwise omit.)

#### Orphaned Versions (cleanup candidates)

| Plugin | Orphaned Versions | Disk Usage |
|--------|-------------------|------------|
| {plugin name} | {count} old versions | {total size, e.g. "4.2 MB"} |

Total reclaimable: ~{sum} MB

(Omit this sub-section if no orphaned versions exist.)

#### Potential Issues

| Issue | Plugin | Details |
|-------|--------|---------|
| Enabled but not installed | {plugin name} | In enabledPlugins but not in installed_plugins.json |
| Not updated in 30+ days | {plugin name} | Last updated {YYYY-MM-DD} |

(Omit this sub-section if no issues detected.)

---

## Project Scope (`.claude/`)

### Hooks

| # | Event | Matcher | Action | Origin |
|---|-------|---------|--------|--------|
| {seq} | {event} | {matcher or "—"} | {what it does} | {custom/installed} |

Sequence numbers continue from the global hooks for the same event type. Project hooks always execute after global and plugin hooks.

### MCP Servers

| Name | Type | Package/URL | Origin | Loading |
|------|------|-------------|--------|---------|
| {name} | {npx/http/stdio} | {package or url} | {custom/installed} | {eager / deferred (N tools)} |

For the Loading column:
- **eager** — all tools loaded into context immediately
- **deferred (N tools)** — tools lazy-loaded via Tool Search; N is the count of deferred tools for this server

### Deferred Tools

(Include only if any MCP servers use deferred/lazy loading. Otherwise omit this sub-section.)

| Tool | MCP Server | Description |
|------|-----------|-------------|
| {tool name, e.g. mcp__github__create_issue} | {server name} | {tool description} |

If ToolSearch was unavailable at generation time, show: "Deferred tools: unable to query — MCP servers unavailable at generation time."

### Background Monitoring

(Include only if Monitor tool usage or run_in_background patterns are detected in project skills or hooks. Otherwise omit this sub-section. Skip in global mode.)

| Source | Type | What's Monitored |
|--------|------|-----------------|
| {file path relative to project} | {hook/skill} | {brief description of what's being monitored} |

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

## Memory Files

(Include only if `~/.claude/projects/<slug>/memory/` exists and contains `.md` files other than `MEMORY.md`. Otherwise omit this entire section.)

| File | Type | Description |
|------|------|-------------|
| {filename} | {type from frontmatter} | {description from frontmatter} |

Summary: {total} memory files ({N} user, {N} project, {N} feedback, {N} reference)

If any validation warnings were found for memory files (orphaned files or broken links), they will appear in the Validation section.

---

## Scheduled Tasks

(Include only if local scheduled tasks exist in `~/.claude/scheduled-tasks/` OR remote triggers were discovered via the MCP tool. Otherwise omit this entire section.)

| Task ID | Description | Schedule | Enabled | Source |
|---------|-------------|----------|---------|--------|
| {directory name or taskId} | {description} | {cron expression or fireAt timestamp} | {yes/no} | {local/remote} |

Note: Only persistent tasks (created via `mcp__scheduled-tasks__create_scheduled_task`) are listed. Session-only ephemeral jobs from `CronCreate` are not inventoried since they die with the session.

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

## Instruction Files

(Include only if at least one instruction file exists: global `~/.claude/CLAUDE.md`, or any `CLAUDE.md`, `CLAUDE.local.md`, or `AGENTS.md` at the project root, an ancestor, or a subdirectory. Otherwise omit this entire section.)

Mode: `{instructionFiles mode}` ({default / set in ~/.claude/settings.json / uncertain: <reason>})

Use the `uncertain: <reason>` form when `modeSource` is `conflict` or `invalid`. The reason names both conflicting values, or the invalid value.

### Hierarchy

List all discovered instruction files in load order (global, ancestors from the filesystem root down, project root, subdirectories). Within a directory, list `CLAUDE.md`, `.claude/CLAUDE.md`, and `CLAUDE.local.md` before `AGENTS.md`:

| Path | File | Lines | Scope | Status | Note |
|------|------|-------|-------|--------|------|
| ~/.claude/CLAUDE.md | CLAUDE.md | {line count} | global | active | |
| {ancestor}/CLAUDE.md | CLAUDE.md | {line count} | ancestor | active | |
| ./CLAUDE.md | CLAUDE.md | {line count} | project root | active | |
| ./AGENTS.md | AGENTS.md | {line count} | project root | inactive | CLAUDE.md present |
| ./{subdir}/AGENTS.md | AGENTS.md | {line count} | subdirectory | on demand | |

Status is computed by [Instruction file activation](#instruction-file-activation). Use the Note column for the reason a file is `inactive` and for "via CLAUDE.md" (imported or symlinked).
Only show rows for files that exist.

### Quality Score (active root file)

(Include this sub-section only if there is an active root file. Name it in the heading line, e.g. "Scoring `./AGENTS.md`".)

Score the active root file (`CLAUDE.md`, `CLAUDE.local.md`, or `AGENTS.md`) against these criteria by scanning for section headings containing relevant keywords (case-insensitive):

- **Dev commands**: headings with "commands", "scripts", "dev commands", "build", "run"
- **Architecture**: headings with "architecture", "structure", "overview", "design"
- **Gotchas**: headings with "gotchas", "known issues", "caveats", "warnings", "pitfalls"
- **Environment setup**: headings with "environment", "setup", "prerequisites", "requirements", "installation"
- **Conventions**: headings with "conventions", "style", "coding standards", "formatting", "naming"
- **Deployment**: headings with "deploy", "deployment", "release", "production" — mark "not applicable" if project has no deployment
- **Key file paths**: look for backtick-wrapped file paths (e.g., `src/`, `lib/`, `skills/`)
- **Length**: count lines of the scored content (rule 6's combined content when it applies) — ≤200 = good, 201-400 = long, >400 = excessive

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

If `claude-md-management` plugin is installed (check `enabledPlugins`), append: "Run `/claude-md-management:claude-md-improver` for detailed CLAUDE.md analysis and improvements." (If the active root file is `AGENTS.md`, say "instruction file" instead of "CLAUDE.md".)

---

## Settings Conflicts

(Project mode only. Include only if overlapping keys were found across scopes. Otherwise omit this entire section. Skip entirely in global mode.)

| Setting | Global | Project | Local | Effective |
|---------|--------|---------|-------|-----------|
| {key} | {value or "--"} | {value or "--"} | {value or "--"} | {value} ({winning scope}) |

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
| Generated by | `inventory@local` plugin (custom) |
| Schema version | 5 |
| Kept fresh by | SessionStart hook (regenerates on config change or >24h stale) |
| Gitignored | Yes — `.CLAUDE.inventory.md`, `.CLAUDE.inventory.json`, `.CLAUDE.inventory.hash` |
| JSON sidecar | `.CLAUDE.inventory.json` (machine-readable) |
| Self-documenting | This plugin, its skill, command, and hook appear in the inventory above |
```

### 6b. Write `.CLAUDE.inventory.json`

Write a machine-readable JSON sidecar to the project root with this structure:

```json
{
  "schemaVersion": 5,
  "generated": "ISO-8601 timestamp",
  "generator": "inventory@local",
  "scopes": {
    "global": {
      "hooks": [
        { "event": "...", "command": "...", "origin": "custom|installed", "source": "global settings|<plugin name>", "order": 1, "description": "..." }
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
        { "event": "...", "matcher": "...", "action": "...", "origin": "custom|installed", "order": 4 }
      ],
      "mcpServers": [
        { "name": "...", "type": "...", "package": "...", "origin": "custom|installed", "loading": "eager|deferred", "deferredToolCount": 0 }
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
  "pluginHealth": {
    "orphanedVersions": [
      { "plugin": "github", "marketplace": "claude-plugins-official", "versions": ["78497c524da3", "d5c15b861cd2"], "diskUsageMB": 4.2 }
    ],
    "enabledButNotInstalled": ["railway@claude-plugins-official"],
    "stalePlugins": [
      { "plugin": "claude-code-setup", "lastUpdated": "2026-03-15T14:27:30.313Z", "daysSinceUpdate": 27 }
    ],
    "totalReclaimableMB": 32.0
  },
  "memory": {
    "files": [
      { "filename": "user_environment.md", "type": "user", "name": "User Environment", "description": "Shell and tool PATH quirks" }
    ],
    "summary": { "total": 1, "user": 1, "project": 0, "feedback": 0, "reference": 0 },
    "orphaned": ["unlinked_note.md"],
    "brokenLinks": ["deleted_memory.md"]
  },
  "scheduledTasks": [
    {
      "taskId": "check-inbox",
      "description": "Check email for urgent items",
      "cronExpression": "0 9 * * 1-5",
      "fireAt": null,
      "enabled": true,
      "source": "local"
    }
  ],
  "mcpAuthState": [
    {
      "server": "Google Calendar",
      "needsAuthSince": "2026-03-16T04:30:15.584Z"
    }
  ],
  "keybindings": [],
  "instructionFiles": {
    "mode": "claude-md-or-agents-md",
    "modeSource": "default",
    "activeRootFile": "./AGENTS.md",
    "agentsMdIgnored": false
  },
  "claudeMdQuality": {
    "exists": true,
    "path": "./AGENTS.md",
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
  "claudeMdHierarchy": [
    { "path": "~/.claude/CLAUDE.md", "file": "CLAUDE.md", "lines": 12, "scope": "global", "status": "active", "note": null },
    { "path": "./AGENTS.md", "file": "AGENTS.md", "lines": 85, "scope": "project_root", "status": "active", "note": null },
    { "path": "./packages/api/AGENTS.md", "file": "AGENTS.md", "lines": 24, "scope": "subdirectory", "status": "on_demand", "note": null }
  ],
  "settingsConflicts": [
    {
      "key": "effortLevel",
      "global": "high",
      "project": "low",
      "local": null,
      "effective": "low",
      "effectiveScope": "project"
    }
  ],
  "deferredTools": [
    { "tool": "mcp__github__create_issue", "server": "github", "description": "Create a new issue" },
    { "tool": "mcp__github__list_prs", "server": "github", "description": "List pull requests" }
  ],
  "monitoring": [
    { "source": "hooks/test-watcher.sh", "type": "hook", "description": "Test suite output (PostToolUse)" },
    { "source": "skills/deploy/SKILL.md", "type": "skill", "description": "Deployment log streaming" }
  ],
  "security": {
    "sandboxMode": "pid_namespace",
    "dangerouslySkipPermissions": false,
    "permissionCount": 127,
    "os": "linux"
  },
  "validation": [
    { "level": "warning", "item": "...", "message": "..." }
  ],
  "recommendations": [
    { "type": "...", "name": "...", "reason": "...", "priority": "Low|Medium|High" }
  ]
}
```

**Schema version 5** adds the `instructionFiles` object, adds `path` to `claudeMdQuality` (the active root file's relative path, e.g. `./AGENTS.md`), and adds `file`, `status` (`active` / `on_demand` / `inactive`), and `note` to each `claudeMdHierarchy` entry. A hierarchy entry's `file` is always the bare filename, exactly one of `CLAUDE.md`, `CLAUDE.local.md`, or `AGENTS.md`. Its location goes in `path`, including `.claude/` locations (e.g. `path` `./.claude/CLAUDE.md` with `file` `CLAUDE.md`). Hierarchy entries now include `AGENTS.md` and `CLAUDE.local.md` files and the `ancestor` scope. An `ancestor` entry's `path` is the file's absolute path, with forward slashes on every platform, a Windows drive written as `C:/`, and the home directory written as `~/` (e.g. `~/code/CLAUDE.md`, `/srv/CLAUDE.md`, `C:/srv/CLAUDE.md`). The `claudeMdQuality` and `claudeMdHierarchy` key names are kept for compatibility, though they now cover `AGENTS.md` too. `instructionFiles.modeSource` is `default`, `user_settings`, `conflict` (both `pluginConfigs` IDs are set and differ), or `invalid` (the value is not one of the four modes). In both of the last two cases, `mode` holds the mode used for activation. `activeRootFile` is the same value as `claudeMdQuality.path` (e.g. `./.claude/CLAUDE.md`), or `null` when no root file is active. `agentsMdIgnored` is `true` when a root or ancestor `AGENTS.md` exists and is `inactive` for any reason (a CLAUDE.md-family file is present, the mode is `claude-md` or `managed-only`, or the plugin is disabled), and `false` otherwise. `claudeMdQuality.exists` is `true` only when there is an active root file; when it is `false`, the other `claudeMdQuality` fields are omitted. `claudeMdQuality.lineCount` is the Length criterion's count of the scored content, so it can exceed the root file's own `claudeMdHierarchy` `lines`.

### 6c. Write `.CLAUDE.inventory.hash`

Compute a hash of the key config files for staleness detection. Try the Bash approach
first — if Bash is unavailable or fails, fall back to a Python one-liner, and if that
also fails, write a timestamp-based fallback. The hash does NOT need to be
cryptographically secure — it just needs to change when configs change.

**Approach 1 — Bash (preferred):**
```bash
hash_input=$(cat ~/.claude/settings.json ~/.claude/plugins/installed_plugins.json .claude/settings.json 2>/dev/null; ls ~/.claude/skills/ .claude/skills/ 2>/dev/null | sort; ls ~/.claude/projects/*/memory/ 2>/dev/null | sort; ls ~/.claude/scheduled-tasks/ 2>/dev/null | sort; find ~/.claude/plugins/cache/ -name '.orphaned_at' 2>/dev/null | sort)
printf '%s' "$hash_input" | md5sum | cut -d' ' -f1
```

**Approach 2 — Python fallback (if Bash fails or is restricted):**
```python
import hashlib, os, glob
files = [os.path.expanduser("~/.claude/settings.json"), os.path.expanduser("~/.claude/plugins/installed_plugins.json"), ".claude/settings.json"]
data = ""
for f in files:
    try: data += open(f).read()
    except: pass
for d in [os.path.expanduser("~/.claude/skills"), ".claude/skills", os.path.expanduser("~/.claude/scheduled-tasks")]:
    try: data += "\n".join(sorted(os.listdir(d)))
    except: pass
for pattern in [os.path.expanduser("~/.claude/projects/*/memory/")]:
    try: data += "\n".join(sorted(glob.glob(pattern + "*.md")))
    except: pass
for f in sorted(glob.glob(os.path.expanduser("~/.claude/plugins/cache/**/.orphaned_at"), recursive=True)):
    try: data += f
    except: pass
print(hashlib.md5(data.encode()).hexdigest())
```

**Approach 3 — Timestamp fallback (last resort):**
If neither Bash nor Python can compute a hash, write the current ISO-8601 timestamp
instead. This means the hook will always see a "changed" hash and prompt regeneration,
which is the safe default.

Write the resulting hash string (or timestamp) to `.CLAUDE.inventory.hash`.

**IMPORTANT:** Verify the hash is not the MD5 of an empty string (`d41d8cd98f00b204e9800998ecf8427e`
or `e3b0c44298fc1c149afbf4c8996fb924` for SHA-256). If it is, the computation failed —
fall back to the next approach.

---

## Phase 7 — Gitignore

Idempotent check — only append if not already present:

```bash
grep -qF '.CLAUDE.inventory' .gitignore 2>/dev/null
```

If not found, append:

```gitignore

# Automation inventory (auto-generated by inventory plugin)
.CLAUDE.inventory.md
.CLAUDE.inventory.json
.CLAUDE.inventory.hash
```

---

## Edge Cases

- **Not a git repo:** Still generate the inventory files. Skip the gitignore step.
- **No project `.claude/` directory:** Show "No project-level automations configured" under Project Scope.
- **No `settings.local.json`:** Show "No local overrides" under Local Scope.
- **Plugin install path missing:** Record `[!] Plugin directory not found` in Validation.
- **Plugin has `.orphaned_at`:** Record `[!] Plugin orphaned since <date>` in Validation.
- **Empty blocklist:** Omit the Blocked Plugins section entirely.
- **No previous `.CLAUDE.inventory.json` (first run):** Skip change detection, omit Recent Changes.
- **No `pyproject.toml` or `package.json`:** Omit Recommendations or provide generic suggestions.
- **Skill frontmatter missing `description`:** Use the skill directory name as fallback.
- **No instruction files at all:** Omit the entire Instruction Files section (no `CLAUDE.md`, `CLAUDE.local.md`, or `AGENTS.md` anywhere, and no global `~/.claude/CLAUDE.md`).
- **Only global CLAUDE.md exists:** Show hierarchy table with just the global row. Omit Quality Score sub-section.
- **Only AGENTS.md at the project root and no counting file in an ancestor directory (default mode):** `AGENTS.md` is `active` and is the active root file. Score it.
- **Both CLAUDE.md and AGENTS.md at the project root (default mode):** `CLAUDE.md` is `active` and scored. `AGENTS.md` is `inactive` with a Validation warning, unless `CLAUDE.md` imports `@AGENTS.md` or is a symlink to it (then `AGENTS.md` is `active` "via CLAUDE.md" and no warning). If `AGENTS.md` is a symlink to `CLAUDE.md`, it is `active` "via CLAUDE.md (symlink, uncertain)" and there is no warning.
- **CLAUDE.md only in an ancestor directory:** It counts. Project `AGENTS.md` files are `inactive` in default mode, unless rule 4 applies.
- **Only AGENTS.md exists and mode is `claude-md` or `managed-only`:** List it as `inactive`. Omit the Quality Score sub-section and record the "No project instructions load" warning.
- **`instructionFiles` set only in project or local settings:** Ignore it for activation (Claude Code does) and record a warning.
- **`~/.claude/AGENTS.md` exists:** Not a documented global file, so do not list it as global. If the home directory is the project root or an ancestor of it, the docs' rule (`.claude/AGENTS.md` in the working directory and the directories above it) covers it: list it as the project-root `.claude/AGENTS.md` row or an `ancestor` row with the usual status and Note "uncertain: home-directory .claude/AGENTS.md".
- **No memory directory for this project:** Omit the Memory Files section entirely.
- **Memory directory exists but is empty:** Omit the Memory Files section.
- **MEMORY.md index missing but memory files exist:** List the files, report all as orphaned in Validation.
- **Memory file has no YAML frontmatter:** Use the filename (without `.md`) as the name, "unknown" as the type, and "No frontmatter" as the description.
- **No `~/.claude/scheduled-tasks/` directory:** Omit the Scheduled Tasks section entirely.
- **Task subdirectory exists but has no definition file:** Record `[!] Scheduled task has no definition: <taskId>` in Validation. Still list the task with "unknown" description.
- **Task definition format unrecognized:** List the task ID but mark description as "Unable to parse task definition".
- **No settings conflicts (all keys unique per scope):** Omit the Settings Conflicts section entirely.
- **Global mode:** Skip settings conflict detection entirely (only one scope to read).
- **MCP scheduled-tasks server unavailable:** Fall back to filesystem-only discovery. All tasks shown as `source: local`. Do not show an error — degrade gracefully.
- **Remote task has same taskId as local task:** Show both rows with different source values. This is an unusual state but not an error.
- **No MCP servers configured:** MCP Servers table shows "No MCP servers configured." Deferred Tools sub-section omitted.
- **ToolSearch unavailable at generation time:** Show MCP Servers table without Loading column data (or mark all as "unknown"). Show note instead of Deferred Tools table.
- **All MCP servers use eager loading:** Omit the Deferred Tools sub-section. Loading column shows "eager" for all.
- **Global mode:** Deferred Tools section is omitted (MCP servers are project-scoped).
- **No Monitor tool usage detected:** Omit the Background Monitoring sub-section entirely.
- **Hook script references run_in_background but doesn't use Monitor:** Still list it — the pattern suggests background process management even without explicit Monitor tool usage.
- **Global mode:** Skip monitoring detection entirely (project-scoped feature).
