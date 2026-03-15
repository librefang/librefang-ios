import Foundation

nonisolated struct HealthDetail: Codable, Sendable {
    let status: String
    let version: String
    let uptimeSeconds: Int
    let panicCount: Int
    let restartCount: Int
    let agentCount: Int
    let database: String
    let configWarnings: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case uptimeSeconds = "uptime_seconds"
        case panicCount = "panic_count"
        case restartCount = "restart_count"
        case agentCount = "agent_count"
        case database
        case configWarnings = "config_warnings"
    }

    var isHealthy: Bool {
        status == "ok" && database.lowercased() == "connected"
    }

    var localizedStatusLabel: String {
        StatusPresentation.localizedHealthLabel(for: status)
    }

    var statusTone: PresentationTone {
        StatusPresentation.healthTone(for: status)
    }

    var localizedDatabaseLabel: String {
        StatusPresentation.localizedConnectionLabel(for: database)
    }
}

nonisolated struct BuildVersionInfo: Codable, Sendable {
    let name: String
    let version: String
    let buildDate: String
    let gitSHA: String
    let rustVersion: String
    let platform: String
    let arch: String

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case buildDate = "build_date"
        case gitSHA = "git_sha"
        case rustVersion = "rust_version"
        case platform
        case arch
    }
}

nonisolated struct RuntimeConfigSummary: Codable, Sendable {
    let homeDir: String
    let dataDir: String
    let apiKey: String
    let defaultModel: RuntimeDefaultModel
    let memory: RuntimeMemoryConfig

    enum CodingKeys: String, CodingKey {
        case homeDir = "home_dir"
        case dataDir = "data_dir"
        case apiKey = "api_key"
        case defaultModel = "default_model"
        case memory
    }
}

nonisolated struct RuntimeDefaultModel: Codable, Sendable {
    let provider: String
    let model: String
    let apiKeyEnv: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case apiKeyEnv = "api_key_env"
    }
}

nonisolated struct RuntimeMemoryConfig: Codable, Sendable {
    let decayRate: Double

    enum CodingKeys: String, CodingKey {
        case decayRate = "decay_rate"
    }
}

nonisolated struct PrometheusMetricSample: Sendable, Hashable, Identifiable {
    let name: String
    let labels: [String: String]
    let value: Double

    var id: String {
        if labels.isEmpty {
            return name
        }
        let suffix = labels.keys.sorted().map { key in
            "\(key)=\(labels[key] ?? "")"
        }.joined(separator: ",")
        return "\(name){\(suffix)}"
    }
}

nonisolated struct PrometheusMetricsSnapshot: Sendable {
    let samples: [PrometheusMetricSample]

    static func parse(_ text: String) -> PrometheusMetricsSnapshot {
        let samples = text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> PrometheusMetricSample? in
                let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, !raw.hasPrefix("#") else { return nil }
                return parseSample(raw)
            }
        return PrometheusMetricsSnapshot(samples: samples)
    }

    private static func parseSample(_ line: String) -> PrometheusMetricSample? {
        let pieces = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2 else { return nil }
        let metric = String(pieces[0])
        let valueString = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(valueString) else { return nil }

        if let openBrace = metric.firstIndex(of: "{"),
           let closeBrace = metric.lastIndex(of: "}") {
            let name = String(metric[..<openBrace])
            let labelText = String(metric[metric.index(after: openBrace)..<closeBrace])
            return PrometheusMetricSample(name: name, labels: parseLabels(labelText), value: value)
        }

        return PrometheusMetricSample(name: metric, labels: [:], value: value)
    }

    private static func parseLabels(_ text: String) -> [String: String] {
        guard !text.isEmpty else { return [:] }
        return text
            .split(separator: ",", omittingEmptySubsequences: true)
            .reduce(into: [String: String]()) { partialResult, pair in
                let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
                guard components.count == 2 else { return }
                let key = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value.removeFirst()
                    value.removeLast()
                }
                partialResult[key] = value
            }
    }

    func firstValue(named name: String) -> Double? {
        samples.first(where: { $0.name == name && $0.labels.isEmpty })?.value
    }

    func values(named name: String) -> [PrometheusMetricSample] {
        samples.filter { $0.name == name }
    }

    var activeAgents: Int {
        Int(firstValue(named: "librefang_agents_active") ?? 0)
    }

    var totalAgents: Int {
        Int(firstValue(named: "librefang_agents_total") ?? 0)
    }

    var uptimeSeconds: Int {
        Int(firstValue(named: "librefang_uptime_seconds") ?? 0)
    }

    var panicCount: Int {
        Int(firstValue(named: "librefang_panics_total") ?? 0)
    }

    var restartCount: Int {
        Int(firstValue(named: "librefang_restarts_total") ?? 0)
    }

    var versionLabel: String? {
        values(named: "librefang_info").first?.labels["version"]
    }

    var totalRollingTokens: Int {
        Int(values(named: "librefang_tokens_total").reduce(0) { $0 + $1.value })
    }

    var totalRollingToolCalls: Int {
        Int(values(named: "librefang_tool_calls_total").reduce(0) { $0 + $1.value })
    }

    var tokenLeaders: [PrometheusMetricSample] {
        values(named: "librefang_tokens_total").sorted { $0.value > $1.value }
    }

    var toolCallLeaders: [PrometheusMetricSample] {
        values(named: "librefang_tool_calls_total").sorted { $0.value > $1.value }
    }
}
