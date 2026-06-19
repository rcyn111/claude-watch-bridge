import SwiftUI

struct WatchContentView: View {
    var body: some View {
        NavigationStack {
            PermissionRequestView()
                .navigationTitle("Claude Watch")
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        NavigationLink(destination: RequestHistoryView()) {
                            Image(systemName: "clock")
                                .font(.caption)
                        }
                    }
                }
        }
    }
}
