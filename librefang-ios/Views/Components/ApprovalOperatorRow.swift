import SwiftUI

struct ApprovalOperatorRow: View {
    let approval: ApprovalItem
    var isBusy = false
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(approval.actionSummary)
                        .font(.subheadline.weight(.medium))
                    Text(approval.agentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(approval.riskLevel.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskColor.opacity(0.12))
                    .foregroundStyle(riskColor)
                    .clipShape(Capsule())
            }

            if !approval.description.isEmpty {
                Text(approval.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                Label(approval.toolName, systemImage: "wrench.and.screwdriver")
                Label(relativeRequestedAt, systemImage: "clock")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Button {
                    onApprove()
                } label: {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isBusy)

                Button(role: .destructive) {
                    onReject()
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private var riskColor: Color {
        switch approval.riskLevel.lowercased() {
        case "critical":
            .red
        case "high":
            .orange
        default:
            .yellow
        }
    }

    private var relativeRequestedAt: String {
        guard let date = approval.requestedAt.approvalISO8601Date else { return approval.requestedAt }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
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
