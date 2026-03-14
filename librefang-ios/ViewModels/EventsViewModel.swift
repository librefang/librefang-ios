import Foundation

@Observable
final class EventsViewModel {
    var entries: [AuditEntry] = []
    var auditVerify: AuditVerifyStatus?
    var tipHash: String?
    var isLoading = false
    var error: String?
    var lastRefresh: Date?

    private let api: APIClientProtocol
    private var refreshTask: Task<Void, Never>?

    init(api: APIClientProtocol) {
        self.api = api
    }

    func startAutoRefresh(interval: TimeInterval = 20) {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    func refresh() async {
        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do {
                    let audit = try await self.api.recentAudit(limit: 80)
                    self.entries = audit.entries.sorted { $0.seq > $1.seq }
                    self.tipHash = audit.tipHash
                } catch {
                    self.error = self.error ?? error.localizedDescription
                }
            }
            group.addTask { @MainActor in
                do {
                    self.auditVerify = try await self.api.auditVerify()
                } catch {
                    /* Verification is optional in the detailed feed */
                }
            }
        }

        lastRefresh = Date()
        isLoading = false
    }

    var criticalCount: Int {
        entries.filter { $0.severity == .critical }.count
    }

    var warningCount: Int {
        entries.filter { $0.severity == .warning }.count
    }

    var infoCount: Int {
        entries.filter { $0.severity == .info }.count
    }
}
