import SwiftUI

private enum ApprovalRiskFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .critical:
            String(localized: "Critical")
        case .high:
            String(localized: "High+")
        }
    }
}

struct ApprovalsView: View {
    @Environment(\.dependencies) private var deps
    @State private var searchText = ""
    @State private var filter: ApprovalRiskFilter = .all
    @State private var pendingAction: ApprovalDecisionAction?
    @State private var actionInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?

    private var vm: DashboardViewModel { deps.dashboardViewModel }
    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var filterTone: PresentationTone {
        switch filter {
        case .all:
            .neutral
        case .critical:
            .critical
        case .high:
            .warning
        }
    }

    private var filteredApprovals: [ApprovalItem] {
        vm.approvals
            .filter { approval in
                switch filter {
                case .all:
                    return true
                case .critical:
                    return approval.isCriticalRisk
                case .high:
                    return approval.isHighRiskOrAbove
                }
            }
            .filter { approval in
                let query = trimmedSearchText.lowercased()
                guard !query.isEmpty else { return true }
                return [
                    approval.agentName,
                    approval.agentId,
                    approval.toolName,
                    approval.actionSummary,
                    approval.description,
                ]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
            }
            .sorted { lhs, rhs in
                if lhs.riskRank != rhs.riskRank {
                    return lhs.riskRank > rhs.riskRank
                }
                return lhs.requestedAt > rhs.requestedAt
            }
    }

    private var criticalApprovalCount: Int {
        vm.approvals.filter(\.isCriticalRisk).count
    }

    private var highRiskApprovalCount: Int {
        vm.approvals.filter(\.isHighRiskOrAbove).count
    }

    private var approvalAgentCount: Int {
        Set(vm.approvals.map(\.agentId)).count
    }
    private var visibleToolCount: Int {
        Set(filteredApprovals.map(\.toolName)).count
    }
    private var approvalsSectionCount: Int { 1 }
    private var approvalsPrimaryRouteCount: Int { 3 }
    private var approvalsSupportRouteCount: Int { 1 }

