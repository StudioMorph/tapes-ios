import Foundation

struct APIErrorResponse: Decodable {
    let error: APIErrorBody
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
}

enum APIError: LocalizedError {
    case unauthorized
    case invalidCredentials
    case forbidden(String)
    case notFound(String)
    case expired(String)
    case tierRequired(String)
    case rateLimited(String)
    case validation(String)
    case musicAlreadySet
    case server(String)
    case network(Error)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please sign in again."
        case .invalidCredentials: return "Incorrect email or password."
        case .forbidden(let msg): return msg
        case .notFound(let msg): return msg
        case .expired(let msg): return msg
        case .tierRequired(let msg): return msg
        case .rateLimited(let msg): return msg
        case .validation(let msg): return msg
        case .musicAlreadySet: return "Background music for this tape is already set on the server."
        case .server(let msg): return msg
        case .network(let err): return "Network error: \(err.localizedDescription)"
        case .decodingFailed(let err): return "Failed to process response: \(err.localizedDescription)"
        }
    }

    var userMessage: String {
        errorDescription ?? "Something went wrong."
    }

    static func from(status: Int, body: Data) -> APIError {
        if let parsed = try? JSONDecoder().decode(APIErrorResponse.self, from: body) {
            let msg = parsed.error.message
            switch parsed.error.code {
            case "UNAUTHORIZED": return .unauthorized
            case "INVALID_CREDENTIALS": return .invalidCredentials
            case "FORBIDDEN": return .forbidden(msg)
            case "TAPE_NOT_FOUND", "CLIP_NOT_FOUND": return .notFound(msg)
            case "TAPE_EXPIRED": return .expired(msg)
            case "TIER_REQUIRED": return .tierRequired(msg)
            case "RATE_LIMITED": return .rateLimited(msg)
            case "VALIDATION_ERROR", "EMAIL_EXISTS", "INVALID_TOKEN", "TOKEN_EXPIRED": return .validation(msg)
            case "MUSIC_ALREADY_SET": return .musicAlreadySet
            default: return .server(msg)
            }
        }

        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden("Access denied.")
        case 404: return .notFound("Not found.")
        case 410: return .expired("This tape has expired.")
        case 429: return .rateLimited("Too many requests. Please try again later.")
        default: return .server("Something went wrong (HTTP \(status)).")
        }
    }
}
