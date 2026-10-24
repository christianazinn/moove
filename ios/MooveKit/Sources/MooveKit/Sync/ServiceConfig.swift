import Foundation

/// What the agent worker announces about itself in the public `service_config`
/// table on every start (#122): where to upload photos, and which build is running.
/// The upload URL changes whenever the laptop's tunnel restarts, so the app reads
/// it here at runtime and only falls back to the build's xcconfig value.
public struct ServiceConfig: Sendable, Equatable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) { self.values = values }

    /// The worker's upload origin, if it announced a valid http(s) one.
    public var uploadBaseURL: URL? {
        guard let raw = values["upload_base_url"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    public var workerVersion: String? { values["worker_version"].flatMap { $0.isEmpty ? nil : $0 } }

    public var workerStartedAt: Date? {
        guard let raw = values["worker_started_at"] else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// The runtime URL when the worker announced one, else `fallback` (the build's config).
    public func uploadBaseURL(fallback: URL?) -> URL? { uploadBaseURL ?? fallback }
}
