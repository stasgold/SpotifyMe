import SwiftUI
import UIKit

/// Lets each person enter their own Spotify Client ID (and optional GetSongBPM key) on the device.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    var onDone: (() -> Void)?

    @State private var clientID = AppConfig.spotifyClientID
    @State private var bpmKey = AppConfig.getSongBPMAPIKey
    @State private var copied = false
    @State private var isSaving = false

    private var trimmedID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { AppConfig.isValidClientID(trimmedID) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each person uses their own free Spotify developer app.")
                    Text("1. Open the Spotify Developer Dashboard and create an app.")
                    Text("2. Add this Redirect URI and tick **Web API**:")
                    Button {
                        UIPasteboard.general.string = AppConfig.redirectURI
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : AppConfig.redirectURI,
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.body.monospaced())
                    }
                    Text("3. Under **User Management**, add your Spotify account's email.")
                    Text("4. Copy the app's **Client ID** and paste it below.")
                }
                .font(.subheadline)
                Link(destination: AppConfig.dashboardURL) {
                    Label("Open Spotify Developer Dashboard", systemImage: "safari")
                }
            } header: {
                Text("Set up Spotify")
            }

            Section {
                TextField("32-character Client ID", text: $clientID)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !trimmedID.isEmpty && !isValid {
                    Text("A Client ID is 32 letters and digits (0–9, a–f).")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Spotify Client ID")
            } footer: {
                Text("No client secret is needed. It's stored only on this iPhone.")
            }

            Section {
                TextField("Optional", text: $bpmKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link("Get a free key at getsongbpm.com", destination: URL(string: "https://getsongbpm.com/api")!)
            } header: {
                Text("GetSongBPM API key")
            } footer: {
                Text("Improves BPM matching for the running moods.")
            }

            Section {
                Button {
                    Task {
                        isSaving = true
                        await model.configure(clientID: trimmedID, getSongBPMAPIKey: bpmKey)
                        isSaving = false
                        onDone?()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Save").bold() }
                        Spacer()
                    }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .navigationTitle("Welcome")
    }
}
