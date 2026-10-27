#!/usr/bin/env bash
# SessionStart hook: check if .CLAUDE.inventory.md needs regeneration
set -euo pipefail

# Only act in git repos
[ -d ".git" ] || exit 0

stale=false

# Check 1: File missing
if [ ! -f ".CLAUDE.inventory.md" ]; then
    stale=true
fi

# Check 2: File older than 24 hours
if [ "$stale" = false ] && [ -f ".CLAUDE.inventory.md" ]; then
    now=$(date +%s)
    if [ "$(uname -s)" = "Darwin" ]; then
        file_mod=$(stat -f %m ".CLAUDE.inventory.md" 2>/dev/null || echo 0)
    else
        # Linux and Git Bash on Windows
        file_mod=$(stat -c %Y ".CLAUDE.inventory.md" 2>/dev/null || echo 0)
    fi
    file_age=$(( now - file_mod ))
    [ "$file_age" -gt 86400 ] && stale=true
fi

# Check 3: Config hash changed (catches plugin installs/removals immediately)
if [ "$stale" = false ] && [ -f ".CLAUDE.inventory.hash" ]; then
    current_hash=""

    # Build hash input from key config files + directory listings
    hash_input=""
    [ -f "$HOME/.claude/settings.json" ] && hash_input+=$(cat "$HOME/.claude/settings.json" 2>/dev/null)
    [ -f "$HOME/.claude/plugins/installed_plugins.json" ] && hash_input+=$(cat "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
    hash_input+=$(ls "$HOME/.claude/skills/" 2>/dev/null | sort)
    [ -f ".claude/settings.json" ] && hash_input+=$(cat ".claude/settings.json" 2>/dev/null)
    hash_input+=$(ls ".claude/skills/" 2>/dev/null | sort)
    # v1.2: include memory files, scheduled tasks, and orphan markers
    # Use find instead of ls+glob to avoid glob expansion crashing under set -euo pipefail
    # when no memory directories exist
    hash_input+=$(find "$HOME/.claude/projects/" -maxdepth 3 -name 'MEMORY.md' 2>/dev/null | sort)
    hash_input+=$(ls "$HOME/.claude/scheduled-tasks/" 2>/dev/null | sort)
    hash_input+=$(find "$HOME/.claude/plugins/cache/" -name '.orphaned_at' 2>/dev/null | sort)

    if command -v md5sum &>/dev/null; then
        current_hash=$(printf '%s' "$hash_input" | md5sum | cut -d' ' -f1)
    elif command -v md5 &>/dev/null; then
        current_hash=$(printf '%s' "$hash_input" | md5 -q)
    fi

    if [ -n "$current_hash" ]; then
        stored_hash=$(cat ".CLAUDE.inventory.hash" 2>/dev/null || echo "")
        [ "$current_hash" != "$stored_hash" ] && stale=true
    fi
fi

if $stale; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "Automation inventory (.CLAUDE.inventory.md) is missing, stale, or configs have changed. Run /inventory to regenerate."\n  }\n}\n'
fi

exit 0
