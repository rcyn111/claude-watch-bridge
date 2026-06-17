import SwiftUI

struct PairingView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var bridgeHost = ""
    @State private var bridgePort = "3712"
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // Bridge connection settings
                Section("Bridge Server") {
                    HStack {
                        Text("Host")
                        TextField("e.g. 192.168.1.5", text: $bridgeHost)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("Port")
                        TextField("3712", text: $bridgePort)
                            .keyboardType(.numberPad)
                    }
                    Button("Connect") {
                        configureAndConnect()
                    }
                    .disabled(isPairing || bridgeHost.isEmpty)

                    if bridgeClient.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                // Pairing code entry
                Section("Pairing") {
                    Text("Enter the 6-digit code displayed in your terminal")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("000000", text: $pairingCode)
                        .font(.largeTitle.monospaced())
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .focused($isCodeFocused)
                        .disabled(isPairing || !bridgeClient.isConnected)
                        .onChange(of: pairingCode) { newValue in
                            // Auto-submit when 6 digits are entered
                            if newValue.count == 6 {
                                verifyCode()
                            }
                            // Limit to 6 characters
                            if newValue.count > 6 {
                                pairingCode = String(newValue.prefix(6))
                            }
                        }

                    Button(action: verifyCode) {
                        if isPairing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Verify")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairingCode.count != 6 || isPairing || !bridgeClient.isConnected)
                }

                // Error display
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Pair with Claude Watch")
            .onAppear {
                // Pre-fill with any previously saved host/port.
                if bridgeHost.isEmpty {
                    bridgeHost = bridgeClient.bridgeHost
                }
                if bridgePort == "3712" && bridgeClient.bridgePort != 3712 {
                    bridgePort = "\(bridgeClient.bridgePort)"
                }
            }
        }
    }

    private func configureAndConnect() {
        guard let port = Int(bridgePort) else {
            errorMessage = "Invalid port"
            return
        }
        bridgeClient.configure(host: bridgeHost, port: port)

        Task {
            let healthy = await bridgeClient.checkHealth()
            await MainActor.run {
                bridgeClient.isConnected = healthy
                if !healthy {
                    errorMessage = "Cannot reach bridge at \(bridgeHost):\(bridgePort)"
                } else {
                    errorMessage = nil
                }
            }
        }
    }

    private func verifyCode() {
        isPairing = true
        errorMessage = nil

        Task {
            do {
                let token = try await bridgeClient.verifyPairingCode(pairingCode)
                try? KeychainManager.saveToken(token)
                await MainActor.run {
                    isPairing = false
                    pairingCode = ""
                }
                // Begin receiving permission requests over SSE.
                bridgeClient.startListening()
            } catch {
                await MainActor.run {
                    isPairing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
