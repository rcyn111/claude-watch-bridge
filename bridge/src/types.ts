// ---- Claude Code Hook Input ----

export interface HookInput {
  hook_event_name: string;
  session_id?: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
  permission_suggestions?: PermissionSuggestion[];
  permission_mode?: string;
  cwd?: string;
  transcript_path?: string;
}

export interface PermissionSuggestion {
  type: string;
  rules: string[];
  behavior: string;
  destination: string;
}

// ---- Internal Permission Request ----

export interface PermissionRequest {
  id: string;
  requestId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  permissionSuggestions: PermissionSuggestion[];
  timeoutSeconds: number;
  receivedAt: Date;
}

export function toolInputCommand(input: Record<string, unknown>): string {
  if (typeof input.command === "string") return input.command;
  if (typeof input.file_path === "string") return input.file_path;
  return JSON.stringify(input);
}

// ---- Permission Decision ----

export type DecisionBehavior = "allow" | "deny";

export interface PermissionDecision {
  requestId: string;
  behavior: DecisionBehavior;
  updatedInput?: Record<string, unknown>;
  updatedPermissions?: PermissionUpdate[];
  message?: string;
  interrupt?: boolean;
  timestamp: string;
}

export interface PermissionUpdate {
  type: "addRules" | "replaceRules" | "removeRules";
  rules: string[];
  behavior: string;
  destination: string;
}

// ---- Hook Response (to Claude Code) ----

export interface HookResponse {
  hookSpecificOutput: {
    hookEventName: string;
    decision: {
      behavior: DecisionBehavior;
      updatedInput?: Record<string, unknown>;
      message?: string;
      interrupt?: boolean;
    };
    updatedPermissions?: PermissionUpdate[];
  };
}

// ---- SSE Events ----

export interface SSEEvent {
  type: "permission_request" | "tool_use" | "session_ended" | "heartbeat" | "error";
  requestId?: string;
  toolName?: string;
  toolInput?: Record<string, unknown>;
  suggestions?: PermissionSuggestion[];
  deadline?: string;
  status?: string;
  message?: string;
  createdAt?: string;
}

// ---- Pairing ----

export interface PairingCode {
  code: string;
  expiresAt: number;
}

export interface PairingSession {
  token: string;
  sessionId: string;
  createdAt: number;
  expiresAt: number;
}

export interface PairingVerifyRequest {
  code: string;
}

export interface PairingVerifyResponse {
  token: string;
  expiresAt: string;
}

// ---- Pending Request (for status) ----

export interface PendingRequest {
  requestId: string;
  toolName: string;
  receivedAt: string;
  deadline: string;
  timeoutSeconds: number;
}
