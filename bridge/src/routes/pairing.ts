import { Router, Request, Response, NextFunction } from "express";
import { pairingService } from "../services/pairingservice";
import { PairingVerifyRequest, PairingVerifyResponse } from "../types";
import { config } from "../config";
import { logger } from "../utils/logger";

const router = Router();

// --- Brute-force protection for pairing code verification ----------------
// 6-digit code has only 1M possibilities; limit guesses per IP per window.
const verifyAttempts = new Map<string, { count: number; resetAt: number }>();

function checkRateLimit(ip: string): { allowed: boolean; retryAfter: number } {
  const now = Date.now();
  const windowMs = (config.pairVerifyWindowSeconds ?? 60) * 1000;
  const max = config.pairVerifyMaxAttempts ?? 5;
  let entry = verifyAttempts.get(ip);
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + windowMs };
    verifyAttempts.set(ip, entry);
  }
  if (entry.count >= max) {
    return { allowed: false, retryAfter: Math.ceil((entry.resetAt - now) / 1000) };
  }
  entry.count += 1;
  return { allowed: true, retryAfter: 0 };
}

/**
 * POST /pair
 *
 * Request a pairing code. Returns a 6-digit code displayed in the terminal.
 * The user enters this code in the iOS app to establish a trusted session.
 */
router.post("/", (req: Request, res: Response, next: NextFunction) => {
  try {
    const pairingCode = pairingService.generateCode();
    res.json({
      code: pairingCode.code,
      expiresIn: Math.max(0, Math.round((pairingCode.expiresAt - Date.now()) / 1000)),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * POST /pair/verify
 *
 * Verify a pairing code entered in the iOS app.
 * On success, returns a bearer token for subsequent authenticated requests.
 */
router.post("/verify", (req: Request, res: Response, next: NextFunction) => {
  try {
    const ip = req.ip || "unknown";
    const rl = checkRateLimit(ip);
    if (!rl.allowed) {
      res.status(429).json({ error: `Too many attempts. Retry in ${rl.retryAfter}s.` });
      return;
    }

    const { code } = req.body as PairingVerifyRequest;

    if (!code || typeof code !== "string") {
      res.status(400).json({ error: "Missing or invalid pairing code" });
      return;
    }

    const token = pairingService.verifyCode(code);
    if (!token) {
      res.status(401).json({ error: "Invalid or expired pairing code" });
      return;
    }

    const session = pairingService.getSession(token);
    const response: PairingVerifyResponse = {
      token,
      expiresAt: session ? new Date(session.expiresAt).toISOString() : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    };

    logger.info({ sessionId: session?.sessionId }, "Pairing verified, token issued");
    res.json(response);
  } catch (error) {
    next(error);
  }
});

export default router;
