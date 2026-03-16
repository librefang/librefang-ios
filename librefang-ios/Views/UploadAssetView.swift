import SwiftUI
import UIKit

struct UploadAssetView: View {
    let image: AgentSessionImage

    @Environment(\.dependencies) private var deps
    @State private var uiImage: UIImage?
    @State private var contentType: String?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "Loading attachment..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.94))
            } else if let uiImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Color.black.opacity(0.94))
            } else {
                ContentUnavailableView(
                    "Attachment Preview Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(loadError ?? "LibreFang returned a file that iOS could not render as an image.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading {
                UploadAssetInfoCard(
                    filename: image.filename,
                    fileId: image.fileId,
                    contentType: contentType
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(image.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = image.fileId
                    } label: {
                        Label("Copy File ID", systemImage: "doc.on.doc")
                    }

                    Button {
                        UIPasteboard.general.string = image.filename
                    } label: {
                        Label("Copy Filename", systemImage: "text.cursor")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadAttachment()
        }
    }

    @MainActor
    private func loadAttachment() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await deps.apiClient.uploadedFile(fileId: image.fileId)
            contentType = payload.contentType
            uiImage = UIImage(data: payload.data)
            if uiImage == nil {
                loadError = payload.contentType.map { "Content-Type: \($0)" }
            } else {
                loadError = nil
            }
        } catch {
            loadError = error.localizedDescription
            uiImage = nil
        }
    }
}

private struct UploadAssetInfoCard: View {
    let filename: String
    let fileId: String
    let contentType: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UploadAssetValueRow(label: "Filename") {
                Text(filename)
                    .lineLimit(2)
            }

            UploadAssetValueRow(label: "File ID") {
                Text(fileId)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let contentType, !contentType.isEmpty {
                UploadAssetValueRow(label: "Content-Type") {
                    Text(contentType)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct UploadAssetValueRow<Content: View>: View {
    let label: LocalizedStringKey
    let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ResponsiveValueRow {
            Text(label)
                .foregroundStyle(.secondary)
        } value: {
            content
        }
        .font(.caption)
    }
}
