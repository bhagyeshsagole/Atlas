import Foundation
import Supabase

/// Stable, non-experimental client for Supabase Edge Functions.
enum EdgeFunctionClient {
    typealias Response = (Data, HTTPURLResponse)

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
    }

    private static let projectRef = "nqaodudipodgtrnxcknv"
    private static let functionName = AIProxy.functionName

    private static var supabaseURL: URL? {
        SupabaseConfig.url ?? URL(string: "https://\(projectRef).supabase.co")
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func buildURL(function: String, path: String?) -> URL? {
        guard let base = supabaseURL else { return nil }
        var url = base.appendingPathComponent("functions/v1").appendingPathComponent(function)
        if let path, path.isEmpty == false {
            let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
            url = url.appendingPathComponent(cleaned)
        }
        return url
    }

    private static func defaultHeaders(includeAuthIfAvailable: Bool) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json"
        ]

        if let anonKey = SupabaseConfig.anonKey {
            headers["apikey"] = anonKey
        }

        if includeAuthIfAvailable,
           let token = OpenAIConfig.supabaseClient?.auth.currentSession?.accessToken,
           token.isEmpty == false {
            headers["Authorization"] = "Bearer \(token)"
        }

        return headers
    }

    /// Low-level invoke that performs a request to an Edge Function.
    static func invoke(
        function: String = functionName,
        path: String? = nil,
        method: HTTPMethod = .post,
        body: Encodable? = nil,
        headers: [String: String] = [:],
        includeAuthIfAvailable: Bool = true
    ) async throws -> Response {
        guard let url = buildURL(function: function, path: path) else {
            throw OpenAIError(statusCode: nil, message: "Supabase URL missing.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        var requestHeaders = defaultHeaders(includeAuthIfAvailable: includeAuthIfAvailable)
        headers.forEach { requestHeaders[$0.key] = $0.value }
        requestHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let body {
            request.httpBody = try jsonEncoder.encode(AnyEncodable(body))
        }

        let requestId = UUID().uuidString.prefix(6)
        #if DEBUG
        print("[AI][EDGE][REQ \(requestId)] \(method.rawValue) url=\(url.absoluteString)")
        #endif

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError(statusCode: nil, message: "Invalid response.")
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        #if DEBUG
        if http.statusCode >= 300 {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            print("[AI][EDGE][RES \(requestId)] status=\(http.statusCode) ms=\(elapsed) error=\(snippet.prefix(300))")
        } else {
            print("[AI][EDGE][RES \(requestId)] status=\(http.statusCode) ms=\(elapsed)")
        }
        #endif

        guard 200..<300 ~= http.statusCode else {
            let parsedError = parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw OpenAIError(
                statusCode: http.statusCode,
                message: "\(parsedError) \(snippet)"
            )
        }

        return (data, http)
    }

    /// Convenience to decode JSON responses.
    static func invokeJSON<T: Decodable>(
        function: String = functionName,
        path: String? = nil,
        method: HTTPMethod = .post,
        body: Encodable? = nil,
        headers: [String: String] = [:],
        includeAuthIfAvailable: Bool = true,
        decode type: T.Type
    ) async throws -> T {
        let (data, _) = try await invoke(
            function: function,
            path: path,
            method: method,
            body: body,
            headers: headers,
            includeAuthIfAvailable: includeAuthIfAvailable
        )
        return try jsonDecoder.decode(type, from: data)
    }

    static func callChat(payload: Encodable) async throws -> Response {
        try await invoke(path: "chat", method: .post, body: payload, includeAuthIfAvailable: true)
    }

    static func checkHealth() async throws -> Response {
        try await invoke(path: "health", method: .get, body: nil, includeAuthIfAvailable: false)
    }

    #if DEBUG
    static func debugLogHealth() async {
        do {
            let (data, response) = try await checkHealth()
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[AI][EDGE][HEALTH] status=\(response.statusCode) body=\(body)")
        } catch {
            print("[AI][EDGE][HEALTH][ERROR] \(error)")
        }
    }
    #endif

    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let envelope = try? jsonDecoder.decode(ErrorEnvelope.self, from: data) else {
            return nil
        }

        if let message = envelope.message, message.isEmpty == false {
            return message
        }
        if let error = envelope.error, error.isEmpty == false {
            return error
        }
        return nil
    }
}

private struct ErrorEnvelope: Decodable {
    let error: String?
    let message: String?
    let code: String?
}

/// Type erasure for encoding arbitrary payloads.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeFunc = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
