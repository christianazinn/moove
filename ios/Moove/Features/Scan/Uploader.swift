import Foundation
import MooveKit

/// Sends scan files to the agent worker, because SpacetimeDB isn't a blob store.
///
/// Contract with `agents/src/upload.ts`: `POST {MOOVE_UPLOAD_BASE_URL}/upload` with the
/// raw file as the body and its `Content-Type`; responds `{"url": "<public url>"}`.
/// The worker names files itself (random UUIDs), so no file name is sent.
protocol Uploader: Sendable {
    func upload(_ file: URL, contentType: String) async throws -> String
}

struct HTTPUploader: Uploader {
    /// Read before every attempt (#222): the worker's tunnel URL can change mid-scan,
    /// and the app learns the new one from `service_config`.
    var baseURL: @Sendable () -> URL? = { AppConfig.effectiveUploadBaseURL }
    var token: String?
    var policy = UploadRetryPolicy.standard

    struct Response: Decodable { let url: String }

    /// Retries 429/5xx/network failures with backoff (MooveKit `UploadRetry`); throws
    /// `UploadFailure` once it gives up.
    func upload(_ file: URL, contentType: String) async throws -> String {
        let token = token
        return try await UploadRetry.run(policy: policy, baseURL: baseURL) { base in
            var request = URLRequest(url: base.appending(path: "upload"))
            request.httpMethod = "POST"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            request.timeoutInterval = 60
            let data: Data, response: URLResponse
            do {
                (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
            } catch let error as URLError {
                throw UploadFailure.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw UploadFailure.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw UploadFailure.status(http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
            }
            guard let url = try? JSONDecoder().decode(Response.self, from: data).url else { throw UploadFailure.badResponse }
            return url
        }
    }
}

/// Offline demo: keep files on the device and reference them by file URL.
struct LocalUploader: Uploader {
    func upload(_ file: URL, contentType: String) async throws -> String { file.absoluteString }
}
