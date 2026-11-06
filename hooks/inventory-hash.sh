#!/usr/bin/env bash
# Print the config hash that /inventory stores in .CLAUDE.inventory.hash.
#
# This script is the single definition of the hash. The SessionStart hook
# (inventory.sh) calls it, and skills/inventory/SKILL.md phase 6c runs it,
# so the stored hash and the hook's comparison hash always come from the same
# recipe. The Python fallback in SKILL.md mirrors it byte for byte;
# tests/hash-parity.sh checks both.
#
# Run it from the project root. Missing files and directories are normal and
# contribute only their section header. Prints nothing if neither md5sum nor
# md5 is available. Always exits 0.
set -uo pipefail
export LC_ALL=C

claude_dir="$HOME/.claude"

hash_stream() {
    local f d e p

    # Config files: header, raw contents (if present), newline.
    for f in "$claude_dir/settings.json" \
             "$claude_dir/plugins/installed_plugins.json" \
             ".claude/settings.json"; do
        printf 'file:%s\n' "$f"
        [ -f "$f" ] && cat "$f"
        printf '\n'
    done

    # Directory listings: header, then non-hidden entry names, sorted.
    for d in "$claude_dir/skills" ".claude/skills" "$claude_dir/scheduled-tasks"; do
        printf 'dir:%s\n' "$d"
        if [ -d "$d" ]; then
            for e in "$d"/*; do
                [ -e "$e" ] || [ -L "$e" ] || continue
                printf '%s\n' "${e##*/}"
            done | sort
        fi
    done

    # Memory files: sorted paths of ~/.claude/projects/*/memory/*.md.
    printf 'memory\n'
    for p in "$claude_dir"/projects/*/memory/*.md; do
        [ -f "$p" ] && printf '%s\n' "$p"
    done | sort

    # Orphaned plugin markers anywhere under the plugin cache, sorted.
    printf 'orphans\n'
    if [ -d "$claude_dir/plugins/cache" ]; then
        find "$claude_dir/plugins/cache" -name '.orphaned_at' 2>/dev/null | sort
    fi
    return 0
}

if command -v md5sum >/dev/null 2>&1; then
    hash_stream | md5sum | cut -d' ' -f1
elif command -v md5 >/dev/null 2>&1; then
    hash_stream | md5 -q
fi
exit 0
