import Foundation

@Observable
final class UsageService {
    private let authManager: AuthManager
    private let usageState: UsageState
    private let notificationManager: NotificationManager?
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: TimeInterval = 60

    init(authManager: AuthManager, usageState: UsageState, notificationManager: NotificationManager? = nil) {
        self.authManager = authManager
        self.usageState = usageState
        self.notificationManager = notificationManager
    }

    func fetchUsage() async {
        NSLog("[UsageService] fetchUsage called. isConfigured=\(authManager.isConfigured) orgId=\(authManager.organizationId)")
        guard authManager.isConfigured, !authManager.organizationId.isEmpty else {
            usageState.setError("Not authenticated")
            NSLog("[UsageService] Not authenticated, skipping")
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(authManager.organizationId)/usage"
        guard let url = URL(string: urlString) else {
            usageState.setError("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in authManager.buildHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                usageState.setError("HTTP \(code)")
                return
            }

            NSLog("[UsageService] HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) body: \(String(data: data.prefix(200), encoding: .utf8) ?? "nil")")
            let usageResponse = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
            NSLog("[UsageService] Decoded! 5h=\(usageResponse.fiveHour.utilization)%")
            usageState.update(with: usageResponse)
            NSLog("[UsageService] Calling checkAndNotify, notificationManager is \(notificationManager == nil ? "nil" : "set")")
            notificationManager?.checkAndNotify(response: usageResponse)
        } catch {
            usageState.setError(error.localizedDescription)
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchUsage()
                try? await Task.sleep(for: .seconds(pollingInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
