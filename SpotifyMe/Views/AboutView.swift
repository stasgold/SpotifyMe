import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSetup = false

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
                Section("Spotify app") {
                    LabeledContent("Client ID", value: maskedClientID)
                    Button("Change Client ID or API keys") { showSetup = true }
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
            .sheet(isPresented: $showSetup) {
                NavigationStack {
                    SetupView(onDone: { showSetup = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showSetup = false }
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var maskedClientID: String {
        let id = AppConfig.spotifyClientID
        return id.count > 8 ? "…" + id.suffix(6) : id
    }
}
