import SwiftUI

private struct MonitoringRefreshInteractionModifier: ViewModifier {
    let isRefreshing: Bool
    let restoreDelay: TimeInterval

    @State private var interactionRevision = 0
    @State private var isInteractive = true

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isInteractive)
            .disabled(!isInteractive)
            .onAppear {
                updateInteractivity(for: isRefreshing)
            }
            .onChange(of: isRefreshing) { _, newValue in
                updateInteractivity(for: newValue)
            }
    }

    private func updateInteractivity(for isRefreshing: Bool) {
        interactionRevision += 1
        let revision = interactionRevision

        guard !isRefreshing else {
            isInteractive = false
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
            await MainActor.run {
                guard interactionRevision == revision else { return }
                isInteractive = true
            }
        }
    }

    private var restoreDelayNanoseconds: UInt64 {
        UInt64(max(restoreDelay, 0) * 1_000_000_000)
    }
}

extension View {
    func monitoringRefreshInteractionGate(
        isRefreshing: Bool,
        restoreDelay: TimeInterval = 0.8
    ) -> some View {
        modifier(
            MonitoringRefreshInteractionModifier(
                isRefreshing: isRefreshing,
                restoreDelay: restoreDelay
            )
        )
    }
}
