import Foundation

final class DigestSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let credentials: CameraCredentials

    init(credentials: CameraCredentials) {
        self.credentials = credentials
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let acceptedMethods = [
            NSURLAuthenticationMethodHTTPDigest,
            NSURLAuthenticationMethodHTTPBasic
        ]

        guard acceptedMethods.contains(method), challenge.previousFailureCount == 0 else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(
            .useCredential,
            URLCredential(
                user: credentials.username,
                password: credentials.password,
                persistence: .forSession
            )
        )
    }
}

