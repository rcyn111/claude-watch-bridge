import fs from "fs";
import { createApp } from "./app";
import { config } from "./config";
import { logger } from "./utils/logger";
import { pairingService } from "./services/pairingservice";

async function main() {
  // Ensure the data directory exists for sessions.json / logs.
  try {
    fs.mkdirSync(config.dataDir, { recursive: true });
  } catch (err) {
    logger.warn({ err }, "Could not create data directory");
  }

  // Drop expired sessions restored from disk.
  const pruned = pairingService.pruneExpired();

  const app = createApp();

  app.listen(config.port, config.host, () => {
    const sessions = pairingService.getSessionCount();
    logger.info(`Bridge server started on http://${config.host}:${config.port}`);
    logger.info(`Health check: http://${config.host}:${config.port}/health`);

    console.log("\n" + "=".repeat(50));
    console.log("  CLAUDE WATCH BRIDGE");
    console.log("=".repeat(50));
    if (pruned > 0) {
      console.log(`  Pruned ${pruned} expired session(s).`);
    }
    if (sessions > 0) {
      console.log(`  Already paired with ${sessions} device(s).`);
      console.log("  Open the iOS app — it will reconnect automatically.");
      console.log("");
      console.log("  Need to pair a new device? Run:");
      console.log(`  curl -X POST http://${config.host}:${config.port}/pair`);
    } else {
      const pairingCode = pairingService.generateCode();
      console.log(`  Pairing Code: ${pairingCode.code}`);
      console.log(`  Expires in:   ${config.pairingCodeExpirySeconds}s`);
      console.log("");
      console.log("  Open the iOS app and enter this code to pair.");
      console.log("  For a new code, run:");
      console.log(`  curl -X POST http://${config.host}:${config.port}/pair`);
    }
    console.log("=".repeat(50) + "\n");
  });

  // Graceful shutdown
  const shutdown = () => {
    logger.info("Shutting down bridge server...");
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  logger.error({ err }, "Failed to start bridge server");
  process.exit(1);
});
