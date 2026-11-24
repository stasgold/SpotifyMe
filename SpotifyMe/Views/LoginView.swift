import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.green)
            Text("SpotifyMe")
                .font(.largeTitle.bold())
            Text("Playlists for every mood, built from your own listening history and saved to Spotify.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text("Connect Spotify").bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let url = await model.auth.authorizationURL()
            let callback = try await webAuthenticationSession.authenticate(
                using: url,
                callbackURLScheme: AppConfig.redirectScheme,
                preferredBrowserSession: .shared
            )
            await model.signIn(callbackURL: callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User closed the sheet; nothing to report.
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
