# Inventory Plugin v2.0 "Global View" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break the inventory out of the project directory — add a global standalone skill (`/inventory-global`), cross-project comparison (`/inventory-compare`), settings conflict detection, and remote triggers inventory.

**Architecture:** The existing `SKILL.md` gains a mode parameter (project vs global). Two new command files route to the skill with the appropriate mode. Cross-project comparison is a separate output file (`~/.claude/.CLAUDE.cross-project.md`). Settings conflicts and remote triggers are additive sections within the existing project-mode template. JSON schema bumps to version 3.

**Tech Stack:** Markdown (SKILL.md prompt, command files), Bash (hook script), JSON (plugin metadata, evals)

**Key files:**
- `skills/inventory/SKILL.md` — core prompt (~682 lines, all features modify this)
- `commands/inventory-global.md` — NEW: slash command for global-only mode
- `commands/inventory-compare.md` — NEW: slash command for cross-project comparison
- `.claude-plugin/plugin.json` — version bump to 2.0.0
- `evals/evals.json` — new test scenarios

---

## Task 1: Mode Parameter — Global vs Project

Add a mode concept to the SKILL.md so it can operate in either project mode (existing behavior) or global mode (new).

**Files:**
- Modify: `skills/inventory/SKILL.md:1-27` (frontmatter and intro)
- Modify: `skills/inventory/SKILL.md:29-31` (Phase 1 opening)

- [ ] **Step 1: Update SKILL.md frontmatter to describe both modes**

In `skills/inventory/SKILL.md`, replace the frontmatter description (lines 3-10):

Old:
```yaml
description: >
  Generate or update .CLAUDE.inventory.md — a comprehensive inventory of all
  Claude Code automations (hooks, skills, plugins, agents, MCP servers) ordered
  by scope, with each item tagged as installed or custom. Use when the user says
  "update automatons", "list my automations", "what skills/hooks do I have",
  "refresh automation inventory", or when the SessionStart hook reports the
  inventory is missing or stale. Also run after /claude-code-setup:claude-automation-recommender
  to capture new recommendations.
```

New:
```yaml
description: >
  Generate or update automation inventory files. Operates in two modes:
  **Project mode** (default, invoked via `/inventory`): scans global + project + local
  scopes, writes `.CLAUDE.inventory.md` to the project root.
  **Global mode** (invoked via `/inventory-global`): scans global scope only,
  writes `.CLAUDE.inventory.md` to `~/.claude/`.
  Use when the user says "update automatons", "list my automations", "what skills/hooks
  do I have", "refresh automation inventory", or when the SessionStart hook reports
  the inventory is missing or stale.
```

- [ ] **Step 2: Add mode determination section after the "When to Run" block**

After the "When to Run" section (around line 27), add:

```markdown

## Mode

This skill operates in one of two modes based on how it was invoked:

- **Project mode** (default): Invoked via `/inventory`. Scans global + project + local scopes. Writes output to the current project root. Requires being inside a project directory.
- **Global mode**: Invoked via `/inventory-global`. Scans global scope only — skips all project-scope and local-scope reads. Writes output to `~/.claude/`. Works from any directory.

The mode determines which Phase 1 discovery sources are read, which Phase 6 output sections are generated, and where output files are written.

**In Global mode, skip these entirely:**
- Phase 1: Project scope, Local scope, Memory files (project-specific)
- Phase 5: Recommendations (requires project tech stack detection)
- Phase 6a: Project Scope section, Local Scope section, Memory Files section, CLAUDE.md Quality Score sub-section (hierarchy table still shows global CLAUDE.md if it exists), Settings Conflicts section
- Phase 6a header: Use `> Regenerate: \`/inventory-global\`` instead of `> Regenerate: \`/inventory\``
- Phase 6a output path: Write to `~/.claude/.CLAUDE.inventory.md` instead of project root
- Phase 6b output path: Write to `~/.claude/.CLAUDE.inventory.json` instead of project root
- Phase 6c output path: Write to `~/.claude/.CLAUDE.inventory.hash` instead of project root
- Phase 7: Skip gitignore step (not in a project)
```

- [ ] **Step 3: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.0): add project/global mode parameter to SKILL.md"
```

---

## Task 2: Global Standalone Command

