import Foundation

/// One scan's uploads, kept across retries so a retry only re-sends what failed:
/// files already uploaded keep their URL. (Double-submit and re-import guards live
/// in the app's ScanSession.)
public struct ScanSubmission: Sendable, Equatable {
    /// Public URL per local file, for files the upload server accepted.
    public private(set) var uploaded: [URL: String] = [:]

    public init() {}

    public mutating func recordUpload(_ file: URL, url: String) {
        uploaded[file] = url
    }

    /// The local file changed (a retaken photo), so its old upload no longer matches.
    public mutating func forgetUpload(_ file: URL) {
        uploaded[file] = nil
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
