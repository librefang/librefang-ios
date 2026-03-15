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
                LabeledContent("Agent") {
                    Text(agent.name)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Receipts") {
                    Text(receipts.count.formatted())
                        .monospacedDigit()
                }
                LabeledContent("Delivered") {
                    Text(deliveredCount.formatted())
                        .foregroundStyle(deliveredStatus.tone.color)
                        .monospacedDigit()
                }
                LabeledContent("Failed") {
                    Text(failedCount.formatted())
                        .foregroundStyle(failedStatus.tone.color)
                        .monospacedDigit()
                }
                LabeledContent("Unsettled") {
                    Text(unsettledCount.formatted())
                        .foregroundStyle(unsettledStatus.tone.color)
                        .monospacedDigit()
                }
            } header: {
                Text("Delivery Summary")
            } footer: {
                Text("Receipts come from LibreFang's outbound channel delivery tracker and help confirm whether an agent actually reached the outside world.")
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    channelLabel
                    Spacer()
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 6) {
                    channelLabel
                    statusBadge
                }
            }

            Text(receipt.recipient)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    timestampLabel
                    messageIDLabel
                }

                VStack(alignment: .leading, spacing: 3) {
                    timestampLabel
                    messageIDLabel
                }
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
        Text(receipt.status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(receipt.status.tone.color.opacity(0.12))
            .foregroundStyle(receipt.status.tone.color)
            .clipShape(Capsule())
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
