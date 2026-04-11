# Inventory Plugin v2.1 "Capabilities" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track newer Claude Code primitives — Tool Search/deferred tools, Monitor tool usage, and sandbox configuration — positioning the inventory as the definitive view of the full Claude Code surface area.

**Architecture:** All 3 features are additive to the existing 7-phase SKILL.md structure. Each adds discovery sources (Phase 1) and output sections (Phase 6). No architectural changes — same pattern as v1.2. JSON schema bumps to version 4.

**Tech Stack:** Markdown (SKILL.md prompt), JSON (plugin metadata, evals)

**Key files:**
- `skills/inventory/SKILL.md` — core prompt (all 3 features modify this)
- `.claude-plugin/plugin.json` — version bump to 2.1.0
- `evals/evals.json` — new test scenarios

**Prerequisite:** v2.0 must be implemented first (SKILL.md references v2.0 structures).

---

## Task 1: Tool Search / Deferred Tools Inventory

Add a Loading column to the MCP Servers table and a new Deferred Tools sub-section.

**Files:**
- Modify: `skills/inventory/SKILL.md` Phase 1 project scope (MCP discovery)
- Modify: `skills/inventory/SKILL.md` Phase 6a (MCP Servers table + new sub-section)
- Modify: `skills/inventory/SKILL.md` Phase 6b (JSON sidecar)
- Modify: `skills/inventory/SKILL.md` Edge Cases

- [ ] **Step 1: Add deferred tools discovery to Phase 1 project scope**

In `skills/inventory/SKILL.md`, after the `.claude/settings.json` row in the project scope table (which currently reads `hooks (all events + matchers), mcpServers (all entries)`), update the mcpServers extract description. Replace the row:

Old:
```markdown
| `.claude/settings.json` | `hooks` (all events + matchers), `mcpServers` (all entries) |
```

New:
```markdown
| `.claude/settings.json` | `hooks` (all events + matchers), `mcpServers` (all entries — for each server, check if it has `toolSearch` or deferred tool configuration to determine loading strategy) |
```

Then add a new paragraph after the project scope table:

```markdown

**Deferred tools enumeration:** At generation time, invoke `ToolSearch` with a broad query (e.g., `"*"` or `"list all"`) to enumerate currently deferred/lazy-loaded tools. For each tool returned, record its name, the MCP server it belongs to, and its description. If MCP servers are unavailable or ToolSearch returns an error, skip this step gracefully and note "Deferred tools: unable to query — MCP server unavailable" in the output.
```

- [ ] **Step 2: Update MCP Servers table in Phase 6a**

In `skills/inventory/SKILL.md`, replace the MCP Servers table in the Project Scope section:

Old:
```markdown
### MCP Servers

| Name | Type | Package/URL | Origin |
|------|------|-------------|--------|
| {name} | {npx/http/stdio} | {package or url} | {custom/installed} |
```

New:
```markdown
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
```

- [ ] **Step 3: Add deferredTools to Phase 6b JSON sidecar**

In the JSON sidecar template, after the `settingsConflicts` block (added by v2.0) and before `"validation"`, add:

```json
  "deferredTools": [
    { "tool": "mcp__github__create_issue", "server": "github", "description": "Create a new issue" },
    { "tool": "mcp__github__list_prs", "server": "github", "description": "List pull requests" }
  ],
```

- [ ] **Step 4: Add edge cases**

In the Edge Cases section, add:

```markdown
- **No MCP servers configured:** MCP Servers table shows "No MCP servers configured." Deferred Tools sub-section omitted.
- **ToolSearch unavailable at generation time:** Show MCP Servers table without Loading column data (or mark all as "unknown"). Show note instead of Deferred Tools table.
- **All MCP servers use eager loading:** Omit the Deferred Tools sub-section. Loading column shows "eager" for all.
- **Global mode:** Deferred Tools section is omitted (MCP servers are project-scoped).
```

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.1): add deferred tools inventory with Tool Search integration"
```

---

## Task 2: Monitor Tool Tracking

Detect Monitor tool usage in project skills and hooks.

**Files:**
- Modify: `skills/inventory/SKILL.md` Phase 1 (add discovery)
- Modify: `skills/inventory/SKILL.md` Phase 6a (add output section)
- Modify: `skills/inventory/SKILL.md` Phase 6b (add JSON key)
- Modify: `skills/inventory/SKILL.md` Edge Cases

- [ ] **Step 1: Add monitoring discovery to Phase 1 project scope**

In `skills/inventory/SKILL.md`, after the deferred tools enumeration paragraph (added in Task 1), add:

```markdown

**Background monitoring detection:** Search for Monitor tool usage in project automations:
- Grep project skills (`.claude/skills/*/SKILL.md`) for references to `Monitor` tool (case-insensitive: "Monitor", "monitor tool", "background monitor")
- Grep hook scripts referenced in `.claude/settings.json` for `run_in_background` patterns
- Check `.claude/settings.json` for any monitor-related configuration keys

This is detection-only — report where monitoring is configured, not whether monitors are currently running. Skip in global mode (project-scoped feature).
```

- [ ] **Step 2: Add Background Monitoring output section to Phase 6a**

In `skills/inventory/SKILL.md`, after the Deferred Tools sub-section (added in Task 1) and before the Skills section in Project Scope, add:

```markdown

### Background Monitoring

(Include only if Monitor tool usage or run_in_background patterns are detected in project skills or hooks. Otherwise omit this sub-section. Skip in global mode.)

