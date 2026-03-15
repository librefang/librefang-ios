import Foundation

nonisolated struct UploadedFilePayload: Sendable {
    let data: Data
    let contentType: String?
}
