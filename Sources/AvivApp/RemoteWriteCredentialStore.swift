import Foundation
import Security

protocol RemoteWriteCredentialStoring: AnyObject {
    func token(for sourceID: String) throws -> String?
    func store(token: String, for sourceID: String) throws
    func removeToken(for sourceID: String) throws
}

enum RemoteWriteCredentialStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidTokenData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "The remote-save credential could not be accessed: \(detail)."
        case .invalidTokenData:
            return "The saved remote-write credential is not valid UTF-8 text."
        }
    }
}

final class KeychainRemoteWriteCredentialStore: RemoteWriteCredentialStoring {
    static let service = "net.pitchai.aviv.remote-write"

    func token(for sourceID: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: sourceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw RemoteWriteCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw RemoteWriteCredentialStoreError.invalidTokenData
        }
        return token
    }

    func store(token: String, for sourceID: String) throws {
        guard let data = token.data(using: .utf8), !token.isEmpty else {
            throw RemoteWriteCredentialStoreError.invalidTokenData
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: sourceID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw RemoteWriteCredentialStoreError.keychain(updateStatus)
        }

        var item = query
        for (key, value) in attributes {
            item[key] = value
        }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RemoteWriteCredentialStoreError.keychain(addStatus)
        }
    }

    func removeToken(for sourceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: sourceID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteWriteCredentialStoreError.keychain(status)
        }
    }
}
