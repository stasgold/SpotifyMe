import SpotifyMeCore
import SwiftUI

struct MoodGridView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAbout = false
    @State private var showNewMood = false
    @State private var editing: CustomMood?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: MoodChoice.builtIn(mood)) {
                            MoodTile(choice: .builtIn(mood), gradient: mood.gradient)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(model.customMoods) { custom in
                        NavigationLink(value: MoodChoice.custom(custom)) {
                            MoodTile(choice: .custom(custom), gradient: MoodPalette.gradient(custom.colorIndex))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editing = custom } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                            Button(role: .destructive) { model.deleteCustomMood(custom) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    Button { showNewMood = true } label: { NewMoodTile() }
                        .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Pick a mood")
            .navigationDestination(for: MoodChoice.self) { choice in
                PlaylistPreviewView(choice: choice)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About")
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showNewMood) {
                MoodEditorView(mood: CustomMood(colorIndex: model.customMoods.count), isNew: true)
            }
            .sheet(item: $editing) { MoodEditorView(mood: $0, isNew: false) }
        }
    }
}

struct MoodTile: View {
    let choice: MoodChoice
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: choice.symbol)
                .font(.title)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(choice.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(choice.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct NewMoodTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").font(.title)
            Text("New mood").font(.headline)
            Text("Set every parameter").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6])))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

extension Mood {
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .slowDown: colors = [.indigo, .blue]
        case .speedUp: colors = [.orange, .red]
        case .running180: colors = [.green, .teal]
        case .running170: colors = [.teal, .cyan]
        case .feelingGood: colors = [.yellow, .orange]
        case .surpriseMe: colors = [.purple, .pink]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
