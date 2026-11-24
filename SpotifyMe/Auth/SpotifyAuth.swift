import Foundation
import SpotifyMeCore

/// Spotify sign-in with Authorization Code + PKCE (no client secret on the device),
/// token storage in the Keychain, and automatic refresh.
actor SpotifyAuth: AccessTokenProvider {
    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    enum AuthError: LocalizedError {
        case notSignedIn, missingCode, stateMismatch, denied(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Please sign in to Spotify."
            case .missingCode: return "Spotify did not return an authorization code."
            case .stateMismatch: return "Sign-in response did not match the request. Please try again."
            case .denied(let reason): return "Spotify sign-in was cancelled (\(reason))."
            }
        }
    }

    static let scopes = [
        "user-top-read",
        "user-read-recently-played",
        "user-library-read",
        "playlist-modify-private",
        "playlist-modify-public"
    ]

    private let clientID: String
    private let redirectURI: String
    private let keychainKey = "spotify.tokens"
    private var tokens: Tokens?
    private var pending: (pkce: PKCE, state: String)?
    private var refreshTask: Task<Tokens, Error>?

    init(clientID: String, redirectURI: String) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        if let data = Keychain.load(keychainKey) {
            tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        }
    }

    var isSignedIn: Bool { tokens != nil }

    /// URL to open in ASWebAuthenticationSession.
    func authorizationURL() -> URL {
        let pkce = PKCE()
        let state = UUID().uuidString
        pending = (pkce, state)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " "))
        ]
        return components.url!
    }

    /// Handle the redirect (spotifyme://callback?code=...&state=...).
    func handleCallback(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") { throw AuthError.denied(error) }
        guard let pending, value("state") == pending.state else { throw AuthError.stateMismatch }
        guard let code = value("code") else { throw AuthError.missingCode }
        self.pending = nil

        let newTokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": pending.pkce.verifier
        ], previousRefreshToken: nil)
        store(newTokens)
    }

    func signOut() {
        tokens = nil
        Keychain.delete(keychainKey)
    }

    // MARK: AccessTokenProvider

    func accessToken() async throws -> String {
        guard let tokens else { throw AuthError.notSignedIn }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }

        // Share one refresh between concurrent callers.
        if let refreshTask { return try await refreshTask.value.accessToken }
        let refreshToken = tokens.refreshToken
        let task = Task { () throws -> Tokens in
            try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID
            ], previousRefreshToken: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            store(refreshed)
            return refreshed.accessToken
        } catch {
            // A rejected refresh token means the user must sign in again.
            if case APIError.http(let status, _) = error, status == 400 { signOut() }
            throw error
        }
    }

    // MARK: Private

    private func store(_ newTokens: Tokens) {
        tokens = newTokens
        if let data = try? JSONEncoder().encode(newTokens) {
            Keychain.save(data, for: keychainKey)
        }
    }

    private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws -> Tokens {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" unescaped, which form decoding would turn into a space.
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let data = try await HTTPClient().send(request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let refresh = response.refresh_token ?? previousRefreshToken else { throw AuthError.notSignedIn }
        return Tokens(accessToken: response.access_token, refreshToken: refresh,
                      expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in)))
    }
}
