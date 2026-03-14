import Foundation

struct ServerConfig: Codable, Sendable {
    var baseURL: String
    var apiKey: String

    static let defaultURL = "http://127.0.0.1:4545"

    @MainActor
    static var saved: ServerConfig {
        let url = UserDefaults.standard.string(forKey: "serverURL") ?? defaultURL
        let key = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        return ServerConfig(baseURL: url, apiKey: key)
    }

    @MainActor
    func save() {
        UserDefaults.standard.set(baseURL, forKey: "serverURL")
        UserDefaults.standard.set(apiKey, forKey: "apiKey")
    }
}

struct HealthStatus: Codable, Sendable {
    let status: String
    let version: String

    var isHealthy: Bool { status == "ok" }
}
