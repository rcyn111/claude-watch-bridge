// NOTE: Bonjour discovery is experimental and currently unused in the app.
//       The bridge binds to 127.0.0.1 by default for security; to use Bonjour
//       you must set HOST=0.0.0.0 on the bridge. When that is enabled, this
//       file should be rewritten to use NetServiceBrowser + NetService for
//       proper service resolution (the current NWBrowser skeleton does not
//       resolve endpoints).  For now, enter your Mac's LAN IP manually.

import Foundation
import Network

@MainActor
class BonjourDiscovery: ObservableObject {
    @Published var discoveredBridges: [BridgeInfo] = []
    @Published var isSearching = false

    private var browser: NWBrowser?

    struct BridgeInfo: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
    }

    func startSearching() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let serviceType = "_claude-watch._tcp"
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed(let error):
                    print("Bonjour browser failed: \(error)")
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                var bridges: [BridgeInfo] = []
                for result in results {
                    switch result.endpoint {
                    case .service(let name, let type, let domain, let interface):
                        // Try to resolve the endpoint to get host and port
                        bridges.append(BridgeInfo(
                            name: name,
                            host: "\(name).\(type).\(domain)",
                            port: 3712  // Default, will be resolved properly
                        ))
                    default:
                        break
                    }
                }
                self?.discoveredBridges = bridges
            }
        }

        browser?.start(queue: .main)
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
}
