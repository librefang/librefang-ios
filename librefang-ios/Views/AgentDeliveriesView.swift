import SwiftUI

struct AgentDeliveriesView: View {
    let agent: Agent
    let initialReceipts: [DeliveryReceipt]

    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var scope: DeliveryScope
    @State private var receipts: [DeliveryReceipt]
    @State private var isLoading: Bool
    @State private var loadError: String?

    init(agent: Agent, initialReceipts: [DeliveryReceipt] = [], initialScope: DeliveryScope? = nil) {
        self.agent = agent
        self.initialReceipts = initialReceipts
        _scope = State(initialValue: initialScope ?? (initialReceipts.contains(where: { $0.status == .failed }) ? .failed : .all))
        _receipts = State(initialValue: initialReceipts.sorted { $0.timestamp > $1.timestamp })
        _isLoading = State(initialValue: initialReceipts.isEmpty)
    }

    private var filteredReceipts: [DeliveryReceipt] {
        let scoped = receipts.filter { receipt in
            switch scope {
            case .all:
                return true
            case .failed:
                return receipt.status == .failed
            case .unsettled:
                return receipt.status == .sent || receipt.status == .bestEffort
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scoped }
        return scoped.filter { receipt in
            [
                receipt.channel,
                receipt.recipient,
                receipt.messageId,
                receipt.status.label,
                receipt.error ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var failedCount: Int {
        receipts.filter { $0.status == .failed }.count
    }

    private var deliveredCount: Int {
        receipts.filter { $0.status == .delivered }.count
    }

    private var unsettledCount: Int {
        receipts.filter { $0.status == .sent || $0.status == .bestEffort }.count
    }

    private var deliveredStatus: MonitoringSummaryStatus {
        .countStatus(deliveredCount, activeTone: .positive)
    }

    private var failedStatus: MonitoringSummaryStatus {
        .countStatus(failedCount, activeTone: .critical)
    }

    private var unsettledStatus: MonitoringSummaryStatus {
        .countStatus(unsettledCount, activeTone: .warning)
    }

    private var exportText: String {
        let header = [
            String(localized: "LibreFang Delivery Snapshot"),
            String(localized: "Agent: \(agent.name)"),
            String(localized: "Scope: \(scope.label)"),
            String(localized: "Visible receipts: \(filteredReceipts.count)"),
            String(localized: "Delivered: \(deliveredCount)"),
            String(localized: "Failed: \(failedCount)"),
            String(localized: "Unsettled: \(unsettledCount)")
        ]

        let rows = filteredReceipts.map { receipt in
            var parts = [
                receipt.status.label,
                receipt.channel,
                receipt.recipient,
                receipt.timestamp
            ]
            if let error = receipt.error, !error.isEmpty {
                parts.append(error)
            }
            return parts.joined(separator: " · ")
        }

        return (header + [""] + rows).joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                DeliverySummaryRow(label: "Agent") {
                    Text(agent.name)
                        .foregroundStyle(.secondary)
                }
                DeliverySummaryRow(label: "Receipts") {
                    Text(receipts.count.formatted())
                        .monospacedDigit()
                }
                DeliverySummaryRow(label: "Delivered") {
                    Text(deliveredCount.formatted())
                        .foregroundStyle(deliveredStatus.tone.color)
                        .monospacedDigit()
                }
                DeliverySummaryRow(label: "Failed") {
                    Text(failedCount.formatted())
                        .foregroundStyle(failedStatus.tone.color)
                        .monospacedDigit()
                }
                DeliverySummaryRow(label: "Unsettled") {
                    Text(unsettledCount.formatted())
                        .foregroundStyle(unsettledStatus.tone.color)
                        .monospacedDigit()
                }
            } header: {
                Text("Delivery Summary")
            } footer: {
                Text("Receipts come from LibreFang's outbound channel delivery tracker and help confirm whether an agent actually reached the outside world.")
            }

            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Primary Surfaces"),
                    detail: String(localized: "Keep the agent, incident, and audit exits closest to delivery failures and unsettled receipts.")
                ) {
                    NavigationLink {
                        AgentDetailView(agent: agent)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Back To Agent"),
                            detail: String(localized: "Return to the agent detail page with sessions, files, memory, and approvals."),
                            systemImage: "cpu",
                            tone: .neutral
                        )
                    }

                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Incidents"),
                            detail: String(localized: "Switch to the incident queue when delivery failures need broader triage."),
                            systemImage: "bell.badge",
                            tone: failedCount > 0 ? .critical : .neutral,
                            badgeText: failedCount > 0
                                ? (failedCount == 1 ? String(localized: "1 failure") : String(localized: "\(failedCount) failures"))
                                : nil,
                            badgeTone: .critical
                        )
                    }

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialSearchText: agent.id, initialScope: .critical)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Event Feed"),
                            detail: String(localized: "Switch to audit events when delivery failures might be tied to runtime or channel activity."),
                            systemImage: "list.bullet.rectangle.portrait",
                            tone: unsettledCount > 0 ? .warning : .neutral,
                            badgeText: unsettledCount > 0
                                ? (unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"))
                                : nil,
                            badgeTone: .warning
                        )
                    }
                }

                MonitoringSurfaceGroupCard(
                    title: String(localized: "Supporting Surfaces"),
                    detail: String(localized: "Keep broader runtime context behind the primary delivery investigation path.")
                ) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Open Runtime"),
                            detail: String(localized: "Switch to runtime when outbound failures may reflect broader channel or provider trouble."),
                            systemImage: "server.rack",
                            tone: .neutral
                        )
                    }
                }
            } header: {
                Text("Operator Surfaces")
            } footer: {
                Text("Use these routes when delivery receipts need incident, event, or runtime context.")
            }

            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        "Delivery Receipts Unavailable",
                        systemImage: "tray.full.badge.minus",
                        description: Text(loadError)
                    )
                }
            } else if filteredReceipts.isEmpty, !isLoading {
                Section("Receipts") {
                    ContentUnavailableView(
                        receipts.isEmpty ? String(localized: "No Delivery Receipts") : String(localized: "No Matching Receipts"),
                        systemImage: "paperplane",
                        description: Text(receipts.isEmpty ? String(localized: "This agent has no recent outbound delivery receipts.") : String(localized: "Try a different recipient, channel, or status search."))
                    )
                }
            } else {
                Section("Receipts") {
                    ForEach(filteredReceipts) { receipt in
                        DeliveryReceiptRow(receipt: receipt)
                    }
                }
            }
        }
        .navigationTitle("Deliveries")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipient, channel, or status")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !filteredReceipts.isEmpty {
                    ShareLink(
                        item: exportText,
                        preview: SharePreview(
                            String(localized: "\(agent.name) Deliveries"),
                            image: Image(systemName: "paperplane")
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Menu {
                    Picker("Scope", selection: $scope) {
                        ForEach(DeliveryScope.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: scope == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .refreshable {
            await loadReceipts()
        }
        .overlay {
            if isLoading && receipts.isEmpty {
                ProgressView("Loading deliveries...")
            }
        }
        .task {
            if receipts.isEmpty {
                await loadReceipts()
            }
        }
    }

    @MainActor
    private func loadReceipts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            receipts = (try await deps.apiClient.agentDeliveries(agentId: agent.id, limit: 100)).receipts
                .sorted { $0.timestamp > $1.timestamp }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct DeliverySummaryRow<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ResponsiveValueRow {
            Text(label)
        } value: {
            content
        }
    }
}

enum DeliveryScope: CaseIterable {
    case all
    case failed
    case unsettled

    var label: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .failed:
            return String(localized: "Failed")
        case .unsettled:
            return String(localized: "Unsettled")
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "tray.full"
        case .failed:
            return "exclamationmark.triangle"
        case .unsettled:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}

private struct DeliveryReceiptRow: View {
    let receipt: DeliveryReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow {
                channelLabel
            } accessory: {
                statusBadge
            }

            Text(receipt.recipient)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            FlowLayout(spacing: 8) {
                timestampLabel
                messageIDLabel
            }

            if let error = receipt.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private var relativeTimestamp: String {
        guard let date = receipt.timestamp.agentSessionISO8601Date else { return receipt.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var channelLabel: some View {
        Text(receipt.localizedChannelLabel)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }

    private var statusBadge: some View {
        PresentationToneBadge(
            text: receipt.status.label,
            tone: receipt.status.tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    private var timestampLabel: some View {
        Text(relativeTimestamp)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var messageIDLabel: some View {
        Text(receipt.messageId)
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
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
