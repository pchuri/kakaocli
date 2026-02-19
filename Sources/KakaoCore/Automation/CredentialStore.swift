import Foundation
import Security

/// Manages KakaoTalk login credentials using macOS Keychain.
public final class CredentialStore: Sendable {

    private static let service = "com.kakaocli.credentials"
    private static let emailAccount = "kakaotalk-email"
    private static let passwordAccount = "kakaotalk-password"

    public init() {}

    // MARK: - Read

    public var email: String? {
        Self.readKeychain(account: Self.emailAccount)
    }

    public var password: String? {
        Self.readKeychain(account: Self.passwordAccount)
    }

    public var hasCredentials: Bool {
        email != nil && password != nil
    }

    // MARK: - Write

    public func save(email: String, password: String) throws {
        try Self.writeKeychain(account: Self.emailAccount, value: email)
        try Self.writeKeychain(account: Self.passwordAccount, value: password)
    }

    public func clear() {
        Self.deleteKeychain(account: Self.emailAccount)
        Self.deleteKeychain(account: Self.passwordAccount)
    }

    // MARK: - Keychain Primitives

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(account: String, value: String) throws {
        let data = Data(value.utf8)

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]

        var status = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum CredentialError: Error, CustomStringConvertible {
    case keychainError(OSStatus)

    public var description: String {
        switch self {
        case .keychainError(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error: \(status) (\(msg))"
        }
    }
}
