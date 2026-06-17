import { Router, Request, Response, NextFunction } from "express";
import { z } from "zod";
import { decisionService } from "../services/decisionservice";
import { pairingService } from "../services/pairingservice";
import { PermissionDecision, DecisionBehavior } from "../types";
import { logger } from "../utils/logger";
import { AuthenticatedRequest } from "../middleware/auth";

const router = Router();

const decisionSchema = z.object({
  requestId: z.string().uuid(),
  behavior: z.enum(["allow", "deny"]),
  updatedInput: z.record(z.unknown()).optional(),
  updatedPermissions: z
    .array(
      z.object({
        type: z.enum(["addRules", "replaceRules", "removeRules"]),
        rules: z.array(z.string()),
        behavior: z.string(),
        destination: z.string(),
      })
    )
    .optional(),
  message: z.string().optional(),
  interrupt: z.boolean().optional(),
});

/**
 * POST /decisions
 *
 * Submit an approve/deny decision from the iOS app (on behalf of the Apple Watch).
 * This resolves the pending promise in DecisionService, which unblocks the hook response.
 */
router.post("/", (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    // Validate session token
    const token = req.authToken;
    if (!token || !pairingService.validateToken(token)) {
      res.status(401).json({ error: "Invalid or expired session token" });
      return;
    }

    const parsed = decisionSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Invalid decision body", details: parsed.error.issues });
      return;
    }

    const decision: PermissionDecision = {
      requestId: parsed.data.requestId,
      behavior: parsed.data.behavior,
      updatedInput: parsed.data.updatedInput,
      updatedPermissions: parsed.data.updatedPermissions,
      message: parsed.data.message,
      interrupt: parsed.data.interrupt,
      timestamp: new Date().toISOString(),
    };

    const resolved = decisionService.submitDecision(decision.requestId, decision);
    if (!resolved) {
      res.status(404).json({ error: "Request not found or already decided" });
      return;
    }

    logger.info({ requestId: decision.requestId, behavior: decision.behavior }, "Decision submitted");

    res.json({ status: "accepted" });
  } catch (error) {
    next(error);
  }
});

export default router;
