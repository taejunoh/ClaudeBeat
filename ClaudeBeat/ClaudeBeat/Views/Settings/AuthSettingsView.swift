import AppKit
import SwiftUI

struct AuthSettingsView: View {
    @Bindable var authManager: AuthManager
    var usageState: UsageState
    var onLogin: () -> Void = {}
    var onLogout: () async -> Void = {}
    var onSaveKey: (String) async -> Void = { _ in }

    @State private var sessionKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusView
                Spacer()
                // Show only the action that applies: log out when connected, log in otherwise.
                if isConnected {
                    Button("Log out") { Task { await onLogout() } }
                } else {
                    Button("Log in to Claude", action: onLogin)
                }
            }

            Divider()

            Text("Session key (Google sign-in fallback)")
                .font(.headline)
            HStack {
                SecureField("Session Key", text: $sessionKey)
                    .textFieldStyle(.roundedBorder)
                Button("Paste") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        sessionKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                Button("Save") { Task { await onSaveKey(sessionKey) } }
                    .disabled(sessionKey.isEmpty)
            }
            Text("Only needed if you sign in to Claude with Google. Paste sessionKey from a.claude.ai browser cookies, then Save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { sessionKey = authManager.sessionCookie }
    }

    /// Logged in with data flowing.
    private var isConnected: Bool {
        !usageState.needsLogin && usageState.response != nil
    }

    @ViewBuilder
    private var statusView: some View {
        if usageState.needsLogin {
            Label("Login required", systemImage: "circle.fill")
                .foregroundStyle(.red)
        } else if usageState.response != nil {
            Label("Connected", systemImage: "circle.fill")
                .foregroundStyle(.green)
        } else if usageState.isError {
            Label(usageState.errorMessage ?? "Error", systemImage: "circle.fill")
                .foregroundStyle(.orange)
        } else {
            Label("Connecting…", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}
