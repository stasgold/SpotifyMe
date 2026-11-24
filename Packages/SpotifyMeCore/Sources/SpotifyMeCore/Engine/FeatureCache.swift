import Foundation

/// Persistent cache of audio features so each track is looked up only once.
/// Also remembers misses for a while so unknown tracks are not re-queried on every refresh.
public actor FeatureCache {
    struct Stored: Codable {
        var features: [String: AudioFeatures] = [:]
        var misses: [String: Date] = [:]
    }

    private let fileURL: URL?
    private var stored = Stored()
    private let missTTL: TimeInterval

    /// - Parameter fileURL: where to persist; nil keeps the cache in memory only (tests).
    public init(fileURL: URL?, missTTL: TimeInterval = 14 * 24 * 3600) {
        self.fileURL = fileURL
        self.missTTL = missTTL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    public func features(for id: String) -> AudioFeatures? { stored.features[id] }

    /// IDs that have no cached features and were not recently looked up without success.
    public func idsNeedingLookup(_ ids: [String]) -> [String] {
        let now = Date()
        return ids.filter { id in
            guard stored.features[id] == nil else { return false }
            if let missed = stored.misses[id], now.timeIntervalSince(missed) < missTTL { return false }
            return true
        }
    }

    public func store(_ features: AudioFeatures, for id: String) {
        // Never replace full mood data with BPM-only data.
        if let existing = stored.features[id], existing.hasMoodData, !features.hasMoodData { return }
        stored.features[id] = features
        stored.misses[id] = nil
    }

    public func recordMiss(_ id: String) {
        stored.misses[id] = Date()
    }

    public func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            // A failed cache write only costs extra lookups next time.
        }
    }

    public func clear() {
        stored = Stored()
        save()
    }
}
