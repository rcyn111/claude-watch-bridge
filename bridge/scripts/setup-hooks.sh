#!/bin/bash
# setup-hooks.sh
# Manages the Claude Code settings.json hook entries for the Apple Watch bridge.
#
# Usage:
#   ./scripts/setup-hooks.sh              # Write/merge into ~/.claude/settings.json
#   ./scripts/setup-hooks.sh --local      # Write/merge into .claude/settings.local.json
#   ./scripts/setup-hooks.sh --dry-run    # Print config without writing
#   ./scripts/setup-hooks.sh --remove     # Remove bridge hooks (use --local for project file)
#   PORT=8080 HOOK_TIMEOUT=120 ./scripts/setup-hooks.sh
#
# Idempotent: re-running merges by URL without duplicating entries.

set -euo pipefail

PORT="${PORT:-3712}"
HOST="${HOST:-127.0.0.1}"
HOOK_TIMEOUT="${HOOK_TIMEOUT:-300}"
BRIDGE_URL="http://${HOST}:${PORT}"

# Parse args: a single mode flag.
MODE="global"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --local)   MODE="local" ;;
    --remove)  MODE="remove" ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Settings file path per mode.
case "$MODE" in
  local)     SETTINGS_FILE=".claude/settings.local.json" ;;
  global|*)  SETTINGS_FILE="$HOME/.claude/settings.json" ;;
esac

# --- Optional shared-secret auth header for hook endpoints ---------------
# When HOOK_TOKEN is set, the generated hook config includes an Authorization
# header and allowsEnvVars so Claude Code can read the token from the
# environment.  Requires Claude Code ≥ 1.0.50 (http hooks with headers).
if [ -n "${HOOK_TOKEN:-}" ]; then
  HOOK_AUTH=',"headers":{"Authorization":"Bearer $HOOK_TOKEN"},"allowedEnvVars":["HOOK_TOKEN"]'
  echo "Hook auth enabled — Claude Code will send Authorization: Bearer <HOOK_TOKEN>"
else
  HOOK_AUTH=""
fi

HOOK_CONFIG=$(cat <<EOF
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "http",
            "url": "${BRIDGE_URL}/hook/permission-request",
            "timeout": ${HOOK_TIMEOUT}${HOOK_AUTH},
            "statusMessage": "Awaiting approval on Apple Watch..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "http",
            "url": "${BRIDGE_URL}/hook/post-tool-use",
            "timeout": 10${HOOK_AUTH}
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "http",
            "url": "${BRIDGE_URL}/hook/stop",
            "timeout": 10${HOOK_AUTH}
          }
        ]
      }
    ]
  }
}
EOF
)

# --- dry-run --------------------------------------------------------------
if [ "$MODE" == "dry-run" ]; then
  echo "Would merge the following configuration into ${SETTINGS_FILE}:"
  echo "$HOOK_CONFIG" | python3 -m json.tool 2>/dev/null || echo "$HOOK_CONFIG"
  exit 0
fi

# --- remove ---------------------------------------------------------------
if [ "$MODE" == "remove" ]; then
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "No settings file at $SETTINGS_FILE — nothing to remove."
    exit 0
  fi
  python3 -c "
import json
path = '$SETTINGS_FILE'
with open(path) as f:
    data = json.load(f)
prefix = '$BRIDGE_URL/hook/'
hooks = data.get('hooks', {})
removed = 0
for event, groups in list(hooks.items()):
    for group in groups:
        group['hooks'] = [h for h in group.get('hooks', []) if not (h.get('url','').startswith(prefix))]
        removed += sum(1 for _ in [])
    # drop groups with no hooks left
    hooks[event] = [g for g in groups if g.get('hooks')]
    if not hooks[event]:
        del hooks[event]
if not hooks:
    data.pop('hooks', None)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print(f'Removed bridge hooks from {path}')
"
  exit 0
fi

# --- merge (idempotent) ---------------------------------------------------
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "$HOOK_CONFIG" > "$SETTINGS_FILE"
  echo "Created $SETTINGS_FILE"
else
  echo "Existing settings found at $SETTINGS_FILE"
  echo "Merging hooks (dedup by URL)..."

  python3 -c "
import json
path = '$SETTINGS_FILE'
with open(path) as f:
    existing = json.load(f)

new = json.loads('''$HOOK_CONFIG''')

existing.setdefault('hooks', {})
for event, new_groups in new['hooks'].items():
    cur_groups = existing['hooks'].setdefault(event, [])
    for new_group in new_groups:
        # Find a group with the same matcher (or None matcher) to merge into.
        target = None
        nm = new_group.get('matcher')
        for g in cur_groups:
            gm = g.get('matcher')
            if (gm is None and nm is None) or gm == nm:
                target = g
                break
        if target is None:
            cur_groups.append(new_group)
            continue
        for h in new_group['hooks']:
            url = h.get('url')
            match = next((eh for eh in target.get('hooks', []) if eh.get('url') == url), None)
            if match is not None:
                # Update fields (e.g. timeout) on the existing handler in place.
                match.update(h)
            else:
                target.setdefault('hooks', []).append(h)

with open(path, 'w') as f:
    json.dump(existing, f, indent=2)
    f.write('\n')
print(f'Hooks merged into {path}')
" 2>/dev/null || {
      echo "Warning: python3 unavailable or merge failed; writing standalone config." >&2
      echo "$HOOK_CONFIG" > "$SETTINGS_FILE"
      echo "Wrote $SETTINGS_FILE"
    }
fi

echo ""
echo "Claude Watch hooks configured!"
echo "Bridge URL: $BRIDGE_URL"
echo "Permission timeout: ${HOOK_TIMEOUT}s"
echo ""
echo "Next steps:"
echo "  1. Start the bridge server: make bridge   (or: make install for auto-start)"
echo "  2. Open the iOS companion app and pair with the bridge"
echo "  3. Open the Watch app"
echo "  4. Start using Claude Code — permissions will appear on your Watch!"
echo ""
echo "To remove later: make hooks-remove   (or: ./scripts/setup-hooks.sh --remove)"
