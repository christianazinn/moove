import Foundation

/// One scan's upload-and-import progress, kept across retries so a retry only
/// re-runs what failed: files already uploaded keep their URL, and a scan that
/// was imported is never imported again (`import_scan` creates a new room each call).
public struct ScanSubmission: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case idle
        case submitting
        case imported
        case failed(String)
    }

    public private(set) var state: State = .idle
    /// Public URL per local file, for files the upload server accepted.
    public private(set) var uploaded: [URL: String] = [:]

    public init() {}

    /// False while a submit is running and once the scan is imported.
    public var canSubmit: Bool {
        switch state {
        case .idle, .failed: true
        case .submitting, .imported: false
        }
    }

    public var isImported: Bool { state == .imported }

    /// Starts an attempt. Returns false (and changes nothing) if one is running or the scan is already imported.
    public mutating func begin() -> Bool {
        guard canSubmit else { return false }
        state = .submitting
        return true
    }

    public mutating func recordUpload(_ file: URL, url: String) {
        uploaded[file] = url
    }

    /// The local file changed (a retaken photo), so its old upload no longer matches.
    public mutating func forgetUpload(_ file: URL) {
        uploaded[file] = nil
    }

    /// Ends the attempt with the import's own result, never a stale app-wide error.
    public mutating func finish(error: String?) {
        guard state == .submitting else { return }
        state = error.map(State.failed) ?? .imported
    }

    /// Only http(s) URLs go to SpacetimeDB: a `file://` URL means nothing to the agents
    /// or to anyone else's device.
    public static func isSyncableURL(_ string: String?) -> Bool {
        guard let string, let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
    }
}

extension ScanImport {
    /// This import with every non-http(s) URL dropped. Dropped room files stay local-only
    /// (nil, stored as '' by the module); dropped photos leave the item photo-less.
    public func syncable() -> ScanImport {
        func keep(_ url: String?) -> String? { ScanSubmission.isSyncableURL(url) ? url : nil }
        var copy = self
        copy.usdzUrl = keep(usdzUrl)
        copy.capturedRoomJsonUrl = keep(capturedRoomJsonUrl)
        copy.objects = objects.map { var o = $0; o.photoUrl = keep(o.photoUrl); return o }
        return copy
    }

    /// True if either room file isn't reachable off this device.
    public var hasLocalOnlyRoomFiles: Bool {
        !ScanSubmission.isSyncableURL(usdzUrl) || !ScanSubmission.isSyncableURL(capturedRoomJsonUrl)
    }
}
