import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Data sources") {
                    Link("Listening history and playlists: Spotify", destination: URL(string: "https://www.spotify.com")!)
                    Link("Audio features: ReccoBeats", destination: URL(string: "https://reccobeats.com")!)
                    // Required by GetSongBPM's API terms: a visible link back to their site.
                    Link("BPM data by GetSongBPM.com", destination: URL(string: "https://getsongbpm.com")!)
                    Link("BPM data: Deezer", destination: URL(string: "https://www.deezer.com")!)
                }
                Section {
                    Button("Clear cached track data") {
                        Task { await model.clearCache() }
                    }
                    Button("Sign out of Spotify", role: .destructive) {
                        Task {
                            await model.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
