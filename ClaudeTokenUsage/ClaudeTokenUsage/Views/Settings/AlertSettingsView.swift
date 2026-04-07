import SwiftUI

struct AlertSettingsView: View {
    @Bindable var notificationManager: NotificationManager

    var body: some View {
        Form {
            Section("Session (5h)") {
                Toggle("Enable alerts", isOn: $notificationManager.sessionAlertsEnabled)
                HStack {
                    Text("Warn at")
                    Slider(value: $notificationManager.sessionThreshold, in: 50...100, step: 5)
                    Text("\(Int(notificationManager.sessionThreshold))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .disabled(!notificationManager.sessionAlertsEnabled)
            }

            Section("Weekly (7d)") {
                Toggle("Enable alerts", isOn: $notificationManager.weeklyAlertsEnabled)
                HStack {
                    Text("Warn at")
                    Slider(value: $notificationManager.weeklyThreshold, in: 50...100, step: 5)
                    Text("\(Int(notificationManager.weeklyThreshold))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .disabled(!notificationManager.weeklyAlertsEnabled)
            }

            Section("Extra Usage") {
                Toggle("Enable alerts", isOn: $notificationManager.extraUsageAlertsEnabled)
                HStack {
                    Text("Warn at $")
                    TextField("Amount", value: $notificationManager.extraUsageThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                .disabled(!notificationManager.extraUsageAlertsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
