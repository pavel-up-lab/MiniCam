struct PlaybackTransitionQueue<Request> {
    enum Action: Equatable {
        case startNow
        case stopPlayer
        case wait
    }

    private var pendingRequest: Request?
    private(set) var isWaitingForStop = false

    mutating func schedule(
        _ request: Request,
        playerNeedsStop: Bool
    ) -> Action {
        pendingRequest = request

        if isWaitingForStop {
            return .wait
        }
        guard playerNeedsStop else {
            pendingRequest = nil
            return .startNow
        }

        isWaitingForStop = true
        return .stopPlayer
    }

    mutating func finishStopping() -> Request? {
        guard isWaitingForStop else { return nil }
        isWaitingForStop = false
        defer { pendingRequest = nil }
        return pendingRequest
    }

    mutating func reset() {
        pendingRequest = nil
        isWaitingForStop = false
    }
}
