import Foundation
import Security

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "local.minicam.camera",
        account: String = "primary-camera"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> CameraCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw CameraError.secureStorageFailure(status)
        }

        return try JSONDecoder().decode(KeychainPayload.self, from: data).credentials
    }

    func save(_ credentials: CameraCredentials) throws {
        let data = try JSONEncoder().encode(KeychainPayload(credentials: credentials))
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CameraError.secureStorageFailure(insertStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw CameraError.secureStorageFailure(status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CameraError.secureStorageFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct KeychainPayload: Codable {
    let username: String
    let password: String

    init(credentials: CameraCredentials) {
        username = credentials.username
        password = credentials.password
    }

    var credentials: CameraCredentials {
        CameraCredentials(username: username, password: password)
    }
}

