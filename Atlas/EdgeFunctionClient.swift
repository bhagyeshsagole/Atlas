import Foundation
import Supabase

/// Supabase Edge Function client with shared Supabase instance, auth headers, and refresh-on-401.
enum EdgeFunctionClient {
    typealias Response = (Data, HTTPURLResponse)

    private static let projectRef = "nqaodudipodgtrnxcknv"
    private static let functionName = AIProxy.functionName

    #if DEBUG
    static var allowUnauthenticatedInDebug = false
    #endif

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseService.shared else {
            throw OpenAIError(statusCode: nil, message: "Supabase client unavailable.")
        }
        return client
    }

    private static func fetchAccessToken(requiresAuth: Bool) async throws -> (token: String?, userId: String?) {
        let client = try requireClient()
        do {
            let session = try await client.auth.session
            return (session.accessToken, session.user.id.uuidString)
        } catch {
            if let current = client.auth.currentSession {
                _ = try? await client.auth.refreshSession(refreshToken: current.refreshToken)
            }
            if let refreshed = try? await client.auth.session {
                return (refreshed.accessToken, refreshed.user.id.uuidString)
            }
            if requiresAuth {
                #if DEBUG
                if allowUnauthenticatedInDebug == false {
                    throw OpenAIError(statusCode: 401, message: "Session expired — sign in again.")
                }
                #else
                throw OpenAIError(statusCode: 401, message: "Session expired — sign in again.")
                #endif
            }
            let fallback = client.auth.currentSession
            return (fallback?.accessToken, fallback?.user.id.uuidString)
        }
    }

    private static func invokeFunction(
        path: String?,
        method: FunctionInvokeOptions.Method,
        body: Encodable?,
        requiresAuth: Bool
    ) async throws -> Response {
        let client = try requireClient()
        var headers: [String: String] = [:]
        if let anonKey = SupabaseConfig.anonKey {
            headers["apikey"] = anonKey
        }

        var lastError: OpenAIError?

        for attempt in 0...1 {
            let (token, userId) = try await fetchAccessToken(requiresAuth: requiresAuth)
            if let token, token.isEmpty == false {
                headers["Authorization"] = "Bearer \(token)"
            }

            let name = path.map { "\(functionName)/\($0)" } ?? functionName
            let options: FunctionInvokeOptions
            if let body {
                options = FunctionInvokeOptions(method: method, headers: headers, body: AnyEncodable(body))
            } else {
                options = FunctionInvokeOptions(method: method, headers: headers)
            }

            let requestId = UUID().uuidString.prefix(6)
            #if DEBUG
            let clientId = Unmanaged.passUnretained(client as AnyObject).toOpaque()
            print("[AI][EDGE][REQ \(requestId)] func=\(name) method=\(method.rawValue) auth=\(token?.isEmpty == false) user=\(userId ?? "nil") client=\(clientId)")
            #endif

            do {
                let response: Response = try await client.functions.invoke(
                    name,
                    options: options
                ) { data, response in
                    (data, response)
                }
                #if DEBUG
                print("[AI][EDGE][RES \(requestId)] status=\(response.1.statusCode)")
                #endif
                return response
            } catch let error as FunctionsError {
                switch error {
                case let .httpError(code, data):
                    let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
                    #if DEBUG
                    print("[AI][EDGE][RES \(requestId)] status=\(code) body=\(snippet)")
                    #endif
                    if code == 401 && attempt == 0 {
                        _ = try? await client.auth.refreshSession()
                        continue
                    }
                    if code == 401 {
                        lastError = OpenAIError(statusCode: code, message: "AI locked behind sign-in. Please sign in again.")
                    } else if code == 403 {
                        lastError = OpenAIError(statusCode: code, message: "AI blocked by server policy. \(snippet)")
                    } else {
                        lastError = OpenAIError(statusCode: code, message: snippet.isEmpty ? "HTTP \(code)" : String(snippet))
                    }
                case .relayError:
                    lastError = OpenAIError(statusCode: nil, message: "Edge relay error.")
                }
            } catch {
                lastError = OpenAIError(statusCode: nil, message: error.localizedDescription)
            }
        }

        throw lastError ?? OpenAIError(statusCode: nil, message: "Unknown error.")
    }

    static func callChat(payload: Encodable) async throws -> Response {
        try await invokeFunction(path: "chat", method: .post, body: payload, requiresAuth: true)
    }

    static func checkHealth() async throws -> Response {
        try await invokeFunction(path: "health", method: .get, body: nil, requiresAuth: true)
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
