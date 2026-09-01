import Foundation

struct CameraCredentials: Equatable, Sendable {
    let username: String
    let password: String

    var isEmpty: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }
}

