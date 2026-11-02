#!/usr/bin/env bash
# Regression tests for the staleness hash.
#
#  1. hooks/inventory-hash.sh and the Python fallback in skills/inventory/SKILL.md
#     (phase 6c) produce the same hash, with and without optional directories.
#  2. hooks/inventory.sh exits 0 when optional ~/.claude directories are missing.
#  3. The hook stays quiet when the stored hash is current, and reports stale
#     after a config change.
#
# Runs in a throwaway HOME and project; touches nothing real.
# Usage: bash tests/hash-parity.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hash_script="$repo/hooks/inventory-hash.sh"
hook="$repo/hooks/inventory.sh"
skill="$repo/skills/inventory/SKILL.md"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# Extract the Python fallback block from SKILL.md phase 6c.
py="$sandbox/fallback.py"
awk '/^\*\*Approach 2/ {grab=1; next}
     grab && /^```python/ {inblock=1; next}
     inblock && /^```/ {exit}
     inblock {print}' "$skill" > "$py"
[ -s "$py" ] || { echo "FAIL: could not extract the Python fallback from SKILL.md"; exit 1; }

pass=0
fail=0
check() { # name, condition result (0 = pass)
    if [ "$2" -eq 0 ]; then pass=$((pass + 1)); echo "ok   - $1"
    else fail=$((fail + 1)); echo "FAIL - $1"; fi
}

new_env() { # name -> sets HOME and cwd to a fresh project
    export HOME="$sandbox/$1/home"
    mkdir -p "$HOME/.claude" "$sandbox/$1/project/.git"
    cd "$sandbox/$1/project"
}

parity() { # name
    local a b
    a="$(bash "$hash_script")"
    b="$(python3 "$py")"
    [ -n "$a" ] && [ "$a" = "$b" ]
    check "$1: script and Python fallback agree ($a)" $?
}

# --- Minimal setup: only settings.json, every optional directory missing ---
new_env minimal
echo '{"enabledPlugins":{}}' > "$HOME/.claude/settings.json"
parity "minimal"

touch .CLAUDE.inventory.md
echo "stale-value" > .CLAUDE.inventory.hash
set +e; out="$(bash "$hook")"; rc=$?; set -e
[ "$rc" -eq 0 ]
check "minimal: hook exits 0 with optional dirs missing (got $rc)" $?
[[ "$out" == *hookSpecificOutput* ]]
check "minimal: hook reports stale for a mismatched hash" $?

bash "$hash_script" > .CLAUDE.inventory.hash
out="$(bash "$hook")"
[ -z "$out" ]
check "minimal: hook is quiet when the stored hash is current" $?

# --- Full setup: every input present, including hidden entries to ignore ---
new_env full
c="$HOME/.claude"
mkdir -p "$c/plugins/cache/mkt/plug/1.0" "$c/skills/alpha" "$c/skills/Beta" "$c/skills/.hidden" \
         "$c/scheduled-tasks/daily" "$c/projects/-p-one/memory" "$c/projects/-p-two/memory" \
         .claude/skills/local-skill
printf '{"hooks":{}}' > "$c/settings.json"            # no trailing newline
printf '{"plugins":{}}\n' > "$c/plugins/installed_plugins.json"
printf '{"mcpServers":{}}\n' > .claude/settings.json
touch "$c/plugins/cache/mkt/plug/1.0/.orphaned_at" \
      "$c/projects/-p-one/memory/MEMORY.md" "$c/projects/-p-two/memory/notes.md"
parity "full"

touch .CLAUDE.inventory.md
bash "$hash_script" > .CLAUDE.inventory.hash
out="$(bash "$hook")"
[ -z "$out" ]
check "full: hook is quiet when the stored hash is current" $?

mkdir -p "$c/skills/new-skill"
out="$(bash "$hook")"
[[ "$out" == *hookSpecificOutput* ]]
check "full: hook reports stale after a new skill is added" $?
parity "full + new skill"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
