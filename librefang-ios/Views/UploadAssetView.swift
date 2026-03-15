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
                ProgressView("Loading attachment...")
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
        .navigationTitle(image.filename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = image.fileId
                } label: {
                    Image(systemName: "doc.on.doc")
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
