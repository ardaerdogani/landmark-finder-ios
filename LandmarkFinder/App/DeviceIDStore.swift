import Foundation
import Security

final class DeviceIDStore {
    static let shared = DeviceIDStore()

    private init() {
        if let existing = readKeychain(account: account) {
            identifier = existing
        } else {
            let new = UUID().uuidString
            saveKeychain(new, account: account)
            identifier = new
        }
    }

    private let service = "com.yourcompany.LandmarkFinder.deviceid"
    private let account = "device_identifier"

    private(set) var identifier: String = ""

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
}

