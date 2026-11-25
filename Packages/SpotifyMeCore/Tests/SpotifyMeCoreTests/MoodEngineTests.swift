import XCTest
@testable import SpotifyMeCore

/// Deterministic RNG so tests are repeatable.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class MoodEngineTests: XCTestCase {
    private var rng = SeededRNG(state: 42)
    private let engine = MoodEngine(options: .init(targetCount: 30, maxPerArtist: 2, jitter: 0))

    private func track(_ id: String, artist: String? = nil, tempo: Double? = nil, energy: Double? = nil,
                       valence: Double? = nil, dance: Double? = nil, acoustic: Double? = nil,
                       origins: Set<TrackOrigin> = [.topMediumTerm]) -> CandidateTrack {
        let artistName = artist ?? "Artist \(id)"
        let features: AudioFeatures? = (tempo == nil && energy == nil && valence == nil) ? nil :
            AudioFeatures(tempo: tempo, energy: energy, valence: valence, danceability: dance, acousticness: acoustic, source: "test")
        return CandidateTrack(track: Track(id: id, name: "Song \(id)", artists: [artistName], primaryArtistID: artistName,
                                           durationMs: 200_000, isrc: nil),
                              features: features, origins: origins)
    }

    func testCadenceDeviationCountsHalfTime() {
        XCTAssertEqual(MoodEngine.cadenceDeviation(tempo: 180, cadence: 180), 0)
        XCTAssertEqual(MoodEngine.cadenceDeviation(tempo: 90, cadence: 180), 0)
        XCTAssertEqual(MoodEngine.cadenceDeviation(tempo: 88, cadence: 180), 4)
        XCTAssertEqual(MoodEngine.cadenceDeviation(tempo: 172, cadence: 170), 2)
        XCTAssertNil(MoodEngine.cadenceDeviation(tempo: nil, cadence: 180))
    }

    func testRunning180SelectsMatchingTempos() {
        let pool = [
            track("a", tempo: 180, energy: 0.8),
            track("b", tempo: 90, energy: 0.9),      // half-time
            track("c", tempo: 178, energy: nil),     // BPM only (fallback source) is allowed
            track("d", tempo: 120, energy: 0.9),     // wrong tempo
            track("e", tempo: 181, energy: 0.3),     // too calm
            track("f", tempo: 170, energy: 0.8)      // 170 is outside even the widened window
        ]
        let ids = Set(engine.playlist(for: .running180, from: pool, rng: &rng).map(\.id))
        XCTAssertEqual(ids, ["a", "b", "c"])
    }

    func testRunning170() {
        let pool = [track("a", tempo: 170, energy: 0.8), track("b", tempo: 85, energy: 0.8), track("c", tempo: 180, energy: 0.8)]
        XCTAssertEqual(Set(engine.playlist(for: .running170, from: pool, rng: &rng).map(\.id)), ["a", "b"])
    }

    func testRunningWidensWindowOnlyWhenNeeded() {
        let pool = [track("exact", tempo: 180, energy: 0.8), track("near", tempo: 187, energy: 0.8)]
        // Not enough tracks at ±5, so ±8 is used and "near" is included.
        XCTAssertEqual(Set(engine.playlist(for: .running180, from: pool, rng: &rng).map(\.id)), ["exact", "near"])

        let small = MoodEngine(options: .init(targetCount: 1, maxPerArtist: 2, jitter: 0))
        XCTAssertEqual(small.playlist(for: .running180, from: pool, rng: &rng).map(\.id), ["exact"])
    }

    func testSlowDownIsCalmAndWindsDown() {
        let pool = [
            track("a", tempo: 70, energy: 0.2, acoustic: 0.9),
            track("b", tempo: 90, energy: 0.4, acoustic: 0.5),
            track("c", tempo: 95, energy: 0.3, acoustic: 0.7),
            track("loud", tempo: 80, energy: 0.8),
            track("fast", tempo: 140, energy: 0.2)
        ]
        let result = engine.playlist(for: .slowDown, from: pool, rng: &rng).map(\.id)
        XCTAssertEqual(result, ["b", "c", "a"]) // energy 0.4 -> 0.3 -> 0.2
    }

    func testSpeedUpBuilds() {
        let pool = [
            track("mid", tempo: 125, energy: 0.75),
            track("high", tempo: 148, energy: 0.95),
            track("low", tempo: 102, energy: 0.62),
            track("slow", tempo: 90, energy: 0.9)
        ]
        XCTAssertEqual(engine.playlist(for: .speedUp, from: pool, rng: &rng).map(\.id), ["low", "mid", "high"])
    }

    func testFeelingGood() {
        let pool = [
            track("happy", tempo: 120, energy: 0.7, valence: 0.9, dance: 0.8),
            track("sad", tempo: 120, energy: 0.7, valence: 0.2, dance: 0.8),
            track("intense", tempo: 120, energy: 0.95, valence: 0.9, dance: 0.8),
            track("stiff", tempo: 120, energy: 0.7, valence: 0.9, dance: 0.3)
        ]
        XCTAssertEqual(engine.playlist(for: .feelingGood, from: pool, rng: &rng).map(\.id), ["happy"])
    }

    func testMaxTwoTracksPerArtist() {
        let pool = (0..<5).map { track("t\($0)", artist: "Same", tempo: 180, energy: 0.8) }
        XCTAssertEqual(engine.playlist(for: .running180, from: pool, rng: &rng).count, 2)
    }

    func testSurpriseMeMixesForgottenAndNew() {
        var pool: [CandidateTrack] = []
        pool += (0..<20).map { track("old\($0)", origins: [.topLongTerm]) }
        pool += (0..<20).map { track("new\($0)", origins: [.recommendation]) }
        pool += (0..<20).map { track("now\($0)", origins: [.topShortTerm, .topLongTerm]) }

        let result = engine.playlist(for: .surpriseMe, from: pool, rng: &rng)
        XCTAssertEqual(result.count, 30)
        XCTAssertEqual(result.filter { $0.id.hasPrefix("old") }.count, 12)
        XCTAssertEqual(result.filter { $0.id.hasPrefix("new") }.count, 18)
        XCTAssertTrue(result.allSatisfy { !$0.id.hasPrefix("now") }, "Currently played tracks are not a surprise")
    }

    func testSpreadArtistsAvoidsRepeats() {
        let tracks = [track("1", artist: "A"), track("2", artist: "A"), track("3", artist: "B"), track("4", artist: "B")]
        let spread = MoodEngine.spreadArtists(tracks).map(\.track.primaryArtist)
        for i in 1..<spread.count { XCTAssertNotEqual(spread[i], spread[i - 1]) }
    }

    func testDeduplicateMergesOrigins() {
        let merged = MoodEngine.deduplicated([track("x", origins: [.liked]), track("x", origins: [.topLongTerm])])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].origins, [.liked, .topLongTerm])
    }

    func testReccoBeatsHrefParsing() {
        XCTAssertEqual(ReccoBeatsAPI.spotifyID(fromHref: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"), "4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertNil(ReccoBeatsAPI.spotifyID(fromHref: "https://open.spotify.com/artist/abc"))
        XCTAssertNil(ReccoBeatsAPI.spotifyID(fromHref: nil))
    }

    func testGetSongBPMNoResultShape() throws {
        let data = Data(#"{"search":{"error":"no result"}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(GetSongBPMAPI.Response.self, from: data).search)
    }

    // MARK: - Custom moods

    func testCustomMoodAppliesEveryEnabledRange() {
        let mood = CustomMood(tempo: .init(isEnabled: true, min: 100, max: 120),
                              energy: .init(isEnabled: true, min: 0.5, max: 0.9),
                              valence: .init(isEnabled: true, min: 0.6, max: 1),
                              danceability: .init(isEnabled: false, min: 0, max: 1),
                              acousticness: .init(isEnabled: true, min: 0, max: 0.3))
        let pool = [
            track("ok", tempo: 110, energy: 0.7, valence: 0.8, acoustic: 0.1),
            track("slow", tempo: 90, energy: 0.7, valence: 0.8, acoustic: 0.1),
            track("sad", tempo: 110, energy: 0.7, valence: 0.3, acoustic: 0.1),
            track("acoustic", tempo: 110, energy: 0.7, valence: 0.8, acoustic: 0.9),
            track("noTempo", energy: 0.7, valence: 0.8, acoustic: 0.1)
        ]
        XCTAssertEqual(engine.playlist(for: mood, from: pool, rng: &rng).map(\.id), ["ok"])
    }

    func testCustomMoodHalfTimeAndTempoOrder() {
        var mood = CustomMood(tempo: .init(isEnabled: true, min: 170, max: 190), countHalfTime: true,
                              energy: .init(min: 0, max: 1), valence: .init(min: 0, max: 1),
                              danceability: .init(min: 0, max: 1), acousticness: .init(min: 0, max: 1))
        mood.order = .tempoRising
        let pool = [track("a", tempo: 186), track("b", tempo: 88), track("c", tempo: 180), track("d", tempo: 120)]
        XCTAssertEqual(engine.playlist(for: mood, from: pool, rng: &rng).map(\.id), ["b", "c", "a"])
        mood.countHalfTime = false
        XCTAssertEqual(Set(engine.playlist(for: mood, from: pool, rng: &rng).map(\.id)), ["a", "c"])
    }

    func testCustomMoodSourcesCountAndArtistCap() {
        var mood = CustomMood(tempo: .init(min: 0, max: 300), energy: .init(min: 0, max: 1),
                              valence: .init(min: 0, max: 1), danceability: .init(min: 0, max: 1),
                              acousticness: .init(min: 0, max: 1), sources: [.liked], targetCount: 3, maxPerArtist: 1)
        let pool = [
            track("l1", artist: "X", energy: 0.5, origins: [.liked]),
            track("l2", artist: "X", energy: 0.5, origins: [.liked]),
            track("l3", artist: "Y", energy: 0.5, origins: [.liked]),
            track("t1", artist: "Z", energy: 0.5, origins: [.topShortTerm])
        ]
        let ids = engine.playlist(for: mood, from: pool, rng: &rng).map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertFalse(ids.contains("t1"))
        mood.sources = [.liked, .topTracks]
        XCTAssertEqual(engine.playlist(for: mood, from: pool, rng: &rng).count, 3)
    }

    func testCustomMoodRoundTripsThroughJSON() throws {
        let mood = CustomMood(name: "Evening", order: .energyFalling, targetCount: 25)
        let decoded = try JSONDecoder().decode(CustomMood.self, from: JSONEncoder().encode(mood))
        XCTAssertEqual(decoded, mood)
    }

    // MARK: - Filling with recommendations

    func testFillTopsUpToTargetWithBestFittingRecommendations() {
        let small = MoodEngine(options: .init(targetCount: 4, maxPerArtist: 2, jitter: 0))
        let pool = [
            track("mine1", tempo: 70, energy: 0.2),
            track("mine2", tempo: 75, energy: 0.3),
            // Recommendations that miss Slow Down's strict rules by different amounts.
            track("recClose", tempo: 85, energy: 0.5, origins: [.recommendation]),
            track("recFar", tempo: 170, energy: 0.95, origins: [.recommendation]),
            track("recMid", tempo: 105, energy: 0.5, origins: [.recommendation]),
            // Not a recommendation: never used as filler.
            track("liked", tempo: 160, energy: 0.9, origins: [.liked])
        ]
        let picked = small.playlist(for: .slowDown, from: pool, rng: &rng)
        XCTAssertEqual(Set(picked.map(\.id)), ["mine1", "mine2"])

        let filled = small.filled(picked, for: .builtIn(.slowDown), from: pool, rng: &rng)
        XCTAssertEqual(Set(filled.map(\.id)), ["mine1", "mine2", "recClose", "recMid"])
        // Still in Slow Down order: energy falls.
        let energies = filled.map { $0.features?.energy ?? 0 }
        XCTAssertEqual(energies, energies.sorted(by: >))
    }

    func testFillRespectsArtistCapAndLeavesFullPlaylistsAlone() {
        let small = MoodEngine(options: .init(targetCount: 3, maxPerArtist: 1, jitter: 0))
        let pool = [
            track("r1", artist: "Same", tempo: 128, energy: 0.8, origins: [.recommendation]),
            track("r2", artist: "Same", tempo: 128, energy: 0.8, origins: [.recommendation]),
            track("r3", artist: "Other", tempo: 128, energy: 0.8, origins: [.recommendation])
        ]
        let filled = small.filled([], for: .builtIn(.speedUp), from: pool, rng: &rng)
        XCTAssertEqual(filled.count, 2)
        XCTAssertEqual(Set(filled.map(\.track.primaryArtist)), ["Same", "Other"])

        let full = [track("a"), track("b"), track("c")]
        XCTAssertEqual(small.filled(full, for: .builtIn(.speedUp), from: pool, rng: &rng).map(\.id), ["a", "b", "c"])
    }

    func testFillUsesCustomMoodTargetCount() {
        var mood = CustomMood(tempo: .init(isEnabled: true, min: 100, max: 110), targetCount: 2)
        mood.sources = [.liked]
        let pool = [
            track("r1", tempo: 140, energy: 0.6, origins: [.recommendation]),
            track("r2", tempo: 112, energy: 0.6, origins: [.recommendation]),
            track("r3", tempo: 180, energy: 0.6, origins: [.recommendation])
        ]
        // No source match at all, but the custom mood's target of 2 is still filled with the closest tempos.
        XCTAssertTrue(engine.playlist(for: mood, from: pool, rng: &rng).isEmpty)
        let filled = engine.filled([], for: .custom(mood), from: pool, rng: &rng)
        XCTAssertEqual(Set(filled.map(\.id)), ["r1", "r2"])
    }
}
