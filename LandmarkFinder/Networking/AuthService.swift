import Foundation
import GoogleSignIn
import UIKit

final class AuthService {
    private let api = APIClient.shared
    private let tokens = AuthTokenStore.shared

    func register(email: String, password: String) async throws {
        let resp: TokenResponse = try await api.request(
            method: "POST",
            path: Endpoints.Auth.register,
            body: AuthRequest(email: email, password: password),
            requiresAuth: false
        )
        tokens.setAccessToken(resp.access_token)
        tokens.setRefreshToken(resp.refresh_token)
    }

    func login(email: String, password: String) async throws {
        let resp: TokenResponse = try await api.request(
            method: "POST",
            path: Endpoints.Auth.login,
            body: AuthRequest(email: email, password: password),
            requiresAuth: false
        )
        tokens.setAccessToken(resp.access_token)
        tokens.setRefreshToken(resp.refresh_token)
    }

    func logout() async throws {
        guard let refresh = tokens.getRefreshToken() else {
            tokens.clearAll()
            return
        }
        struct RevokedResp: Codable { let revoked: Bool }

        _ = try await api.request(
            method: "POST",
            path: Endpoints.Auth.logout,
            body: LogoutRequest(refresh_token: refresh),
            requiresAuth: false,
            retryOn401: false
        ) as RevokedResp

        tokens.clearAll()
    }

    func me() async throws -> MeResponse {
        try await api.request(
            method: "GET",
            path: Endpoints.User.me,
            requiresAuth: true
        )
    }

    // MARK: - Google Sign-In

    // Presents Google Sign-In, exchanges ID token with backend, persists JWTs.
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        // If the user has an existing Google session, prefer that.
        let signInResult: GIDSignInResult
        if viewController.view.window?.windowScene != nil {
            // Use the overload that supports hint/additionalScopes if you want to pass them,
            // but do not pass a configuration here; it is not supported in this overload.
            signInResult = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: []
            )
        } else {
            signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw NSError(domain: "AuthService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"])
        }

        let resp: TokenResponse = try await api.request(
            method: "POST",
            path: Endpoints.Auth.google,
            body: GoogleAuthRequest(id_token: idToken),
            requiresAuth: false
        )

        tokens.setAccessToken(resp.access_token)
        tokens.setRefreshToken(resp.refresh_token)
    }

    func signOutGoogle() {
        GIDSignIn.sharedInstance.signOut()
    }
}

// Helper to supply a clientID if you want to set per-scene configuration.
// If you use GoogleService-Info.plist via Firebase, you can read the client ID from it instead.
// For simple setups, you can remove the configuration parameter above and rely on Info.plist.
enum GoogleClientIDProvider {
    static func clientID(for _: UIWindowScene) -> String {
        // If using Firebase, return FirebaseApp.app()?.options.clientID ?? ""
        // Or hardcode your OAuth client ID string here.
        // Leaving empty uses default configuration from Info.plist if present.
        return ""
    }
}
