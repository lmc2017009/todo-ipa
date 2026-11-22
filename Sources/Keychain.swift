import Foundation
import Security

/// API 密钥存储：优先钥匙串，失败时回退到 UserDefaults（自签名安装下也能用）
enum Keychain {
    private static let service = "com.operit.aichat"
    private static let fallbackKey = "aichat.api-key.fallback"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ value: String, account: String = "default") {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }

        let data = Data(value.utf8)
        SecItemDelete(query(account) as CFDictionary)

        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        } else {
            UserDefaults.standard.set(value, forKey: fallbackKey)
        }
    }

    static func read(account: String = "default") -> String {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        return UserDefaults.standard.string(forKey: fallbackKey) ?? ""
    }

    static func delete(account: String = "default") {
        SecItemDelete(query(account) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }
}