Create the `/inventory-global` slash command that invokes the skill in global mode.

**Files:**
- Create: `commands/inventory-global.md`

- [ ] **Step 1: Create the command file**

Create `commands/inventory-global.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/inventory-global.md
git commit -m "feat(v2.0): add /inventory-global slash command"
```

---

## Task 3: Settings Conflict Detection

Add settings conflict detection to Phase 1 discovery and Phase 6a output for project mode.

**Files:**
- Modify: `skills/inventory/SKILL.md` Phase 1 (add settings conflict discovery)
- Modify: `skills/inventory/SKILL.md` Phase 6a (add output section)
- Modify: `skills/inventory/SKILL.md` Phase 6b (add JSON key)
- Modify: `skills/inventory/SKILL.md` Edge Cases

- [ ] **Step 1: Add settings conflict discovery to Phase 1**

In `skills/inventory/SKILL.md`, after the Memory files section in Phase 1 (after line 73, before `### Plugin-bundled content`), add:

```markdown

### Settings conflict detection (project mode only)

In project mode, after reading all three settings files (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`), compare their top-level keys. For any key that appears in more than one scope, record:
- The key name
- The value at each scope (or null if absent)
- Which scope provides the effective value (most specific wins: local > project > global)

Skip this step entirely in global mode.
```

- [ ] **Step 2: Add Settings Conflicts output section to Phase 6a**

In `skills/inventory/SKILL.md`, after the CLAUDE.md Quality section (around line 443) and before the Validation section (around line 447), add:

```markdown

---

## Settings Conflicts

(Project mode only. Include only if overlapping keys were found across scopes. Otherwise omit this entire section. Skip entirely in global mode.)

| Setting | Global | Project | Local | Effective |
|---------|--------|---------|-------|-----------|
| {key} | {value or "--"} | {value or "--"} | {value or "--"} | {value} ({winning scope}) |
```

- [ ] **Step 3: Add settingsConflicts to Phase 6b JSON sidecar**

In the JSON sidecar template, after the `claudeMdHierarchy` block (around line 586) and before `"validation"`, add:

```json
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
```

- [ ] **Step 4: Add edge cases**

In the Edge Cases section, add:

```markdown
- **No settings conflicts (all keys unique per scope):** Omit the Settings Conflicts section entirely.
- **Global mode:** Skip settings conflict detection entirely (only one scope to read).
```

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.0): add settings conflict detection across scopes"
```

---

## Task 4: Remote Triggers Inventory

Extend the Scheduled Tasks section with a Source column distinguishing local vs remote tasks.

**Files:**
- Modify: `skills/inventory/SKILL.md` Phase 1 (add remote trigger discovery)
- Modify: `skills/inventory/SKILL.md` Phase 6a (update scheduled tasks table)
- Modify: `skills/inventory/SKILL.md` Phase 6b (add source field to JSON)

- [ ] **Step 1: Add remote trigger discovery to Phase 1**

In `skills/inventory/SKILL.md`, after the scheduled tasks discovery row in the global scope table (line 44), add a new paragraph:

```markdown

**Remote triggers:** In addition to reading the filesystem, also invoke `mcp__scheduled-tasks__list_scheduled_tasks` at generation time to query active remote triggers managed by Anthropic's infrastructure. If the MCP server is unavailable, fall back to filesystem-only discovery. For each task returned by the MCP tool that doesn't match a local filesystem task (by taskId), mark it as `source: "remote"`.
```

- [ ] **Step 2: Update Scheduled Tasks output table in Phase 6a**

In `skills/inventory/SKILL.md`, replace the Scheduled Tasks table (around lines 366-368):

Old:
```markdown
| Task ID | Description | Schedule | Enabled |
|---------|-------------|----------|---------|
| {directory name} | {description from task definition} | {cron expression or fireAt timestamp} | {yes/no} |
```

New:
```markdown
| Task ID | Description | Schedule | Enabled | Source |
|---------|-------------|----------|---------|--------|
| {directory name or taskId} | {description} | {cron expression or fireAt timestamp} | {yes/no} | {local/remote} |
```

- [ ] **Step 3: Verify JSON sidecar already has source field**

The `scheduledTasks` JSON entry already includes `"source": "local"` from v1.2. No change needed — remote tasks will use `"source": "remote"`.

