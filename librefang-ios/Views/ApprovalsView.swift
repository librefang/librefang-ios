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
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                    filterTone: filter == .critical ? .critical : filter == .high ? .warning : .neutral,
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Surface Rail"),
                    detail: String(localized: "Keep the incident, on-call, and runtime exits closest to approval review.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Primary Surfaces"),
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
                        title: String(localized: "Supporting Surfaces"),
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
                Text("Operator Deck")
            } footer: {
                Text("Queue severity, drilldown routes, and filter controls now stay together before the approval list itself.")
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

private struct ApprovalFilterChip: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        SelectableCapsuleBadge(text: label, isSelected: isSelected)
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
