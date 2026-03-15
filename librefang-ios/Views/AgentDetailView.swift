import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @Environment(\.dependencies) private var deps
    @State private var budgetDetail: AgentBudgetDetail?
    @State private var sessionSnapshot: AgentSessionSnapshot?
    @State private var agentSessions: [SessionInfo] = []
    @State private var agentMemory: [AgentMemoryEntry] = []
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
    @State private var newSessionLabel = ""
    @State private var isCreatingSession = false
    @State private var showChat = false
    @State private var isLoadingBudget = true
    @State private var isLoadingSession = true
    @State private var isLoadingSessions = true
    @State private var isLoadingMemory = true

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

    var body: some View {
        List {
            identitySection
            statusSection
            modelResolutionSection
            approvalsSection
            budgetSections
            sessionSections
            memorySection
            recentAuditSection
            actionsSection
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            await loadSession()
            await loadSessions()
            await loadMemory()
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
            DetailRow(icon: "power", label: "State", value: agent.state, valueColor: stateColor)
            DetailRow(icon: "gearshape.2", label: "Mode", value: agent.mode)
            DetailRow(icon: "checkmark.circle", label: "Ready", value: agent.ready ? "Yes" : "No",
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
                DetailRow(icon: "lock", label: "Auth", value: auth,
                          valueColor: auth == "configured" ? .green : .red)
            }
            if let profile = agent.profile {
                DetailRow(icon: "person", label: "Profile", value: profile)
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
                        value: resolvedCatalogModel.available ? "Available" : "Unavailable",
                        valueColor: resolvedCatalogModel.available ? .green : .orange
                    )
                    if let providerMatchesResolvedModel {
                        DetailRow(
                            icon: "arrow.triangle.branch",
                            label: "Provider Match",
                            value: providerMatchesResolvedModel ? "Match" : "Drift",
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
                        value: "No match found",
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
                Text(modelDiagnostic?.detail ?? "This section resolves the agent's requested model through LibreFang's alias map and active model catalog.")
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
                Text((snapshot.label?.isEmpty == false ? snapshot.label : nil) ?? "Current")
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
                Label(isWatched ? "Remove From Watchlist" : "Add To Watchlist", systemImage: isWatched ? "star.slash" : "star")
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

    private func capabilitySummary(for model: CatalogModel) -> String {
        var capabilities: [String] = []
        if model.supportsTools {
            capabilities.append("tools")
        }
        if model.supportsVision {
            capabilities.append("vision")
        }
        if model.supportsStreaming {
            capabilities.append("streaming")
        }
        return capabilities.isEmpty ? "No extra capabilities advertised" : capabilities.joined(separator: " • ")
    }

    private func contextSummary(for model: CatalogModel) -> String {
        let contextWindow = model.contextWindow.map { "\($0.formatted()) ctx" }
        let maxOutput = model.maxOutputTokens.map { "\($0.formatted()) out" }
        return [contextWindow, maxOutput]
            .compactMap { $0 }
            .joined(separator: " • ")
            .ifEmpty("Catalog did not publish token limits")
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
                title: "Fresh Session",
                message: switchResponse.message ?? "Created and switched to the new session."
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: "Fresh Session",
                message: error.localizedDescription
            )
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
                title: "Session Label",
                message: response.message ?? (trimmedLabel.isEmpty ? "Session label cleared." : "Session label updated.")
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: "Session Label",
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
                title: "Delete Session",
                message: response.message ?? "Session deleted."
            )
        } catch {
            operatorNotice = OperatorActionNotice(
                title: "Delete Session",
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
    let label: LocalizedStringKey
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
    let label: LocalizedStringKey
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
                    Text("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(displayText)
                .font(.subheadline)
                .lineLimit(4)

            if let imageCount = message.images?.count, imageCount > 0 {
                Text("\(imageCount) image attachment\(imageCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var roleTitle: String {
        switch message.role {
        case "User":
            "User"
        case "System":
            "System"
        default:
            "Agent"
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
            return "\(images.count) image attachment\(images.count == 1 ? "" : "s")"
        }
        return "No message content"
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

            Text(entry.outcome.capitalized)
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
