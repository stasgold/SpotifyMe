import Foundation

/// Pure, deterministic (given an RNG) selection and ordering of tracks for a mood.
/// No networking here, so the rules can be unit-tested.
public struct MoodEngine: Sendable {
    public struct Options: Sendable {
        public var targetCount: Int
        public var maxPerArtist: Int
        /// Random jitter added to scores so each refresh differs a little.
        public var jitter: Double

        public init(targetCount: Int = 30, maxPerArtist: Int = 2, jitter: Double = 0.05) {
            self.targetCount = targetCount
            self.maxPerArtist = maxPerArtist
            self.jitter = jitter
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func playlist(for mood: Mood, from pool: [CandidateTrack]) -> [CandidateTrack] {
        var rng = SystemRandomNumberGenerator()
        return playlist(for: mood, from: pool, rng: &rng)
    }

    public func playlist<R: RandomNumberGenerator>(for mood: Mood, from pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        let pool = Self.deduplicated(pool)
        switch mood {
        case .slowDown: return slowDown(pool, rng: &rng)
        case .speedUp: return speedUp(pool, rng: &rng)
        case .running180, .running170: return running(cadence: mood.cadence!, pool, rng: &rng)
        case .feelingGood: return feelingGood(pool, rng: &rng)
        case .surpriseMe: return surpriseMe(pool, rng: &rng)
        }
    }

    // MARK: - Slow Down

    private func slowDown<R: RandomNumberGenerator>(_ pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        let scored: [(CandidateTrack, Double)] = pool.compactMap { c in
            guard let f = c.features, let energy = f.energy else { return nil }
            guard energy < 0.45 else { return nil }
            if let tempo = f.tempo, !(60...100).contains(tempo) { return nil }
            let acoustic = f.acousticness ?? 0.3
            // Lower energy and more acoustic score higher.
            let score = (0.45 - energy) / 0.45 * 0.6 + acoustic * 0.4
            return (c, score)
        }
        let picked = pick(scored, rng: &rng)
        // Wind down: highest energy first, calmest last.
        return picked.sorted { ($0.features?.energy ?? 0) > ($1.features?.energy ?? 0) }
    }

    // MARK: - Speed Up

    private func speedUp<R: RandomNumberGenerator>(_ pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        let scored: [(CandidateTrack, Double)] = pool.compactMap { c in
            guard let f = c.features, let energy = f.energy, let tempo = f.tempo else { return nil }
            guard energy >= 0.6, (100...150).contains(tempo) else { return nil }
            return (c, energy)
        }
        let picked = pick(scored, rng: &rng)
        // Build: tempo and energy climb together.
        return picked.sorted { Self.intensity($0) < Self.intensity($1) }
    }

    private static func intensity(_ c: CandidateTrack) -> Double {
        let tempo = c.features?.tempo ?? 100
        let energy = c.features?.energy ?? 0.6
        return (tempo - 100) / 50 * 0.5 + energy * 0.5
    }

    // MARK: - Running

    /// How far a track's tempo is from the cadence, counting half-time
    /// (one step per half beat, e.g. 90 BPM for 180 spm). Returns nil when there is no tempo.
    public static func cadenceDeviation(tempo: Double?, cadence: Double) -> Double? {
        guard let tempo, tempo > 0 else { return nil }
        return min(abs(tempo - cadence), abs(tempo * 2 - cadence))
    }

    private func running<R: RandomNumberGenerator>(cadence: Double, _ pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        // Start strict and widen the tempo window only if there are not enough tracks.
        var result: [CandidateTrack] = []
        for tolerance in [5.0, 8.0] {
            let scored: [(CandidateTrack, Double)] = pool.compactMap { c in
                guard let dev = Self.cadenceDeviation(tempo: c.features?.tempo, cadence: cadence), dev <= tolerance else { return nil }
                let energy = c.features?.energy
                if let energy, energy < 0.65 { return nil }
                // Tracks with only BPM (no energy) are allowed but ranked lower.
                let energyScore = energy ?? 0.5
                let score = (1 - dev / tolerance) * 0.6 + energyScore * 0.4
                return (c, score)
            }
            result = pick(scored, rng: &rng)
            if result.count >= options.targetCount { break }
        }
        return Self.warmUpCoolDown(result)
    }

    /// Exact-tempo tracks in the middle, with the gentlest tracks first and last.
    static func warmUpCoolDown(_ tracks: [CandidateTrack]) -> [CandidateTrack] {
        guard tracks.count >= 4 else { return tracks }
        let byEnergy = tracks.sorted { ($0.features?.energy ?? 0.5) < ($1.features?.energy ?? 0.5) }
        let first = byEnergy[0]
        let last = byEnergy[1]
        let middle = tracks.filter { $0.id != first.id && $0.id != last.id }
        return [first] + middle + [last]
    }

    // MARK: - Feeling Good

    private func feelingGood<R: RandomNumberGenerator>(_ pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        let scored: [(CandidateTrack, Double)] = pool.compactMap { c in
            guard let f = c.features, let valence = f.valence, let energy = f.energy else { return nil }
            let dance = f.danceability ?? 0.6
            guard valence >= 0.65, (0.5...0.85).contains(energy), dance >= 0.6 else { return nil }
            return (c, valence * 0.6 + dance * 0.4)
        }
        return Self.spreadArtists(pick(scored, rng: &rng))
    }

    // MARK: - Surprise Me

    private func surpriseMe<R: RandomNumberGenerator>(_ pool: [CandidateTrack], rng: inout R) -> [CandidateTrack] {
        let personal: Set<TrackOrigin> = [.topShortTerm, .topMediumTerm, .topLongTerm, .recentlyPlayed, .liked]
        let recent: Set<TrackOrigin> = [.topShortTerm, .recentlyPlayed]

        let forgotten = pool.filter { $0.origins.contains(.topLongTerm) && $0.origins.isDisjoint(with: recent) }
        let fresh = pool.filter { $0.origins.isDisjoint(with: personal) }
        let likedNotRecent = pool.filter { $0.origins.contains(.liked) && $0.origins.isDisjoint(with: recent) }

        let forgottenTarget = Int((Double(options.targetCount) * 0.4).rounded())
        var counts: [String: Int] = [:]
        var chosen: [CandidateTrack] = []
        var used = Set<String>()

        func take(from source: [CandidateTrack], upTo limit: Int) {
            for c in source.shuffled(using: &rng) where chosen.count < limit {
                guard !used.contains(c.id), counts[c.track.artistKey, default: 0] < options.maxPerArtist else { continue }
                chosen.append(c)
                used.insert(c.id)
                counts[c.track.artistKey, default: 0] += 1
            }
        }

        take(from: forgotten, upTo: forgottenTarget)
        take(from: fresh, upTo: options.targetCount)
        // Top up if one bucket is thin.
        take(from: forgotten, upTo: options.targetCount)
        take(from: likedNotRecent, upTo: options.targetCount)

        chosen.shuffle(using: &rng)
        return Self.spreadArtists(chosen)
    }

    // MARK: - Helpers

    /// Sort by (score + jitter), then take tracks while respecting the per-artist cap.
    private func pick<R: RandomNumberGenerator>(_ scored: [(CandidateTrack, Double)], rng: inout R) -> [CandidateTrack] {
        let jittered = scored.map { ($0.0, $0.1 + (options.jitter > 0 ? Double.random(in: -options.jitter...options.jitter, using: &rng) : 0)) }
        let ranked = jittered.sorted { $0.1 > $1.1 }.map(\.0)
        var counts: [String: Int] = [:]
        var result: [CandidateTrack] = []
        for c in ranked {
            guard result.count < options.targetCount else { break }
            let key = c.track.artistKey
            guard counts[key, default: 0] < options.maxPerArtist else { continue }
            counts[key, default: 0] += 1
            result.append(c)
        }
        return result
    }

    /// Reorder so the same artist does not play twice in a row where possible.
    static func spreadArtists(_ tracks: [CandidateTrack]) -> [CandidateTrack] {
        var remaining = tracks
        var result: [CandidateTrack] = []
        while !remaining.isEmpty {
            let lastKey = result.last?.track.artistKey
            let index = remaining.firstIndex { $0.track.artistKey != lastKey } ?? 0
            result.append(remaining.remove(at: index))
        }
        return result
    }

    /// Merge duplicates (same Spotify ID) by combining their origins.
    static func deduplicated(_ pool: [CandidateTrack]) -> [CandidateTrack] {
        var order: [String] = []
        var byID: [String: CandidateTrack] = [:]
        for c in pool {
            if var existing = byID[c.id] {
                existing.origins.formUnion(c.origins)
                if existing.features == nil { existing.features = c.features }
                byID[c.id] = existing
            } else {
                byID[c.id] = c
                order.append(c.id)
            }
        }
        return order.compactMap { byID[$0] }
    }
}
