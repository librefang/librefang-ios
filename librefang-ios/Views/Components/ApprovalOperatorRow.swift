import SwiftUI

struct ApprovalOperatorRow: View {
    let approval: ApprovalItem
    var isBusy = false
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonitoringFactsRow(
                horizontalAlignment: .top,
                verticalSpacing: 6,
                headerVerticalSpacing: 4,
                factsFont: .caption2,
                factsColor: .secondary
            ) {
                summaryBlock
            } accessory: {
                riskBadge
            } facts: {
                metadataLabels
            }

            ResponsiveInlineGroup(horizontalSpacing: 10, verticalSpacing: 10) {
                approveButton
                rejectButton
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private var relativeRequestedAt: String {
        guard let date = approval.requestedAt.approvalISO8601Date else { return approval.requestedAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private var summaryBlock: some View {
        Text(approval.actionSummary)
            .font(.subheadline.weight(.medium))
            .lineLimit(2)
    }

    private var riskBadge: some View {
        PresentationToneBadge(
            text: approval.localizedRiskLabel,
            tone: approval.riskTone
        )
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(approval.agentName, systemImage: "cpu")
        Label(approval.toolName, systemImage: "wrench.and.screwdriver")
        Label(relativeRequestedAt, systemImage: "clock")
    }

    private var approveButton: some View {
        Button {
            onApprove()
        } label: {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Approve", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(isBusy)
    }

    private var rejectButton: some View {
        Button(role: .destructive) {
            onReject()
        } label: {
            Label("Reject", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }
}

private extension String {
    var approvalISO8601Date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: self) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: self)
    }
}
