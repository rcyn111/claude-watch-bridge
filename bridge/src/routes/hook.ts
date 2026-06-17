import { Router, Request, Response, NextFunction } from "express";
import { z } from "zod";
import { decisionService } from "../services/decisionservice";
import { pairingService } from "../services/pairingservice";
import { HookInput, HookResponse, DecisionBehavior } from "../types";
import { logger } from "../utils/logger";
import { AuthenticatedRequest } from "../middleware/auth";

const router = Router();

// Behaviour used when a decision can't be reached (timeout or no device
// connected). "deny" (default) blocks the tool; "ask" defers to Claude Code's
// normal in-terminal permission prompt. Set HOOK_FALLBACK_BEHAVIOR=ask to
// avoid denying tools just because the watch was unreachable.
type FallbackBehavior = DecisionBehavior | "ask";
const fallbackBehavior: FallbackBehavior =
  (process.env.HOOK_FALLBACK_BEHAVIOR as FallbackBehavior) || "deny";

const hookInputSchema = z.object({
  hook_event_name: z.string(),
  session_id: z.string().optional(),
  tool_name: z.string(),
  tool_input: z.record(z.unknown()).default({}),
  permission_suggestions: z
    .array(
      z.object({
        type: z.string(),
        rules: z.array(z.string()),
        behavior: z.string(),
        destination: z.string(),
      })
    )
    .optional()
    .default([]),
  permission_mode: z.string().optional(),
  cwd: z.string().optional(),
});

/**
 * POST /hook/permission-request
 *
 * Blocking endpoint for Claude Code PermissionRequest hooks.
 * Queues the request, awaits a decision from the Apple Watch,
 * and returns the hook response.
 */
router.post("/permission-request", async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    // Validate auth token for hook requests
    const hookToken = process.env.HOOK_TOKEN;
    if (hookToken) {
      const authHeader = req.headers.authorization;
      if (!authHeader || authHeader !== `Bearer ${hookToken}`) {
        res.status(401).json({ error: "Invalid hook token" });
        return;
      }
    }

    const parsed = hookInputSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Invalid hook input", details: parsed.error.issues });
      return;
    }

    const hookInput: HookInput = parsed.data;
    const sessionId = hookInput.session_id || "unknown";

    logger.info({ toolName: hookInput.tool_name, sessionId }, "Received permission request hook");

    try {
      // Wait for a decision from the Apple Watch
      const decision = await decisionService.awaitDecision(
        {
          tool_name: hookInput.tool_name,
          tool_input: hookInput.tool_input,
          permission_suggestions: hookInput.permission_suggestions,
        },
        sessionId
      );

      // Format the response per Claude Code hook spec
      const response: HookResponse = {
        hookSpecificOutput: {
          hookEventName: "PermissionRequest",
          decision: {
            behavior: decision.behavior,
            ...(decision.updatedInput ? { updatedInput: decision.updatedInput } : {}),
            ...(decision.message ? { message: decision.message } : {}),
            ...(decision.interrupt ? { interrupt: decision.interrupt } : {}),
          },
          ...(decision.updatedPermissions
            ? { updatedPermissions: decision.updatedPermissions }
            : {}),
        },
      };

      logger.info(
        { toolName: hookInput.tool_name, behavior: decision.behavior },
        "Returning permission decision to Claude Code"
      );

      res.json(response);
    } catch (err: any) {
      // Timeout, no client connected, or session ended.
      const reason: string = err?.message || "Decision failed";
      const noClient = reason === "No client connected";
      logger.warn({ toolName: hookInput.tool_name, reason, fallbackBehavior }, "Decision failed (timeout/no-client/cancel)");

      const message = noClient
        ? "No Apple Watch/iPhone connected. Open the Claude Watch app, or approve in the terminal."
        : "Watch decision timed out. Approve or deny in the terminal.";

      // "ask" returns a normal 200 response deferring to the terminal prompt;
      // "deny" (default) keeps the legacy 408 + deny behaviour.
      const status = fallbackBehavior === "ask" ? 200 : 408;
      res.status(status).json({
        error: reason,
        hookSpecificOutput: {
          hookEventName: "PermissionRequest",
          decision: {
            behavior: fallbackBehavior as DecisionBehavior,
            message,
            interrupt: false,
          },
        },
      });
    }
  } catch (error) {
    next(error);
  }
});

/**
 * POST /hook/post-tool-use
 *
 * Non-blocking: receives tool usage notifications and broadcasts via SSE.
 */
router.post("/post-tool-use", (req: Request, res: Response) => {
  const { tool_name, tool_input } = req.body;
  logger.info({ toolName: tool_name }, "Post-tool-use event received");

  // This is a fire-and-forget notification — SSE broadcast would happen here
  // if there are connected iOS clients watching tool activity.

  res.json({ status: "ok" });
});

/**
 * POST /hook/stop
 *
 * Notifies that a Claude Code session has ended.
 * Cancels pending requests for that session only (so concurrent sessions
 * are not affected).
 */
router.post("/stop", (req: Request, res: Response) => {
  const sessionId = req.body?.session_id as string | undefined;
  logger.info({ sessionId }, "Session stop event received");
  decisionService.cancelAll(sessionId);
  res.json({ status: "ok" });
});

export default router;
