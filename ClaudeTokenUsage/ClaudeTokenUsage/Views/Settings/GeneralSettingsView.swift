import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("pollingInterval") var pollingInterval: Double = 60

    var body: some View {
        Form {
            Section("Polling") {
                HStack {
                    Text("Refresh every")
                    Slider(value: $pollingInterval, in: 15...300, step: 15)
                    Text("\(Int(pollingInterval))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Section("System") {
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
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            }
        }
        .formStyle(.grouped)
    }
}
