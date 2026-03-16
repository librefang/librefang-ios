import SwiftUI

struct ToolProfilesView: View {
    let selectedProfileName: String?

    @Environment(\.dependencies) private var deps
    @State private var profiles: [ToolProfileSummary]
    @State private var isLoading: Bool
    @State private var loadError: String?
    @State private var searchText = ""

    init(selectedProfileName: String? = nil, initialProfiles: [ToolProfileSummary] = []) {
        self.selectedProfileName = selectedProfileName
        _profiles = State(initialValue: initialProfiles.sorted { $0.name < $1.name })
        _isLoading = State(initialValue: initialProfiles.isEmpty)
    }

    private var selectedProfile: ToolProfileSummary? {
        let normalized = selectedProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.name.lowercased() == normalized }
    }

    private var filteredProfiles: [ToolProfileSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.name.lowercased().contains(query)
                || profile.tools.joined(separator: " ").lowercased().contains(query)
        }
    }

    private var toolProfilesPrimaryRouteCount: Int { 2 }
    private var toolProfilesSupportRouteCount: Int { 2 }
    private var toolProfilesSectionCount: Int {
        3 + ((selectedProfile != nil || ((selectedProfileName?.isEmpty == false) && !isLoading && loadError == nil)) ? 1 : 0)
    }
    private var toolProfilesSectionPreviewTitles: [String] {
        var sections: [String] = []
        if selectedProfile != nil || ((selectedProfileName?.isEmpty == false) && !isLoading && loadError == nil) {
            sections.append(String(localized: "Current Profile"))
        }
        sections.append(String(localized: "Profiles"))
        return sections
    }
    private var selectedToolCount: Int {
        selectedProfile?.tools.count ?? 0
    }
    private var densestVisibleToolCount: Int {
        filteredProfiles.map { $0.tools.count }.max() ?? 0
    }

    var body: some View {
        List {
            Section {
                ToolProfilesSnapshotCard(
                    totalProfiles: profiles.count,
                    visibleProfiles: filteredProfiles.count,
                    selectedProfileName: selectedProfile?.name,
                    selectedToolCount: selectedProfile?.tools.count
                )
            }

            Section {
                ToolProfilesSectionInventoryDeck(
                    sectionCount: toolProfilesSectionCount,
                    visibleProfileCount: filteredProfiles.count,
                    totalProfileCount: profiles.count,
                    selectedProfileName: selectedProfile?.name ?? ((selectedProfileName?.isEmpty == false && !isLoading && loadError == nil) ? selectedProfileName : nil),
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isLoading: isLoading && profiles.isEmpty && loadError == nil,
                    hasLoadError: loadError != nil
                )
                if !toolProfilesSectionPreviewTitles.isEmpty {
                    MonitoringSectionPreviewDeck(
                        title: String(localized: "Section Preview"),
                        detail: String(localized: "Keep the next tool-profile stacks visible before the current profile and full profile list open up."),
                        sectionTitles: toolProfilesSectionPreviewTitles
                    )
                }

                ToolProfilesPressureCoverageDeck(
                    visibleProfileCount: filteredProfiles.count,
                    selectedToolCount: selectedToolCount,
                    densestVisibleToolCount: densestVisibleToolCount,
                    hasSelectedProfile: selectedProfile != nil,
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                ToolProfilesFocusCoverageDeck(
                    visibleProfileCount: filteredProfiles.count,
                    totalProfileCount: profiles.count,
                    selectedProfileName: selectedProfile?.name,
                    selectedToolCount: selectedToolCount,
                    densestVisibleToolCount: densestVisibleToolCount,
                    hasSelectedProfile: selectedProfile != nil,
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                ToolProfilesWorkstreamCoverageDeck(
                    visibleProfileCount: filteredProfiles.count,
                    totalProfileCount: profiles.count,
                    selectedProfileName: selectedProfile?.name,
                    selectedToolCount: selectedToolCount,
                    densestVisibleToolCount: densestVisibleToolCount,
                    hasSelectedProfile: selectedProfile != nil,
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                ToolProfilesRouteInventoryDeck(
                    primaryRouteCount: toolProfilesPrimaryRouteCount,
                    supportRouteCount: toolProfilesSupportRouteCount,
                    visibleProfileCount: filteredProfiles.count,
                    totalProfileCount: profiles.count,
                    selectedProfileName: selectedProfile?.name,
                    hasSearchScope: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                MonitoringSurfaceGroupCard(
                    title: String(localized: "Routes"),
                    detail: String(localized: "Keep fleet, runtime, integration, and diagnostics exits closest to compact tool-profile review.")
                ) {
                    MonitoringShortcutRail(
                        title: String(localized: "Primary"),
                        detail: String(localized: "Use fleet and runtime surfaces first.")
                    ) {
                        NavigationLink {
                            AgentsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Agents"),
                                systemImage: "person.3",
                                tone: selectedProfile != nil ? .positive : .neutral,
                                badgeText: selectedProfileName
                            )
                        }
                        .buttonStyle(.plain)

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

                    MonitoringShortcutRail(
                        title: String(localized: "Support"),
                        detail: String(localized: "Keep integration and diagnostics context behind the primary fleet exits.")
                    ) {
                        NavigationLink {
                            IntegrationsView(initialScope: .attention)
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Integrations"),
                                systemImage: "square.3.layers.3d.down.forward"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            MonitoringSurfaceShortcutChip(
                                title: String(localized: "Diagnostics"),
                                systemImage: "stethoscope"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Routes")
            } footer: {
                Text("Use these routes when profile inspection needs fleet, runtime, or integration context.")
            }

            if let selectedProfile {
                Section {
                    SelectedToolProfileDeck(profile: selectedProfile)

                    profileHeader(selectedProfile, highlight: true)

                    toolSummary(profile: selectedProfile, maxVisibleTools: selectedProfile.tools.count)
                } header: {
                    Text("Current Profile")
                } footer: {
                    Text("Tool profiles are server-defined bundles. They explain what an agent can and cannot call even when the rest of the runtime looks healthy.")
                }
            } else if let selectedProfileName, !selectedProfileName.isEmpty, !isLoading, loadError == nil {
                Section {
                    ContentUnavailableView(
                        String(localized: "Current Profile Missing"),
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(String(localized: "LibreFang did not return a tool profile named \"\(selectedProfileName)\"."))
                    )
                } header: {
                    Text("Current Profile")
                }
            }

            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        String(localized: "Profiles Unavailable"),
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(loadError)
                    )
                }
            } else if profiles.isEmpty {
                Section("All Profiles") {
                    ContentUnavailableView(
                        String(localized: "No Tool Profiles"),
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(String(localized: "LibreFang did not return any tool profile summaries."))
                    )
                }
            } else if filteredProfiles.isEmpty {
                Section("All Profiles") {
                    ContentUnavailableView(
                        String(localized: "No Matching Profiles"),
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(String(localized: "Try a different profile or tool search."))
                    )
                }
            } else {
                Section("All Profiles") {
                    ToolProfilesCatalogDeck(
                        profiles: filteredProfiles,
                        totalProfiles: profiles.count,
                        selectedProfileName: selectedProfile?.name
                    )

                    ForEach(filteredProfiles) { profile in
                        VStack(alignment: .leading, spacing: 6) {
                            profileHeader(profile, highlight: profile.name.lowercased() == selectedProfileName?.lowercased())
                            toolSummary(profile: profile, maxVisibleTools: 4)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Tool Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search profile or tool")
        .refreshable {
            await loadProfiles()
        }
        .overlay {
            if isLoading && profiles.isEmpty {
                ProgressView("Loading profiles...")
            }
        }
        .task {
            if profiles.isEmpty {
                await loadProfiles()
            }
        }
    }

    @ViewBuilder
    private func profileHeader(_ profile: ToolProfileSummary, highlight: Bool) -> some View {
        let profileStatus = MonitoringSummaryStatus(
            summary: profile.tools.count == 1
                ? String(localized: "1 tool")
                : String(localized: "\(profile.tools.count) tools"),
            tone: highlight ? .positive : .neutral
        )

        ResponsiveAccessoryRow(verticalSpacing: 4) {
            profileNameLabel(profile)
        } accessory: {
            toolCountBadge(profileStatus)
        }
    }

    private func profileNameLabel(_ profile: ToolProfileSummary) -> some View {
        Text(profile.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }

    private func toolCountBadge(_ status: MonitoringSummaryStatus) -> some View {
        PresentationToneBadge(
            text: status.summary,
            tone: status.tone,
            horizontalPadding: 6,
            verticalPadding: 2
        )
    }

    @ViewBuilder
    private func toolSummary(profile: ToolProfileSummary, maxVisibleTools: Int) -> some View {
        let visibleTools = Array(profile.tools.prefix(maxVisibleTools))
        let remaining = max(profile.tools.count - visibleTools.count, 0)

        if visibleTools.isEmpty {
            Text("No tools in this profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(visibleTools.count == profile.tools.count
                ? String(localized: "Showing all tools")
                : String(localized: "Showing \(visibleTools.count) of \(profile.tools.count) tools"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(visibleTools, id: \.self) { tool in
                    ToolProfileToolChip(label: tool)
                }

                if remaining > 0 {
                    TintedCapsuleBadge(
                        text: String(localized: "+\(remaining) more"),
                        foregroundStyle: .secondary,
                        backgroundStyle: Color(.systemGray5),
                        horizontalPadding: 8,
                        verticalPadding: 5
                    )
                }
            }
        }
    }

    @MainActor
    private func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            profiles = (try await deps.apiClient.profiles()).sorted { $0.name < $1.name }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ToolProfilesSnapshotCard: View {
    let totalProfiles: Int
    let visibleProfiles: Int
    let selectedProfileName: String?
    let selectedToolCount: Int?

    var body: some View {
        MonitoringSnapshotCard(
            summary: String(localized: "Tool profiles explain what the runtime is allowed to call."),
            verticalPadding: 4
        ) {
            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: totalProfiles == 1 ? String(localized: "1 profile") : String(localized: "\(totalProfiles) profiles"),
                    tone: totalProfiles > 0 ? .positive : .neutral
                )
                if visibleProfiles != totalProfiles {
                    PresentationToneBadge(
                        text: String(localized: "\(visibleProfiles) visible"),
                        tone: .warning
                    )
                }
                if let selectedProfileName {
                    PresentationToneBadge(
                        text: selectedProfileName,
                        tone: .positive
                    )
                }
                if let selectedToolCount {
                    PresentationToneBadge(
                        text: selectedToolCount == 1 ? String(localized: "1 tool") : String(localized: "\(selectedToolCount) tools"),
                        tone: .neutral
                    )
                }
            }
        }
    }
}

private struct ToolProfilesSectionInventoryDeck: View {
    let sectionCount: Int
    let visibleProfileCount: Int
    let totalProfileCount: Int
    let selectedProfileName: String?
    let hasSearchScope: Bool
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
                    ? String(localized: "Section coverage stays visible while tool profiles are still loading.")
                    : String(localized: "Section coverage stays visible before routes, the selected profile, and the wider profile catalog."),
                detail: hasSearchScope
                    ? String(localized: "Use section coverage to confirm the scoped profile catalog before pivoting into fleet or runtime context.")
                    : String(localized: "Use section coverage to confirm how much profile context is ready before leaving the catalog."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: sectionCount == 1 ? String(localized: "1 section ready") : String(localized: "\(sectionCount) sections ready"),
                        tone: coverageTone
                    )
                    PresentationToneBadge(
                        text: totalProfileCount == 1 ? String(localized: "1 catalog profile") : String(localized: "\(totalProfileCount) catalog profiles"),
                        tone: totalProfileCount == 0 ? .neutral : .positive
                    )
                    if let selectedProfileName {
                        PresentationToneBadge(text: selectedProfileName, tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Section Coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep snapshot, routes, selected-profile state, and the wider profile catalog visible before drilling into bundled tools."))
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
                        text: visibleProfileCount == totalProfileCount
                            ? (visibleProfileCount == 1 ? String(localized: "1 visible profile") : String(localized: "\(visibleProfileCount) visible profiles"))
                            : String(localized: "\(visibleProfileCount) of \(totalProfileCount) visible"),
                        tone: .positive
                    )
                }
            } facts: {
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if let selectedProfileName {
                    Label(selectedProfileName, systemImage: "checkmark.circle")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ToolProfilesPressureCoverageDeck: View {
    let visibleProfileCount: Int
    let selectedToolCount: Int
    let densestVisibleToolCount: Int
    let hasSelectedProfile: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to separate selected-profile focus from broad tool-density pressure before opening the catalog below."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if hasSelectedProfile {
                        PresentationToneBadge(
                            text: selectedToolCount == 1 ? String(localized: "1 selected tool") : String(localized: "\(selectedToolCount) selected tools"),
                            tone: selectedToolCount > 0 ? .positive : .neutral
                        )
                    }
                    if densestVisibleToolCount > 0 {
                        PresentationToneBadge(
                            text: densestVisibleToolCount == 1 ? String(localized: "1 tool in top profile") : String(localized: "\(densestVisibleToolCount) tools in top profile"),
                            tone: densestVisibleToolCount > 12 ? .warning : .neutral
                        )
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep selected-profile focus and catalog tool density readable before drilling into bundled tool sets."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleProfileCount == 1 ? String(localized: "1 visible profile") : String(localized: "\(visibleProfileCount) visible profiles"),
                    tone: .positive
                )
            } facts: {
                if hasSelectedProfile {
                    Label(String(localized: "Selected profile"), systemImage: "checkmark.circle")
                }
                if densestVisibleToolCount > 12 {
                    Label(String(localized: "Dense catalog"), systemImage: "square.stack.3d.up")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSelectedProfile {
            return String(localized: "Tool-profile pressure is currently anchored by the selected profile and its bundled tools.")
        }
        if hasSearchScope {
            return String(localized: "Tool-profile pressure is currently concentrated in a search-scoped catalog slice.")
        }
        return String(localized: "Tool-profile pressure is currently low and mostly reflects catalog tool density.")
    }
}

private struct ToolProfilesFocusCoverageDeck: View {
    let visibleProfileCount: Int
    let totalProfileCount: Int
    let selectedProfileName: String?
    let selectedToolCount: Int
    let densestVisibleToolCount: Int
    let hasSelectedProfile: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to keep the dominant tool-profile lane visible before moving from compact catalog decks into the selected profile and full profile list."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleProfileCount == totalProfileCount
                            ? (visibleProfileCount == 1 ? String(localized: "1 visible profile") : String(localized: "\(visibleProfileCount) visible profiles"))
                            : String(localized: "\(visibleProfileCount) of \(totalProfileCount) visible"),
                        tone: visibleProfileCount > 0 ? .positive : .neutral
                    )
                    if hasSelectedProfile, let selectedProfileName {
                        PresentationToneBadge(text: selectedProfileName, tone: .positive)
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Focus coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the dominant tool-profile lane readable before pivoting into fleet, runtime, or integration context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: densestVisibleToolCount == 1 ? String(localized: "1 tool in top profile") : String(localized: "\(densestVisibleToolCount) tools in top profile"),
                    tone: densestVisibleToolCount > 12 ? .warning : .neutral
                )
            } facts: {
                if hasSelectedProfile {
                    Label(
                        selectedToolCount == 1 ? String(localized: "1 selected tool") : String(localized: "\(selectedToolCount) selected tools"),
                        systemImage: "checkmark.circle"
                    )
                }
                if densestVisibleToolCount > 12 {
                    Label(String(localized: "Dense catalog"), systemImage: "square.stack.3d.up")
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryLine: String {
        if hasSelectedProfile {
            return String(localized: "Tool-profile focus coverage is currently anchored by the selected profile and its bundled tools.")
        }
        if hasSearchScope {
            return String(localized: "Tool-profile focus coverage is currently anchored by the filtered profile catalog.")
        }
        if densestVisibleToolCount > 12 {
            return String(localized: "Tool-profile focus coverage is currently anchored by dense bundled tool sets.")
        }
        return String(localized: "Tool-profile focus coverage is currently balanced across the visible profile catalog.")
    }
}

private struct ToolProfilesWorkstreamCoverageDeck: View {
    let visibleProfileCount: Int
    let totalProfileCount: Int
    let selectedProfileName: String?
    let selectedToolCount: Int
    let densestVisibleToolCount: Int
    let hasSelectedProfile: Bool
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this deck to see whether tool-profile review is currently led by the selected profile, dense catalogs, or scoped search before the profile list opens."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: visibleProfileCount == totalProfileCount
                            ? (visibleProfileCount == 1 ? String(localized: "1 visible profile") : String(localized: "\(visibleProfileCount) visible profiles"))
                            : String(localized: "\(visibleProfileCount) of \(totalProfileCount) visible"),
                        tone: visibleProfileCount > 0 ? .positive : .neutral
                    )
                    if hasSelectedProfile, let selectedProfileName {
                        PresentationToneBadge(text: selectedProfileName, tone: .positive)
                    }
                    if hasSearchScope {
                        PresentationToneBadge(text: String(localized: "Search scoped"), tone: .neutral)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Workstream coverage"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep selected-profile depth, dense tool catalogs, and scoped search state readable before moving through the full profile list."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: densestVisibleToolCount == 1 ? String(localized: "1 tool in top profile") : String(localized: "\(densestVisibleToolCount) tools in top profile"),
                    tone: densestVisibleToolCount > 12 ? .warning : .neutral
                )
            } facts: {
                if hasSelectedProfile {
                    Label(
                        selectedToolCount == 1 ? String(localized: "1 selected tool") : String(localized: "\(selectedToolCount) selected tools"),
                        systemImage: "checkmark.circle"
                    )
                }
                if densestVisibleToolCount > 12 {
                    Label(String(localized: "Dense catalog"), systemImage: "square.stack.3d.up")
                }
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var summaryLine: String {
        if hasSelectedProfile {
            return String(localized: "Tool-profile workstream coverage is currently anchored by the selected profile.")
        }
        if densestVisibleToolCount > 12 {
            return String(localized: "Tool-profile workstream coverage is currently anchored by dense visible tool catalogs.")
        }
        if hasSearchScope {
            return String(localized: "Tool-profile workstream coverage is currently anchored by the filtered profile slice.")
        }
        return String(localized: "Tool-profile workstream coverage is currently light across the visible profiles.")
    }
}

private struct ToolProfilesRouteInventoryDeck: View {
    let primaryRouteCount: Int
    let supportRouteCount: Int
    let visibleProfileCount: Int
    let totalProfileCount: Int
    let selectedProfileName: String?
    let hasSearchScope: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: hasSearchScope
                    ? String(localized: "Tool-profile routes stay compact while the catalog is search-scoped.")
                    : String(localized: "Tool-profile routes stay compact before the surrounding fleet and runtime drilldowns."),
                detail: String(localized: "Use the route inventory to gauge how many exits are active before leaving the tool-profile directory."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: primaryRouteCount == 1 ? String(localized: "1 primary route") : String(localized: "\(primaryRouteCount) primary routes"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: supportRouteCount == 1 ? String(localized: "1 support route") : String(localized: "\(supportRouteCount) support routes"),
                        tone: .neutral
                    )
                    if let selectedProfileName {
                        PresentationToneBadge(text: selectedProfileName, tone: .positive)
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Route Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the active catalog slice and selected bundle visible before pivoting into fleet, runtime, or integration context."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(
                    text: visibleProfileCount == totalProfileCount
                        ? (visibleProfileCount == 1 ? String(localized: "1 visible profile") : String(localized: "\(visibleProfileCount) visible profiles"))
                        : String(localized: "\(visibleProfileCount) of \(totalProfileCount) visible"),
                    tone: .positive
                )
            } facts: {
                if hasSearchScope {
                    Label(String(localized: "Search scoped"), systemImage: "magnifyingglass")
                }
                if let selectedProfileName {
                    Label(selectedProfileName, systemImage: "checkmark.circle")
                }
                Label(
                    totalProfileCount == 1 ? String(localized: "1 catalog profile") : String(localized: "\(totalProfileCount) catalog profiles"),
                    systemImage: "person.crop.rectangle.stack"
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SelectedToolProfileDeck: View {
    let profile: ToolProfileSummary

    private var longestToolName: String? {
        profile.tools.max { $0.count < $1.count }
    }

    private var toolNameCharacterCount: Int {
        profile.tools.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "The selected tool profile stays compact before the full profile tool list."),
                detail: String(localized: "Use the current-profile deck to confirm the loaded bundle and its tool weight before opening the full tool grid."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: profile.tools.count == 1 ? String(localized: "1 tool in profile") : String(localized: "\(profile.tools.count) tools in profile"),
                        tone: profile.tools.isEmpty ? .neutral : .positive
                    )
                    PresentationToneBadge(
                        text: toolNameCharacterCount == 1 ? String(localized: "1 tool character") : String(localized: "\(toolNameCharacterCount) tool characters"),
                        tone: .neutral
                    )
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Profile Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the selected bundle name, tool count, and the most verbose tool label visible while comparing profile contents."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                PresentationToneBadge(text: profile.name, tone: .positive)
            } facts: {
                Label(
                    profile.tools.count == 1 ? String(localized: "1 bundled tool") : String(localized: "\(profile.tools.count) bundled tools"),
                    systemImage: "wrench.and.screwdriver"
                )
                if let longestToolName {
                    Label(longestToolName, systemImage: "textformat.size")
                }
            }
        }
    }
}

private struct ToolProfilesCatalogDeck: View {
    let profiles: [ToolProfileSummary]
    let totalProfiles: Int
    let selectedProfileName: String?

    private var visibleToolCount: Int {
        profiles.reduce(0) { $0 + $1.tools.count }
    }

    private var emptyProfileCount: Int {
        profiles.filter(\.tools.isEmpty).count
    }

    private var largestProfile: ToolProfileSummary? {
        profiles.max { $0.tools.count < $1.tools.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonitoringSnapshotCard(
                summary: String(localized: "The filtered profile catalog stays compact before the full profile directory."),
                detail: selectedProfileName == nil
                    ? String(localized: "Use this deck to gauge profile breadth and the heaviest bundle before opening each catalog entry.")
                    : String(localized: "Use this deck to compare the selected profile against the rest of the visible catalog."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    PresentationToneBadge(
                        text: profiles.count == totalProfiles
                            ? (profiles.count == 1 ? String(localized: "1 visible profile") : String(localized: "\(profiles.count) visible profiles"))
                            : String(localized: "\(profiles.count) of \(totalProfiles) visible"),
                        tone: .positive
                    )
                    PresentationToneBadge(
                        text: visibleToolCount == 1 ? String(localized: "1 visible tool") : String(localized: "\(visibleToolCount) visible tools"),
                        tone: .neutral
                    )
                    if emptyProfileCount > 0 {
                        PresentationToneBadge(
                            text: emptyProfileCount == 1 ? String(localized: "1 empty profile") : String(localized: "\(emptyProfileCount) empty profiles"),
                            tone: .warning
                        )
                    }
                }
            }

            MonitoringFactsRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Catalog Facts"))
                        .font(.subheadline.weight(.medium))
                    Text(String(localized: "Keep the visible profile count, catalog tool footprint, and largest bundle visible while scanning profile inventory."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } accessory: {
                if let largestProfile {
                    PresentationToneBadge(
                        text: largestProfile.tools.count == 1 ? String(localized: "Largest: 1 tool") : String(localized: "Largest: \(largestProfile.tools.count) tools"),
                        tone: .neutral
                    )
                }
            } facts: {
                Label(
                    profiles.count == 1 ? String(localized: "1 catalog profile") : String(localized: "\(profiles.count) catalog profiles"),
                    systemImage: "person.crop.rectangle.stack"
                )
                Label(
                    visibleToolCount == 1 ? String(localized: "1 visible tool") : String(localized: "\(visibleToolCount) visible tools"),
                    systemImage: "wrench.and.screwdriver"
                )
                if let largestProfile {
                    Label(largestProfile.name, systemImage: "chart.bar")
                }
                if let selectedProfileName {
                    Label(selectedProfileName, systemImage: "checkmark.circle")
                }
            }
        }
    }
}

private struct ToolProfileToolChip: View {
    let label: String

    var body: some View {
        TintedLabelCapsuleBadge(
            text: label,
            systemImage: "wrench.and.screwdriver",
            foregroundStyle: .secondary,
            backgroundStyle: Color(.systemGray5),
            horizontalPadding: 8,
            verticalPadding: 5
        )
        .lineLimit(1)
        .truncationMode(.middle)
    }
}
