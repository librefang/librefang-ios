import SwiftUI

struct AgentDeliveriesView: View {
    let agent: Agent
    let initialReceipts: [DeliveryReceipt]

    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var receipts: [DeliveryReceipt]
    @State private var isLoading: Bool
    @State private var loadError: String?

    init(agent: Agent, initialReceipts: [DeliveryReceipt] = []) {
        self.agent = agent
        self.initialReceipts = initialReceipts
        _receipts = State(initialValue: initialReceipts.sorted { $0.timestamp > $1.timestamp })
        _isLoading = State(initialValue: initialReceipts.isEmpty)
    }

    private var filteredReceipts: [DeliveryReceipt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return receipts }
        return receipts.filter { receipt in
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
                        .foregroundStyle(deliveredCount > 0 ? .green : .secondary)
                        .monospacedDigit()
                }
                LabeledContent("Failed") {
                    Text(failedCount.formatted())
                        .foregroundStyle(failedCount > 0 ? .red : .secondary)
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
                        receipts.isEmpty ? "No Delivery Receipts" : "No Matching Receipts",
                        systemImage: "paperplane",
                        description: Text(receipts.isEmpty ? "This agent has no recent outbound delivery receipts." : "Try a different recipient, channel, or status search.")
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

private struct DeliveryReceiptRow: View {
    let receipt: DeliveryReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.channel.capitalized)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(receipt.status.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            Text(receipt.recipient)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(receipt.messageId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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

    private var statusColor: Color {
        switch receipt.status {
        case .delivered:
            return .green
        case .failed:
            return .red
        case .bestEffort:
            return .orange
        case .sent:
            return .blue
        }
    }

    private var relativeTimestamp: String {
        guard let date = receipt.timestamp.agentSessionISO8601Date else { return receipt.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
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
