import SwiftUI

struct AlertSettingsView: View {
    @Bindable var notificationManager: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Session Reset") {
                Toggle("Notify when session resets", isOn: $notificationManager.sessionResetAlertEnabled)
                    .padding(.vertical, 4)
            }

            GroupBox("Session (5h)") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable", isOn: $notificationManager.sessionAlertsEnabled)
                    HStack {
                        Text("Warn at")
                        Slider(value: $notificationManager.sessionThreshold, in: 50...100, step: 5)
                        Text("\(Int(notificationManager.sessionThreshold))%")
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                    .disabled(!notificationManager.sessionAlertsEnabled)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Weekly (7d)") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable", isOn: $notificationManager.weeklyAlertsEnabled)
                    HStack {
                        Text("Warn at")
                        Slider(value: $notificationManager.weeklyThreshold, in: 50...100, step: 5)
                        Text("\(Int(notificationManager.weeklyThreshold))%")
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                    .disabled(!notificationManager.weeklyAlertsEnabled)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Extra Usage") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable", isOn: $notificationManager.extraUsageAlertsEnabled)
                    HStack {
                        Text("Warn at $")
                        TextField("Amount", value: $notificationManager.extraUsageThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    .disabled(!notificationManager.extraUsageAlertsEnabled)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
}
