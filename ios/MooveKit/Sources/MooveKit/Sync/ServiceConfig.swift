import Foundation

/// What the agent worker announces about itself in the public `service_config`
/// table on every start (#122): where to upload photos, and which build is running.
/// The upload URL changes whenever the laptop's tunnel restarts, so the app reads
/// it here at runtime and only falls back to the build's xcconfig value.
public struct ServiceConfig: Sendable, Equatable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) { self.values = values }

    /// The worker's upload origin, if it announced a valid one. Photos and scans go there, so
    /// (#17 follow-up) it must be a bare origin: no user@, query or fragment, and plain http only
    /// to a local host (localhost, *.local, loopback or a private IPv4 LAN address).
    public var uploadBaseURL: URL? {
        guard let raw = values["upload_base_url"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              let parts = URLComponents(string: raw), let url = parts.url,
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { return nil }
        if scheme == "https" { return url }
        return scheme == "http" && Self.isLocalHost(host) ? url : nil
    }

    static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let o = labels.compactMap { UInt8($0) }
        guard labels.count == 4, o.count == 4 else { return false }
        return o[0] == 127 || o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && (16...31).contains(o[1]))
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
