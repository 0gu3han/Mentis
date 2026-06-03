import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Base environment
            Color.mSurface.ignoresSafeArea()

            // Radial glow behind the form — "illuminated by attention"
            RadialGradient(
                colors: [Color.mSecondary.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 48) {
                Spacer()

                // Display headline
                VStack(spacing: 10) {
                    Text("MENTIS")
                        .font(.mDisplay(52))
                        .foregroundStyle(Color.mOnSurface)
                        .tracking(-1)
                    Text("Your spatial memory palace")
                        .font(.mLabel(13))
                        .tracking(0.6)
                        .foregroundStyle(Color.mSecondary)
                        .textCase(.uppercase)
                }

                // Form — Pedestal card
                VStack(spacing: 20) {
                    // Email — Sink field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EMAIL")
                            .font(.mLabel())
                            .tracking(0.8)
                            .foregroundStyle(Color.mSecondary)
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .textContentType(.emailAddress)
                            .sinkStyle()
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.mLabel())
                            .foregroundStyle(Color(hex: "#ff6b8a"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    MentisPrimaryButton(title: "Continue", isLoading: isLoading) {
                        Task { await login() }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .opacity(email.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(24)
                .background(Color.mSurfaceContainerHigh,
                             in: RoundedRectangle(cornerRadius: 20))
                .ambientShadow()
                .padding(.horizontal, 24)

                Spacer()
            }

            // Settings gear — top right
            VStack {
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.mSecondary)
                            .padding(20)
                    }
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            ServerSettingsSheet()
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        do {
            let resp = try await APIClient.shared.login(email: email)
            appState.login(userId: resp.user_id, email: resp.email)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Server Settings Sheet

private struct ServerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url: String = APIClient.shared.baseURL

    var body: some View {
        ZStack {
            Color.mSurface.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("Server Settings")
                    .font(.mTitle(22))
                    .foregroundStyle(Color.mOnSurface)

                VStack(alignment: .leading, spacing: 6) {
                    Text("SERVER URL")
                        .font(.mLabel())
                        .tracking(0.8)
                        .foregroundStyle(Color.mSecondary)
                    TextField("http://10.0.0.147:5001", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .sinkStyle()
                }

                Text("Use your Mac's LAN IP when running on a real device. Find it with: ipconfig getifaddr en0")
                    .font(.mLabel(12))
                    .foregroundStyle(Color.mSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                MentisPrimaryButton(title: "Save", isLoading: false) {
                    APIClient.shared.baseURL = url
                    dismiss()
                }

                Spacer()
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
