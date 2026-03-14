import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @Environment(\.dependencies) private var deps
    @State private var budgetDetail: AgentBudgetDetail?
    @State private var showChat = false
    @State private var isLoadingBudget = true

    var body: some View {
        List {
            // Identity
            Section {
                HStack(spacing: 16) {
                    Text(agent.identity?.emoji ?? "🤖")
                        .font(.system(size: 48))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.title2.weight(.bold))
                        Text(agent.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(Color.clear)
            }

            // Status
            Section("Status") {
                DetailRow(icon: "power", label: "State", value: agent.state, valueColor: stateColor)
                DetailRow(icon: "gearshape.2", label: "Mode", value: agent.mode)
                if let provider = agent.modelProvider {
                    DetailRow(icon: "cloud", label: "Provider", value: provider)
                }
                if let model = agent.modelName {
                    DetailRow(icon: "cpu", label: "Model", value: model)
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

            // Budget
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

            // Actions
            if agent.isRunning {
                Section("Actions") {
                    Button {
                        showChat = true
                    } label: {
                        Label("Send Message", systemImage: "paperplane.fill")
                    }

                    Button {
                        UIPasteboard.general.string = agent.id
                    } label: {
                        Label("Copy Agent ID", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                budgetDetail = try await deps.apiClient.budgetAgent(id: agent.id)
            } catch {
                // Budget is optional
            }
            isLoadingBudget = false
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: deps.makeChatViewModel(for: agent))
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
