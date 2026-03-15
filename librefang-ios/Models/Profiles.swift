import Foundation

nonisolated struct ToolProfileSummary: Codable, Identifiable, Sendable, Hashable {
    let name: String
    let tools: [String]

    var id: String { name }
}
