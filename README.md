# Claude Watch Bridge

Approve Claude Code permission requests from your Apple Watch.

<p align="center">
  <img src="docs/watch-mockup.png" alt="Apple Watch Claude Code authorization" width="300"/>
</p>

## How It Works

```
Claude Code (Terminal) ──HTTP──> Bridge Server (Mac) ──WiFi──> iPhone App ──Bluetooth──> Apple Watch
                                  ▲                              │          ▲
                                  │◄──── POST /decisions ───────┘          │◄── WCSession
                                  └─────────────────────────────────────────┘
```

When Claude Code needs permission to run a command, read a file, or make an edit, it sends an HTTP request to the Bridge Server on your Mac. The bridge forwards it to your iPhone, which sends it to your Apple Watch. You tap **Approve** or **Deny** on your wrist, and the decision travels back — all within seconds.

## Prerequisites

- macOS 14+ (Sonoma or later)
- iOS 17+ on iPhone
- watchOS 10+ on Apple Watch
- Node.js 18+ installed on your Mac
- All devices on the same Wi-Fi network

## Quick Start

### 1. Install and start the Bridge Server

The easiest way is to run it as a launchd agent that **auto-starts on login and stays alive**:

```bash
make install        # builds + installs + starts the launchd agent
make status         # check it's running
make logs           # tail logs (pretty)
```

Prefer to run it in the foreground instead?

```bash
cd bridge
npm install
npm run build
npm start
```

You'll see a 6-digit pairing code in the terminal (only when no device is paired yet):

```
==================================================
  CLAUDE WATCH BRIDGE
==================================================
  Pairing Code: 482916
  Expires in:   120s

  Open the iOS app and enter this code to pair.
==================================================
```

### 2. Configure Claude Code hooks

```bash
make hooks
```

This adds the Watch authorization hooks to your `~/.claude/settings.json`.

### 3. Build and run the iOS app

Open the Xcode project (requires XcodeGen):

```bash
brew install xcodegen
make ios-open
```

Select your iPhone as the target, then build and run. Enter the 6-digit pairing code from the terminal.

### 4. Install the Watch app

In Xcode, select the Watch app scheme and install it on your paired Apple Watch. Or enable "Show App on Apple Watch" in the Watch app on your iPhone.

### 5. Start using Claude Code

That's it! When Claude Code needs permission, you'll feel a tap on your wrist. Approve or deny right from your watch.

## Operation

### Always-on (launchd daemon)

`make install` registers the bridge as a launchd agent that starts on login and
restarts if it crashes. Pairing sessions are persisted to `~/.claude-watch/sessions.json`,
so **restarting the bridge (or rebooting) does not require re-pairing** — the iOS
app reconnects automatically.

| Command | What it does |
|---------|--------------|
| `make install` | Build + install + start the launchd agent |
| `make uninstall` | Stop and remove the agent |
| `make restart` | Restart the agent |
| `make status` | Reachability + health + connection stats |
| `make logs` | Tail the log (pretty-printed) |
| `make pair` | Request a fresh pairing code |
| `make hooks` | Install Claude Code hooks (idempotent) |
| `make hooks-remove` | Remove the Claude Code hooks |

### Resilience

- **Fail-fast when no device is connected:** if no iPhone/Watch is connected via
  SSE when a permission request arrives, the bridge returns after a short grace
  window (`NO_CLIENT_GRACE_SECONDS`, default 3s) instead of blocking Claude Code
  for the full `HOOK_TIMEOUT`. Set `HOOK_FALLBACK_BEHAVIOR=ask` to have Claude
  Code fall back to its normal terminal prompt in that case (default `deny`).
- **Auto-reconnect:** the iOS app streams SSE with exponential backoff and
  reconnects on any disconnect.
- **Session isolation:** a `Stop` hook only cancels pending requests for that
  Claude session, so concurrent sessions don't interfere.

