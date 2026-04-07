import Foundation

@Observable
final class UsageService {
    private let authManager: AuthManager
    private let usageState: UsageState
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: TimeInterval = 60

    init(authManager: AuthManager, usageState: UsageState) {
        self.authManager = authManager
        self.usageState = usageState
    }

    func fetchUsage() async {
        guard authManager.isConfigured, !authManager.organizationId.isEmpty else {
            usageState.setError("Not authenticated")
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(authManager.organizationId)/usage"
        guard let url = URL(string: urlString) else {
            usageState.setError("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
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

            let usageResponse = try JSONDecoder.apiDecoder.decode(UsageResponse.self, from: data)
            usageState.update(with: usageResponse)
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
