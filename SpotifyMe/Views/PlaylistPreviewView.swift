import SpotifyMeCore
import SwiftUI

struct PlaylistPreviewView: View {
    let choice: MoodChoice

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    @State private var tracks: [CandidateTrack] = []
    @State private var status = "Reading your listening history…"
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var savedURL: URL?
    @State private var editing: CustomMood?

    /// The latest version of a custom mood, so edits apply right away.
    private var mood: MoodChoice {
        if case .custom(let original) = choice, let current = model.customMood(id: original.id) {
            return .custom(current)
        }
        return choice
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(status).foregroundStyle(.secondary)
                    }
                }
            } else if tracks.isEmpty {
                Section {
                    Text("No matching tracks found yet. Try Refresh, or listen to a bit more music first.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(tracks) { TrackRow(candidate: $0) }
                } header: {
                    Text("\(tracks.count) tracks · \(durationText)")
                }
            }
        }
        .navigationTitle(mood.title)
        .toolbar {
            if case .custom(let custom) = mood {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = custom }
                        .disabled(isLoading || isSaving)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load(forceRefresh: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(isLoading || isSaving)
                    .accessibilityLabel("Refresh")
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .task { await load(forceRefresh: false) }
        .sheet(item: $editing) { custom in
            MoodEditorView(mood: custom, isNew: false) {
                Task { await load(forceRefresh: false) }
            }
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        VStack(spacing: 8) {
            if let savedURL {
                Button {
                    openURL(savedURL)
                } label: {
                    Label("Saved! Open in Spotify", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) }
                    Text(model.savedPlaylistID(for: mood) == nil ? "Save to Spotify" : "Update playlist in Spotify").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracks.isEmpty || isLoading || isSaving)
        }
        .padding()
        .background(.bar)
    }

    private var durationText: String {
        let minutes = tracks.reduce(0) { $0 + $1.track.durationMs } / 60_000
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        savedURL = nil
        defer { isLoading = false }
        do {
            tracks = try await model.service.generate(mood, forceRefresh: forceRefresh) { progress in
                Task { @MainActor in status = progress.text }
            }
        } catch {
            await model.handle(error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let playlist = try await model.service.save(tracks, choice: mood, existingPlaylistID: model.savedPlaylistID(for: mood))
            model.setSavedPlaylistID(playlist.id, for: mood)
            savedURL = playlist.url
        } catch {
            await model.handle(error)
        }
    }
}

struct TrackRow: View {
    let candidate: CandidateTrack

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.track.name).lineLimit(1)
                Text(candidate.track.artistLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if candidate.origins == [.recommendation] {
                Text("Recommended")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.tint)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
            if let tempo = candidate.features?.tempo {
                Text("\(Int(tempo.rounded())) BPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension PlaylistService.Progress {
    var text: String {
        switch self {
        case .readingHistory: return "Reading your listening history…"
        case .analyzingTracks(let done, let total): return "Analyzing tempo and mood (\(done)/\(total))…"
        case .findingMoreTracks: return "Finding more matching tracks…"
        case .choosingTracks: return "Choosing tracks…"
        }
    }
}
