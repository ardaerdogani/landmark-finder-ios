import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        switch env.state {
        case .launching:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading session...")
                    .foregroundStyle(.secondary)
            }

        case .loggedOut:
            NavigationStack {
                LoginView()
            }

        case .loggedIn:
            TabView {
                NavigationStack {
                    CameraView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Logout") {
                                    Task { await env.logout() }
                                }
                            }
                        }
                }
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }

                NavigationStack {
                    HistoryView()
                }
                .tabItem {
                    Label("History", systemImage: "clock")
                }
            }
        }
    }
}
