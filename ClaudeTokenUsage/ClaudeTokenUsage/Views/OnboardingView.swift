import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var authManager: AuthManager
    let onComplete: () -> Void

    @State private var sessionKey: String = ""
    @State private var isConnecting: Bool = false
    @State private var showInstructions: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                Text("Claude Token Usage")
                    .font(.title2.bold())

                Text("Monitor your Claude usage from the menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Session key input
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your session key")
                    .font(.headline)

                HStack {
                    SecureField("sessionKey value", text: $sessionKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)

                    Button("Paste") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            sessionKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .disabled(isConnecting)
                }

                Button {
                    showInstructions.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showInstructions ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("How to find your session key")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if showInstructions {
                    VStack(alignment: .leading, spacing: 4) {
                        instructionStep("1", "Open claude.ai in your browser and log in")
                        instructionStep("2", "Open DevTools (⌘⌥I) → Application tab")
                        instructionStep("3", "Sidebar → Cookies → https://a.claude.ai")
                        instructionStep("4", "Find \"sessionKey\" and copy its value")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Connection status
            if case .error(let message) = authManager.connectionStatus {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Connect button
            Button {
                connect()
            } label: {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sessionKey.isEmpty || isConnecting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }

    private func instructionStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .fontWeight(.medium)
                .frame(width: 16, alignment: .trailing)
            Text(text)
        }
    }

    private func connect() {
        isConnecting = true
        authManager.authMethod = .sessionCookie
        authManager.sessionCookie = sessionKey

        Task { @MainActor in
            do {
                try await authManager.fetchOrganizationId()
                if case .connected = authManager.connectionStatus {
                    onComplete()
                }
            } catch {
                print("Connection error: \(error)")
            }
            isConnecting = false
        }
    }
}
