import { Request, Response, NextFunction } from "express";
import { logger } from "../utils/logger";

/**
 * Bearer token authentication middleware.
 * Validates the session token from the Authorization header.
 *
 * Skip auth for: health, pairing, and hook routes. Hook routes are called by
 * Claude Code (which has no session token); they rely on the loopback bind
 * plus the optional HOOK_TOKEN checked inside the hook route itself.
 */
export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  // Skip auth for health, pairing, and hook routes
  const skipPaths = ["/health", "/pair", "/pair/verify"];
  if (skipPaths.includes(req.path) || req.path.startsWith("/hook")) {
    next();
    return;
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing or invalid Authorization header" });
    return;
  }

  const token = authHeader.slice(7);
  // We inject the pairingService into the request via app.locals
  // This will be validated in the route handler since we need the imported service
  (req as AuthenticatedRequest).authToken = token;

  next();
}

export interface AuthenticatedRequest extends Request {
  authToken?: string;
}
