import { Router, Request, Response } from "express";
import fs from "fs";
import path from "path";
import { decisionService } from "../services/decisionservice";
import { sseService } from "../services/sseservice";
import { pairingService } from "../services/pairingservice";

// Read the version from package.json at runtime so there is a single source
// of truth.  The file lives at the bridge root (two levels above ./dist/).
let bridgeVersion = "0.0.0";
try {
  const pkgPath = path.join(__dirname, "../../package.json");
  bridgeVersion = JSON.parse(fs.readFileSync(pkgPath, "utf8")).version ?? bridgeVersion;
} catch { /* keep default */ }

const router = Router();

/**
 * GET /health
 *
 * Health check endpoint. Returns bridge status and connection stats.
 */
router.get("/", (req: Request, res: Response) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    version: bridgeVersion,
    connections: {
      sse: sseService.getConnectedCount(),
      pending: decisionService.getPendingCount(),
      sessions: pairingService.getSessionCount(),
    },
  });
});

export default router;
