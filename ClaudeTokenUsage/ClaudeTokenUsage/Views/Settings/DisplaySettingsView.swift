import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage("showResetTime") var showResetTime = true
    @AppStorage("showSessionLabel") var showSessionLabel = true

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show reset time", isOn: $showResetTime)
                Toggle("Show \"Session:\" label", isOn: $showSessionLabel)
            }
        }
        .formStyle(.grouped)
    }
}
