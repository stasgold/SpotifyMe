import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies a valid (refreshed if needed) Spotify access token.
public protocol AccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}

/// The Spotify Web API calls SpotifyMe needs.
///
/// Notes on Spotify's restrictions for Development Mode apps:
/// - Nov 2024: audio-features, audio-analysis, recommendations and related-artists were removed
///   for new apps. Tempo/mood data comes from ReccoBeats/GetSongBPM/Deezer instead.
/// - Feb 2026: artist top-tracks and batch "get several" endpoints were removed, playlist creation
///   moved to POST /me/playlists, and playlist item endpoints moved from /tracks to /items.
public struct SpotifyAPI: Sendable {
    public enum TimeRange: String, Sendable { case shortTerm = "short_term", mediumTerm = "medium_term", longTerm = "long_term" }

    private let base = "https://api.spotify.com/v1"
    private let tokens: AccessTokenProvider
    private let http: HTTPClient

    public init(tokens: AccessTokenProvider, http: HTTPClient = HTTPClient()) {
        self.tokens = tokens
        self.http = http
    }

    // MARK: Reading history

    public func topTracks(_ range: TimeRange, limit: Int = 50) async throws -> [Track] {
        let page: Page<SpotifyTrack> = try await get("/me/top/tracks", ["time_range": range.rawValue, "limit": "\(limit)"])
        return page.items.compactMap(\.model)
    }

    public func topArtists(_ range: TimeRange, limit: Int = 20) async throws -> [Artist] {
        let page: Page<SpotifyArtist> = try await get("/me/top/artists", ["time_range": range.rawValue, "limit": "\(limit)"])
        return page.items.map { Artist(id: $0.id, name: $0.name) }
    }

    public func recentlyPlayed(limit: Int = 50) async throws -> [Track] {
        let page: Page<PlayHistory> = try await get("/me/player/recently-played", ["limit": "\(limit)"])
        return page.items.compactMap(\.track.model)
    }

    /// Liked Songs, newest first, up to `maxCount`.
    public func likedTracks(maxCount: Int = 200) async throws -> [Track] {
        var result: [Track] = []
        var offset = 0
        while result.count < maxCount {
            let page: Page<SavedTrack> = try await get("/me/tracks", ["limit": "50", "offset": "\(offset)"])
            result += page.items.compactMap(\.track.model)
            if page.next == nil || page.items.isEmpty { break }
            offset += 50
        }
        return Array(result.prefix(maxCount))
    }

    /// Tracks by an artist via search (replacement for the removed artist top-tracks endpoint).
    public func searchTracks(byArtist name: String, limit: Int = 10) async throws -> [Track] {
        let query = "artist:\"\(name)\""
        let result: SearchResult = try await get("/search", ["q": query, "type": "track", "limit": "\(limit)"])
        return result.tracks.items.compactMap(\.model)
    }

    // MARK: Writing playlists

    public struct CreatedPlaylist: Sendable { public let id: String; public let url: URL? }

    public func createPlaylist(name: String, description: String, isPublic: Bool = false) async throws -> CreatedPlaylist {
        struct Body: Encodable { let name: String; let description: String; let `public`: Bool }
        struct Response: Decodable { let id: String; let external_urls: [String: String]? }
        let data = try await send("POST", "/me/playlists", body: Body(name: name, description: description, public: isPublic))
        let response = try JSONDecoder().decode(Response.self, from: data)
        return CreatedPlaylist(id: response.id, url: response.external_urls?["spotify"].flatMap(URL.init(string:)))
    }

    /// Replaces the playlist's contents with `uris` (first 100 via PUT, the rest appended via POST).
    public func replacePlaylistItems(playlistID: String, uris: [String]) async throws {
        struct Body: Encodable { let uris: [String] }
        let chunks = stride(from: 0, to: max(uris.count, 1), by: 100).map { Array(uris[$0..<min($0 + 100, uris.count)]) }
        for (index, chunk) in chunks.enumerated() {
            _ = try await send(index == 0 ? "PUT" : "POST", "/playlists/\(playlistID)/items", body: Body(uris: chunk))
        }
    }

    /// Whether a playlist we created earlier still exists (the user may have deleted it).
    public func playlistExists(_ playlistID: String) async -> Bool {
        struct Minimal: Decodable { let id: String }
        do {
            let _: Minimal = try await get("/playlists/\(playlistID)", ["fields": "id"])
            return true
        } catch {
            return false
        }
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let token = try await tokens.accessToken()
        return try await http.get(.make(base + path, query), headers: ["Authorization": "Bearer \(token)"], as: T.self)
    }

    private func send<B: Encodable>(_ method: String, _ path: String, body: B) async throws -> Data {
        let token = try await tokens.accessToken()
        var request = URLRequest(url: .make(base + path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await http.send(request)
    }
}

public struct Artist: Hashable, Sendable {
    public let id: String
    public let name: String
}

// MARK: - Wire types

struct Page<T: Decodable>: Decodable {
    let items: [T]
    let next: String?
}

struct SpotifyArtist: Decodable {
    let id: String
    let name: String
}

struct SpotifyTrack: Decodable {
    struct ArtistRef: Decodable { let id: String?; let name: String }
    let id: String?
    let name: String
    let duration_ms: Int?
    let artists: [ArtistRef]
    let external_ids: [String: String]?
    let is_local: Bool?

    /// nil for local files or tracks without a Spotify ID.
    var model: Track? {
        guard let id, is_local != true else { return nil }
        return Track(id: id, name: name, artists: artists.map(\.name), primaryArtistID: artists.first?.id,
                     durationMs: duration_ms ?? 0, isrc: external_ids?["isrc"])
    }
}

struct PlayHistory: Decodable { let track: SpotifyTrack }
struct SavedTrack: Decodable { let track: SpotifyTrack }
struct SearchResult: Decodable { let tracks: Page<SpotifyTrack> }
