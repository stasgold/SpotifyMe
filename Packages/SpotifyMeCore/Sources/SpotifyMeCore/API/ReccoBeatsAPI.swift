import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ReccoBeats (https://reccobeats.com): free, no API key. Provides Spotify-style audio features
/// and recommendations, keyed by Spotify track IDs. Rate-limited (HTTP 429 + Retry-After),
/// which HTTPClient handles.
public struct ReccoBeatsAPI: Sendable {
    private let base = "https://api.reccobeats.com/v1"
    private let http: HTTPClient
    /// Max Spotify IDs per audio-features request.
    static let batchSize = 40

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    /// Audio features keyed by Spotify track ID. Tracks ReccoBeats does not know are left out.
    public func audioFeatures(spotifyIDs: [String]) async throws -> [String: AudioFeatures] {
        var result: [String: AudioFeatures] = [:]
        for start in stride(from: 0, to: spotifyIDs.count, by: Self.batchSize) {
            let batch = spotifyIDs[start..<min(start + Self.batchSize, spotifyIDs.count)]
            let url = URL.make(base + "/audio-features", ["ids": batch.joined(separator: ",")])
            let response = try await http.get(url, headers: ["Accept": "application/json"], as: Content<FeaturesDTO>.self)
            for item in response.content {
                guard let spotifyID = Self.spotifyID(fromHref: item.href) else { continue }
                result[spotifyID] = AudioFeatures(tempo: item.tempo, energy: item.energy, valence: item.valence,
                                                  danceability: item.danceability, acousticness: item.acousticness,
                                                  source: "ReccoBeats")
            }
        }
        return result
    }

    /// Recommended tracks similar to up to 5 seed tracks, optionally steered toward a target tempo/energy/valence.
    public func recommendations(seedIDs: [String], size: Int = 50,
                                tempo: Double? = nil, energy: Double? = nil, valence: Double? = nil) async throws -> [Track] {
        var query = ["seeds": seedIDs.prefix(5).joined(separator: ","), "size": "\(min(max(size, 1), 100))"]
        if let tempo { query["tempo"] = String(format: "%.0f", tempo) }
        if let energy { query["energy"] = String(format: "%.2f", energy) }
        if let valence { query["valence"] = String(format: "%.2f", valence) }
        let url = URL.make(base + "/track/recommendation", query)
        let response = try await http.get(url, headers: ["Accept": "application/json"], as: Content<TrackDTO>.self)
        return response.content.compactMap { dto in
            guard let id = Self.spotifyID(fromHref: dto.href) else { return nil }
            return Track(id: id, name: dto.trackTitle, artists: dto.artists?.map(\.name) ?? [],
                         primaryArtistID: dto.artists?.first.flatMap { Self.spotifyArtistID(fromHref: $0.href) },
                         durationMs: dto.durationMs ?? 0, isrc: dto.isrc)
        }
    }

    /// "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC" -> "4uLU6hMCjMI75M1A2tKUQC"
    static func spotifyID(fromHref href: String?) -> String? {
        guard let href, let url = URL(string: href), url.pathComponents.contains("track") else { return nil }
        return url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
    }

    static func spotifyArtistID(fromHref href: String?) -> String? {
        guard let href, let url = URL(string: href), url.pathComponents.contains("artist") else { return nil }
        return url.lastPathComponent
    }

    struct Content<T: Decodable>: Decodable { let content: [T] }

    struct FeaturesDTO: Decodable {
        let href: String?
        let tempo: Double?
        let energy: Double?
        let valence: Double?
        let danceability: Double?
        let acousticness: Double?
    }

    struct TrackDTO: Decodable {
        struct ArtistDTO: Decodable { let name: String; let href: String? }
        let trackTitle: String
        let artists: [ArtistDTO]?
        let durationMs: Int?
        let isrc: String?
        let href: String?
    }
}
