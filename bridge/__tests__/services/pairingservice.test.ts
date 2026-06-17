import { PairingService } from "../../src/services/pairingservice";

// Mock config
jest.mock("../../src/config", () => ({
  config: {
    pairingCodeExpirySeconds: 2,
    pairingCodeLength: 6,
    tokenLength: 8,
  },
}));

// Mock logger
jest.mock("../../src/utils/logger", () => ({
  logger: {
    info: jest.fn(),
  },
}));

describe("PairingService", () => {
  let service: PairingService;

  beforeEach(() => {
    service = new PairingService();
  });

  it("should generate a 6-digit pairing code", () => {
    const code = service.generateCode();
    expect(code.code).toMatch(/^\d{6}$/);
    expect(code.expiresAt).toBeGreaterThan(Date.now());
  });

  it("should verify a valid code and return a token", () => {
    const code = service.generateCode();
    const token = service.verifyCode(code.code);

    expect(token).toBeTruthy();
    expect(token!.length).toBe(16); // 8 bytes = 16 hex chars
    expect(service.getSessionCount()).toBe(1);
  });

  it("should reject an invalid code", () => {
    service.generateCode();
    const token = service.verifyCode("000000");
    expect(token).toBeNull();
  });

  it("should expire codes after timeout", async () => {
    const code = service.generateCode();

    // Wait for expiry
    await new Promise((resolve) => setTimeout(resolve, 2500));

    const token = service.verifyCode(code.code);
    expect(token).toBeNull();
  });

  it("should consume the code after successful verification", () => {
    const code = service.generateCode();
    service.verifyCode(code.code);

    // Second attempt should fail
    const secondToken = service.verifyCode(code.code);
    expect(secondToken).toBeNull();
  });

  it("should validate stored tokens", () => {
    const code = service.generateCode();
    const token = service.verifyCode(code.code);

    expect(service.validateToken(token!)).toBe(true);
    expect(service.validateToken("invalid-token")).toBe(false);
  });

  it("should revoke sessions", () => {
    const code = service.generateCode();
    const token = service.verifyCode(code.code);

    expect(service.getSessionCount()).toBe(1);
    expect(service.revokeSession(token!)).toBe(true);
    expect(service.getSessionCount()).toBe(0);
    expect(service.validateToken(token!)).toBe(false);
  });

  it("should not verify if no code is active", () => {
    const token = service.verifyCode("123456");
    expect(token).toBeNull();
  });
});
