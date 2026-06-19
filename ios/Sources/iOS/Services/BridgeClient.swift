import Foundation

enum BridgeError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case pairingFailed
    case decisionFailed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Bridge URL not configured"
        case .notAuthenticated: return "Not authenticated with bridge"
        case .pairingFailed: return "Pairing verification failed"
        case .decisionFailed: return "Failed to submit decision"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        }
    }
}

@MainActor
class BridgeClient: ObservableObject {
    @Published var isConnected = false
    @Published var bridgeURL: URL?
    @Published var sessionToken: String?
    @Published var bridgeHost: String = ""
    @Published var bridgePort: Int = 3712
    @Published var lastSSE: String = "—"

    private var listenTask: Task<Void, Never>?
    private var urlSession: URLSession

    var onEvent: ((BridgeEvent) -> Void)?

    private let defaults = UserDefaults.standard
    private let hostKey = "bridgeHost"
    private let portKey = "bridgePort"

    init() {
        let config = URLSessionConfiguration.default
        // Generous request timeout so the 30s SSE heartbeat keeps the stream
        // alive without spuriously timing out.
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 3600
        self.urlSession = URLSession(configuration: config)

        // Restore saved host/port so the app reconnects without re-entry.
        if defaults.object(forKey: portKey) != nil {
            bridgePort = defaults.integer(forKey: portKey)
        }
        if let savedHost = defaults.string(forKey: hostKey), !savedHost.isEmpty {
            bridgeHost = savedHost
            bridgeURL = URL(string: "http://\(savedHost):\(bridgePort)")
        }
    }

    /// Build the bridge URL from host and port, and persist them.
    func configure(host: String, port: Int) {
        bridgeHost = host
        bridgePort = port
        bridgeURL = URL(string: "http://\(host):\(port)")
        defaults.set(host, forKey: hostKey)
        defaults.set(port, forKey: portKey)
        isConnected = false
    }

    // MARK: - Pairing

    /// Request a new pairing code from the bridge
    func requestPairingCode() async throws -> String {
        guard let url = bridgeURL else { throw BridgeError.notConfigured }

        var request = URLRequest(url: url.appendingPathComponent("/pair"))
        request.httpMethod = "POST"

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.pairingFailed
        }

        struct PairingResponse: Codable { let code: String; let expiresIn: Int }
        let result = try JSONDecoder().decode(PairingResponse.self, from: data)
        return result.code
    }

    /// Verify a pairing code and receive a session token
    func verifyPairingCode(_ code: String) async throws -> String {
        guard let url = bridgeURL else { throw BridgeError.notConfigured }

        var request = URLRequest(url: url.appendingPathComponent("/pair/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.pairingFailed
        }

        struct VerifyResponse: Codable { let token: String; let expiresAt: String }
        let result = try JSONDecoder().decode(VerifyResponse.self, from: data)
        self.sessionToken = result.token
        return result.token
    }

    // MARK: - SSE (streaming + auto-reconnect)

    /// Start a background task that connects to the SSE event stream and stays
    /// connected, reconnecting with exponential backoff on any disconnect.
    /// Events are delivered via `onEvent`.
    func startListening() {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            guard let self else { return }
            var backoff: TimeInterval = 1
            while !Task.isCancelled {
                guard let url = self.bridgeURL, let token = self.sessionToken else {
                    self.isConnected = false
                    self.lastSSE = "no url/token"
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                self.lastSSE = "loop"
                do {
                    self.lastSSE = "connecting..."
                    var request = URLRequest(url: url.appendingPathComponent("/events"))
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    self.lastSSE = "req sent"
                    let (bytes, response) = try await self.urlSession.bytes(for: request)
                    self.lastSSE = "got resp"
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        self.lastSSE = "bad status"
                        // 401 etc. — token may be invalid; back off and retry.
                        self.isConnected = false
                        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                        backoff = min(backoff * 2, 30)
                        continue
                    }

                    self.isConnected = true
                    backoff = 1

                    var eventType = ""
                    var dataBuffer = ""
                    var eventCount = 0
                    var lineCount = 0
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        lineCount += 1
                        if line.hasPrefix("event: ") {
                            eventType = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data: ") {
                            dataBuffer = String(line.dropFirst(6))
                        } else if line.isEmpty {
                            eventCount += 1
                            if eventType != "heartbeat", !dataBuffer.isEmpty,
                               let data = dataBuffer.data(using: .utf8),
                               let event = try? JSONDecoder().decode(BridgeEvent.self, from: data) {
                                self.lastSSE = "#\(eventCount): \(event.type.rawValue)"
                                self.onEvent?(event)
                            } else {
                                self.lastSSE = "ev#\(eventCount): \(eventType)"
                            }
                            eventType = ""
                            dataBuffer = ""
                        }
                    }
                    self.lastSSE = "end:\(lineCount)L"

                    // Stream ended (server restart, network drop) — reconnect.
                    self.isConnected = false
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    backoff = min(backoff * 2, 30)
                } catch is CancellationError {
                    break
                } catch {
                    self.isConnected = false
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    backoff = min(backoff * 2, 30)
                }
            }
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        isConnected = false
    }

    // MARK: - Decisions

    /// Submit a decision back to the bridge
    func submitDecision(_ decision: PermissionDecision) async throws {
        guard let url = bridgeURL, let token = sessionToken else {
            throw BridgeError.notAuthenticated
        }

        var request = URLRequest(url: url.appendingPathComponent("/decisions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(decision)

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeError.decisionFailed
        }
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard let url = bridgeURL else { return false }
        do {
            var request = URLRequest(url: url.appendingPathComponent("/health"))
            request.timeoutInterval = 5
            let (_, response) = try await urlSession.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
