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
        guard authManager.isConfigured, !authManager.organizationId.isEmpty else {
            await MainActor.run { usageState.setError("Not authenticated") }
            return
        }

        let urlString = "https://claude.ai/api/organizations/\(authManager.organizationId)/usage"
        guard let url = URL(string: urlString) else {
            await MainActor.run { usageState.setError("Invalid URL") }
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
                await MainActor.run { usageState.setError("HTTP \(code)") }
                return
            }

            let decoder = JSONDecoder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                if let date = formatter.date(from: dateString) { return date }
                if let date = fallbackFormatter.date(from: dateString) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }

            let usageResponse = try decoder.decode(UsageResponse.self, from: data)
            await MainActor.run {
                usageState.update(with: usageResponse)
                notificationManager?.checkAndNotify(response: usageResponse)
            }
        } catch {
            await MainActor.run { usageState.setError(error.localizedDescription) }
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchUsage()
                guard let interval = self?.pollingInterval else { break }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
