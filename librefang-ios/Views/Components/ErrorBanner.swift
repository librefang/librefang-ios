import SwiftUI

struct ErrorBanner: View {
    let message: String
    var onRetry: (() async -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveAccessoryRow(horizontalAlignment: .top, verticalSpacing: 6) {
                messageSummary
            } accessory: {
                if let onDismiss {
                    dismissButton(onDismiss)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if let onRetry {
                Button {
                    Task {
                        isRetrying = true
                        await onRetry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Text("Retry")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(isRetrying)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var messageSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)

            Text(message)
                .font(.caption)
                .lineLimit(3)
                .foregroundStyle(.white)
        }
    }

    private func dismissButton(_ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
