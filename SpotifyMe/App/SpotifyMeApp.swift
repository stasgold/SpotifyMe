import SwiftUI

@main
struct SpotifyMeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.green)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !AppConfig.isConfigured {
                MissingConfigView()
            } else if model.isSignedIn {
                MoodGridView()
            } else {
                LoginView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MissingConfigView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Spotify Client ID missing", systemImage: "key.slash")
        } description: {
            Text("Copy Config.example.xcconfig to Config.xcconfig, add your Spotify Client ID, and rebuild. See README.md.")
        }
    }
}
