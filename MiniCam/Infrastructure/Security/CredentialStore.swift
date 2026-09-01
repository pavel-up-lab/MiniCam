import Foundation

protocol CredentialStore: Sendable {
    func load() throws -> CameraCredentials?
    func save(_ credentials: CameraCredentials) throws
    func remove() throws
}

