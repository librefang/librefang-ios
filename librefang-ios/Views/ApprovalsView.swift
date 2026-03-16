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

    private var filteredApprovals: [ApprovalItem] {
        var base = vm.approvals
        
        switch filter {
        case .all:
            break
        case .critical:
            base = base.filter { $0.isCriticalRisk }
        case .high:
            base = base.filter { $0.isHighRiskOrAbove }
        }
        
        let query = trimmedSearchText.lowercased()
        if !query.isEmpty {
            base = base.filter {
                $0.agentName.localizedCaseInsensitiveContains(query) ||
                $0.toolName.localizedCaseInsensitiveContains(query) ||
                $0.actionSummary.localizedCaseInsensitiveContains(query)
            }
        }
        
        return base
    }
    var body: some View {
        List {
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

            if filteredApprovals.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    searchText.isEmpty ? String(localized: "No Pending Approvals") : String(localized: "No Search Results"),
                    systemImage: "checkmark.shield",
                    description: Text(searchText.isEmpty ? String(localized: "Nothing pending right now.") : String(localized: "Try a different search."))
                )
            } else {
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
            }
        }
        .navigationTitle(String(localized: "Approvals"))
        .searchable(text: $searchText, prompt: Text(String(localized: "Search agent, tool, or action")))
        .monitoringRefreshInteractionGate(isRefreshing: vm.isLoading)
        .refreshable {
            await vm.refresh()
        }
        .overlay {
            if vm.isLoading && vm.approvals.isEmpty {
                ProgressView(String(localized: "Loading approvals..."))
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
            Button(String(localized: "Cancel"), role: .cancel) {}
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
