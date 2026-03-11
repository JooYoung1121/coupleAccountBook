import Foundation
import Security

/// iOS Keychain 래퍼 — LinkedAccount 비밀번호 보안 저장용
final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // 기존 항목 삭제 후 새로 저장
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - LinkedAccount 전용 헬퍼

    static func passwordKey(for accountId: String) -> String {
        "linkedAccount_\(accountId)_password"
    }

    func saveAccountPassword(accountId: String, password: String) {
        _ = save(key: Self.passwordKey(for: accountId), value: password)
    }

    func loadAccountPassword(accountId: String) -> String? {
        load(key: Self.passwordKey(for: accountId))
    }

    func deleteAccountPassword(accountId: String) {
        delete(key: Self.passwordKey(for: accountId))
    }
}
