import Foundation

@MainActor
@Observable
final class UsageService {
    private let transport: UsageTransport
    private let usageState: UsageState
    private let notificationManager: NotificationManager?
    private var pollingTask: Task<Void, Never>?

    var pollingInterval: TimeInterval = 60
    private var organizationId: String = ""

    init(transport: UsageTransport, usageState: UsageState, notificationManager: NotificationManager? = nil) {
        self.transport = transport
        self.usageState = usageState
        self.notificationManager = notificationManager
    }

    func fetchUsage() async {
        do {
            if organizationId.isEmpty {
                try await resolveOrganizationId()
            }
            let data = try await transport.fetchJSON(path: "/api/organizations/\(organizationId)/usage")
            let response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: data)
            usageState.update(with: response)
            notificationManager?.checkAndNotify(response: response)
        } catch {
            handle(error)
        }
    }

    private func resolveOrganizationId() async throws {
        let data = try await transport.fetchJSON(path: "/api/organizations")
        let orgs = try JSONDecoder.makeAPIDecoder().decode([Organization].self, from: data)
        guard let first = orgs.first else { throw TransportError.decode }
        organizationId = first.uuid
    }

    private func handle(_ error: Error) {
        switch error {
        case TransportError.needsLogin:
            organizationId = ""
            usageState.setNeedsLogin()
        case TransportError.challenge:
            usageState.setError("Connecting…")
        case TransportError.network(let code):
            usageState.setError("HTTP \(code)")
        case TransportError.decode:
            usageState.setError("Bad response")
        case TransportError.webView(let message):
            usageState.setError(message)
        default:
            usageState.setError(error.localizedDescription)
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { @MainActor [weak self] in
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