- [ ] **Step 4: Add edge cases**

In the Edge Cases section, add:

```markdown
- **MCP scheduled-tasks server unavailable:** Fall back to filesystem-only discovery. All tasks shown as `source: local`. Do not show an error — degrade gracefully.
- **Remote task has same taskId as local task:** Show both rows with different source values. This is an unusual state but not an error.
```

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.0): add remote triggers to scheduled tasks inventory"
```

---

## Task 5: Cross-Project Comparison Command

Create the `/inventory-compare` command and add the cross-project comparison logic to SKILL.md.

**Files:**
- Create: `commands/inventory-compare.md`
- Modify: `skills/inventory/SKILL.md` (add cross-project comparison as a separate mode/phase)

- [ ] **Step 1: Create the command file**

Create `commands/inventory-compare.md`:

```markdown
---
description: "Compare automations across all projects — generates ~/.claude/.CLAUDE.cross-project.md"
---

Run a cross-project comparison of Claude Code automations. This is a separate analysis
from the per-project or global inventory.

## Instructions

1. List all directories in `~/.claude/projects/`
2. Filter out worktree slugs: exclude any slug containing `--claude-worktrees-`
3. Reverse-map each slug to a filesystem path:
   - The slug uses `--` as path separator. `C--Users-sneak-Documents-Foo` maps to `C:\Users\sneak\Documents\Foo` (Windows) or the equivalent Unix path
   - Verify each resolved path exists on disk before including
4. Performance guard: if more than 50 non-worktree slugs exist, warn the user and process only the 50 most recently modified (by directory mtime)
5. For each resolved project path that exists on disk:
   - Read `<path>/.claude/settings.json` → count hooks (array length per event) and MCP servers (object key count)
   - Glob `<path>/.claude/skills/*/SKILL.md` → count skills
   - Glob `<path>/.claude/agents/*.md` → count agents
   - Check `<path>/CLAUDE.md` exists; if so, count lines and run the 8-criteria quality score
   - Count memory files from `~/.claude/projects/<slug>/memory/` (exclude MEMORY.md)
6. Generate a comparison table and inconsistency report

## Output

Write two files:

### ~/.claude/.CLAUDE.cross-project.md

```markdown
# Cross-Project Comparison

> Auto-generated by `inventory` plugin — {YYYY-MM-DD}
> Regenerate: `/inventory-compare`

## Summary

| Feature | {project1 name} | {project2 name} | ... |
|---------|-----------------|-----------------|-----|
| Hooks | {count} | {count} | ... |
| MCP servers | {count} | {count} | ... |
| Skills | {count} | {count} | ... |
| Agents | {count} | {count} | ... |
| Memory files | {count} | {count} | ... |
| CLAUDE.md | {yes (score/8) / no} | ... | ... |

Use the project directory name (last path segment) as the column header, not the full slug.

## Inconsistencies

| Issue | Projects Affected | Details |
|-------|-------------------|---------|
| No CLAUDE.md | {project names} | Missing project instructions |
| No hooks | {project names} | No automation hooks configured |

If no inconsistencies detected, show "No inconsistencies detected across {N} projects."
```

### ~/.claude/.CLAUDE.cross-project.json

```json
{
  "generatedAt": "ISO-8601",
  "generator": "inventory@local",
  "projects": [
    {
      "slug": "C--Users-sneak-Documents-BratBot",
      "path": "C:\\Users\\sneak\\Documents\\BratBot",
      "name": "BratBot",
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
```

## Edge Cases

