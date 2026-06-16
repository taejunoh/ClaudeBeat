import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var authManager: AuthManager
    let onLogin: () -> Void               // opens the embedded login window
    let onPaste: (String) async -> Bool   // injects sessionKey, returns logged-in

    @State private var sessionKey: String = ""
    @State private var isConnecting: Bool = false
    @State private var showPaste: Bool = false
    @State private var pasteFailed: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("ClaudeBeat")
                    .font(.title2.bold())
                Text("Monitor your Claude usage from the menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                onLogin()
            } label: {
                Text("Log in to Claude")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button {
                showPaste.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showPaste ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Use a session key instead (Google sign-in)")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            if showPaste {
                VStack(alignment: .leading, spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        instructionStep("1", "Open claude.ai in your browser and log in")
                        instructionStep("2", "Open DevTools (⌘⌥I) → Application tab")
                        instructionStep("3", "Sidebar → Cookies → https://a.claude.ai")
                        instructionStep("4", "Find \"sessionKey\" and copy its value")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if pasteFailed {
                        Label("Couldn't connect with that key", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        connectWithPaste()
                    } label: {
                        if isConnecting {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                        } else {
                            Text("Connect").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(sessionKey.isEmpty || isConnecting)
                }
                .padding(8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
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

    private func connectWithPaste() {
        isConnecting = true
        pasteFailed = false
        Task { @MainActor in
            let ok = await onPaste(sessionKey)
            if ok { authManager.sessionCookie = sessionKey }
            isConnecting = false
            pasteFailed = !ok
        }
    }
}
