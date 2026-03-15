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
                MonitoringSurfaceGroupCard(
                    title: String(localized: "Primary Routes"),
                    detail: String(localized: "Keep the fleet and runtime exits closest to compact tool-profile review.")
                ) {
                    NavigationLink {
                        AgentsView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Agents"),
                            detail: String(localized: "Switch to fleet view when the same profile shape needs to be checked across multiple agents."),
                            systemImage: "person.3",
                            tone: selectedProfile != nil ? .positive : .neutral,
                            badgeText: selectedProfileName,
                            badgeTone: .neutral
                        )
                    }

                    NavigationLink {
                        RuntimeView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Runtime"),
                            detail: String(localized: "Switch to runtime when profile scope needs provider, approval, or session context."),
                            systemImage: "server.rack",
                            tone: .neutral
                        )
                    }
                }

                MonitoringSurfaceGroupCard(
                    title: String(localized: "Support Routes"),
                    detail: String(localized: "Keep integration and diagnostics context behind the primary fleet exits.")
                ) {
                    NavigationLink {
                        IntegrationsView(initialScope: .attention)
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Integrations"),
                            detail: String(localized: "Switch to integrations if the profile looks healthy but tool execution still depends on providers or channels."),
                            systemImage: "square.3.layers.3d.down.forward",
                            tone: .neutral
                        )
                    }

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        MonitoringJumpRow(
                            title: String(localized: "Diagnostics"),
                            detail: String(localized: "Switch to diagnostics when profile mismatch may actually reflect runtime health or config drift."),
                            systemImage: "stethoscope",
                            tone: .neutral
                        )
                    }
                }
            } header: {
                Text("Route Deck")
            } footer: {
                Text("Use these routes when profile inspection needs fleet, runtime, or integration context.")
            }

            if let selectedProfile {
                Section {
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
            } else {
                Section("All Profiles") {
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
