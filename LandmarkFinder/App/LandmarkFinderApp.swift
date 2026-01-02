import SwiftUI
import GoogleSignIn

@main
struct LandmarkFinderApp: App {
    @StateObject private var env = AppEnvironment()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(env)
                .onAppear {
                    env.bootstrap()
                }
                .onOpenURL { url in
                    // Handle OAuth callback via GoogleSignIn using scene lifecycle
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Deprecated application(_:open:options:) removed.
    // Keep this class if you need other app-level delegate functionality.
}
