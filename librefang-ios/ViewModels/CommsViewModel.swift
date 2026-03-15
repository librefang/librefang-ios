import Foundation

@Observable
final class CommsViewModel {
    var topology: CommsTopology?
    var events: [CommsEvent] = []
    var isLoading = false
    var isStreaming = false
    var error: String?
    var lastRefresh: Date?

    private let api: APIClientProtocol
    private let streamClient = CommsEventStreamClient()
    private var refreshTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    init(api: APIClientProtocol) {
        self.api = api
    }

    func startAutoRefresh(interval: TimeInterval = 20) {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            await self?.refresh()
            await self?.startStream()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }

                if self?.isStreaming == true {
                    await self?.refreshTopology()
                } else {
                    await self?.refresh()
                    await self?.startStream()
                }
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    @MainActor
    func refresh() async {
        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await self.refreshTopology()
            }
            group.addTask { @MainActor in
                do {
                    self.events = try await self.api.commsEvents(limit: 120)
                } catch {
                    self.error = self.error ?? error.localizedDescription
                }
            }
        }

        lastRefresh = Date()
        isLoading = false
    }

    @MainActor
    private func refreshTopology() async {
        do {
            self.topology = try await self.api.commsTopology()
        } catch {
            /* Topology can stay stale while the live event stream remains available. */
        }
    }

    @MainActor
    private func startStream() async {
        guard streamTask == nil else { return }

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                let connectionInfo = try await self.api.connectionInfo()
                let stream = await self.streamClient.stream(connectionInfo: connectionInfo)

                for try await event in stream {
                    await MainActor.run {
                        self.isStreaming = true
                        self.ingest(event)
                        self.error = nil
                        self.lastRefresh = Date()
                    }
                }

                await MainActor.run {
                    self.isStreaming = false
                    self.streamTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isStreaming = false
                    self.streamTask = nil
                }
            } catch {
                await MainActor.run {
                    self.isStreaming = false
                    self.streamTask = nil
                    if self.events.isEmpty {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    @MainActor
    private func ingest(_ event: CommsEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
            events.sort { $0.timestamp > $1.timestamp }
            if events.count > 150 {
                events = Array(events.prefix(150))
            }
        }
    }

    var nodeCount: Int { topology?.nodes.count ?? 0 }
    var edgeCount: Int { topology?.edges.count ?? 0 }
    var taskEventCount: Int {
        events.filter {
            $0.kind == .taskPosted || $0.kind == .taskClaimed || $0.kind == .taskCompleted
        }.count
    }
    var spawnEventCount: Int {
        events.filter { $0.kind == .agentSpawned || $0.kind == .agentTerminated }.count
    }
}
