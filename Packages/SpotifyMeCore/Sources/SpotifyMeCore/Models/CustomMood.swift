import Foundation

/// A mood the user defines by setting every selection rule themselves.
public struct CustomMood: Codable, Hashable, Identifiable, Sendable {
    /// An inclusive range of a feature. A disabled range accepts any value, including a missing one.
    public struct Range: Codable, Hashable, Sendable {
        public var isEnabled: Bool
        public var min: Double
        public var max: Double

        public init(isEnabled: Bool = false, min: Double, max: Double) {
            self.isEnabled = isEnabled
            self.min = min
            self.max = max
        }

        public func contains(_ value: Double) -> Bool { (Swift.min(min, max)...Swift.max(min, max)).contains(value) }
        public var midpoint: Double { (min + max) / 2 }
        public var halfWidth: Double { abs(max - min) / 2 }
    }

    /// Where tracks may come from.
    public enum Source: String, Codable, CaseIterable, Hashable, Sendable {
        case topTracks, recentlyPlayed, liked, topArtists, newMusic

        public var title: String {
            switch self {
            case .topTracks: return "Your top tracks"
            case .recentlyPlayed: return "Recently played"
            case .liked: return "Liked Songs"
            case .topArtists: return "More from your top artists"
            case .newMusic: return "New recommendations"
            }
        }

        var origins: Set<TrackOrigin> {
            switch self {
            case .topTracks: return [.topShortTerm, .topMediumTerm, .topLongTerm]
            case .recentlyPlayed: return [.recentlyPlayed]
            case .liked: return [.liked]
            case .topArtists: return [.artistSearch]
            case .newMusic: return [.recommendation]
            }
        }
    }

    /// How the chosen tracks are ordered.
    public enum Order: String, Codable, CaseIterable, Hashable, Sendable {
        case bestMatchFirst, shuffled, energyRising, energyFalling, tempoRising, tempoFalling, warmUpCoolDown

        public var title: String {
            switch self {
            case .bestMatchFirst: return "Best match first"
            case .shuffled: return "Shuffled"
            case .energyRising: return "Energy builds up"
            case .energyFalling: return "Energy winds down"
            case .tempoRising: return "Tempo speeds up"
            case .tempoFalling: return "Tempo slows down"
            case .warmUpCoolDown: return "Gentle start and finish"
            }
        }
    }

    public var id: UUID
    public var name: String
    /// SF Symbol name.
    public var symbol: String
    /// Index into the app's color palette.
    public var colorIndex: Int

    public var tempo: Range
    /// Count a track at half the tempo as a match (e.g. 90 BPM for a 180 BPM target), as runners do.
    public var countHalfTime: Bool
    public var energy: Range
    public var valence: Range
    public var danceability: Range
    public var acousticness: Range

    public var sources: Set<Source>
    public var order: Order
    public var targetCount: Int
    public var maxPerArtist: Int
    /// Avoid the same artist twice in a row (applied after ordering, except for tempo/energy orders).
    public var spreadArtists: Bool
    /// Fetch recommendations aimed at these settings when too few tracks match.
    public var addRecommendationsWhenShort: Bool

    public init(id: UUID = UUID(), name: String = "My Mood", symbol: String = "music.note", colorIndex: Int = 0,
                tempo: Range = Range(min: 90, max: 130), countHalfTime: Bool = false,
                energy: Range = Range(min: 0.4, max: 0.8), valence: Range = Range(min: 0.4, max: 1),
                danceability: Range = Range(min: 0.5, max: 1), acousticness: Range = Range(min: 0, max: 0.5),
                sources: Set<Source> = Set(Source.allCases), order: Order = .bestMatchFirst,
                targetCount: Int = 30, maxPerArtist: Int = 2, spreadArtists: Bool = true,
                addRecommendationsWhenShort: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.tempo = tempo
        self.countHalfTime = countHalfTime
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.acousticness = acousticness
        self.sources = sources
        self.order = order
        self.targetCount = targetCount
        self.maxPerArtist = maxPerArtist
        self.spreadArtists = spreadArtists
        self.addRecommendationsWhenShort = addRecommendationsWhenShort
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom Mood" : trimmed
    }

    /// One-line summary of the active rules.
    public var summary: String {
        var parts: [String] = []
        if tempo.isEnabled { parts.append("\(Int(tempo.min))–\(Int(tempo.max)) BPM") }
        func pct(_ r: Range, _ label: String) {
            if r.isEnabled { parts.append("\(label) \(Int(r.min * 100))–\(Int(r.max * 100))%") }
        }
        pct(energy, "energy")
        pct(valence, "positivity")
        pct(danceability, "dance")
        pct(acousticness, "acoustic")
        return parts.isEmpty ? "Any track from your library" : parts.joined(separator: " · ")
    }

    var allowedOrigins: Set<TrackOrigin> {
        sources.reduce(into: Set<TrackOrigin>()) { $0.formUnion($1.origins) }
    }

    /// True when the tempo window is enabled, so BPM fallbacks are worth looking up.
    public var needsTempo: Bool { tempo.isEnabled }
}

/// A built-in mood or one the user made. Drives generation, saving and display.
public enum MoodChoice: Hashable, Identifiable, Sendable {
    case builtIn(Mood)
    case custom(CustomMood)

    public var id: String {
        switch self {
        case .builtIn(let mood): return mood.rawValue
        case .custom(let mood): return "custom." + mood.id.uuidString
        }
    }

    public var title: String {
        switch self {
        case .builtIn(let mood): return mood.title
        case .custom(let mood): return mood.displayName
        }
    }

    public var subtitle: String {
        switch self {
        case .builtIn(let mood): return mood.subtitle
        case .custom(let mood): return mood.summary
        }
    }

    public var symbol: String {
        switch self {
        case .builtIn(let mood): return mood.symbol
        case .custom(let mood): return mood.symbol
        }
    }

    public var playlistName: String { "SpotifyMe · \(title)" }

    public var playlistDescription: String {
        switch self {
        case .builtIn(let mood): return mood.playlistDescription
        case .custom(let mood): return "\(mood.summary). Custom mood made by SpotifyMe from your listening history."
        }
    }
}