    var body: some View {
        List {
            Section {
                ApprovalsScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                ApprovalsStatusDeckCard(
                    pendingApprovalCount: vm.pendingApprovalCount,
                    criticalApprovalCount: criticalApprovalCount,
                    highRiskApprovalCount: highRiskApprovalCount,
                    approvalAgentCount: approvalAgentCount,
                    visibleApprovalCount: filteredApprovals.count,
                    filterLabel: filter.label,
                    filterTone: filterTone,
                    hasSearchScope: !trimmedSearchText.isEmpty
                )
                ApprovalsSectionInventoryDeck(
                    sectionCount: approvalsSectionCount,
                    pendingApprovalCount: vm.pendingApprovalCount,
                    visibleApprovalCount: filteredApprovals.count,
                    criticalApprovalCount: criticalApprovalCount,
                    highRiskApprovalCount: highRiskApprovalCount,
                    approvalAgentCount: approvalAgentCount,
                    toolCount: visibleToolCount,
                    hasSearchScope: !trimmedSearchText.isEmpty
                )
                ApprovalsPressureCoverageDeck(
                    pendingApprovalCount: vm.pendingApprovalCount,
                    visibleApprovalCount: filteredApprovals.count,
                    criticalApprovalCount: criticalApprovalCount,
                    highRiskApprovalCount: highRiskApprovalCount,
                    approvalAgentCount: approvalAgentCount,
                    toolCount: visibleToolCount,
                    hasSearchScope: !trimmedSearchText.isEmpty
                )
                ApprovalsSupportCoverageDeck(
                    visibleApprovalCount: filteredApprovals.count,
                    approvalAgentCount: approvalAgentCount,
                    toolCount: visibleToolCount,
                    hasSearchScope: !trimmedSearchText.isEmpty,
                    filterLabel: filter.label,
                    filterTone: filterTone
                )
                ApprovalsActionReadinessDeck(
                    primaryRouteCount: approvalsPrimaryRouteCount,
                    supportRouteCount: approvalsSupportRouteCount,
                    visibleApprovalCount: filteredApprovals.count,
                    criticalApprovalCount: criticalApprovalCount,
                    approvalAgentCount: approvalAgentCount,
                    hasSearchScope: !trimmedSearchText.isEmpty,
                    filterLabel: filter.label,
                    filterTone: filterTone
                )
                ApprovalsFocusCoverageDeck(
                    visibleApprovalCount: filteredApprovals.count,
                    criticalApprovalCount: criticalApprovalCount,
                    highRiskApprovalCount: highRiskApprovalCount,
                    approvalAgentCount: approvalAgentCount,
                    toolCount: visibleToolCount,
                    hasSearchScope: !trimmedSearchText.isEmpty,
                    filterLabel: filter.label,
                    filterTone: filterTone
                )
                ApprovalsRouteInventoryDeck(
                    primaryRouteCount: approvalsPrimaryRouteCount,
                    supportRouteCount: approvalsSupportRouteCount,
                    pendingApprovalCount: vm.pendingApprovalCount,
                    criticalApprovalCount: criticalApprovalCount,
                    approvalAgentCount: approvalAgentCount
                )
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Keep the incident, on-call, and runtime exits closest to approval review.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Primary"),
                        detail: String(localized: "Use the main operator routes first when approval pressure needs broader queue context.")
                    ) {
                        NavigationLink {
                            IncidentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Incidents"),
                                systemImage: "bell.badge",
                                tone: criticalApprovalCount > 0 ? .critical : .neutral,
                                badgeText: criticalApprovalCount > 0 ? "\(criticalApprovalCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            OnCallView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "On Call"),
                                systemImage: "waveform.path.ecg",
                                tone: vm.pendingApprovalCount > 0 ? .warning : .neutral,
                                badgeText: vm.pendingApprovalCount > 0 ? "\(vm.pendingApprovalCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            RuntimeView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Runtime"),
                                systemImage: "server.rack",
                                tone: vm.runtimeAlertCount > 0 ? .warning : .neutral,
                                badgeText: vm.runtimeAlertCount > 0 ? "\(vm.runtimeAlertCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    MonitoringShortcutRail(
                        title: String(localized: "Support"),
                        detail: String(localized: "Use fleet context when approval requests cluster around the same agents.")
                    ) {
                        NavigationLink {
                            AgentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Agents"),
                                systemImage: "person.3",
                                tone: .neutral,
                                badgeText: approvalAgentCount > 0 ? "\(approvalAgentCount)" : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                ApprovalsFilterCard(
                    filter: $filter,
                    searchText: searchText,
                    visibleCount: filteredApprovals.count,
                    totalCount: vm.approvals.count
                )
            } header: {
                Text("Controls")
            } footer: {
                Text("Keep severity, routes, and filters together before the approval list.")
            }

            if filteredApprovals.isEmpty && !vm.isLoading {
                Section("Approvals") {
                    ContentUnavailableView(
                        searchText.isEmpty ? String(localized: "No Pending Approvals") : String(localized: "No Search Results"),
                        systemImage: "checkmark.shield",
                        description: Text(searchText.isEmpty ? String(localized: "The current dashboard snapshot has no unresolved approval gates.") : String(localized: "Try a different agent, tool, or action query."))
                    )
                }
            } else {
                Section {
                    ApprovalsQueueInventoryDeck(
                        approvals: filteredApprovals,
                        totalCount: vm.approvals.count,
                        filterLabel: filter.label,
                        filterTone: filterTone,
                        searchText: trimmedSearchText
                    )

                    ForEach(filteredApprovals) { approval in
                        ApprovalOperatorRow(
                            approval: approval,
                            isBusy: actionInFlightID == approval.id,
                            onApprove: {
                                pendingAction = .approve(approval)
                            },
                            onReject: {
                                pendingAction = .reject(approval)
                            }
                        )
                    }
                } header: {
                    Text("Approvals")
                } footer: {
                    Text("Resolve requests from mobile after confirmation. The queue refreshes from the server after each decision.")
                }
            }
        }
        .navigationTitle("Approvals")
        .searchable(text: $searchText, prompt: "Search agent, tool, or action")
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && vm.approvals.isEmpty {
                ProgressView("Loading approvals...")
            }
        }
        .task {
            if vm.approvals.isEmpty {
                await vm.refresh()
            }
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: actionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .alert(item: $operatorNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var actionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAction = nil
                }
            }
        )
    }

    @MainActor
    private func performAction(_ action: ApprovalDecisionAction) async {
        pendingAction = nil
        actionInFlightID = action.approvalID
        defer { actionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await vm.refresh()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
    }

}

