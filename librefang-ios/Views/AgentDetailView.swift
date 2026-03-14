import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @Environment(\.dependencies) private var deps
    @State private var budgetDetail: AgentBudgetDetail?
    @State private var sessionSnapshot: AgentSessionSnapshot?
    @State private var agentSessions: [SessionInfo] = []
    @State private var showChat = false
    @State private var isLoadingBudget = true
    @State private var isLoadingSession = true
    @State private var isLoadingSessions = true

    private var agentApprovals: [ApprovalItem] {
        deps.dashboardViewModel.approvals.filter { $0.agentId == agent.id || $0.agentName == agent.name }
    }

    private var agentRecentEvents: [AuditEntry] {
        deps.dashboardViewModel.recentAudit
            .filter { $0.agentId == agent.id }
            .sorted { $0.seq > $1.seq }
    }

    private var sessionItems: [SessionAttentionItem] {
        agentSessions.map { deps.dashboardViewModel.sessionAttentionItem(for: $0) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.session.messageCount > rhs.session.messageCount
            }
    }

    private var isWatched: Bool {
        deps.agentWatchlistStore.isWatched(agent)
    }

    var body: some View {
        List {
            // Identity
            Section {
                HStack(spacing: 16) {
                    Text(agent.identity?.emoji ?? "🤖")
                        .font(.system(size: 48))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.title2.weight(.bold))
                        if isWatched {
                            Label("Pinned on this iPhone", systemImage: "star.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.yellow)
                        }
                        Text(agent.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(Color.clear)
            }

            // Status
            Section("Status") {
                DetailRow(icon: "power", label: "State", value: agent.state, valueColor: stateColor)
                DetailRow(icon: "gearshape.2", label: "Mode", value: agent.mode)
                DetailRow(icon: "checkmark.circle", label: "Ready", value: agent.ready ? "Yes" : "No",
                          valueColor: agent.ready ? .green : .orange)
                if let provider = agent.modelProvider {
                    DetailRow(icon: "cloud", label: "Provider", value: provider)
                }
                if let model = agent.modelName {
                    DetailRow(icon: "cpu", label: "Model", value: model)
                }
                if let tier = agent.modelTier {
                    DetailRow(icon: "star", label: "Tier", value: tier)
                }
                if let auth = agent.authStatus {
                    DetailRow(icon: "lock", label: "Auth", value: auth,
                              valueColor: auth == "configured" ? .green : .red)
                }
                if let profile = agent.profile {
                    DetailRow(icon: "person", label: "Profile", value: profile)
                }
            }

            if !agentApprovals.isEmpty {
                Section("Approvals") {
                    ForEach(agentApprovals) { approval in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(approval.actionSummary)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(approval.riskLevel.capitalized)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                            Text(approval.toolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !approval.description.isEmpty {
                                Text(approval.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Budget
            if isLoadingBudget {
                Section("Cost") {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }
            } else if let detail = budgetDetail {
                Section("Cost (USD)") {
                    BudgetPeriodRow(label: "Hourly", period: detail.hourly)
                    BudgetPeriodRow(label: "Daily", period: detail.daily)
                    BudgetPeriodRow(label: "Monthly", period: detail.monthly)
                }

                Section("Token Usage") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(detail.tokens.used.formatted()) / \(detail.tokens.limit.formatted())")
                                .font(.subheadline.monospacedDigit())
                            Text("\(Int(detail.tokens.pct * 100))% used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Gauge(value: min(detail.tokens.pct, 1.0)) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(progressColor(detail.tokens.pct))
                        .scaleEffect(0.7)
                    }
                }
            }

            // Session
            if isLoadingSession {
                Section("Session") {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }
            } else if let snapshot = sessionSnapshot {
                Section("Session") {
                    LabeledContent("Label") {
                        Text((snapshot.label?.isEmpty == false ? snapshot.label : nil) ?? "Current")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Messages") {
                        Text(snapshot.messageCount.formatted())
                            .monospacedDigit()
                    }
                    LabeledContent("Context Tokens") {
                        Text(snapshot.contextWindowTokens.formatted())
                            .monospacedDigit()
                    }
                }

                if isLoadingSessions {
                    Section("Session Inventory") {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                    }
                } else if !sessionItems.isEmpty {
                    Section {
                        LabeledContent("Total Sessions") {
                            Text("\(sessionItems.count)")
                                .monospacedDigit()
                        }
                        LabeledContent("Attention") {
                            Text("\(sessionItems.filter { $0.severity > 0 }.count)")
                                .foregroundStyle(sessionItems.contains { $0.severity > 0 } ? .orange : .secondary)
                        }

                        ForEach(sessionItems.prefix(4)) { item in
                            AgentSessionInventoryRow(item: item)
                        }

                        NavigationLink {
                            SessionsView(initialSearchText: agent.id, initialFilter: .all)
                        } label: {
                            Label("Open Session Monitor", systemImage: "rectangle.stack")
                        }
                    } header: {
                        Text("Session Inventory")
                    } footer: {
                        if sessionItems.count > 4 {
                            Text("Showing 4 of \(sessionItems.count) sessions for this agent")
                        }
                    }
                }

                Section("Recent Activity") {
                    if snapshot.messages.isEmpty {
                        Text("No conversation recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(snapshot.messages.suffix(3).enumerated()), id: \.offset) { _, message in
                            SessionPreviewRow(message: message)
                        }
                    }
                }
            }

            if !agentRecentEvents.isEmpty {
                Section {
                    ForEach(agentRecentEvents.prefix(3)) { entry in
                        AgentAuditRow(entry: entry)
                    }

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialSearchText: agent.id)
                    } label: {
                        Label("Open Full Event Feed", systemImage: "list.bullet.rectangle.portrait")
                    }
                } header: {
                    Text("Recent Audit")
                } footer: {
                    Text("Showing recent audit events already loaded on the dashboard for this agent.")
                }
            }

            // Actions
            Section("Actions") {
                Button {
                    deps.agentWatchlistStore.toggle(agent)
                } label: {
                    Label(isWatched ? "Remove From Watchlist" : "Add To Watchlist", systemImage: isWatched ? "star.slash" : "star")
                }

                NavigationLink {
                    EventsView(api: deps.apiClient, initialSearchText: agent.id)
                } label: {
                    Label("Inspect Audit Events", systemImage: "list.bullet.rectangle.portrait")
                }

                NavigationLink {
                    SessionsView(initialSearchText: agent.id, initialFilter: .all)
                } label: {
                    Label("Inspect Agent Sessions", systemImage: "rectangle.stack")
                }

                if agent.isRunning {
                    Button {
                        showChat = true
                    } label: {
                        Label("Open Conversation", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                }

                Button {
                    UIPasteboard.general.string = agent.id
                } label: {
                    Label("Copy Agent ID", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    deps.agentWatchlistStore.toggle(agent)
                } label: {
                    Image(systemName: isWatched ? "star.fill" : "star")
                        .foregroundStyle(isWatched ? .yellow : .primary)
                }
            }
        }
        .task {
            await loadBudget()
            await loadSession()
            await loadSessions()
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: deps.makeChatViewModel(for: agent))
            }
        }
    }

    private var stateColor: Color {
        switch agent.state {
        case "Running": .green
        case "Suspended": .yellow
        case "Terminated": .red
        default: .gray
        }
    }

    private func progressColor(_ pct: Double) -> Color {
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return .green
    }

    @MainActor
    private func loadBudget() async {
        defer { isLoadingBudget = false }
        do {
            budgetDetail = try await deps.apiClient.budgetAgent(id: agent.id)
        } catch {
            // Budget is optional
        }
    }

    @MainActor
    private func loadSession() async {
        defer { isLoadingSession = false }
        do {
            sessionSnapshot = try await deps.apiClient.session(agentId: agent.id)
        } catch {
            // Session visibility is optional
        }
    }

    @MainActor
    private func loadSessions() async {
        defer { isLoadingSessions = false }
        do {
            agentSessions = (try await deps.apiClient.agentSessions(agentId: agent.id)).sessions
        } catch {
            /* Multi-session inventory is optional */
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(valueColor)
        } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
            }
        }
    }
}

// MARK: - Budget Period Row

private struct BudgetPeriodRow: View {
    let label: LocalizedStringKey
    let period: BudgetPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("$\(period.spend, specifier: "%.4f")")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Text("/ $\(period.limit, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(period.pct, 1.0))
                .tint(period.pct > 0.9 ? .red : period.pct > 0.7 ? .orange : .green)
        }
        .padding(.vertical, 2)
    }
}

private struct SessionPreviewRow: View {
    let message: AgentSessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleColor)
                Spacer()
                if let toolCount = message.tools?.count, toolCount > 0 {
                    Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(displayText)
                .font(.subheadline)
                .lineLimit(4)

            if let imageCount = message.images?.count, imageCount > 0 {
                Text("\(imageCount) image attachment\(imageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var roleTitle: String {
        switch message.role {
        case "User":
            "User"
        case "System":
            "System"
        default:
            "Agent"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case "User":
            .blue
        case "System":
            .orange
        default:
            .green
        }
    }

    private var displayText: String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let tools = message.tools, !tools.isEmpty {
            return tools.map(\.name).joined(separator: ", ")
        }
        if let images = message.images, !images.isEmpty {
            return "\(images.count) image attachment\(images.count == 1 ? "" : "s")"
        }
        return "No message content"
    }
}

private struct AgentSessionInventoryRow: View {
    let item: SessionAttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(item.session.messageCount) msgs")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(item.session.messageCount >= 40 ? .orange : .secondary)
            }

            HStack(spacing: 8) {
                if item.reasons.isEmpty {
                    Text("No unusual session pressure")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(item.reasons.prefix(2), id: \.self) { reason in
                        Text(reason)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(signalColor.opacity(0.12))
                            .foregroundStyle(signalColor)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(relativeCreatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let label = (item.session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? String(item.session.sessionId.prefix(8)) : label
    }

    private var relativeCreatedAt: String {
        guard let date = item.session.createdAt.agentSessionISO8601Date else { return item.session.createdAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var signalColor: Color {
        if item.severity >= 6 { return .red }
        if item.severity > 0 { return .orange }
        return .secondary
    }
}

private struct AgentAuditRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.friendlyAction)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.outcome.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(outcomeColor)
        }
        .padding(.vertical, 2)
    }

    private var relativeTimestamp: String {
        guard let date = entry.timestamp.agentSessionISO8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var outcomeColor: Color {
        switch entry.severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .info:
            .green
        }
    }
}

private extension String {
    var agentSessionISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}
