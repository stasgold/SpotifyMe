import SpotifyMeCore
import SwiftUI

/// Create or edit a custom mood, setting every selection rule.
struct MoodEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var mood: CustomMood
    private let isNew: Bool
    private let onSave: () -> Void
    @State private var confirmDelete = false

    static let symbols = [
        "music.note", "headphones", "figure.run", "figure.walk", "bicycle", "dumbbell.fill",
        "moon.stars.fill", "sun.max.fill", "bolt.fill", "heart.fill", "flame.fill", "leaf.fill",
        "cup.and.saucer.fill", "car.fill", "book.fill", "party.popper.fill", "sparkles", "cloud.rain.fill"
    ]

    init(mood: CustomMood = CustomMood(), isNew: Bool, onSave: @escaping () -> Void = {}) {
        _mood = State(initialValue: mood)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                tempoSection
                Section {
                    PercentRangeRow(title: "Energy", detail: "Calm → intense", range: $mood.energy)
                    PercentRangeRow(title: "Positivity", detail: "Sad, dark → happy, cheerful", range: $mood.valence)
                    PercentRangeRow(title: "Danceability", detail: "Free-flowing → steady, danceable beat", range: $mood.danceability)
                    PercentRangeRow(title: "Acousticness", detail: "Electronic → acoustic", range: $mood.acousticness)
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Turn a filter on to require it. Tracks closest to the middle of each range rank highest. Tracks missing data for an active filter are skipped.")
                }
                sourcesSection
                playlistSection
                if !isNew {
                    Section {
                        Button("Delete mood", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Mood" : "Edit Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveCustomMood(mood)
                        onSave()
                        dismiss()
                    }
                    .disabled(mood.sources.isEmpty)
                }
            }
            .confirmationDialog("Delete \"\(mood.displayName)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.deleteCustomMood(mood)
                    dismiss()
                }
            } message: {
                Text("The playlist already saved in Spotify is kept.")
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section("Name and look") {
            TextField("Mood name", text: $mood.name)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            mood.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(mood.symbol == symbol ? .white : .primary)
                                .background(mood.symbol == symbol ? AnyShapeStyle(MoodPalette.gradient(mood.colorIndex)) : AnyShapeStyle(.quaternary),
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack(spacing: 10) {
                ForEach(MoodPalette.colors.indices, id: \.self) { index in
                    Button {
                        mood.colorIndex = index
                    } label: {
                        Circle()
                            .fill(MoodPalette.gradient(index))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if mood.colorIndex == index {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(index + 1)")
                }
            }
        }
    }

    private var tempoSection: some View {
        Section {
            Toggle("Filter by tempo", isOn: $mood.tempo.isEnabled)
            if mood.tempo.isEnabled {
                Stepper("Min: \(Int(mood.tempo.min)) BPM", value: $mood.tempo.min, in: 40...220, step: 1)
                    .onChange(of: mood.tempo.min) { _, new in if mood.tempo.max < new { mood.tempo.max = new } }
                Stepper("Max: \(Int(mood.tempo.max)) BPM", value: $mood.tempo.max, in: 40...220, step: 1)
                    .onChange(of: mood.tempo.max) { _, new in if mood.tempo.min > new { mood.tempo.min = new } }
                Toggle("Count half-time tempo", isOn: $mood.countHalfTime)
            }
        } header: {
            Text("Tempo")
        } footer: {
            if mood.tempo.isEnabled {
                Text(mood.countHalfTime
                     ? "A track at half the tempo also matches (e.g. 90 BPM for 180), which suits running cadence."
                     : "Only tracks whose BPM is inside this range are used.")
            }
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(CustomMood.Source.allCases, id: \.self) { source in
                Toggle(source.title, isOn: Binding(
                    get: { mood.sources.contains(source) },
                    set: { on in
                        if on { mood.sources.insert(source) } else { mood.sources.remove(source) }
                    }
                ))
            }
        } header: {
            Text("Pick tracks from")
        } footer: {
            if mood.sources.isEmpty { Text("Choose at least one source.").foregroundStyle(.red) }
        }
    }

    private var playlistSection: some View {
        Section {
            Stepper("Tracks: \(mood.targetCount)", value: $mood.targetCount, in: 5...100, step: 5)
            Stepper("Max per artist: \(mood.maxPerArtist)", value: $mood.maxPerArtist, in: 1...10)
            Picker("Order", selection: $mood.order) {
                ForEach(CustomMood.Order.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if mood.order == .bestMatchFirst || mood.order == .shuffled {
                Toggle("Avoid same artist back to back", isOn: $mood.spreadArtists)
            }
            Toggle("Fill up with recommendations", isOn: $mood.addRecommendationsWhenShort)
        } header: {
            Text("Playlist")
        } footer: {
            if mood.addRecommendationsWhenShort {
                Text("If your own tracks don't reach \(mood.targetCount), recommended tracks closest to this mood fill the rest, even if they miss some filters.")
            }
        }
    }
}

/// A 0–100% range filter with an on/off switch.
private struct PercentRangeRow: View {
    let title: String
    let detail: String
    @Binding var range: CustomMood.Range

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $range.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(range.isEnabled ? "\(Int(range.min * 100))% – \(Int(range.max * 100))%" : detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if range.isEnabled {
                slider("Min", value: $range.min)
                    .onChange(of: range.min) { _, new in if range.max < new { range.max = new } }
                slider("Max", value: $range.max)
                    .onChange(of: range.max) { _, new in if range.min > new { range.min = new } }
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.05)
                .accessibilityLabel("\(title) \(label.lowercased())")
        }
    }
}

/// Tile colors for custom moods.
enum MoodPalette {
    static let colors: [[Color]] = [
        [.blue, .cyan], [.green, .mint], [.orange, .red], [.pink, .purple],
        [.indigo, .blue], [.yellow, .orange], [.teal, .green], [.gray, .black]
    ]

    static func gradient(_ index: Int) -> LinearGradient {
        let pair = colors[((index % colors.count) + colors.count) % colors.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
