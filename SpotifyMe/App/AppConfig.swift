import Foundation

/// App settings. The Spotify Client ID and GetSongBPM key are entered on the device
/// (stored in UserDefaults) so each person can use their own Spotify app. Values from
/// Config.xcconfig (through Info.plist) are used as defaults when nothing was entered.
enum AppConfig {
    static let redirectScheme = "spotifyme"
    static let redirectURI = "spotifyme://callback"
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    private static let clientIDKey = "settings.spotifyClientID"
    private static let bpmKeyKey = "settings.getSongBPMAPIKey"

    static var spotifyClientID: String {
        stored(clientIDKey) ?? bundleValue("SpotifyClientID")
    }

    static var getSongBPMAPIKey: String {
        stored(bpmKeyKey) ?? bundleValue("GetSongBPMAPIKey")
    }

    static var isConfigured: Bool { isValidClientID(spotifyClientID) }

    static func save(clientID: String, getSongBPMAPIKey: String) {
        let defaults = UserDefaults.standard
        defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey)
        defaults.set(getSongBPMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: bpmKeyKey)
    }

    /// Spotify Client IDs are 32 hexadecimal characters.
    static func isValidClientID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count == 32 && trimmed.allSatisfy(\.isHexDigit)
    }

    private static func stored(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private static func bundleValue(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        // An unset build setting shows up as "" or as the literal "$(NAME)".
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespaces)
    }
}
