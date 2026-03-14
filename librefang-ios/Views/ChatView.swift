import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if viewModel.messages.isEmpty {
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(viewModel.agent.name)
        .navigationBarTitleDisplayMode(.inline)
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

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                // Metadata
                HStack(spacing: 6) {
                    if message.role == .agent {
                        if let tokens = message.tokens, tokens > 0 {
                            Label("\(tokens)", systemImage: "number")
                        }
                        if let cost = message.cost, cost > 0 {
                            Label("$\(cost, specifier: "%.4f")", systemImage: "dollarsign.circle")
                        }
                    }
                    Text(message.timestamp, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)
            }

            if message.role == .agent { Spacer(minLength: 48) }
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? .blue : Color(.systemGray5)
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
