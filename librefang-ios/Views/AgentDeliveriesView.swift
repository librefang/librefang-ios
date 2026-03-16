import SwiftUI

private enum AgentDeliveriesSectionAnchor: Hashable {
    case receipts
}

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

    private var hasActiveFilter: Bool {
        scope != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var agentDeliveriesSectionCount: Int {
        isLoading && receipts.isEmpty && loadError == nil ? 2 : 3
    }
    private var agentDeliveriesSectionPreviewTitles: [String] {
        [String(localized: "Receipts")]
    }

    private var agentDeliveriesPrimaryRouteCount: Int { 3 }
    private var agentDeliveriesSupportRouteCount: Int { 1 }

    private var latestReceiptTimestampLabel: String? {
        guard let receipt = filteredReceipts.first ?? receipts.first else { return nil }
        guard let date = receipt.timestamp.agentSessionISO8601Date else { return receipt.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summarySnapshotText: String {
        if failedCount > 0 || unsettledCount > 0 {
            return String(localized: "Delivery failures and unsettled sends stay visible before the full receipt log.")
        }
        if receipts.isEmpty {
            return String(localized: "This surface keeps outbound delivery state visible before any receipts load.")
        }
        return String(localized: "Recent outbound receipts stay summarized before the longer delivery log.")
    }

    private var summarySnapshotDetail: String {
        if hasActiveFilter {
            return filteredReceipts.count == 1
                ? String(localized: "1 receipt matches the current delivery filter.")
                : String(localized: "\(filteredReceipts.count) receipts match the current delivery filter.")
        }
        return String(localized: "Use the route deck when delivery receipts need incident, audit, or runtime context.")
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
        ScrollViewReader { proxy in
            List {
            Section {
                MonitoringSnapshotCard(
                    summary: summarySnapshotText,
                    detail: summarySnapshotDetail
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: receipts.count == 1 ? String(localized: "1 receipt") : String(localized: "\(receipts.count) receipts"),
                            tone: receipts.isEmpty ? .neutral : .positive
                        )
                        PresentationToneBadge(
                            text: deliveredCount == 1 ? String(localized: "1 delivered") : String(localized: "\(deliveredCount) delivered"),
                            tone: deliveredStatus.tone
                        )
                        if failedCount > 0 {
                            PresentationToneBadge(
                                text: failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                                tone: failedStatus.tone
                            )
                        }
                        if unsettledCount > 0 {
                            PresentationToneBadge(
                                text: unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                                tone: unsettledStatus.tone
                            )
                        }
                    }
                }

                MonitoringFactsRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Active Delivery Slice"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Keep the agent, current scope, and freshest receipt timing available while filtering receipt history."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } accessory: {
                    PresentationToneBadge(text: scope.label, tone: scope.tone)
                } facts: {
                    Label(agent.name, systemImage: "cpu")
                    Label(
                        filteredReceipts.count == 1 ? String(localized: "1 visible receipt") : String(localized: "\(filteredReceipts.count) visible receipts"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    if let latestReceiptTimestampLabel {
                        Label(latestReceiptTimestampLabel, systemImage: "clock")
                    }
                }
            } header: {
                Text("Delivery Summary")
            } footer: {
                Text("Receipts come from LibreFang's outbound channel delivery tracker and help confirm whether an agent actually reached the outside world.")
            }

            Section {
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Shortcuts"),
                    detail: String(localized: "Keep nearby agent, incident, audit, and runtime exits closest to delivery failures and unsettled receipts.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Primary"),
                        detail: String(localized: "Use nearby incident and audit surfaces first.")
                    ) {
                        NavigationLink {
                            AgentDetailView(agent: agent)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Agent"),
                                systemImage: "cpu"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Incidents"),
                                systemImage: "bell.badge",
                                tone: failedCount > 0 ? .critical : .neutral,
                                badgeText: failedCount > 0
                                    ? (failedCount == 1 ? String(localized: "1 failure") : String(localized: "\(failedCount) failures"))
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            EventsView(api: deps.apiClient, initialSearchText: agent.id, initialScope: .critical)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Events"),
                                systemImage: "list.bullet.rectangle.portrait",
                                tone: unsettledCount > 0 ? .warning : .neutral,
                                badgeText: unsettledCount > 0
                                    ? (unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"))
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    MonitoringShortcutRail(
                        title: String(localized: "Support"),
                        detail: String(localized: "Keep broader runtime context behind the primary delivery path.")
                    ) {
                        NavigationLink {
                            RuntimeView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Runtime"),
                                systemImage: "server.rack"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(String(localized: "Shortcuts"))
            } footer: {
                Text(String(localized: "Use these routes when delivery receipts need incident, event, or runtime context."))
            }

            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        String(localized: "Delivery Receipts Unavailable"),
                        systemImage: "tray.full.badge.minus",
                        description: Text(loadError)
                    )
                }
                .id(AgentDeliveriesSectionAnchor.receipts)
            } else if filteredReceipts.isEmpty, !isLoading {
                Section("Receipts") {
                    ContentUnavailableView(
                        receipts.isEmpty ? String(localized: "No Delivery Receipts") : String(localized: "No Matching Receipts"),
                        systemImage: "paperplane",
                        description: Text(receipts.isEmpty ? String(localized: "This agent has no recent outbound delivery receipts.") : String(localized: "Try a different recipient, channel, or status search."))
                    )
                }
                .id(AgentDeliveriesSectionAnchor.receipts)
            } else {
                Section("Receipts") {
                    ForEach(filteredReceipts) { receipt in
                        DeliveryReceiptRow(receipt: receipt)
                    }
                }
                .id(AgentDeliveriesSectionAnchor.receipts)
            }
            }
            .navigationTitle(String(localized: "Deliveries"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text(String(localized: "Search recipient, channel, or status")))
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
                        Picker(String(localized: "Scope"), selection: $scope) {
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
            .monitoringRefreshInteractionGate(isRefreshing: isLoading)
            .refreshable {
                await loadReceipts()
            }
            .overlay {
                if isLoading && receipts.isEmpty {
                    ProgressView(String(localized: "Loading deliveries..."))
                }
            }
            .task {
                if receipts.isEmpty {
                    await loadReceipts()
                }
            }
        }
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: AgentDeliveriesSectionAnchor) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func agentDeliveriesSectionPreviewJumpItems(_ proxy: ScrollViewProxy) -> [MonitoringSectionJumpItem] {
        [
            MonitoringSectionJumpItem(
                title: String(localized: "Receipts"),
                systemImage: "paperplane",
                tone: failedCount > 0 ? .critical : (unsettledCount > 0 ? .warning : .positive)
            ) {
                jump(proxy, to: .receipts)
            }
        ]
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

private struct AgentDeliveriesSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleCount: Int
    let totalCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone
    let isLoading: Bool
    let hasLoadError: Bool

    private var coverageTone: PresentationTone {
        if hasLoadError { return .critical }
        if isLoading { return .warning }
        return .positive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: isLoading
                    ? String(localized: "Section coverage stays visible while delivery receipts are still loading.")
                    : String(localized: "Section coverage stays visible before routes and the longer receipt log."),
                detail: hasActiveFilter
                    ? String(localized: "Use section coverage to confirm the active receipt scope before pivoting into nearby incident or runtime surfaces.")
                    : String(localized: "Use section coverage to confirm how much delivery context is ready before leaving receipt inspection."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: coverageTone
                    )
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failure") : String(localized: "\(failedCount) failures"),
                            tone: .critical
                        )
                    }
                    if unsettledCount > 0 {
                        PresentationToneBadge(
                            text: unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep summary, routes, and receipt coverage visible before drilling into the full outbound delivery log."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if isLoading {
                    PresentationToneBadge(text: String(localized: "Loading"), tone: .warning)
                } else if hasLoadError {
                    PresentationToneBadge(text: String(localized: "Blocked"), tone: .critical)
                } else {
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: .positive
                    )
                }
            } facts: {
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
                if failedCount > 0 {
                    Label(
                        failedCount == 1 ? String(localized: "1 failed receipt") : String(localized: "\(failedCount) failed receipts"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentDeliveriesPressureCoverageDeck: View {
    let visibleCount: Int
    let deliveredCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let latestReceiptTimestampLabel: String?
    let hasActiveFilter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate confirmed delivery, failed sends, unsettled receipts, and scoped receipt slices before opening the full log."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failed receipt") : String(localized: "\(failedCount) failed receipts"),
                            tone: .critical
                        )
                    }
                    if unsettledCount > 0 {
                        PresentationToneBadge(
                            text: unsettledCount == 1 ? String(localized: "1 unsettled receipt") : String(localized: "\(unsettledCount) unsettled receipts"),
                            tone: .warning
                        )
                    }
                    if deliveredCount > 0 {
                        PresentationToneBadge(
                            text: deliveredCount == 1 ? String(localized: "1 delivered receipt") : String(localized: "\(deliveredCount) delivered receipts"),
                            tone: .positive
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep delivery failure, settlement lag, and freshness readable before the outbound receipt rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"),
                    tone: .positive
                )
            } facts: {
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
                if let latestReceiptTimestampLabel {
                    Label(latestReceiptTimestampLabel, systemImage: "clock")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if failedCount > 0 {
            return String(localized: "Delivery pressure is currently anchored by failed outbound receipts.")
        }
        if unsettledCount > 0 {
            return String(localized: "Delivery pressure is currently concentrated in unsettled outbound receipts.")
        }
        return String(localized: "Delivery pressure is currently low and mostly reflects confirmed outbound receipts.")
    }
}

private struct AgentDeliveriesSupportCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let deliveredCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let latestReceiptTimestampLabel: String?
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep delivery confirmation, failure support, and the freshest receipt timing readable before leaving the outbound receipt log."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Filter active"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep delivered, failed, and unsettled receipt support readable before moving into incidents, events, or runtime context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if deliveredCount > 0 {
                    Label(
                        deliveredCount == 1 ? String(localized: "1 delivered") : String(localized: "\(deliveredCount) delivered"),
                        systemImage: "checkmark.circle"
                    )
                }
                if failedCount > 0 {
                    Label(
                        failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if unsettledCount > 0 {
                    Label(
                        unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                        systemImage: "hourglass"
                    )
                }
                if let latestReceiptTimestampLabel {
                    Label(latestReceiptTimestampLabel, systemImage: "clock")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if failedCount > 0 {
            return String(localized: "Delivery support coverage is currently anchored by failed outbound receipts.")
        }
        if unsettledCount > 0 {
            return String(localized: "Delivery support coverage is currently anchored by unsettled outbound receipts.")
        }
        if hasActiveFilter {
            return String(localized: "Delivery support coverage is currently narrowed to the filtered receipt slice.")
        }
        if deliveredCount > 0 {
            return String(localized: "Delivery support coverage is currently anchored by delivered outbound receipts.")
        }
        return String(localized: "Delivery support coverage is currently light across the visible receipts.")
    }
}

private struct AgentDeliveriesFocusCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let deliveredCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let latestReceiptTimestampLabel: String?
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant delivery lane visible before opening route rails and the full receipt log."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: visibleCount == totalCount
                            ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                            : String(localized: "\(visibleCount) of \(totalCount) visible"),
                        tone: visibleCount > 0 ? .positive : .neutral
                    )
                    if hasActiveFilter {
                        PresentationToneBadge(text: String(localized: "Filter active"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant delivery lane readable before moving from compact delivery decks into receipt rows and adjacent incident routes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: deliveredCount == 1 ? String(localized: "1 delivered") : String(localized: "\(deliveredCount) delivered"),
                    tone: deliveredCount > 0 ? .positive : .neutral
                )
            } facts: {
                if failedCount > 0 {
                    Label(
                        failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if unsettledCount > 0 {
                    Label(
                        unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                        systemImage: "hourglass"
                    )
                }
                if let latestReceiptTimestampLabel {
                    Label(latestReceiptTimestampLabel, systemImage: "clock")
                }
            }
        }
    }

    private var summaryLine: String {
        if failedCount > 0 {
            return String(localized: "Delivery focus coverage is currently anchored by failed outbound receipts.")
        }
        if unsettledCount > 0 {
            return String(localized: "Delivery focus coverage is currently anchored by unsettled outbound receipts.")
        }
        if hasActiveFilter {
            return String(localized: "Delivery focus coverage is currently anchored by the filtered receipt slice.")
        }
        return String(localized: "Delivery focus coverage is currently balanced across recent outbound receipts.")
    }
}

private struct AgentDeliveriesWorkstreamCoverageDeck: View {
    let visibleCount: Int
    let totalCount: Int
    let deliveredCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let latestReceiptTimestampLabel: String?
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether delivery review is currently led by failed receipts, unsettled receipts, or confirmed outbound traffic before the log opens."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                            tone: .warning
                        )
                    }
                    if unsettledCount > 0 {
                        PresentationToneBadge(
                            text: unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep failed, unsettled, and delivered receipt lanes readable before moving through the full outbound receipt log."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                if deliveredCount > 0 {
                    Label(
                        deliveredCount == 1 ? String(localized: "1 delivered") : String(localized: "\(deliveredCount) delivered"),
                        systemImage: "checkmark.circle"
                    )
                }
                if let latestReceiptTimestampLabel {
                    Label(latestReceiptTimestampLabel, systemImage: "clock")
                }
                if hasActiveFilter {
                    Label(String(localized: "Filter active"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if failedCount > 0 {
            return String(localized: "Delivery workstream coverage is currently anchored by failed outbound receipts.")
        }
        if unsettledCount > 0 {
            return String(localized: "Delivery workstream coverage is currently anchored by unsettled outbound receipts.")
        }
        if deliveredCount > 0 {
            return String(localized: "Delivery workstream coverage is currently anchored by delivered outbound receipts.")
        }
        return String(localized: "Delivery workstream coverage is currently light across the visible receipts.")
    }
}

private struct AgentDeliveriesActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let deliveredCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let latestReceiptTimestampLabel: String?
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, receipt failure pressure, and visible outbound coverage before leaving the compact delivery log."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failed") : String(localized: "\(failedCount) failed"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, failed or unsettled receipts, and visible outbound coverage readable before pivoting into incidents, events, or runtime context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: visibleCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    systemImage: "arrowshape.turn.up.right"
                )
                if supportRouteCount > 0 {
                    Label(
                        supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        systemImage: "square.grid.2x2"
                    )
                }
                if deliveredCount > 0 {
                    Label(
                        deliveredCount == 1 ? String(localized: "1 delivered") : String(localized: "\(deliveredCount) delivered"),
                        systemImage: "checkmark.circle"
                    )
                }
                if unsettledCount > 0 {
                    Label(
                        unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                        systemImage: "hourglass"
                    )
                }
                if let latestReceiptTimestampLabel {
                    Label(latestReceiptTimestampLabel, systemImage: "clock")
                }
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var summaryLine: String {
        if failedCount > 0 {
            return String(localized: "Delivery action readiness is currently anchored by failed outbound receipts and the next route exits.")
        }
        if unsettledCount > 0 {
            return String(localized: "Delivery action readiness is currently anchored by unsettled outbound receipts and nearby route exits.")
        }
        if hasActiveFilter {
            return String(localized: "Delivery action readiness is currently anchored by the scoped receipt slice and route breadth.")
        }
        return String(localized: "Delivery action readiness is currently clear enough for route pivots and receipt review.")
    }
}

private struct AgentDeliveriesRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleCount: Int
    let totalCount: Int
    let failedCount: Int
    let unsettledCount: Int
    let hasActiveFilter: Bool
    let scopeLabel: String
    let scopeTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveFilter
                    ? String(localized: "Delivery routes stay compact while the receipt log is scoped.")
                    : String(localized: "Delivery routes stay compact before the surrounding incident and runtime drilldowns."),
                detail: String(localized: "Use the route inventory to gauge the visible receipt slice before leaving delivery inspection."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: scopeLabel, tone: scopeTone)
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failure") : String(localized: "\(failedCount) failures"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep visible receipt size and unsettled delivery pressure readable before pivoting into agent, incident, events, or runtime context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? (visibleCount == 1 ? String(localized: "1 visible receipt") : String(localized: "\(visibleCount) visible receipts"))
                        : String(localized: "\(visibleCount) of \(totalCount) visible"),
                    tone: .positive
                )
            } facts: {
                if unsettledCount > 0 {
                    Label(
                        unsettledCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledCount) unsettled"),
                        systemImage: "clock.badge.exclamationmark"
                    )
                }
                if hasActiveFilter {
                    Label(String(localized: "Scoped inventory"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .padding(.vertical, 2)
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

    var tone: PresentationTone {
        switch self {
        case .all:
            return .neutral
        case .failed:
            return .critical
        case .unsettled:
            return .warning
        }
    }
}

private struct DeliveryReceiptsInventoryDeck: View {
    let receipts: [DeliveryReceipt]
    let totalReceipts: Int
    let scope: DeliveryScope
    let searchText: String

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var failedCount: Int {
        receipts.filter { $0.status == .failed }.count
    }

    private var unsettledCount: Int {
        receipts.filter { $0.status == .sent || $0.status == .bestEffort }.count
    }

    private var channelCount: Int {
        Set(receipts.map(\.channel)).count
    }

    private var recipientCount: Int {
        Set(receipts.map(\.recipient)).count
    }

    private var dominantChannel: String? {
        receipts
            .reduce(into: [String: Int]()) { counts, receipt in
                counts[receipt.channel, default: 0] += 1
            }
            .max { $0.value < $1.value }?
            .key
    }

    private var latestReceiptLabel: String? {
        guard let latest = receipts.first else { return nil }
        guard let date = latest.timestamp.agentSessionISO8601Date else { return latest.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasActiveSearch
                    ? String(localized: "The filtered delivery slice stays compact before the full receipt list.")
                    : String(localized: "The active delivery slice stays compact before the full receipt list."),
                detail: hasActiveSearch
                    ? (receipts.count == 1
                        ? String(localized: "1 receipt matches the current delivery search.")
                        : String(localized: "\(receipts.count) receipts match the current delivery search."))
                    : String(localized: "Use the deck to gauge channel spread, recent failures, and unsettled sends before opening each receipt row."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: receipts.count == totalReceipts
                            ? (receipts.count == 1 ? String(localized: "1 visible receipt") : String(localized: "\(receipts.count) visible receipts"))
                            : String(localized: "\(receipts.count) of \(totalReceipts) visible"),
                        tone: .positive
                    )
                    if failedCount > 0 {
                        PresentationToneBadge(
                            text: failedCount == 1 ? String(localized: "1 failed receipt") : String(localized: "\(failedCount) failed receipts"),
                            tone: .critical
                        )
                    }
                    if unsettledCount > 0 {
                        PresentationToneBadge(
                            text: unsettledCount == 1 ? String(localized: "1 unsettled receipt") : String(localized: "\(unsettledCount) unsettled receipts"),
                            tone: .warning
                        )
                    }
                    PresentationToneBadge(
                        text: channelCount == 1 ? String(localized: "1 channel") : String(localized: "\(channelCount) channels"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Receipt Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active scope, channel spread, dominant delivery lane, and latest receipt timing visible while scanning delivery history."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: scope.label, tone: scope.tone)
            } facts: {
                Label(
                    recipientCount == 1 ? String(localized: "1 recipient") : String(localized: "\(recipientCount) recipients"),
                    systemImage: "person.2"
                )
                if let dominantChannel {
                    Label(localizedChannelLabel(for: dominantChannel), systemImage: "paperplane")
                }
                if let latestReceiptLabel {
                    Label(latestReceiptLabel, systemImage: "clock")
                }
            }
        }
    }

    private func localizedChannelLabel(for channel: String) -> String {
        receipts.first(where: { $0.channel == channel })?.localizedChannelLabel ?? channel
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
