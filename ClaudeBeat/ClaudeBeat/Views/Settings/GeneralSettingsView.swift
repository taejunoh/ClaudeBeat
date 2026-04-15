import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("pollingInterval") var pollingInterval: Double = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Polling")
                .font(.headline)

            HStack {
                Text("Refresh every")
                Slider(value: $pollingInterval, in: 15...300, step: 15)
                Text("\(Int(pollingInterval))s")
                    .monospacedDigit()
                    .frame(width: 35)
            }

            Divider()

            Text("System")
                .font(.headline)

            Toggle("Launch at login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Launch at login error: \(error)")
                    }
                }
            ))

            Divider()

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
