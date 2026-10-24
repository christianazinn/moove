import Foundation
import MooveKit

/// Asks the worker's movers agent for quotes: `POST /moves/quotes` on `AppConfig.effectiveUploadBaseURL`
/// (pattern of `ListingImportClient`). No secrets: the rate table lives on the worker and in MooveKit.
struct MoverQuotesClient: Sendable {
    enum ClientError: LocalizedError {
        case notConfigured
        case badStatus(Int, String?)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: "No worker URL is set."
            case let .badStatus(code, message): "The worker answered \(code)" + (message.map { ": \($0)" } ?? ".")
            case .badResponse: "The worker sent a reply Moove couldn't read."
            }
        }
    }

    var baseURL: URL?
    var timeout: TimeInterval = 20
    var session: URLSession = .shared

    init(baseURL: URL? = AppConfig.effectiveUploadBaseURL, timeout: TimeInterval = 20, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    func quotes(_ body: MoverQuoteRequest) async throws -> MoverQuotesResult {
        guard let baseURL else { throw ClientError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent("moves/quotes"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct WorkerError: Decodable { var error: String }
            throw ClientError.badStatus(http.statusCode, (try? JSONDecoder().decode(WorkerError.self, from: data))?.error)
        }
        guard let result = try? JSONDecoder().decode(MoverQuotesResult.self, from: data), !result.quotes.isEmpty else {
            throw ClientError.badResponse
        }
        return result
    }

    /// The worker's answer, or the same estimates worked out on this phone when it can't be reached.
    func quotesOrOnDevice(_ body: MoverQuoteRequest) async -> MoverQuotesResult {
        do {
            return try await quotes(body)
        } catch {
            return MoverRates.onDevice(body)
        }
    }
}
