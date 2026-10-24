import Foundation

/// Build-time config injected from Config/*.xcconfig via Info.plist.
struct AppConfig: Sendable {
    var spacetimeHost: String
    var spacetimeDB: String
    var uploadBaseURL: URL?
    var auth0Domain: String?
    var auth0ClientId: String?

    var auth0Configured: Bool { auth0Domain != nil && auth0ClientId != nil }

    static let current: AppConfig = {
        func value(_ key: String) -> String? {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        return AppConfig(
            spacetimeHost: value("MooveSpacetimeHost") ?? "https://maincloud.spacetimedb.com",
            spacetimeDB: value("MooveSpacetimeDB") ?? "moove",
            uploadBaseURL: value("MooveUploadBaseURL").flatMap(URL.init(string:)),
            auth0Domain: value("MooveAuth0Domain"),
            auth0ClientId: value("MooveAuth0ClientId")
        )
    }()
}
