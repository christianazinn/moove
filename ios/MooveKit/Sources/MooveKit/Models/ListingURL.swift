import Foundation

/// Where a listing's "View listing" link should go right now.
///
/// A simulated eBay listing's page is served by the worker's own upload server, and the worker
/// stores its URL as an absolute link on the upload host it had at posting time, e.g.
/// `https://old-words.trycloudflare.com/files/listing-1.html`. The laptop's quick tunnel gets a
/// new host on every restart (the current one is announced in `service_config`, #122), so that
/// link dies while the same page still loads on the current host. `resolve` moves such links onto
/// the current upload base. It only touches our own pages: a `/files/` path that is either a
/// simulated listing page (`/files/listing-*`) or on a host that was an upload base before. A real
/// eBay URL is never rewritten.
public enum ListingURL {
    /// The URL to open for a stored listing `url`, or nil when there is nothing openable.
    /// - `uploadBase`: the current upload origin (`MooveStore.uploadBaseURL`). Nil leaves links as stored.
    /// - `previousUploadHosts`: hosts known to have been upload bases (lowercased, `host` or `host:port`).
    ///   Quick-tunnel hosts (`*.trycloudflare.com`) always count: they're never a marketplace.
    public static func resolve(_ raw: String?, simulated: Bool, uploadBase: URL?, previousUploadHosts: Set<String> = []) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        // A relative `/files/...` link (not written today, but harmless to accept) only means
        // something against the current base.
        if raw.hasPrefix("/files/") {
            guard let uploadBase, let rel = URLComponents(string: raw) else { return nil }
            return rebase(rel, onto: uploadBase)
        }

        guard let parts = URLComponents(string: raw), let url = parts.url else { return nil }
        guard let uploadBase,
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.path.hasPrefix("/files/"),
              !isMarketplace(host)
        else { return url }

        let hostKey = key(host: host, port: parts.port)
        if let baseHost = uploadBase.host?.lowercased(), key(host: baseHost, port: uploadBase.port) == hostKey { return url }

        let name = parts.path.dropFirst("/files/".count)
        let isListingPage = simulated && name.hasPrefix("listing-") && !name.contains("/")
        let wasUploadHost = previousUploadHosts.contains(hostKey) || previousUploadHosts.contains(host)
            || host.hasSuffix(".trycloudflare.com")
        guard isListingPage || wasUploadHost else { return url }
        return rebase(parts, onto: uploadBase) ?? url
    }

    /// eBay (sandbox or production) and anything under it: never ours, never rewritten.
    static func isMarketplace(_ host: String) -> Bool {
        host == "ebay.com" || host.hasSuffix(".ebay.com") || host.contains(".ebay.") || host.hasPrefix("ebay.")
    }

    private static func key(host: String, port: Int?) -> String {
        port.map { "\(host):\($0)" } ?? host
    }

    /// `/files/...` (plus any query or fragment) under the base's scheme, host, port and path prefix.
    private static func rebase(_ link: URLComponents, onto base: URL) -> URL? {
        guard var out = URLComponents(url: base, resolvingAgainstBaseURL: false), out.host != nil else { return nil }
        var prefix = out.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        out.percentEncodedPath = prefix + link.percentEncodedPath
        out.percentEncodedQuery = link.percentEncodedQuery
        out.percentEncodedFragment = link.percentEncodedFragment
        return out.url
    }
}

public extension Listing {
    /// The listing page to open now, with a dead tunnel host moved onto the current upload base.
    func viewURL(uploadBase: URL?, previousUploadHosts: Set<String> = []) -> URL? {
        ListingURL.resolve(url, simulated: simulated, uploadBase: uploadBase, previousUploadHosts: previousUploadHosts)
    }
}
