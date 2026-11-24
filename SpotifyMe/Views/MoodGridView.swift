import SpotifyMeCore
import SwiftUI

struct MoodGridView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAbout = false

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: mood) {
                            MoodTile(mood: mood)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Pick a mood")
            .navigationDestination(for: Mood.self) { mood in
                PlaylistPreviewView(mood: mood)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About")
                }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }
}

struct MoodTile: View {
    let mood: Mood

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: mood.symbol)
                .font(.title)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(mood.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(mood.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(mood.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