| Source | Type | What's Monitored |
|--------|------|-----------------|
| {file path relative to project} | {hook/skill} | {brief description of what's being monitored} |
```

- [ ] **Step 3: Add monitoring to Phase 6b JSON sidecar**

In the JSON sidecar template, after the `deferredTools` block (added in Task 1) and before `"validation"`, add:

```json
  "monitoring": [
    { "source": "hooks/test-watcher.sh", "type": "hook", "description": "Test suite output (PostToolUse)" },
    { "source": "skills/deploy/SKILL.md", "type": "skill", "description": "Deployment log streaming" }
  ],
```

- [ ] **Step 4: Add edge cases**

In the Edge Cases section, add:

```markdown
- **No Monitor tool usage detected:** Omit the Background Monitoring sub-section entirely.
- **Hook script references run_in_background but doesn't use Monitor:** Still list it — the pattern suggests background process management even without explicit Monitor tool usage.
- **Global mode:** Skip monitoring detection entirely (project-scoped feature).
```

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.1): add monitor tool tracking in project automations"
```

---

## Task 3: Sandbox Configuration

Report the current sandboxing and security posture.

**Files:**
- Modify: `skills/inventory/SKILL.md` Phase 1 (add discovery)
- Modify: `skills/inventory/SKILL.md` Phase 6a (add output section)
- Modify: `skills/inventory/SKILL.md` Phase 6b (add JSON key)

- [ ] **Step 1: Add security posture discovery to Phase 1 global scope**

In `skills/inventory/SKILL.md`, add a row to the global scope discovery table (after the scheduled-tasks row):

```markdown
| `~/.claude/settings.json` (security keys) | Check for `sandboxMode`, `dangerouslySkipPermissions`, and any sandbox-related configuration. Also detect the OS via `uname -s` to determine if PID namespace isolation is available (Linux only). |
```

- [ ] **Step 2: Add Security output section to Phase 6a**

In `skills/inventory/SKILL.md`, after the `### Settings` section (which currently just shows effortLevel) and before `### Plugin Health`, add:

```markdown

### Security

| Setting | Value | Scope |
|---------|-------|-------|
| Sandbox mode | {enabled (PID namespace) / enabled (basic) / disabled / N/A (not Linux)} | {global/project} |
| dangerouslySkipPermissions | {true/false} | {global} |
| Permission entries | {count from settings.local.json} | {local} |

If `dangerouslySkipPermissions` is `true`, add a warning note: "**Warning:** Permissions bypass is enabled. All tool calls execute without confirmation."
```

- [ ] **Step 3: Add security to Phase 6b JSON sidecar**

In the JSON sidecar template, after the `"monitoring"` block (added in Task 2) and before `"validation"`, add:

```json
  "security": {
    "sandboxMode": "pid_namespace",
    "dangerouslySkipPermissions": false,
    "permissionCount": 127,
    "os": "linux"
  },
```

- [ ] **Step 4: Commit**

```bash
git add skills/inventory/SKILL.md
git commit -m "feat(v2.1): add sandbox and security posture reporting"
```

---

## Task 4: Schema Version Bump and Metadata

Bump JSON schema to version 4, update plugin version, add evals, update docs.

**Files:**
- Modify: `skills/inventory/SKILL.md` (schema version references)
- Modify: `.claude-plugin/plugin.json` (version bump)
- Modify: `evals/evals.json` (new scenario)
- Modify: `CLAUDE.md` (version)

- [ ] **Step 1: Update schema version in SKILL.md**

Change both schema version references in SKILL.md:
- About This File table: `| Schema version | 3 |` → `| Schema version | 4 |`
- JSON sidecar template: `"schemaVersion": 3,` → `"schemaVersion": 4,`

- [ ] **Step 2: Bump plugin version**

In `.claude-plugin/plugin.json`, change `"version": "2.0.0"` to `"version": "2.1.0"`.

- [ ] **Step 3: Add new eval scenario**

In `evals/evals.json`, add one entry after the existing id:6 entry:

```json
    {
      "id": 7,
      "prompt": "Generate an inventory showing my deferred MCP tools, any background monitoring in my skills, and my sandbox security settings.",
      "expected_output": "A .CLAUDE.inventory.md where MCP Servers table has a Loading column (eager/deferred), followed by a Deferred Tools sub-table listing lazy-loaded tools. Background Monitoring sub-section lists any skills/hooks using Monitor tool or run_in_background. Security section under Global Scope shows sandbox mode, dangerouslySkipPermissions, and permission count. JSON sidecar includes deferredTools, monitoring, and security keys with schemaVersion: 4.",
      "files": [],
      "assertions": []
    }
```

- [ ] **Step 4: Update CLAUDE.md version**

In `CLAUDE.md`, change `**Version:** 2.0.0` to `**Version:** 2.1.0`.

- [ ] **Step 5: Commit**

```bash
git add skills/inventory/SKILL.md .claude-plugin/plugin.json evals/evals.json CLAUDE.md
git commit -m "chore(v2.1): bump version to 2.1.0, schema to 4, add evals"
```

---

## Task 5: Integration Verification

Verify all 3 new features appear correctly.

**Files:**
- None modified — verification only

- [ ] **Step 1: Run `/inventory` and verify new sections**

Invoke `/inventory` and confirm:
- MCP Servers table has a Loading column
- Deferred Tools sub-section appears (if any MCP servers use lazy loading)
- Background Monitoring sub-section appears (if Monitor tool usage detected)
- Security section appears under Global Scope
- `schemaVersion: 4` in JSON sidecar
- `deferredTools`, `monitoring`, `security` keys in JSON sidecar
- No regressions in v2.0 or v1.2 sections

- [ ] **Step 2: Run `/inventory-global` and verify security section**

Invoke `/inventory-global` and confirm:
- Security section appears (global scope, applies to global mode)
- Deferred Tools and Background Monitoring sections are omitted (project-scoped)

- [ ] **Step 3: Final commit if fixes needed**

```bash
git add -A
git commit -m "fix(v2.1): address integration verification findings"
```
