import Foundation
import Security

final class AuthTokenStore {
    static let shared = AuthTokenStore()

    private init() {}

    private let service = "com.yourcompany.LandmarkFinder"
    private let refreshAccount = "refresh_token"

    // Access kısa süreli: memory
    private var _accessToken: String?
    var accessToken: String? { _accessToken }

    func setAccessToken(_ token: String?) {
        _accessToken = token
    }

    // Refresh uzun süreli: Keychain
    func getRefreshToken() -> String? {
        readKeychain(account: refreshAccount)
    }

    func setRefreshToken(_ token: String?) {
        if let token { saveKeychain(token, account: refreshAccount) }
        else { deleteKeychain(account: refreshAccount) }
    }

    func clearAll() {
        _accessToken = nil
        deleteKeychain(account: refreshAccount)
    }

    // MARK: - Keychain helpers

    private func saveKeychain(_ value: String, account: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let add: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]) { $1 }

        SecItemAdd(add as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
