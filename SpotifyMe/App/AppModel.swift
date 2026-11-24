import Foundation
import SpotifyMeCore

/// App-wide state shared by the views.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isConfigured = AppConfig.isConfigured
    @Published var errorMessage: String?
    @Published private(set) var customMoods: [CustomMood] = AppModel.loadCustomMoods()

    private(set) var auth: SpotifyAuth
    private(set) var service: PlaylistService
    private let cache: FeatureCache

    init() {
        let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyMe/features.json")
        cache = FeatureCache(fileURL: cacheURL)
        (auth, service) = Self.makeClients(cache: cache)

        Task { isSignedIn = await auth.isSignedIn }
    }

    /// Save credentials entered on the device and rebuild the Spotify clients.
    /// Changing the Client ID signs out, since tokens belong to one Spotify app.
    func configure(clientID: String, getSongBPMAPIKey: String) async {
        let clientChanged = clientID.trimmingCharacters(in: .whitespacesAndNewlines) != AppConfig.spotifyClientID
        AppConfig.save(clientID: clientID, getSongBPMAPIKey: getSongBPMAPIKey)
        if clientChanged { await auth.signOut() }
        (auth, service) = Self.makeClients(cache: cache)
        isSignedIn = await auth.isSignedIn
        isConfigured = AppConfig.isConfigured
    }

    private static func makeClients(cache: FeatureCache) -> (SpotifyAuth, PlaylistService) {
        let auth = SpotifyAuth(clientID: AppConfig.spotifyClientID, redirectURI: AppConfig.redirectURI)
        var fallbacks: [BPMLookup] = []
        if !AppConfig.getSongBPMAPIKey.isEmpty {
            fallbacks.append(GetSongBPMAPI(apiKey: AppConfig.getSongBPMAPIKey))
        }
        fallbacks.append(DeezerAPI())
        let service = PlaylistService(spotify: SpotifyAPI(tokens: auth), bpmFallbacks: fallbacks, cache: cache)
        return (auth, service)
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

    // MARK: Custom moods

    private static let customMoodsKey = "customMoods"

    private static func loadCustomMoods() -> [CustomMood] {
        guard let data = UserDefaults.standard.data(forKey: customMoodsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomMood].self, from: data)) ?? []
    }

    func customMood(id: UUID) -> CustomMood? {
        customMoods.first { $0.id == id }
    }

    /// Adds the mood, or replaces the one with the same ID.
    func saveCustomMood(_ mood: CustomMood) {
        if let index = customMoods.firstIndex(where: { $0.id == mood.id }) {
            customMoods[index] = mood
        } else {
            customMoods.append(mood)
        }
        persistCustomMoods()
    }

    func deleteCustomMood(_ mood: CustomMood) {
        customMoods.removeAll { $0.id == mood.id }
        UserDefaults.standard.removeObject(forKey: playlistKey(.custom(mood)))
        persistCustomMoods()
    }

    private func persistCustomMoods() {
        if let data = try? JSONEncoder().encode(customMoods) {
            UserDefaults.standard.set(data, forKey: Self.customMoodsKey)
        }
    }

    // MARK: Saved playlist IDs (so refreshing a mood updates the same playlist)

    private func playlistKey(_ choice: MoodChoice) -> String { "playlist.\(choice.id)" }

    func savedPlaylistID(for choice: MoodChoice) -> String? {
        UserDefaults.standard.string(forKey: playlistKey(choice))
    }

    func setSavedPlaylistID(_ id: String, for choice: MoodChoice) {
        UserDefaults.standard.set(id, forKey: playlistKey(choice))
    }
}
