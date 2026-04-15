import SwiftUI

enum MenuBarDisplay: String, CaseIterable {
    case session = "Current Session (5h)"
    case weekly = "Weekly Limit (7d)"
    case both = "Both"
}

struct DisplaySettingsView: View {
    @AppStorage("menuBarDisplay") var menuBarDisplay: String = MenuBarDisplay.session.rawValue
    @AppStorage("showResetTime") var showResetTime = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menu Bar Display")
                .font(.headline)

            Picker("Show", selection: $menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases, id: \.rawValue) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Toggle("Show reset time", isOn: $showResetTime)
        }
        .padding()
    }
}
