#!/bin/bash
# daemon.sh — manage the Claude Watch Bridge as a launchd agent (auto-start,
# keep-alive, captured logs). Safe to re-run.
#
# Usage:
#   ./bridge/scripts/daemon.sh install     # build + install + start launchd agent
#   ./bridge/scripts/daemon.sh uninstall   # stop + remove launchd agent
#   ./bridge/scripts/daemon.sh restart     # restart the agent
#   ./bridge/scripts/daemon.sh status      # reachability + health + connection stats
#   ./bridge/scripts/daemon.sh logs        # tail -f the log (pretty-printed)
#   PORT=8080 ./bridge/scripts/daemon.sh install

set -euo pipefail

BRIDGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$HOME/.claude-watch}"
LOG_FILE="${LOG_FILE:-$DATA_DIR/bridge.log}"
PORT="${PORT:-3712}"
HOST="${HOST:-127.0.0.1}"
LABEL="com.claude-watch.bridge"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
PRETTY="$BRIDGE_DIR/node_modules/.bin/pino-pretty"

node_bin="$(command -v node || true)"
if [ -z "$node_bin" ]; then
  echo "node not found in PATH" >&2
  exit 1
fi

cmd="${1:-status}"

write_plist() {
  mkdir -p "$(dirname "$PLIST")" "$DATA_DIR"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${node_bin}</string>
    <string>${BRIDGE_DIR}/dist/index.js</string>
  </array>
  <key>WorkingDirectory</key><string>${BRIDGE_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PORT</key><string>${PORT}</string>
    <key>HOST</key><string>${HOST}</string>
    <key>DATA_DIR</key><string>${DATA_DIR}</string>
    <key>LOG_FILE</key><string></string>
    <key>NODE_ENV</key><string>production</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_FILE}</string>
  <key>StandardErrorPath</key><string>${LOG_FILE}</string>
</dict>
</plist>
EOF
}

case "$cmd" in
  install)
    if [ ! -f "$BRIDGE_DIR/dist/index.js" ]; then
      echo "==> Building bridge..."
      (cd "$BRIDGE_DIR" && npm install --silent && npm run build)
    fi
    write_plist
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Installed and started launchd agent: ${LABEL}"
    echo "  URL:   http://${HOST}:${PORT}"
    echo "  Logs:  ${LOG_FILE}   (make logs)"
    echo "  Stop:  make uninstall"
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Uninstalled launchd agent: ${LABEL}"
    ;;
  restart)
    if [ ! -f "$PLIST" ]; then echo "Not installed. Run: make install" >&2; exit 1; fi
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Restarted: ${LABEL}"
    ;;
  status)
    url="http://${HOST}:${PORT}/health"
    if resp=$(curl -fsS --max-time 3 "$url" 2>/dev/null); then
      echo "✅ Bridge running at ${url}"
      echo "$resp" | python3 -m json.tool 2>/dev/null || echo "$resp"
    else
      echo "❌ Bridge not reachable at ${url}"
      if [ -f "$PLIST" ]; then
        echo "launchd agent is installed. Recent logs:"
        tail -n 15 "$LOG_FILE" 2>/dev/null || echo "  (no log file yet)"
      else
        echo "launchd agent not installed. Run: make install"
      fi
      exit 1
    fi
    ;;
  logs)
    if [ ! -f "$LOG_FILE" ]; then echo "No log file at $LOG_FILE" >&2; exit 1; fi
    if [ -x "$PRETTY" ]; then
      tail -f "$LOG_FILE" | "$PRETTY"
    else
      tail -f "$LOG_FILE"
    fi
    ;;
  pair)
    curl -fsS -X POST "http://${HOST}:${PORT}/pair" | python3 -m json.tool 2>/dev/null \
      || curl -s -X POST "http://${HOST}:${PORT}/pair"
    ;;
  *)
    echo "Usage: $0 {install|uninstall|restart|status|logs|pair}" >&2
    exit 1
    ;;
esac
