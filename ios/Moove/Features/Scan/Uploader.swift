import Foundation

/// Sends scan files to the agent worker, because SpacetimeDB isn't a blob store.
///
/// Contract with `agents/src/upload.ts`: `POST {MOOVE_UPLOAD_BASE_URL}/upload` with the
/// raw file as the body and its `Content-Type`; responds `{"url": "<public url>"}`.
/// The worker names files itself (random UUIDs), so no file name is sent.
protocol Uploader: Sendable {
    func upload(_ file: URL, contentType: String) async throws -> String
}

struct HTTPUploader: Uploader {
    let baseURL: URL
    var token: String?

    struct Response: Decodable { let url: String }

    func upload(_ file: URL, contentType: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "upload"))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data).url
    }
}

/// Offline demo: keep files on the device and reference them by file URL.
struct LocalUploader: Uploader {
    func upload(_ file: URL, contentType: String) async throws -> String { file.absoluteString }
}

/// Live backend with no upload server configured: every upload fails, so the scan is
/// imported with its room files local-only instead of syncing `file://` URLs.
struct UnavailableUploader: Uploader {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "no upload server is configured" }
    }

    func upload(_ file: URL, contentType: String) async throws -> String { throw NotConfigured() }
}
