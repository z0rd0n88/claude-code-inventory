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
    # The hash recipe lives in inventory-hash.sh so it matches what /inventory
    # writes (skills/inventory/SKILL.md phase 6c) exactly.
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    current_hash=$(bash "$script_dir/inventory-hash.sh" 2>/dev/null || true)

    if [ -n "$current_hash" ]; then
        stored_hash=$(cat ".CLAUDE.inventory.hash" 2>/dev/null || echo "")
        [ "$current_hash" != "$stored_hash" ] && stale=true
    fi
fi

if $stale; then
    printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "Automation inventory (.CLAUDE.inventory.md) is missing, stale, or configs have changed. Run /inventory to regenerate."\n  }\n}\n'
fi

exit 0
