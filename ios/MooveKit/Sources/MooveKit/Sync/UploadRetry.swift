import Foundation

/// When and how often to retry an upload to the worker's `/upload` (#222).
///
/// The upload port rate-limits per client (429 after 120 uploads/min, #202) and its quick
/// tunnel blips when it restarts (the new URL arrives through `service_config`). Those
/// are worth waiting out. Other 4xx answers (bad request, 413 too large, 507 storage cap)
/// won't change on a retry, so they fail at once.
public struct UploadRetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxAttempts: Int = 4, baseDelay: Duration = .seconds(1), maxDelay: Duration = .seconds(15)) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let standard = UploadRetryPolicy()

    /// Whether a failure is worth another attempt.
    public static func isTransient(_ failure: UploadFailure) -> Bool {
        switch failure {
        case .network, .noServer: true
        case .status(let code, _): code == 429 || code == 408 || (500...599).contains(code) && code != 507
        case .badResponse: false
        }
    }

    /// Wait before attempt `attempt + 1` (attempt is 1-based): 1 s, 2 s, 4 s… capped at
    /// `maxDelay`. A server's `Retry-After` wins when it's longer, up to the cap.
    public func delay(after attempt: Int, retryAfter: Double? = nil) -> Duration {
        let exponential = baseDelay * (1 << max(0, min(attempt - 1, 10)))
        var wait = min(exponential, maxDelay)
        if let retryAfter, retryAfter > 0 { wait = max(wait, min(.milliseconds(Int(retryAfter * 1000)), maxDelay)) }
        return wait
    }
}

public enum UploadFailure: Error, Equatable, Sendable {
    /// The server answered with a non-2xx status (`Retry-After` seconds, if sent).
    case status(Int, retryAfter: Double?)
    /// No answer: offline, timed out, DNS, TLS, connection reset.
    case network(String)
    /// No upload URL is known yet (the worker hasn't announced one).
    case noServer
    /// 2xx but the body wasn't `{"url": …}`.
    case badResponse

    public var message: String {
        switch self {
        case .status(429, _): "the upload server is busy (rate limited)"
        case .status(507, _): "the upload server is out of space"
        case .status(let code, _): "the upload server answered \(code)"
        case .network(let why): why
        case .noServer: "no upload server announced yet"
        case .badResponse: "the upload server sent an unexpected answer"
        }
    }
}

public enum UploadRetry {
    /// Runs `attempt` against the current upload URL until it succeeds, fails permanently,
    /// or runs out of attempts. `baseURL` is read again before every attempt, so a tunnel
    /// that restarted mid-upload is picked up. `sleep` is injectable for tests.
    public static func run<T: Sendable>(
        policy: UploadRetryPolicy = .standard,
        baseURL: @Sendable () async -> URL?,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        attempt: @Sendable (URL) async throws -> T
    ) async throws -> T {
        var last: UploadFailure = .noServer
        for n in 1...max(1, policy.maxAttempts) {
            do {
                guard let url = await baseURL() else { throw UploadFailure.noServer }
                return try await attempt(url)
            } catch let failure as UploadFailure {
                last = failure
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                last = .network(error.localizedDescription)
            }
            guard UploadRetryPolicy.isTransient(last), n < policy.maxAttempts else { break }
            var retryAfter: Double?
            if case .status(_, let after) = last { retryAfter = after }
            try await sleep(policy.delay(after: n, retryAfter: retryAfter))
        }
        throw last
    }
}
