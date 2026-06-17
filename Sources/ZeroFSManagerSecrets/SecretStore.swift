import Foundation
import Security
import ZeroFSManagerDomain

public enum SecretKind: String, CaseIterable, Codable, Sendable {
    case s3AccessKeyID
    case s3SecretAccessKey
    case zeroFSEncryptionPassword
}

public protocol SecretStore {
    func save(_ value: String, kind: SecretKind, profileID: ProfileID) throws
    func read(kind: SecretKind, profileID: ProfileID) throws -> String?
    func delete(kind: SecretKind, profileID: ProfileID) throws
}

public enum SecretStoreError: Error, CustomStringConvertible {
    case encodingFailed
    case decodingFailed
    case keychainStatus(OSStatus)

    public var description: String {
        switch self {
        case .encodingFailed:
            "Secret encoding failed"
        case .decodingFailed:
            "Secret decoding failed"
        case .keychainStatus(let status):
            "Keychain operation failed with status \(status)"
        }
    }
}

public final class InMemorySecretStore: SecretStore {
    private var values: [Key: String] = [:]

    public init() {}

    public func save(_ value: String, kind: SecretKind, profileID: ProfileID) throws {
        values[Key(profileID: profileID, kind: kind)] = value
    }

    public func read(kind: SecretKind, profileID: ProfileID) throws -> String? {
        values[Key(profileID: profileID, kind: kind)]
    }

    public func delete(kind: SecretKind, profileID: ProfileID) throws {
        values.removeValue(forKey: Key(profileID: profileID, kind: kind))
    }

    private struct Key: Hashable {
        var profileID: ProfileID
        var kind: SecretKind
    }
}

public final class KeychainSecretStore: SecretStore {
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    public func save(_ value: String, kind: SecretKind, profileID: ProfileID) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }

        var query = baseQuery(kind: kind, profileID: profileID)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.keychainStatus(status)
        }
    }

    public func read(kind: SecretKind, profileID: ProfileID) throws -> String? {
        var query = baseQuery(kind: kind, profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.decodingFailed
        }
        return value
    }

    public func delete(kind: SecretKind, profileID: ProfileID) throws {
        let status = SecItemDelete(baseQuery(kind: kind, profileID: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(kind: SecretKind, profileID: ProfileID) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zerofs.manager.\(profileID.rawValue).\(kind.rawValue)",
            kSecAttrAccount as String: "\(profileID.rawValue):\(kind.rawValue)",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum SecretRedactor {
    public static func redact(_ text: String, secrets: [String]) -> String {
        secrets
            .filter { !$0.isEmpty }
            .reduce(text) { partial, secret in
                partial.replacingOccurrences(of: secret, with: "[REDACTED]")
            }
    }
}
