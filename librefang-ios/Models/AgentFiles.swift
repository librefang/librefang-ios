import Foundation

nonisolated struct AgentWorkspaceFileListResponse: Codable, Sendable {
    let files: [AgentWorkspaceFileSummary]
}

nonisolated struct AgentWorkspaceFileSummary: Codable, Identifiable, Sendable, Hashable {
    let name: String
    let exists: Bool
    let sizeBytes: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, exists
        case sizeBytes = "size_bytes"
    }
}

nonisolated struct AgentWorkspaceFileDetail: Codable, Sendable {
    let name: String
    let content: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case name, content
        case sizeBytes = "size_bytes"
    }
}
