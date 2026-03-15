import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @Environment(\.dependencies) private var deps
    @State private var budgetDetail: AgentBudgetDetail?
    @State private var agentDetailSnapshot: AgentDetailSnapshot?
    @State private var sessionSnapshot: AgentSessionSnapshot?
    @State private var agentSessions: [SessionInfo] = []
    @State private var agentMemory: [AgentMemoryEntry] = []
    @State private var agentFiles: [AgentWorkspaceFileSummary] = []
    @State private var agentDeliveries: [DeliveryReceipt] = []
    @State private var agentProfileSummary: ToolProfileSummary?
    @State private var agentToolFilters: AgentToolFilters?
    @State private var agentSkills: AgentAssignmentScope?
    @State private var agentMCPServers: AgentAssignmentScope?
    @State private var pendingApprovalAction: ApprovalDecisionAction?
    @State private var approvalActionInFlightID: String?
    @State private var pendingSessionAction: AgentSessionControlAction?
    @State private var sessionActionInFlightID: String?
    @State private var editingSession: SessionInfo?
    @State private var sessionLabelDraft = ""
    @State private var pendingDeleteSession: SessionInfo?
    @State private var sessionCatalogActionInFlightID: String?
    @State private var operatorNotice: OperatorActionNotice?
    @State private var showCreateSessionSheet = false
    @State private var showFindSessionSheet = false
    @State private var newSessionLabel = ""
    @State private var sessionLookupLabel = ""
    @State private var sessionLookupResult: SessionLabelLookupResult?
    @State private var sessionLookupError: String?
    @State private var isCreatingSession = false
    @State private var isLookingUpSession = false
    @State private var showChat = false
    @State private var isLoadingBudget = true
    @State private var isLoadingAgentSnapshot = true
    @State private var isLoadingSession = true
    @State private var isLoadingSessions = true
    @State private var isLoadingMemory = true
    @State private var isLoadingFiles = true
    @State private var isLoadingDeliveries = true
    @State private var isLoadingProfile = true
    @State private var isLoadingCapabilities = true

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

    private var currentSessionID: String? {
        sessionSnapshot?.sessionId
    }

    private var currentSessionInfo: SessionInfo? {
        guard let currentSessionID else { return nil }
        return agentSessions.first { $0.sessionId == currentSessionID }
    }

    private var modelDiagnostic: AgentModelDiagnostic? {
        deps.dashboardViewModel.modelDiagnostic(for: agent)
    }

    private var requestedModelReference: String? {
        deps.dashboardViewModel.requestedModelReference(for: agent)
    }

    private var resolvedAlias: ModelAliasEntry? {
        deps.dashboardViewModel.resolvedAlias(for: agent)
    }

    private var resolvedCatalogModel: CatalogModel? {
        deps.dashboardViewModel.resolvedCatalogModel(for: agent)
    }

    private var hasModelResolution: Bool {
        requestedModelReference != nil || resolvedAlias != nil || resolvedCatalogModel != nil
    }

    private var providerMatchesResolvedModel: Bool? {
        guard let declaredProvider = normalizedProvider(agent.modelProvider),
              let catalogProvider = resolvedCatalogModel?.provider
        else {
            return nil
        }
        return declaredProvider.compare(catalogProvider, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private var integrationSearchText: String {
        requestedModelReference ?? resolvedCatalogModel?.id ?? agent.id
    }

    private var failedDeliveryCount: Int {
        agentDeliveries.filter { $0.status == .failed }.count
    }

    private var unsettledDeliveryCount: Int {
        agentDeliveries.filter { $0.status == .sent || $0.status == .bestEffort }.count
    }

    private var missingWorkspaceFileCount: Int {
        agentFiles.filter { !$0.exists }.count
    }

    private var diagnosticsShareText: String {
        let structuredMemoryCount = agentMemory.filter(\.isStructured).count
        let diagnosticsModelLabel = requestedModelReference ?? agent.modelName ?? String(localized: "Unknown")
        let currentSessionLabel = currentSessionInfo?.label?.isEmpty == false
            ? currentSessionInfo?.label
            : currentSessionID.map { String($0.prefix(8)) }
        let diagnosticsSessionLabel = currentSessionLabel ?? String(localized: "Unavailable")

        let lines = [
            String(localized: "LibreFang Agent Diagnostics"),
            String(localized: "Agent: \(agent.name)"),
            String(localized: "State: \(agent.stateLabel)"),
            String(localized: "Model: \(diagnosticsModelLabel)"),
            String(localized: "Current session: \(diagnosticsSessionLabel)"),
            String(localized: "Pending approvals: \(agentApprovals.count)"),
            String(localized: "Session inventory: \(agentSessions.count)"),
            String(localized: "Memory keys: \(agentMemory.count)"),
            String(localized: "Structured memory: \(structuredMemoryCount)"),
            String(localized: "Identity files missing: \(missingWorkspaceFileCount)"),
            String(localized: "Delivery failures: \(failedDeliveryCount)"),
            String(localized: "Unsettled deliveries: \(unsettledDeliveryCount)"),
            String(localized: "Recent audit events: \(agentRecentEvents.count)")
        ]

        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            identitySection
            statusSection
            modelResolutionSection
            configSnapshotSection
            approvalsSection
            budgetSections
            sessionSections
            memorySection
            deliveriesSection
            filesSection
            recentAuditSection
            actionsSection
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(
                    item: diagnosticsShareText,
                    preview: SharePreview(
                        String(localized: "\(agent.name) Diagnostics"),
                        image: Image(systemName: "stethoscope")
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }

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
            await loadAgentSnapshot()
            await loadSession()
            await loadSessions()
            await loadMemory()
            await loadDeliveries()
            await loadFiles()
            await loadProfile()
            await loadCapabilities()
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: deps.makeChatViewModel(for: agent))
            }
        }
        .sheet(isPresented: $showCreateSessionSheet) {
            NavigationStack {
                Form {
                    Section("New Session") {
                        TextField("Optional label", text: $newSessionLabel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("A fresh session is useful when you need a clean operator context without resetting the existing thread.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Fresh Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCreateSessionSheet = false
                        }
                        .disabled(isCreatingSession)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await createFreshSession() }
                        } label: {
                            if isCreatingSession {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Create")
                            }
                        }
                        .disabled(isCreatingSession)
                    }
                }
            }
        }
        .sheet(isPresented: $showFindSessionSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("incident_review", text: $sessionLookupLabel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task { await lookupSessionByLabel() }
                        } label: {
                            if isLookingUpSession {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Find Session", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(isLookingUpSession || sessionLookupLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("Session Label")
                    } footer: {
                        Text("LibreFang resolves labels server-side for this agent, so this works even when the current inventory is stale.")
                    }

                    if let sessionLookupResult {
                        Section("Result") {
                            LabeledContent("Session") {
                                Text((sessionLookupResult.label?.isEmpty == false ? sessionLookupResult.label : nil) ?? String(sessionLookupResult.sessionId.prefix(8)))
                                    .foregroundStyle(.secondary)
                            }
                            LabeledContent("Messages") {
                                Text(sessionLookupResult.messageCount.formatted())
                                    .monospacedDigit()
                            }

                            if sessionLookupResult.sessionId == currentSessionID {
                                Label("This is already the active session.", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    pendingSessionAction = .switchSession(
                                        agentID: agent.id,
                                        agentName: agent.name,
                                        session: SessionInfo(
                                            sessionId: sessionLookupResult.sessionId,
                                            agentId: sessionLookupResult.agentId,
                                            messageCount: sessionLookupResult.messageCount,
                                            createdAt: "",
                                            label: sessionLookupResult.label
                                        )
                                    )
                                    showFindSessionSheet = false
                                } label: {
                                    Label("Switch To This Session", systemImage: "arrow.triangle.swap")
                                }
                            }
                        }
                    } else if let sessionLookupError {
                        Section("Result") {
                            Text(sessionLookupError)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Find Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showFindSessionSheet = false
                        }
                    }
                }
            }
        }
        .sheet(item: $editingSession) { session in
            NavigationStack {
                Form {
                    Section {
                        TextField("Optional label", text: $sessionLabelDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("Clear the field to remove the label. Labeled sessions are easier to hand off and recover later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Session Label")
                    } footer: {
                        Text(sessionDisplayTitle(session))
                    }
                }
                .navigationTitle("Edit Label")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingSession = nil
                        }
                        .disabled(isCatalogActionBusy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await saveSessionLabel(for: session) }
                        } label: {
                            if sessionCatalogActionInFlightID == "label:\(session.sessionId)" {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(isCatalogActionBusy)
                    }
                }
            }
        }
        .confirmationDialog(
            pendingApprovalAction?.title ?? "",
            isPresented: approvalActionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingApprovalAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performApprovalAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .confirmationDialog(
            pendingSessionAction?.title ?? "",
            isPresented: sessionActionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingSessionAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                Task { await performSessionAction(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .confirmationDialog(
            "Delete Session",
            isPresented: deleteSessionConfirmationPresented,
            titleVisibility: .visible,
            presenting: pendingDeleteSession
        ) { session in
            Button("Delete Session", role: .destructive) {
                Task { await deleteSession(session) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Remove \(sessionDisplayTitle(session)) from this agent history? This cannot be undone.")
        }
        .alert(item: $operatorNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var identitySection: some View {
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
    }

    private var statusSection: some View {
        Section("Status") {
            DetailRow(icon: "power", label: "State", value: agent.stateLabel, valueColor: stateColor)
            DetailRow(icon: "gearshape.2", label: "Mode", value: agent.mode)
            DetailRow(icon: "checkmark.circle", label: "Ready", value: agent.ready ? String(localized: "Yes") : String(localized: "No"),
                      valueColor: agent.ready ? .green : .orange)
            if let provider = agent.modelProvider {
                DetailRow(icon: "cloud", label: "Provider", value: provider)
            }
            if let model = agent.modelName {
                DetailRow(icon: "cpu", label: "Model", value: model)
            }
            if let modelDiagnostic {
                DetailRow(
                    icon: "square.stack.3d.up.slash",
                    label: "Catalog Check",
                    value: modelDiagnostic.issueSummary,
                    valueColor: .orange
                )
                if let resolvedModel = modelDiagnostic.resolvedModel {
                    DetailRow(
                        icon: "square.stack.3d.up",
                        label: "Resolved Model",
                        value: resolvedModel.id
                    )
                }
            }
            if let tier = agent.modelTier {
                DetailRow(icon: "star", label: "Tier", value: tier)
            }
            if let auth = agent.authStatus {
                DetailRow(
                    icon: "lock",
                    label: "Auth",
                    value: agent.authStatusLabel ?? auth,
                    valueColor: auth == "configured" ? .green : .red
                )
            }
            if !isLoadingDeliveries {
                DetailRow(
                    icon: "paperplane",
                    label: "Delivery Check",
                    value: deliveryStatusSummary,
                    valueColor: deliveryStatusColor
                )
            }
            if !isLoadingFiles && !agentFiles.isEmpty {
                DetailRow(
                    icon: "doc.badge.gearshape",
                    label: "Workspace Check",
                    value: missingWorkspaceFileCount == 0
                        ? String(localized: "Identity files present")
                        : String(localized: "\(missingWorkspaceFileCount) missing"),
                    valueColor: missingWorkspaceFileCount == 0 ? .green : .orange
                )
            }
            if !isLoadingCapabilities {
                if let agentToolFilters {
                    DetailRow(
                        icon: "slider.horizontal.3",
                        label: "Tool Scope",
                        value: toolScopeSummary(agentToolFilters),
                        valueColor: agentToolFilters.isRestricted ? .orange : .green
                    )
                }
                if let agentSkills {
                    DetailRow(
                        icon: "sparkles",
                        label: "Skills",
                        value: assignmentSummary(agentSkills, emptyLabel: String(localized: "All skills")),
                        valueColor: agentSkills.usesAllowlist ? .orange : .green
                    )
                }
                if let agentMCPServers {
                    DetailRow(
                        icon: "shippingbox",
                        label: "MCP Scope",
                        value: assignmentSummary(agentMCPServers, emptyLabel: String(localized: "All servers")),
                        valueColor: agentMCPServers.usesAllowlist ? .orange : .green
                    )
                }
                NavigationLink {
                    AgentCapabilitiesView(
                        agent: agent,
                        initialToolFilters: agentToolFilters,
                        initialSkills: agentSkills,
                        initialMCPServers: agentMCPServers
                    )
                } label: {
                    Label("Inspect Capabilities", systemImage: "slider.horizontal.3")
                }
            }
            if let profile = agent.profile {
                NavigationLink {
                    ToolProfilesView(selectedProfileName: profile)
                } label: {
                    DetailRow(icon: "person", label: "Profile", value: profile)
                }
                if isLoadingProfile {
                    LabeledContent("Tools") {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if let agentProfileSummary {
                    LabeledContent("Tools") {
                        Text(agentProfileSummary.tools.count.formatted())
                            .foregroundStyle(agentProfileSummary.tools.isEmpty ? Color.secondary : Color.blue)
                            .monospacedDigit()
                    }
                    if !agentProfileSummary.tools.isEmpty {
                        LabeledContent("Profile Tools") {
                            Text(profileToolPreview(agentProfileSummary))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } else {
                    DetailRow(
                        icon: "person.crop.circle.badge.exclamationmark",
                        label: "Profile Check",
                        value: String(localized: "Unknown profile"),
                        valueColor: .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var modelResolutionSection: some View {
        if hasModelResolution {
            Section {
                if let requestedModelReference {
                    DetailRow(icon: "cpu", label: "Requested", value: requestedModelReference)
                }

                if let resolvedAlias {
                    DetailRow(
                        icon: "arrow.left.arrow.right",
                        label: "Alias",
                        value: "\(resolvedAlias.alias) -> \(resolvedAlias.modelId)"
                    )
                }

                if let resolvedCatalogModel {
                    DetailRow(
                        icon: "square.stack.3d.up",
                        label: "Catalog Model",
                        value: resolvedCatalogModel.id
                    )
                    DetailRow(
                        icon: "cloud",
                        label: "Catalog Provider",
                        value: resolvedCatalogModel.provider
                    )
                    DetailRow(
                        icon: "checkmark.circle",
                        label: "Availability",
                        value: resolvedCatalogModel.available
                            ? String(localized: "Available")
                            : String(localized: "Unavailable"),
                        valueColor: resolvedCatalogModel.available ? .green : .orange
                    )
                    if let providerMatchesResolvedModel {
                        DetailRow(
                            icon: "arrow.triangle.branch",
                            label: "Provider Match",
                            value: providerMatchesResolvedModel
                                ? String(localized: "Match")
                                : String(localized: "Drift"),
                            valueColor: providerMatchesResolvedModel ? .green : .orange
                        )
                    }
                    LabeledContent("Capabilities") {
                        Text(capabilitySummary(for: resolvedCatalogModel))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Context") {
                        Text(contextSummary(for: resolvedCatalogModel))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } else if requestedModelReference != nil {
                    DetailRow(
                        icon: "questionmark.square.dashed",
                        label: "Catalog Match",
                        value: String(localized: "No match found"),
                        valueColor: .orange
                    )
                }

                NavigationLink {
                    IntegrationsView(initialSearchText: integrationSearchText)
                } label: {
                    Label("Inspect Integration Diagnostics", systemImage: "square.3.layers.3d.down.forward")
                }
            } header: {
                Text("Model Resolution")
            } footer: {
                Text(
                    modelDiagnostic?.detail
                        ?? String(localized: "This section resolves the agent's requested model through LibreFang's alias map and active model catalog.")
                )
            }
        }
    }

    @ViewBuilder
    private var configSnapshotSection: some View {
        if let agentDetailSnapshot, hasConfigSnapshotContent(agentDetailSnapshot) {
            Section {
                if !agentDetailSnapshot.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(agentDetailSnapshot.description)
                    }
                    .padding(.vertical, 2)
                }

                if !agentDetailSnapshot.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(agentDetailSnapshot.tags.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if !agentDetailSnapshot.fallbackModels.isEmpty {
                    LabeledContent("Fallbacks") {
                        Text("\(agentDetailSnapshot.fallbackModels.count)")
                            .monospacedDigit()
                    }

                    ForEach(agentDetailSnapshot.fallbackModels.prefix(3), id: \.id) { fallback in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(fallback.provider)/\(fallback.model)")
                                .font(.subheadline.weight(.medium))

                            if let match = fallbackCatalogModel(for: fallback) {
                                Text(
                                    match.available
                                        ? String(localized: "Catalog available")
                                        : String(localized: "Catalog unavailable")
                                )
                                    .font(.caption)
                                    .foregroundStyle(match.available ? .green : .orange)
                            } else {
                                Text("No catalog match")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if agentDetailSnapshot.fallbackModels.count > 3 {
                        Text("Showing 3 of \(agentDetailSnapshot.fallbackModels.count) fallback models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !agentDetailSnapshot.capabilities.tools.isEmpty {
                    DetailRow(
                        icon: "wrench.and.screwdriver",
                        label: "Manifest Tools",
                        value: String(localized: "\(agentDetailSnapshot.capabilities.tools.count) grants")
                    )
                }

                if !agentDetailSnapshot.capabilities.network.isEmpty {
                    DetailRow(
                        icon: "network",
                        label: "Network Grants",
                        value: String(localized: "\(agentDetailSnapshot.capabilities.network.count) hosts")
                    )
                }
            } header: {
                Text("Config Snapshot")
            } footer: {
                Text("This is the read-only manifest snapshot from LibreFang. Use it to compare runtime behavior against fallback routing and capability grants.")
            }
        } else if isLoadingAgentSnapshot {
            Section("Config Snapshot") {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var approvalsSection: some View {
        if !agentApprovals.isEmpty {
            Section("Approvals") {
                ForEach(agentApprovals) { approval in
                    ApprovalOperatorRow(
                        approval: approval,
                        isBusy: approvalActionInFlightID == approval.id,
                        onApprove: {
                            pendingApprovalAction = .approve(approval)
                        },
                        onReject: {
                            pendingApprovalAction = .reject(approval)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var budgetSections: some View {
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
    }

    @ViewBuilder
    private var sessionSections: some View {
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
            sessionSummarySection(snapshot)
            sessionControlsSection
            sessionInventorySection
            recentActivitySection(snapshot)
        }
    }

    private func sessionSummarySection(_ snapshot: AgentSessionSnapshot) -> some View {
        Section("Session") {
            LabeledContent("Label") {
                Text((snapshot.label?.isEmpty == false ? snapshot.label : nil) ?? String(localized: "Current"))
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
    }

    private var sessionControlsSection: some View {
        Section {
            Button {
                showCreateSessionSheet = true
            } label: {
                Label("Start Fresh Session", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(isCreatingSession || hasActiveSessionOperation)

            if let currentSessionInfo {
                Button {
                    startEditingLabel(for: currentSessionInfo)
                } label: {
                    Label("Relabel Current Session", systemImage: "tag")
                }
                .disabled(hasActiveSessionOperation)
            }

            Button {
                sessionLookupResult = nil
                sessionLookupError = nil
                sessionLookupLabel = currentSessionInfo?.label ?? ""
                showFindSessionSheet = true
            } label: {
                Label("Find Session by Label", systemImage: "magnifyingglass")
            }
            .disabled(hasActiveSessionOperation)

            Button {
                pendingSessionAction = .compact(agentID: agent.id, agentName: agent.name)
            } label: {
                Label("Compact Current Session", systemImage: "arrow.down.doc")
            }
            .disabled(hasActiveSessionOperation)

            Button(role: .destructive) {
                pendingSessionAction = .reset(agentID: agent.id, agentName: agent.name)
            } label: {
                Label("Reset Current Session", systemImage: "trash")
            }
            .disabled(hasActiveSessionOperation)

            Button(role: .destructive) {
                pendingSessionAction = .stopRun(agentID: agent.id, agentName: agent.name)
            } label: {
                Label("Stop Active Run", systemImage: "stop.circle")
            }
            .disabled(hasActiveSessionOperation)
        } header: {
            Text("Session Controls")
        } footer: {
            Text("These commands affect the active session on the server. Use them after confirming the current agent state.")
        }
    }

    @ViewBuilder
    private var sessionInventorySection: some View {
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
                    AgentSessionInventoryRow(
                        item: item,
                        isCurrentSession: currentSessionID == item.session.sessionId,
                        isBusy: isSessionBusy(item.session),
                        onSwitch: currentSessionID == item.session.sessionId ? nil : {
                            pendingSessionAction = .switchSession(
                                agentID: agent.id,
                                agentName: agent.name,
                                session: item.session
                            )
                        },
                        onEditLabel: {
                            startEditingLabel(for: item.session)
                        },
                        onDelete: currentSessionID == item.session.sessionId ? nil : {
                            pendingDeleteSession = item.session
                        }
                    )
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
    }

    private func recentActivitySection(_ snapshot: AgentSessionSnapshot) -> some View {
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

    private var memorySection: some View {
        Section {
            if isLoadingMemory {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else {
                LabeledContent("Keys") {
                    Text(agentMemory.count.formatted())
                        .monospacedDigit()
                }

                LabeledContent("Structured") {
                    let structured = agentMemory.filter(\.isStructured).count
                    Text(structured.formatted())
                        .foregroundStyle(structured > 0 ? .orange : .secondary)
                        .monospacedDigit()
                }

                if agentMemory.isEmpty {
                    Text("No agent memory keys stored.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agentMemory.prefix(3)) { entry in
                        AgentMemorySummaryRow(entry: entry)
                    }
                }

                NavigationLink {
                    AgentMemoryView(agent: agent, initialEntries: agentMemory) { updatedEntries in
                        agentMemory = updatedEntries
                        isLoadingMemory = false
                    }
                } label: {
                    Label("Open Agent Memory", systemImage: "internaldrive")
                }
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("Agent memory is durable KV state shared across runs. Use it when the current session does not explain agent behavior.")
        }
    }

    private var filesSection: some View {
        Section {
            if isLoadingFiles {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else {
                let existingFiles = agentFiles.filter(\.exists)

                LabeledContent("Identity Files") {
                    Text("\(existingFiles.count)/\(agentFiles.count)")
                        .foregroundStyle(existingFiles.count < agentFiles.count ? .orange : .green)
                        .monospacedDigit()
                }

                ForEach(agentFiles.filter(\.exists).prefix(3)) { file in
                    AgentFileSummaryRow(file: file)
                }

                if missingWorkspaceFileCount > 0 {
                    NavigationLink {
                        AgentFilesView(agent: agent, initialFiles: agentFiles, initialScope: .missing)
                    } label: {
                        Label("Review Missing Identity Files", systemImage: "doc.badge.gearshape")
                    }
                }

                NavigationLink {
                    AgentFilesView(agent: agent, initialFiles: agentFiles)
                } label: {
                    Label("Inspect Workspace Identity", systemImage: "doc.text.magnifyingglass")
                }
            }
        } header: {
            Text("Workspace")
        } footer: {
            Text("SOUL.md, IDENTITY.md, AGENTS.md, MEMORY.md, and related files often explain why an agent is behaving differently from its live session.")
        }
    }

    private var deliveriesSection: some View {
        Section {
            if isLoadingDeliveries {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else {
                let failed = agentDeliveries.filter { $0.status == .failed }.count
                let delivered = agentDeliveries.filter { $0.status == .delivered }.count

                LabeledContent("Receipts") {
                    Text(agentDeliveries.count.formatted())
                        .monospacedDigit()
                }
                LabeledContent("Delivered") {
                    Text(delivered.formatted())
                        .foregroundStyle(delivered > 0 ? .green : .secondary)
                        .monospacedDigit()
                }
                LabeledContent("Failed") {
                    Text(failed.formatted())
                        .foregroundStyle(failed > 0 ? .red : .secondary)
                        .monospacedDigit()
                }

                if agentDeliveries.isEmpty {
                    Text("No recent delivery receipts.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(agentDeliveries.prefix(3)) { receipt in
                        AgentDeliverySummaryRow(receipt: receipt)
                    }
                }

                if failedDeliveryCount > 0 {
                    NavigationLink {
                        AgentDeliveriesView(agent: agent, initialReceipts: agentDeliveries, initialScope: .failed)
                    } label: {
                        Label("Review Failed Deliveries", systemImage: "exclamationmark.triangle")
                    }
                }

                if unsettledDeliveryCount > 0 {
                    NavigationLink {
                        AgentDeliveriesView(agent: agent, initialReceipts: agentDeliveries, initialScope: .unsettled)
                    } label: {
                        Label("Review Unsettled Deliveries", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }

                NavigationLink {
                    AgentDeliveriesView(agent: agent, initialReceipts: agentDeliveries)
                } label: {
                    Label("Inspect Delivery Receipts", systemImage: "paperplane")
                }
            }
        } header: {
            Text("Deliveries")
        } footer: {
            Text("Use delivery receipts to confirm whether outbound channel sends actually reached a recipient or failed downstream.")
        }
    }

    @ViewBuilder
    private var recentAuditSection: some View {
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
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                deps.agentWatchlistStore.toggle(agent)
            } label: {
                Label(
                    isWatched
                        ? String(localized: "Remove From Watchlist")
                        : String(localized: "Add To Watchlist"),
                    systemImage: isWatched ? "star.slash" : "star"
                )
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

            NavigationLink {
                AgentDeliveriesView(agent: agent, initialReceipts: agentDeliveries)
            } label: {
                Label("Inspect Delivery Receipts", systemImage: "paperplane")
            }

            NavigationLink {
                AgentCapabilitiesView(
                    agent: agent,
                    initialToolFilters: agentToolFilters,
                    initialSkills: agentSkills,
                    initialMCPServers: agentMCPServers
                )
            } label: {
                Label("Inspect Capabilities", systemImage: "slider.horizontal.3")
            }

            if let profile = agent.profile {
                NavigationLink {
                    ToolProfilesView(selectedProfileName: profile)
                } label: {
                    Label("Inspect Tool Profile", systemImage: "person.crop.rectangle.stack")
                }
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

    private func normalizedProvider(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hasConfigSnapshotContent(_ snapshot: AgentDetailSnapshot) -> Bool {
        !snapshot.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !snapshot.tags.isEmpty
            || !snapshot.fallbackModels.isEmpty
            || !snapshot.capabilities.tools.isEmpty
            || !snapshot.capabilities.network.isEmpty
    }

    private func fallbackCatalogModel(for fallback: AgentFallbackModel) -> CatalogModel? {
        deps.dashboardViewModel.catalogModels.first { model in
            model.provider.compare(fallback.provider, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
            model.id.compare(fallback.model, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private var deliveryStatusSummary: String {
        if failedDeliveryCount > 0 {
            return String(localized: "\(failedDeliveryCount) failed")
        }
        if unsettledDeliveryCount > 0 {
            return String(localized: "\(unsettledDeliveryCount) unsettled")
        }
        if !agentDeliveries.isEmpty {
            return String(localized: "No recent failures")
        }
        return String(localized: "No recent sends")
    }

    private var deliveryStatusColor: Color {
        if failedDeliveryCount > 0 { return .red }
        if unsettledDeliveryCount > 0 { return .orange }
        if !agentDeliveries.isEmpty { return .green }
        return .secondary
    }

    private func profileToolPreview(_ profile: ToolProfileSummary) -> String {
        let preview = profile.tools.prefix(4).joined(separator: " • ")
        if profile.tools.count > 4 {
            return "\(preview) +\(profile.tools.count - 4)"
        }
        return preview
    }

    private func capabilitySummary(for model: CatalogModel) -> String {
        var capabilities: [String] = []
        if model.supportsTools {
            capabilities.append(String(localized: "tools"))
        }
        if model.supportsVision {
            capabilities.append(String(localized: "vision"))
        }
        if model.supportsStreaming {
            capabilities.append(String(localized: "streaming"))
        }
        return capabilities.isEmpty
            ? String(localized: "No extra capabilities advertised")
            : capabilities.joined(separator: " • ")
    }

    private func contextSummary(for model: CatalogModel) -> String {
        let contextWindow = model.contextWindow.map { String(localized: "\($0.formatted()) ctx") }
        let maxOutput = model.maxOutputTokens.map { String(localized: "\($0.formatted()) out") }
        return [contextWindow, maxOutput]
            .compactMap { $0 }
            .joined(separator: " • ")
            .ifEmpty(String(localized: "Catalog did not publish token limits"))
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
    private func loadAgentSnapshot() async {
        defer { isLoadingAgentSnapshot = false }
        do {
            agentDetailSnapshot = try await deps.apiClient.agentDetail(agentId: agent.id)
        } catch {
            agentDetailSnapshot = nil
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

    @MainActor
    private func loadMemory() async {
        defer { isLoadingMemory = false }
        do {
            agentMemory = (try await deps.apiClient.agentMemory(agentId: agent.id)).kvPairs
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        } catch {
            agentMemory = []
        }
    }

    @MainActor
    private func loadFiles() async {
        defer { isLoadingFiles = false }
        do {
            agentFiles = (try await deps.apiClient.agentFiles(agentId: agent.id)).files
                .sorted { lhs, rhs in
                    if lhs.exists != rhs.exists {
                        return lhs.exists && !rhs.exists
                    }
                    return lhs.name < rhs.name
                }
        } catch {
            agentFiles = []
        }
    }

    @MainActor
    private func loadDeliveries() async {
        defer { isLoadingDeliveries = false }
        do {
            agentDeliveries = (try await deps.apiClient.agentDeliveries(agentId: agent.id, limit: 20)).receipts
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            agentDeliveries = []
        }
    }

    @MainActor
    private func loadProfile() async {
        defer { isLoadingProfile = false }
        guard let profile = agent.profile else {
            agentProfileSummary = nil
            return
        }

        do {
            agentProfileSummary = try await deps.apiClient.profile(name: profile)
        } catch {
            agentProfileSummary = nil
        }
    }

    @MainActor
    private func loadCapabilities() async {
        defer { isLoadingCapabilities = false }

        do {
            async let toolFilters = deps.apiClient.agentToolFilters(agentId: agent.id)
            async let skills = deps.apiClient.agentSkills(agentId: agent.id)
            async let mcpServers = deps.apiClient.agentMCPServers(agentId: agent.id)

            agentToolFilters = try await toolFilters
            agentSkills = try await skills
            agentMCPServers = try await mcpServers
        } catch {
            agentToolFilters = nil
            agentSkills = nil
            agentMCPServers = nil
        }
    }

    private func toolScopeSummary(_ filters: AgentToolFilters) -> String {
        switch (filters.toolAllowlist.isEmpty, filters.toolBlocklist.isEmpty) {
        case (true, true):
            return String(localized: "All tools")
        case (false, true):
            return String(localized: "\(filters.toolAllowlist.count) allowed")
        case (true, false):
            return String(localized: "\(filters.toolBlocklist.count) blocked")
        case (false, false):
            return String(localized: "\(filters.toolAllowlist.count) allow / \(filters.toolBlocklist.count) block")
        }
    }

    private func assignmentSummary(_ assignment: AgentAssignmentScope, emptyLabel: String) -> String {
        assignment.usesAllowlist
            ? String(localized: "\(assignment.assigned.count) assigned")
            : emptyLabel
    }

    private var approvalActionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingApprovalAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingApprovalAction = nil
                }
            }
        )
    }

    private var sessionActionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingSessionAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSessionAction = nil
                }
            }
        )
    }

    private var deleteSessionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteSession != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteSession = nil
                }
            }
        )
    }

    private var hasActiveSessionOperation: Bool {
        sessionActionInFlightID != nil || sessionCatalogActionInFlightID != nil
    }

    private var isCatalogActionBusy: Bool {
        sessionCatalogActionInFlightID != nil
    }

    private func isSessionBusy(_ session: SessionInfo) -> Bool {
        sessionActionInFlightID == "switch:\(agent.id):\(session.id)"
            || sessionCatalogActionInFlightID == "label:\(session.sessionId)"
            || sessionCatalogActionInFlightID == "delete:\(session.sessionId)"
    }

    private func startEditingLabel(for session: SessionInfo) {
        sessionLabelDraft = session.label ?? ""
        editingSession = session
    }

    private func sessionDisplayTitle(_ session: SessionInfo) -> String {
        let trimmedLabel = (session.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        return String(session.sessionId.prefix(8))
    }

    @MainActor
    private func performApprovalAction(_ action: ApprovalDecisionAction) async {
        pendingApprovalAction = nil
        approvalActionInFlightID = action.approvalID
        defer { approvalActionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await deps.dashboardViewModel.refresh()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func performSessionAction(_ action: AgentSessionControlAction) async {
        pendingSessionAction = nil
        sessionActionInFlightID = action.id
        defer { sessionActionInFlightID = nil }

        do {
            let response = try await action.perform(using: deps.apiClient)
            await deps.dashboardViewModel.refresh()
            isLoadingSession = true
            isLoadingSessions = true
            await loadSession()
            await loadSessions()
            operatorNotice = action.successNotice(from: response)
        } catch {
            operatorNotice = OperatorActionNotice(
                title: action.title,
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func createFreshSession() async {
        isCreatingSession = true
        defer { isCreatingSession = false }

        let trimmedLabel = newSessionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let session = try await deps.apiClient.createSession(
                agentId: agent.id,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel
            )
            let switchResponse = try await deps.apiClient.switchSession(agentId: agent.id, sessionId: session.sessionId)
            await deps.dashboardViewModel.refresh()
            isLoadingSession = true
            isLoadingSessions = true
            await loadSession()
            await loadSessions()
            showCreateSessionSheet = false
            newSessionLabel = ""
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Fresh Session"),
                message: switchResponse.message ?? String(localized: "Created and switched to the new session.")
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Fresh Session"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func lookupSessionByLabel() async {
        let trimmedLabel = sessionLookupLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return }

        isLookingUpSession = true
        defer { isLookingUpSession = false }

        do {
            sessionLookupResult = try await deps.apiClient.findSessionByLabel(agentId: agent.id, label: trimmedLabel)
            sessionLookupError = nil
        } catch {
            sessionLookupResult = nil
            sessionLookupError = error.localizedDescription
        }
    }

    @MainActor
    private func saveSessionLabel(for session: SessionInfo) async {
        let trimmedLabel = sessionLabelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionCatalogActionInFlightID = "label:\(session.sessionId)"
        defer { sessionCatalogActionInFlightID = nil }

        do {
            let response = try await deps.apiClient.setSessionLabel(
                id: session.sessionId,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel
            )
            editingSession = nil
            sessionLabelDraft = ""
            await deps.dashboardViewModel.refresh()
            isLoadingSession = true
            isLoadingSessions = true
            await loadSession()
            await loadSessions()
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Session Label"),
                message: response.message
                    ?? (trimmedLabel.isEmpty
                        ? String(localized: "Session label cleared.")
                        : String(localized: "Session label updated."))
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Session Label"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteSession(_ session: SessionInfo) async {
        pendingDeleteSession = nil
        sessionCatalogActionInFlightID = "delete:\(session.sessionId)"
        defer { sessionCatalogActionInFlightID = nil }

        do {
            let response = try await deps.apiClient.deleteSession(id: session.sessionId)
            await deps.dashboardViewModel.refresh()
            isLoadingSession = true
            isLoadingSessions = true
            await loadSession()
            await loadSessions()
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Delete Session"),
                message: response.message ?? String(localized: "Session deleted.")
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: String(localized: "Delete Session"),
                message: error.localizedDescription
            )
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let icon: String
    let label: LocalizedStringResource
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
    let label: LocalizedStringResource
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
                    Text(toolSummaryLabel(toolCount))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(displayText)
                .font(.subheadline)
                .lineLimit(4)

            if let images = message.images, !images.isEmpty {
                Text(imageAttachmentSummaryLabel(images.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images) { image in
                            NavigationLink {
                                UploadAssetView(image: image)
                            } label: {
                                Label(image.filename, systemImage: "photo")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var roleTitle: String {
        switch message.role {
        case "User":
            String(localized: "User")
        case "System":
            String(localized: "System")
        default:
            String(localized: "Agent")
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
            return images.count == 1
                ? String(localized: "1 image attachment")
                : String(localized: "\(images.count) image attachments")
        }
        return String(localized: "No message content")
    }

    private func toolSummaryLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 tool")
            : String(localized: "\(count) tools")
    }

    private func imageAttachmentSummaryLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 image attachment")
            : String(localized: "\(count) image attachments")
    }
}

private struct AgentSessionInventoryRow: View {
    let item: SessionAttentionItem
    let isCurrentSession: Bool
    let isBusy: Bool
    let onSwitch: (() -> Void)?
    let onEditLabel: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isCurrentSession {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else if let onSwitch {
                    Button {
                        onSwitch()
                    } label: {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Switch")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                    .disabled(isBusy)
                }
                if onEditLabel != nil || onDelete != nil {
                    Menu {
                        if let onEditLabel {
                            Button {
                                onEditLabel()
                            } label: {
                                Label("Edit Label", systemImage: "tag")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete Session", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isBusy)
                }
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

            Text(entry.localizedOutcomeLabel)
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

private struct AgentMemorySummaryRow: View {
    let entry: AgentMemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.key)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if entry.isStructured {
                    Text("Structured")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct AgentFileSummaryRow: View {
    let file: AgentWorkspaceFileSummary

    var body: some View {
        HStack {
            Text(file.name)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct AgentDeliverySummaryRow: View {
    let receipt: DeliveryReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(receipt.localizedChannelLabel)
                    .font(.subheadline.weight(.medium))
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
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch receipt.status {
        case .delivered:
            .green
        case .failed:
            .red
        case .bestEffort:
            .orange
        case .sent:
            .blue
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
