import Foundation
import Security
import UIKit

struct AuthenticationCredentials: Codable, Equatable, Sendable {
    let token: String
    let username: String
}

enum AuthenticationCredentialsStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            "Не удалось обратиться к защищённому хранилищу (код \(status))."
        case .invalidData:
            "В защищённом хранилище находятся некорректные данные авторизации."
        }
    }
}

@MainActor
final class AuthenticationCredentialsStore {
    static let shared = AuthenticationCredentialsStore()

    private let service = "com.aglamov.OneCAnalytics.authentication"
    private let account = "rudn-session"
    private lazy var deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    func save(_ credentials: AuthenticationCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AuthenticationCredentialsStoreError.keychain(updateStatus)
        }

        let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthenticationCredentialsStoreError.keychain(addStatus)
        }
    }

    func load() throws -> AuthenticationCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AuthenticationCredentialsStoreError.keychain(status)
        }
        guard let data = item as? Data,
              let credentials = try? JSONDecoder().decode(AuthenticationCredentials.self, from: data) else {
            throw AuthenticationCredentialsStoreError.invalidData
        }
        return credentials
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationCredentialsStoreError.keychain(status)
        }
    }

    func addAuthentication(to request: inout URLRequest) throws {
        guard let credentials = try load() else {
            throw AuthenticationError.missingCredentials
        }
        request.setValue(credentials.token, forHTTPHeaderField: "XAuthToken")
        request.setValue(credentials.username, forHTTPHeaderField: "Login")
        request.setValue(deviceIdentifier, forHTTPHeaderField: "X-Auth-Key")
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
