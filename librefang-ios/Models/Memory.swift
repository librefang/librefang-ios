import Foundation

nonisolated struct AgentMemoryListResponse: Codable, Sendable {
    let kvPairs: [AgentMemoryEntry]

    enum CodingKeys: String, CodingKey {
        case kvPairs = "kv_pairs"
    }
}

nonisolated struct AgentMemoryExportSnapshot: Codable, Sendable {
    let agentId: String
    let version: Int
    let kv: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case version, kv
        case agentId = "agent_id"
    }

    var prettyPrintedJSONString: String {
        let payload: [String: Any] = [
            "agent_id": agentId,
            "version": version,
            "kv": kv.mapValues(\.exportFoundationObject)
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{\n  \"agent_id\": \"\(agentId)\",\n  \"version\": \(version)\n}"
        }

        return text
    }
}

nonisolated struct AgentMemoryEntry: Codable, Identifiable, Sendable, Hashable {
    let key: String
    let value: JSONValue

    var id: String { key }
    var isStructured: Bool { value.isStructured }
    var summary: String { value.memorySummary }
    var editorText: String { value.memoryEditorText }
}

extension JSONValue {
    nonisolated var isStructured: Bool {
        switch self {
        case .object, .array:
            true
        default:
            false
        }
    }

    nonisolated var memorySummary: String {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Empty string") : trimmed
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return value.formatted()
        case .bool(let value):
            return value ? String(localized: "true") : String(localized: "false")
        case .object(let value):
            return value.count == 1
                ? String(localized: "1 field")
                : String(localized: "\(value.count) fields")
        case .array(let value):
            return value.count == 1
                ? String(localized: "1 item")
                : String(localized: "\(value.count) items")
        case .null:
            return String(localized: "null")
        }
    }

    nonisolated var memoryEditorText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return value.formatted()
        case .bool(let value):
            return value ? String(localized: "true") : String(localized: "false")
        case .null:
            return String(localized: "null")
        case .object, .array:
            return prettyPrintedJSONString ?? memorySummary
        }
    }

    nonisolated var prettyPrintedJSONString: String? {
        guard let object = foundationObject else { return nil }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func parseMemoryEditorText(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .string("") }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            return fromFoundationObject(object)
        }

        return .string(text)
    }

    private nonisolated var foundationObject: Any? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.foundationObject).compactMapValues { $0 }
        case .array(let value):
            return value.compactMap(\.foundationObject)
        case .null:
            return NSNull()
        }
    }

    fileprivate nonisolated var exportFoundationObject: Any {
        foundationObject ?? NSNull()
    }

    private nonisolated static func fromFoundationObject(_ object: Any) -> JSONValue {
        switch object {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as [String: Any]:
            return .object(value.mapValues(fromFoundationObject))
        case let value as [Any]:
            return .array(value.map(fromFoundationObject))
        case _ as NSNull:
            return .null
        default:
            return .string(String(describing: object))
        }
    }
}
