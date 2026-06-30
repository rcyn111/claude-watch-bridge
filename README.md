# Claude Watch Bridge

Approve Claude Code permission requests from your Apple Watch.

[English](README.md) | [中文](README.zh-CN.md)

<p align="center">
  <img src="docs/watch-mockup.png" alt="Apple Watch Claude Code authorization" width="300"/>
</p>

## How It Works

```
Claude Code (Terminal) ──HTTP──> Bridge Server (Mac) ──WiFi──> iPhone App ──Bluetooth──> Apple Watch
       ▲                          │          ▲
       │◄──── POST /decisions ───┘          │◄── WCSession
       └─────────────────────────────────────┘
```

When Claude Code needs permission to run a command, read a file, or make an edit, it sends an HTTP request to the Bridge Server on your Mac. The bridge forwards it to your iPhone, which sends it to your Apple Watch. You tap **Approve** or **Deny** on your wrist, and the decision travels back — all within seconds.

## Prerequisites

- macOS 14+ (Sonoma or later)
- iOS 17+ on iPhone
- watchOS 10+ on Apple Watch
- Node.js 18+ on your Mac
- All devices on the same Wi-Fi network

## Quick Start

### 1. Install and start the Bridge Server

Recommended: run as a launchd agent that auto-starts on login and stays alive:

```bash
make install        # build + install + start the launchd agent
make status         # check it's running
make logs           # tail logs
```

Or run in the foreground:

```bash
cd bridge
npm install
npm run build
npm start
```

When no device is paired, the terminal shows a 6-digit pairing code:

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

### 3. Build and run the iOS app

Requires XcodeGen:

```bash
brew install xcodegen
make ios-open
```

Select your iPhone as the target, build and run. Enter the 6-digit pairing code.

### 4. Install the Watch app

In Xcode, select the Watch app scheme and install on your paired Apple Watch.

### 5. Start using Claude Code

When Claude Code needs permission, you'll feel a tap on your wrist. Approve or deny right from your watch.

## Operation

### Launchd daemon

`make install` registers the bridge as a launchd agent. Sessions are persisted to `~/.claude-watch/sessions.json`, so restarting the bridge (or rebooting) does not require re-pairing.

| Command | What it does |
|---------|--------------|
| `make install` | Build + install + start launchd agent |
| `make uninstall` | Stop and remove the agent |
| `make restart` | Restart the agent |
| `make status` | Reachability + health + connection stats |
| `make logs` | Tail log output |
| `make pair` | Request a fresh pairing code |
| `make hooks` | Install Claude Code hooks (idempotent) |
| `make hooks-remove` | Remove Claude Code hooks |

### Resilience

- **Fail-fast**: If no iPhone/Watch is connected, the bridge returns after a short grace window (default 3s) instead of blocking. Set `HOOK_FALLBACK_BEHAVIOR=ask` to fall back to the terminal prompt.
- **Auto-reconnect**: iOS app uses exponential backoff SSE reconnection.
- **Session isolation**: `Stop` hook only cancels requests for that Claude session.

## Architecture

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Bridge Server | Node.js + TypeScript + Express | Receives Claude Code hooks, relays to iPhone |
| iOS Companion | SwiftUI + WCSession | Bridges HTTP/SSE to Apple Watch |
| Apple Watch App | SwiftUI (watchOS) | Display permissions, collect decisions |

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

- **Local-only**: Binds to `127.0.0.1` by default — no external exposure
- **Pairing code**: 6-digit random, 120s expiry, terminal-only display
- **Bearer token**: 256-bit random, stored in iOS Keychain
- **No cloud**: All communication stays local

## Configuration

Set via environment variables or `bridge/.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3712` | Bridge HTTP port |
| `HOST` | `127.0.0.1` | Bind address |
| `HOOK_TIMEOUT` | `300` | Max seconds to wait for Watch decision |
| `HOOK_FALLBACK_BEHAVIOR` | `deny` | `deny` or `ask` (terminal fallback) |
| `NO_CLIENT_GRACE_SECONDS` | `3` | Grace window before failing with no device |
| `PAIRING_CODE_EXPIRY` | `120` | Pairing code validity (seconds) |
| `PAIR_VERIFY_MAX_ATTEMPTS` | `5` | Max guesses per IP per window |
| `SESSION_TTL` | `604800` | Session token lifetime (7 days) |
| `SSE_HEARTBEAT` | `30` | SSE keepalive interval (seconds) |
| `LOG_LEVEL` | `info` | Logging level |
| `DATA_DIR` | `~/.claude-watch` | Data storage directory |
| `LOG_FILE` | `~/.claude-watch/bridge.log` | Log file path |

## Development

```bash
make setup                # Install dependencies
cd bridge && npm run dev  # Dev mode with hot reload
make bridge-test          # Run tests
brew install xcodegen     # Required for iOS
make ios-gen              # Generate Xcode project
make ios-open             # Open Xcode
```

## Troubleshooting

**Check the bridge first:**
```bash
make status     # Running? How many clients/sessions?
make logs       # Live logs
```

**Watch doesn't show requests:** Ensure iPhone and Mac are on the same Wi-Fi, Watch is connected via Bluetooth, and WCSession is active.

**Claude Code blocks then denies:** No device was connected. Open the iOS app or set `HOOK_FALLBACK_BEHAVIOR=ask`.

**Pairing code expired:** Run `make pair` for a new code. Restarting does not require re-pairing.

**iOS app can't reach bridge:** Use your Mac's LAN IP (e.g. `192.168.1.5`), not `127.0.0.1`.

## License

MIT
