import pino, { StreamEntry } from "pino";
import fs from "fs";
import { config } from "../config";

// In-process multistream logger (no worker thread) so it stays robust when run
// as a background launchd daemon.
//
// - stdout: pretty in dev, raw JSON in production (the daemon runs in
//   production and lets launchd capture stdout to the log file).
// - file: raw JSON appended to config.logFile, when set (disabled for the
//   daemon via LOG_FILE="" to avoid duplicating launchd's stdout capture).
const isProd = process.env.NODE_ENV === "production";
const level = config.logLevel as pino.Level;

const streams: StreamEntry[] = [];

if (isProd) {
  streams.push({ level, stream: process.stdout });
} else {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const pretty = require("pino-pretty");
    streams.push({
      level,
      stream: pretty({ colorize: true, translateTime: "HH:MM:ss", ignore: "pid,hostname" }),
    });
  } catch {
    streams.push({ level, stream: process.stdout });
  }
}

if (config.logFile) {
  try {
    fs.mkdirSync(config.dataDir, { recursive: true });
    streams.push({
      level,
      stream: fs.createWriteStream(config.logFile, { flags: "a" }),
    });
  } catch {
    // File logging unavailable — continue with stdout only.
  }
}

export const logger = pino({ level: config.logLevel }, pino.multistream(streams));
