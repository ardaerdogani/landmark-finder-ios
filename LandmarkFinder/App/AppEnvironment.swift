import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
final class AppEnvironment: ObservableObject {
    enum State: Equatable {
        case launching
        case loggedOut
        case loggedIn(email: String)
    }

    @Published private(set) var state: State = .launching
    @Published var errorMessage: String?

    private let auth = AuthService()
    private let tokens = AuthTokenStore.shared
    private let deviceService = DeviceService()
    private let deviceIdStore = DeviceIDStore.shared

    func bootstrap() {
        Task {
            do {
                if tokens.getRefreshToken() != nil {
                    try await forceRefreshTokens()
                    let me = try await auth.me()
                    await registerDeviceIfNeeded()
                    state = .loggedIn(email: me.email)
                } else {
                    state = .loggedOut
                }
            } catch {
                tokens.clearAll()
                errorMessage = "Session expired. Please login again."
                state = .loggedOut
            }
        }
    }

    func login(email: String, password: String) async {
        do {
            try await auth.login(email: email, password: password)
            let me = try await auth.me()
            await registerDeviceIfNeeded()
            state = .loggedIn(email: me.email)
        } catch {
            errorMessage = "Login failed. Check email/password."
        }
    }

    func register(email: String, password: String) async {
        do {
            try await auth.register(email: email, password: password)
            let me = try await auth.me()
            await registerDeviceIfNeeded()
            state = .loggedIn(email: me.email)
        } catch {
            errorMessage = "Registration failed. Try a different email or password."
        }
    }

    func googleLogin(presenting: UIViewController) async {
        do {
            try await auth.signInWithGoogle(presenting: presenting)
            let me = try await auth.me()
            await registerDeviceIfNeeded()
            state = .loggedIn(email: me.email)
        } catch {
            errorMessage = "Google Sign-In failed."
        }
    }

    func logout() async {
        do {
            try await auth.logout()
        } catch {
            // ignore
        }
        state = .loggedOut
    }

    // MARK: - Helpers

    private func forceRefreshTokens() async throws {
        guard let refresh = tokens.getRefreshToken() else { throw APIError.noRefreshToken }

        let resp: TokenResponse = try await APIClient.shared.request(
            method: "POST",
            path: Endpoints.Auth.refresh,
            body: RefreshRequest(refresh_token: refresh),
            requiresAuth: false,
            retryOn401: false
        )
        tokens.setAccessToken(resp.access_token)
        tokens.setRefreshToken(resp.refresh_token)
    }

    private func registerDeviceIfNeeded() async {
        let deviceId = deviceIdStore.identifier
        let model = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
        do {
            try await deviceService.registerDevice(
                deviceId: deviceId,
                platform: "ios",
                deviceModel: model,
                osVersion: osVersion
            )
        } catch {
            // Non-blocking
        }
    }
}