private struct ApprovalsFilterCard: View {
    @Binding var filter: ApprovalRiskFilter
    let searchText: String
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        MonitoringFilterCard(summary: summaryLine, detail: searchSummary) {
            activeBadge
        } controls: {
            FlowLayout(spacing: 8) {
                ForEach(ApprovalRiskFilter.allCases) { option in
                    Button {
                        filter = option
                    } label: {
                        ApprovalFilterChip(
                            label: option.label,
                            isSelected: filter == option
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeBadge: some View {
        PresentationToneBadge(
            text: filter.label,
            tone: badgeTone
        )
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return totalCount == 1
                ? String(localized: "1 approval in queue")
                : String(localized: "\(totalCount) approvals in queue")
        }

        return String(localized: "\(visibleCount) of \(totalCount) approvals visible")
    }

    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "Use search to narrow by agent, tool, or action.")
        }
        return String(localized: "Search active: \"\(query)\"")
    }

    private var badgeTone: PresentationTone {
        switch filter {
        case .all:
            return .neutral
        case .critical:
            return .critical
        case .high:
            return .warning
        }
    }
}

private struct ApprovalsStatusDeckCard: View {
    let pendingApprovalCount: Int
    let criticalApprovalCount: Int
    let highRiskApprovalCount: Int
    let approvalAgentCount: Int
    let visibleApprovalCount: Int
    let filterLabel: String
    let filterTone: PresentationTone
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: pendingApprovalCount == 1
                    ? String(localized: "1 approval gate is waiting for operator review.")
                    : String(localized: "\(pendingApprovalCount) approval gates are waiting for operator review."),
                detail: String(localized: "Critical and high-risk approvals stay visible above the mobile action queue.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    if criticalApprovalCount > 0 {
                        PresentationToneBadge(
                            text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                            tone: .critical
                        )
                    }
                    if highRiskApprovalCount > 0 {
                        PresentationToneBadge(
                            text: highRiskApprovalCount == 1 ? String(localized: "1 high+") : String(localized: "\(highRiskApprovalCount) high+"),
                            tone: .warning
                        )
                    }
                    if approvalAgentCount > 0 {
                        PresentationToneBadge(
                            text: approvalAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(approvalAgentCount) agents"),
                            tone: .neutral
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(
                            text: visibleApprovalCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleApprovalCount) visible results"),
                            tone: .neutral
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Approval queue facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue severity, agent spread, and visible results clear before acting on requests from the phone."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: filterLabel,
                    tone: filterTone
                )
            } facts: {
                Label(
                    pendingApprovalCount == 1 ? String(localized: "1 pending approval") : String(localized: "\(pendingApprovalCount) pending approvals"),
                    systemImage: "checkmark.shield"
                )
                if criticalApprovalCount > 0 {
                    Label(
                        criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                        systemImage: "xmark.octagon"
                    )
                }
                if highRiskApprovalCount > 0 {
                    Label(
                        highRiskApprovalCount == 1 ? String(localized: "1 high-risk request") : String(localized: "\(highRiskApprovalCount) high-risk requests"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                Label(
                    approvalAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(approvalAgentCount) agents"),
                    systemImage: "person.3"
                )
                Label(
                    visibleApprovalCount == 1 ? String(localized: "1 visible result") : String(localized: "\(visibleApprovalCount) visible results"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                if hasSearchScope {
                    Label(String(localized: "Scoped search"), systemImage: "magnifyingglass")
                }
            }
        }
    }
}

private struct ApprovalsSectionInventoryDeck: View {
    let sectionCount: Int
    let pendingApprovalCount: Int
    let visibleApprovalCount: Int
    let criticalApprovalCount: Int
    let highRiskApprovalCount: Int
    let approvalAgentCount: Int
    let toolCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: visibleApprovalCount == 1 ? String(localized: "1 visible approval") : String(localized: "\(visibleApprovalCount) visible approvals"),
                        tone: visibleApprovalCount > 0 ? .positive : .neutral
                    )
                    if criticalApprovalCount > 0 {
                        PresentationToneBadge(
                            text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                            tone: .critical
                        )
                    }
                    if highRiskApprovalCount > criticalApprovalCount {
                        PresentationToneBadge(
                            text: highRiskApprovalCount == 1 ? String(localized: "1 high-risk") : String(localized: "\(highRiskApprovalCount) high-risk"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue coverage, agent spread, and tool load visible before the approval rows take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: pendingApprovalCount == 1 ? String(localized: "1 pending") : String(localized: "\(pendingApprovalCount) pending"),
                    tone: pendingApprovalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    approvalAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(approvalAgentCount) visible agents"),
                    systemImage: "person.3"
                )
                Label(
                    toolCount == 1 ? String(localized: "1 visible tool") : String(localized: "\(toolCount) visible tools"),
                    systemImage: "wrench.and.screwdriver"
                )
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 approval section is active below the controls deck.")
            : String(localized: "\(sectionCount) approval sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Visible queue coverage, agent spread, and tool load stay summarized before the phone-sized approval list takes over.")
    }
}

private struct ApprovalsPressureCoverageDeck: View {
    let pendingApprovalCount: Int
    let visibleApprovalCount: Int
    let criticalApprovalCount: Int
    let highRiskApprovalCount: Int
    let approvalAgentCount: Int
    let toolCount: Int
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "Approval pressure coverage keeps severity mix readable before routes and row actions."),
                detail: String(localized: "Use this deck to judge whether the mobile queue is dominated by critical decisions, high-risk tool calls, or spread across many agents."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if criticalApprovalCount > 0 {
                        PresentationToneBadge(
                            text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                            tone: .critical
                        )
                    }
                    if highRiskApprovalCount > criticalApprovalCount {
                        PresentationToneBadge(
                            text: highRiskApprovalCount == 1 ? String(localized: "1 high-risk") : String(localized: "\(highRiskApprovalCount) high-risk"),
                            tone: .warning
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Scoped queue"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep decision pressure, agent spread, and visible tool breadth readable before acting on the queue."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: pendingApprovalCount == 1 ? String(localized: "1 pending") : String(localized: "\(pendingApprovalCount) pending"),
                    tone: pendingApprovalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    visibleApprovalCount == 1 ? String(localized: "1 visible approval") : String(localized: "\(visibleApprovalCount) visible approvals"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                Label(
                    approvalAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(approvalAgentCount) agents"),
                    systemImage: "person.3"
                )
                Label(
                    toolCount == 1 ? String(localized: "1 visible tool") : String(localized: "\(toolCount) visible tools"),
                    systemImage: "wrench.and.screwdriver"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ApprovalsSupportCoverageDeck: View {
    let visibleApprovalCount: Int
    let approvalAgentCount: Int
    let toolCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep queue scope, agent spread, and tool breadth readable before acting on individual approvals."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                    PresentationToneBadge(
                        text: visibleApprovalCount == 1 ? String(localized: "1 visible approval") : String(localized: "\(visibleApprovalCount) visible approvals"),
                        tone: visibleApprovalCount > 0 ? .positive : .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Support coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep queue breadth, agent spread, and tool mix visible before the approval rows and action buttons take over."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: approvalAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(approvalAgentCount) agents"),
                    tone: approvalAgentCount > 0 ? .positive : .neutral
                )
            } facts: {
                Label(
                    toolCount == 1 ? String(localized: "1 visible tool") : String(localized: "\(toolCount) visible tools"),
                    systemImage: "wrench.and.screwdriver"
                )
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSearchScope {
            return String(localized: "Approval support coverage is currently narrowed to a filtered slice of the queue.")
        }
        if approvalAgentCount > 1 || toolCount > 1 {
            return String(localized: "Approval support coverage is currently spread across multiple agents and tools.")
        }
        return String(localized: "Approval support coverage is currently narrow and mostly reflects a single agent or tool slice.")
    }
}

private struct ApprovalsQueueInventoryDeck: View {
    let approvals: [ApprovalItem]
    let totalCount: Int
    let filterLabel: String
    let filterTone: PresentationTone
    let searchText: String

    private var visibleCount: Int {
        approvals.count
    }

    private var criticalCount: Int {
        approvals.filter(\.isCriticalRisk).count
    }

    private var highRiskCount: Int {
        approvals.filter(\.isHighRiskOrAbove).count
    }

    private var agentCount: Int {
        Set(approvals.map(\.agentId)).count
    }

    private var toolCount: Int {
        Set(approvals.map(\.toolName)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: detailLine,
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    if !searchText.isEmpty {
                        PresentationToneBadge(
                            text: String(localized: "Search scoped"),
                            tone: .neutral
                        )
                    }
                    if criticalCount > 0 {
                        PresentationToneBadge(
                            text: criticalCount == 1 ? String(localized: "1 critical visible") : String(localized: "\(criticalCount) critical visible"),
                            tone: .critical
                        )
                    }
                    if highRiskCount > criticalCount {
                        PresentationToneBadge(
                            text: String(localized: "\(highRiskCount) high+ visible"),
                            tone: .warning
                        )
                    }
                    if let latestRequestLabel {
                        PresentationToneBadge(text: latestRequestLabel, tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Queue inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use the compact queue slice to judge how much of the approval backlog is already visible on the phone."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleCount == totalCount
                        ? String(localized: "Full queue")
                        : String(localized: "\(visibleCount)/\(totalCount) visible"),
                    tone: visibleCount == totalCount ? .positive : .neutral
                )
            } facts: {
                Label(
                    visibleCount == 1 ? String(localized: "1 visible request") : String(localized: "\(visibleCount) visible requests"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                Label(
                    agentCount == 1 ? String(localized: "1 agent") : String(localized: "\(agentCount) agents"),
                    systemImage: "person.3"
                )
                Label(
                    toolCount == 1 ? String(localized: "1 tool") : String(localized: "\(toolCount) tools"),
                    systemImage: "wrench.and.screwdriver"
                )
                if highRiskCount > 0 {
                    Label(
                        highRiskCount == 1 ? String(localized: "1 high-risk request") : String(localized: "\(highRiskCount) high-risk requests"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if let latestRequestLabel {
                    Label(latestRequestLabel, systemImage: "clock")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if visibleCount == totalCount {
            return visibleCount == 1
                ? String(localized: "The mobile queue is showing the only pending approval.")
                : String(localized: "The mobile queue is showing all \(visibleCount) pending approvals.")
        }
        return String(localized: "The mobile queue is showing \(visibleCount) of \(totalCount) pending approvals.")
    }

    private var detailLine: String {
        if searchText.isEmpty {
            return String(localized: "Filter by risk first, then use agent, tool, or action search only when the queue is still too broad.")
        }
        return String(localized: "Search is narrowed to \"\(searchText)\", so only the matching approval slice stays in the mobile queue.")
    }

    private var latestRequestLabel: String? {
        guard let date = approvals.compactMap(\.requestedAt.approvalRequestedDate).max() else { return nil }
        return String(localized: "Latest \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
    }
}

private struct ApprovalsActionReadinessDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleApprovalCount: Int
    let criticalApprovalCount: Int
    let approvalAgentCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    private var totalRouteCount: Int {
        primaryRouteCount + supportRouteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to check route breadth, filter scope, and visible approval coverage before moving into the approval route rail."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: totalRouteCount == 1 ? String(localized: "1 route ready") : String(localized: "\(totalRouteCount) routes ready"),
                        tone: totalRouteCount > 0 ? .positive : .neutral
                    )
                    if criticalApprovalCount > 0 {
                        PresentationToneBadge(
                            text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Action readiness"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep route breadth, filter scope, and visible approval spread readable before leaving the approval queue for broader operator context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleApprovalCount == 1 ? String(localized: "1 visible approval") : String(localized: "\(visibleApprovalCount) visible approvals"),
                    tone: visibleApprovalCount > 0 ? .warning : .neutral
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
                if approvalAgentCount > 0 {
                    Label(
                        approvalAgentCount == 1 ? String(localized: "1 visible agent") : String(localized: "\(approvalAgentCount) visible agents"),
                        systemImage: "person.2"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if criticalApprovalCount > 0 {
            return String(localized: "Approval action readiness is currently anchored by critical approval requests.")
        }
        if hasSearchScope {
            return String(localized: "Approval action readiness is currently anchored by the active search scope and filtered review slice.")
        }
        return String(localized: "Approval action readiness is currently centered on grouped operator exits and visible queue coverage.")
    }
}

private struct ApprovalsFocusCoverageDeck: View {
    let visibleApprovalCount: Int
    let criticalApprovalCount: Int
    let highRiskApprovalCount: Int
    let approvalAgentCount: Int
    let toolCount: Int
    let hasSearchScope: Bool
    let filterLabel: String
    let filterTone: PresentationTone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant approval lane visible before opening route rails and the full approval queue."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: filterLabel, tone: filterTone)
                    PresentationToneBadge(
                        text: visibleApprovalCount == 1 ? String(localized: "1 visible approval") : String(localized: "\(visibleApprovalCount) visible approvals"),
                        tone: visibleApprovalCount > 0 ? .positive : .neutral
                    )
                    if criticalApprovalCount > 0 {
                        PresentationToneBadge(
                            text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                            tone: .critical
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant approval lane readable before moving from the compact control decks into route rails and queue rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: highRiskApprovalCount == 1 ? String(localized: "1 high risk") : String(localized: "\(highRiskApprovalCount) high risk"),
                    tone: highRiskApprovalCount > 0 ? .warning : .neutral
                )
            } facts: {
                if approvalAgentCount > 0 {
                    Label(
                        approvalAgentCount == 1 ? String(localized: "1 agent lane") : String(localized: "\(approvalAgentCount) agent lanes"),
                        systemImage: "person.2"
                    )
                }
                if toolCount > 0 {
                    Label(
                        toolCount == 1 ? String(localized: "1 tool lane") : String(localized: "\(toolCount) tool lanes"),
                        systemImage: "wrench.and.screwdriver"
                    )
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if criticalApprovalCount > 0 || highRiskApprovalCount > 0 {
            return String(localized: "Approval focus coverage is currently anchored by critical and high-risk review lanes.")
        }
        if hasSearchScope {
            return String(localized: "Approval focus coverage is currently anchored by the filtered approval slice.")
        }
        return String(localized: "Approval focus coverage is currently balanced across the visible approval lanes.")
    }
}

private struct ApprovalsRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let pendingApprovalCount: Int
    let criticalApprovalCount: Int
    let approvalAgentCount: Int

    var body: some View {
        MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                    tone: .neutral
                )
                PresentationToneBadge(
                    text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                    tone: .neutral
                )
                if pendingApprovalCount > 0 {
                    PresentationToneBadge(
                        text: pendingApprovalCount == 1 ? String(localized: "1 pending") : String(localized: "\(pendingApprovalCount) pending"),
                        tone: .warning
                    )
                }
                if criticalApprovalCount > 0 {
                    PresentationToneBadge(
                        text: criticalApprovalCount == 1 ? String(localized: "1 critical") : String(localized: "\(criticalApprovalCount) critical"),
                        tone: .critical
                    )
                }
                if approvalAgentCount > 0 {
                    PresentationToneBadge(
                        text: approvalAgentCount == 1 ? String(localized: "1 agent") : String(localized: "\(approvalAgentCount) agents"),
                        tone: .neutral
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        let totalRoutes = primaryRouteCount + supportRouteCount
        return totalRoutes == 1
            ? String(localized: "1 approval route is grouped in this deck.")
            : String(localized: "\(totalRoutes) approval routes are grouped in this deck.")
    }

    private var detailLine: String {
        String(localized: "Queue exits stay summarized here before the runtime, incident, and fleet route chips.")
    }
}

private struct ApprovalFilterChip: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        SelectableCapsuleBadge(text: label, isSelected: isSelected)
    }
}

private extension String {
    var approvalRequestedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}

private struct ApprovalsScoreboard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let vm: DashboardViewModel

    private var criticalStatus: MonitoringSummaryStatus {
        .countStatus(criticalCount, activeTone: .critical)
    }

    private var highRiskStatus: MonitoringSummaryStatus {
        .countStatus(highCount, activeTone: .warning)
    }

    private var agentStatus: MonitoringSummaryStatus {
        .countStatus(agentCount, activeTone: .warning)
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.pendingApprovalCount)",
                label: "Pending",
                icon: "checkmark.shield",
                color: vm.approvalBacklogStatus.tone.color
            )
            StatBadge(
                value: "\(criticalCount)",
                label: "Critical",
                icon: "xmark.shield",
                color: criticalStatus.tone.color
            )
            StatBadge(
                value: "\(highCount)",
                label: "High+",
                icon: "exclamationmark.shield",
                color: highRiskStatus.tone.color
            )
            StatBadge(
                value: "\(agentCount)",
                label: "Agents",
                icon: "cpu",
                color: agentStatus.tone.color
            )
        }
        .padding(.horizontal)
    }

    private var criticalCount: Int {
        vm.approvals.filter(\.isCriticalRisk).count
    }

    private var highCount: Int {
        vm.approvals.filter(\.isHighRiskOrAbove).count
    }

    private var agentCount: Int {
        Set(vm.approvals.map(\.agentId)).count
    }
}
