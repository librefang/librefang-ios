import SwiftUI

private enum ApprovalRiskFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "All"
        case .critical:
            "Critical"
        case .high:
            "High+"
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
                    return approval.riskLevel.lowercased().contains("critical")
                case .high:
                    let level = approval.riskLevel.lowercased()
                    return level.contains("critical") || level.contains("high")
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
                let lhsRisk = approvalRank(lhs.riskLevel)
                let rhsRisk = approvalRank(rhs.riskLevel)
                if lhsRisk != rhsRisk {
                    return lhsRisk > rhsRisk
                }
                return lhs.requestedAt > rhs.requestedAt
            }
    }

    var body: some View {
        List {
            Section {
                ApprovalsScoreboard(vm: vm)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }

            Section("Filter") {
                Picker("Risk", selection: $filter) {
                    ForEach(ApprovalRiskFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if filteredApprovals.isEmpty && !vm.isLoading {
                Section("Approvals") {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Pending Approvals" : "No Search Results",
                        systemImage: "checkmark.shield",
                        description: Text(searchText.isEmpty ? "The current dashboard snapshot has no unresolved approval gates." : "Try a different agent, tool, or action query.")
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

    private func approvalRank(_ riskLevel: String) -> Int {
        let normalized = riskLevel.lowercased()
        if normalized.contains("critical") {
            return 3
        }
        if normalized.contains("high") {
            return 2
        }
        if normalized.contains("medium") {
            return 1
        }
        return 0
    }
}

private struct ApprovalsScoreboard: View {
    let vm: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatBadge(
                value: "\(vm.pendingApprovalCount)",
                label: "Pending",
                icon: "checkmark.shield",
                color: vm.pendingApprovalCount > 0 ? .red : .green
            )
            StatBadge(
                value: "\(criticalCount)",
                label: "Critical",
                icon: "xmark.shield",
                color: criticalCount > 0 ? .red : .secondary
            )
            StatBadge(
                value: "\(highCount)",
                label: "High+",
                icon: "exclamationmark.shield",
                color: highCount > 0 ? .orange : .secondary
            )
            StatBadge(
                value: "\(agentCount)",
                label: "Agents",
                icon: "cpu",
                color: agentCount > 0 ? .orange : .secondary
            )
        }
        .padding(.horizontal)
    }

    private var criticalCount: Int {
        vm.approvals.filter { $0.riskLevel.lowercased().contains("critical") }.count
    }

    private var highCount: Int {
        vm.approvals.filter {
            let risk = $0.riskLevel.lowercased()
            return risk.contains("critical") || risk.contains("high")
        }.count
    }

    private var agentCount: Int {
        Set(vm.approvals.map(\.agentId)).count
    }
}