## Architecture

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Bridge Server | Node.js + TypeScript + Express | Receives Claude Code hooks, relays to iPhone |
| iOS Companion App | SwiftUI + WCSession | Bridges HTTP/SSE to Apple Watch |
| Apple Watch App | SwiftUI (watchOS) | Display permissions and collect decisions |

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/pair` | Request pairing code |
| `POST` | `/pair/verify` | Exchange code for session token |
| `GET` | `/events` | SSE stream (authenticated) |
| `POST` | `/hook/permission-request` | **Blocking**: wait for Watch decision |
| `POST` | `/hook/post-tool-use` | Tool usage notification |
| `POST` | `/hook/stop` | Session ended |
| `POST` | `/decisions` | Submit approve/deny (authenticated) |
| `GET` | `/pending` | List pending requests (authenticated) |

## Security

- **Local-only**: The bridge binds to `127.0.0.1` by default — no external network exposure
- **Pairing code**: 6-digit random code, expires in 120 seconds, shown only in the terminal
- **Bearer token**: 256-bit random token stored in iOS Keychain
- **No cloud**: All communication stays on your local network

## Configuration

Set these environment variables (or create `bridge/.env`):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3712` | Bridge HTTP port |
| `HOST` | `127.0.0.1` | Bridge bind address |
| `HOOK_TIMEOUT` | `300` | Max seconds to wait for Watch decision |
| `HOOK_FALLBACK_BEHAVIOR` | `deny` | `deny` blocks the tool on timeout/no-device; `ask` defers to the terminal prompt |
| `NO_CLIENT_GRACE_SECONDS` | `3` | Grace window before failing a request with no device connected |
| `PAIRING_CODE_EXPIRY` | `120` | Pairing code validity (seconds) |
| `PAIR_VERIFY_MAX_ATTEMPTS` | `5` | Max pairing-code guesses per IP per window |
| `SESSION_TTL` | `604800` | Session token lifetime in seconds (7 days) |
| `SSE_HEARTBEAT` | `30` | SSE keepalive interval (seconds) |
| `LOG_LEVEL` | `info` | Logging level (debug/info/warn/error) |
| `DATA_DIR` | `~/.claude-watch` | Where `sessions.json` and logs are stored |
| `LOG_FILE` | `~/.claude-watch/bridge.log` | Log file; set to `""` to disable file logging |

## Development

```bash
# Install dependencies
make setup

# Start bridge in dev mode (hot reload)
cd bridge && npm run dev

# Run tests
make bridge-test

# Generate Xcode project (requires XcodeGen)
brew install xcodegen
make ios-gen

# Open Xcode
make ios-open
```

## Troubleshooting

**Check the bridge first:**
```bash
make status     # is it running? how many clients/sessions?
make logs       # watch live logs
```

**Watch doesn't show requests:**
- Ensure iPhone is on the same Wi-Fi as your Mac
- Check that Watch is connected to iPhone via Bluetooth
- Verify WCSession status in the iOS app Dashboard
- Check bridge logs for SSE connection status (`make logs`)

**Claude Code blocks for minutes then denies:**
- No device was connected. Open the iOS app so it reconnects, or set
  `HOOK_FALLBACK_BEHAVIOR=ask` so Claude Code falls back to the terminal prompt
  instead of denying when the watch is unreachable.

**Pairing code expired:**
- Run `make pair` (or `curl -X POST http://127.0.0.1:3712/pair`) for a new code.
- You do **not** need to re-pair after restarting the bridge or rebooting —
  sessions are persisted and the iOS app reconnects automatically.

**iOS app can't reach the bridge:**
- The phone must use your **Mac's LAN IP** (e.g. `192.168.1.5`), not `127.0.0.1`
  (which would refer to the phone itself). The host you enter is saved for next time.

**"Not reachable" on iPhone app:**
- Open the Watch app on your iPhone
- Ensure the Claude Watch app is installed
- Keep the iPhone app in the foreground during initial pairing

## License

MIT
