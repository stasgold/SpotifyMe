import Foundation
import SpotifyMeCore

/// App-wide state shared by the views.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published var errorMessage: String?

    let auth: SpotifyAuth
    let service: PlaylistService
    private let cache: FeatureCache

    init() {
        auth = SpotifyAuth(clientID: AppConfig.spotifyClientID, redirectURI: AppConfig.redirectURI)

        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyMe/features.json")
        cache = FeatureCache(fileURL: cacheURL)

        var fallbacks: [BPMLookup] = []
        if !AppConfig.getSongBPMAPIKey.isEmpty {
            fallbacks.append(GetSongBPMAPI(apiKey: AppConfig.getSongBPMAPIKey))
        }
        fallbacks.append(DeezerAPI())

        service = PlaylistService(spotify: SpotifyAPI(tokens: auth), bpmFallbacks: fallbacks, cache: cache)

        Task { isSignedIn = await auth.isSignedIn }
    }

    func signIn(callbackURL: URL) async {
        do {
            try await auth.handleCallback(callbackURL)
            isSignedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        await auth.signOut()
        isSignedIn = false
    }

    func clearCache() async {
        await cache.clear()
    }

    /// Call when a request fails; signs out if the session is no longer valid.
    func handle(_ error: Error) async {
        errorMessage = error.localizedDescription
        if case APIError.unauthorized = error { await signOut() }
        if case SpotifyAuth.AuthError.notSignedIn = error { await signOut() }
    }

    // MARK: Saved playlist IDs (so refreshing a mood updates the same playlist)

    func savedPlaylistID(for mood: Mood) -> String? {
        UserDefaults.standard.string(forKey: "playlist.\(mood.rawValue)")
    }

    func setSavedPlaylistID(_ id: String, for mood: Mood) {
        UserDefaults.standard.set(id, forKey: "playlist.\(mood.rawValue)")
    }
}
