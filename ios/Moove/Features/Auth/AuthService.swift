import Foundation
import Observation
import Auth0

/// Auth0 sign-in. The ID token (an OIDC JWT) is also the SpacetimeDB
/// connection token, so the module's `ctx.sender` is derived from the Auth0 user.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(Profile)
        /// No Auth0: anonymous SpacetimeDB identity (demo fallback).
        case guest
    }

    struct Profile: Equatable {
        var sub: String
        var name: String
        var email: String?
    }

    private(set) var state: State = .checking
    var error: String?

    private let config: AppConfig
    private let credentialsManager: CredentialsManager?
    static let guestKey = "moove.auth.guest"

    init(config: AppConfig = .current) {
        self.config = config
        if let domain = config.auth0Domain, let clientId = config.auth0ClientId {
            credentialsManager = CredentialsManager(authentication: Auth0.authentication(clientId: clientId, domain: domain))
        } else {
            credentialsManager = nil
        }
    }

    var isConfigured: Bool { credentialsManager != nil }

    /// Restores a saved session on launch, renewing the tokens if needed.
    func restore() async {
        if UserDefaults.standard.bool(forKey: Self.guestKey) { return state = .guest }
        guard let manager = credentialsManager, manager.canRenew() || manager.hasValid() else {
            return state = .signedOut
        }
        do {
            let credentials = try await manager.credentials()
            state = .signedIn(try Self.profile(fromIDToken: credentials.idToken))
        } catch {
            state = .signedOut
        }
    }

    /// A fresh (renewed if close to expiry) ID token for SpacetimeDB, or nil for guests.
    func spacetimeToken() async -> String? {
        guard case .signedIn = state, let manager = credentialsManager else { return nil }
        return try? await manager.credentials(minTTL: 300).idToken
    }

    func signIn() async {
        guard let domain = config.auth0Domain, let clientId = config.auth0ClientId, let manager = credentialsManager else {
            error = "Auth0 isn't configured in Config/Moove.xcconfig"
            return
        }
        do {
            let credentials = try await Auth0.webAuth(clientId: clientId, domain: domain)
                .scope("openid profile email offline_access")
                .start()
            _ = try manager.store(credentials: credentials)
            UserDefaults.standard.set(false, forKey: Self.guestKey)
            state = .signedIn(try Self.profile(fromIDToken: credentials.idToken))
            error = nil
        } catch WebAuthError.userCancelled {
            // Closed the login sheet; stay on the login screen.
        } catch {
            self.error = error.localizedDescription
        }
    }

    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: Self.guestKey)
        state = .guest
    }

    func signOut() async {
        UserDefaults.standard.set(false, forKey: Self.guestKey)
        if case .signedIn = state, let domain = config.auth0Domain, let clientId = config.auth0ClientId {
            // Clears the Auth0 session cookie too, so the next login can pick another account.
            try? await Auth0.webAuth(clientId: clientId, domain: domain).logout(federated: false)
        }
        _ = try? credentialsManager?.clear()
        Keychain.set(nil, for: .spacetimeToken)
        state = .signedOut
    }

    /// Reads `sub`, `name` and `email` from the ID token. Auth0.swift has
    /// already validated the token's signature and claims when it was issued.
    static func profile(fromIDToken token: String) throws -> Profile {
        struct Claims: Decodable { let sub: String; let name: String?; let nickname: String?; let email: String? }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw URLError(.cannotDecodeContentData) }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw URLError(.cannotDecodeContentData) }
        let claims = try JSONDecoder().decode(Claims.self, from: data)
        return Profile(sub: claims.sub, name: claims.name ?? claims.nickname ?? claims.email ?? "Mover", email: claims.email)
    }
}
