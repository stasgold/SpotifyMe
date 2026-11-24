import Foundation

/// Values injected from Config.xcconfig through Info.plist.
enum AppConfig {
    static let redirectScheme = "spotifyme"
    static let redirectURI = "spotifyme://callback"

    static var spotifyClientID: String { value("SpotifyClientID") }
    static var getSongBPMAPIKey: String { value("GetSongBPMAPIKey") }

    static var isConfigured: Bool { !spotifyClientID.isEmpty }

    private static func value(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        // An unset build setting shows up as "" or as the literal "$(NAME)".
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespaces)
    }
}