- Path with hyphens in directory name: the slug reversal is ambiguous. Verify resolved path exists on disk. If not, skip the project with a warning.
- No `~/.claude/projects/` directory: show "No projects found."
- All slugs are worktrees: show "No non-worktree projects found."
- Project path exists but has no `.claude/` directory: show zeros for all counts, CLAUDE.md = no.
```

- [ ] **Step 2: Commit**

```bash
git add commands/inventory-compare.md
git commit -m "feat(v2.0): add /inventory-compare cross-project comparison command"
```

---

## Task 6: Schema Version Bump and Metadata

Bump JSON schema to version 3, update plugin version, add evals, update docs.

**Files:**
- Modify: `skills/inventory/SKILL.md:472,485` (schema version references)
- Modify: `.claude-plugin/plugin.json` (version bump)
- Modify: `evals/evals.json` (new scenarios)
- Modify: `CLAUDE.md` (version, structure)

- [ ] **Step 1: Update schema version in SKILL.md**

In `skills/inventory/SKILL.md`, change the two schema version references:

Line 472 (About This File table): change `| Schema version | 2 |` to `| Schema version | 3 |`

Line 485 (JSON sidecar): change `"schemaVersion": 2,` to `"schemaVersion": 3,`

- [ ] **Step 2: Bump plugin version**

In `.claude-plugin/plugin.json`, change `"version": "1.2.0"` to `"version": "2.0.0"`.

- [ ] **Step 3: Add new eval scenarios**

In `evals/evals.json`, add two entries after the existing id:4 entry:

```json
    {
      "id": 5,
      "prompt": "Generate a global-only inventory of my Claude Code setup. I want to see just my global plugins, skills, hooks, and settings — no project-specific stuff.",
      "expected_output": "A ~/.claude/.CLAUDE.inventory.md file containing only Global Scope sections: hooks, skills, plugins, plugin-bundled content, blocked plugins, settings, plugin health. No Project Scope, Local Scope, Memory Files, or Recommendations sections. Header shows 'Regenerate: /inventory-global'. JSON sidecar at ~/.claude/.CLAUDE.inventory.json with schemaVersion: 3.",
      "files": [],
      "assertions": []
    },
    {
      "id": 6,
      "prompt": "Compare the automations across all my projects. Show me what each project has and flag any inconsistencies.",
      "expected_output": "A ~/.claude/.CLAUDE.cross-project.md file with a Summary table showing counts (hooks, MCP servers, skills, agents, memory files, CLAUDE.md status) per project, plus an Inconsistencies table flagging projects missing CLAUDE.md or hooks. Worktree slugs filtered out. JSON sidecar at ~/.claude/.CLAUDE.cross-project.json.",
      "files": [],
      "assertions": []
    }
```

- [ ] **Step 4: Update CLAUDE.md**

In `CLAUDE.md`, change `**Version:** 1.2.0` to `**Version:** 2.0.0`.

Add the two new command files to the repository structure tree:

```
├── commands/
│   ├── inventory.md             # /inventory slash command
│   ├── inventory-global.md      # /inventory-global slash command (v2.0)
│   └── inventory-compare.md     # /inventory-compare slash command (v2.0)
```

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md .claude-plugin/plugin.json evals/evals.json CLAUDE.md
git commit -m "chore(v2.0): bump version to 2.0.0, schema to 3, add evals and docs"
```

---

## Task 7: Integration Verification

Verify the v2.0 implementation by running commands and checking output.

**Files:**
- None modified — verification only

- [ ] **Step 1: Run `/inventory` (project mode)**

Invoke `/inventory` to verify existing project-mode behavior is unchanged. Confirm:
- Output goes to project root (not `~/.claude/`)
- Settings Conflicts section appears if any conflicts exist, or is omitted
- Scheduled Tasks includes a Source column
- `schemaVersion: 3` in JSON sidecar
- No regressions in v1.2 sections

- [ ] **Step 2: Run `/inventory-global` (global mode)**

Invoke `/inventory-global` to verify global-only behavior. Confirm:
- Output goes to `~/.claude/.CLAUDE.inventory.md`
- Only global-scope sections appear (no Project Scope, Local Scope, Memory Files)
- Header says "Regenerate: `/inventory-global`"
- JSON sidecar at `~/.claude/.CLAUDE.inventory.json` with `schemaVersion: 3`
- Recommendations section is omitted

- [ ] **Step 3: Run `/inventory-compare` (cross-project mode)**

Invoke `/inventory-compare` to verify cross-project comparison. Confirm:
- Output goes to `~/.claude/.CLAUDE.cross-project.md`
- Summary table lists projects with correct counts
- Worktree slugs are filtered out
- Inconsistencies table flags relevant issues
- JSON sidecar at `~/.claude/.CLAUDE.cross-project.json`

- [ ] **Step 4: Final commit if fixes needed**

```bash
git add -A
git commit -m "fix(v2.0): address integration verification findings"
```
