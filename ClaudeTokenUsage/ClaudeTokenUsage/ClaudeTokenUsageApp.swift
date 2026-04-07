import SwiftUI

@main
struct ClaudeTokenUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Claude Usage", systemImage: "circle.fill") {
            Text("Claude Token Usage")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
