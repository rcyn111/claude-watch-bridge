import request from "supertest";
import express from "express";
import hookRoutes from "../../src/routes/hook";
import { errorHandler } from "../../src/middleware/errorHandler";

// Mock services — use jest.fn() directly in the factory (not variables)
// because jest.mock calls are hoisted above const declarations.
jest.mock("../../src/services/decisionservice", () => ({
  decisionService: {
    awaitDecision: jest.fn(),
    submitDecision: jest.fn(),
    cancelAll: jest.fn(),
    getPendingCount: jest.fn(),
    getPendingList: jest.fn(),
  },
}));

jest.mock("../../src/services/pairingservice", () => ({
  pairingService: {
    validateToken: jest.fn().mockReturnValue(true),
  },
}));

jest.mock("../../src/utils/logger", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

const { decisionService } = require("../../src/services/decisionservice");

function createTestApp() {
  const app = express();
  app.use(express.json());
  app.use("/hook", hookRoutes);
  app.use(errorHandler);
  return app;
}

describe("Hook Routes", () => {
  let app: express.Application;

  beforeEach(() => {
    jest.clearAllMocks();
    app = createTestApp();
  });

  describe("POST /hook/permission-request", () => {
    it("should return 400 for invalid hook input", async () => {
      const res = await request(app)
        .post("/hook/permission-request")
        .send({ invalid: "data" });

      expect(res.status).toBe(400);
      expect(res.body.error).toBe("Invalid hook input");
    });

    it("should process a valid permission request and return decision", async () => {
      (decisionService.awaitDecision as jest.Mock).mockResolvedValue({
        requestId: "test-id",
        behavior: "allow",
        timestamp: new Date().toISOString(),
      });

      const res = await request(app)
        .post("/hook/permission-request")
        .send({
          hook_event_name: "PermissionRequest",
          session_id: "test-session",
          tool_name: "Bash",
          tool_input: { command: "ls -la" },
          permission_suggestions: [],
        });

      expect(res.status).toBe(200);
      expect(res.body.hookSpecificOutput).toBeDefined();
      expect(res.body.hookSpecificOutput.decision.behavior).toBe("allow");
      expect(decisionService.awaitDecision).toHaveBeenCalledTimes(1);
    });

    it("should return 408 on decision timeout", async () => {
      (decisionService.awaitDecision as jest.Mock).mockRejectedValue(
        new Error("Decision timeout")
      );

      const res = await request(app)
        .post("/hook/permission-request")
        .send({
          hook_event_name: "PermissionRequest",
          session_id: "test-session",
          tool_name: "Bash",
          tool_input: { command: "rm -rf /" },
          permission_suggestions: [],
        });

      expect(res.status).toBe(408);
    });
  });

  describe("POST /hook/post-tool-use", () => {
    it("should accept tool use notifications", async () => {
      const res = await request(app)
        .post("/hook/post-tool-use")
        .send({
          tool_name: "Read",
          tool_input: { file_path: "/tmp/test.txt" },
        });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe("ok");
    });
  });

  describe("POST /hook/stop", () => {
    it("should cancel all pending requests on session stop", async () => {
      const res = await request(app).post("/hook/stop").send({});

      expect(res.status).toBe(200);
      expect(res.body.status).toBe("ok");
      expect(decisionService.cancelAll).toHaveBeenCalled();
    });
  });
});
