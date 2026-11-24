import Foundation

/// A track in the candidate pool, independent of which API it came from.
public struct Track: Codable, Hashable, Identifiable, Sendable {
    /// Spotify track ID (base-62).
    public let id: String
    public let name: String
    public let artists: [String]
    public let primaryArtistID: String?
    public let durationMs: Int
    public let isrc: String?

    public init(id: String, name: String, artists: [String], primaryArtistID: String?, durationMs: Int, isrc: String?) {
        self.id = id
        self.name = name
        self.artists = artists
        self.primaryArtistID = primaryArtistID
        self.durationMs = durationMs
        self.isrc = isrc
    }

    public var uri: String { "spotify:track:\(id)" }
    public var primaryArtist: String { artists.first ?? "" }
    public var artistLine: String { artists.joined(separator: ", ") }

    /// Key used to limit tracks per artist. Falls back to the name when the ID is missing.
    var artistKey: String { primaryArtistID ?? primaryArtist.lowercased() }
}

/// Audio features in Spotify's former scale (0...1 for most fields, BPM for tempo).
/// Any field may be missing depending on which provider answered.
public struct AudioFeatures: Codable, Hashable, Sendable {
    public var tempo: Double?
    public var energy: Double?
    public var valence: Double?
    public var danceability: Double?
    public var acousticness: Double?
    public var source: String

    public init(tempo: Double? = nil, energy: Double? = nil, valence: Double? = nil,
                danceability: Double? = nil, acousticness: Double? = nil, source: String) {
        self.tempo = tempo
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.acousticness = acousticness
        self.source = source
    }

    /// True when we have the mood fields (energy/valence), not just BPM.
    public var hasMoodData: Bool { energy != nil && valence != nil }
}

/// Where a track in the pool came from. Used by "Surprise Me".
public enum TrackOrigin: String, Codable, Hashable, Sendable {
    case topShortTerm, topMediumTerm, topLongTerm, recentlyPlayed, liked, artistSearch, recommendation
}

/// A track together with its features and origins.
public struct CandidateTrack: Hashable, Sendable, Identifiable {
    public var track: Track
    public var features: AudioFeatures?
    public var origins: Set<TrackOrigin>

    public var id: String { track.id }

    public init(track: Track, features: AudioFeatures?, origins: Set<TrackOrigin>) {
        self.track = track
        self.features = features
        self.origins = origins
    }
}
