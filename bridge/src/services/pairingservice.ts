import { randomBytes, randomInt } from "crypto";
import fs from "fs";
import { config } from "../config";
import { PairingCode, PairingSession } from "../types";
import { logger } from "../utils/logger";

interface StoredSession extends PairingSession {}

export class PairingService {
  private activeCode: PairingCode | null = null;
  private activeSessions = new Map<string, PairingSession>();

  constructor() {
    this.load();
  }

  generateCode(): PairingCode {
    const min = Math.pow(10, config.pairingCodeLength - 1);
    const max = Math.pow(10, config.pairingCodeLength) - 1;
    const code = randomInt(min, max + 1).toString().padStart(config.pairingCodeLength, "0");

    this.activeCode = {
      code,
      expiresAt: Date.now() + config.pairingCodeExpirySeconds * 1000,
    };

    logger.info({ code, expiresIn: config.pairingCodeExpirySeconds }, "New pairing code generated");
    return this.activeCode;
  }

  verifyCode(code: string): string | null {
    if (!this.activeCode) return null;
    if (Date.now() > this.activeCode.expiresAt) {
      this.activeCode = null;
      logger.info("Pairing code expired");
      return null;
    }
    if (this.activeCode.code !== code) return null;

    // Code valid — create session token
    const token = randomBytes(config.tokenLength).toString("hex");
    const sessionId = randomBytes(16).toString("hex");
    const now = Date.now();
    const ttlMs = (config.sessionTtlSeconds ?? 7 * 24 * 60 * 60) * 1000;
    const session: PairingSession = {
      token,
      sessionId,
      createdAt: now,
      expiresAt: now + ttlMs,
    };
    this.activeSessions.set(token, session);
    this.persist();

    this.activeCode = null;
    logger.info({ sessionId, expiresAt: new Date(session.expiresAt).toISOString() }, "Pairing verified, session created");
    return token;
  }

  validateToken(token: string): boolean {
    const session = this.activeSessions.get(token);
    if (!session) return false;
    if (Date.now() >= session.expiresAt) {
      this.activeSessions.delete(token);
      this.persist();
      logger.info({ sessionId: session.sessionId }, "Session token expired, revoked");
      return false;
    }
    return true;
  }

  getSession(token: string): PairingSession | null {
    return this.activeSessions.get(token) || null;
  }

  revokeSession(token: string): boolean {
    const removed = this.activeSessions.delete(token);
    if (removed) this.persist();
    return removed;
  }

  getSessionCount(): number {
    return this.activeSessions.size;
  }

  /** Remove all expired sessions. */
  pruneExpired(): number {
    const now = Date.now();
    let removed = 0;
    for (const [token, session] of this.activeSessions) {
      if (now >= session.expiresAt) {
        this.activeSessions.delete(token);
        removed++;
      }
    }
    if (removed > 0) this.persist();
    return removed;
  }

  // --- Persistence -------------------------------------------------------

  private load(): void {
    const path = config.sessionStorePath;
    if (!path) return; // persistence disabled (e.g. in tests)
    try {
      const raw = fs.readFileSync(path, "utf8");
      const data = JSON.parse(raw) as { sessions?: StoredSession[] };
      const now = Date.now();
      for (const s of data.sessions ?? []) {
        if (s && typeof s.token === "string" && now < s.expiresAt) {
          this.activeSessions.set(s.token, s);
        }
      }
      if (this.activeSessions.size > 0) {
        logger.info({ count: this.activeSessions.size }, "Restored pairing sessions from disk");
      }
    } catch (err: any) {
      if (err?.code !== "ENOENT") {
        logger.warn({ err }, "Failed to load pairing sessions, starting fresh");
      }
    }
  }

  private persist(): void {
    const path = config.sessionStorePath;
    if (!path) return; // persistence disabled
    try {
      fs.mkdirSync(config.dataDir, { recursive: true });
      const data = { sessions: Array.from(this.activeSessions.values()) };
      fs.writeFileSync(path, JSON.stringify(data, null, 2), "utf8");
    } catch (err) {
      logger.warn({ err }, "Failed to persist pairing sessions");
    }
  }
}

export const pairingService = new PairingService();
