import Foundation
import Security

enum JevCredential {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.daniel.LayaClipboard.TypeSafe",
        kSecAttrAccount as String: "api-key"
    ]

    static func load() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        guard status == errSecSuccess, let data = value as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw ClipboardError.message("Configure the TypeSafe API key from the menu.")
        }
        return key
    }

    static func save(_ text: String) throws {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...1024).contains(key.utf8.count), key.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }),
              let data = key.data(using: .utf8) else {
            throw ClipboardError.message("The copied value is not a valid API key.")
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ClipboardError.message("macOS could not save the TypeSafe key in Keychain.")
        }
    }
}
