import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Something that can look up a track's BPM when ReccoBeats has no data for it.
public protocol BPMLookup: Sendable {
    var name: String { get }
    func bpm(for track: Track) async throws -> Double?
}

/// GetSongBPM (https://getsongbpm.com/api): free with an API key.
/// Terms: a visible link back to GetSongBPM.com is REQUIRED (the app's About screen has one).
public struct GetSongBPMAPI: BPMLookup {
    public let name = "GetSongBPM"
    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public func bpm(for track: Track) async throws -> Double? {
        let url = URL.make("https://api.getsong.co/search/", [
            "type": "both",
            "lookup": "song:\(track.name) artist:\(track.primaryArtist)",
            "limit": "5"
        ])
        let response = try await http.get(url, headers: ["X-API-KEY": apiKey], as: Response.self)
        guard let results = response.search else { return nil }
        // Prefer a result whose artist matches; otherwise take the first.
        let match = results.first { $0.artist?.name.lowercased() == track.primaryArtist.lowercased() } ?? results.first
        return match?.tempo.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }

    struct Response: Decodable {
        let search: [Result]?

        init(from decoder: Decoder) throws {
            // When nothing is found the API returns {"search": {"error": "no result"}} instead of an array.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            search = try? container.decode([Result].self, forKey: .search)
        }
        enum CodingKeys: String, CodingKey { case search }
    }

    struct Result: Decodable {
        struct ArtistDTO: Decodable { let name: String }
        let title: String?
        let tempo: String?
        let artist: ArtistDTO?
    }
}

/// Deezer public API: free, no key for catalog lookups. Tracks found by ISRC carry a `bpm` field,
/// which is often 0 (not analyzed); 0 is treated as unknown.
public struct DeezerAPI: BPMLookup {
    public let name = "Deezer"
    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func bpm(for track: Track) async throws -> Double? {
        guard let isrc = track.isrc, !isrc.isEmpty else { return nil }
        let url = URL.make("https://api.deezer.com/track/isrc:\(isrc)")
        let response = try await http.get(url, as: Response.self)
        guard let bpm = response.bpm, bpm > 0 else { return nil }
        return bpm
    }

    struct Response: Decodable {
        let bpm: Double?
    }
}
