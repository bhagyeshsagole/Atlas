import Foundation

enum RoutineAIError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidURL
    case requestFailed(underlying: String)
    case httpStatus(Int, body: String?)
    case decodeFailed
    case emptyResponse
    case rateLimited
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Missing API key."
        case .invalidURL: return "Invalid request URL."
        case .requestFailed(let underlying): return underlying
        case .httpStatus(let code, _): return "Request failed (HTTP \(code))."
        case .decodeFailed: return "Could not parse the response."
        case .emptyResponse: return "Empty response."
        case .rateLimited: return "Rate limited."
        case .cancelled: return "Request cancelled."
        }
    }
}
