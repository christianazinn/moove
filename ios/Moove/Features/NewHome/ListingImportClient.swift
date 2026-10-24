import Foundation
import MooveKit

/// Talks to the worker's HTTP server (`PUBLIC_UPLOAD_BASE_URL`) for listing imports (#89):
/// `POST /upload` for floor-plan screenshots and `POST /homes/import` for the plan itself.
/// No secrets: the worker holds the Claude and Apify keys.
struct ListingImportClient: Sendable {
    /// Body of `POST /homes/import`. Every field is optional; nil fields are left out of the JSON.
    struct Request: Codable, Sendable, Hashable {
        var url: String?
        var address: String?
        var beds: Int?
        var baths: Double?
        var sqft: Double?
        var floorPlanImageUrls: [String]?
        var useScraper: Bool?
    }

    /// How the worker produced the result.
    enum Method: String, Codable, Sendable, Hashable {
        case floorplan, scraper, facts
    }

    /// 200 body of `POST /homes/import`. `floorPlan == nil` means "no plan found": estimate locally.
    struct Response: Codable, Sendable, Hashable {
        var name: String
        var address: String?
        var site: String?
        var beds: Int?
        var baths: Double?
        var sqft: Double?
        var floorPlan: FloorPlan?
        var method: Method
        var notes: [String]
        var listingUrl: String?
        var simulated: Bool
    }

    enum ClientError: LocalizedError {
        case notConfigured
        case badStatus(Int, String?)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: "No worker URL is set (MooveUploadBaseURL)."
            case let .badStatus(code, message): "The worker answered \(code)" + (message.map { ": \($0)" } ?? ".")
            case .badResponse: "The worker sent a reply Moove couldn't read."
            }
        }
    }

    var baseURL: URL?
    var timeout: TimeInterval = 30
    var session: URLSession = .shared

    init(baseURL: URL? = AppConfig.current.uploadBaseURL, timeout: TimeInterval = 30, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    var isConfigured: Bool { baseURL != nil }

    /// `POST /upload` with the raw bytes; returns the public URL of the stored file.
    func upload(imageData: Data, contentType: String) async throws -> URL {
        var request = try makeRequest(path: "upload")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, from: imageData)
        try check(response, data)
        struct Uploaded: Decodable { var url: String }
        guard let body = try? JSONDecoder().decode(Uploaded.self, from: data), let url = URL(string: body.url) else {
            throw ClientError.badResponse
        }
        return url
    }

    /// `POST /homes/import` with a JSON body.
    func importHome(_ body: Request) async throws -> Response {
        var request = try makeRequest(path: "homes/import")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ClientError.badResponse
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL else { throw ClientError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        return request
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct WorkerError: Decodable { var error: String }
            let message = (try? JSONDecoder().decode(WorkerError.self, from: data))?.error
            throw ClientError.badStatus(http.statusCode, message)
        }
    }
}
