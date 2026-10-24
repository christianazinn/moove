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

    /// How the worker's Visa rail checks out (#191), or nil for a worker or module that doesn't
    /// announce it (or an unknown value). Then the app shows nothing extra before payment.
    public var visaCheckout: VisaCheckoutMode? {
        values["visa_checkout"].flatMap { VisaCheckoutMode(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }

    public var workerVersion: String? { values["worker_version"].flatMap { $0.isEmpty ? nil : $0 } }

    public var workerStartedAt: Date? {
        guard let raw = values["worker_started_at"] else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// The runtime URL when the worker announced one, else `fallback` (the build's config).
    /// On a real device a loopback announcement (`localhost`, `127.x`: what the worker announces
    /// when its `PUBLIC_UPLOAD_BASE_URL` is unset) points at the phone itself, so uploads would
    /// silently fail. There the build's URL wins whenever it is set.
    public func uploadBaseURL(fallback: URL?, onDevice: Bool = Self.runningOnDevice) -> URL? {
        guard let announced = uploadBaseURL else { return fallback }
        if onDevice, let fallback, Self.isLoopback(announced.host?.lowercased() ?? "") { return fallback }
        return announced
    }

    /// True on a physical iPhone/iPad (not the Simulator, not macOS/Linux test runs).
    public static var runningOnDevice: Bool {
        #if os(iOS) && !targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host == "[::1]" || host.hasPrefix("127.")
    }
}

/// service_config `visa_checkout` (#191): which Visa backend the buy agent pays through.
public enum VisaCheckoutMode: String, Sendable, Equatable, CaseIterable {
    /// No network: every purchase is simulated.
    case simulated
    /// The CyberSource sandbox on a test card, no fallback: a real sandbox call, no real money.
    case sandbox
    /// The sandbox, but a 5xx/network error falls back to simulated for that one purchase, so
    /// before payment it isn't known which; the payment row is labeled after.
    case sandboxFallback = "sandbox+fallback"
}
