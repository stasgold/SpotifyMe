import Foundation

public enum Mood: String, CaseIterable, Codable, Identifiable, Sendable {
    case slowDown
    case speedUp
    case running180
    case running170
    case feelingGood
    case surpriseMe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .slowDown: return "Slow Down"
        case .speedUp: return "Speed Up"
        case .running180: return "Running 180 bpm"
        case .running170: return "Running 170 bpm"
        case .feelingGood: return "Feeling Good"
        case .surpriseMe: return "Surprise Me"
        }
    }

    public var subtitle: String {
        switch self {
        case .slowDown: return "Calm, low-energy tracks that wind down"
        case .speedUp: return "Tempo and energy that keep building"
        case .running180: return "Matched to 180 steps per minute"
        case .running170: return "Matched to 170 steps per minute"
        case .feelingGood: return "Upbeat, happy and danceable"
        case .surpriseMe: return "Forgotten favorites and new finds"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .slowDown: return "moon.stars.fill"
        case .speedUp: return "bolt.fill"
        case .running180: return "figure.run"
        case .running170: return "figure.run.circle.fill"
        case .feelingGood: return "sun.max.fill"
        case .surpriseMe: return "sparkles"
        }
    }

    public var playlistName: String { "SpotifyMe · \(title)" }

    public var playlistDescription: String {
        "\(subtitle). Made by SpotifyMe from your listening history."
    }

    /// Target running cadence, if this is a running mood.
    public var cadence: Double? {
        switch self {
        case .running180: return 180
        case .running170: return 170
        default: return nil
        }
    }
}
