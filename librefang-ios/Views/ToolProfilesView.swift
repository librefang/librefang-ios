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
            if let selectedProfile {
                Section {
                    profileHeader(selectedProfile, highlight: true)

                    ForEach(selectedProfile.tools, id: \.self) { tool in
                        Label(tool, systemImage: "wrench.and.screwdriver")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Current Profile")
                } footer: {
                    Text("Tool profiles are server-defined bundles. They explain what an agent can and cannot call even when the rest of the runtime looks healthy.")
                }
            }

            if let loadError {
                Section("Status") {
                    ContentUnavailableView(
                        "Profiles Unavailable",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(loadError)
                    )
                }
            } else {
                Section("All Profiles") {
                    ForEach(filteredProfiles) { profile in
                        VStack(alignment: .leading, spacing: 6) {
                            profileHeader(profile, highlight: profile.name.lowercased() == selectedProfileName?.lowercased())

                            Text(profile.tools.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
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
        HStack {
            Text(profile.name.capitalized)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(profile.tools.count) tools")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((highlight ? Color.blue : Color.secondary).opacity(0.12))
                .foregroundStyle(highlight ? .blue : .secondary)
                .clipShape(Capsule())
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
