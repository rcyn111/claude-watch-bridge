import { Response } from "express";
import { logger } from "../utils/logger";
import { SSEEvent } from "../types";
import { config } from "../config";

class SSEService {
  private clients = new Map<string, { res: Response; heartbeat: NodeJS.Timeout }>();

  /**
   * Invoked whenever a new SSE client (the iOS app) connects. The decision
   * service uses this to extend the decision window for requests that were
   * waiting for a client to appear.
   */
  onClientConnected?: () => void;

  addClient(clientId: string, res: Response): void {
    // Set SSE headers
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });

    // Send initial connection event
    this.sendToClient(res, {
      type: "heartbeat",
      message: "connected",
    });

    const heartbeat = setInterval(() => {
      try {
        res.write(": heartbeat\n\n");
      } catch {
        clearInterval(heartbeat);
        this.clients.delete(clientId);
      }
    }, config.sseHeartbeatSeconds * 1000);

    this.clients.set(clientId, { res, heartbeat });
    logger.info({ clientId, total: this.clients.size }, "SSE client connected");

    // Notify listeners (e.g. decision service) that a client is now available.
    try {
      this.onClientConnected?.();
    } catch (err) {
      logger.warn({ err }, "onClientConnected callback threw");
    }

    res.on("close", () => {
      clearInterval(heartbeat);
      this.clients.delete(clientId);
      logger.info({ clientId, total: this.clients.size }, "SSE client disconnected");
    });
  }

  broadcast(event: SSEEvent): void {
    const eventType = event.type;
    const payload = `event: ${eventType}\ndata: ${JSON.stringify(event)}\n\n`;

    this.clients.forEach(({ res }, id) => {
      try {
        res.write(payload);
      } catch {
        this.clients.delete(id);
      }
    });
  }

  broadcastPermissionRequest(event: SSEEvent): void {
    this.broadcast(event);
  }

  private sendToClient(res: Response, event: SSEEvent): void {
    const eventType = event.type;
    const payload = `event: ${eventType}\ndata: ${JSON.stringify(event)}\n\n`;
    res.write(payload);
  }

  getConnectedCount(): number {
    return this.clients.size;
  }
}

export const sseService = new SSEService();
