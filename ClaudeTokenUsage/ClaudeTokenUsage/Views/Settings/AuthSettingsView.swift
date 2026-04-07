import AppKit
import SwiftUI

struct AuthSettingsView: View {
    @Bindable var authManager: AuthManager

    var body: some View {
        Form {
            Picker("Auth Method", selection: $authManager.authMethod) {
                ForEach(AuthMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }

            switch authManager.authMethod {
            case .oauth:
                HStack {
                    Text("OAuth Token")
                    Spacer()
                    if authManager.oauthToken.isEmpty {
                        Text("Not found in Keychain")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Found")
                            .foregroundStyle(.green)
                    }
                }

                Button("Load from Keychain") {
                    authManager.loadOAuthTokenFromKeychain()
                }

            case .sessionCookie:
                HStack {
                    SecureField("Session Key", text: $authManager.sessionCookie)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            authManager.sessionCookie = string.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                Text("Paste sessionKey from a.claude.ai browser cookies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                connectionStatusView
                Spacer()
                Button("Test Connection") {
                    Task {
                        try? await authManager.fetchOrganizationId()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch authManager.connectionStatus {
        case .unknown:
            Label("Not tested", systemImage: "circle")
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
