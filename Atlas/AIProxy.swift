import Foundation
enum AIProxy {
    static let functionName = "openai-proxy"
    private static let cacheInterval: TimeInterval = 300
    private static var lastHealthyAt: Date?

    static func endpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("functions/v1/\(functionName)")
    }

    static func endpointString(baseURL: URL) -> String {
        endpoint(baseURL: baseURL).absoluteString
    }

    static func healthURL(baseURL: URL) -> URL {
        endpoint(baseURL: baseURL).appendingPathComponent("health")
    }

    /// Performs a lightweight health check against the Edge Function and caches success for a short window.
    static func ensureHealthy() async throws {
        if let lastHealthyAt, Date().timeIntervalSince(lastHealthyAt) < cacheInterval {
            return
        }

        _ = try await EdgeFunctionClient.checkHealth()
        lastHealthyAt = Date()
    }
}
