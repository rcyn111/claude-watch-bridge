import dotenv from "dotenv";
import path from "path";
import os from "os";

dotenv.config();

// Data directory for persistent state (pairing sessions) and logs.
// Defaults to ~/.claude-watch so the bridge survives restarts without re-pairing.
const dataDir = process.env.DATA_DIR || path.join(os.homedir(), ".claude-watch");

// LOG_FILE: unset -> default path; set to "" -> disable file logging
// (used by the launchd daemon, which captures stdout to the log file itself).
const logFileEnv = process.env.LOG_FILE;
const logFile = logFileEnv !== undefined ? logFileEnv : path.join(dataDir, "bridge.log");

export const config = {
  port: parseInt(process.env.PORT || "3712", 10),
  host: process.env.HOST || "127.0.0.1",
  hookTimeoutSeconds: parseInt(process.env.HOOK_TIMEOUT || "300", 10),
  pairingCodeExpirySeconds: parseInt(process.env.PAIRING_CODE_EXPIRY || "120", 10),
  pairingCodeLength: parseInt(process.env.PAIRING_CODE_LENGTH || "6", 10),
  tokenLength: parseInt(process.env.TOKEN_LENGTH || "32", 10), // bytes
  sseHeartbeatSeconds: parseInt(process.env.SSE_HEARTBEAT || "30", 10),
  logLevel: process.env.LOG_LEVEL || "info",

  // --- Operation / reliability ---
  // Grace window to wait for a phone/watch SSE client before giving up on a
  // permission request. Prevents Claude Code from blocking for the full
  // HOOK_TIMEOUT when no device is connected.
  noClientGraceSeconds: parseInt(process.env.NO_CLIENT_GRACE_SECONDS || "3", 10),
  // Session token lifetime (seconds). Stored tokens are rejected after this.
  sessionTtlSeconds: parseInt(process.env.SESSION_TTL || String(7 * 24 * 60 * 60), 10),
  // Pairing-code brute-force protection.
  pairVerifyMaxAttempts: parseInt(process.env.PAIR_VERIFY_MAX_ATTEMPTS || "5", 10),
  pairVerifyWindowSeconds: parseInt(process.env.PAIR_VERIFY_WINDOW || "60", 10),

  // --- Persistence ---
  dataDir,
  sessionStorePath: process.env.SESSION_STORE || path.join(dataDir, "sessions.json"),
  logFile,
};
