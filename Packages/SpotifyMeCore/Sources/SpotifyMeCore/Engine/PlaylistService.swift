import Foundation

/// Orchestrates: gather listening history -> attach audio features -> apply mood rules -> save to Spotify.
public actor PlaylistService {
    public enum Progress: Sendable {
        case readingHistory
        case analyzingTracks(done: Int, total: Int)
        case findingMoreTracks
        case choosingTracks
    }

    private let spotify: SpotifyAPI
    private let recco: ReccoBeatsAPI
    private let bpmFallbacks: [BPMLookup]
    private let cache: FeatureCache
    private let engine: MoodEngine
    /// Fewer than this many tracks for a mood triggers fetching recommendations.
    private let minimumTracks: Int
    /// Cap on slow, one-by-one fallback BPM lookups per generation.
    private let maxFallbackLookups: Int

    private var pool: [String: CandidateTrack] = [:]
    private var poolBuiltAt: Date?

    public init(spotify: SpotifyAPI, recco: ReccoBeatsAPI = ReccoBeatsAPI(), bpmFallbacks: [BPMLookup],
                cache: FeatureCache, engine: MoodEngine = MoodEngine(),
                minimumTracks: Int = 20, maxFallbackLookups: Int = 60) {
        self.spotify = spotify
        self.recco = recco
        self.bpmFallbacks = bpmFallbacks
        self.cache = cache
        self.engine = engine
        self.minimumTracks = minimumTracks
        self.maxFallbackLookups = maxFallbackLookups
    }

    // MARK: - Public

    public func generate(_ mood: Mood, forceRefresh: Bool = false,
                         progress: @Sendable (Progress) -> Void = { _ in }) async throws -> [CandidateTrack] {
        try await generate(.builtIn(mood), forceRefresh: forceRefresh, progress: progress)
    }

    public func generate(_ choice: MoodChoice, forceRefresh: Bool = false,
                         progress: @Sendable (Progress) -> Void = { _ in }) async throws -> [CandidateTrack] {
        try await ensurePool(forceRefresh: forceRefresh, progress: progress)

        let needsTempo: Bool
        let wantsMore: Bool
        let minimum: Int
        switch choice {
        case .builtIn(let mood):
            needsTempo = mood.cadence != nil
            wantsMore = mood != .surpriseMe
            minimum = minimumTracks
        case .custom(let mood):
            needsTempo = mood.needsTempo
            // Recommendations would be filtered out if new music isn't an allowed source.
            wantsMore = mood.addRecommendationsWhenShort && mood.sources.contains(.newMusic)
            minimum = min(minimumTracks, max(1, mood.targetCount))
        }

        if needsTempo {
            await fillMissingTempos(progress: progress)
        }

        progress(.choosingTracks)
        var result = engine.playlist(for: choice, from: Array(pool.values))

        if result.count < minimum, wantsMore {
            progress(.findingMoreTracks)
            await expandPool(for: choice, seeds: result.map(\.id), progress: progress)
            progress(.choosingTracks)
            result = engine.playlist(for: choice, from: Array(pool.values))
        }
        await cache.save()
        return result
    }

    /// Writes the tracks to Spotify. Reuses `existingPlaylistID` if it still exists, else creates a new playlist.
    public func save(_ tracks: [CandidateTrack], mood: Mood, existingPlaylistID: String?) async throws -> SpotifyAPI.CreatedPlaylist {
        try await save(tracks, choice: .builtIn(mood), existingPlaylistID: existingPlaylistID)
    }

    public func save(_ tracks: [CandidateTrack], choice mood: MoodChoice, existingPlaylistID: String?) async throws -> SpotifyAPI.CreatedPlaylist {
        let playlist: SpotifyAPI.CreatedPlaylist
        if let existingPlaylistID, await spotify.playlistExists(existingPlaylistID) {
            playlist = SpotifyAPI.CreatedPlaylist(id: existingPlaylistID,
                                                  url: URL(string: "https://open.spotify.com/playlist/\(existingPlaylistID)"))
        } else {
            playlist = try await spotify.createPlaylist(name: mood.playlistName, description: mood.playlistDescription)
        }
        try await spotify.replacePlaylistItems(playlistID: playlist.id, uris: tracks.map(\.track.uri))
        return playlist
    }

    // MARK: - Pool

    private func ensurePool(forceRefresh: Bool, progress: @Sendable (Progress) -> Void) async throws {
        let stale = poolBuiltAt.map { Date().timeIntervalSince($0) > 3600 } ?? true
        guard forceRefresh || stale || pool.isEmpty else { return }

        progress(.readingHistory)
        pool = [:]

        // Required: if these fail (e.g. expired login) the error is shown to the user.
        async let short = spotify.topTracks(.shortTerm)
        async let medium = spotify.topTracks(.mediumTerm)
        async let long = spotify.topTracks(.longTerm)
        add(try await short, origin: .topShortTerm)
        add(try await medium, origin: .topMediumTerm)
        add(try await long, origin: .topLongTerm)

        // Optional sources: a failure here just means a smaller pool.
        if let recent = try? await spotify.recentlyPlayed() { add(recent, origin: .recentlyPlayed) }
        if let liked = try? await spotify.likedTracks() { add(liked, origin: .liked) }

        if let artists = try? await spotify.topArtists(.mediumTerm, limit: 10) {
            for artist in artists {
                if let tracks = try? await spotify.searchTracks(byArtist: artist.name) {
                    // Keep only tracks actually by this artist (search can be fuzzy).
                    add(tracks.filter { $0.primaryArtistID == nil || $0.primaryArtistID == artist.id }, origin: .artistSearch)
                }
            }
        }

        // New music for "Surprise Me", seeded by recent favorites.
        let seeds = pool.values.filter { $0.origins.contains(.topShortTerm) }.prefix(5).map(\.id)
        if !seeds.isEmpty, let recs = try? await recco.recommendations(seedIDs: Array(seeds), size: 60) {
            add(recs, origin: .recommendation)
        }

        await attachFeatures(progress: progress)
        poolBuiltAt = Date()
    }

    private func add(_ tracks: [Track], origin: TrackOrigin) {
        for track in tracks {
            if var existing = pool[track.id] {
                existing.origins.insert(origin)
                pool[track.id] = existing
            } else {
                pool[track.id] = CandidateTrack(track: track, features: nil, origins: [origin])
            }
        }
    }

    // MARK: - Features

    private func attachFeatures(progress: @Sendable (Progress) -> Void) async {
        let ids = Array(pool.keys)
        let toFetch = await cache.idsNeedingLookup(ids)
        let batch = ReccoBeatsAPI.batchSize
        for start in stride(from: 0, to: toFetch.count, by: batch) {
            progress(.analyzingTracks(done: start, total: toFetch.count))
            let chunk = Array(toFetch[start..<min(start + batch, toFetch.count)])
            guard let found = try? await recco.audioFeatures(spotifyIDs: chunk) else { continue }
            for id in chunk {
                if let features = found[id] {
                    await cache.store(features, for: id)
                } else if !bpmFallbacksEnabled {
                    await cache.recordMiss(id)
                }
            }
        }
        progress(.analyzingTracks(done: toFetch.count, total: toFetch.count))
        for id in ids {
            pool[id]?.features = await cache.features(for: id)
        }
    }

    private var bpmFallbacksEnabled: Bool { !bpmFallbacks.isEmpty }

    /// For running moods: look up BPM one by one (GetSongBPM, then Deezer) for tracks without a tempo.
    private func fillMissingTempos(progress: @Sendable (Progress) -> Void) async {
        guard bpmFallbacksEnabled else { return }
        let missing = pool.values.filter { $0.features?.tempo == nil }.map(\.track)
        let candidates = await cache.idsNeedingLookup(missing.map(\.id))
        let candidateSet = Set(candidates)
        let lookups = missing.filter { candidateSet.contains($0.id) }.prefix(maxFallbackLookups)

        for (index, track) in lookups.enumerated() {
            progress(.analyzingTracks(done: index, total: lookups.count))
            var found: Double?
            for service in bpmFallbacks {
                if let bpm = try? await service.bpm(for: track) {
                    found = bpm
                    var features = pool[track.id]?.features ?? AudioFeatures(source: service.name)
                    features.tempo = bpm
                    features.source = features.hasMoodData ? features.source : service.name
                    await cache.store(features, for: track.id)
                    pool[track.id]?.features = features
                    break
                }
            }
            if found == nil { await cache.recordMiss(track.id) }
        }
    }

    // MARK: - Expansion

    private func expandPool(for choice: MoodChoice, seeds: [String], progress: @Sendable (Progress) -> Void) async {
        let fallbackSeeds = pool.values.filter { $0.origins.contains(.topShortTerm) || $0.origins.contains(.topMediumTerm) }.map(\.id)
        let seedIDs = Array((seeds + fallbackSeeds).prefix(5))
        guard !seedIDs.isEmpty else { return }

        let target: (tempo: Double?, energy: Double?, valence: Double?)
        switch choice {
        case .builtIn(let mood):
            switch mood {
            case .slowDown: target = (80, 0.3, nil)
            case .speedUp: target = (128, 0.8, nil)
            case .running180: target = (180, 0.8, nil)
            case .running170: target = (170, 0.8, nil)
            case .feelingGood: target = (118, 0.7, 0.85)
            case .surpriseMe: target = (nil, nil, nil)
            }
        case .custom(let mood):
            target = (mood.tempo.isEnabled ? mood.tempo.midpoint : nil,
                      mood.energy.isEnabled ? mood.energy.midpoint : nil,
                      mood.valence.isEnabled ? mood.valence.midpoint : nil)
        }
        guard let recs = try? await recco.recommendations(seedIDs: seedIDs, size: 100, tempo: target.tempo,
                                                         energy: target.energy, valence: target.valence) else { return }
        add(recs, origin: .recommendation)
        await attachFeatures(progress: progress)
    }
}
