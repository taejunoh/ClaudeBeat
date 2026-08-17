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
            Self.logRawResponse(endpoint: "usage", body: data)
            let response: UsageResponse
            do {
                response = try JSONDecoder.makeAPIDecoder().decode(UsageResponse.self, from: data)
            } catch let error as DecodingError {
                Self.logDecodeFailure(endpoint: "usage", error: error, body: data)
                throw TransportError.decode
            }
            usageState.update(with: response)
            notificationManager?.checkAndNotify(response: response)
        } catch {
            handle(error)
        }
    }

    private func resolveOrganizationId() async throws {
        let data = try await transport.fetchJSON(path: "/api/organizations")
        let orgs: [Organization]
        do {
            orgs = try JSONDecoder.makeAPIDecoder().decode(LossyArray<Organization>.self, from: data).elements
        } catch let error as DecodingError {
            Self.logDecodeFailure(endpoint: "organizations", error: error, body: data)
            throw TransportError.decode
        }
        guard let first = orgs.first else { throw TransportError.decode }
        organizationId = first.uuid
    }

    /// Writes the last raw response body to Library/Logs/last-response.log, overwriting each
    /// time so it stays bounded. The usage endpoint's shape drifts (fields appear, disappear,
    /// and go null without notice), so keeping the most recent payload on disk is what makes
    /// the next drift diagnosable without guessing at key names. The write is fire-and-forget:
    /// it is no longer guaranteed to complete before `fetchUsage()` returns, so a write
    /// scheduled just before the user quits the app can be lost.
    nonisolated private static func logRawResponse(endpoint: String, body: Data) {
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-UTF8 body>"
        let contents = """
        timestamp: \(Date())
        endpoint: \(endpoint)
        body: \(bodyString)
        """
        // UsageService is @MainActor and this runs on every poll (60s by default), so the
        // write is moved off the main actor. Both log files hold only the most recent
        // entry and are written atomically, so a race between writers is last-writer-wins.
        // The file semantic is unchanged, but the value semantic changed: with detached
        // writes, the last writer is no longer necessarily the newest response. Each entry
        // is timestamped, so a reader of the log can tell.
        Task.detached(priority: .utility) { write(contents, to: "last-response.log") }
    }

    /// Writes a diagnostic dump of a decode failure to Library/Logs/decode-failures.log
    /// inside the app's sandbox container, overwriting each time so it stays bounded.
    nonisolated private static func logDecodeFailure(endpoint: String, error: Error, body: Data) {
        let bodyString = String(data: body, encoding: .utf8) ?? "<non-UTF8 body>"
        let contents = """
        timestamp: \(Date())
        endpoint: \(endpoint)
        error: \(String(describing: error))
        body: \(bodyString)
        """
        Task.detached(priority: .utility) { write(contents, to: "decode-failures.log") }
    }

    nonisolated private static func write(_ contents: String, to fileName: String) {
        guard let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true) else { return }
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            try contents.write(
                to: logsDir.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Logging is best-effort; never let a logging failure mask the original error.
        }
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
