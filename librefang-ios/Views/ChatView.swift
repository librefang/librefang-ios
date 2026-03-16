import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SessionBanner(viewModel: viewModel)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Loading conversation…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else if viewModel.messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.tertiary)
                                Text("Send a message to \(viewModel.agent.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = message.content
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                }
                        }

                        if viewModel.isSending {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isSending) {
                    scrollToBottom(proxy: proxy)
                }
                .onTapGesture {
                    isInputFocused = false
                }
            }

            // Error
            if let error = viewModel.error {
                ErrorBanner(message: error, onDismiss: {
                    viewModel.error = nil
                })
                .padding(.bottom, 4)
            }

            Divider()

            // Input Bar
            ResponsiveInlineGroup(horizontalSpacing: 8, verticalSpacing: 8, verticalAlignment: .trailing) {
                messageField
                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(viewModel.agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.activate()
        }
        .onDisappear {
            viewModel.deactivate()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(viewModel.agent.identity?.emoji ?? "🤖")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var canSend: Bool {
        !viewModel.isSending && !viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var messageField: some View {
        TextField("Message...", text: $viewModel.inputText, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused($isInputFocused)
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.send() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
        }
        .disabled(!canSend)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isSending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble

private struct SessionBanner: View {
    let viewModel: ChatViewModel

    private var connectionState: ChatConnectionState {
        viewModel.connectionState
    }

    private var shouldShowBanner: Bool {
        viewModel.messageCount > 0
            || viewModel.contextWindowTokens > 0
            || viewModel.sessionLabel != nil
            || viewModel.isLoadingHistory
            || viewModel.isSending
            || viewModel.error != nil
    }

    var body: some View {
        if shouldShowBanner {
            VStack(alignment: .leading, spacing: 8) {
                ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 10) {
                    sessionSummary
                } accessory: {
                    FlowLayout(spacing: 10) {
                        realtimeIndicator
                        if viewModel.contextWindowTokens > 0 {
                            contextTokens
                        }
                    }
                }
                ChatSessionInventoryDeck(
                    sessionLabel: viewModel.sessionLabel,
                    messageCount: viewModel.messageCount,
                    loadedMessageCount: viewModel.messages.count,
                    contextWindowTokens: viewModel.contextWindowTokens,
                    isLoadingHistory: viewModel.isLoadingHistory,
                    isSending: viewModel.isSending,
                    hasError: viewModel.error != nil,
                    connectionState: connectionState
                )
                ChatSessionPressureDeck(
                    messageCount: viewModel.messageCount,
                    loadedMessageCount: viewModel.loadedMessageCount,
                    historyLagCount: viewModel.historyLagCount,
                    contextWindowTokens: viewModel.contextWindowTokens,
                    isLoadingHistory: viewModel.isLoadingHistory,
                    isSending: viewModel.isSending,
                    hasError: viewModel.error != nil,
                    connectionState: connectionState
                )
                ChatSessionRouteDeck(
                    agent: viewModel.agent,
                    messageCount: viewModel.messageCount,
                    contextWindowTokens: viewModel.contextWindowTokens,
                    historyLagCount: viewModel.historyLagCount,
                    hasNamedSession: viewModel.hasNamedSession,
                    hasError: viewModel.error != nil,
                    connectionState: connectionState
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.sessionLabel?.isEmpty == false ? viewModel.sessionLabel! : String(localized: "Current Session"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(String(localized: "\(viewModel.messageCount) messages"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(transportDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var realtimeIndicator: some View {
        PresentationToneLabelBadge(
            text: connectionState.label,
            systemImage: connectionState.symbolName,
            tone: connectionState.tone
        )
    }

    private var contextTokens: some View {
        ResponsiveInlineGroup(horizontalSpacing: 6, verticalSpacing: 3) {
            PresentationToneBadge(
                text: viewModel.contextWindowTokens.formatted(),
                tone: .neutral,
                horizontalPadding: 10,
                verticalPadding: 6
            )
            Text("context tokens")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var transportDetail: String {
        if viewModel.isLoadingHistory {
            return String(localized: "Loading recent conversation and session context.")
        }
        if viewModel.isSending {
            return connectionState == .live
                ? String(localized: "Agent is replying over the live session.")
                : String(localized: "Agent is replying through fallback request and response.")
        }
        switch connectionState {
        case .live:
            return String(localized: "Realtime replies stay attached to this session.")
        case .fallback:
            return String(localized: "Messages use fallback request and response until realtime reconnects.")
        }
    }
}

private struct ChatSessionInventoryDeck: View {
    let sessionLabel: String?
    let messageCount: Int
    let loadedMessageCount: Int
    let contextWindowTokens: Int
    let isLoadingHistory: Bool
    let isSending: Bool
    let hasError: Bool
    let connectionState: ChatConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ResponsiveAccessoryRow(horizontalSpacing: 8, verticalSpacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Session inventory"))
                        .font(.caption.weight(.semibold))
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                PresentationToneLabelBadge(
                    text: connectionState.label,
                    systemImage: connectionState.symbolName,
                    tone: connectionState.tone
                )
            }

            FlowLayout(spacing: 8) {
                PresentationToneBadge(
                    text: messageCount == 1 ? String(localized: "1 message") : String(localized: "\(messageCount) messages"),
                    tone: .neutral,
                    horizontalPadding: 10,
                    verticalPadding: 6
                )
                if loadedMessageCount > 0 && loadedMessageCount != messageCount {
                    PresentationToneBadge(
                        text: loadedMessageCount == 1 ? String(localized: "1 loaded") : String(localized: "\(loadedMessageCount) loaded"),
                        tone: .neutral,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
                if contextWindowTokens > 0 {
                    PresentationToneBadge(
                        text: String(localized: "\(contextWindowTokens.formatted()) context"),
                        tone: .neutral,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
                if sessionLabel?.isEmpty == false {
                    PresentationToneBadge(
                        text: String(localized: "Named session"),
                        tone: .neutral,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
                if isLoadingHistory {
                    PresentationToneBadge(
                        text: String(localized: "History loading"),
                        tone: .neutral,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
                if isSending {
                    PresentationToneBadge(
                        text: String(localized: "Replying"),
                        tone: connectionState == .live ? .positive : .warning,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
                if hasError {
                    PresentationToneBadge(
                        text: String(localized: "Needs retry"),
                        tone: .critical,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                }
            }
        }
    }

    private var detailLine: String {
        if isLoadingHistory {
            return String(localized: "The banner stays compact while recent history loads.")
        }
        if isSending {
            return String(localized: "Reply state, context usage, and loaded history stay visible while the agent is typing.")
        }
        if hasError {
            return String(localized: "Session pressure stays visible so you can retry without losing context.")
        }
        return String(localized: "Session pressure stays readable before you scroll into the conversation.")
    }
}

private struct ChatSessionPressureDeck: View {
    let messageCount: Int
    let loadedMessageCount: Int
    let historyLagCount: Int
    let contextWindowTokens: Int
    let isLoadingHistory: Bool
    let isSending: Bool
    let hasError: Bool
    let connectionState: ChatConnectionState

    private var isHighVolumeSession: Bool {
        messageCount >= 40
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Use this pressure slice to keep reply state, history lag, fallback transport, and context usage readable before scrolling through the conversation."),
                verticalPadding: 4
            ) {
                FlowLayout(spacing: 8) {
                    if hasError {
                        PresentationToneBadge(text: String(localized: "Needs retry"), tone: .critical)
                    }
                    if isLoadingHistory {
                        PresentationToneBadge(text: String(localized: "History loading"), tone: .neutral)
                    }
                    if isSending {
                        PresentationToneBadge(
                            text: String(localized: "Replying"),
                            tone: connectionState == .live ? .positive : .warning
                        )
                    }
                    if historyLagCount > 0 {
                        PresentationToneBadge(
                            text: historyLagCount == 1 ? String(localized: "1 older message hidden") : String(localized: "\(historyLagCount) older messages hidden"),
                            tone: .warning
                        )
                    }
                    if isHighVolumeSession {
                        PresentationToneBadge(text: String(localized: "High volume"), tone: .warning)
                    }
                }
            }

            MonitoringFactsRow(
                verticalSpacing: 8,
                headerVerticalSpacing: 4,
                factsFont: .caption2
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Pressure coverage"))
                        .font(.caption.weight(.semibold))
                    Text(String(localized: "Keep transport mode, reply state, context load, and history coverage visible while the agent is still in session."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } accessory: {
                PresentationToneLabelBadge(
                    text: connectionState.label,
                    systemImage: connectionState.symbolName,
                    tone: connectionState.tone
                )
            } facts: {
                Label(
                    messageCount == 1 ? String(localized: "1 total message") : String(localized: "\(messageCount) total messages"),
                    systemImage: "bubble.left.and.bubble.right"
                )
                if loadedMessageCount > 0 {
                    Label(
                        loadedMessageCount == 1 ? String(localized: "1 loaded locally") : String(localized: "\(loadedMessageCount) loaded locally"),
                        systemImage: "tray.full"
                    )
                }
                if contextWindowTokens > 0 {
                    Label(
                        String(localized: "\(contextWindowTokens.formatted()) context tokens"),
                        systemImage: "text.word.spacing"
                    )
                }
            }
        }
    }

    private var summaryLine: String {
        if hasError {
            return String(localized: "Chat pressure is currently anchored by a retryable session error.")
        }
        if isSending && connectionState == .fallback {
            return String(localized: "Chat pressure is currently anchored by a fallback reply.")
        }
        if isLoadingHistory {
            return String(localized: "Chat pressure is currently anchored by history loading.")
        }
        if historyLagCount > 0 {
            return historyLagCount == 1
                ? String(localized: "Chat pressure is currently concentrated in 1 older message that is still offscreen.")
                : String(localized: "Chat pressure is currently concentrated in \(historyLagCount) older messages that are still offscreen.")
        }
        if isHighVolumeSession {
            return String(localized: "Chat pressure is currently concentrated in a high-volume conversation.")
        }
        if contextWindowTokens > 0 {
            return String(localized: "Chat pressure is currently low and mostly reflects active context usage.")
        }
        return String(localized: "Chat pressure is currently low and mostly reflects the live session state.")
    }
}

private struct ChatSessionRouteDeck: View {
    let agent: Agent
    let messageCount: Int
    let contextWindowTokens: Int
    let historyLagCount: Int
    let hasNamedSession: Bool
    let hasError: Bool
    let connectionState: ChatConnectionState

    private let primaryRouteCount = 3
    private let supportRouteCount = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitoringSnapshotCard(
                summary: summaryLine,
                detail: String(localized: "Keep the most common agent, session, memory, workspace, and delivery drilldowns one tap away while staying in the current chat."),
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
                    if hasError {
                        PresentationToneBadge(text: String(localized: "Retry state"), tone: .critical)
                    }
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Primary"),
                detail: String(localized: "Jump straight to the agent, session backlog, or durable memory without leaving the active conversation.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Fast exits")) {
                    NavigationLink {
                        AgentDetailView(agent: agent)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Agent"),
                            systemImage: "person.crop.square",
                            tone: connectionState == .live ? .positive : .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SessionsView(initialSearchText: agent.id, initialFilter: .all)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Sessions"),
                            systemImage: "rectangle.stack",
                            tone: messageCount >= 40 || historyLagCount > 0 ? .warning : .neutral,
                            badgeText: messageCount == 0 ? nil : String(localized: "\(messageCount) msgs")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentMemoryView(agent: agent)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Memory"),
                            systemImage: "brain.head.profile",
                            tone: contextWindowTokens > 0 ? .warning : .neutral,
                            badgeText: contextWindowTokens == 0 ? nil : String(localized: "\(contextWindowTokens.formatted()) ctx")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            MonitoringSurfaceGroupCard(
                title: String(localized: "Support"),
                detail: String(localized: "Keep workspace identity and outbound receipts close when the reply needs deeper operator verification.")
            ) {
                MonitoringShortcutRail(title: String(localized: "Support exits")) {
                    NavigationLink {
                        AgentFilesView(agent: agent)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Files"),
                            systemImage: "folder",
                            tone: hasNamedSession ? .positive : .neutral
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AgentDeliveriesView(agent: agent)
                    } label: {
                        MonitoringSurfaceShortcutChip(
                            title: String(localized: "Deliveries"),
                            systemImage: "paperplane",
                            tone: hasError ? .warning : .neutral
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryLine: String {
        if hasError {
            return String(localized: "Chat routes stay compact while retry pressure is active.")
        }
        if historyLagCount > 0 {
            return String(localized: "Chat routes stay compact while older session history is still offscreen.")
        }
        if connectionState == .fallback {
            return String(localized: "Chat routes stay compact while transport is running in fallback mode.")
        }
        return String(localized: "Chat routes stay compact around the current live session.")
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 28) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(foregroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: .infinity, alignment: bubbleAlignment)

                if !message.images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.images) { image in
                                NavigationLink {
                                    UploadAssetView(image: image)
                                } label: {
                                    TintedLabelCapsuleBadge(
                                        text: image.filename,
                                        systemImage: "photo",
                                        foregroundStyle: .blue,
                                        backgroundStyle: Color.blue.opacity(0.12),
                                        horizontalPadding: 8,
                                        verticalPadding: 6
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: bubbleAlignment)
                }

                ResponsiveInlineGroup(
                    horizontalSpacing: 6,
                    verticalSpacing: 3,
                    verticalAlignment: message.role == .user ? .trailing : .leading
                ) {
                    metadataContent
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: bubbleAlignment)
            }
            .frame(maxWidth: .infinity, alignment: bubbleAlignment)

            if message.role != .user { Spacer(minLength: 28) }
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        agentUsageMetadata
        deliveryMetadata
    }

    @ViewBuilder
    private var agentUsageMetadata: some View {
        if message.role == .agent {
            if let tokens = message.tokens, tokens > 0 {
                Label("\(tokens)", systemImage: "number")
            }
            if let cost = message.cost, cost > 0 {
                Label(localizedUSDCurrency(cost, standardPrecision: 4, minimumDisplayValue: 0.0001), systemImage: "dollarsign.circle")
            }
        }
    }

    @ViewBuilder
    private var deliveryMetadata: some View {
        Text(message.timestamp, style: .time)
        if message.isStreaming {
            PresentationToneBadge(
                text: String(localized: "Live"),
                tone: .positive,
                horizontalPadding: 6,
                verticalPadding: 2
            )
        }
    }

    private var hasUsageMetadata: Bool {
        (message.tokens ?? 0) > 0 || (message.cost ?? 0) > 0
    }

    private var bubbleAlignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            .blue
        case .system:
            .orange.opacity(0.18)
        case .agent:
            Color(.systemGray5)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            .white
        case .system:
            .orange
        case .agent:
            .primary
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(dotScale(for: i))
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { phase = 1 }
    }

    private func dotScale(for index: Int) -> CGFloat {
        phase == 0 ? 0.6 : 1.0
    }
}

private func localizedUSDCurrency(
    _ value: Double,
    standardPrecision: Int = 2,
    smallValuePrecision: Int? = nil,
    minimumDisplayValue: Double = 0.01
) -> String {
    let standard = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(standardPrecision))
    if value == 0 {
        return value.formatted(standard)
    }
    if value < minimumDisplayValue {
        let minimumPrecision = smallValuePrecision ?? standardPrecision
        let minimumStyle = FloatingPointFormatStyle<Double>.Currency(code: "USD")
            .precision(.fractionLength(minimumPrecision))
        return "<\(minimumDisplayValue.formatted(minimumStyle))"
    }
    if let smallValuePrecision, value < 1 {
        let small = FloatingPointFormatStyle<Double>.Currency(code: "USD")
            .precision(.fractionLength(smallValuePrecision))
        return value.formatted(small)
    }
    return value.formatted(standard)
}
