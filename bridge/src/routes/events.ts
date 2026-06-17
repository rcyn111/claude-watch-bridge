import { Router, Request, Response, NextFunction } from "express";
import { sseService } from "../services/sseservice";
import { pairingService } from "../services/pairingservice";
import { logger } from "../utils/logger";
import { AuthenticatedRequest } from "../middleware/auth";
import { randomUUID } from "crypto";

const router = Router();

/**
 * GET /events
 *
 * SSE endpoint. The iOS app connects here after authentication to receive
 * real-time permission requests and status updates.
 *
 * Events:
 *   - permission_request: New permission request awaiting decision
 *   - session_ended: Claude Code session terminated
 *   - heartbeat: Keepalive ping
 *   - error: Error notification
 */
router.get("/", (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const token = req.authToken;
    if (!token || !pairingService.validateToken(token)) {
      res.status(401).json({ error: "Invalid or expired session token" });
      return;
    }

    const clientId = randomUUID();
    logger.info({ clientId }, "SSE connection established");

    // Add client to SSE service
    sseService.addClient(clientId, res);

    // Connection stays open until client disconnects or server stops
    // The res object is kept open by the SSE service
  } catch (error) {
    next(error);
  }
});

export default router;
