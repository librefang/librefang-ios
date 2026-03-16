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

    private var watchAccentColor: Color {
        PresentationTone.caution.color
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

    private var existingWorkspaceFileCount: Int {
        agentFiles.filter(\.exists).count
    }

    private var workspaceIdentitySummary: WorkspaceIdentitySummary {
        .summarize(existingCount: existingWorkspaceFileCount, totalCount: agentFiles.count)
    }

    private var providerAlignmentStatus: ProviderAlignmentStatus? {
        guard let providerMatchesResolvedModel else { return nil }
        return ProviderAlignmentStatus(isAligned: providerMatchesResolvedModel)
    }

    private var profileToolCountTone: PresentationTone {
        (agentProfileSummary?.tools.isEmpty == false) ? .positive : .neutral
    }

    private var sessionAttentionTone: PresentationTone {
        sessionItems.contains { $0.severity > 0 } ? .warning : .neutral
    }

    private var structuredMemoryTone: PresentationTone {
        agentMemory.contains { $0.isStructured } ? .warning : .neutral
    }

    private var deliveredReceiptTone: PresentationTone {
        agentDeliveries.contains { $0.status == .delivered } ? .positive : .neutral
    }

    private var failedReceiptTone: PresentationTone {
        agentDeliveries.contains { $0.status == .failed } ? .critical : .neutral
    }

    private var sessionIssueCount: Int {
        sessionItems.filter { $0.severity > 0 }.count
    }
    private var sessionControlActionCount: Int {
        5 + (currentSessionInfo == nil ? 0 : 1)
    }
    private var destructiveSessionActionCount: Int { 2 }
    private var visibleSessionInventoryCount: Int { min(sessionItems.count, 4) }

    private var diagnosticsSnapshotSummary: String {
        if failedDeliveryCount > 0 || missingWorkspaceFileCount > 0 {
            return String(localized: "This agent already has delivery or workspace issues surfaced on mobile.")
        }
        if !agentApprovals.isEmpty || sessionIssueCount > 0 {
            return String(localized: "Single-agent approvals and session pressure are visible before the deeper detail sections.")
        }
        return String(localized: "Single-agent diagnostics, runtime context, and operator actions stay grouped on this screen.")
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

    private var currentSessionBadgeText: String? {
        guard let currentSessionInfo else { return nil }
        return sessionDisplayTitle(currentSessionInfo)
    }

    private var profileBadgeText: String? {
        guard let profile = agent.profile else { return nil }
        return profile
    }

    private var monitoringSurfaceIssueCount: Int {
        agentApprovals.count + sessionIssueCount + failedDeliveryCount + missingWorkspaceFileCount
    }
    private var diagnosticsSectionCount: Int {
        [
            true,
            hasModelResolution,
            !agentApprovals.isEmpty,
            budgetDetail != nil,
            true,
            true,
            true,
            !agentRecentEvents.isEmpty
        ]
        .filter { $0 }
        .count
    }

    private var agentBudgetTone: PresentationTone {
        guard let budgetDetail else { return .neutral }
        let utilization = max(
            budgetDetail.hourly.pct,
            budgetDetail.daily.pct,
            budgetDetail.monthly.pct,
            budgetDetail.tokens.pct
        )
        return StatusPresentation.budgetUtilizationStatus(for: utilization)?.tone ?? .neutral
    }

    private var sessionSnapshotSummary: String {
        if sessionIssueCount > 0 {
            return String(localized: "Active session pressure stays visible before controls, inventory, and recent activity.")
        }
        return String(localized: "Keep the active session label, message volume, and context window visible before session controls.")
    }

    private var sessionSnapshotDetail: String {
        if let label = sessionSnapshot?.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return String(localized: "Current session label: \(label)")
        }
        return String(localized: "This agent is currently using an unlabeled session.")
    }

    private var budgetSnapshotSummary: String {
        guard let budgetDetail else {
            return String(localized: "Budget guardrails stay visible before the detailed spend rows.")
        }

        let maxUtilization = max(
            budgetDetail.hourly.pct,
            budgetDetail.daily.pct,
            budgetDetail.monthly.pct,
            budgetDetail.tokens.pct
        )

        if maxUtilization >= 0.9 {
            return String(localized: "Budget pressure stays visible before the detailed hourly, daily, monthly, and token rows.")
        }
        return String(localized: "Budget guardrails stay visible before the detailed spend rows.")
    }

    private var memorySnapshotSummary: String {
        if agentMemory.contains(where: \.isStructured) {
            return String(localized: "Structured memory stays visible before the key preview and deep memory route.")
        }
        if agentMemory.isEmpty {
            return String(localized: "Memory state stays visible before any durable keys exist.")
        }
        return String(localized: "Memory state stays visible before the key preview and deep memory route.")
    }

    private var workspaceSnapshotSummary: String {
        if missingWorkspaceFileCount > 0 {
            return String(localized: "Workspace identity drift stays visible before the file preview and deep workspace route.")
        }
        if agentFiles.isEmpty {
            return String(localized: "Workspace identity stays visible before the file inventory loads.")
        }
        return String(localized: "Workspace identity stays visible before the file preview and deep workspace route.")
    }

    private var deliveriesSnapshotSummary: String {
        if failedDeliveryCount > 0 || unsettledDeliveryCount > 0 {
            return String(localized: "Delivery pressure stays visible before the receipt preview and deep delivery route.")
        }
        if agentDeliveries.isEmpty {
            return String(localized: "Delivery state stays visible before any recent receipts exist.")
        }
        return String(localized: "Delivery state stays visible before the receipt preview and deep delivery route.")
    }

    var body: some View {
        List {
            identitySection
            controlDeckSection
            statusSection
            capabilitiesSection
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: diagnosticsShareText,
                        preview: SharePreview(
                            String(localized: "\(agent.name) Diagnostics"),
                            image: Image(systemName: "stethoscope")
                        )
                    ) {
                        Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                    }

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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(isWatched ? watchAccentColor : .primary)
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

    private var controlDeckSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                agentDiagnosticsStatusDeckCard
                AgentSectionInventoryDeck(
                    sectionCount: diagnosticsSectionCount,
                    issueCount: monitoringSurfaceIssueCount,
                    approvalCount: agentApprovals.count,
                    sessionCount: agentSessions.count,
                    memoryCount: agentMemory.count,
                    fileCount: agentFiles.count,
                    deliveryCount: agentDeliveries.count,
                    auditCount: agentRecentEvents.count,
                    hasBudget: budgetDetail != nil,
                    hasModelResolution: hasModelResolution
                )
                agentOperatorSurfaceDeckCard
            }
        } header: {
            Text("Controls")
        } footer: {
            Text("Keep the digest and next exits together before deeper diagnostics sections.")
        }
    }

    private var agentOperatorSurfaceDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSurfaceGroupCard(
                title: String(localized: "Primary"),
                detail: String(localized: "Keep the most likely next operator exits visible as compact shortcuts right below the agent digest.")
            ) {
                FlowLayout(spacing: 8) {
                    NavigationLink {
                        IncidentsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Incidents"),
                            systemImage: "bell.badge",
                            tone: monitoringSurfaceIssueCount > 0 ? .warning : .neutral,
                            badgeText: monitoringSurfaceIssueCount == 0 ? nil : String(localized: "\(monitoringSurfaceIssueCount) issues")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionsView(initialSearchText: agent.id, initialFilter: .all)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "rectangle.stack",
                            tone: sessionAttentionTone,
                            badgeText: currentSessionBadgeText ?? (sessionIssueCount == 0 ? nil : String(localized: "\(sessionIssueCount) issues"))
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentDeliveriesView(agent: agent, initialReceipts: agentDeliveries)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Receipts"),
                            systemImage: "paperplane",
                            tone: failedDeliveryCount > 0 ? .critical : deliveredReceiptTone,
                            badgeText: agentDeliveries.isEmpty
                                ? String(localized: "No receipts")
                                : String(localized: "\(agentDeliveries.count) receipts")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentFilesView(agent: agent, initialFiles: agentFiles)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Workspace"),
                            systemImage: "doc.text.magnifyingglass",
                            tone: workspaceIdentitySummary.tone,
                            badgeText: workspaceIdentitySummary.progressLabel
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentMemoryView(agent: agent, initialEntries: agentMemory) { updatedEntries in
                            agentMemory = updatedEntries
                            isLoadingMemory = false
                        }
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Memory"),
                            systemImage: "internaldrive",
                            tone: structuredMemoryTone,
                            badgeText: agentMemory.isEmpty ? String(localized: "Empty") : String(localized: "\(agentMemory.count) keys")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Support"),
                detail: String(localized: "Keep broader runtime, budget, and capability routes visible as a secondary shortcut rail.")
            ) {
                FlowLayout(spacing: 8) {
                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Runtime"),
                            systemImage: "server.rack"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tone: deps.dashboardViewModel.diagnosticsSummaryTone,
                            badgeText: deps.dashboardViewModel.diagnosticsConfigWarningCount > 0
                                ? (deps.dashboardViewModel.diagnosticsConfigWarningCount == 1
                                    ? String(localized: "1 warning")
                                    : String(localized: "\(deps.dashboardViewModel.diagnosticsConfigWarningCount) warnings"))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IntegrationsView(initialSearchText: integrationSearchText, initialScope: .attention)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Integrations"),
                            systemImage: "square.3.layers.3d.down.forward",
                            tone: modelDiagnostic?.statusTone ?? .neutral,
                            badgeText: requestedModelReference
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BudgetView()
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Budget"),
                            systemImage: "chart.bar",
                            tone: agentBudgetTone
                        )
                    }
                    .buttonStyle(.plain)

                    if !agentApprovals.isEmpty {
                        NavigationLink {
                            ApprovalsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Approvals"),
                                systemImage: "checkmark.shield",
                                tone: .critical,
                                badgeText: agentApprovals.count == 1 ? String(localized: "1 approval") : String(localized: "\(agentApprovals.count) approvals")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        EventsView(api: deps.apiClient, initialSearchText: agent.id)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Audit Feed"),
                            systemImage: "list.bullet.rectangle.portrait",
                            badgeText: agentRecentEvents.isEmpty ? nil : String(localized: "\(agentRecentEvents.count) loaded")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentCapabilitiesView(
                            agent: agent,
                            initialToolFilters: agentToolFilters,
                            initialSkills: agentSkills,
                            initialMCPServers: agentMCPServers
                        )
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Capabilities"),
                            systemImage: "slider.horizontal.3",
                            tone: agentToolFilters?.scopeTone ?? .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    if let profile = agent.profile {
                        NavigationLink {
                            ToolProfilesView(selectedProfileName: profile)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Tool Profile"),
                                systemImage: "person.crop.rectangle.stack",
                                tone: profileToolCountTone,
                                badgeText: profileBadgeText
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if agent.isRunning {
                        Button {
                            showChat = true
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Live Chat"),
                                systemImage: "bubble.left.and.bubble.right.fill",
                                tone: .positive
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var agentDiagnosticsStatusDeckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: diagnosticsSnapshotSummary,
                detail: String(localized: "Use this compact digest before jumping into sessions, memory, deliveries, workspace files, or approvals.")
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(text: agent.stateLabel, tone: agent.stateTone)
                    if !agentApprovals.isEmpty {
                        PresentationToneBadge(
                            text: agentApprovals.count == 1 ? String(localized: "1 approval") : String(localized: "\(agentApprovals.count) approvals"),
                            tone: .critical
                        )
                    }
                    if !agentSessions.isEmpty {
                        PresentationToneBadge(
                            text: agentSessions.count == 1 ? String(localized: "1 session") : String(localized: "\(agentSessions.count) sessions"),
                            tone: sessionIssueCount > 0 ? .warning : .neutral
                        )
                    }
                    if sessionIssueCount > 0 {
                        PresentationToneBadge(
                            text: sessionIssueCount == 1 ? String(localized: "1 session issue") : String(localized: "\(sessionIssueCount) session issues"),
                            tone: .warning
                        )
                    }
                    if !agentMemory.isEmpty {
                        PresentationToneBadge(
                            text: agentMemory.count == 1 ? String(localized: "1 memory key") : String(localized: "\(agentMemory.count) memory keys"),
                            tone: structuredMemoryTone
                        )
                    }
                    if missingWorkspaceFileCount > 0 {
                        PresentationToneBadge(
                            text: missingWorkspaceFileCount == 1 ? String(localized: "1 missing identity file") : String(localized: "\(missingWorkspaceFileCount) missing identity files"),
                            tone: .warning
                        )
                    }
                    if failedDeliveryCount > 0 {
                        PresentationToneBadge(
                            text: failedDeliveryCount == 1 ? String(localized: "1 failed delivery") : String(localized: "\(failedDeliveryCount) failed deliveries"),
                            tone: .critical
                        )
                    }
                    if unsettledDeliveryCount > 0 {
                        PresentationToneBadge(
                            text: unsettledDeliveryCount == 1 ? String(localized: "1 unsettled delivery") : String(localized: "\(unsettledDeliveryCount) unsettled deliveries"),
                            tone: .warning
                        )
                    }
                    if !agentRecentEvents.isEmpty {
                        PresentationToneBadge(
                            text: agentRecentEvents.count == 1 ? String(localized: "1 recent event") : String(localized: "\(agentRecentEvents.count) recent events"),
                            tone: .neutral
                        )
                    }
                    if let agentProfileSummary, !agentProfileSummary.tools.isEmpty {
                        PresentationToneBadge(
                            text: agentProfileSummary.tools.count == 1 ? String(localized: "1 profile tool") : String(localized: "\(agentProfileSummary.tools.count) profile tools"),
                            tone: profileToolCountTone
                        )
                    }
                    if isWatched {
                        PresentationToneBadge(text: String(localized: "Watched"), tone: .caution)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Operator facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the current model path, session, and failure counts visible while scrolling deeper sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let requestedModelReference {
                    PresentationToneBadge(text: requestedModelReference, tone: modelDiagnostic?.statusTone ?? .neutral)
                }
            } facts: {
                Label(currentSessionBadgeText ?? String(localized: "No current session"), systemImage: "text.bubble")
                Label(
                    failedDeliveryCount == 1 ? String(localized: "1 failed receipt") : String(localized: "\(failedDeliveryCount) failed receipts"),
                    systemImage: "paperplane"
                )
                Label(
                    missingWorkspaceFileCount == 1 ? String(localized: "1 missing file") : String(localized: "\(missingWorkspaceFileCount) missing files"),
                    systemImage: "doc.text"
                )
                Label(
                    agentMemory.count == 1 ? String(localized: "1 memory key") : String(localized: "\(agentMemory.count) memory keys"),
                    systemImage: "internaldrive"
                )
            }
        }
    }

    private var identitySection: some View {
        Section {
            ResponsiveIconDetailRow(horizontalAlignment: .center, horizontalSpacing: 16, verticalSpacing: 10, spacerMinLength: 0) {
                identityEmoji
            } detail: {
                identityText
            }
            .listRowBackground(Color.clear)
        }
    }

    private var identityEmoji: some View {
        Text(agent.identity?.emoji ?? "🤖")
            .font(.system(size: 48))
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(agent.name)
                .font(.title2.weight(.bold))
                .lineLimit(2)
            if isWatched {
                Label("Pinned on this iPhone", systemImage: "star.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(watchAccentColor)
            }
            Text(agent.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusSection: some View {
        Section("Runtime Status") {
            DetailRow(icon: "power", label: "State", value: agent.stateLabel, valueColor: agent.stateTone.color)
            DetailRow(icon: "gearshape.2", label: "Mode", value: agent.modeLabel)
            DetailRow(icon: "checkmark.circle", label: "Ready", value: agent.readyLabel,
                      valueColor: agent.readyTone.color)
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
                    valueColor: modelDiagnostic.statusTone.color
                )
                if let resolvedModel = modelDiagnostic.resolvedModel {
                    DetailRow(
                        icon: "square.stack.3d.up",
                        label: "Resolved Model",
                        value: resolvedModel.id
                    )
                }
            }
            if let tier = agent.modelTierLabel {
                DetailRow(icon: "star", label: "Tier", value: tier)
            }
            if let auth = agent.authStatus {
                DetailRow(
                    icon: "lock",
                    label: "Auth",
                    value: agent.authStatusLabel ?? auth,
                    valueColor: agent.authStatusTone?.color ?? .secondary
                )
            }
            if !isLoadingDeliveries {
                DetailRow(
                    icon: "paperplane",
                    label: "Delivery Check",
                    value: deliveryStatusSummary,
                    valueColor: deliverySummaryStatus.tone.color
                )
            }
            if !isLoadingFiles && !agentFiles.isEmpty {
                DetailRow(
                    icon: "doc.badge.gearshape",
                    label: "Workspace Check",
                    value: workspaceIdentitySummary.statusLabel,
                    valueColor: workspaceIdentitySummary.tone.color
                )
            }
        }
    }

    @ViewBuilder
    private var capabilitiesSection: some View {
        if !isLoadingCapabilities || agent.profile != nil || isLoadingProfile {
            Section {
                if isLoadingCapabilities {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                } else {
                    if let agentToolFilters {
                        DetailRow(
                            icon: "slider.horizontal.3",
                            label: "Tool Scope",
                            value: toolScopeSummary(agentToolFilters),
                            valueColor: agentToolFilters.scopeTone.color
                        )
                    }
                    if let agentSkills {
                        DetailRow(
                            icon: "sparkles",
                            label: "Skills",
                            value: assignmentSummary(agentSkills, emptyLabel: String(localized: "All skills")),
                            valueColor: agentSkills.scopeTone.color
                        )
                    }
                    if let agentMCPServers {
                        DetailRow(
                            icon: "shippingbox",
                            label: "MCP Scope",
                            value: assignmentSummary(agentMCPServers, emptyLabel: String(localized: "All servers")),
                            valueColor: agentMCPServers.scopeTone.color
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
                        AgentDetailValueRow("Tools") {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else if let agentProfileSummary {
                        AgentDetailValueRow("Tools") {
                            Text(agentProfileSummary.tools.count.formatted())
                                .foregroundStyle(profileToolCountTone.color)
                                .monospacedDigit()
                        }
                        if !agentProfileSummary.tools.isEmpty {
                            AgentDetailValueRow("Profile Tools") {
                                Text(profileToolPreview(agentProfileSummary))
                                    .foregroundStyle(.secondary)
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
            } header: {
                Text("Assignments & Profile")
            } footer: {
                Text("Keep tool scope, skills, MCP assignment, and the active profile together before leaving the agent surface.")
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
                        value: resolvedCatalogModel.localizedAvailabilityLabel,
                        valueColor: resolvedCatalogModel.availabilityTone.color
                    )
                    if let providerAlignmentStatus {
                        DetailRow(
                            icon: "arrow.triangle.branch",
                            label: "Provider Match",
                            value: providerAlignmentStatus.label,
                            valueColor: providerAlignmentStatus.tone.color
                        )
                    }
                    AgentDetailValueRow("Capabilities") {
                        Text(capabilitySummary(for: resolvedCatalogModel))
                            .foregroundStyle(.secondary)
                    }
                    AgentDetailValueRow("Context") {
                        Text(contextSummary(for: resolvedCatalogModel))
                            .foregroundStyle(.secondary)
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
                    AgentDetailValueRow("Tags") {
                        Text(agentDetailSnapshot.tags.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }

                if !agentDetailSnapshot.fallbackModels.isEmpty {
                    AgentDetailValueRow("Fallbacks") {
                        Text("\(agentDetailSnapshot.fallbackModels.count)")
                            .monospacedDigit()
                    }

                    ForEach(agentDetailSnapshot.fallbackModels.prefix(3), id: \.id) { fallback in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(fallback.provider)/\(fallback.model)")
                                .font(.subheadline.weight(.medium))

                            if let match = fallbackCatalogModel(for: fallback) {
                                Text(match.available
                                    ? String(localized: "Catalog available")
                                    : String(localized: "Catalog unavailable"))
                                    .font(.caption)
                                    .foregroundStyle(match.availabilityTone.color)
                            } else {
                                Text("No catalog match")
                                    .font(.caption)
                                    .foregroundStyle(PresentationTone.warning.color)
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
                MonitoringSnapshotCard(
                    summary: budgetSnapshotSummary,
                    detail: String(localized: "Use the global budget surface when the agent spend summary no longer has enough context.")
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: String(localized: "Hourly"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: detail.hourly.pct)?.tone ?? .neutral
                        )
                        PresentationToneBadge(
                            text: String(localized: "Daily"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: detail.daily.pct)?.tone ?? .neutral
                        )
                        PresentationToneBadge(
                            text: String(localized: "Monthly"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: detail.monthly.pct)?.tone ?? .neutral
                        )
                        PresentationToneBadge(
                            text: String(localized: "Tokens"),
                            tone: StatusPresentation.budgetUtilizationStatus(for: detail.tokens.pct)?.tone ?? .neutral
                        )
                    }
                }

                BudgetPeriodRow(label: "Hourly", period: detail.hourly)
                BudgetPeriodRow(label: "Daily", period: detail.daily)
                BudgetPeriodRow(label: "Monthly", period: detail.monthly)
            }

            Section("Token Usage") {
                MonitoringFactsRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Token Pressure"))
                            .font(.subheadline.weight(.medium))
                        Text(String(localized: "Keep the token budget and utilization visible before leaving the agent spend view."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } accessory: {
                    Gauge(value: min(detail.tokens.pct, 1.0)) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint((StatusPresentation.budgetUtilizationStatus(for: detail.tokens.pct) ?? .normal).color())
                    .scaleEffect(0.7)
                } facts: {
                    Label(
                        "\(detail.tokens.used.formatted()) / \(detail.tokens.limit.formatted())",
                        systemImage: "number"
                    )
                    Label(
                        String(localized: "\(Int(detail.tokens.pct * 100))% used"),
                        systemImage: "chart.bar"
                    )
                    Label(
                        localizedUSDCurrency(detail.daily.spend, standardPrecision: 2, smallValuePrecision: 4),
                        systemImage: "dollarsign.circle"
                    )
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
            MonitoringSnapshotCard(
                summary: sessionSnapshotSummary,
                detail: sessionSnapshotDetail
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: (snapshot.label?.isEmpty == false ? snapshot.label : nil) ?? String(localized: "Current"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: snapshot.messageCount == 1 ? String(localized: "1 message") : String(localized: "\(snapshot.messageCount) messages"),
                        tone: .neutral
                    )
                    PresentationToneBadge(
                        text: String(localized: "\(snapshot.contextWindowTokens.formatted()) ctx"),
                        tone: .neutral
                    )
                    if sessionIssueCount > 0 {
                        PresentationToneBadge(
                            text: sessionIssueCount == 1 ? String(localized: "1 issue") : String(localized: "\(sessionIssueCount) issues"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session Inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active label, broader inventory, and recent transcript coverage visible while triaging session state."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if sessionItems.count > 1 {
                    PresentationToneBadge(
                        text: sessionItems.count == 1 ? String(localized: "1 known session") : String(localized: "\(sessionItems.count) known sessions"),
                        tone: sessionAttentionTone
                    )
                }
            } facts: {
                Label(
                    currentSessionInfo.map(sessionDisplayTitle) ?? String(localized: "Current session"),
                    systemImage: "text.bubble"
                )
                Label(
                    snapshot.messageCount == 1 ? String(localized: "1 transcript message") : String(localized: "\(snapshot.messageCount) transcript messages"),
                    systemImage: "text.bubble.fill"
                )
                Label(
                    sessionItems.count == 1 ? String(localized: "1 tracked session") : String(localized: "\(sessionItems.count) tracked sessions"),
                    systemImage: "rectangle.stack"
                )
            }
        }
    }

    private var sessionControlsSection: some View {
        Section {
            AgentSessionControlsInventoryDeck(
                actionCount: sessionControlActionCount,
                destructiveActionCount: destructiveSessionActionCount,
                sessionCount: sessionItems.count,
                visibleSessionCount: visibleSessionInventoryCount,
                issueCount: sessionIssueCount,
                hasCurrentSession: currentSessionInfo != nil,
                isBusy: hasActiveSessionOperation || isCreatingSession
            )

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
                AgentDetailValueRow("Total Sessions") {
                    Text("\(sessionItems.count)")
                        .monospacedDigit()
                }
                AgentDetailValueRow("Attention") {
                    Text("\(sessionItems.filter { $0.severity > 0 }.count)")
                        .foregroundStyle(sessionAttentionTone.color)
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
                    Label("Sessions", systemImage: "rectangle.stack")
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
                MonitoringSnapshotCard(
                    summary: memorySnapshotSummary,
                    detail: String(localized: "Use the full memory surface when the compact key preview is not enough to explain agent behavior.")
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: agentMemory.count == 1 ? String(localized: "1 key") : String(localized: "\(agentMemory.count) keys"),
                            tone: agentMemory.isEmpty ? .neutral : .positive
                        )
                        let structured = agentMemory.filter(\.isStructured).count
                        PresentationToneBadge(
                            text: structured == 1 ? String(localized: "1 structured") : String(localized: "\(structured) structured"),
                            tone: structuredMemoryTone
                        )
                    }
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
                    Label("Memory", systemImage: "internaldrive")
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
                MonitoringSnapshotCard(
                    summary: workspaceSnapshotSummary,
                    detail: String(localized: "Use the full workspace identity surface when the previewed files are not enough to explain agent behavior.")
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: workspaceIdentitySummary.progressLabel,
                            tone: workspaceIdentitySummary.tone
                        )
                        if missingWorkspaceFileCount > 0 {
                            PresentationToneBadge(
                                text: missingWorkspaceFileCount == 1 ? String(localized: "1 missing") : String(localized: "\(missingWorkspaceFileCount) missing"),
                                tone: .warning
                            )
                        }
                    }
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

                MonitoringSnapshotCard(
                    summary: deliveriesSnapshotSummary,
                    detail: String(localized: "Use the full receipt surface when the compact preview is not enough to explain channel behavior.")
                ) {
                    FlowLayout(spacing: 8) {
                        PresentationToneBadge(
                            text: agentDeliveries.count == 1 ? String(localized: "1 receipt") : String(localized: "\(agentDeliveries.count) receipts"),
                            tone: agentDeliveries.isEmpty ? .neutral : .positive
                        )
                        PresentationToneBadge(
                            text: delivered == 1 ? String(localized: "1 delivered") : String(localized: "\(delivered) delivered"),
                            tone: deliveredReceiptTone
                        )
                        if failed > 0 {
                            PresentationToneBadge(
                                text: failed == 1 ? String(localized: "1 failed") : String(localized: "\(failed) failed"),
                                tone: failedReceiptTone
                            )
                        }
                        if unsettledDeliveryCount > 0 {
                            PresentationToneBadge(
                                text: unsettledDeliveryCount == 1 ? String(localized: "1 unsettled") : String(localized: "\(unsettledDeliveryCount) unsettled"),
                                tone: .warning
                            )
                        }
                    }
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
                    Label("Events", systemImage: "list.bullet.rectangle.portrait")
                }
            } header: {
                Text("Recent Audit")
            } footer: {
                Text("Showing recent audit events already loaded on the dashboard for this agent.")
            }
        }
    }

    private var actionsSection: some View {
        Section("Local Actions") {
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

            Button {
                UIPasteboard.general.string = agent.id
            } label: {
                Label("Copy Agent ID", systemImage: "doc.on.doc")
            }
        }
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
        deliverySummaryStatus.label
    }

    private var deliverySummaryStatus: DeliverySummaryStatus {
        .summarize(
            failedCount: failedDeliveryCount,
            unsettledCount: unsettledDeliveryCount,
            totalCount: agentDeliveries.count
        )
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
        ResponsiveLabeledContentRow(verticalSpacing: 6) {
            rowLabel
        } value: {
            Text(value)
                .foregroundStyle(valueColor)
        }
    }

    private var rowLabel: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
        }
    }
}

private struct AgentDetailValueRow<Value: View>: View {
    let label: LocalizedStringResource
    let value: Value

    init(_ label: LocalizedStringResource, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        ResponsiveLabeledContentRow(verticalSpacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        } value: {
            value
        }
    }
}

private struct AgentSectionInventoryDeck: View {
    let sectionCount: Int
    let issueCount: Int
    let approvalCount: Int
    let sessionCount: Int
    let memoryCount: Int
    let fileCount: Int
    let deliveryCount: Int
    let auditCount: Int
    let hasBudget: Bool
    let hasModelResolution: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonitoringSnapshotCard(summary: summaryLine, detail: detailLine, verticalPadding: 4) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 live section") : String(localized: "\(sectionCount) live sections"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: issueCount == 1 ? String(localized: "1 issue") : String(localized: "\(issueCount) issues"),
                        tone: issueCount > 0 ? .warning : .neutral
                    )
                    PresentationToneBadge(
                        text: hasModelResolution ? String(localized: "Model path visible") : String(localized: "Model path pending"),
                        tone: hasModelResolution ? .positive : .neutral
                    )
                    PresentationToneBadge(
                        text: hasBudget ? String(localized: "Budget visible") : String(localized: "Budget pending"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section inventory"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep session, memory, workspace, receipts, and audit coverage visible before the operator routes and deeper agent sections."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: approvalCount == 1 ? String(localized: "1 approval") : String(localized: "\(approvalCount) approvals"),
                    tone: approvalCount > 0 ? .warning : .neutral
                )
            } facts: {
                Label(
                    sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"),
                    systemImage: "rectangle.stack"
                )
                Label(
                    memoryCount == 1 ? String(localized: "1 memory key") : String(localized: "\(memoryCount) memory keys"),
                    systemImage: "internaldrive"
                )
                Label(
                    fileCount == 1 ? String(localized: "1 workspace file") : String(localized: "\(fileCount) workspace files"),
                    systemImage: "doc.text"
                )
                Label(
                    deliveryCount == 1 ? String(localized: "1 receipt") : String(localized: "\(deliveryCount) receipts"),
                    systemImage: "paperplane"
                )
                if auditCount > 0 {
                    Label(
                        auditCount == 1 ? String(localized: "1 audit event") : String(localized: "\(auditCount) audit events"),
                        systemImage: "list.bullet.rectangle.portrait"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        sectionCount == 1
            ? String(localized: "1 agent section is active below the controls deck.")
            : String(localized: "\(sectionCount) agent sections are active below the controls deck.")
    }

    private var detailLine: String {
        String(localized: "Current model path, budget visibility, and deeper diagnostics coverage stay summarized before the route rails and detail sections.")
    }
}

// MARK: - Budget Period Row

private struct BudgetPeriodRow: View {
    let label: LocalizedStringResource
    let period: BudgetPeriod

    var body: some View {
        let utilizationStatus = StatusPresentation.budgetUtilizationStatus(for: period.pct) ?? .normal

        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 4) {
                Text(label)
                    .font(.subheadline)
            } accessory: {
                HStack(spacing: 6) {
                    Text(localizedUSDCurrency(period.spend, standardPrecision: 2, smallValuePrecision: 4))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    Text("/ \(localizedUSDCurrency(period.limit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(period.pct, 1.0))
                .tint(utilizationStatus.color())
        }
        .padding(.vertical, 2)
    }
}

private func localizedUSDCurrency(
    _ value: Double,
    standardPrecision: Int = 2,
    smallValuePrecision: Int? = nil,
    minimumDisplayValue: Double = 0.01
) -> String {
    let style = FloatingPointFormatStyle<Double>.Currency(code: "USD")
    if value == 0 {
        return value.formatted(style.precision(.fractionLength(standardPrecision)))
    }
    if value < minimumDisplayValue {
        return "<\(minimumDisplayValue.formatted(style.precision(.fractionLength(standardPrecision))))"
    }
    let precision = value < 1 ? (smallValuePrecision ?? standardPrecision) : standardPrecision
    return value.formatted(style.precision(.fractionLength(precision)))
}

private struct SessionPreviewRow: View {
    let message: AgentSessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalSpacing: 8, verticalSpacing: 4, spacerMinLength: 0) {
                roleLabel
            } accessory: {
                toolSummary
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
                                TintedLabelCapsuleBadge(
                                    text: image.filename,
                                    systemImage: "photo",
                                    foregroundStyle: message.roleTintColor,
                                    backgroundStyle: message.roleTintColor.opacity(0.12),
                                    horizontalPadding: 8,
                                    verticalPadding: 6
                                )
                                .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
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

    private var roleLabel: some View {
        Text(message.localizedRoleLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(message.roleTintColor)
    }

    @ViewBuilder
    private var toolSummary: some View {
        if let toolCount = message.tools?.count, toolCount > 0 {
            Text(toolSummaryLabel(toolCount))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AgentSessionInventoryRow: View {
    let item: SessionAttentionItem
    let isCurrentSession: Bool
    let isBusy: Bool
    let onSwitch: (() -> Void)?
    let onEditLabel: (() -> Void)?
    let onDelete: (() -> Void)?

    private let currentSessionTone: PresentationTone = .positive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, horizontalSpacing: 10, verticalSpacing: 6) {
                titleLabel
            } accessory: {
                trailingControls
            }

            ResponsiveAccessoryRow(horizontalSpacing: 8, verticalSpacing: 6, spacerMinLength: 0) {
                reasonSummary
            } accessory: {
                createdAtLabel
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

    private var titleLabel: some View {
        Text(displayTitle)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var messageCountLabel: some View {
        Text("\(item.session.messageCount) msgs")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(item.messageCountTone.color)
    }

    private var currentBadge: some View {
        PresentationToneBadge(
            text: String(localized: "Current"),
            tone: currentSessionTone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    @ViewBuilder
    private var switchButton: some View {
        if let onSwitch {
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
    }

    @ViewBuilder
    private var actionsMenu: some View {
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
    }

    private var trailingControls: some View {
        FlowLayout(spacing: 8) {
            if isCurrentSession {
                currentBadge
            } else {
                switchButton
            }
            actionsMenu
            messageCountLabel
        }
    }

    @ViewBuilder
    private var reasonSummary: some View {
        if item.reasons.isEmpty {
            Text("No unusual session pressure")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(item.reasons.prefix(2), id: \.self) { reason in
                    reasonChip(reason)
                }
            }
        }
    }

    private var createdAtLabel: some View {
        Text(relativeCreatedAt)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func reasonChip(_ reason: String) -> some View {
        PresentationToneBadge(
            text: reason,
            tone: item.tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

}

private struct AgentSessionControlsInventoryDeck: View {
    let actionCount: Int
    let destructiveActionCount: Int
    let sessionCount: Int
    let visibleSessionCount: Int
    let issueCount: Int
    let hasCurrentSession: Bool
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep action breadth, current-session context, and visible inventory load readable before the session-control buttons take over."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: actionCount == 1 ? String(localized: "1 action") : String(localized: "\(actionCount) actions"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: hasCurrentSession ? String(localized: "Current session loaded") : String(localized: "No current session"),
                        tone: hasCurrentSession ? .positive : .neutral
                    )
                    if issueCount > 0 {
                        PresentationToneBadge(
                            text: issueCount == 1 ? String(localized: "1 session issue") : String(localized: "\(issueCount) session issues"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Session-control coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Use this slice to confirm whether the visible controls are centered on normal relabel or lookup work versus destructive recovery actions."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: isBusy ? String(localized: "Action running") : String(localized: "Idle"),
                    tone: isBusy ? .warning : .neutral
                )
            } facts: {
                Label(
                    destructiveActionCount == 1 ? String(localized: "1 destructive action") : String(localized: "\(destructiveActionCount) destructive actions"),
                    systemImage: "exclamationmark.triangle"
                )
                if sessionCount > 0 {
                    Label(
                        visibleSessionCount == sessionCount
                            ? (sessionCount == 1 ? String(localized: "1 visible session") : String(localized: "\(sessionCount) visible sessions"))
                            : String(localized: "\(visibleSessionCount) of \(sessionCount) sessions visible"),
                        systemImage: "rectangle.stack"
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        hasCurrentSession
            ? String(localized: "Session controls currently expose \(actionCount) actions around the active session.")
            : String(localized: "Session controls currently expose \(actionCount) agent-level actions before a current session is resolved.")
    }
}

private struct AgentAuditRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(verticalSpacing: 6, spacerMinLength: 0) {
                titleLabel
            } accessory: {
                timestampLabel
            }

            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(entry.localizedOutcomeLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.severity.tone.color)
        }
        .padding(.vertical, 2)
    }

    private var relativeTimestamp: String {
        guard let date = entry.timestamp.agentSessionISO8601Date else { return entry.timestamp }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var titleLabel: some View {
        Text(entry.friendlyAction)
            .font(.subheadline.weight(.medium))
    }

    private var timestampLabel: some View {
        Text(relativeTimestamp)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

}

private struct AgentMemorySummaryRow: View {
    let entry: AgentMemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ResponsiveAccessoryRow(verticalSpacing: 6, spacerMinLength: 0) {
                keyLabel
            } accessory: {
                structureBadge
            }

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var keyLabel: some View {
        Text(entry.key)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    @ViewBuilder
    private var structureBadge: some View {
        if let structureBadgeLabel = entry.structureBadgeLabel,
           let structureTone = entry.structureTone {
            PresentationToneBadge(
                text: structureBadgeLabel,
                tone: structureTone,
                horizontalPadding: 6,
                verticalPadding: 2
            )
        }
    }
}

private struct AgentFileSummaryRow: View {
    let file: AgentWorkspaceFileSummary

    var body: some View {
        ResponsiveAccessoryRow(verticalSpacing: 4, spacerMinLength: 0) {
            Text(file.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        } accessory: {
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
            ResponsiveAccessoryRow(verticalSpacing: 6, spacerMinLength: 0) {
                Text(receipt.localizedChannelLabel)
                    .font(.subheadline.weight(.medium))
            } accessory: {
                PresentationToneBadge(
                    text: receipt.status.label,
                    tone: receipt.status.tone,
                    horizontalPadding: 6,
                    verticalPadding: 2
                )
            }

            Text(receipt.recipient)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
