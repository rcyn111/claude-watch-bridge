import { randomUUID } from "crypto";
import { PermissionRequest, PermissionDecision, DecisionBehavior } from "../types";
import { sseService } from "./sseservice";
import { config } from "../config";
import { logger } from "../utils/logger";

interface PendingEntry {
  request: PermissionRequest;
  sessionId: string;
  resolve: (decision: PermissionDecision) => void;
  reject: (error: Error) => void;
  createdAt: number;
  deadlineMs: number;
  /** True while we're still waiting for a phone/watch client to connect. */
  awaitingClient: boolean;
  timer: NodeJS.Timeout;
}

export class DecisionService {
  private pendingRequests = new Map<string, PendingEntry>();

  constructor() {
    // When a client connects, extend any requests that were waiting for one
    // to use the full decision window instead of the short no-client grace.
    sseService.onClientConnected = () => this.notifyClientConnected();
  }

  /**
   * Queue a permission request and wait for a decision.
   * Returns a Promise that resolves when the decision is submitted or rejects
   * on timeout / no-client / session-ended.
   *
   * If no SSE client (phone/watch) is connected when the request arrives, we
   * only wait a short grace period (`noClientGraceSeconds`) rather than the
   * full `HOOK_TIMEOUT`, so Claude Code is not blocked for minutes when the
   * watch is unreachable. If a client connects during the grace window, the
   * request is upgraded to the full timeout.
   */
  async awaitDecision(
    hookInput: {
      tool_name: string;
      tool_input: Record<string, unknown>;
      permission_suggestions?: { type: string; rules: string[]; behavior: string; destination: string }[];
    },
    sessionId: string
  ): Promise<PermissionDecision> {
    const requestId = randomUUID();
    const timeoutMs = config.hookTimeoutSeconds * 1000;
    const createdAt = Date.now();
    const deadlineMs = createdAt + timeoutMs;
    const hasClient = sseService.getConnectedCount() > 0;

    const request: PermissionRequest = {
      id: requestId,
      requestId,
      toolName: hookInput.tool_name,
      toolInput: hookInput.tool_input,
      permissionSuggestions: hookInput.permission_suggestions ?? [],
      timeoutSeconds: config.hookTimeoutSeconds,
      receivedAt: new Date(createdAt),
    };

    const entry: PendingEntry = {
      request,
      sessionId,
      resolve: undefined as unknown as (d: PermissionDecision) => void,
      reject: undefined as unknown as (e: Error) => void,
      createdAt,
      deadlineMs,
      awaitingClient: !hasClient,
      timer: undefined as unknown as NodeJS.Timeout,
    };

    return new Promise((resolve, reject) => {
      entry.resolve = resolve;
      entry.reject = reject;
      this.pendingRequests.set(requestId, entry);
      this.armTimer(entry);

      // Broadcast the pending request to all SSE clients
      sseService.broadcastPermissionRequest({
        type: "permission_request",
        requestId,
        toolName: request.toolName,
        toolInput: request.toolInput,
        suggestions: request.permissionSuggestions,
        createdAt: request.receivedAt.toISOString(),
        deadline: new Date(deadlineMs).toISOString(),
      });

      logger.info(
        { requestId, toolName: request.toolName, sessionId, awaitingClient: entry.awaitingClient },
        "Permission request queued, awaiting decision"
      );
    });
  }

  /**
   * (Re)arm the timeout timer for a pending entry.
   * While awaiting a client, the timer fires at the end of the short grace
   * window; once a client is connected, it fires at the request deadline.
   */
  private armTimer(entry: PendingEntry): void {
    if (entry.timer) clearTimeout(entry.timer);

    const graceMs = (config.noClientGraceSeconds ?? 3) * 1000;
    const fireAt = entry.awaitingClient
      ? Math.min(entry.deadlineMs, entry.createdAt + graceMs)
      : entry.deadlineMs;
    const delay = Math.max(0, fireAt - Date.now());

    entry.timer = setTimeout(() => {
      if (!this.pendingRequests.has(entry.request.id)) return;
      this.pendingRequests.delete(entry.request.id);
      const reason = entry.awaitingClient ? "No client connected" : "Decision timeout";
      logger.warn({ requestId: entry.request.id, toolName: entry.request.toolName, reason }, "Permission request expired");
      entry.reject(new Error(reason));
    }, delay);
  }

  /** Called by the SSE service when a phone/watch client connects. */
  private notifyClientConnected(): void {
    this.pendingRequests.forEach((entry) => {
      if (!entry.awaitingClient) return;
      entry.awaitingClient = false;
      this.armTimer(entry);
      logger.info({ requestId: entry.request.id }, "Client connected; awaiting full decision window");
    });
  }

  /**
   * Submit a decision for a pending request.
   * Returns true if the request was found and resolved, false if already handled or expired.
   */
  submitDecision(requestId: string, decision: PermissionDecision): boolean {
    const pending = this.pendingRequests.get(requestId);
    if (!pending) {
      logger.warn({ requestId }, "Decision submitted for unknown/expired request");
      return false;
    }

    clearTimeout(pending.timer);
    this.pendingRequests.delete(requestId);
    pending.resolve(decision);

    logger.info(
      { requestId, behavior: decision.behavior, toolName: pending.request.toolName },
      "Decision resolved"
    );
    return true;
  }

  /**
   * Cancel pending requests. If `sessionId` is given, only requests from that
   * Claude session are cancelled; otherwise all pending requests are cancelled.
   */
  cancelAll(sessionId?: string): void {
    let cancelled = 0;
    this.pendingRequests.forEach((entry, id) => {
      if (sessionId && entry.sessionId !== sessionId) return;
      clearTimeout(entry.timer);
      this.pendingRequests.delete(id);
      entry.reject(new Error("Session ended"));
      cancelled++;
    });
    if (cancelled > 0) {
      logger.info({ sessionId, cancelled }, "Pending permission requests cancelled");
    }
  }

  getPendingCount(): number {
    return this.pendingRequests.size;
  }

  getPendingList(): { requestId: string; toolName: string; sessionId: string; receivedAt: string; deadline: string; timeoutSeconds: number }[] {
    const list: { requestId: string; toolName: string; sessionId: string; receivedAt: string; deadline: string; timeoutSeconds: number }[] = [];
    this.pendingRequests.forEach((entry, requestId) => {
      list.push({
        requestId,
        toolName: entry.request.toolName,
        sessionId: entry.sessionId,
        receivedAt: entry.request.receivedAt.toISOString(),
        deadline: new Date(entry.deadlineMs).toISOString(),
        timeoutSeconds: config.hookTimeoutSeconds,
      });
    });
    return list;
  }
}

export const decisionService = new DecisionService();
