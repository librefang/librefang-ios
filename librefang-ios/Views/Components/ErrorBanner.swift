import SwiftUI

struct ErrorBanner: View {
    let message: String
    var onRetry: (() async -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)

            Text(message)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.white)

            Spacer()

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

            if let onDismiss {
                Button {
                    withAnimation { onDismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
