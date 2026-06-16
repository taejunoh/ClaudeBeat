import AppKit
import SwiftUI

struct AuthSettingsView: View {
    @Bindable var authManager: AuthManager
    var onLogin: () -> Void = {}
    var onLogout: () async -> Void = {}

    @State private var sessionKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                connectionStatusView
                Spacer()
                Button("Log in to Claude", action: onLogin)
                Button("Log out") { Task { await onLogout() } }
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
                Button("Save") {
                    authManager.sessionCookie = sessionKey
                }
                .disabled(sessionKey.isEmpty)
            }
            Text("Paste sessionKey from a.claude.ai browser cookies, then Save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch authManager.connectionStatus {
        case .unknown:
            Label("Not connected", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "circle.fill")
                .foregroundStyle(.red)
        }
    }
}
