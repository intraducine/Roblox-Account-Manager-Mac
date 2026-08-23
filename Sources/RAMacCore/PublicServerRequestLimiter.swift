import Foundation

actor PublicServerRequestLimiter {
    static let shared = PublicServerRequestLimiter()

    private var remainingRequests: Int?
    private var resetAt: Date?
    private var isLearningLimit = false
    private var limitWaiters: [CheckedContinuation<Void, Never>] = []

    func acquirePermit() async throws {
        try Task.checkCancellation()
        clearExpiredLimit()

        if let remainingRequests {
            guard remainingRequests > 0 else {
                throw RobloxAPIError.requestBudgetPaused(secondsUntilReset())
            }
            self.remainingRequests = remainingRequests - 1
            return
        }

        if isLearningLimit {
            await withCheckedContinuation { continuation in
                limitWaiters.append(continuation)
            }
            try Task.checkCancellation()
            try await acquirePermit()
            return
        }

        isLearningLimit = true
    }

    func observe(_ response: HTTPURLResponse) {
        let retryAfter = Self.integerHeader("Retry-After", in: response)
        let reset = Self.integerHeader("x-ratelimit-reset", in: response)
        let remaining = Self.integerHeader("x-ratelimit-remaining", in: response)

        if response.statusCode == 429 {
            remainingRequests = 0
            setReset(after: retryAfter ?? reset ?? 60)
        } else if let remaining {
            remainingRequests = max(0, remaining)
            if remaining == 0 {
                setReset(after: reset ?? 60)
            } else if let reset {
                setReset(after: reset)
            } else {
                resetAt = nil
            }
        } else {
            remainingRequests = nil
            resetAt = nil
        }

        finishLearningLimit()
    }

    func requestFailedBeforeResponse() {
        finishLearningLimit()
    }

    private func setReset(after seconds: Int) {
        let safeDelay = max(1, seconds)
        resetAt = Date().addingTimeInterval(TimeInterval(safeDelay) + 0.5)
    }

    private func clearExpiredLimit() {
        guard let resetAt, Date() >= resetAt else { return }
        remainingRequests = nil
        self.resetAt = nil
    }

    private func secondsUntilReset() -> Int? {
        guard let resetAt else { return nil }
        return max(1, Int(ceil(resetAt.timeIntervalSinceNow)))
    }

    private func finishLearningLimit() {
        isLearningLimit = false
        let waiters = limitWaiters
        limitWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private static func integerHeader(_ name: String, in response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: name) else { return nil }
        let firstNumber = value.split(whereSeparator: { !$0.isNumber }).first
        return firstNumber.flatMap { Int($0) }
    }
}
