import { DecisionService } from "../../src/services/decisionservice";
import { sseService } from "../../src/services/sseservice";
import { PermissionDecision, DecisionBehavior } from "../../src/types";

// Mock SSE service
jest.mock("../../src/services/sseservice", () => ({
  sseService: {
    broadcastPermissionRequest: jest.fn(),
    broadcast: jest.fn(),
    getConnectedCount: jest.fn().mockReturnValue(1),
    // onClientConnected is assigned by DecisionService at construction.
  },
}));

// Mock logger
jest.mock("../../src/utils/logger", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

// Mock config to use shorter timeout for tests
jest.mock("../../src/config", () => ({
  config: {
    hookTimeoutSeconds: 2,
    noClientGraceSeconds: 1,
    port: 3712,
    host: "127.0.0.1",
  },
}));

describe("DecisionService", () => {
  let service: DecisionService;

  beforeEach(() => {
    service = new DecisionService();
  });

  it("should create a pending request and resolve on decision", async () => {
    const hookInput = {
      tool_name: "Bash",
      tool_input: { command: "ls -la" },
      permission_suggestions: [],
    };

    const decisionPromise = service.awaitDecision(hookInput, "test-session");

    // Submit a decision
    const decision: PermissionDecision = {
      requestId: "",
      behavior: "allow",
      timestamp: new Date().toISOString(),
    };

    // Get the requestId from pending list
    const pending = service.getPendingList();
    expect(pending.length).toBe(1);
    decision.requestId = pending[0].requestId;

    const resolved = service.submitDecision(decision.requestId, decision);
    expect(resolved).toBe(true);

    const result = await decisionPromise;
    expect(result.behavior).toBe("allow");
    expect(service.getPendingCount()).toBe(0);
  });

  it("should reject on timeout", async () => {
    const hookInput = {
      tool_name: "Read",
      tool_input: { file_path: "/tmp/test.txt" },
      permission_suggestions: [],
    };

    await expect(
      service.awaitDecision(hookInput, "test-session")
    ).rejects.toThrow("Decision timeout");

    expect(service.getPendingCount()).toBe(0);
  });

  it("should return false for unknown requestId", () => {
    const decision: PermissionDecision = {
      requestId: "nonexistent-id",
      behavior: "allow",
      timestamp: new Date().toISOString(),
    };

    expect(service.submitDecision("nonexistent-id", decision)).toBe(false);
  });

  it("should handle multiple concurrent requests", async () => {
    const promises = [];
    for (let i = 0; i < 3; i++) {
      promises.push(
        service.awaitDecision(
          { tool_name: "Bash", tool_input: { command: `cmd${i}` }, permission_suggestions: [] },
          "session"
        )
      );
    }

    expect(service.getPendingCount()).toBe(3);

    // Resolve each one
    const pending = service.getPendingList();
    for (const p of pending) {
      service.submitDecision(p.requestId, {
        requestId: p.requestId,
        behavior: "deny",
        timestamp: new Date().toISOString(),
      });
    }

    const results = await Promise.all(promises);
    expect(results.every((r) => r.behavior === "deny")).toBe(true);
    expect(service.getPendingCount()).toBe(0);
  });

  it("should cancel all on cancelAll", async () => {
    const promises = [];
    for (let i = 0; i < 2; i++) {
      promises.push(
        service.awaitDecision(
          { tool_name: "Bash", tool_input: { command: `cmd${i}` }, permission_suggestions: [] },
          "session"
        )
      );
    }

    service.cancelAll();

    for (const p of promises) {
      await expect(p).rejects.toThrow("Session ended");
    }
    expect(service.getPendingCount()).toBe(0);
  });

  it("should only cancel pending requests for the given session", async () => {
    const promiseA = service.awaitDecision(
      { tool_name: "Bash", tool_input: { command: "a" }, permission_suggestions: [] },
      "session-a"
    );
    const promiseB = service.awaitDecision(
      { tool_name: "Bash", tool_input: { command: "b" }, permission_suggestions: [] },
      "session-b"
    );

    expect(service.getPendingCount()).toBe(2);

    // Cancel only session-a; session-b must remain pending.
    service.cancelAll("session-a");

    await expect(promiseA).rejects.toThrow("Session ended");
    expect(service.getPendingCount()).toBe(1);

    // session-b should still resolve normally when decided.
    const pending = service.getPendingList();
    expect(pending.length).toBe(1);
    service.submitDecision(pending[0].requestId, {
      requestId: pending[0].requestId,
      behavior: "allow",
      timestamp: new Date().toISOString(),
    });
    await expect(promiseB).resolves.toMatchObject({ behavior: "allow" });
  });

  it("should fail fast with 'No client connected' when no SSE client is present", async () => {
    (sseService.getConnectedCount as jest.Mock).mockReturnValue(0);

    const start = Date.now();
    await expect(
      service.awaitDecision(
        { tool_name: "Bash", tool_input: { command: "ls" }, permission_suggestions: [] },
        "session"
      )
    ).rejects.toThrow("No client connected");

    // Should reject after the grace window (1s), not the full 2s timeout.
    const elapsed = Date.now() - start;
    expect(elapsed).toBeLessThan(1900);
    expect(service.getPendingCount()).toBe(0);

    // Restore for subsequent tests.
    (sseService.getConnectedCount as jest.Mock).mockReturnValue(1);
  });
});
