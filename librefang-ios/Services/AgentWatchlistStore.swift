import Foundation

@MainActor
@Observable
final class AgentWatchlistStore {
    private enum StorageKey {
        static let watchedAgentIDs = "agent.watchlist.ids"
    }

    private let defaults: UserDefaults
    private(set) var watchedAgentIDs: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.watchedAgentIDs = defaults.stringArray(forKey: StorageKey.watchedAgentIDs) ?? []
    }

    func isWatched(_ agent: Agent) -> Bool {
        watchedAgentIDs.contains(agent.id)
    }

    func toggle(_ agent: Agent) {
        if isWatched(agent) {
            watchedAgentIDs.removeAll { $0 == agent.id }
        } else {
            watchedAgentIDs.insert(agent.id, at: 0)
        }
        persist()
    }

    func removeMissingAgents(validIDs: Set<String>) {
        let filtered = watchedAgentIDs.filter { validIDs.contains($0) }
        guard filtered != watchedAgentIDs else { return }
        watchedAgentIDs = filtered
        persist()
    }

    func watchedAgents(from agents: [Agent]) -> [Agent] {
        let agentMap = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return watchedAgentIDs.compactMap { agentMap[$0] }
    }

    private func persist() {
        defaults.set(watchedAgentIDs, forKey: StorageKey.watchedAgentIDs)
    }
}
